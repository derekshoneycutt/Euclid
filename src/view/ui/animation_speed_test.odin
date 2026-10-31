#+test
package ui

import testing "core:testing"
import animationmodel "../../core/animation"
import bridgemodel "../../bridge/model"
import capturemodel "../capture/model"
import viewmodel "model"
import uianimation "animation"
import uisemantics "semantics"
import native "../native"
import geometry "../../core/geometry"
import theme "theme"

// Paused FF never changes speed; playing after completion restarts instead of resuming.
@(test)
animation_completed_transport_retains_speed_and_independent_pauses :: proc(
    t: ^testing.T) {
    ji: bridgemodel.Euclid_Julia_Interface
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    state, store := animation_controls_test_state(t, &ji, &animation)
    defer free(store, context.allocator)
    defer destroy_shell_test_state(state)
    playback := &state^.ui_runtime.playback
    playback^.rate = .Quadruple
    playback^.animation_policy_paused = true
    uianimation.apply_animation_control_hit(state, {
        toggle_pause_requested = true,
    })
    testing.expect(t, playback^.construction_paused)
    testing.expect(t, !playback^.simulation_paused)
    uianimation.apply_animation_control_hit(state, {
        cycle_speed_requested = true,
    })
    testing.expect(t, playback^.completion_requested)
    testing.expect_value(t, playback^.rate, animationmodel.Playback_Rate.Quadruple)
    playback^.completion_requested = false
    playback^.completed = true
    uianimation.apply_animation_control_hit(state, {
        toggle_pause_requested = true,
    })
    testing.expect(t, ji.pending_animation_reset)
    testing.expect(t, !playback^.completed && !playback^.construction_paused)
    testing.expect(t, playback^.animation_policy_paused)
    testing.expect_value(t, playback^.rate, animationmodel.Playback_Rate.Quadruple)
}

// Transport cycling retains pause and selected speed through reset and every capture exit.
@(test)
animation_speed_cycles_without_resuming_and_capture_restores_choice :: proc(
    t: ^testing.T) {
    ji: bridgemodel.Euclid_Julia_Interface
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    state, store := animation_controls_test_state(t, &ji, &animation)
    defer free(store, context.allocator)
    defer destroy_shell_test_state(state)
    state.ui_runtime.playback.simulation_paused = true
    expected_rates: [3]animationmodel.Playback_Rate = {.Double, .Quadruple, .Normal}
    for expected in expected_rates {
        uianimation.apply_animation_control_hit(state, {
            cycle_speed_requested = true,
        })
        testing.expect_value(t, state.ui_runtime.playback.rate, expected)
        testing.expect(t, state.ui_runtime.playback.simulation_paused)
    }
    state.ui_runtime.playback.rate = .Quadruple
    uianimation.apply_animation_control_hit(state, {
        refresh_requested = true,
    })
    testing.expect_value(t,
        state.ui_runtime.playback.rate, animationmodel.Playback_Rate.Quadruple)
    for phase in capturemodel.Gif_Capture_Phase {
        state.gif_capture_status.gif_capture_phase = phase
        effective := capturemodel.gif_capture_playback_rate(
            state.ui_runtime.playback.rate, phase)
        locked := capturemodel.gif_capture_locks_playback_rate(phase)
        testing.expect_value(t, effective,
            animationmodel.Playback_Rate.Normal if locked else .Quadruple)
        if locked {
            uianimation.apply_animation_control_hit(state, {
                cycle_speed_requested = true,
            })
            testing.expect_value(t, state.ui_runtime.playback.rate,
                animationmodel.Playback_Rate.Quadruple)
        }
    }
}

// The rate button has no trailing text reservation and its slash/badges stay in one slot.
@(test)
animation_speed_glyphs_fit_one_transport_slot :: proc(t: ^testing.T) {
    slots := uianimation.animation_control_layout_slots({0, 0, 640, 480}, false)
    testing.expect_value(t, slots.speed.width, slots.pause.width)
    testing.expect_value(t, slots.panel.x + slots.panel.width,
        slots.speed.x + slots.speed.width + theme.ANIMATION_CONTROL_PADDING)
    vertices: [1024]native.Draw_Vertex
    indices: [2048]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    for rate in animationmodel.Playback_Rate {
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {30, 30}, {30, 30}))
        uianimation.draw_encoded_speed_glyph(&encoder, {3, 3, 24, 24},
            theme.UI_TEXT_COLOR, rate)
        badge_vertices := 0
        for vertex in vertices[:encoder.vertex_count] {
            testing.expect(t,
                geometry.rectangle_contains({0, 0, 30, 30}, vertex.position))
            if vertex.color == theme.UI_COMPONENT_BACKGROUND_COLOR {
                badge_vertices += 1
            }
        }
        testing.expect_value(t, badge_vertices > 0, rate != .Normal)
        testing.expect(t, encoder.vertex_count > 0)
    }
}

// Disabled speed has honest semantics and ignores a previously addressed activation.
@(test)
animation_speed_capture_disables_semantic_activation :: proc(t: ^testing.T) {
    ji: bridgemodel.Euclid_Julia_Interface
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    state, store := animation_controls_test_state(t, &ji, &animation)
    defer free(store, context.allocator)
    defer destroy_shell_test_state(state)
    focus := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(focus, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(focus)
    state.ui_runtime.semantic_focus = focus
    state.ui_runtime.playback.rate = .Double
    testing.expect(t, uisemantics.semantic_begin(focus))
    _ = uianimation.prepare_animation_controls(state, {})
    testing.expect_value(t,
        uisemantics.semantic_publish(focus), viewmodel.Ui_Semantic_Status.Ok)
    id := uisemantics.semantic_control_id(
        .Animation_Control, uianimation.ANIMATION_SPEED_BUTTON_ID)
    testing.expect(t, uisemantics.semantic_append_command(focus, {
        target = id,
        kind = .Activate,
    }))
    state.gif_capture_status.save_gif_requested = true
    testing.expect(t, uisemantics.semantic_begin(focus))
    prepared := uianimation.prepare_animation_controls(state, {})
    testing.expect(t, prepared.speed_locked && !prepared.speed.action.activated)
    testing.expect_value(t,
        state.ui_runtime.playback.rate, animationmodel.Playback_Rate.Double)
    testing.expect_value(t,
        uisemantics.semantic_publish(focus), viewmodel.Ui_Semantic_Status.Ok)
    snapshot := uisemantics.semantic_snapshot(focus)
    testing.expect(t,
        .Enabled not_in
            snapshot.nodes[uisemantics.semantic_node_index(snapshot, id)].states)
}

// Semantic activation dismisses the old rate tooltip just like pointer activation.
@(test)
animation_speed_keyboard_activation_dismisses_tooltip :: proc(t: ^testing.T) {
    ji: bridgemodel.Euclid_Julia_Interface
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    state, store := animation_controls_test_state(t, &ji, &animation)
    defer free(store, context.allocator)
    defer destroy_shell_test_state(state)
    focus := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(focus, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(focus)
    state.ui_runtime.semantic_focus = focus
    testing.expect(t, uisemantics.semantic_begin(focus))
    _ = uianimation.prepare_animation_controls(state, {})
    testing.expect_value(t, uisemantics.semantic_publish(focus),
        viewmodel.Ui_Semantic_Status.Ok)
    id := uisemantics.semantic_control_id(
        .Animation_Control, uianimation.ANIMATION_SPEED_BUTTON_ID)
    testing.expect(t, uisemantics.semantic_append_command(focus,{
        target = id,
        kind = .Activate,
    }))
    testing.expect(t, uisemantics.semantic_begin(focus))
    _ = uianimation.prepare_animation_controls(state, {})
    testing.expect_value(t, state.ui_runtime.playback.rate,
        animationmodel.Playback_Rate.Double)
    testing.expect_value(t, state.ui_runtime.tooltip.dismissed_owner, id)
}
