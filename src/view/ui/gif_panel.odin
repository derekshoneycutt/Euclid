package ui

import "../../core"

import "core:fmt"

import rl "vendor:raylib"

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
