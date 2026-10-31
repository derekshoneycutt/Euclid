package content

import reader "../../persistence/content"

import contentdata "../../core/content"

import "core:sync/chan"
import "core:log"

// Coalesced query plus an optional first control request that followed it.
Search_Coalesced_Request :: struct {
    query: Content_Worker_Request,
    pending: Content_Worker_Request,
    has_pending: bool,
}

// Drain queued requests and retain shutdown or the newest query generation.
search_worker_coalesce :: proc(
    service: ^Content_Service,
    first: Content_Worker_Request) -> Search_Coalesced_Request {
    result: Search_Coalesced_Request = {
        query = first,
    }
    for {
        candidate, available := chan.try_recv(service.requests)
        if !available {
            return result
        }
        if candidate.kind != .Query {
            result.pending = candidate
            result.has_pending = true
            return result
        }
        if candidate.query.generation >= result.query.query.generation {
            result.query = candidate
        }
    }
}

// Publish one worker control result after a staged-catalogue operation.
content_worker_control_result :: proc(
    service: ^Content_Service, status: Search_Query_Status,
    generation: u64) {
    _ = chan.send(service.control_results, Content_Control_Result{
        status = status,
        index_generation = generation,
    })
}

// Stage one immutable candidate while preserving the active query connection.
content_worker_stage :: proc(
    service: ^Content_Service, staged: ^reader.Content_Database,
    request: ^Content_Worker_Request) {
    if !reader.content_database_close(staged) {
        log.error("content_stage_close_failed")
        content_worker_control_result(service, .Unavailable, 0)
        return
    }
    _ = contentdata.content_generation_reset(service.staged_generation)
    path := string(request.database_path[:request.database_path_length])
    fingerprint := string(request.expected_fingerprint[:])
    if reader.content_database_open(
        staged, path, fingerprint, service.staged_generation) &&
        staged.index_generation == service.staged_generation^.generation {
        content_worker_control_result(
            service, .Candidate_Ready, staged.index_generation)
        return
    }
    content_worker_control_result(service, .Unavailable, 0)
}

// Promote one admitted candidate and retire the previous active connection.
content_worker_commit :: proc(
    service: ^Content_Service, active, staged: ^reader.Content_Database) -> bool {
    if !reader.content_database_ready(staged) || service.active_generation == nil ||
       service.staged_generation == nil ||
       !service.staged_generation^.sealed || !service.staged_generation^.data.complete ||
       active.index_generation != service.active_generation^.generation ||
       staged.index_generation != service.staged_generation^.generation {
        content_worker_control_result(service, .Unavailable, 0)
        return false
    }
    previous := active^
    active^ = staged^
    staged^ = previous
    generation := active.index_generation
    content_worker_control_result(service, .Candidate_Committed, generation)
    return true
}

// Retire or roll back one candidate and preserve the prior active connection.
content_worker_discard :: proc(
    service: ^Content_Service, active, staged: ^reader.Content_Database,
    committed: bool) {
    if committed {
        active^, staged^ = staged^, active^
    }
    closed := reader.content_database_close(staged)
    if !closed {
        log.error("content_discard_close_failed")
    }
    _ = chan.send(service.control_results, Content_Control_Result{
        status = .Candidate_Discarded,
        cleanup_failed = !closed,
    })
}

// Retire the previous active connection after the outer transaction publishes.
content_worker_finalize :: proc(
    service: ^Content_Service, staged: ^reader.Content_Database) -> bool {
    closed := reader.content_database_close(staged)
    if !closed {
        log.error("content_finalize_close_failed")
    }
    status := closed ? Search_Query_Status.Candidate_Finalized : .Unavailable
    content_worker_control_result(service, status, 0)
    return closed
}

// Dispatch one non-query command and report whether the owner loop should stop.
content_worker_dispatch_control :: proc(
    service: ^Content_Service, active, staged: ^reader.Content_Database,
    request: ^Content_Worker_Request,
    candidate_committed: ^bool) -> (bool, bool) {
    if request.kind == .Query {
        return false, false
    }
    if request.kind == .Shutdown {
        _ = chan.send(service.results, Search_Query_Result{
            status = .Stopped,
        })
        return true, true
    }
    if request.kind == .Stage {
        content_worker_stage(service, staged, request)
    } else if request.kind == .Commit {
        candidate_committed^ = content_worker_commit(service, active, staged)
    } else if request.kind == .Discard {
        content_worker_discard(
            service, active, staged, candidate_committed^)
        candidate_committed^ = false
    } else if request.kind == .Finalize {
        if content_worker_finalize(service, staged) {
            candidate_committed^ = false
        }
    }
    return true, false
}

// Consume a retained control before receiving later requests from the channel.
content_worker_next_request :: proc(
    service: ^Content_Service,
    coalesced: ^Search_Coalesced_Request) -> (Content_Worker_Request, bool) {
    if coalesced.has_pending {
        coalesced.has_pending = false
        return coalesced.pending, true
    }
    return chan.recv(service.requests)
}

// Run the SQLite owner loop, coalescing adjacent queries without crossing controls.
content_worker_run :: proc(
    service: ^Content_Service, database: ^reader.Content_Database) {
    staged: reader.Content_Database
    coalesced: Search_Coalesced_Request
    candidate_committed := false
    defer {
        if !reader.content_database_close(&staged) {
            log.error("content_shutdown_candidate_close_failed")
        }
    }
    for {
        defer free_all(context.temp_allocator)
        request, received := content_worker_next_request(service, &coalesced)
        if !received {
            return
        }
        handled, stop := content_worker_dispatch_control(
            service, database, &staged, &request, &candidate_committed)
        if stop {
            return
        }
        if handled {
            continue
        }
        coalesced = search_worker_coalesce(service, request)
        content_worker_execute_query(service, database, coalesced.query.query)
    }
}

// Execute and publish a pointer-free result within the owning request's scratch lifetime.
content_worker_execute_query :: proc(
    service: ^Content_Service, database: ^reader.Content_Database,
    query: Search_Query_Request) {
    execution := reader.content_database_execute(database, query)
    if !execution.ok {
        execution.result.status = .Query_Failed
    }
    _ = chan.try_send(service.results, execution.result)
}

// Own SQLite from open through finalization on the dedicated worker thread.
content_worker_entry :: proc(data: rawptr) {
    defer free_all(context.temp_allocator)
    service := cast(^Content_Service)data
    path := string(service.database_path[:service.database_path_length])
    fingerprint := string(service.expected_fingerprint[:])
    database: reader.Content_Database
    ready := reader.content_database_open(
        &database, path, fingerprint, service.active_generation) &&
        service.active_generation^.sealed && service.active_generation^.data.complete &&
        database.index_generation == service.active_generation^.generation
    status := ready ? Search_Query_Status.Ready : .Unavailable
    _ = chan.send(service.results, Search_Query_Result{
        status = status,
        index_generation = database.index_generation,
    })
    free_all(context.temp_allocator)
    if ready {
        content_worker_run(service, &database)
    }
    if !reader.content_database_close(&database) {
        log.error("content_shutdown_active_close_failed")
    }
}
