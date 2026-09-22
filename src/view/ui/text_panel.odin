package ui

import native "../native"

import viewmodel "../model"

import "../../core"
import dyncompile "../../dynview/compile"
import dynlayout "../../dynview/layout"
import julia "../../bridge"
import view_core "../core"
import "../font"
import ui_dynview "./dynview"

import rl "vendor:raylib"

//   Prepared post-layout interaction state for one non-Terminal presentation.
Presentation_Preparation :: struct {
    active: bool,
    text_panel: rl.Rectangle,
    view_text: string,
    scroll: Scroll_Container_Update_Result,
    selection_view: ui_dynview.Dynview_Selection_View,
}

//   Compute the bordered viewport used by text and Terminal presentations.
view_text_content_panel :: proc(panel: rl.Rectangle) -> rl.Rectangle {
    panel_geometry := container_geometry(panel, 1)
    text_panel := rl.Rectangle{
        panel_geometry.inner_rect.x + 5,
        panel_geometry.inner_rect.y + 5,
        panel_geometry.inner_rect.width - 10,
        panel_geometry.inner_rect.height - 10,
    }
    return container_geometry(text_panel, 1).drawn_rect
}

//   Draw selection behind one non-Terminal presentation.
view_text_draw_selection :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    selection_view: ui_dynview.Dynview_Selection_View) {
    ui_dynview.dynview_selection_draw(
        &state^.dynview, ui_runtime^.dynview_selection, selection_view)
}

//   Draw the view-text transcript content and copy affordances.
view_text_draw_content :: proc(
    state: ^core.Euclid_General_State,
    ui_runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    text_panel: rl.Rectangle,
    view_text: string,
    selection_view: ui_dynview.Dynview_Selection_View) {
    view_text_draw_selection(state, ui_runtime, selection_view)

    fallback := ui_dynview.Fallback_Text_Content{
        view_text, native.to_raylib_color(UI_TEXT_COLOR),
    }
    ui_dynview.draw_presentation_styled_or_fallback(state, ui_runtime, fallback,
        ui_dynview.Presentation_Draw_Params{
            panel = text_panel,
            scroll_y = state^.ui_runtime.view_text_scroll_y,
            font = font.cache_borrow(&state.font_cache, .Regular),
            font_cache = &state.font_cache,
            metrics = ui_dynview.Wrapped_Text_Metrics{
                padding = TEXT_PADDING,
                row_height = TEXT_ROW_HEIGHT,
                wrap_advance = TEXT_WRAP_ADVANCE,
                font_size = TREE_FONT_SIZE,
            },
        })

    view_core.draw_copy_icons(&state^.dynview, text_panel)
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
    text_panel: rl.Rectangle,
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
    scroll: Scroll_Container_Update_Result,
    view_text: string,
    mouse_input: Input_Frame,
    keyboard_enabled: bool) -> ui_dynview.Dynview_Selection_View {
    ui_runtime := &state^.ui_runtime
    dyncompile.refresh_presentation_copy_targets(&state.dynview, {
        panel = scroll.view_rect, scroll_y = scroll.scroll_y_out,
        text_padding = TEXT_PADDING, icon_size = DYNVIEW_COPY_ICON_SIZE,
        icon_x_pad = DYNVIEW_COPY_ICON_X_PAD})
    frame_dt := min(f32(0.05), max(f32(0), rl.GetFrameTime()))
    _ = view_core.prepare_copy_icons(&state^.dynview, mouse_input, frame_dt,
        &ui_runtime^.ui_press_owner)
    selection_view := ui_dynview.Dynview_Selection_View{panel = scroll.view_rect,
        scroll_y = scroll.scroll_y_out, text_padding = TEXT_PADDING,
        row_height = TEXT_ROW_HEIGHT, wrap_advance = TEXT_WRAP_ADVANCE,
        fallback_text = view_text}
    content := ui_dynview.dynview_selection_content(&state^.dynview, view_text)
    selection := &ui_runtime^.dynview_selection
    ui_dynview.dynview_selection_reconcile(selection, content)
    ui_dynview.dynview_selection_update_mouse({runtime = &state^.dynview,
        selection = selection, press_owner = &ui_runtime^.ui_press_owner,
        content = content, view = selection_view, frame = mouse_input})
    if keyboard_enabled {
        ui_dynview.dynview_selection_update_keyboard(
            &state^.dynview, selection, content, view_text, mouse_input)
    }
    return selection_view
}

//   Resolve post-layout presentation interaction before rendering.
prepare_presentation_interaction :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    mouse_input: Input_Frame,
    keyboard_enabled: bool) -> Presentation_Preparation {
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
        text_panel, {text_padding = TEXT_PADDING,
            wrap_advance = TEXT_WRAP_ADVANCE, row_height = TEXT_ROW_HEIGHT,
            text = view_text})
    state^.ui_runtime.view_text_scroll_max = max(0, content_h - text_panel.height)
    scroll_step := dynlayout.presentation_scroll_step_or_fallback(
        &state.dynview, TEXT_ROW_HEIGHT)
    scroll := prepare_presentation_scroll(
        state, text_panel, content_h, scroll_step, mouse_input)
    selection_view := prepare_presentation_content_interaction(
        state, scroll, view_text, mouse_input, keyboard_enabled)
    return {true, scroll.view_rect, view_text, scroll, selection_view}
}

//   Render wrapped animation view text with scroll handling.
draw_view_text_panel :: proc(
    state: ^core.Euclid_General_State,
    panel: rl.Rectangle,
    terminal_frame: Terminal_Prepared_Frame,
    presentation: Presentation_Preparation) {
    if state == nil || state.julia_interface == nil {
        return
    }
    if !ui_presentation_is_visible(&state^.ui_runtime) { return }

    ui_runtime := &state.ui_runtime
    _ = draw_container(panel, .Dark_Red)
    text_panel := view_text_content_panel(panel)
    text_panel = draw_container(text_panel, .Grey).drawn_rect

    if is_terminal_selected(state) {
        terminal_draw(state, terminal_frame)
        return
    }

    if !presentation.active { return }
    scroll_container_draw_begin(presentation.scroll)
    view_text_draw_content(state, ui_runtime, presentation.text_panel,
        presentation.view_text, presentation.selection_view)
    scroll_container_draw_end(presentation.scroll)
}
