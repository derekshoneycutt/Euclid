package catalog

import catalogdata "../../core/catalog"

import "core:sync/chan"

// Coalesced query plus an optional first control request that followed it.
Search_Coalesced_Request :: struct {
    query: Search_Worker_Request,
    pending: Search_Worker_Request,
    has_pending: bool,
}

// Drain queued requests and retain shutdown or the newest query generation.
search_worker_coalesce :: proc(
    service: ^Catalog_Service,
    first: Search_Worker_Request) -> Search_Coalesced_Request {
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
catalog_worker_control_result :: proc(
    service: ^Catalog_Service, status: Search_Query_Status,
    generation: u64) {
    _ = chan.send(service.control_results, Catalog_Control_Result{
        status = status,
        index_generation = generation,
    })
}

// Stage one immutable candidate while preserving the active query connection.
catalog_worker_stage :: proc(
    service: ^Catalog_Service, staged: ^Catalog_Database,
    request: ^Search_Worker_Request) {
    _ = catalog_database_close(staged)
    _ = catalogdata.catalog_generation_reset(service.staged_generation)
    path := string(request.database_path[:request.database_path_length])
    fingerprint := string(request.expected_fingerprint[:])
     if catalog_database_open(staged, path, fingerprint, service.staged_generation) &&
         staged.index_generation == service.staged_generation^.generation {
        catalog_worker_control_result(
            service, .Candidate_Ready, staged.index_generation)
        return
    }
    catalog_worker_control_result(service, .Unavailable, 0)
}

// Promote one admitted candidate and retire the previous active connection.
catalog_worker_commit :: proc(
    service: ^Catalog_Service, active, staged: ^Catalog_Database) -> bool {
    if staged.connection.handle == nil || service.active_generation == nil ||
       service.staged_generation == nil ||
       active.index_generation != service.active_generation^.generation ||
       staged.index_generation != service.staged_generation^.generation {
        catalog_worker_control_result(service, .Unavailable, 0)
        return false
    }
    previous := active^
    active^ = staged^
    staged^ = previous
    generation := active.index_generation
    catalog_worker_control_result(service, .Candidate_Committed, generation)
    return true
}

// Retire or roll back one candidate and preserve the prior active connection.
catalog_worker_discard :: proc(
    service: ^Catalog_Service, active, staged: ^Catalog_Database,
    committed: bool) {
    if committed {
        active^, staged^ = staged^, active^
    }
    _ = catalog_database_close(staged)
    catalog_worker_control_result(service, .Candidate_Discarded, 0)
}

// Retire the previous active connection after the outer transaction publishes.
catalog_worker_finalize :: proc(
    service: ^Catalog_Service, staged: ^Catalog_Database) {
    _ = catalog_database_close(staged)
    catalog_worker_control_result(service, .Candidate_Finalized, 0)
}

// Dispatch one non-query command and report whether the owner loop should stop.
catalog_worker_dispatch_control :: proc(
    service: ^Catalog_Service, active, staged: ^Catalog_Database,
    request: ^Search_Worker_Request,
    candidate_committed: ^bool) -> (bool, bool) {
    if request.kind == .Query {
        return false, false
    }
    if request.kind == .Shutdown {
        _ = chan.send(service.results, Search_Query_Result{status = .Stopped})
        return true, true
    }
    if request.kind == .Stage {
        catalog_worker_stage(service, staged, request)
    } else if request.kind == .Commit {
        candidate_committed^ = catalog_worker_commit(service, active, staged)
    } else if request.kind == .Discard {
        catalog_worker_discard(
            service, active, staged, candidate_committed^)
        candidate_committed^ = false
    } else if request.kind == .Finalize {
        catalog_worker_finalize(service, staged)
        candidate_committed^ = false
    }
    return true, false
}

// Run the SQLite owner loop, coalescing adjacent queries without crossing controls.
search_worker_run :: proc(service: ^Catalog_Service, database: ^Catalog_Database) {
    staged: Catalog_Database
    pending: Search_Worker_Request
    has_pending := false
    candidate_committed := false
    defer _ = catalog_database_close(&staged)
    for {
        request: Search_Worker_Request
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
        handled, stop := catalog_worker_dispatch_control(
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
        execution := catalog_database_execute(database, coalesced.query.query)
        if !execution.ok {
            execution.result.status = .Query_Failed
        }
        _ = chan.try_send(service.results, execution.result)
        free_all(context.temp_allocator)
    }
}

// Own SQLite from open through finalization on the dedicated worker thread.
search_worker_entry :: proc(data: rawptr) {
    service := cast(^Catalog_Service)data
    path := string(service.database_path[:service.database_path_length])
    fingerprint := string(service.expected_fingerprint[:])
    database: Catalog_Database
    ready := catalog_database_open(
        &database, path, fingerprint, service.active_generation) &&
        database.index_generation == service.active_generation^.generation
    status := ready ? Search_Query_Status.Ready : .Unavailable
    _ = chan.send(service.results, Search_Query_Result{
        status = status, index_generation = database.index_generation})
    if ready {
        search_worker_run(service, &database)
    }
    _ = catalog_database_close(&database)
}
