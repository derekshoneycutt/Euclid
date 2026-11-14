package view

import bridgemodel "../bridge/model"
import contentdata "../core/content"

import "core:testing"
import "core:sync/chan"

// Drain an abandoned load before submitting its successor, keeping reply pressure bounded.
@(test)
exercise_query_drains_superseded_worker_results :: proc(t: ^testing.T) {
    fixture := julia_egress_router_test_context_create()
    defer julia_egress_router_test_context_destroy(fixture)
    service := new(contentdata.Content_Service, context.allocator)
    defer free(service, context.allocator)
    service.running = true
    requests, request_error := chan.create(
        chan.Chan(contentdata.Content_Worker_Request), 8, context.allocator)
    results, result_error := chan.create(
        chan.Chan(contentdata.Exercise_Query_Result), 2, context.allocator)
    service.requests, service.exercise_results = requests, results
    testing.expect(t, request_error == .None && result_error == .None)
    defer _ = chan.destroy(service.requests)
    defer _ = chan.destroy(service.exercise_results)
    fixture.state.content_service = service
    operation := exercise_query_test_pending(fixture)
    operation.intent.token = 2
    operation.intent.query.generation = 2
    operation.state = .Admitted
    operation.inflight_token = 1
    testing.expect(t,
        chan.try_send(service.exercise_results, exercise_query_test_read(1)))
    service_exercise_queries(fixture.state)
    testing.expect(t, !fixture.state.exercise_header.visible)
    testing.expect_value(t, operation.inflight_token, u64(2))
    testing.expect_value(t, operation.state, bridgemodel.Exercise_Operation_State.Waiting)
    testing.expect(t,
        chan.try_send(service.exercise_results, exercise_query_test_read(2)))
    service_exercise_queries(fixture.state)
    testing.expect(t, fixture.state.exercise_header.visible)
    testing.expect_value(t, operation.result.generation, u64(2))
    testing.expect_value(t, operation.inflight_token, u64(0))
}

// Accept an instruction read through the shared header show without resetting Terminal.
@(test)
exercise_query_commits_only_current_instruction_reads :: proc(t: ^testing.T) {
    fixture := julia_egress_router_test_context_create()
    defer julia_egress_router_test_context_destroy(fixture)
    operation := exercise_query_test_pending(fixture)
    result := exercise_query_test_read(1)
    accept_exercise_query_result(fixture.state, operation, &result)
    testing.expect_value(t, operation.state, bridgemodel.Exercise_Operation_State.Ready)
    testing.expect_value(t,
        operation.result.status, contentdata.Exercise_Query_Status.Ready)
    testing.expect_value(t, string(fixture.state.exercise_header.text[:5]), "Task!")
    testing.expect_value(t, fixture.state.exercise_header.last_request_id, u64(1))
    testing.expect(t, fixture.state.terminal.awaiting_eval)
    testing.expect_value(t, fixture.state.terminal.animation_generation, u64(4))
}

// Hide, newer show/load, navigation, and changed content identities reject stale text.
@(test)
exercise_query_rejects_stale_publication :: proc(t: ^testing.T) {
    fixture := julia_egress_router_test_context_create()
    defer julia_egress_router_test_context_destroy(fixture)
    for reason in 0..<4 {
        operation := exercise_query_test_pending(fixture)
        fixture.service.animation_generation = 4
        fixture.state.exercise_header.last_request_id = 0
        if reason == 0 {
            fixture.state.exercise_header.last_request_id = 1
        } else if reason == 1 {
            fixture.service.exercise_header_request_sequence.last_issued = 2
        } else if reason == 2 {
            fixture.service.animation_generation = 5
        }
        result := exercise_query_test_read(1)
        if reason == 3 {
            result.index_generation = 1
        }
        accept_exercise_query_result(fixture.state, operation, &result)
        testing.expect_value(t, operation.result.status,
            contentdata.Exercise_Query_Status.Superseded)
        testing.expect(t, !fixture.state.exercise_header.visible)
        testing.expect(t, fixture.state.terminal.awaiting_eval)
    }
}

// Prepare one correlated load without worker or native resource ownership.
exercise_query_test_pending :: proc(
    fixture: Router_Test_Context) -> ^bridgemodel.Exercise_Operation {
    fixture.service.exercise_header_request_sequence.last_issued = 1
    operation := &fixture.service.exercise_operation
    operation.state = .Waiting
    operation.index_generation = 0
    operation.intent = {
        token = 1,
        animation_generation = 4,
        header_request_id = 1,
        load = true,
        query = {
            generation = 1,
            kind = .Resolve_Alias,
        },
    }
    return operation
}

// Construct a fixed copy-out read result for acceptance and rejection tests.
exercise_query_test_read :: proc(token: u64) -> contentdata.Exercise_Query_Result {
    result: contentdata.Exercise_Query_Result = {
        generation = token,
        kind = .Read_Uuid,
        status = .Ready,
        instructions_length = 5,
    }
    copy(result.instructions[:], "Task!")
    return result
}
