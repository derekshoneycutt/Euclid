package uisharing

import core "../../../core"
import contentdata "../../../core/content"
import geometry "../../../core/geometry"
import capturemodel "../../capture/model"
import native "../../native"
import input "../../input"
import viewfont "../../font"
import viewmessages "../../messages"
import viewmodel "../model"
import uigif "../gif"
import sharinglayout "../layout/sharing"
import uisettings "../settings"
import uiwidgets "../widgets"
import uisemantics "../semantics"
import theme "../theme"
import viewtext "../text"

PNG_SAVE_BUTTON_ID :: 6401
PNG_PATH_INPUT_ID :: 6402
SHARING_SCROLL_ID :: 6403
PNG_STATUS_ID :: 6404

// Sharing_Preparation borrows published text and retains observational widget results.
Sharing_Preparation :: struct {
    layout: sharinglayout.Sharing_Layout,
    gif: uigif.Gif_View_Preparation,
    button: uiwidgets.Text_Button_Result,
    path: uiwidgets.Input_Box_Result,
    path_text: string,
    status: contentdata.Content_Message_Id,
    scroll: uiwidgets.Scroll_Container_Update_Result,
}

// png_path_input_visible reports whether the last successful PNG path is exposed.
png_path_input_visible :: proc(runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    return runtime.layout.active_accordion_section == .Save_Gif &&
        runtime.sharing.png_path_available
}

// png_path_input_rect shares scrolled path geometry with ordinary pointer routing.
png_path_input_rect :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> geometry.Rectangle {
    return sharinglayout.sharing_layout_for_runtime(runtime).path
}

// Resolve PNG feedback without replacing the retained successful path.
png_status_message :: proc(state: ^core.Euclid_General_State) ->
    contentdata.Content_Message_Id {
    switch state.png_capture_status.phase {
    case .Pending:
        return .Png_Status_Pending
    case .Saved:
        return .Png_Status_Saved
    case .Error:
        return .Png_Status_Error
    case .Idle:
        if capturemodel.gif_capture_locks_playback_rate(
            state.gif_capture_status.gif_capture_phase,
            state.gif_capture_status.save_gif_requested) {
            return .Png_Status_Gif_Active
        }
        return .Png_Status_Idle
    }
    unreachable()
}

// Measure both fixed PNG rows and existing GIF rows before resolving scrollbar range.
sharing_content_height :: proc(
    panel: geometry.Rectangle, text_percent, control_percent: int) -> f32 {
    layout := sharinglayout.sharing_layout(panel, text_percent, control_percent, 0)
    inset := theme.ui_control_size_metric(theme.SETTINGS_PANEL_INSET, control_percent)
    header := theme.ui_control_size_metric(theme.SETTINGS_HEADER_TOP_OFFSET,
        control_percent)
    rows := uigif.gif_view_layout_rows({
        layout.gif_panel.x + inset, layout.gif_panel.y + header,
        max(f32(0), layout.gif_panel.width - inset * 2), panel.height},
        text_percent, control_percent)
    return rows.status_y - panel.y +
        uigif.gif_path_input_top_offset(text_percent, control_percent) +
        uigif.gif_path_input_height(text_percent, control_percent) + inset
}

// Retain Sharing-local wheel/thumb state while keeping visual-only preparation immutable.
prepare_sharing_scroll :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    frame: input.Input_Frame, interactive: bool) ->
    uiwidgets.Scroll_Container_Update_Result {
    ui := &state.ui_runtime
    preferences := ui.preferences.values.interface
    height := sharing_content_height(panel, preferences.text_size_percent,
        preferences.control_size_percent)
    step := theme.ui_font_size(preferences.text_size_percent) * 3
    if !interactive {
        return uiwidgets.scroll_container_visual(panel, height,
            ui.sharing.scroll_y, step, preferences.control_size_percent)
    }
    result := uiwidgets.scroll_container_update({
        id = SHARING_SCROLL_ID,
        rect = panel,
        content_height = height,
        scroll_y_in = ui.sharing.scroll_y,
        mouse_input = frame,
        interaction_space_rect = panel,
        wheel_step = step,
        press_owner = &ui.input.press_owner,
        state_in = {ui.sharing.scroll_dragging, ui.sharing.scroll_drag_off},
        semantic_focus = ui.semantic_focus,
        semantic_id = uisemantics.semantic_control_id(.Gif_Control, SHARING_SCROLL_ID),
        control_size_percent = preferences.control_size_percent,
    })
    ui.sharing.scroll_y = result.scroll_y_out
    ui.sharing.scroll_dragging = result.state_out.is_dragging_thumb
    ui.sharing.scroll_drag_off = result.state_out.drag_offset_y
    return result
}

// Build the one-shot action using the same semantic/button path as GIF controls.
png_button_params :: proc(
    state: ^core.Euclid_General_State, rect, panel: geometry.Rectangle,
    frame: input.Input_Frame) -> uiwidgets.Text_Button_Params {
    enabled := capturemodel.png_capture_available(&state.png_capture_status,
        capturemodel.gif_capture_view(&state.gif_capture_status))
    label := viewmessages.shell_message(state, .Png_Save)
    return {
        id = PNG_SAVE_BUTTON_ID,
        rect = rect,
        label = label,
        enabled = enabled,
        mouse = frame,
        interaction_space_rect = panel,
        interaction_enabled = true,
        font = viewfont.cache_borrow(&state.font_cache, .Regular),
        font_resolver = viewfont.cache_terminal_resolver(&state.font_cache),
        semantics = {
            publish = true,
            focus = state.ui_runtime.semantic_focus,
            id = uisemantics.semantic_control_id(.Gif_Control, PNG_SAVE_BUTTON_ID),
            role = .Button,
            states = uiwidgets.button_semantic_states(enabled),
            region = .Accordion_Content,
            traversal_order = 0,
            clip_bounds = panel,
            label = label,
        },
    }
}

// Share the GIF field's widget contract while retaining PNG-specific text and selection.
png_path_params :: proc(
    state: ^core.Euclid_General_State, rect: geometry.Rectangle,
    frame: input.Input_Frame, text: string) -> uiwidgets.Input_Box_Params {
    return uigif.saved_path_input_params(state, rect, frame, text, {
        &state.ui_runtime.png_path_input, PNG_PATH_INPUT_ID,
        state.png_capture_status.path_revision,
        viewmessages.shell_message(state, .Png_Saved_Path_Accessible), 1})
}

// Prepare both independent save sections; GIF intent wins any same-frame admission conflict.
prepare_sharing_view :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    frame: input.Input_Frame, interactive := true) -> Sharing_Preparation {
    scroll := prepare_sharing_scroll(state, panel, frame, interactive)
    preferences := state.ui_runtime.preferences.values.interface
    result: Sharing_Preparation = {
        scroll = scroll,
        layout = sharinglayout.sharing_layout(panel, preferences.text_size_percent,
            preferences.control_size_percent, scroll.scroll_y_out),
    }
    result.gif = uigif.prepare_gif_view(
        state, result.layout.gif_panel, frame, interactive)
    result.button = uiwidgets.prepare_text_button(
        png_button_params(state, result.layout.button, panel, frame),
        &state.ui_runtime.input.press_owner, interactive)
    if result.button.action.activated {
        _ = capturemodel.png_capture_request(&state.png_capture_status,
            capturemodel.gif_capture_view(&state.gif_capture_status))
    }
    result.status = png_status_message(state)
    result.path_text = capturemodel.png_capture_path(&state.png_capture_status)
    if len(result.path_text) > 0 {
        params := png_path_params(state, result.layout.path, frame, result.path_text)
        if interactive {
            result.path = uiwidgets.input_box_prepare(
                params, &state.ui_runtime.input.press_owner)
        } else {
            result.path = uiwidgets.input_box_draw_result(params, false)
        }
        if interactive && result.path.hovered {
            state.ui_runtime.input.cursor = .Text
        }
    }
    if interactive {
        register_sharing_feedback(state, panel, result)
    }
    return result
}

// Publish one status node and an optional keyboard/page-scroll owner.
register_sharing_feedback :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    prepared: Sharing_Preparation) {
    focus := state.ui_runtime.semantic_focus
    _ = uisemantics.semantic_register_control(focus, {
        id = uisemantics.semantic_control_id(.Gif_Control, PNG_STATUS_ID),
        role = .Status,
        states = {.Visible},
        region = .Accordion_Content,
        bounds = {panel.x, prepared.layout.status_y, panel.width,
            theme.ui_font_size(
                state.ui_runtime.preferences.values.interface.text_size_percent)},
        clip_bounds = panel,
        label = viewmessages.shell_message(state, prepared.status),
    })
    if prepared.scroll.scrollbar.has_scrollbar {
        _ = uisemantics.semantic_register_control(focus, {
            id = uisemantics.semantic_control_id(.Gif_Control, SHARING_SCROLL_ID),
            role = .Panel,
            states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
            actions = {.Focus, .Scroll, .Set_Value},
            region = .Accordion_Content,
            traversal_order = 20,
            bounds = panel,
            clip_bounds = panel,
            numeric_range = {0, f64(prepared.scroll.maximum),
                f64(prepared.scroll.scroll_y_out), f64(prepared.scroll.step),
                .Vertical, true},
            label = viewmessages.shell_message(state, .Navigation_Sharing),
        })
    }
}

// Draw prepared geometry only; capture remains owned by the display frame coordinator.
draw_encoded_sharing_geometry :: proc(
    encoder: ^native.Draw_Encoder, prepared: Sharing_Preparation) {
    uigif.draw_encoded_gif_geometry(encoder, prepared.gif)
    _ = native.draw_encoder_rectangle(encoder,
        prepared.button.control_geometry.bounds, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(encoder,
        prepared.button.control_geometry.bounds, 1,
        theme.draw_color(encoder, .Control_Border))
}

// Draw localized headings, independent feedback, and both selectable saved-path fields.
draw_encoded_sharing_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle, prepared: Sharing_Preparation) {
    layout := prepared.layout
    x := layout.button.x
    uisettings.draw_encoded_settings_section_heading(state, encoder,
        .Png_Save, x, layout.png_heading_y)
    uisettings.draw_encoded_settings_section_heading(state, encoder,
        .Gif_Save, x, layout.gif_heading_y)
    viewtext.draw_encoded_label(&state.font_cache, encoder,
        viewmessages.shell_message(state, .Png_Description), x, layout.description_y)
    uigif.draw_encoded_gif_button_text(state, encoder,
        viewmessages.shell_message(state, .Png_Save),
        prepared.button.control_geometry.bounds, false)
    viewtext.draw_encoded_label(&state.font_cache, encoder,
        viewmessages.shell_message(state, prepared.status), x, layout.status_y)
    if len(prepared.path_text) > 0 {
        viewtext.draw_encoded_label(&state.font_cache, encoder,
            viewmessages.shell_message(state, .Gif_Saved_Path_Label), x, layout.path.y)
        uiwidgets.draw_encoded_input_box(encoder,
            png_path_params(state, layout.path, {}, prepared.path_text), prepared.path)
    }
    uigif.draw_encoded_gif_text(state, encoder, layout.gif_panel, prepared.gif)
    uiwidgets.draw_encoded_scrollbar(encoder, prepared.scroll.scrollbar)
}
