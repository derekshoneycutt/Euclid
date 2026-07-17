package ui

import "../../core"
import view_core "../core"

import "core:fmt"

import rl "vendor:raylib"

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

