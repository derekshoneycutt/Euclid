#+test
package content

import contentfixture "../../persistence/content/testsupport"

import "base:runtime"
import "core:mem"
import "core:os"
import "core:sync/chan"
import "core:testing"

// Test-owned scratch records pressure at real worker reset boundaries.
Content_Test_Scratch :: struct {
    temporary: runtime.Default_Temp_Allocator,
    before: [16]uint,
    after: [16]uint,
    reset_count: int,
}

// Forward allocations while recording each whole-arena reset on the executing thread.
content_test_scratch_allocator :: proc(
    data: rawptr, mode: mem.Allocator_Mode,
    size, alignment: int, old_memory: rawptr, old_size: int,
    location: runtime.Source_Code_Location = #caller_location) ->
        ([]byte, mem.Allocator_Error) {
    scratch := (^Content_Test_Scratch)(data)
    index := scratch.reset_count
    if mode == .Free_All {
        assert(index < len(scratch.before))
        scratch.before[index] = scratch.temporary.arena.total_used
    }
    result, err := runtime.default_temp_allocator_proc(
        &scratch.temporary, mode, size, alignment, old_memory, old_size, location)
    if mode == .Free_All {
        scratch.after[index] = scratch.temporary.arena.total_used
        scratch.reset_count += 1
    }
    return result, err
}

// Run the actual owner entry with isolated scratch, never resetting fixture memory.
content_test_run_with_scratch :: proc(
    service: ^Content_Service, scratch: ^Content_Test_Scratch) {
    saved_context := context
    defer context = saved_context
    defer runtime.default_temp_allocator_destroy(&scratch.temporary)
    context.temp_allocator = {
        procedure = content_test_scratch_allocator,
        data = scratch,
    }
    content_worker_entry(service)
}

// Prepare channels and owned generations without starting a concurrent worker.
content_test_init_scratch_service :: proc(
    service: ^Content_Service, path, fingerprint: string) -> bool {
    copy(service.database_path[:], transmute([]u8)path)
    service.database_path_length = u16(len(path))
    copy(service.expected_fingerprint[:], transmute([]u8)fingerprint)
    return content_service_init_storage(service)
}

// Queue controls without queries between stages, followed by one query and shutdown.
content_test_queue_scratch_requests :: proc(
    t: ^testing.T, service: ^Content_Service, path: string) {
    failed, failed_valid := content_stage_request_make(
        path, contentfixture.SEARCH_TEST_CANDIDATE_FINGERPRINT)
    stage, valid := content_stage_request_make(
        path, contentfixture.SEARCH_TEST_FINGERPRINT)
    query, query_valid := search_query_request_make(1, 0, "perpendicular")
    testing.expect(t, failed_valid && valid && query_valid)
    requests: [8]Content_Worker_Request = {
        failed,
        stage,
        {
            kind = .Discard,
        },
        stage,
        {
            kind = .Commit,
        },
        {
            kind = .Finalize,
        },
        {
            kind = .Query,
            query = query,
        },
        {
            kind = .Shutdown,
        },
    }
    for request in requests {
        testing.expect(t, chan.try_send(service.requests, request))
    }
}

// Verify startup and control-only workloads reclaim scratch before the next request.
@(test)
content_worker_reclaims_startup_and_request_scratch :: proc(t: ^testing.T) {
    fixture := contentfixture.search_test_database_create("scratch-requests")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    service: Content_Service
    initialized := content_test_init_scratch_service(
        &service, fixture.path, contentfixture.SEARCH_TEST_FINGERPRINT)
    testing.expect(t, initialized)
    if !initialized {
        return
    }
    defer content_service_destroy(&service)
    content_test_queue_scratch_requests(t, &service, fixture.path)
    scratch: Content_Test_Scratch
    content_test_run_with_scratch(&service, &scratch)
    testing.expect_value(t, scratch.reset_count, 10)
    for used in scratch.after[:scratch.reset_count] {
        testing.expect_value(t, used, uint(0))
    }
    for index in ([4]int{0, 1, 2, 4}) {
        testing.expect(t, scratch.before[index] > 0)
    }
    for index in ([6]int{3, 5, 6, 7, 8, 9}) {
        testing.expect_value(t, scratch.before[index], uint(0))
    }
    content_test_check_scratch_results(t, &service)
}

// Check queued values after all scratch resets and database finalization have completed.
content_test_check_scratch_results :: proc(t: ^testing.T, service: ^Content_Service) {
    controls: [6]Search_Query_Status = {
        .Unavailable, .Candidate_Ready, .Candidate_Discarded,
        .Candidate_Ready, .Candidate_Committed, .Candidate_Finalized,
    }
    for expected in controls {
        result, received := chan.try_recv(service.control_results)
        testing.expect(t, received)
        testing.expect_value(t, result.status, expected)
        testing.expect(t, !result.cleanup_failed)
    }
    ready, received_ready := chan.try_recv(service.results)
    query, received_query := chan.try_recv(service.results)
    stopped, received_stopped := chan.try_recv(service.results)
    testing.expect(t, received_ready && received_query && received_stopped)
    testing.expect_value(t, ready.status, Search_Query_Status.Ready)
    testing.expect_value(t, query.status, Search_Query_Status.Ready)
    testing.expect_value(t, query.generation, u64(1))
    testing.expect(t, query.returned_count > 0)
    testing.expect_value(t, string(query.document_keys[0].document_id.bytes[:]),
        "00000000-0000-0000-0000-000000000001")
    testing.expect_value(t, stopped.status, Search_Query_Status.Stopped)
    testing.expect(t, service.active_generation^.sealed &&
        service.active_generation^.data.complete)
}

// Verify failed startup releases admission scratch without waiting for a first query.
@(test)
content_worker_reclaims_failed_startup_scratch :: proc(t: ^testing.T) {
    fixture := contentfixture.search_test_database_create("scratch-failed-startup")
    defer delete(fixture.directory)
    defer delete(fixture.path)
    defer _ = os.remove_all(fixture.directory)
    testing.expect(t, fixture.ok)
    service: Content_Service
    initialized := content_test_init_scratch_service(
        &service, fixture.path, contentfixture.SEARCH_TEST_CANDIDATE_FINGERPRINT)
    testing.expect(t, initialized)
    if !initialized {
        return
    }
    defer content_service_destroy(&service)
    scratch: Content_Test_Scratch
    content_test_run_with_scratch(&service, &scratch)
    testing.expect_value(t, scratch.reset_count, 2)
    testing.expect(t, scratch.before[0] > 0)
    testing.expect_value(t, scratch.before[1], uint(0))
    testing.expect_value(t, scratch.after[0], uint(0))
    testing.expect_value(t, scratch.after[1], uint(0))
    readiness, received := chan.try_recv(service.results)
    testing.expect(t, received)
    testing.expect_value(t, readiness.status, Search_Query_Status.Unavailable)
}
