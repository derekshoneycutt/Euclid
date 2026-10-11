package content

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
    result := Search_Coalesced_Request{query = first}
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
    service: ^Content_Service, staged: ^Content_Database,
    request: ^Content_Worker_Request) {
    if !content_database_close(staged) {
        log.error("content_stage_close_failed")
        content_worker_control_result(service, .Unavailable, 0)
        return
    }
    _ = contentdata.content_generation_reset(service.staged_generation)
    path := string(request.database_path[:request.database_path_length])
    fingerprint := string(request.expected_fingerprint[:])
    if content_database_open(staged, path, fingerprint, service.staged_generation) &&
         staged.index_generation == service.staged_generation^.generation {
        content_worker_control_result(
            service, .Candidate_Ready, staged.index_generation)
        return
    }
    content_worker_control_result(service, .Unavailable, 0)
}

// Promote one admitted candidate and retire the previous active connection.
content_worker_commit :: proc(
    service: ^Content_Service, active, staged: ^Content_Database) -> bool {
    if staged.connection.handle == nil || service.active_generation == nil ||
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
    service: ^Content_Service, active, staged: ^Content_Database,
    committed: bool) {
    if committed {
        active^, staged^ = staged^, active^
    }
    closed := content_database_close(staged)
    if !closed {
        log.error("content_discard_close_failed")
    }
    _ = chan.send(service.control_results, Content_Control_Result{
        status = .Candidate_Discarded, cleanup_failed = !closed})
}

// Retire the previous active connection after the outer transaction publishes.
content_worker_finalize :: proc(
    service: ^Content_Service, staged: ^Content_Database) -> bool {
    closed := content_database_close(staged)
    if !closed {
        log.error("content_finalize_close_failed")
    }
    status := closed ? Search_Query_Status.Candidate_Finalized : .Unavailable
    content_worker_control_result(service, status, 0)
    return closed
}

// Dispatch one non-query command and report whether the owner loop should stop.
content_worker_dispatch_control :: proc(
    service: ^Content_Service, active, staged: ^Content_Database,
    request: ^Content_Worker_Request,
    candidate_committed: ^bool) -> (bool, bool) {
    if request.kind == .Query {
        return false, false
    }
    if request.kind == .Shutdown {
        _ = chan.send(service.results, Search_Query_Result{status = .Stopped})
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

// Run the SQLite owner loop, coalescing adjacent queries without crossing controls.
content_worker_run :: proc(service: ^Content_Service, database: ^Content_Database) {
    staged: Content_Database
    pending: Content_Worker_Request
    has_pending := false
    candidate_committed := false
    defer {
        if !content_database_close(&staged) {
            log.error("content_shutdown_candidate_close_failed")
        }
    }
    for {
        request: Content_Worker_Request
        if has_pending {
            request = pending
            has_pending = false
        } else {
            received: bool
            request, received = chan.recv(service.requests)
            if !received {
                return
            }
        }
        handled, stop := content_worker_dispatch_control(
            service, database, &staged, &request, &candidate_committed)
        if stop {
            return
        }
        if handled {
            continue
        }
        coalesced := search_worker_coalesce(service, request)
        pending = coalesced.pending
        has_pending = coalesced.has_pending
        content_worker_execute_query(service, database, coalesced.query.query)
    }
}

// Execute and publish a bounded result before retiring query-local temporary storage.
content_worker_execute_query :: proc(
    service: ^Content_Service, database: ^Content_Database,
    query: Search_Query_Request) {
    execution := content_database_execute(database, query)
    if !execution.ok {
        execution.result.status = .Query_Failed
    }
    _ = chan.try_send(service.results, execution.result)
    free_all(context.temp_allocator)
}

// Own SQLite from open through finalization on the dedicated worker thread.
content_worker_entry :: proc(data: rawptr) {
    service := cast(^Content_Service)data
    path := string(service.database_path[:service.database_path_length])
    fingerprint := string(service.expected_fingerprint[:])
    database: Content_Database
    ready := content_database_open(
        &database, path, fingerprint, service.active_generation) &&
        service.active_generation^.sealed && service.active_generation^.data.complete &&
        database.index_generation == service.active_generation^.generation
    status := ready ? Search_Query_Status.Ready : .Unavailable
    _ = chan.send(service.results, Search_Query_Result{
        status = status, index_generation = database.index_generation})
    if ready {
        content_worker_run(service, &database)
    }
    if !content_database_close(&database) {
        log.error("content_shutdown_active_close_failed")
    }
}
