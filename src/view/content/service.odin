package content

import contentdata "../../core/content"

import "core:mem"
import tlsf "core:mem/tlsf"
import vmem "core:mem/virtual"
import "core:sync/chan"
import "core:thread"

CONTENT_WORKER_CHANNEL_CAPACITY :: 8
CONTENT_SERVICE_EXTRA_ALLOCATOR_CAPACITY :: 64 * 1024
CONTENT_SERVICE_ALLOCATOR_CAPACITY :: size_of(Content_Generation) * 2 +
    CONTENT_WORKER_CHANNEL_CAPACITY *
        (size_of(Content_Worker_Request) + size_of(Search_Query_Result) +
            size_of(Content_Control_Result)) +
    CONTENT_SERVICE_EXTRA_ALLOCATOR_CAPACITY

// Release dedicated service storage after every channel and generation borrower stops.
content_service_release_allocator :: proc(service: ^Content_Service) {
    if service.active_generation != nil {
        contentdata.content_generation_destroy(service.active_generation)
        free(service.active_generation,
            mem.mutex_allocator(&service.synchronized_allocator))
        service.active_generation = nil
    }
    if service.staged_generation != nil {
        contentdata.content_generation_destroy(service.staged_generation)
        free(service.staged_generation,
            mem.mutex_allocator(&service.synchronized_allocator))
        service.staged_generation = nil
    }
    tlsf.destroy(&service.allocator_state)
    if service.backing != nil {
        vmem.release(raw_data(service.backing), uint(len(service.backing)))
    }
    service.backing = nil
}

// Allocate and initialize the active and staged generation slots in service storage.
content_service_init_generations :: proc(
    service: ^Content_Service, allocator: mem.Allocator) -> bool {
    service.active_generation = new(Content_Generation, allocator)
    if service.active_generation == nil {
        return false
    }
    if contentdata.content_generation_init(service.active_generation) != .Ok {
        return false
    }
    service.staged_generation = new(Content_Generation, allocator)
    if service.staged_generation == nil {
        return false
    }
    return contentdata.content_generation_init(service.staged_generation) == .Ok
}

// Allocate bounded request, query-result, and control-result channels.
content_service_init_channels :: proc(
    service: ^Content_Service, allocator: mem.Allocator) -> bool {
    requests, request_error := chan.create(
        chan.Chan(Content_Worker_Request), CONTENT_WORKER_CHANNEL_CAPACITY, allocator)
    if request_error != .None {
        return false
    }
    service.requests = requests
    results, result_error := chan.create(
        chan.Chan(Search_Query_Result), CONTENT_WORKER_CHANNEL_CAPACITY, allocator)
    if result_error != .None {
        _ = chan.destroy(service.requests)
        return false
    }
    service.results = results
    controls, control_error := chan.create(
        chan.Chan(Content_Control_Result), CONTENT_WORKER_CHANNEL_CAPACITY, allocator)
    if control_error == .None {
        service.control_results = controls
        return true
    }
    _ = chan.destroy(service.results)
    _ = chan.destroy(service.requests)
    return false
}

// Initialize fixed service storage, both generations, and bounded channels.
content_service_init_storage :: proc(service: ^Content_Service) -> bool {
    backing, backing_error := vmem.reserve_and_commit(CONTENT_SERVICE_ALLOCATOR_CAPACITY)
    if backing_error != nil {
        return false
    }
    service.backing = backing
    if tlsf.init_from_buffer(&service.allocator_state, backing) != .None {
        content_service_release_allocator(service)
        return false
    }
    mem.mutex_allocator_init(
        &service.synchronized_allocator, tlsf.allocator(&service.allocator_state))
    allocator := mem.mutex_allocator(&service.synchronized_allocator)
    if !content_service_init_generations(service, allocator) ||
       !content_service_init_channels(service, allocator) {
        content_service_release_allocator(service)
        return false
    }
    return true
}

// Start the owner thread with the service allocator inherited in its context.
content_service_start_worker :: proc(service: ^Content_Service) -> bool {
    saved_context := context
    context.allocator = mem.mutex_allocator(&service.synchronized_allocator)
    service.worker = thread.create_and_start_with_data(
        rawptr(service), content_worker_entry)
    context = saved_context
    return service.worker != nil
}

// Join a failed startup and release all service-owned storage.
content_service_rollback_start :: proc(service: ^Content_Service) {
    if service.worker != nil {
        thread.destroy(service.worker)
    }
    _ = chan.destroy(service.control_results)
    _ = chan.destroy(service.results)
    _ = chan.destroy(service.requests)
    content_service_release_allocator(service)
    service^ = {}
}

// Start one worker and synchronously require validated database readiness.
content_service_init :: proc(
    service: ^Content_Service, database_path,
    expected_fingerprint: string) -> bool {
    if service == nil || service.running || len(database_path) == 0 ||
       len(database_path) > len(service.database_path) ||
       len(expected_fingerprint) != SEARCH_FINGERPRINT_BYTE_COUNT {
        return false
    }
    service^ = {}
    copy(service.database_path[:], transmute([]u8)database_path)
    service.database_path_length = u16(len(database_path))
    copy(service.expected_fingerprint[:], transmute([]u8)expected_fingerprint)
    if !content_service_init_storage(service) {
        service^ = {}
        return false
    }
    if !content_service_start_worker(service) {
        content_service_rollback_start(service)
        return false
    }
    readiness, received := chan.recv(service.results)
    if !received || readiness.status != .Ready ||
       !service.active_generation^.sealed || !service.active_generation^.data.complete ||
       service.active_generation^.generation != readiness.index_generation {
        content_service_rollback_start(service)
        return false
    }
    service.index_generation = readiness.index_generation
    service.running = true
    return true
}

// Allocate and start one service at an address stable for its worker lifetime.
content_service_create :: proc(
    database_path, expected_fingerprint: string) -> ^Content_Service {
    storage, storage_error := vmem.reserve_and_commit(size_of(Content_Service))
    if storage_error != nil {
        return nil
    }
    service := cast(^Content_Service)raw_data(storage)
    service^ = {}
    if content_service_init(service, database_path, expected_fingerprint) {
        return service
    }
    vmem.release(rawptr(service), size_of(Content_Service))
    return nil
}

// Try to submit one query without blocking the display owner.
content_service_try_submit :: proc(
    service: ^Content_Service, request: Search_Query_Request) -> bool {
    return service != nil && service.running && chan.try_send(
        service.requests, Content_Worker_Request{kind = .Query, query = request})
}

// Try to receive one worker result without blocking the display owner.
content_service_try_receive :: proc(
    service: ^Content_Service) -> (Search_Query_Result, bool) {
    if service == nil || !service.running {
        return {}, false
    }
    return chan.try_recv(service.results)
}

// Build one bounded worker request for a candidate immutable database.
content_stage_request_make :: proc(
    database_path, expected_fingerprint: string) -> (Content_Worker_Request, bool) {
    if len(database_path) == 0 || len(database_path) > CATALOG_DATABASE_PATH_CAPACITY ||
       len(expected_fingerprint) != SEARCH_FINGERPRINT_BYTE_COUNT {
        return {}, false
    }
    request := Content_Worker_Request{
        kind = .Stage,
        database_path_length = u16(len(database_path)),
    }
    copy(request.database_path[:], transmute([]u8)database_path)
    copy(request.expected_fingerprint[:], transmute([]u8)expected_fingerprint)
    return request, true
}

// Stage and validate one candidate without replacing the active catalogue.
content_service_stage :: proc(
    service: ^Content_Service, database_path,
    expected_fingerprint: string) -> bool {
    if service == nil || !service.running || service.candidate_state != .None {
        return false
    }
    request, valid := content_stage_request_make(database_path, expected_fingerprint)
    if !valid || !chan.send(service.requests, request) {
        return false
    }
    result, received := chan.recv(service.control_results)
    if !received || result.status != .Candidate_Ready ||
       !service.staged_generation^.sealed || !service.staged_generation^.data.complete ||
       service.staged_generation^.generation != result.index_generation {
        return false
    }
    service.candidate_state = .Staged
    return true
}

// Return the sealed candidate generation only after staged admission succeeds.
content_service_staged_generation :: proc(
    service: ^Content_Service) -> ^Content_Generation {
    if service == nil || !service.running || service.staged_generation == nil ||
       service.candidate_state != .Staged || !service.staged_generation^.sealed ||
       !service.staged_generation^.data.complete ||
       service.staged_generation^.generation == 0 {
        return nil
    }
    return service.staged_generation
}

// Promote one admitted candidate and advance index and generation identities together.
content_service_commit :: proc(service: ^Content_Service) -> bool {
    if service == nil || !service.running || service.candidate_state != .Staged ||
       service.staged_generation == nil || service.staged_generation^.generation == 0 ||
       !service.staged_generation^.sealed || !service.staged_generation^.data.complete ||
       !chan.send(service.requests, Content_Worker_Request{kind = .Commit}) {
        return false
    }
    result, received := chan.recv(service.control_results)
    if !received || result.status != .Candidate_Committed ||
       result.index_generation != service.staged_generation^.generation {
        return false
    }
    service.active_generation, service.staged_generation =
        service.staged_generation, service.active_generation
    service.index_generation = result.index_generation
    service.candidate_state = .Committed
    return true
}

// Discard or reverse one candidate while preserving the prior active generation.
content_service_discard :: proc(service: ^Content_Service) -> bool {
    if service == nil || !service.running ||
       !chan.send(service.requests, Content_Worker_Request{kind = .Discard}) {
        return false
    }
    result, received := chan.recv(service.control_results)
    if !received || result.status != .Candidate_Discarded {
        return false
    }
    if service.candidate_state == .Committed {
        service.active_generation, service.staged_generation =
            service.staged_generation, service.active_generation
        service.index_generation = service.active_generation^.generation
    }
    if service.active_generation^.generation != service.index_generation ||
       contentdata.content_generation_reset(service.staged_generation) != .Ok {
        return false
    }
    service.candidate_state = .None
    return !result.cleanup_failed
}

// Retire the previous connection after all outer reload publications succeed.
content_service_finalize :: proc(service: ^Content_Service) -> bool {
    if service == nil || !service.running ||
       service.candidate_state != .Committed ||
       !chan.send(service.requests, Content_Worker_Request{kind = .Finalize}) {
        return false
    }
    result, received := chan.recv(service.control_results)
    if !received || result.status != .Candidate_Finalized ||
       service.active_generation^.generation != service.index_generation ||
       contentdata.content_generation_reset(service.staged_generation) != .Ok {
        return false
    }
    service.candidate_state = .None
    return true
}

// Return the immutable index generation validated during worker startup.
content_service_index_generation :: proc(service: ^Content_Service) -> u64 {
    if service == nil || !service.running {
        return 0
    }
    return service.index_generation
}

// Return the active sealed generation only while its identity matches the index.
content_service_generation :: proc(
    service: ^Content_Service) -> ^Content_Generation {
    if service == nil || !service.running || service.active_generation == nil ||
       !service.active_generation^.sealed || !service.active_generation^.data.complete ||
       service.active_generation^.generation != service.index_generation {
        return nil
    }
    return service.active_generation
}

// Stop, join, and release one worker before its owning allocator is destroyed.
content_service_destroy :: proc(service: ^Content_Service) {
    if service == nil {
        return
    }
    if service.running {
        _ = chan.send(service.requests, Content_Worker_Request{kind = .Shutdown})
        for {
            result, received := chan.recv(service.results)
            if !received || result.status == .Stopped {
                break
            }
        }
        service.running = false
    }
    if service.worker != nil {
        thread.destroy(service.worker)
    }
    if service.backing != nil {
        _ = chan.destroy(service.control_results)
        _ = chan.destroy(service.results)
        _ = chan.destroy(service.requests)
        content_service_release_allocator(service)
    }
    service^ = {}
}

// Stop and release one service created with content_service_create.
content_service_destroy_owned :: proc(service: ^Content_Service) {
    if service == nil {
        return
    }
    content_service_destroy(service)
    vmem.release(rawptr(service), size_of(Content_Service))
}

// Copy one bounded query into a pointer-free request value.
search_query_request_make :: proc(
    generation: u64, offset: u32, source: string) -> (Search_Query_Request, bool) {
    if len(source) > SEARCH_QUERY_BYTE_CAPACITY {
        return {}, false
    }
    request := Search_Query_Request{generation = generation, result_offset = offset,
        query_length = u16(len(source))}
    copy(request.query_bytes[:], transmute([]u8)source)
    return request, true
}