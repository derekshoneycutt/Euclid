package ui

import native "../native"

import viewmodel "../model"

import "../../core"
import geometry "../../core/geometry"
import view_core "../core"
import view_font "../font"

import "core:fmt"

//   Row y-positions for the GIF panel's two sliders.
Gif_Slider_Rows :: struct {
    downsample_y: f32,
    frame_step_y: f32,
}

//   Shared dependencies for controls in one GIF panel frame.
Gif_Panel_Context :: struct {
    panel: geometry.Rectangle,
    mouse_input: Input_Frame,
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    font: view_font.Font_Face,
    resolver: view_font.Font_Resolver,
}

//   Row positions for all controls in one GIF panel layout.
Gif_View_Rows :: struct {
    sliders: Gif_Slider_Rows,
    timing_y: f32,
    save_button_y: f32,
    status_y: f32,
}

//   Fixed prepared interaction results for all GIF panel controls.
Gif_View_Preparation :: struct {
    rows: Gif_View_Rows,
    downsample: Integer_Slider_Result,
    frame_step: Integer_Slider_Result,
    animation_timing: Text_Button_Result,
    recorded_timing: Text_Button_Result,
    timing_mode: viewmodel.Gif_Capture_Timing_Mode,
    save_button: Text_Button_Result,
    phase: viewmodel.Gif_Capture_Phase,
    captured_frames: int,
    status_note: [260]u8,
    status_note_len: int,
    last_path: [260]u8,
    last_path_len: int,
}

// draw_encoded_gif_geometry encodes GIF controls while capture stays deferred.
draw_encoded_gif_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle) {
    if state == nil {return}
    stack_rect := geometry.Rectangle{panel.x + SETTINGS_PANEL_INSET,
        panel.y + SETTINGS_HEADER_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        panel.height - SETTINGS_HEADER_TOP_OFFSET}
    rows := gif_view_layout_rows(stack_rect)
    draw_encoded_slider_geometry(encoder, {panel, rows.sliders.downsample_y,
        state^.ui_runtime.gif_downsample_factor, 1, 4})
    draw_encoded_slider_geometry(encoder, {panel, rows.sliders.frame_step_y,
        state^.ui_runtime.gif_frame_step, 1, 4})
    animation, recorded := gif_timing_button_rects(panel, rows.timing_y)
    if state^.ui_runtime.gif_timing_mode == .Animation {
        _ = native.draw_encoder_rectangle(encoder, animation, UI_BORDER_COLOR)
    } else {
        _ = native.draw_encoder_rectangle(encoder, recorded, UI_BORDER_COLOR)
    }
    _ = native.draw_encoder_rectangle_outline(encoder, animation, 1, UI_BORDER_COLOR)
    _ = native.draw_encoder_rectangle_outline(encoder, recorded, 1, UI_BORDER_COLOR)
    button := geometry.Rectangle{panel.x + SETTINGS_PANEL_INSET, rows.save_button_y,
        panel.width - SETTINGS_PANEL_INSET * 2, SETTINGS_GIF_BUTTON_HEIGHT}
    _ = native.draw_encoder_rectangle(
        encoder, geometry.Rectangle(button), UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, geometry.Rectangle(button), 1, UI_BORDER_COLOR)
}

// draw_encoded_gif_text emits capture controls while readback remains deferred.
draw_encoded_gif_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle, prepared: Gif_View_Preparation) {
    stack := geometry.Rectangle{panel.x + SETTINGS_PANEL_INSET,
        panel.y + SETTINGS_HEADER_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        panel.height - SETTINGS_HEADER_TOP_OFFSET}
    rows := gif_view_layout_rows(stack)
    x := panel.x + SETTINGS_PANEL_INSET
    draw_encoded_label(state, encoder, "Output scale", x, rows.sliders.downsample_y)
    draw_encoded_gif_value(
        state, encoder, panel, gif_output_scale_label(prepared.downsample.value),
        rows.sliders.downsample_y)
    draw_encoded_label(state, encoder, "Capture every", x, rows.sliders.frame_step_y)
    draw_encoded_gif_value(
        state, encoder, panel, gif_capture_cadence_label(prepared.frame_step.value),
        rows.sliders.frame_step_y)
    draw_encoded_label(state, encoder, "Playback timing", x, rows.timing_y)
    animation, recorded := gif_timing_button_rects(panel, rows.timing_y)
    draw_encoded_gif_button_text(state, encoder, "Animation", animation)
    draw_encoded_gif_button_text(state, encoder, "Recorded", recorded)
    draw_encoded_label(state, encoder, gif_capture_button_label(prepared.phase),
        x + SETTINGS_PANEL_INSET, rows.save_button_y + SETTINGS_PANEL_INSET)
    draw_encoded_gif_status(state, encoder, prepared, x, rows.status_y)
}

// draw_encoded_gif_status emits prepared phase, note, and published-path rows.
draw_encoded_gif_status :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Gif_View_Preparation, x, row_y: f32) {
    draw_encoded_label(state, encoder,
        gif_capture_status_label(prepared.phase, prepared.captured_frames),
        x, row_y)
    if prepared.status_note_len > 0 {
        status_note := prepared.status_note
        note := string(status_note[:prepared.status_note_len])
        draw_encoded_label(state, encoder, note,
            x, row_y + SETTINGS_GIF_STATUS_NOTE_ROW_OFFSET)
    }
    if prepared.phase == .Saved && prepared.last_path_len > 0 {
        last_path := prepared.last_path
        path := string(last_path[:prepared.last_path_len])
        draw_encoded_label(state, encoder, fmt.tprintf("Path: %s", path),
            x, row_y + SETTINGS_GIF_STATUS_PATH_ROW_OFFSET)
    }
}

// draw_encoded_gif_value right-aligns one prepared slider value in the panel.
draw_encoded_gif_value :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle, text: string, row_y: f32) {
    face := view_font.cache_borrow(&state^.font_cache, .Regular)
    width, measured := view_core.ui_text_measure_monospace(
        text, face, TREE_FONT_SIZE, 0)
    if !measured {width = 20}
    draw_encoded_label(state, encoder, text,
        settings_right_aligned_x(panel, width), row_y)
}

// gif_output_scale_label describes one integer downsample factor as output scale.
gif_output_scale_label :: proc(factor: int) -> string {
    switch clamp(factor, 1, 4) {
    case 1: return "100%"
    case 2: return "50%"
    case 3: return "33%"
    case 4: return "25%"
    }
    return "100%"
}

// gif_capture_cadence_label describes how often one presentation is sampled.
gif_capture_cadence_label :: proc(frame_step: int) -> string {
    clamped := clamp(frame_step, 1, 4)
    if clamped == 1 {return "frame"}
    return fmt.tprintf("%d frames", clamped)
}

// gif_timing_button_rects divides one row into two stable timing choices.
gif_timing_button_rects :: proc(
    panel: geometry.Rectangle, row_y: f32) -> (geometry.Rectangle, geometry.Rectangle) {
    available := panel.width - SETTINGS_PANEL_INSET * 2 -
        SETTINGS_GIF_TIMING_BUTTON_GAP
    width := max(f32(0), available * 0.5)
    y := row_y + SETTINGS_GIF_TIMING_BUTTON_TOP_OFFSET
    animation := geometry.Rectangle{panel.x + SETTINGS_PANEL_INSET, y,
        width, SETTINGS_GIF_BUTTON_HEIGHT}
    recorded := geometry.Rectangle{animation.x + width +
        SETTINGS_GIF_TIMING_BUTTON_GAP, y, width, SETTINGS_GIF_BUTTON_HEIGHT}
    return animation, recorded
}

// draw_encoded_gif_button_text centers one timing choice in its segment.
draw_encoded_gif_button_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    text: string, rectangle: geometry.Rectangle) {
    face := view_font.cache_borrow(&state^.font_cache, .Regular)
    width, measured := view_core.ui_text_measure_monospace(
        text, face, TREE_FONT_SIZE, 0)
    if !measured {width = 0}
    draw_encoded_label(state, encoder, text,
        rectangle.x + max(f32(0), (rectangle.width - width) * 0.5),
        rectangle.y + (rectangle.height - TREE_FONT_SIZE) * 0.5)
}

//   Build one GIF slider parameter record shared by update and draw.
gif_slider_params :: proc(
    ctx: Gif_Panel_Context,
    row_y: f32,
    press_id: int,
    label: string,
    value: ^int) -> Integer_Slider_Params {
    return {
        panel = geometry.Rectangle(ctx.panel), row_y = row_y,
        mouse_input = ctx.mouse_input,
        ui_runtime = ctx.ui_runtime, press_id = press_id, label = label,
        value = value, min_value = 1, max_value = 4, font = ctx.font,
        font_resolver = ctx.resolver,
    }
}

//   Build the GIF save/cancel button parameters shared by update and draw.
gif_save_button_params :: proc(
    ctx: Gif_Panel_Context,
    row_y: f32) -> Text_Button_Params {
    phase := ctx.ui_runtime.gif_capture_phase
    return {
        id = 3001,
        rect = {ctx.panel.x + SETTINGS_PANEL_INSET, row_y,
            ctx.panel.width - SETTINGS_PANEL_INSET * 2,
            SETTINGS_GIF_BUTTON_HEIGHT},
        label = gif_capture_button_label(phase),
        enabled = gif_capture_button_enabled(phase), mouse = ctx.mouse_input,
        interaction_space_rect = geometry.Rectangle(ctx.panel),
        interaction_enabled = true,
        font = ctx.font, font_resolver = ctx.resolver,
    }
}

// gif_timing_button_params builds one choice in the timing selector.
gif_timing_button_params :: proc(
    ctx: Gif_Panel_Context, id: int, label: string,
    rectangle: geometry.Rectangle) -> Text_Button_Params {
    return {
        id = id, rect = rectangle, label = label,
        enabled = gif_capture_button_enabled(ctx.ui_runtime.gif_capture_phase),
        mouse = ctx.mouse_input, interaction_space_rect = ctx.panel,
        interaction_enabled = true, font = ctx.font, font_resolver = ctx.resolver,
    }
}

// gif_capture_button_label describes the action or active work for one phase.
gif_capture_button_label :: proc(phase: viewmodel.Gif_Capture_Phase) -> string {
    switch phase {
    case .Armed:
        return "Cancel GIF"
    case .Recording:
        return "Recording..."
    case .Finalizing:
        return "Saving..."
    case .Idle, .Saved, .Error:
        return "Save GIF"
    }
    return "Save GIF"
}

// gif_capture_button_enabled reports whether one phase accepts button input.
gif_capture_button_enabled :: #force_inline proc(
    phase: viewmodel.Gif_Capture_Phase) -> bool {
    return phase != .Recording && phase != .Finalizing
}

//   Return human-readable status text for one prepared GIF capture phase.
gif_capture_status_label :: proc(
    phase: viewmodel.Gif_Capture_Phase, captured_frames: int) -> string {
    switch phase {
    case .Idle:
        return "Status: Idle"
    case .Armed:
        return "Status: Armed"
    case .Recording:
        return fmt.tprintf("Status: Recording (%d frames)",
            captured_frames)
    case .Finalizing:
        return "Status: Saving"
    case .Saved:
        return "Status: Saved"
    case .Error:
        return "Status: Error"
    }

    return "Status: Idle"
}

//   Place one fixed-size GIF settings row and return it with the advanced cursor.
gif_stack_row :: #force_inline proc(
    rect: geometry.Rectangle, segment_size: f32,
    cursor: Stack_Panel_Cursor) -> Stack_Panel_Result {

    return stack_panel_place_segment(Stack_Panel_Params{
        origin_x = rect.x,
        origin_y = rect.y,
        axis = .Y,
        direction_sign = 1,
        rect = geometry.Rectangle(rect),
        can_expand = false,
        segment_size_is_set = true,
        segment_size = segment_size,
        cursor_in = cursor,
    })
}

//   Lay out all GIF panel rows from one inset stack rectangle.
gif_view_layout_rows :: proc(stack_rect: geometry.Rectangle) -> Gif_View_Rows {
    stack_cursor := stack_panel_cursor_zero()
    stack_cursor.offset = SETTINGS_GIF_FRAME_STEP_SEGMENT_SIZE
    downsample_row := gif_stack_row(stack_rect,
        SETTINGS_GIF_FRAME_STEP_SEGMENT_SIZE, stack_cursor)
    frame_step_row := gif_stack_row(stack_rect,
        SETTINGS_GIF_FRAME_TO_TIMING_SEGMENT_SIZE, downsample_row.cursor_out)
    timing_row := gif_stack_row(stack_rect,
        SETTINGS_GIF_TIMING_TO_BUTTON_SEGMENT_SIZE, frame_step_row.cursor_out)
    save_button_row := gif_stack_row(stack_rect,
        SETTINGS_GIF_BUTTON_TO_STATUS_SEGMENT_SIZE, timing_row.cursor_out)
    status_row := gif_stack_row(stack_rect, 0, save_button_row.cursor_out)
    return {
        sliders = {downsample_row.segment_rect.y, frame_step_row.segment_rect.y},
        timing_y = timing_row.segment_rect.y,
        save_button_y = save_button_row.segment_rect.y,
        status_y = status_row.segment_rect.y,
    }
}

//   Resolve the GIF timing selector and publish the selected mode.
prepare_gif_timing_controls :: proc(
    ctx: Gif_Panel_Context, panel: geometry.Rectangle,
    timing_y: f32, result: ^Gif_View_Preparation) {
    animation_rect, recorded_rect := gif_timing_button_rects(panel, timing_y)
    result^.animation_timing = update_text_button(gif_timing_button_params(
        ctx, 6203, "Animation", animation_rect), &ctx.ui_runtime.ui_press_owner)
    result^.recorded_timing = update_text_button(gif_timing_button_params(
        ctx, 6204, "Recorded", recorded_rect), &ctx.ui_runtime.ui_press_owner)
    if result^.animation_timing.clicked {ctx.ui_runtime.gif_timing_mode = .Animation}
    if result^.recorded_timing.clicked {ctx.ui_runtime.gif_timing_mode = .Recorded}
    result^.timing_mode = ctx.ui_runtime.gif_timing_mode
}

//   Resolve GIF controls and commit their action before rendering.
prepare_gif_view :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: Input_Frame) -> Gif_View_Preparation {
    if state == nil || state.particle_system == nil { return {} }
    ctx := Gif_Panel_Context{panel, mouse_input, &state.ui_runtime,
        view_font.cache_borrow(&state.font_cache, .Regular),
        view_font.cache_terminal_resolver(&state.font_cache)}
    stack_rect := geometry.Rectangle{panel.x + SETTINGS_PANEL_INSET,
        panel.y + SETTINGS_HEADER_TOP_OFFSET,
        panel.width - SETTINGS_PANEL_INSET * 2,
        panel.height - SETTINGS_HEADER_TOP_OFFSET}
    result := Gif_View_Preparation{rows = gif_view_layout_rows(stack_rect)}
    result.downsample = update_settings_integer_slider(gif_slider_params(
        ctx, result.rows.sliders.downsample_y, 6201, "Downsample",
        &ctx.ui_runtime.gif_downsample_factor))
    result.frame_step = update_settings_integer_slider(gif_slider_params(
        ctx, result.rows.sliders.frame_step_y, 6202, "Capture every",
        &ctx.ui_runtime.gif_frame_step))
    prepare_gif_timing_controls(ctx, panel, result.rows.timing_y, &result)
    result.save_button = update_text_button(gif_save_button_params(
        ctx, result.rows.save_button_y), &ctx.ui_runtime.ui_press_owner)
    if result.save_button.clicked { ctx.ui_runtime.save_gif_requested = true }
    result.phase = ctx.ui_runtime.gif_capture_phase
    result.captured_frames = ctx.ui_runtime.gif_captured_frames
    result.status_note = ctx.ui_runtime.gif_status_note
    result.status_note_len = ctx.ui_runtime.gif_status_note_len
    result.last_path = ctx.ui_runtime.last_gif_path
    result.last_path_len = ctx.ui_runtime.last_gif_path_len
    return result
}

