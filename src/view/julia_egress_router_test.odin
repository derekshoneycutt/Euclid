package view

import bridgemodel "../bridge/model"
import core "../core"
import testing "core:testing"
import viewpresentation "presentation"

Router_Test_Context :: struct {
    state: ^core.Euclid_General_State,
    service: ^bridgemodel.Julia_Runtime_Service,
    runtime: ^viewpresentation.Presentation_Runtime,
}

// Verify the display copies matching header updates without resetting Terminal.
@(test)
julia_egress_router_commits_exercise_header_updates :: proc(t: ^testing.T) {
    fixture := julia_egress_router_test_context_create()
    defer julia_egress_router_test_context_destroy(fixture)
    source: [5]u8 = "Task!"
    message := julia_egress_router_test_update(4, 2, true, source[:])
    testing.expect(t, !julia_egress_router_dispatch(rawptr(fixture.runtime), &message))
    testing.expect(t, fixture.state^.exercise_header.visible)
    testing.expect_value(t, string(fixture.state^.exercise_header.text[:5]), "Task!")
    source = "Other"
    testing.expect_value(t, string(fixture.state^.exercise_header.text[:5]), "Task!")
    testing.expect(t, fixture.state^.terminal.awaiting_eval)
}

// Verify wrong-generation and out-of-order updates cannot replace or reveal content.
@(test)
julia_egress_router_rejects_stale_exercise_header_updates :: proc(t: ^testing.T) {
    fixture := julia_egress_router_test_context_create()
    defer julia_egress_router_test_context_destroy(fixture)
    source: [5]u8 = "Task!"
    initial := julia_egress_router_test_update(4, 2, true, source[:])
    _ = julia_egress_router_dispatch(rawptr(fixture.runtime), &initial)
    stale := julia_egress_router_test_update(3, 3, true, source[:])
    _ = julia_egress_router_dispatch(rawptr(fixture.runtime), &stale)
    older := julia_egress_router_test_update(4, 1, true, source[:])
    _ = julia_egress_router_dispatch(rawptr(fixture.runtime), &older)
    testing.expect_value(t, string(fixture.state^.exercise_header.text[:5]), "Task!")
    testing.expect(t, fixture.state^.terminal.awaiting_eval)
}

// Verify hides advance ordering so an earlier queued show cannot reveal content again.
@(test)
julia_egress_router_hides_exercise_header_in_request_order :: proc(t: ^testing.T) {
    fixture := julia_egress_router_test_context_create()
    defer julia_egress_router_test_context_destroy(fixture)
    source: [5]u8 = "Task!"
    initial := julia_egress_router_test_update(4, 2, true, source[:])
    _ = julia_egress_router_dispatch(rawptr(fixture.runtime), &initial)
    hidden := julia_egress_router_test_update(4, 4, false, nil)
    _ = julia_egress_router_dispatch(rawptr(fixture.runtime), &hidden)
    before_hide := julia_egress_router_test_update(4, 3, true, source[:])
    _ = julia_egress_router_dispatch(rawptr(fixture.runtime), &before_hide)
    testing.expect(t, !fixture.state^.exercise_header.visible)
    testing.expect_value(t, fixture.state^.exercise_header.count, 0)
    testing.expect(t, fixture.state^.terminal.awaiting_eval)
}

// Verify display invalidation rejects queued work but admits a newer producer request.
@(test)
julia_egress_router_respects_exercise_header_invalidation :: proc(t: ^testing.T) {
    fixture := julia_egress_router_test_context_create()
    defer julia_egress_router_test_context_destroy(fixture)
    fixture.service^.exercise_header_request_sequence.last_issued = 5
    bridgemodel.exercise_header_invalidate_requests(
        &fixture.service^.exercise_header_request_sequence,
        &fixture.state^.exercise_header.last_request_id)
    source: [5]u8 = "Other"
    invalidated := julia_egress_router_test_update(4, 5, true, source[:])
    _ = julia_egress_router_dispatch(rawptr(fixture.runtime), &invalidated)
    testing.expect(t, !fixture.state^.exercise_header.visible)
    replacement := julia_egress_router_test_update(4, 6, true, source[:])
    _ = julia_egress_router_dispatch(rawptr(fixture.runtime), &replacement)
    testing.expect(t, fixture.state^.exercise_header.visible)
    testing.expect_value(t, string(fixture.state^.exercise_header.text[:5]), "Other")
}

// Create the isolated Terminal, Julia service, and presentation state for router tests.
julia_egress_router_test_context_create :: proc() -> Router_Test_Context {
    state := new(core.Euclid_General_State, context.allocator)
    state^.terminal.initialized = true
    state^.terminal.animation_generation = 4
    state^.terminal.awaiting_eval = true
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    service^.animation_generation = 4
    state^.julia_runtime_service = service
    runtime := viewpresentation.create_presentation_runtime()
    runtime^.state = state
    return {state, service, runtime}
}

// Destroy allocations owned by one isolated router test fixture.
julia_egress_router_test_context_destroy :: proc(fixture: Router_Test_Context) {
    viewpresentation.destroy_presentation_runtime(fixture.runtime)
    free(fixture.service, context.allocator)
    free(fixture.state, context.allocator)
}

// Build one typed exercise-header update envelope for router tests.
julia_egress_router_test_update :: proc(
    generation, request_id: u64, visible: bool,
    text: []u8) -> bridgemodel.Julia_Host_Egress {
    return bridgemodel.Julia_Host_Egress(bridgemodel.Exercise_Header_Update{
        animation_generation = generation,
        request_id = request_id,
        visible = visible,
        text = text,
    })
}
