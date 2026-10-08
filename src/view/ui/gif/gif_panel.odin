package uigif

import uilayout "../layout"
import native "../../native"
import core "../../../core"
import contentdata "../../../core/content"
import geometry "../../../core/geometry"
import view_font "../../font"
import viewmodel "../model"
import capturemodel "../../capture/model"
import viewmessages "../../messages"
import viewtext "../text"
import input "../../input"
import uiwidgets "../widgets"
import theme "../theme"
import uisemantics "../semantics"
import uiaccordion "../layout/accordion"
import uisettings "../settings"
import uilibrary "../library"

GIF_PATH_INPUT_BOX_ID :: 6205
GIF_PATH_LABEL_WIDTH :: f32(42)
GIF_PATH_INPUT_HEIGHT :: f32(24)
GIF_PATH_INPUT_TOP_OFFSET :: f32(30)
GIF_STATUS_NODE_ID :: 6301
GIF_STATUS_NOTE_NODE_ID :: 6302

//   Row y-positions for the GIF panel's two sliders.
Gif_Slider_Rows :: struct {
    downsample_y: f32,
    frame_step_y: f32,
}

//   Shared dependencies for controls in one GIF panel frame.
Gif_Panel_Context :: struct {
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame,
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    gif_capture_status: ^capturemodel.Gif_Capture_Status,
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
    downsample: uiwidgets.Integer_Slider_Result,
    frame_step: uiwidgets.Integer_Slider_Result,
    animation_timing: uiwidgets.Text_Button_Result,
    recorded_timing: uiwidgets.Text_Button_Result,
    timing_mode: capturemodel.Gif_Capture_Timing_Mode,
    save_button: uiwidgets.Text_Button_Result,
    phase: capturemodel.Gif_Capture_Phase,
    captured_frames: int,
    status_note: [260]u8,
    status_note_len: int,
    last_path: string,
    path_input: uiwidgets.Input_Box_Result,
}

// Gif_Timing_Button_Descriptor describes one playback timing choice.
Gif_Timing_Button_Descriptor :: struct {
    id: int,
    label: string,
    semantic_label: string,
    order: u16,
    rectangle: geometry.Rectangle,
}

// gif_path_input_rect_for_panel resolves the saved-path field from GIF row layout.
gif_path_input_rect_for_panel :: proc(
    panel: geometry.Rectangle) -> geometry.Rectangle {
    stack := geometry.Rectangle{panel.x + theme.SETTINGS_PANEL_INSET,
        panel.y + theme.SETTINGS_HEADER_TOP_OFFSET,
        panel.width - theme.SETTINGS_PANEL_INSET * 2,
        panel.height - theme.SETTINGS_HEADER_TOP_OFFSET}
    rows := gif_view_layout_rows(stack)
    return {stack.x + GIF_PATH_LABEL_WIDTH,
        rows.status_y + GIF_PATH_INPUT_TOP_OFFSET,
        max(f32(0), stack.width - GIF_PATH_LABEL_WIDTH), GIF_PATH_INPUT_HEIGHT}
}

// gif_path_input_visible reports whether the saved-path control exists this frame.
gif_path_input_visible :: #force_inline proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    capture_view: capturemodel.Gif_Capture_View) -> bool {
    return runtime != nil && runtime^.active_accordion_section == .Save_Gif &&
        capture_view.phase == .Saved && capture_view.path_available
}

// gif_path_input_rect resolves the visible field against active accordion geometry.
gif_path_input_rect :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> geometry.Rectangle {
    return gif_path_input_rect_for_panel(
        uiaccordion.accordion_content_rect(runtime, .Save_Gif))
}

// draw_encoded_gif_geometry encodes GIF controls while capture stays deferred.
draw_encoded_gif_geometry :: proc(
    encoder: ^native.Draw_Encoder, prepared: Gif_View_Preparation) {
    uisettings.draw_encoded_slider_geometry(encoder, prepared.downsample)
    uisettings.draw_encoded_slider_geometry(encoder, prepared.frame_step)
    animation := prepared.animation_timing.control_geometry.bounds
    recorded := prepared.recorded_timing.control_geometry.bounds
    if prepared.timing_mode == .Animation {
        _ = native.draw_encoder_rectangle(encoder, animation, theme.UI_BORDER_COLOR)
    } else {
        _ = native.draw_encoder_rectangle(encoder, recorded, theme.UI_BORDER_COLOR)
    }
    _ = native.draw_encoder_rectangle_outline(
        encoder, animation, 1, theme.UI_BORDER_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, recorded, 1, theme.UI_BORDER_COLOR)
    button := prepared.save_button.control_geometry.bounds
    _ = native.draw_encoder_rectangle(
        encoder, geometry.Rectangle(button), theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, geometry.Rectangle(button), 1, theme.UI_BORDER_COLOR)
}

// draw_encoded_gif_text emits capture controls while readback remains deferred.
draw_encoded_gif_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle, prepared: Gif_View_Preparation) {
    stack := geometry.Rectangle{panel.x + theme.SETTINGS_PANEL_INSET,
        panel.y + theme.SETTINGS_HEADER_TOP_OFFSET,
        panel.width - theme.SETTINGS_PANEL_INSET * 2,
        panel.height - theme.SETTINGS_HEADER_TOP_OFFSET}
    rows := gif_view_layout_rows(stack)
    x := panel.x + theme.SETTINGS_PANEL_INSET
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    viewtext.draw_encoded_label(
        &state^.font_cache, encoder, viewmessages.shell_message(state, .Gif_Output_Scale),
        x, rows.sliders.downsample_y)
    draw_encoded_gif_value(
        state, encoder, panel, gif_output_scale_label(state, prepared.downsample.value),
        rows.sliders.downsample_y)
    viewtext.draw_encoded_label(
        &state^.font_cache, encoder,
        viewmessages.shell_message(state, .Gif_Capture_Every),
        x, rows.sliders.frame_step_y)
    draw_encoded_gif_value(
        state, encoder, panel,
        gif_capture_cadence_label(state, prepared.frame_step.value, storage[:]),
        rows.sliders.frame_step_y)
    viewtext.draw_encoded_label(&state^.font_cache, encoder,
        viewmessages.shell_message(state, .Gif_Playback_Timing), x, rows.timing_y)
    animation, recorded := gif_timing_button_rects(panel, rows.timing_y)
    draw_encoded_gif_button_text(state, encoder,
        viewmessages.shell_message(state, .Gif_Timing_Animation), animation)
    draw_encoded_gif_button_text(state, encoder,
        viewmessages.shell_message(state, .Gif_Timing_Recorded), recorded)
    viewtext.draw_encoded_label(
        &state^.font_cache, encoder, gif_capture_button_label(state, prepared.phase),
        x + theme.SETTINGS_PANEL_INSET, rows.save_button_y + theme.SETTINGS_PANEL_INSET)
    draw_encoded_gif_status(state, encoder, prepared, x, rows.status_y)
}

// draw_encoded_gif_status emits prepared phase, note, and published-path rows.
draw_encoded_gif_status :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Gif_View_Preparation, x, row_y: f32) {
    storage: [contentdata.UI_FORMAT_OUTPUT_BYTE_CAPACITY]u8
    viewtext.draw_encoded_label(&state^.font_cache, encoder,
        gif_capture_status_label(state,
            prepared.phase, prepared.captured_frames, storage[:]),
        x, row_y)
    if prepared.status_note_len > 0 {
        status_note := prepared.status_note
        note := string(status_note[:prepared.status_note_len])
        viewtext.draw_encoded_label(&state^.font_cache, encoder, note,
            x, row_y + theme.SETTINGS_GIF_STATUS_NOTE_ROW_OFFSET)
    }
    if prepared.phase == .Saved && len(prepared.last_path) > 0 {
        field := gif_path_input_rect_for_panel(
            uiaccordion.accordion_content_rect(&state^.ui_runtime, .Save_Gif))
        viewtext.draw_encoded_label(&state^.font_cache, encoder,
            viewmessages.shell_message(state, .Gif_Saved_Path_Label), x,
            field.y + (field.height - theme.TREE_FONT_SIZE) * 0.5)
        params := gif_path_input_params(state, field, {}, prepared.last_path)
        uiwidgets.draw_encoded_input_box(encoder, params, prepared.path_input)
    }
}

// gif_path_input_params builds shared saved-path field parameters for update and draw.
gif_path_input_params :: proc(
    state: ^core.Euclid_General_State, rect: geometry.Rectangle,
    frame: input.Input_Frame, text: string) -> uiwidgets.Input_Box_Params {
    runtime := &state^.ui_runtime
    focus := runtime^.interaction_frame.effective_focus
    target := runtime^.interaction_frame.pointer_target
    advance, measured := viewtext.ui_text_column_advance(
        view_font.cache_borrow(&state^.font_cache, .Regular), theme.TREE_FONT_SIZE)
    if !measured {
        advance = theme.TEXT_WRAP_ADVANCE
    }
    return {rect = rect, clip_rect = runtime^.ui_regions.accordion_rect,
        controls = uilibrary.tree_semantic_id(),
        descriptor = {
            id = uisemantics.semantic_control_id(.Gif_Control, GIF_PATH_INPUT_BOX_ID),
            region = .Accordion_Content, traversal_order = 5,
            label = viewmessages.shell_message(state, .Gif_Saved_Path_Accessible),
            text = text, mode = .Read_Only,
            cursor_byte = runtime^.gif_path_input.cursor_byte,
            anchor_byte = runtime^.gif_path_input.anchor_byte,
            content_revision = state^.gif_capture_status.last_gif_path_revision,
        },
        semantic_focus = runtime^.semantic_focus,
        state = &runtime^.gif_path_input, frame = frame,
        focused = focus.kind == .Input_Box && focus.id == GIF_PATH_INPUT_BOX_ID,
        pointer_routed = target.focus.kind == .Input_Box &&
            target.id == GIF_PATH_INPUT_BOX_ID,
        column_advance = advance,
        font = view_font.cache_borrow(&state^.font_cache, .Regular),
        resolver = view_font.cache_terminal_resolver(&state^.font_cache)}
}

// draw_encoded_gif_value right-aligns one prepared slider value in the panel.
draw_encoded_gif_value :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle, text: string, row_y: f32) {
    face := view_font.cache_borrow(&state^.font_cache, .Regular)
    width, measured := viewtext.ui_text_measure_monospace(
        text, face, theme.TREE_FONT_SIZE, 0)
    if !measured {
        width = 20
    }
    viewtext.draw_encoded_label(&state^.font_cache, encoder, text,
        uisettings.settings_right_aligned_x(panel, width), row_y)
}

// gif_output_scale_label describes one integer downsample factor as output scale.
gif_output_scale_label :: proc(
    state: ^core.Euclid_General_State, factor: int) -> string {
    switch clamp(factor, 1, 4) {
    case 1: return viewmessages.shell_message(state, .Gif_Output_Scale_Hundred)
    case 2: return viewmessages.shell_message(state, .Gif_Output_Scale_Fifty)
    case 3: return viewmessages.shell_message(state, .Gif_Output_Scale_Thirty_Three)
    case 4: return viewmessages.shell_message(state, .Gif_Output_Scale_Twenty_Five)
    }
    return viewmessages.shell_message(state, .Gif_Output_Scale_Hundred)
}

// gif_capture_cadence_label writes multi-frame cadence into caller-owned storage.
gif_capture_cadence_label :: proc(
    state: ^core.Euclid_General_State, frame_step: int, storage: []u8) -> string {
    clamped := clamp(frame_step, 1, 4)
    if clamped == 1 {
        return viewmessages.shell_message(state, .Gif_Cadence_Single)
    }
    return viewmessages.shell_format(state, .Gif_Cadence_Multiple,
        []contentdata.Content_Format_Argument{{"count", u32(clamped)}}, storage)
}

// gif_timing_button_rects divides one row into two stable timing choices.
gif_timing_button_rects :: proc(
    panel: geometry.Rectangle, row_y: f32) -> (geometry.Rectangle, geometry.Rectangle) {
    available := panel.width - theme.SETTINGS_PANEL_INSET * 2 -
        theme.SETTINGS_GIF_TIMING_BUTTON_GAP
    width := max(f32(0), available * 0.5)
    y := row_y + theme.SETTINGS_GIF_TIMING_BUTTON_TOP_OFFSET
    animation := geometry.Rectangle{panel.x + theme.SETTINGS_PANEL_INSET, y,
        width, theme.SETTINGS_GIF_BUTTON_HEIGHT}
    recorded := geometry.Rectangle{animation.x + width +
        theme.SETTINGS_GIF_TIMING_BUTTON_GAP, y, width, theme.SETTINGS_GIF_BUTTON_HEIGHT}
    return animation, recorded
}

// draw_encoded_gif_button_text centers one timing choice in its segment.
draw_encoded_gif_button_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    text: string, rectangle: geometry.Rectangle) {
    face := view_font.cache_borrow(&state^.font_cache, .Regular)
    width, measured := viewtext.ui_text_measure_monospace(
        text, face, theme.TREE_FONT_SIZE, 0)
    if !measured {
        width = 0
    }
    viewtext.draw_encoded_label(&state^.font_cache, encoder, text,
        rectangle.x + max(f32(0), (rectangle.width - width) * 0.5),
        rectangle.y + (rectangle.height - theme.TREE_FONT_SIZE) * 0.5)
}

//   Build one GIF slider parameter record shared by update and draw.
gif_slider_params :: proc(
    ctx: Gif_Panel_Context,
    row_y: f32,
    press_id: int,
    label: string,
    value: int) -> uiwidgets.Integer_Slider_Params {
    return {
        panel = geometry.Rectangle(ctx.panel), row_y = row_y,
        mouse_input = ctx.mouse_input,
        ui_runtime = ctx.ui_runtime, press_id = press_id, label = label,
        value = value, min_value = 1, max_value = 4, font = ctx.font,
        font_resolver = ctx.resolver,
        semantic_domain = .Gif_Control,
        semantic_order = u16(press_id - 6201),
    }
}

//   Build the GIF save/cancel button parameters shared by update and draw.
gif_save_button_params :: proc(
    ctx: Gif_Panel_Context,
    row_y: f32) -> uiwidgets.Text_Button_Params {
    phase := ctx.gif_capture_status.gif_capture_phase
    return {
        id = 3001,
        rect = {ctx.panel.x + theme.SETTINGS_PANEL_INSET, row_y,
            ctx.panel.width - theme.SETTINGS_PANEL_INSET * 2,
            theme.SETTINGS_GIF_BUTTON_HEIGHT},
        label = gif_capture_button_label(ctx.state, phase),
        enabled = gif_capture_button_enabled(phase), mouse = ctx.mouse_input,
        interaction_space_rect = geometry.Rectangle(ctx.panel),
        interaction_enabled = true,
        font = ctx.font, font_resolver = ctx.resolver,
        semantics = {
            publish = true,
            focus = ctx.ui_runtime.semantic_focus,
            id = uisemantics.semantic_control_id(.Gif_Control, 3001),
            role = .Button,
            states = uiwidgets.button_semantic_states(
                gif_capture_button_enabled(phase)),
            region = .Accordion_Content,
            traversal_order = 4,
            clip_bounds = geometry.Rectangle(ctx.panel),
            label = gif_capture_button_label(ctx.state, phase),
        },
    }
}

// gif_timing_button_params builds one choice in the timing selector.
gif_timing_button_params :: proc(
    ctx: Gif_Panel_Context,
    descriptor: Gif_Timing_Button_Descriptor) -> uiwidgets.Text_Button_Params {
    enabled := gif_capture_button_enabled(ctx.gif_capture_status.gif_capture_phase)
    states := uiwidgets.button_semantic_states(enabled)
    animation_selected := descriptor.id == 6203 &&
        ctx.gif_capture_status.gif_timing_mode == .Animation
    recorded_selected := descriptor.id == 6204 &&
        ctx.gif_capture_status.gif_timing_mode == .Recorded
    if animation_selected || recorded_selected {
        states += {.Selected}
    }
    return {
        id = descriptor.id, rect = descriptor.rectangle, label = descriptor.label,
        enabled = enabled,
        mouse = ctx.mouse_input, interaction_space_rect = ctx.panel,
        interaction_enabled = true, font = ctx.font, font_resolver = ctx.resolver,
        semantics = {
            publish = true,
            focus = ctx.ui_runtime.semantic_focus,
            id = uisemantics.semantic_control_id(.Gif_Control, descriptor.id),
            role = .Button,
            states = states,
            region = .Accordion_Content,
            traversal_order = descriptor.order,
            clip_bounds = geometry.Rectangle(ctx.panel),
            label = descriptor.semantic_label,
        },
    }
}

// gif_capture_button_label describes the action or active work for one phase.
gif_capture_button_label :: proc(
    state: ^core.Euclid_General_State, phase: capturemodel.Gif_Capture_Phase) -> string {
    switch phase {
    case .Armed:
        return viewmessages.shell_message(state, .Gif_Action_Cancel)
    case .Recording:
        return viewmessages.shell_message(state, .Gif_Action_Recording)
    case .Finalizing:
        return viewmessages.shell_message(state, .Gif_Action_Saving)
    case .Idle, .Saved, .Error:
        return viewmessages.shell_message(state, .Gif_Save)
    }
    return viewmessages.shell_message(state, .Gif_Save)
}

// gif_capture_button_enabled reports whether one phase accepts button input.
gif_capture_button_enabled :: #force_inline proc(
    phase: capturemodel.Gif_Capture_Phase) -> bool {
    return phase != .Recording && phase != .Finalizing
}

// gif_capture_status_label writes recording progress into caller-owned storage.
gif_capture_status_label :: proc(
    state: ^core.Euclid_General_State, phase: capturemodel.Gif_Capture_Phase,
    captured_frames: int, storage: []u8) -> string {
    switch phase {
    case .Idle:
        return viewmessages.shell_message(state, .Gif_Status_Idle)
    case .Armed:
        return viewmessages.shell_message(state, .Gif_Status_Armed)
    case .Recording:
        return viewmessages.shell_format(state, .Gif_Status_Recording,
            []contentdata.Content_Format_Argument{{"count", i64(captured_frames)}},
            storage)
    case .Finalizing:
        return viewmessages.shell_message(state, .Gif_Status_Saving)
    case .Saved:
        return viewmessages.shell_message(state, .Gif_Status_Saved)
    case .Error:
        return viewmessages.shell_message(state, .Gif_Status_Error)
    }

    return viewmessages.shell_message(state, .Gif_Status_Idle)
}

// gif_accessibility_status_label reports only meaningful capture milestones.
gif_accessibility_status_label :: proc(
    state: ^core.Euclid_General_State, phase: capturemodel.Gif_Capture_Phase) -> string {
    switch phase {
    case .Idle:
        return viewmessages.shell_message(state, .Gif_Accessibility_Idle)
    case .Armed:
        return viewmessages.shell_message(state, .Gif_Accessibility_Armed)
    case .Recording:
        return viewmessages.shell_message(state, .Gif_Accessibility_Recording)
    case .Finalizing:
        return viewmessages.shell_message(state, .Gif_Accessibility_Saving)
    case .Saved:
        return viewmessages.shell_message(state, .Gif_Accessibility_Saved)
    case .Error:
        return viewmessages.shell_message(state, .Gif_Accessibility_Error)
    }
    return viewmessages.shell_message(state, .Gif_Accessibility_Idle)
}

// register_gif_status publishes bounded milestone and optional error detail nodes.
register_gif_status :: proc(
    ctx: Gif_Panel_Context, result: ^Gif_View_Preparation) {
    bounds := geometry.Rectangle{ctx.panel.x + theme.SETTINGS_PANEL_INSET,
        result^.rows.status_y, max(f32(0),
            ctx.panel.width - theme.SETTINGS_PANEL_INSET * 2),
        theme.SETTINGS_GIF_STATUS_NOTE_ROW_OFFSET}
    states := viewmodel.Ui_Node_State{.Visible}
    if result^.phase == .Recording || result^.phase == .Finalizing {
        states += {.Busy}
    }
    _ = uisemantics.semantic_register_control(ctx.ui_runtime.semantic_focus, {
        id = uisemantics.semantic_control_id(.Gif_Control, GIF_STATUS_NODE_ID),
        role = .Status, states = states, bounds = bounds,
        clip_bounds = geometry.Rectangle(ctx.panel),
        label = gif_accessibility_status_label(ctx.state, result^.phase),
    })
    if result^.status_note_len <= 0 {
        return
    }
    note_bounds := bounds
    note_bounds.y += theme.SETTINGS_GIF_STATUS_NOTE_ROW_OFFSET
    note := string(result^.status_note[:result^.status_note_len])
    _ = uisemantics.semantic_register_control(ctx.ui_runtime.semantic_focus, {
        id = uisemantics.semantic_control_id(.Gif_Control, GIF_STATUS_NOTE_NODE_ID),
        role = .Status, states = {.Visible}, bounds = note_bounds,
        clip_bounds = geometry.Rectangle(ctx.panel), label = note,
    })
}

//   Place one fixed-size GIF settings row and return it with the advanced cursor.
gif_stack_row :: #force_inline proc(
    rect: geometry.Rectangle, segment_size: f32,
    cursor: uilayout.Stack_Panel_Cursor) -> uilayout.Stack_Panel_Result {

    return uilayout.stack_panel_place_segment(uilayout.Stack_Panel_Params{
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
    stack_cursor := uilayout.stack_panel_cursor_zero()
    stack_cursor.offset = theme.SETTINGS_GIF_FRAME_STEP_SEGMENT_SIZE
    downsample_row := gif_stack_row(stack_rect,
        theme.SETTINGS_GIF_FRAME_STEP_SEGMENT_SIZE, stack_cursor)
    frame_step_row := gif_stack_row(stack_rect,
        theme.SETTINGS_GIF_FRAME_TO_TIMING_SEGMENT_SIZE, downsample_row.cursor_out)
    timing_row := gif_stack_row(stack_rect,
        theme.SETTINGS_GIF_TIMING_TO_BUTTON_SEGMENT_SIZE, frame_step_row.cursor_out)
    save_button_row := gif_stack_row(stack_rect,
        theme.SETTINGS_GIF_BUTTON_TO_STATUS_SEGMENT_SIZE, timing_row.cursor_out)
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
    timing_y: f32, result: ^Gif_View_Preparation, interactive := true) {
    animation_rect, recorded_rect := gif_timing_button_rects(panel, timing_y)
    result^.animation_timing = uiwidgets.prepare_text_button(gif_timing_button_params(
        ctx, {6203, viewmessages.shell_message(ctx.state, .Gif_Timing_Animation),
            viewmessages.shell_message(ctx.state, .Gif_Timing_Animation_Description),
            2, animation_rect}),
        &ctx.ui_runtime.ui_press_owner, interactive)
    result^.recorded_timing = uiwidgets.prepare_text_button(gif_timing_button_params(
        ctx, {6204, viewmessages.shell_message(ctx.state, .Gif_Timing_Recorded),
            viewmessages.shell_message(ctx.state, .Gif_Timing_Recorded_Description),
            3, recorded_rect}),
        &ctx.ui_runtime.ui_press_owner, interactive)
    if result^.animation_timing.action.activated {
        ctx.gif_capture_status.gif_timing_mode = .Animation
    }
    if result^.recorded_timing.action.activated {
        ctx.gif_capture_status.gif_timing_mode = .Recorded
    }
    result^.timing_mode = ctx.gif_capture_status.gif_timing_mode
}

// prepare_gif_path_input borrows published path text and resolves its interaction.
prepare_gif_path_input :: proc(
    state: ^core.Euclid_General_State, ctx: Gif_Panel_Context,
    mouse_input: input.Input_Frame, result: ^Gif_View_Preparation, interactive := true) {
    result^.last_path = string(ctx.gif_capture_status.last_gif_path[
        :ctx.gif_capture_status.last_gif_path_len])
    if ctx.gif_capture_status.gif_capture_phase != .Saved || len(result^.last_path) == 0 {
        return
    }
    params := gif_path_input_params(state,
        gif_path_input_rect_for_panel(ctx.panel), mouse_input, result^.last_path)
    if !interactive {
        params.focused = false
        result^.path_input = uiwidgets.input_box_draw_result(params, false)
        return
    }
    result^.path_input = uiwidgets.input_box_prepare(
        params, &ctx.ui_runtime.ui_press_owner)
    if result^.path_input.hovered || ctx.ui_runtime.ui_press_owner.kind == .Input_Box {
        ctx.ui_runtime.cursor = .Text
    }
}

// prepare_gif_sliders resolves the two bounded value controls.
prepare_gif_sliders :: proc(
    ctx: Gif_Panel_Context, result: ^Gif_View_Preparation, interactive := true) {
    result^.downsample = uiwidgets.prepare_integer_slider(gif_slider_params(
        ctx, result^.rows.sliders.downsample_y, 6201,
        viewmessages.shell_message(ctx.state, .Gif_Downsample_Accessible),
        ctx.gif_capture_status.gif_downsample_factor), interactive)
    result^.frame_step = uiwidgets.prepare_integer_slider(gif_slider_params(
        ctx, result^.rows.sliders.frame_step_y, 6202,
        viewmessages.shell_message(ctx.state, .Gif_Capture_Every),
        ctx.gif_capture_status.gif_frame_step), interactive)
    if result^.downsample.changed {
        ctx.gif_capture_status.gif_downsample_factor = result^.downsample.value
    }
    if result^.frame_step.changed {
        ctx.gif_capture_status.gif_frame_step = result^.frame_step.value
    }
}

// prepare_gif_capture_button resolves and applies the current capture action.
prepare_gif_capture_button :: proc(
    ctx: Gif_Panel_Context,
    result: ^Gif_View_Preparation, interactive := true) {
    params := gif_save_button_params(ctx, result^.rows.save_button_y)
    result^.save_button = uiwidgets.prepare_text_button(
        params, &ctx.ui_runtime.ui_press_owner, interactive)
    if result^.save_button.action.activated {
        ctx.gif_capture_status.save_gif_requested = true
    }
}

//   Resolve GIF controls and commit their action before rendering.
prepare_gif_view :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame, interactive := true) -> Gif_View_Preparation {
    if state == nil || state.particle_system == nil {
        return {}
    }
    ctx := Gif_Panel_Context{state, panel, mouse_input, &state.ui_runtime,
        &state.gif_capture_status,
        view_font.cache_borrow(&state.font_cache, .Regular),
        view_font.cache_terminal_resolver(&state.font_cache)}
    stack_rect := geometry.Rectangle{panel.x + theme.SETTINGS_PANEL_INSET,
        panel.y + theme.SETTINGS_HEADER_TOP_OFFSET,
        panel.width - theme.SETTINGS_PANEL_INSET * 2,
        panel.height - theme.SETTINGS_HEADER_TOP_OFFSET}
    result := Gif_View_Preparation{rows = gif_view_layout_rows(stack_rect)}
    prepare_gif_sliders(ctx, &result, interactive)
    prepare_gif_timing_controls(ctx, panel, result.rows.timing_y, &result, interactive)
    prepare_gif_capture_button(ctx, &result, interactive)
    result.phase = ctx.gif_capture_status.gif_capture_phase
    result.captured_frames = ctx.gif_capture_status.gif_captured_frames
    result.status_note = ctx.gif_capture_status.gif_status_note
    result.status_note_len = ctx.gif_capture_status.gif_status_note_len
    if interactive {
        register_gif_status(ctx, &result)
    }
    prepare_gif_path_input(state, ctx, mouse_input, &result, interactive)
    return result
}
