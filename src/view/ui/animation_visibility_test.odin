#+test
package ui

import testing "core:testing"
import geometry "../../core/geometry"
import bridgemodel "../../bridge/model"
import viewmodel "model"
import uianimation "animation"
import uisemantics "semantics"

// Collapsing retires overlay semantics and popup focus without changing playback.
@(test)
animation_visibility_retires_overlay_and_preserves_playback :: proc(t: ^testing.T) {
    ji: bridgemodel.Euclid_Julia_Interface
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    state, store := animation_controls_test_state(t, &ji, &animation)
    defer free(store, context.allocator)
    defer destroy_shell_test_state(state)
    focus := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(focus, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(focus)
    state.ui_runtime.semantic_focus = focus
    state.ui_runtime.playback.simulation_paused = true
    eye := uisemantics.semantic_control_id(
        .Animation_Control, uianimation.ANIMATION_VISIBILITY_BUTTON_ID)
    testing.expect(t, uisemantics.semantic_begin(focus))
    before := uianimation.prepare_animation_controls(state, {})
    testing.expect(t, before.overlay_visible)
    testing.expect_value(t, uisemantics.semantic_publish(focus),
        viewmodel.Ui_Semantic_Status.Ok)
    testing.expect(t, uisemantics.semantic_append_command(focus,
        {target = eye, kind = .Activate}))
    state.ui_runtime.membership.active = true
    focus.logical_focus = {domain = .Collection_Membership}
    testing.expect(t, uisemantics.semantic_begin(focus))
    hidden := uianimation.prepare_animation_controls(state, {})
    testing.expect(t, hidden.visible && !hidden.overlay_visible)
    testing.expect(t, !state.ui_runtime.membership.active)
    testing.expect_value(t, focus.logical_focus, eye)
    testing.expect(t, state.ui_runtime.playback.simulation_paused)
    testing.expect(t, !ji.pending_animation_reset)
    testing.expect_value(t, uisemantics.semantic_publish(focus),
        viewmodel.Ui_Semantic_Status.Ok)
    testing.expect_value(t, uisemantics.semantic_snapshot(focus).node_count, 1)
}

// Hidden transport slots pass through while the anchored eye remains interactive.
@(test)
animation_visibility_hit_test_restores_world_input :: proc(t: ^testing.T) {
    world := geometry.Rectangle{80, 40, 640, 480}
    slots := uianimation.animation_control_layout_slots(world, true, true)
    test_rects := [5]geometry.Rectangle{
        slots.refresh, slots.pause, slots.favorite, slots.membership, slots.speed,
    }
    for rect in test_rects {
        _, hit := uianimation.animation_control_hit_test(world, .Idle,
            {rect.x + 1, rect.y + 1},
            {favorite = true, membership = true, hidden = true})
        testing.expect(t, !hit)
    }
    point := geometry.Vector2{slots.eye.x + 1, slots.eye.y + 1}
    id, hit := uianimation.animation_control_hit_test(
        world, .Idle, point, {favorite = true, membership = true, hidden = true})
    testing.expect(t, hit)
    testing.expect_value(t, id, uianimation.ANIMATION_VISIBILITY_BUTTON_ID)
    _, recording_hit := uianimation.animation_control_hit_test(
        world, .Recording, point, {favorite = true, membership = true, hidden = true})
    testing.expect(t, !recording_hit)
}
