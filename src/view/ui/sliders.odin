package ui

import view_core "../core"
import "../../core"

import "core:fmt"

import rl "vendor:raylib"

SETTINGS_MAX_PARTICLES_SLIDER_PRESS_ID :: 6101

//   Build knob geometry from track bounds and normalized ratio.
build_slider_knob :: proc(
    slider_track: rl.Rectangle, ratio: f32) -> (f32, rl.Rectangle) {
    knob_center_x := slider_track.x + ratio * slider_track.width
    knob := rl.Rectangle{
        knob_center_x - SETTINGS_KNOB_WIDTH * 0.5,
        slider_track.y - SETTINGS_KNOB_PAD_Y,
        SETTINGS_KNOB_WIDTH,
        slider_track.height + SETTINGS_KNOB_PAD_Y * 2,
    }
    return knob_center_x, knob
}

//   Scale a rectangle around its center for hover/press visual feedback.
scale_rect_about_center :: #force_inline proc(
    rect: rl.Rectangle, scale: f32) -> rl.Rectangle {
    if scale <= 0 {
        return rect
    }

    center_x := rect.x + rect.width * 0.5
    center_y := rect.y + rect.height * 0.5
    width := rect.width * scale
    height := rect.height * scale

    return rl.Rectangle{
        center_x - width * 0.5,
        center_y - height * 0.5,
        width,
        height,
    }
}

//   Build the slider track rectangle for one settings row.
slider_track_rect :: #force_inline proc(panel: rl.Rectangle, row_y: f32) -> rl.Rectangle {
    return rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y + SETTINGS_TRACK_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        SETTINGS_TRACK_HEIGHT,
    }
}

//   Build the expanded hit area around a slider track.
slider_hit_rect :: #force_inline proc(track: rl.Rectangle) -> rl.Rectangle {
    return rl.Rectangle{
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
    mouse_input: Mouse_Input_State,
    hit: rl.Rectangle) {

    if !rl.CheckCollisionPointRec(mouse_input.position, hit) {
        return
    }

    wheel := mouse_input.wheel_delta
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
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    press_id: int) -> bool {

    return ui_runtime.ui_press_owner.active &&
        ui_runtime.ui_press_owner.kind == .Slider &&
        ui_runtime.ui_press_owner.id == press_id
}

//   Capture shared press ownership for this slider if no control currently owns it.
slider_try_capture_press :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    mouse_input: Mouse_Input_State,
    press_id: int,
    hovered_hit: bool,
    owns_press: ^bool) {

    if ui_runtime.ui_press_owner.active || !mouse_input.left_pressed || !hovered_hit {
        return
    }

    ui_runtime.ui_press_owner.active = true
    ui_runtime.ui_press_owner.kind = .Slider
    ui_runtime.ui_press_owner.id = press_id
    owns_press^ = true
}

//   Release shared press ownership when the current mouse hold ends.
slider_release_if_needed :: proc(
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    mouse_input: Mouse_Input_State,
    owns_press: ^bool) {

    if !owns_press^ || mouse_input.left_down {
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
    min_value, max_value: int,
    denom: int,
    mouse_input: Mouse_Input_State,
    track: rl.Rectangle,
    owns_press: bool) {

    if !owns_press || !mouse_input.left_down || track.width <= 0 {
        return
    }

    t := clamp((mouse_input.position.x - track.x) / track.width, 0, 1)
    clamped^ = clamp(min_value + int(t * f32(denom) + 0.5), min_value, max_value)
}

//   Build knob draw rect and color with icon-button-style hover/press feedback.
slider_knob_draw_style :: proc(
    knob: rl.Rectangle,
    panel: rl.Rectangle,
    mouse_input: Mouse_Input_State,
    pressed_knob: bool) -> (rl.Rectangle, rl.Color) {

    hovered_knob := rl.CheckCollisionPointRec(mouse_input.position, knob) &&
        rl.CheckCollisionPointRec(mouse_input.position, panel)

    knob_hover_t: f32 = 0
    if hovered_knob {
        knob_hover_t = 1
    }

    knob_press_t: f32 = 0
    if pressed_knob {
        knob_press_t = 1
    }

    knob_scale := 1.0 + ICON_BUTTON_HOVER_SCALE_ADD * knob_hover_t -
        ICON_BUTTON_PRESS_SCALE_SUB * knob_press_t
    knob_draw := scale_rect_about_center(knob, knob_scale)

    knob_color := UI_TEXT_COLOR
    if knob_press_t > 0 {
        knob_color = icon_button_darken(knob_color, knob_press_t)
    }

    if pressed_knob {
        knob_draw.x += 0.5
        knob_draw.y += 0.5
    }

    return knob_draw, knob_color
}


//   Render and update a reusable integer slider control.
draw_settings_integer_slider :: proc(
    panel: rl.Rectangle,
    row_y: f32,
    mouse_input: Mouse_Input_State,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    press_id: int,
    label: string,
    value: ^int,
    min_value, max_value: int,
    font: rl.Font) {

    view_core.ui_text(label, int(panel.x + SETTINGS_PANEL_INSET),
        int(row_y), UI_TEXT_COLOR, font)

    track := slider_track_rect(panel, row_y)
    hit := slider_hit_rect(track)

    clamped := clamp(value^, min_value, max_value)
    denom := max(1, max_value - min_value)
    ratio := f32(clamped - min_value) / f32(denom)
    knob_center_x, knob := build_slider_knob(track, ratio)

    slider_apply_wheel_step(&clamped, min_value, max_value, mouse_input, hit)

    hovered_hit := rl.CheckCollisionPointRec(mouse_input.position, hit)

    owns_press := slider_owns_press(ui_runtime, press_id)
    slider_try_capture_press(ui_runtime, mouse_input, press_id, hovered_hit, &owns_press)
    slider_release_if_needed(ui_runtime, mouse_input, &owns_press)
    slider_apply_drag_value(&clamped, min_value, max_value, denom,
        mouse_input, track, owns_press)

    value^ = clamped

    ratio = f32(clamped - min_value) / f32(denom)
    knob_center_x, knob = build_slider_knob(track, ratio)

    pressed_knob := owns_press && mouse_input.left_down
    knob_draw, knob_color :=
        slider_knob_draw_style(knob, panel, mouse_input, pressed_knob)

    rl.DrawRectangleRec(track, BACKGROUND_COLOR)
    rl.DrawRectangleRec(
        rl.Rectangle{
            track.x,
            track.y,
            max(0.0, knob_center_x - track.x),
            track.height,
        },
        UI_BORDER_COLOR)
    rl.DrawRectangleRec(knob_draw, knob_color)

    view_core.ui_text(fmt.tprintf("%d", clamped),
        int(panel.x + panel.width - SETTINGS_PANEL_INSET - 32), int(row_y),
        UI_TEXT_COLOR, font)
}
