package view

import bridgemodel "../bridge/model"
import contentdata "../core/content"
import exerciseheader "../core/exercise_header"
import userdata "../persistence/userdata"

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

// Preserve the visible instruction snapshot when its persisted record is edited or deleted.
@(test)
user_exercise_edit_and_delete_keep_displayed_snapshot :: proc(t: ^testing.T) {
    fixture := julia_egress_router_test_context_create()
    defer julia_egress_router_test_context_destroy(fixture)
    original: [8]u8 = "Original"
    testing.expect(t, exerciseheader.show(&fixture.state.exercise_header, original[:]))
    for request_index in 0..<2 {
        task: userdata.User_Exercise_Task = {
            request_id = u64(request_index + 1),
            operation = .Update if request_index == 0 else .Delete,
        }
        task.result.instructions_length = 7
        copy(task.result.instructions[:], "Changed")
        fixture.state.preferences_runtime.user_exercise_request = task
        fixture.state.preferences_runtime.user_exercise_request_state = .Complete
        operation := &fixture.service.user_exercise_operation
        operation.intent.request_id = task.request_id
        operation.state = .Waiting
        service_user_exercise_operations(fixture.state)
        testing.expect_value(
            t, operation.status, bridgemodel.User_Exercise_Result_Status.Ready)
        testing.expect_value(t,
            string(fixture.state.exercise_header.text[:8]), "Original")
        testing.expect(t, fixture.state.exercise_header.visible)
    }
}

// Keep a stored record intact and report a missing animation without replacing the header.
@(test)
user_exercise_load_reports_unavailable_association_without_mutation :: proc(
    t: ^testing.T) {
    fixture := julia_egress_router_test_context_create()
    defer julia_egress_router_test_context_destroy(fixture)
    original: [8]u8 = "Original"
    testing.expect(t, exerciseheader.show(&fixture.state.exercise_header, original[:]))
    fixture.service.exercise_header_request_sequence.last_issued = 1
    task: userdata.User_Exercise_Task = {
        request_id = 9,
        operation = .Read_Identity,
    }
    task.result.id[15] = 4
    task.result.animation_id[15] = 5
    copy(task.result.reference[:], "triangle")
    task.result.reference_length = 8
    copy(task.result.title[:], "Triangle")
    task.result.title_length = 8
    copy(task.result.instructions[:], "New text")
    task.result.instructions_length = 8
    fixture.state.preferences_runtime.user_exercise_request = task
    fixture.state.preferences_runtime.user_exercise_request_state = .Complete
    operation := &fixture.service.user_exercise_operation
    operation.intent = {
        request_id = 9,
        animation_generation = 4,
        header_request_id = 1,
        load = true,
    }
    operation.state = .Waiting
    service_user_exercise_operations(fixture.state)
    testing.expect_value(t,
        operation.status, bridgemodel.User_Exercise_Result_Status.Missing_Animation)
    testing.expect_value(t,
        string(operation.result.result.reference[
            :operation.result.result.reference_length]),
        "triangle")
    testing.expect_value(t,
        string(fixture.state.exercise_header.text[:8]), "Original")
}

// Drain an abandoned joined task so the single user-store request slot can be reused.
@(test)
user_exercise_cancelled_worker_result_is_drained :: proc(t: ^testing.T) {
    fixture := julia_egress_router_test_context_create()
    defer julia_egress_router_test_context_destroy(fixture)
    fixture.state.preferences_runtime.user_exercise_request = {
        request_id = 12,
        operation = .List,
    }
    fixture.state.preferences_runtime.user_exercise_request_state = .Complete
    fixture.service.user_exercise_operation.intent.request_id = 12
    fixture.service.user_exercise_operation.state = .Idle
    service_user_exercise_operations(fixture.state)
    testing.expect_value(t,
        fixture.state.preferences_runtime.user_exercise_request_state,
        userdata.User_Exercise_Request_State.None)
    testing.expect_value(t,
        fixture.service.user_exercise_operation.state,
        bridgemodel.User_Exercise_Operation_State.Idle)
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
