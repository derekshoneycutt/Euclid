#+test
package magnifier

import geometry "../../core/geometry"
import testing "core:testing"
import viewmodel "../ui/model"

// Keep the lens above the pointer unless it must flip below.
@(test)
magnifier_placement_flips_and_clamps_to_window :: proc(t: ^testing.T) {
    above := magnifier_desired_rect({160, 220}, 320, 480)
    testing.expect_value(t, above, geometry.Rectangle{40, 44, 240, 160})

    below := magnifier_desired_rect({160, 80}, 320, 480)
    testing.expect_value(t, below, geometry.Rectangle{40, 96, 240, 160})

    edge := magnifier_desired_rect({319, 479}, 320, 480)
    testing.expect_value(t, edge, geometry.Rectangle{72, 303, 240, 160})
}

// Hide without fallback outside the window and reset lens interpolation state.
@(test)
magnifier_hides_outside_window_and_when_disabled :: proc(t: ^testing.T) {
    state: viewmodel.Ui_Magnifier_State
    frame: Magnifier_Frame_Input = {
        enabled = true,
        window_focused = true,
        pointer = {120, 160},
        width = 320,
        height = 480,
        delta_seconds = 1.0 / 60,
    }
    visible := magnifier_prepare(&state, frame)
    testing.expect(t, visible.visible && state.initialized)
    frame.pointer = {-1, 100}
    hidden := magnifier_prepare(&state, frame)
    testing.expect(t, !hidden.visible && !state.initialized)
    frame.pointer = {120, 160}
    frame.enabled = false
    disabled := magnifier_prepare(&state, frame)
    testing.expect(t, !disabled.visible)
    frame.enabled = true
    frame.window_focused = false
    unfocused := magnifier_prepare(&state, frame)
    testing.expect(t, !unfocused.visible)
}

// Respect reduced motion and interpolate only the lens, never the source pointer.
@(test)
magnifier_interpolates_placement_unless_reduced_motion :: proc(t: ^testing.T) {
    state: viewmodel.Ui_Magnifier_State
    frame: Magnifier_Frame_Input = {
        enabled = true,
        window_focused = true,
        pointer = {80, 240},
        width = 640,
        height = 480,
        delta_seconds = 1.0 / 60,
    }
    first := magnifier_prepare(&state, frame)
    frame.pointer = {560, 240}
    moved := magnifier_prepare(&state, frame)
    testing.expect_value(t, first.source.x, f32(80))
    testing.expect_value(t, moved.source.x, f32(560))
    testing.expect(t, moved.lens_rect.x > first.lens_rect.x)
    testing.expect(t, moved.lens_rect.x < 400)

    frame.reduce_motion = true
    reduced := magnifier_prepare(&state, frame)
    testing.expect_value(t, reduced.lens_rect.x, f32(392))
}

// Caret mode follows only the clipped caret and chooses the side with available room.
@(test)
magnifier_input_lock_tracks_visible_caret_without_pointer_fallback :: proc(
    t: ^testing.T) {
    state: viewmodel.Ui_Magnifier_State
    frame: Magnifier_Frame_Input = {
        enabled = true,
        input_lock = true,
        caret_anchor = {180, 8, 2, 20},
        caret_clip = {0, 0, 320, 480},
        caret_valid = true,
        window_focused = true,
        pointer = {300, 400},
        width = 320,
        height = 480,
        delta_seconds = 1.0 / 60,
    }
    visible := magnifier_prepare(&state, frame)
    testing.expect(t, visible.visible)
    testing.expect_value(t, visible.source, geometry.Vector2{181, 18})
    testing.expect_value(t, visible.lens_rect.y, f32(34))

    frame.caret_anchor = {180, 300, 2, 20}
    centered := magnifier_prepare(&state, frame)
    testing.expect_value(t, centered.source, geometry.Vector2{181, 310})
    testing.expect(t, centered.lens_rect.y < 134)
    testing.expect(t, centered.lens_rect.y > visible.lens_rect.y)
}

// Caret lock hides for missing, clipped, or retired caret anchors.
@(test)
magnifier_input_lock_hides_without_an_eligible_visible_caret :: proc(
    t: ^testing.T) {
    state: viewmodel.Ui_Magnifier_State
    frame: Magnifier_Frame_Input = {
        enabled = true,
        input_lock = true,
        caret_anchor = {180, 200, 2, 20},
        caret_clip = {0, 0, 320, 480},
        caret_valid = true,
        window_focused = true,
        pointer = {120, 160},
        width = 320,
        height = 480,
        delta_seconds = 1.0 / 60,
    }
    testing.expect(t, magnifier_prepare(&state, frame).visible)
    frame.caret_clip.height = 100
    hidden := magnifier_prepare(&state, frame)
    testing.expect(t, !hidden.visible && !state.initialized)
    frame.caret_clip.height = 480
    frame.caret_valid = false
    retired := magnifier_prepare(&state, frame)
    testing.expect(t, !retired.visible)
}
