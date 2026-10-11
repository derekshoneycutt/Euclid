#+test
package bridge

import "../core"
import contentdata "../core/content"
import "core:testing"

// Allocate a host fixture whose callback values do not borrow a content arena.
content_specification_test_state :: proc() -> ^core.Euclid_General_State {
    state := new(core.Euclid_General_State, context.allocator)
    state^.saved_context = context
    state^.julia_runtime_service = new(Julia_Runtime_Service, context.allocator)
    service := state^.julia_runtime_service
    service^.animation_generation = 7
    service^.active_content_specification = {
        selection_revision = 1, animation_identity = {15 = 1},
        content_generation_identity = 17, runtime_generation_identity = 0,
    }
    service^.pending_content_specification = {
        selection_revision = 2, animation_identity = {15 = 2},
        content_generation_identity = 18, runtime_generation_identity = 1,
    }
    return state
}

// Exercise old Exit, replacement Enter, rollback Enter, stale identities, and reset revisions.
@(test)
content_specification_lifecycle_context :: proc(t: ^testing.T) {
    state := content_specification_test_state()
    defer free(state^.julia_runtime_service, context.allocator)
    defer free(state, context.allocator)
    service := state^.julia_runtime_service
    output: contentdata.Animation_Content_Specification
    testing.expect_value(t, copy_animation_content_specification(
        state, {{15 = 1}, 0, 7, .Exit}, &output), u32(1))
    service^.animation_lifecycle_slot.state = .Pending
    testing.expect_value(t, copy_animation_content_specification(
        state, {{15 = 1}, 0, 7, .Exit}, &output), u32(0))
    testing.expect_value(t, output, service^.active_content_specification)
    testing.expect_value(t, copy_animation_content_specification(
        state, {{15 = 2}, 1, 8, .Enter}, &output), u32(0))
    testing.expect_value(t, output, service^.pending_content_specification)
    testing.expect_value(t, copy_animation_content_specification(
        state, {{15 = 1}, 0, 7, .Enter}, &output), u32(0))
    testing.expect_value(t, output, service^.active_content_specification)
    baseline := output
    testing.expect_value(t, copy_animation_content_specification(
        state, {{15 = 2}, 0, 7, .Exit}, &output), u32(2))
    testing.expect_value(t, copy_animation_content_specification(
        state, {{15 = 1}, 1, 7, .Exit}, &output), u32(4))
    testing.expect_value(t, output, baseline)
    service^.pending_content_specification = service^.active_content_specification
    testing.expect_value(t, copy_animation_content_specification(
        state, {{15 = 1}, 0, 8, .Enter}, &output), u32(0))
    testing.expect_value(t, output.selection_revision, u64(1))
}

// Tick capture remains immutable after active selection changes and allocates no query storage.
@(test)
content_specification_tick_copy_and_errors :: proc(t: ^testing.T) {
    state := content_specification_test_state()
    defer free(state^.julia_runtime_service, context.allocator)
    defer free(state, context.allocator)
    snapshot := new(Animation_Query_Snapshot, context.allocator)
    defer free(snapshot, context.allocator)
    capture_animation_query_snapshot(state, snapshot)
    old := snapshot^.content_specification
    service := state^.julia_runtime_service
    service^.active_content_specification = service^.pending_content_specification
    state^.animation_query_snapshot_target = snapshot
    output: contentdata.Animation_Content_Specification
    for _ in 0..<1000 {
        testing.expect_value(t, copy_animation_content_specification(
            state, {{15 = 1}, 0, 7, .Tick}, &output), u32(0))
        testing.expect_value(t, output, old)
    }
    testing.expect_value(t, copy_animation_content_specification(
        state, {{15 = 2}, 0, 7, .Tick}, &output), u32(2))
    testing.expect_value(t, copy_animation_content_specification(
        state, {{15 = 1}, 0, 8, .Tick}, &output), u32(4))
    testing.expect_value(t, copy_animation_content_specification(
        state, {{15 = 1}, 0, 7, .Tick}, nil), u32(5))
    testing.expect_value(t, copy_animation_content_specification(
        nil, {{}, 0, 0, .Tick}, &output), u32(1))
}
