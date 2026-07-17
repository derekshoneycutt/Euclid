package ui

import "../../core"
import view_core "../core"

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

//   Render particle render-count statistics in settings view.
draw_settings_particle_stats :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    ps: ^core.Particle_System,
    font: rl.Font) {

    stats_y := slider_track.y + SETTINGS_STATS_TOP_OFFSET
    ui_text(fmt.tprintf("Dust particles Rendered: %d", ps.last_render_low),
        int(panel.x + SETTINGS_PANEL_INSET), int(stats_y), UI_TEXT_COLOR, font)
    ui_text(fmt.tprintf("Trail particles Rendered: %d", ps.last_render_mid),
        int(panel.x + SETTINGS_PANEL_INSET), int(stats_y + SETTINGS_STATS_ROW_GAP),
        UI_TEXT_COLOR, font)
    ui_text(fmt.tprintf("Flicker particles Rendered: %d", ps.last_render_high),
        int(panel.x + SETTINGS_PANEL_INSET), int(stats_y + SETTINGS_STATS_ROW_GAP * 2),
        UI_TEXT_COLOR, font)
}

//   Render and handle the Display FPS toggle control.
draw_settings_fps_checkbox :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    mouse: rl.Vector2,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {

    row_y := slider_track.y + SETTINGS_TOGGLE_TOP_OFFSET
    box := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    label_x := box.x + box.width + SETTINGS_CHECKBOX_LABEL_GAP
    label := "Display FPS"

    hit := rl.Rectangle{
        box.x,
        row_y - 4,
        panel.width - SETTINGS_PANEL_INSET * 2,
        box.height + 8,
    }

    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, hit) {
        ui_runtime.display_fps = !ui_runtime.display_fps
    }

    rl.DrawRectangleLinesEx(box, 1, UI_BORDER_COLOR)
    if ui_runtime.display_fps {
        p0 := rl.Vector2{box.x + 3, box.y + box.height * 0.55}
        p1 := rl.Vector2{box.x + 6, box.y + box.height - 3}
        p2 := rl.Vector2{box.x + box.width - 3, box.y + 3}
        rl.DrawLineEx(p0, p1, 1.6, UI_TEXT_COLOR)
        rl.DrawLineEx(p1, p2, 1.6, UI_TEXT_COLOR)
    }

    ui_text(label, int(label_x), int(row_y - 1), UI_TEXT_COLOR, font)
}

//   Render and handle the Limit FPS toggle control.
draw_settings_limit_fps_checkbox :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    mouse: rl.Vector2,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {

    row_y := slider_track.y + SETTINGS_TOGGLE_TOP_OFFSET + 22
    box := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    label_x := box.x + box.width + SETTINGS_CHECKBOX_LABEL_GAP
    label := "Limit FPS"

    hit := rl.Rectangle{
        box.x,
        row_y - 4,
        panel.width - SETTINGS_PANEL_INSET * 2,
        box.height + 8,
    }

    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, hit) {
        ui_runtime.limit_fps = !ui_runtime.limit_fps
        if ui_runtime.limit_fps {
            rl.SetTargetFPS(LIMIT_FPS)
        } else {
            rl.SetTargetFPS(0)
        }
    }

    rl.DrawRectangleLinesEx(box, 1, UI_BORDER_COLOR)
    if ui_runtime.limit_fps {
        p0 := rl.Vector2{box.x + 3, box.y + box.height * 0.55}
        p1 := rl.Vector2{box.x + 6, box.y + box.height - 3}
        p2 := rl.Vector2{box.x + box.width - 3, box.y + 3}
        rl.DrawLineEx(p0, p1, 1.6, UI_TEXT_COLOR)
        rl.DrawLineEx(p1, p2, 1.6, UI_TEXT_COLOR)
    }

    ui_text(label, int(label_x), int(row_y - 1), UI_TEXT_COLOR, font)
}

//   Render and handle the SIMD batch projection toggle control.
draw_settings_simd_projection_checkbox :: proc(
    panel: rl.Rectangle,
    slider_track: rl.Rectangle,
    mouse: rl.Vector2,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {

    row_y := slider_track.y + SETTINGS_TOGGLE_TOP_OFFSET + 44
    box := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        SETTINGS_CHECKBOX_SIZE,
        SETTINGS_CHECKBOX_SIZE,
    }

    label_x := box.x + box.width + SETTINGS_CHECKBOX_LABEL_GAP
    is_available := view_core.simd_batch_projection_available()
    label := "Use SIMD Projection"
    if !is_available {
        label = "Use SIMD Projection (Unavailable)"
    }

    hit := rl.Rectangle{
        box.x,
        row_y - 4,
        panel.width - SETTINGS_PANEL_INSET * 2,
        box.height + 8,
    }

    if is_available && rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, hit) {
        ui_runtime.use_simd_batch_projection = !ui_runtime.use_simd_batch_projection
    }

    border := UI_BORDER_COLOR
    fg := UI_TEXT_COLOR
    if !is_available {
        border = rl.Color{78, 78, 78, 255}
        fg = rl.Color{110, 110, 110, 255}
        ui_runtime.use_simd_batch_projection = false
    }

    rl.DrawRectangleLinesEx(box, 1, border)
    if ui_runtime.use_simd_batch_projection {
        p0 := rl.Vector2{box.x + 3, box.y + box.height * 0.55}
        p1 := rl.Vector2{box.x + 6, box.y + box.height - 3}
        p2 := rl.Vector2{box.x + box.width - 3, box.y + 3}
        rl.DrawLineEx(p0, p1, 1.6, fg)
        rl.DrawLineEx(p1, p2, 1.6, fg)
    }

    ui_text(label, int(label_x), int(row_y - 1), fg, font)
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

//   Render and process the Save/Cancel GIF action button.
draw_settings_save_gif_button :: proc(
    panel: rl.Rectangle,
    row_y: f32,
    mouse: rl.Vector2,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {

    button := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        row_y,
        panel.width - SETTINGS_PANEL_INSET * 2,
        SETTINGS_GIF_BUTTON_HEIGHT,
    }

    is_armed := ui_runtime.gif_capture_phase == .Armed
    disabled := ui_runtime.gif_capture_phase == .Recording ||
        ui_runtime.gif_capture_phase == .Finalizing
    hovered := rl.CheckCollisionPointRec(mouse, button)
    pressed := hovered && rl.IsMouseButtonDown(.LEFT)

    bg := BACKGROUND_COLOR
    fg := UI_TEXT_COLOR
    border := UI_BORDER_COLOR

    if disabled {
        bg = rl.Color{48, 48, 48, 255}
        fg = rl.Color{110, 110, 110, 255}
        border = rl.Color{78, 78, 78, 255}
    } else if pressed {
        bg = UI_BORDER_COLOR
        fg = BACKGROUND_COLOR
        border = UI_BORDER_COLOR
    } else if hovered {
        bg = UI_COMPONENT_BACKGROUND_COLOR
    }

    rl.DrawRectangleRec(button, bg)
    rl.DrawRectangleLinesEx(button, 1, border)
    button_text := "Save Gif"
    if is_armed {
        button_text = "Cancel Gif"
    }
    ui_text(button_text, int(button.x + 8), int(button.y + 3), fg, font)

    if !disabled && rl.IsMouseButtonPressed(.LEFT) && hovered {
        ui_runtime.save_gif_requested = true
    }
}

//   Return human-readable status text for GIF capture phase.
gif_capture_status_label :: proc(ui_runtime: ^core.Euclid_UI_Runtime_State) -> string {
    switch ui_runtime.gif_capture_phase {
    case .Idle:
        return "Status: Idle"
    case .Armed:
        return "Status: Armed"
    case .Recording:
        return fmt.tprintf("Status: Recording (%d frames)", ui_runtime.gif_captured_frames)
    case .Finalizing:
        return "Status: Saving"
    case .Saved:
        return "Status: Saved"
    case .Error:
        return "Status: Error"
    }

    return "Status: Idle"
}

//   Render GIF capture status and last output path when available.
draw_settings_gif_status :: proc(
    panel: rl.Rectangle,
    row_y: f32,
    ui_runtime: ^core.Euclid_UI_Runtime_State,
    font: rl.Font) {

    ui_text(gif_capture_status_label(ui_runtime),
        int(panel.x + SETTINGS_PANEL_INSET), int(row_y), UI_TEXT_COLOR, font)

    if ui_runtime.gif_status_note_len > 0 {
        note_text := string(ui_runtime.gif_status_note[:ui_runtime.gif_status_note_len])
        ui_text(note_text,
            int(panel.x + SETTINGS_PANEL_INSET), int(row_y + 18), UI_TEXT_COLOR, font)
    }

    if ui_runtime.gif_capture_phase == .Saved && ui_runtime.last_gif_path_len > 0 {
        path_text := string(ui_runtime.last_gif_path[:ui_runtime.last_gif_path_len])
        ui_text(fmt.tprintf("Path: %s", path_text),
            int(panel.x + SETTINGS_PANEL_INSET), int(row_y + 36), UI_TEXT_COLOR, font)
    }
}

//   Render full settings panel and wire all settings controls.
draw_settings_view :: proc(
    state: ^core.Euclid_General_State, panel: rl.Rectangle, mouse: rl.Vector2) {

    if state == nil || state.particle_system == nil {
        return
    }

    ps := state.particle_system
    ui_runtime := &state.ui_runtime
    font := state.font

    rl.DrawRectangleRec(panel, UI_COMPONENT_BACKGROUND_COLOR)
    rl.DrawRectangleLinesEx(panel, 1, UI_BORDER_COLOR)

    header_y := int(panel.y + SETTINGS_HEADER_TOP_OFFSET)
    ui_text("Settings", int(panel.x + SETTINGS_PANEL_INSET), header_y, UI_TEXT_COLOR, font)

    slider_label_y, slider_track, slider_hit := build_settings_slider_layout(panel)
    ui_text("Maximum Dust particles",
        int(panel.x + SETTINGS_PANEL_INSET), int(slider_label_y), UI_TEXT_COLOR, font)

    max_particles := core.MAX_LOW_PARTICLES
    ps.use_max_dust_particles = clamp(ps.use_max_dust_particles, 0, max_particles)

    ratio := slider_value_ratio(ps.use_max_dust_particles, max_particles)
    knob_center_x, knob := build_slider_knob(slider_track, ratio)

    update_use_max_particles_slider(ps, ui_runtime, mouse, max_particles,
        slider_track, slider_hit, knob, knob_center_x)

    ratio = slider_value_ratio(ps.use_max_dust_particles, max_particles)
    knob_center_x, knob = build_slider_knob(slider_track, ratio)

    draw_use_max_particles_slider(panel, slider_track, knob_center_x, knob,
        ps.use_max_dust_particles, max_particles, font)
    draw_settings_particle_stats(panel, slider_track, ps, font)
    draw_settings_fps_checkbox(panel, slider_track, mouse, ui_runtime, font)
    draw_settings_limit_fps_checkbox(panel, slider_track, mouse, ui_runtime, font)
    draw_settings_simd_projection_checkbox(panel, slider_track, mouse, ui_runtime, font)
}

//   Render dedicated GIF panel and wire GIF controls.
draw_gif_view :: proc(
    state: ^core.Euclid_General_State, panel: rl.Rectangle, mouse: rl.Vector2) {

    if state == nil || state.particle_system == nil {
        return
    }

    ui_runtime := &state.ui_runtime
    font := state.font

    rl.DrawRectangleRec(panel, UI_COMPONENT_BACKGROUND_COLOR)
    rl.DrawRectangleLinesEx(panel, 1, UI_BORDER_COLOR)

    gif_section_y := panel.y + SETTINGS_HEADER_TOP_OFFSET
    ui_text("GIF Export",
        int(panel.x + SETTINGS_PANEL_INSET), int(gif_section_y), UI_TEXT_COLOR, font)

    draw_settings_integer_slider(panel,
        gif_section_y + SETTINGS_GIF_SLIDER_ROW_GAP, mouse, "Downsample",
        &ui_runtime.gif_downsample_factor, 1, 4, font)

    draw_settings_integer_slider(panel,
        gif_section_y + SETTINGS_GIF_SLIDER_ROW_GAP * 2, mouse, "Frame Step",
        &ui_runtime.gif_frame_step, 1, 4, font)

    draw_settings_save_gif_button(panel,
        gif_section_y + SETTINGS_GIF_BUTTON_TOP_OFFSET, mouse, ui_runtime, font)

    draw_settings_gif_status(panel,
        gif_section_y + SETTINGS_GIF_STATUS_TOP_OFFSET, ui_runtime, font)
}
