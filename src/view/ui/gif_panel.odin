package ui

import native "../native"

import viewmodel "../model"

import "../../core"
import view_core "../core"
import view_font "../font"

import "core:fmt"

import rl "vendor:raylib"

//   Row y-positions for the GIF panel's two sliders.
Gif_Slider_Rows :: struct {
    downsample_y: f32,
    frame_step_y: f32,
}

//   Shared dependencies for controls in one GIF panel frame.
Gif_Panel_Context :: struct {
    panel: rl.Rectangle,
    mouse_input: Input_Frame,
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    font: rl.Font,
    resolver: view_font.Font_Resolver,
}

//   Row positions for all controls in one GIF panel layout.
Gif_View_Rows :: struct {
    sliders: Gif_Slider_Rows,
    save_button_y: f32,
    status_y: f32,
}

//   Fixed prepared interaction results for all GIF panel controls.
Gif_View_Preparation :: struct {
    rows: Gif_View_Rows,
    downsample: Integer_Slider_Result,
    frame_step: Integer_Slider_Result,
    save_button: Text_Button_Result,
}

//   Build one GIF slider parameter record shared by update and draw.
gif_slider_params :: proc(
    ctx: Gif_Panel_Context,
    row_y: f32,
    press_id: int,
    label: string,
    value: ^int) -> Integer_Slider_Params {
    return {
        panel = ctx.panel, row_y = row_y, mouse_input = ctx.mouse_input,
        ui_runtime = ctx.ui_runtime, press_id = press_id, label = label,
        value = value, min_value = 1, max_value = 4, font = ctx.font,
        font_resolver = ctx.resolver,
    }
}

//   Build the GIF save/cancel button parameters shared by update and draw.
gif_save_button_params :: proc(
    ctx: Gif_Panel_Context,
    row_y: f32) -> Text_Button_Params {
    is_armed := ctx.ui_runtime.gif_capture_phase == .Armed
    disabled := ctx.ui_runtime.gif_capture_phase == .Recording ||
        ctx.ui_runtime.gif_capture_phase == .Finalizing
    button_text := "Save Gif"
    if is_armed { button_text = "Cancel Gif" }
    return {
        id = 3001,
        rect = {ctx.panel.x + SETTINGS_PANEL_INSET, row_y,
            ctx.panel.width - SETTINGS_PANEL_INSET * 2,
            SETTINGS_GIF_BUTTON_HEIGHT},
        label = button_text, enabled = !disabled, mouse = ctx.mouse_input,
        interaction_space_rect = ctx.panel, interaction_enabled = true,
        font = ctx.font, font_resolver = ctx.resolver,
    }
}

//   Return human-readable status text for GIF capture phase.
gif_capture_status_label :: proc(
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> string {
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

//   Draw one status row using the GIF panel's shared typeface and resolver.
draw_gif_status_text :: proc(
    ctx: Gif_Panel_Context, text: string, row_y: f32) {
    view_core.ui_text_shaped({
        resolver = ctx.resolver,
        key = .Regular,
        text = text,
        position = {ctx.panel.x + SETTINGS_PANEL_INSET, row_y},
        color = native.to_raylib_color(UI_TEXT_COLOR),
        font = view_core.ui_text_font(ctx.font),
    })
}

//   Render GIF capture status and last output path when available.
draw_settings_gif_status :: proc(ctx: Gif_Panel_Context, row_y: f32) {
    ui_runtime := ctx.ui_runtime
    draw_gif_status_text(ctx, gif_capture_status_label(ui_runtime), row_y)

    if ui_runtime.gif_status_note_len > 0 {
        note_text := string(ui_runtime.gif_status_note[:ui_runtime.gif_status_note_len])
        draw_gif_status_text(ctx, note_text,
            row_y + SETTINGS_GIF_STATUS_NOTE_ROW_OFFSET)
    }

    if ui_runtime.gif_capture_phase == .Saved && ui_runtime.last_gif_path_len > 0 {
        path_text := string(ui_runtime.last_gif_path[:ui_runtime.last_gif_path_len])
        draw_gif_status_text(ctx, fmt.tprintf("Path: %s", path_text),
            row_y + SETTINGS_GIF_STATUS_PATH_ROW_OFFSET)
    }
}

//   Place one fixed-size GIF settings row and return it with the advanced cursor.
gif_stack_row :: #force_inline proc(
    rect: rl.Rectangle, segment_size: f32,
    cursor: Stack_Panel_Cursor) -> Stack_Panel_Result {

    return stack_panel_place_segment(Stack_Panel_Params{
        origin_x = rect.x,
        origin_y = rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = rect,
        can_expand = false,
        segment_size_is_set = true,
        segment_size = segment_size,
        cursor_in = cursor,
    })
}

//   Lay out all GIF panel rows from one inset stack rectangle.
gif_view_layout_rows :: proc(stack_rect: rl.Rectangle) -> Gif_View_Rows {
    stack_cursor := stack_panel_cursor_zero()
    stack_cursor.offset = SETTINGS_GIF_FRAME_STEP_SEGMENT_SIZE
    downsample_row := gif_stack_row(stack_rect,
        SETTINGS_GIF_FRAME_STEP_SEGMENT_SIZE, stack_cursor)
    frame_step_row := gif_stack_row(stack_rect,
        SETTINGS_GIF_FRAME_TO_BUTTON_SEGMENT_SIZE, downsample_row.cursor_out)
    save_button_row := gif_stack_row(stack_rect,
        SETTINGS_GIF_BUTTON_TO_STATUS_SEGMENT_SIZE, frame_step_row.cursor_out)
    status_row := gif_stack_row(stack_rect, 0, save_button_row.cursor_out)
    return {
        sliders = {downsample_row.segment_rect.y, frame_step_row.segment_rect.y},
        save_button_y = save_button_row.segment_rect.y,
        status_y = status_row.segment_rect.y,
    }
}

//   Resolve GIF controls and commit their action before rendering.
prepare_gif_view :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Input_Frame) -> Gif_View_Preparation {
    if state == nil || state.particle_system == nil { return {} }
    ctx := Gif_Panel_Context{panel, mouse_input, &state.ui_runtime,
        view_font.cache_borrow(&state.font_cache, .Regular),
        view_font.cache_terminal_resolver(&state.font_cache)}
    stack_rect := rl.Rectangle{panel.x + SETTINGS_PANEL_INSET,
        panel.y + SETTINGS_HEADER_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        panel.height - SETTINGS_HEADER_TOP_OFFSET}
    result := Gif_View_Preparation{rows = gif_view_layout_rows(stack_rect)}
    result.downsample = update_settings_integer_slider(gif_slider_params(
        ctx, result.rows.sliders.downsample_y, 6201, "Downsample",
        &ctx.ui_runtime.gif_downsample_factor))
    result.frame_step = update_settings_integer_slider(gif_slider_params(
        ctx, result.rows.sliders.frame_step_y, 6202, "Frame Step",
        &ctx.ui_runtime.gif_frame_step))
    result.save_button = update_text_button(gif_save_button_params(
        ctx, result.rows.save_button_y), &ctx.ui_runtime.ui_press_owner)
    if result.save_button.clicked { ctx.ui_runtime.save_gif_requested = true }
    return result
}

//   Render dedicated GIF panel and wire GIF controls.
draw_gif_view :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Input_Frame,
    prepared: Gif_View_Preparation) {

    if state == nil || state.particle_system == nil {
        return
    }

    ui_runtime := &state.ui_runtime
    regular_font := view_font.cache_borrow(&state.font_cache, .Regular)
    resolver := view_font.cache_terminal_resolver(&state.font_cache)
    ctx := Gif_Panel_Context{
        panel, mouse_input, ui_runtime, regular_font, resolver}

    _ = draw_container(panel, .Grey)

    draw_settings_integer_slider_prepared(gif_slider_params(ctx,
        prepared.rows.sliders.downsample_y, 6201, "Downsample",
        &ctx.ui_runtime.gif_downsample_factor), prepared.downsample)
    draw_settings_integer_slider_prepared(gif_slider_params(ctx,
        prepared.rows.sliders.frame_step_y, 6202, "Frame Step",
        &ctx.ui_runtime.gif_frame_step), prepared.frame_step)
    draw_text_button_prepared(gif_save_button_params(ctx,
        prepared.rows.save_button_y), prepared.save_button)
    draw_settings_gif_status(ctx, prepared.rows.status_y)
}
