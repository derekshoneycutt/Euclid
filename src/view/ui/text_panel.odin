package ui

import geometry "../../core/geometry"
import native "../native"

import "../../core"
import dyncompile "../../dynview/compile"
import dynlayout "../../dynview/layout"
import julia "../../bridge"
import view_core "../core"
import "../font"
import ui_dynview "./dynview"

//   Prepared post-layout interaction state for one non-Terminal presentation.
Presentation_Preparation :: struct {
    active: bool,
    text_panel: geometry.Rectangle,
    view_text: string,
    scroll: Scroll_Container_Update_Result,
    selection_view: ui_dynview.Dynview_Selection_View,
}

// Presentation_Content_Interaction groups one prepared interaction request.
Presentation_Content_Interaction :: struct {
    scroll: Scroll_Container_Update_Result,
    view_text: string,
    mouse_input: Input_Frame,
    keyboard_enabled: bool,
    frame_dt: f32,
}

// draw_encoded_presentation_geometry encodes panel and cached non-glyph content.
draw_encoded_presentation_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle) {
    if state == nil || state^.julia_interface == nil {return}
    _ = native.draw_encoder_rectangle(
        encoder, panel, BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, panel, 1, UI_BORDER_COLOR)
    text_panel := view_text_content_panel(panel)
    _ = native.draw_encoder_rectangle(
        encoder, text_panel, UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, text_panel, 1, UI_BORDER_COLOR)
    if is_terminal_selected(state) {return}
    ui_dynview.draw_encoded_geometry(&state^.dynview, encoder,
        text_panel, state^.ui_runtime.view_text_scroll_y,
        TEXT_PADDING)
}

//   Compute the bordered viewport used by text and Terminal presentations.
view_text_content_panel :: proc(
    panel: geometry.Rectangle) -> geometry.Rectangle {
    panel_geometry := container_geometry(panel, 1)
    text_panel := geometry.Rectangle{
        panel_geometry.inner_rect.x + 5,
        panel_geometry.inner_rect.y + 5,
        panel_geometry.inner_rect.width - 10,
        panel_geometry.inner_rect.height - 10,
    }
    return container_geometry(text_panel, 1).drawn_rect
}

// draw_encoded_presentation_text emits visible Dynview or fallback glyphs only.
draw_encoded_presentation_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    presentation: Presentation_Preparation) {
    if state == nil || encoder == nil || !presentation.active {return}
    _ = native.draw_encoder_push_scissor(
        encoder, geometry.Rectangle(presentation.scroll.view_rect))
    fallback := ui_dynview.Fallback_Text_Content{
        presentation.view_text, UI_TEXT_COLOR}
    ui_dynview.draw_presentation_styled_or_fallback(
        state, &state^.ui_runtime, fallback, {
            encoder = encoder,
            panel = geometry.Rectangle(presentation.text_panel),
            scroll_y = state^.ui_runtime.view_text_scroll_y,
            font = font.cache_borrow(&state^.font_cache, .Regular),
            font_cache = &state^.font_cache,
            metrics = {
                padding = TEXT_PADDING,
                row_height = TEXT_ROW_HEIGHT,
                wrap_advance = TEXT_WRAP_ADVANCE,
                font_size = TREE_FONT_SIZE,
            },
        })
    view_core.draw_encoded_copy_icons(&state^.dynview, encoder)
    _ = native.draw_encoder_pop_scissor(encoder)
}

//   Return whether the selected catalog node owns the Terminal surface.
is_terminal_selected :: #force_inline proc(state: ^core.Euclid_General_State) -> bool {
    return state != nil && state^.julia_interface != nil &&
        state^.julia_interface^.selected_animation != nil &&
        state^.julia_interface^.selected_animation^.node_kind == .Terminal
}

//   Report whether the display currently owns a non-Terminal presentation surface.
presentation_scroll_is_available :: #force_inline proc(
    state: ^core.Euclid_General_State) -> bool {

    return state != nil && state^.julia_interface != nil &&
        state^.julia_interface^.selected_animation != nil &&
        !is_terminal_selected(state) &&
        ui_presentation_is_visible(&state^.ui_runtime)
}

//   Apply a requested presentation scroll before the next layout interaction pass.
set_presentation_scroll_position :: proc(
    state: ^core.Euclid_General_State, requested_y: f32) -> bool {

    if !presentation_scroll_is_available(state) {
        return false
    }
    ui_runtime := &state^.ui_runtime
    scroll_container_release_press(&ui_runtime^.ui_press_owner,
        UI_PRESENTATION_SCROLLBAR_ID, &ui_runtime^.text_scroll_dragging,
        &ui_runtime^.text_scroll_drag_off)
    ui_runtime^.view_text_scroll_y = max(0, requested_y)
    return true
}

//   Update and commit the presentation scroll container.
prepare_presentation_scroll :: proc(
    state: ^core.Euclid_General_State,
    text_panel: geometry.Rectangle,
    content_height: f32,
    scroll_step: f32,
    mouse_input: Input_Frame) -> Scroll_Container_Update_Result {
    ui_runtime := &state^.ui_runtime
    scroll := scroll_container_update({id = UI_PRESENTATION_SCROLLBAR_ID,
        rect = text_panel, scroll_y_in = ui_runtime^.view_text_scroll_y,
        content_height = content_height, mouse_input = mouse_input,
        interaction_space_rect = text_panel,
        wheel_step = scroll_step * WHEEL_SCROLL_MULTIPLIER,
        press_owner = &ui_runtime^.ui_press_owner,
        state_in = {ui_runtime^.text_scroll_dragging,
            ui_runtime^.text_scroll_drag_off}})
    ui_runtime^.view_text_scroll_y = scroll.scroll_y_out
    ui_runtime^.text_scroll_dragging = scroll.state_out.is_dragging_thumb
    ui_runtime^.text_scroll_drag_off = scroll.state_out.drag_offset_y
    return scroll
}

//   Resolve copy and selection interaction against prepared presentation layout.
prepare_presentation_content_interaction :: proc(
    state: ^core.Euclid_General_State,
    request: Presentation_Content_Interaction) -> ui_dynview.Dynview_Selection_View {
    ui_runtime := &state^.ui_runtime
    dyncompile.refresh_presentation_copy_targets(&state.dynview, {
        panel = geometry.Rectangle(request.scroll.view_rect),
        scroll_y = request.scroll.scroll_y_out,
        text_padding = TEXT_PADDING, icon_size = DYNVIEW_COPY_ICON_SIZE,
        icon_x_pad = DYNVIEW_COPY_ICON_X_PAD})
    copy_dt := min(f32(0.05), max(f32(0), request.frame_dt))
    _ = view_core.prepare_copy_icons(&state^.dynview,
        request.mouse_input, copy_dt,
        &ui_runtime^.ui_press_owner)
    selection_view := ui_dynview.Dynview_Selection_View{
        panel = geometry.Rectangle(request.scroll.view_rect),
        scroll_y = request.scroll.scroll_y_out, text_padding = TEXT_PADDING,
        row_height = TEXT_ROW_HEIGHT, wrap_advance = TEXT_WRAP_ADVANCE,
        fallback_text = request.view_text}
    content := ui_dynview.dynview_selection_content(
        &state^.dynview, request.view_text)
    selection := &ui_runtime^.dynview_selection
    ui_dynview.dynview_selection_reconcile(selection, content)
    ui_dynview.dynview_selection_update_mouse({runtime = &state^.dynview,
        selection = selection, press_owner = &ui_runtime^.ui_press_owner,
        content = content, view = selection_view, frame = request.mouse_input})
    if request.keyboard_enabled {
        ui_dynview.dynview_selection_update_keyboard(
            &state^.dynview, selection, content,
            request.view_text, request.mouse_input)
    }
    return selection_view
}

//   Resolve post-layout presentation interaction before rendering.
prepare_presentation_interaction :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: Input_Frame,
    keyboard_enabled: bool,
    frame_dt: f32) -> Presentation_Preparation {
    if state != nil {
        state^.ui_runtime.view_text_scroll_max = 0
    }
    if state == nil || state^.julia_interface == nil || is_terminal_selected(state) {
        return {}
    }
    if !ui_presentation_is_visible(&state^.ui_runtime) { return {} }
    text_panel := view_text_content_panel(panel)
    view_text := julia.current_view_snapshot_text(state)
    content_h := dynlayout.presentation_content_height_or_fallback(&state.dynview,
        geometry.Rectangle(text_panel), {text_padding = TEXT_PADDING,
            wrap_advance = TEXT_WRAP_ADVANCE, row_height = TEXT_ROW_HEIGHT,
            text = view_text})
    state^.ui_runtime.view_text_scroll_max = max(0, content_h - text_panel.height)
    scroll_step := dynlayout.presentation_scroll_step_or_fallback(
        &state.dynview, TEXT_ROW_HEIGHT)
    scroll := prepare_presentation_scroll(
        state, text_panel, content_h, scroll_step, mouse_input)
    selection_view := prepare_presentation_content_interaction(state,
        {scroll, view_text, mouse_input, keyboard_enabled, frame_dt})
    return {true, scroll.view_rect, view_text, scroll, selection_view}
}

