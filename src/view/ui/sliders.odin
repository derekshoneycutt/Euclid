package ui

import "../../core"

import "core:fmt"
import "core:math"

import rl "vendor:raylib"

//   Compute label, track, and hit rectangles for the dust slider.
build_settings_slider_layout :: proc(panel: rl.Rectangle) -> (f32, rl.Rectangle, rl.Rectangle) {
    slider_label_y := panel.y + SETTINGS_SLIDER_LABEL_TOP_OFFSET

    slider_track := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        slider_label_y + SETTINGS_TRACK_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        SETTINGS_TRACK_HEIGHT,
    }

    slider_hit := rl.Rectangle{
        slider_track.x,
        slider_track.y - SETTINGS_TRACK_HIT_PAD_Y,
        slider_track.width,
        slider_track.height + SETTINGS_TRACK_HIT_PAD_Y * 2,
    }

    return slider_label_y, slider_track, slider_hit
}

//   Convert an integer slider value into normalized [0,1] ratio.
slider_value_ratio :: proc(value, max_value: int) -> f32 {
    if max_value <= 0 {
        return 0
    }
    return f32(value) / f32(max_value)
}

//   Build knob geometry from track bounds and normalized ratio.
build_slider_knob :: proc(slider_track: rl.Rectangle, ratio: f32) -> (f32, rl.Rectangle) {
    knob_center_x := slider_track.x + ratio * slider_track.width
    knob := rl.Rectangle{
        knob_center_x - SETTINGS_KNOB_WIDTH * 0.5,
        slider_track.y - SETTINGS_KNOB_PAD_Y,
        SETTINGS_KNOB_WIDTH,
        slider_track.height + SETTINGS_KNOB_PAD_Y * 2,
    }
    return knob_center_x, knob
}

//   Apply wheel/drag input to update max dust particle setting.
update_use_max_particles_slider :: proc(
    ps: ^core.Particle_System,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    mouse: rl.Vector2,
    max_particles: int,
    slider_track: rl.Rectangle,
    slider_hit: rl.Rectangle,
    knob: rl.Rectangle,
    knob_center_x: f32) {

    if !rl.IsMouseButtonDown(.LEFT) {
        ui_runtime.settings_slider_dragging = false
    }

    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, knob) {
        ui_runtime.settings_slider_dragging = true
        ui_runtime.settings_slider_drag_offset_x = mouse.x - knob_center_x
    }

    slider_hovered := rl.CheckCollisionPointRec(mouse, slider_hit)
    if slider_hovered {
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            step := max(1, max_particles / 64)
            delta := int(math.round(f64(wheel * f32(step))))
            if delta == 0 {
                if wheel > 0 {
                    delta = step
                } else {
                    delta = -step
                }
            }

            next_value := ps.use_max_dust_particles + delta
            ps.use_max_dust_particles = clamp(next_value, 0, max_particles)
        }
    }

    if slider_track.width > 0 && ui_runtime.settings_slider_dragging &&
        rl.IsMouseButtonDown(.LEFT) {

        knob_target_x := mouse.x - ui_runtime.settings_slider_drag_offset_x
        t_drag := clamp((knob_target_x - slider_track.x) / slider_track.width, 0, 1)
        next_value := int(t_drag * f32(max_particles) + 0.5)
        ps.use_max_dust_particles = clamp(next_value, 0, max_particles)
    }
}

//   Render dust-capacity slider fill, knob, and value text.
draw_use_max_particles_slider :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    knob_center_x: f32,
    knob: rl.Rectangle,
    current_value: int,
    max_particles: int,
    font: rl.Font) {
    rl.DrawRectangleRec(slider_track, BACKGROUND_COLOR)
    rl.DrawRectangleRec(rl.Rectangle{
        slider_track.x,
        slider_track.y,
        max(0.0, knob_center_x - slider_track.x),
        slider_track.height,
    }, UI_BORDER_COLOR)
    rl.DrawRectangleRec(knob, UI_TEXT_COLOR)

    use_max_text := fmt.tprintf("%d / %d", current_value, max_particles)
    ui_text(use_max_text, int(panel.x + SETTINGS_PANEL_INSET),
        int(slider_track.y + SETTINGS_VALUE_TOP_OFFSET), UI_TEXT_COLOR, font)
}

//   Render and update a reusable integer slider control.
draw_settings_integer_slider :: proc(
    panel: rl.Rectangle,
    row_y: f32,
    mouse: rl.Vector2,
    label: string,
    value: ^int,
    min_value, max_value: int,
    font: rl.Font) {

    ui_text(label, int(panel.x + SETTINGS_PANEL_INSET), int(row_y), UI_TEXT_COLOR, font)

    track := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y + SETTINGS_TRACK_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        SETTINGS_TRACK_HEIGHT,
    }

    hit := rl.Rectangle{
        track.x,
        track.y - SETTINGS_TRACK_HIT_PAD_Y,
        track.width,
        track.height + SETTINGS_TRACK_HIT_PAD_Y * 2,
    }

    clamped := clamp(value^, min_value, max_value)
    denom := max(1, max_value - min_value)
    ratio := f32(clamped - min_value) / f32(denom)
    knob_center_x, knob := build_slider_knob(track, ratio)

    if rl.CheckCollisionPointRec(mouse, hit) {
        wheel := rl.GetMouseWheelMove()
        if wheel != 0 {
            delta := 1
            if wheel < 0 {
                delta = -1
            }
            clamped = clamp(clamped + delta, min_value, max_value)
        }
    }

    if rl.IsMouseButtonDown(.LEFT) && rl.CheckCollisionPointRec(mouse, hit) {
        if track.width > 0 {
            t := clamp((mouse.x - track.x) / track.width, 0, 1)
            clamped = clamp(min_value + int(t * f32(denom) + 0.5), min_value, max_value)
        }
    }

    value^ = clamped

    ratio = f32(clamped - min_value) / f32(denom)
    knob_center_x, knob = build_slider_knob(track, ratio)

    rl.DrawRectangleRec(track, BACKGROUND_COLOR)
    rl.DrawRectangleRec(
        rl.Rectangle{
            track.x,
            track.y,
            max(0.0, knob_center_x - track.x),
            track.height,
        },
        UI_BORDER_COLOR)
    rl.DrawRectangleRec(knob, UI_TEXT_COLOR)

    ui_text(fmt.tprintf("%d", clamped),
        int(panel.x + panel.width - SETTINGS_PANEL_INSET - 18), int(row_y),
        UI_TEXT_COLOR, font)
}
