package ui

import viewmodel "../model"

import view_font "../font"
import geometry "../../core/geometry"

SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID :: 6101

//   Inputs for one reusable integer slider control: placement, pointer input,
//   shared UI/press state, label, value cell, and the allowed range, grouped so
//   the draw call passes one coherent value.
Integer_Slider_Params :: struct {
    panel : geometry.Rectangle,
    row_y : f32,
    mouse_input : Input_Frame,
    ui_runtime : ^viewmodel.Euclid_Ui_Runtime_State,
    press_id : int,
    label : string,
    value : ^int,
    min_value : int,
    max_value : int,
    font : view_font.Font_Face,
    font_resolver : view_font.Font_Resolver,
}

//   Prepared interaction and geometry for one integer slider draw.
Integer_Slider_Result :: struct {
    value: int,
}

//   Value range and drag inputs for one slider drag update.
Slider_Drag_Input :: struct {
    min_value : int,
    max_value : int,
    denom : int,
    mouse_input : Input_Frame,
    track : geometry.Rectangle,
}

// Build knob geometry from track bounds and normalized ratio.
build_slider_knob :: proc(
    slider_track: geometry.Rectangle,
    ratio: f32) -> (f32, geometry.Rectangle) {
    knob_center_x := slider_track.x + ratio * slider_track.width
    knob := geometry.Rectangle{
        knob_center_x - SETTINGS_KNOB_WIDTH * 0.5,
        slider_track.y - SETTINGS_KNOB_PAD_Y,
        SETTINGS_KNOB_WIDTH,
        slider_track.height + SETTINGS_KNOB_PAD_Y * 2,
    }
    return knob_center_x, knob
}

//   Build the slider track rectangle for one settings row.
slider_track_rect :: #force_inline proc(
    panel: geometry.Rectangle, row_y: f32) -> geometry.Rectangle {
    return geometry.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y + SETTINGS_TRACK_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        SETTINGS_TRACK_HEIGHT,
    }
}

//   Build the expanded hit area around a slider track.
slider_hit_rect :: #force_inline proc(
    track: geometry.Rectangle) -> geometry.Rectangle {
    return geometry.Rectangle{
        track.x,
        track.y - SETTINGS_TRACK_HIT_PAD_Y,
        track.width,
        track.height + SETTINGS_TRACK_HIT_PAD_Y * 2,
    }
}

//   Apply one wheel-step value change when the pointer is over the slider hit area.
slider_apply_wheel_step :: proc(
    clamped: ^int,
    min_value, max_value: int,
    mouse_input: Input_Frame,
    hit: geometry.Rectangle) {

    if !geometry.rectangle_contains(
        hit, geometry.Vector2(input_frame_mouse_position(mouse_input))) {
        return
    }

    wheel := mouse_input.mouse_wheel_delta
    if wheel == 0 {
        return
    }

    delta := 1
    if wheel < 0 {
        delta = -1
    }
    clamped^ = clamp(clamped^ + delta, min_value, max_value)
}

//   Return whether this slider currently owns the shared global press state.
slider_owns_press :: #force_inline proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    press_id: int) -> bool {

    return ui_runtime.ui_press_owner.active &&
        ui_runtime.ui_press_owner.kind == .Slider &&
        ui_runtime.ui_press_owner.id == press_id
}

//   Capture shared press ownership for this slider if no control currently owns it.
slider_try_capture_press :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    mouse_input: Input_Frame,
    press_id: int,
    hovered_hit: bool,
    owns_press: ^bool) {

    if ui_runtime.ui_press_owner.active ||
        !input_frame_left_pressed(mouse_input) || !hovered_hit {
        return
    }

    ui_runtime.ui_press_owner.active = true
    ui_runtime.ui_press_owner.kind = .Slider
    ui_runtime.ui_press_owner.id = press_id
    owns_press^ = true
}

//   Release shared press ownership when the current mouse hold ends.
slider_release_if_needed :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    mouse_input: Input_Frame,
    owns_press: ^bool) {

    if !owns_press^ || input_frame_left_down(mouse_input) {
        return
    }

    ui_runtime.ui_press_owner.active = false
    ui_runtime.ui_press_owner.kind = .None
    ui_runtime.ui_press_owner.id = -1
    owns_press^ = false
}

//   Apply drag position to compute slider value while this slider owns press.
slider_apply_drag_value :: proc(
    clamped: ^int,
    input: Slider_Drag_Input,
    owns_press: bool) {

    if !owns_press || !input_frame_left_down(input.mouse_input) ||
        input.track.width <= 0 {
        return
    }

    t := clamp((input.mouse_input.mouse_position.x - input.track.x) /
        input.track.width,
        0, 1)
    clamped^ = clamp(input.min_value + int(t * f32(input.denom) + 0.5),
        input.min_value, input.max_value)
}

//   Compute the clamped slider value after wheel/press/drag interaction.
//
// Returns:
//   - clamped: The resolved value.
//   - owns_press: true while this slider owns the press.
slider_resolve_value :: proc(
    params: Integer_Slider_Params,
    track: geometry.Rectangle,
    hit: geometry.Rectangle) -> (int, bool) {

    clamped := clamp(params.value^, params.min_value, params.max_value)
    denom := max(1, params.max_value - params.min_value)

    slider_apply_wheel_step(&clamped, params.min_value, params.max_value,
        params.mouse_input, hit)

    hovered_hit := geometry.rectangle_contains(
        hit, geometry.Vector2(input_frame_mouse_position(params.mouse_input)))
    owns_press := slider_owns_press(params.ui_runtime, params.press_id)
    slider_try_capture_press(params.ui_runtime, params.mouse_input, params.press_id,
        hovered_hit, &owns_press)
    slider_release_if_needed(params.ui_runtime, params.mouse_input, &owns_press)
    slider_apply_drag_value(&clamped,
        Slider_Drag_Input{params.min_value, params.max_value, denom,
            params.mouse_input, track},
        owns_press)
    return clamped, owns_press
}

//   Resolve one integer slider update without issuing drawing commands.
update_settings_integer_slider :: proc(
    params: Integer_Slider_Params) -> Integer_Slider_Result {
    track := slider_track_rect(params.panel, params.row_y)
    hit := slider_hit_rect(track)

    clamped, owns_press := slider_resolve_value(params, track, hit)
    params.value^ = clamped

    _ = owns_press
    return {clamped}
}
