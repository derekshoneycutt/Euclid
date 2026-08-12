package ui

import "../../core"
import view_core "../core"

import "core:fmt"

import rl "vendor:raylib"

//   Render and process the Save/Cancel GIF action button.
draw_settings_save_gif_button :: proc(
    panel: rl.Rectangle,
    row_y: f32,
    mouse_input: Mouse_Input_State,
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

    button_text := "Save Gif"
    if is_armed {
        button_text = "Cancel Gif"
    }

    button_result := draw_text_button(Text_Button_Params{
        id = 3001,
        rect = button,
        label = button_text,
        enabled = !disabled,
        mouse = mouse_input,
        scroll_offset = rl.Vector2{},
        interaction_space_rect = panel,
        interaction_enabled = true,
        font = font,
        has_font_color_override = false,
        font_color_override = rl.Color{},
    }, &ui_runtime.ui_press_owner)

    if button_result.clicked {
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
        return fmt.tprintf("Status: Recording (%d frames)",
            ui_runtime.gif_captured_frames)
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

    view_core.ui_text(gif_capture_status_label(ui_runtime),
        int(panel.x + SETTINGS_PANEL_INSET), int(row_y), UI_TEXT_COLOR, font)

    if ui_runtime.gif_status_note_len > 0 {
        note_text := string(ui_runtime.gif_status_note[:ui_runtime.gif_status_note_len])
        view_core.ui_text(note_text,
            int(panel.x + SETTINGS_PANEL_INSET),
            int(row_y + SETTINGS_GIF_STATUS_NOTE_ROW_OFFSET),
            UI_TEXT_COLOR,
            font)
    }

    if ui_runtime.gif_capture_phase == .Saved && ui_runtime.last_gif_path_len > 0 {
        path_text := string(ui_runtime.last_gif_path[:ui_runtime.last_gif_path_len])
        view_core.ui_text(fmt.tprintf("Path: %s", path_text),
            int(panel.x + SETTINGS_PANEL_INSET),
            int(row_y + SETTINGS_GIF_STATUS_PATH_ROW_OFFSET),
            UI_TEXT_COLOR,
            font)
    }
}

//   Render dedicated GIF panel and wire GIF controls.
draw_gif_view :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Mouse_Input_State) {

    if state == nil || state.particle_system == nil {
        return
    }

    ui_runtime := &state.ui_runtime
    font := state.font

    _ = draw_container(panel, .Grey)

    gif_section_y := panel.y + SETTINGS_HEADER_TOP_OFFSET
    view_core.ui_text("GIF Export",
        int(panel.x + SETTINGS_PANEL_INSET), int(gif_section_y), UI_TEXT_COLOR, font)

    stack_rect := rl.Rectangle{
        panel.x + SETTINGS_PANEL_INSET,
        gif_section_y,
        panel.width - SETTINGS_PANEL_INSET * 2,
        panel.height - SETTINGS_HEADER_TOP_OFFSET,
    }

    stack_cursor := stack_panel_cursor_zero()
    stack_cursor.offset = SETTINGS_GIF_FRAME_STEP_SEGMENT_SIZE

    downsample_row := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = stack_rect.x,
        origin_y = stack_rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = stack_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = SETTINGS_GIF_FRAME_STEP_SEGMENT_SIZE,
        cursor_in = stack_cursor,
    })
    stack_cursor = downsample_row.cursor_out

    frame_step_row := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = stack_rect.x,
        origin_y = stack_rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = stack_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = SETTINGS_GIF_FRAME_TO_BUTTON_SEGMENT_SIZE,
        cursor_in = stack_cursor,
    })
    stack_cursor = frame_step_row.cursor_out

    save_button_row := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = stack_rect.x,
        origin_y = stack_rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = stack_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = SETTINGS_GIF_BUTTON_TO_STATUS_SEGMENT_SIZE,
        cursor_in = stack_cursor,
    })
    stack_cursor = save_button_row.cursor_out

    status_row := stack_panel_place_segment(Stack_Panel_Params{
        origin_x = stack_rect.x,
        origin_y = stack_rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = stack_rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = 0,
        cursor_in = stack_cursor,
    })

    draw_settings_integer_slider(Integer_Slider_Params{
        panel = panel,
        row_y = downsample_row.segment_rect.y,
        mouse_input = mouse_input,
        ui_runtime = ui_runtime,
        press_id = 6201,
        label = "Downsample",
        value = &ui_runtime.gif_downsample_factor,
        min_value = 1,
        max_value = 4,
        font = font,
    })

    draw_settings_integer_slider(Integer_Slider_Params{
        panel = panel,
        row_y = frame_step_row.segment_rect.y,
        mouse_input = mouse_input,
        ui_runtime = ui_runtime,
        press_id = 6202,
        label = "Frame Step",
        value = &ui_runtime.gif_frame_step,
        min_value = 1,
        max_value = 4,
        font = font,
    })

    draw_settings_save_gif_button(panel,
        save_button_row.segment_rect.y, mouse_input, ui_runtime, font)

    draw_settings_gif_status(panel,
        status_row.segment_rect.y, ui_runtime, font)
}
