package uipresentation

import geometry "../../../core/geometry"
import native "../../native"
import core "../../../core"
import animation_model "../../../core/animation"
import dynlayout "../../../dynview/layout"
import julia "../../../bridge"
import font "../../font"
import ui_dynview "../dynview"
import viewmodel "../model"
import viewmessages "../../messages"
import uiwidgets "../widgets"
import viewtext "../text"
import input "../../input"
import theme "../theme"
import uisemantics "../semantics"
import worldmodel "../../world/model"
import uiterminal "../terminal"
import uiaccordion "../layout/accordion"
import uilibrary "../library"
import uisplitter "../layout/splitter"
import log "core:log"

PRESENTATION_NOTE_SPLITTER_HEIGHT :: f32(8)
PRESENTATION_NOTE_ACTION_HEIGHT :: f32(24)
PRESENTATION_NOTE_TEXT_PADDING :: f32(8)

//   Prepared post-layout interaction state for one non-Terminal presentation.
Presentation_Preparation :: struct {
    active: bool,
    text_panel: geometry.Rectangle,
    view_text: string,
    scroll: uiwidgets.Scroll_Container_Update_Result,
    selection_view: ui_dynview.Dynview_Selection_View,
    note_layout: Presentation_Note_Layout,
    note_input_params: uiwidgets.Input_Box_Params,
    note_input: uiwidgets.Input_Box_Result,
    note_done_params: uiwidgets.Text_Button_Params,
    note_done: uiwidgets.Text_Button_Result,
    note_order: uiwidgets.Checkbox_Result,
}

// Presentation_Note_Layout keeps one reading viewport or an original/editor split.
Presentation_Note_Layout :: struct {
    active: bool,
    editing: bool,
    original_panel: geometry.Rectangle,
    splitter: geometry.Rectangle,
    editor_panel: geometry.Rectangle,
    editor_clip: geometry.Rectangle,
    done_rect: geometry.Rectangle,
    order_rect: geometry.Rectangle,
    original_content_height: f32,
    content_height: f32,
}

// Presentation_Note_Editor_Preparation borrows one frame's local editing controls.
Presentation_Note_Editor_Preparation :: struct {
    input_params: uiwidgets.Input_Box_Params,
    input: uiwidgets.Input_Box_Result,
    done_params: uiwidgets.Text_Button_Params,
    done: uiwidgets.Text_Button_Result,
    order: uiwidgets.Checkbox_Result,
}

// Presentation_Content_Interaction groups one prepared interaction request.
Presentation_Content_Interaction :: struct {
    scroll: uiwidgets.Scroll_Container_Update_Result,
    view_text: string,
    selection_view: ui_dynview.Dynview_Selection_View,
    original_screen: geometry.Rectangle,
    mouse_input: input.Input_Frame,
    keyboard_enabled: bool,
}

// Presentation_Interaction_Layout holds one frame's scroll and note geometry.
Presentation_Interaction_Layout :: struct {
    text_panel: geometry.Rectangle,
    view_text: string,
    note_layout: Presentation_Note_Layout,
    scroll: uiwidgets.Scroll_Container_Update_Result,
    text_percent: int,
}

// Presentation_Interaction_Views contains the composed document's selection viewport.
Presentation_Interaction_Views :: struct {
    selection: ui_dynview.Dynview_Selection_View,
    original_screen: geometry.Rectangle,
}

// presentation_note_is_current rejects notes owned by another selection or generation.
presentation_note_is_current :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_interface == nil {
        return false
    }
    note := &state^.ui_runtime.library.collection_note
    animation := state^.julia_interface.current_animation
    return note^.status == .Ready &&
        note^.generation == state^.animation_memory.generation &&
        animation != nil && animation^.stable_id == note^.animation_id &&
        note^.identity.entry_id == state^.ui_runtime.library.tree.selected_item_id
}

// presentation_note_text borrows only the selected placement's animation-owned bytes.
presentation_note_text :: proc(state: ^core.Euclid_General_State) -> string {
    if !presentation_note_is_current(state) ||
       state^.animation_memory.note_buffer == nil {
        return ""
    }
    note := &state^.ui_runtime.library.collection_note
    return string(state^.animation_memory.note_buffer[:note^.text_length])
}

// Build one compact split with bounded, non-overlapping original and editor regions.
presentation_note_edit_layout :: proc(
    panel: geometry.Rectangle, ratio: f32,
    text_percent: int) -> Presentation_Note_Layout {
    splitter_height := theme.ui_scaled_metric(
        PRESENTATION_NOTE_SPLITTER_HEIGHT, text_percent)
    padding := theme.ui_scaled_metric(PRESENTATION_NOTE_TEXT_PADDING, text_percent)
    action_limit := theme.ui_scaled_metric(
        PRESENTATION_NOTE_ACTION_HEIGHT, text_percent)
    available := max(0, panel.height-splitter_height)
    original_height := presentation_note_original_split_height(
        available, ratio, text_percent)
    splitter: geometry.Rectangle = {
        panel.x, panel.y + original_height, panel.width,
        min(splitter_height, max(0, panel.height-original_height))}
    editor_y := splitter.y + splitter.height
    editor_height := max(0, panel.y+panel.height-editor_y)
    footer_rows := f32(2) if panel.width <
        theme.ui_scaled_metric(360, text_percent) else 1
    footer_height := min(action_limit*footer_rows, editor_height)
    done_height := footer_height/footer_rows
    footer_y := editor_y+editor_height-footer_height
    done_width := min(theme.ui_scaled_metric(156, text_percent),
        max(0, panel.width-padding*2))
    editor: geometry.Rectangle = {
        panel.x+padding,
        editor_y+padding,
        max(0, panel.width-padding*2),
        max(0, editor_height-padding-footer_height),
    }
    done: geometry.Rectangle = {
        panel.x+max(padding, panel.width-padding-done_width),
        editor_y+editor_height-done_height,
        done_width, done_height,
    }
    return {
        active = true,
        editing = true,
        original_panel = {panel.x, panel.y, panel.width, original_height},
        splitter = splitter,
        editor_panel = editor,
        editor_clip = {panel.x, editor_y, panel.width, editor_height},
        original_content_height = original_height,
        done_rect = done,
        order_rect = {panel.x+padding, footer_y, done_height, done_height},
    }
}

// Keep both split regions usable when the viewport can fit their minimum heights.
presentation_note_original_split_height :: proc(
    available, ratio: f32, text_percent: int) -> f32 {
    original_height := available * clamp(ratio, f32(0.25), f32(0.75))
    minimum_original := theme.ui_scaled_metric(80, text_percent)
    minimum_editor := theme.ui_scaled_metric(104, text_percent)
    if available >= minimum_original+minimum_editor {
        return clamp(original_height, minimum_original, available-minimum_editor)
    }
    return available * f32(0.32)
}

// Reading uses the published composition in one stationary presentation viewport.
presentation_note_reading_layout :: proc(
    panel: geometry.Rectangle, original_height: f32) -> Presentation_Note_Layout {
    layout: Presentation_Note_Layout = {
        original_content_height = original_height,
        content_height = original_height,
        original_panel = panel,
    }
    return layout
}

// Measure only the unchanged predefined presentation before adding a note section.
presentation_original_content_height :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    text: string) -> f32 {
    scale := state^.ui_runtime.preferences.values.interface.text_size_percent
    return dynlayout.presentation_content_height_or_fallback(&state^.dynview, panel, {
        text_padding = theme.ui_scaled_metric(theme.TEXT_PADDING, scale),
        wrap_advance = theme.ui_scaled_metric(theme.TEXT_WRAP_ADVANCE, scale),
        row_height = theme.ui_scaled_metric(theme.TEXT_ROW_HEIGHT, scale),
        text = text,
    })
}


// prepare_presentation_visual borrows current content without selection or scroll mutations.
prepare_presentation_visual :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle) -> Presentation_Preparation {
    if state^.julia_interface == nil || uiterminal.is_terminal_selected(state) {
        return {}
    }
    base_panel := uiwidgets.text_content_panel(panel)
    text := julia.current_view_snapshot_text(state)
    text_percent := state^.ui_runtime.preferences.values.interface.text_size_percent
    row_height := theme.ui_scaled_metric(theme.TEXT_ROW_HEIGHT, text_percent)
    original_height := presentation_original_content_height(state, base_panel, text)
    note := &state^.ui_runtime.library.collection_note
    editing := presentation_note_is_current(state) && note^.editing
    note_layout := presentation_note_edit_layout(
        base_panel, note^.split_ratio, text_percent) if editing else
        presentation_note_reading_layout(base_panel, original_height)
    content_height := note_layout.content_height
    scroll_panel := geometry.Rectangle(base_panel)
    if note_layout.editing {
        content_height = original_height
        scroll_panel = note_layout.original_panel
    }
    step := dynlayout.presentation_scroll_step_or_fallback(
        &state^.dynview, row_height)
    scroll := uiwidgets.scroll_container_visual(
        scroll_panel, content_height, state^.ui_runtime.presentation.text_scroll_y, step,
        state^.ui_runtime.preferences.values.interface.control_size_percent)
    result: Presentation_Preparation = {
        active = true,
        text_panel = base_panel,
        view_text = text,
        scroll = scroll,
        note_layout = note_layout,
    }
    presentation_prepare_visual_selection(state, &result)
    return result
}

// Derive clipped selection views from a fully prepared non-interactive presentation.
presentation_prepare_visual_selection :: proc(
    state: ^core.Euclid_General_State,
    preparation: ^Presentation_Preparation) {
    scale := state^.ui_runtime.preferences.values.interface.text_size_percent
    text_padding := theme.ui_scaled_metric(theme.TEXT_PADDING, scale)
    row_height := theme.ui_scaled_metric(theme.TEXT_ROW_HEIGHT, scale)
    wrap_advance := theme.ui_scaled_metric(theme.TEXT_WRAP_ADVANCE, scale)
    layout := preparation^.note_layout
    panel := preparation^.text_panel
    preparation^.selection_view = {
        panel = {layout.original_panel.x, panel.y,
            layout.original_panel.width, preparation^.scroll.view_rect.height},
        scroll_y = preparation^.scroll.scroll_y_out-
            (layout.original_panel.y-panel.y),
        text_padding = text_padding,
        row_height = row_height,
        wrap_advance = wrap_advance,
        fallback_text = preparation^.view_text,
    }
}

// presentation_semantic_id identifies one compiled document generation.
presentation_semantic_id :: #force_inline proc(
    state: ^core.Euclid_General_State) -> viewmodel.Ui_Node_Id {
    if state == nil {
        return {}
    }
    return {
        domain = .Presentation,
        generation = state^.dynview.compile_cache.compiled_revision,
    }
}

// register_presentation_semantics publishes the focused document surface.
register_presentation_semantics :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    scroll: uiwidgets.Scroll_Container_Update_Result) {
    id := presentation_semantic_id(state)
    _ = uisemantics.semantic_register_control(state^.ui_runtime.semantic_focus, {
        id = id,
        role = .Document,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Select, .Copy, .Scroll, .Show_Context_Menu},
        region = .Presentation,
        traversal_order = 0,
        bounds = geometry.Rectangle(panel),
        clip_bounds = geometry.Rectangle(
            uiaccordion.ui_presentation_clip(&state^.ui_runtime.layout, panel)),
        numeric_range = {
            f64(scroll.minimum),
            f64(scroll.maximum),
            f64(scroll.scroll_y_out),
            f64(scroll.step),
            scroll.orientation,
            true,
        },
        label = viewmessages.shell_message(state, .Presentation_Accessible_Label),
    })
    semantic := state^.ui_runtime.semantic_focus
    owns_presentation := semantic^.logical_focus.domain == .Presentation
    if !state^.ui_runtime.context_menu.active && !owns_presentation &&
        state^.ui_runtime.input.interaction.logical_focus.kind == .Presentation {
        _ = uisemantics.semantic_request_pointer_focus(semantic, id)
    }
}

// draw_encoded_presentation_geometry encodes panel and cached non-glyph content.
draw_encoded_presentation_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    panel: geometry.Rectangle) {
    if state == nil || state^.julia_interface == nil {
        return
    }
    _ = native.draw_encoder_rectangle(
        encoder, panel, worldmodel.BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, panel, 1, theme.UI_BORDER_COLOR)
    text_panel := uiwidgets.text_content_panel(panel)
    if uiterminal.is_terminal_selected(state) {
        _ = native.draw_encoder_rectangle(
            encoder, text_panel, theme.UI_COMPONENT_BACKGROUND_COLOR)
        _ = native.draw_encoder_rectangle_outline(
            encoder, text_panel, 1, theme.UI_BORDER_COLOR)
        return
    }
    layout := presentation_current_note_layout(state, text_panel)
    presentation_draw_note_geometry(state, encoder, &layout)
    _ = native.draw_encoder_rectangle(
        encoder, layout.original_panel, theme.UI_COMPONENT_BACKGROUND_COLOR)
    _ = native.draw_encoder_rectangle_outline(
        encoder, layout.original_panel, 1, theme.UI_BORDER_COLOR)
    text_percent := state^.ui_runtime.preferences.values.interface.text_size_percent
    ui_dynview.draw_encoded_geometry({
        state = state,
        runtime = &state^.dynview,
        encoder = encoder,
        panel = geometry.Rectangle(layout.original_panel),
        scroll_y = state^.ui_runtime.presentation.text_scroll_y,
        text_padding = theme.ui_scaled_metric(theme.TEXT_PADDING, text_percent),
    })
}

// Resolve the current note mode without mutating scroll, splitter, or input state.
presentation_current_note_layout :: proc(
    state: ^core.Euclid_General_State,
    text_panel: geometry.Rectangle) -> Presentation_Note_Layout {
    note := &state^.ui_runtime.library.collection_note
    text_percent := state^.ui_runtime.preferences.values.interface.text_size_percent
    if presentation_note_is_current(state) && note^.editing {
        return presentation_note_edit_layout(text_panel, note^.split_ratio, text_percent)
    }
    view_text := julia.current_view_snapshot_text(state)
    original_height := presentation_original_content_height(state, text_panel, view_text)
    return presentation_note_reading_layout(text_panel, original_height)
}

// Encode the distinct background and splitter surfaces for the active note mode.
presentation_draw_note_geometry :: proc(
    state: ^core.Euclid_General_State,
    encoder: ^native.Draw_Encoder,
    layout: ^Presentation_Note_Layout) {
    if layout^.editing {
        _ = native.draw_encoder_rectangle(
            encoder, layout^.editor_clip, theme.UI_COMPONENT_BACKGROUND_COLOR)
        _ = native.draw_encoder_rectangle_outline(
            encoder, layout^.editor_clip, 1, theme.UI_BORDER_COLOR)
        if state^.ui_runtime.library.collection_note.splitter_hovered {
            line := layout^.splitter
            visible_height := uisplitter.SPLITTER_VISIBLE_WIDTH*
                theme.ui_control_size_scale(
                    state^.ui_runtime.preferences.values.interface.control_size_percent)
            line.y += (line.height-visible_height)*0.5
            line.height = min(visible_height, line.height)
            _ = native.draw_encoder_rectangle(
                encoder, line, uisplitter.SPLITTER_ACTIVE_COLOR)
        }
    }
}

// Draw clipped Dynview or fallback content, then its prepared scrollbar overlay.
draw_encoded_presentation_text :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    presentation: Presentation_Preparation) {
    if state == nil || encoder == nil || !presentation.active {
        return
    }
    _ = native.draw_encoder_push_scissor(
        encoder, geometry.Rectangle(presentation.text_panel))
    fallback: ui_dynview.Fallback_Text_Content = {
        presentation.view_text, theme.draw_color(encoder, .Text)}
    text_percent := state^.ui_runtime.preferences.values.interface.text_size_percent
    params: ui_dynview.Presentation_Draw_Params = {
        encoder = encoder,
        panel = geometry.Rectangle(presentation.note_layout.original_panel),
        scroll_y = state^.ui_runtime.presentation.text_scroll_y,
        font = font.cache_borrow(&state^.font_cache, .Regular),
        font_cache = &state^.font_cache,
        metrics = {
            padding = theme.ui_scaled_metric(theme.TEXT_PADDING, text_percent),
            row_height = theme.ui_scaled_metric(theme.TEXT_ROW_HEIGHT, text_percent),
            wrap_advance = theme.ui_scaled_metric(theme.TEXT_WRAP_ADVANCE, text_percent),
            font_size = theme.ui_font_size(text_percent),
        },
    }
    _ = native.draw_encoder_push_scissor(encoder, params.panel)
    ui_dynview.draw_presentation_styled_or_fallback(
        state, &state^.ui_runtime, fallback, params)
    selected: ui_dynview.Presentation_Selection_Draw = {
        state, &state^.ui_runtime, fallback, params}
    ui_dynview.draw_presentation_selection(&selected, {
        encoder = encoder,
        runtime = &state^.dynview,
        selection = state^.ui_runtime.presentation.selection,
        view = presentation.selection_view,
    })
    _ = native.draw_encoder_pop_scissor(encoder)
    if presentation.note_layout.editing {
        presentation_draw_note_editor(state, encoder, presentation)
    }
    _ = native.draw_encoder_pop_scissor(encoder)
    uiwidgets.draw_encoded_scrollbar(encoder, presentation.scroll.scrollbar)
}

// Draw the multiline editor and its locally reachable Done action.
presentation_draw_note_editor :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    presentation: Presentation_Preparation) {
    uiwidgets.draw_encoded_input_box(
        encoder, presentation.note_input_params, presentation.note_input)
    presentation_draw_note_done(state, encoder, presentation)
    order := presentation.note_order
    uiwidgets.draw_encoded_checkbox_geometry(encoder, order.box_rect,
        order.checked_out, theme.ui_control_size_scale(
            state^.ui_runtime.preferences.values.interface.control_size_percent))
    viewtext.draw_encoded_colored_label(&state^.font_cache, encoder,
        viewmessages.shell_message(state, .Library_Notes_On_Top),
        {order.label_rect.x, order.label_rect.y}, theme.draw_color(encoder, .Text))
    presentation_draw_note_footer_focus(state, encoder, presentation)
}

// Keep both placement-qualified footer controls visibly focused during keyboard use.
presentation_draw_note_footer_focus :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    presentation: Presentation_Preparation) {
    semantic := state^.ui_runtime.semantic_focus
    note := state^.ui_runtime.library.collection_note
    if semantic == nil || !semantic^.window_focused ||
        semantic^.focus_origin != .Keyboard ||
        semantic^.logical_focus.domain != .Presentation ||
        semantic^.logical_focus.stable_id != note.identity.entry_id ||
        semantic^.logical_focus.generation != note.request_id {
        return
    }
    bounds: geometry.Rectangle
    switch semantic^.logical_focus.local_id {
    case viewmodel.LIBRARY_COLLECTION_NOTE_DONE_ID:
        bounds = presentation.note_done.control_geometry.bounds
    case viewmodel.LIBRARY_COLLECTION_NOTE_ORDER_ID:
        bounds = presentation.note_order.control_geometry.bounds
    case:
        return
    }
    _ = native.draw_encoder_push_scissor(encoder, presentation.note_layout.editor_clip)
    uiwidgets.draw_encoded_focus_ring(encoder, bounds,
        theme.ui_control_size_scale(
            state^.ui_runtime.preferences.values.interface.control_size_percent))
    _ = native.draw_encoder_pop_scissor(encoder)
}

// Draw the local Done control independently of the Library drawer visibility.
presentation_draw_note_done :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    presentation: Presentation_Preparation) {
    rect := presentation.note_done_params.rect
    fill := theme.UI_COMPONENT_BACKGROUND_COLOR
    if presentation.note_done.hovered || presentation.note_done.pressed {
        fill = theme.UI_HOVER_COLOR
    }
    _ = native.draw_encoder_rectangle(encoder, rect, fill)
    _ = native.draw_encoder_rectangle_outline(
        encoder, rect, 1, theme.draw_color(encoder, .Control_Border))
    viewtext.draw_encoded_colored_label(&state^.font_cache, encoder,
        presentation.note_done_params.label,
        {rect.x+PRESENTATION_NOTE_TEXT_PADDING, rect.y+
            max(0, (rect.height-theme.ui_font_size(
                state^.ui_runtime.preferences.values.interface.text_size_percent))*0.5)},
        theme.draw_color(encoder, .Text))
}


//   Report whether the display currently owns a non-Terminal presentation surface.
presentation_scroll_is_available :: #force_inline proc(
    state: ^core.Euclid_General_State) -> bool {

    return state != nil && state^.julia_interface != nil &&
        state^.julia_interface^.selected_animation != nil &&
        !uiterminal.is_terminal_selected(state) &&
        ui_presentation_is_visible(&state^.ui_runtime.presentation)
}

//   Apply a requested presentation scroll before the next layout interaction pass.
set_presentation_scroll_position :: proc(
    state: ^core.Euclid_General_State, requested_y: f32) -> bool {

    if !presentation_scroll_is_available(state) {
        return false
    }
    ui_runtime := &state^.ui_runtime
    uiwidgets.scroll_container_release_press(&ui_runtime^.input.press_owner,
        UI_PRESENTATION_SCROLLBAR_ID, &ui_runtime^.presentation.scroll_dragging,
        &ui_runtime^.presentation.scroll_drag_off)
    ui_runtime^.presentation.text_scroll_y = max(0, requested_y)
    return true
}

//   Update and commit the presentation scroll container.
prepare_presentation_scroll :: proc(
    state: ^core.Euclid_General_State,
    text_panel: geometry.Rectangle,
    content_height: f32,
    scroll_step: f32,
    mouse_input: input.Input_Frame) -> uiwidgets.Scroll_Container_Update_Result {
    ui_runtime := &state^.ui_runtime
    scroll := uiwidgets.scroll_container_update({
        id = UI_PRESENTATION_SCROLLBAR_ID,
        rect = text_panel,
        scroll_y_in = ui_runtime^.presentation.text_scroll_y,
        content_height = content_height,
        mouse_input = mouse_input,
        interaction_space_rect = text_panel,
        wheel_step = scroll_step * theme.WHEEL_SCROLL_MULTIPLIER,
        control_size_percent =
            ui_runtime^.preferences.values.interface.control_size_percent,
        press_owner = &ui_runtime^.input.press_owner,
        state_in = {ui_runtime^.presentation.scroll_dragging,
            ui_runtime^.presentation.scroll_drag_off},
        semantic_focus = ui_runtime^.semantic_focus,
        semantic_id = presentation_semantic_id(state),
    })
    ui_runtime^.presentation.text_scroll_y = scroll.scroll_y_out
    ui_runtime^.presentation.scroll_dragging = scroll.state_out.is_dragging_thumb
    ui_runtime^.presentation.scroll_drag_off = scroll.state_out.drag_offset_y
    return scroll
}

// Capture the internal horizontal splitter without touching pane-layout state.
presentation_note_splitter_update :: proc(
    state: ^core.Euclid_General_State, panel: geometry.Rectangle,
    frame: input.Input_Frame) -> Presentation_Note_Layout {
    note := &state^.ui_runtime.library.collection_note
    text_percent := state^.ui_runtime.preferences.values.interface.text_size_percent
    layout := presentation_note_edit_layout(panel, note^.split_ratio, text_percent)
    note^.splitter_rect = layout.splitter
    owner := &state^.ui_runtime.input.press_owner
    point := uiwidgets.input_frame_mouse_position(frame)
    owns := owner^.active && owner^.kind == .Splitter &&
        owner^.id == viewmodel.PRESENTATION_NOTE_SPLITTER_ID
    hovered := geometry.rectangle_contains(layout.splitter, point)
    if !owner^.active && hovered && uiwidgets.input_frame_left_pressed(frame) {
        owner^ = {
            active = true,
            kind = .Splitter,
            id = viewmodel.PRESENTATION_NOTE_SPLITTER_ID,
        }
        owns = true
    }
    if owns && (uiwidgets.input_frame_left_down(frame) ||
        uiwidgets.input_frame_left_released(frame)) {
        note^.split_ratio = clamp(
            (point.y-panel.y)/max(1, panel.height-layout.splitter.height),
            f32(0.25), f32(0.75))
        layout = presentation_note_edit_layout(panel, note^.split_ratio, text_percent)
        note^.splitter_rect = layout.splitter
    }
    if owns && uiwidgets.input_frame_left_released(frame) {
        owner^ = {}
    }
    if hovered || owns {
        state^.ui_runtime.input.cursor = .Resize_Ns
    }
    note^.splitter_hovered = hovered || owns
    return layout
}

// Register the editor parent before publishing its input and local Done child.
presentation_register_note_editor_panel :: proc(
    state: ^core.Euclid_General_State,
    layout: Presentation_Note_Layout) -> viewmodel.Ui_Node_Id {
    note := &state^.ui_runtime.library.collection_note
    label := viewmessages.shell_message(state, .Library_Edit_Notes)
    id: viewmodel.Ui_Node_Id = {
        domain = .Presentation,
        local_id = 6420,
        stable_id = note^.identity.entry_id,
        generation = note^.request_id,
    }
    _ = uisemantics.semantic_register_control(state^.ui_runtime.semantic_focus, {
        id = id,
        parent = presentation_semantic_id(state),
        role = .Panel,
        states = {.Visible, .Enabled},
        region = .Presentation,
        traversal_order = 1,
        bounds = layout.editor_clip,
        clip_bounds = uiaccordion.ui_presentation_clip(
            &state^.ui_runtime.layout, layout.editor_clip),
        label = label,
    })
    return id
}

// Prepare both editor controls against the active placement's animation-owned bytes.
presentation_prepare_note_editor :: proc(
    state: ^core.Euclid_General_State, layout: Presentation_Note_Layout,
    frame: input.Input_Frame) -> Presentation_Note_Editor_Preparation {
    note := &state^.ui_runtime.library.collection_note
    editor: Presentation_Note_Editor_Preparation
    buffer := state^.animation_memory.note_buffer
    if len(buffer) != animation_model.ANIMATION_NOTE_BUFFER_CAPACITY {
        log.error("collection_note_editor_buffer_unavailable")
        return editor
    }
    note^.editor_rect = layout.editor_panel
    note^.editor_clip_rect = layout.editor_clip
    note^.done_rect = layout.done_rect
    parent := presentation_register_note_editor_panel(state, layout)
    editor.order = presentation_prepare_note_order(state, layout, frame, parent)
    note^.order_rect = editor.order.control_geometry.bounds
    presentation_prepare_note_done(state, layout, frame, parent, &editor)
    editor.input_params = presentation_note_input_params(
        state, parent, layout, frame, buffer)
    editor.input = uiwidgets.input_box_prepare(
        editor.input_params, &state^.ui_runtime.input.press_owner)
    editor.input_params.descriptor = editor.input.descriptor
    if editor.input.changed && !uilibrary.library_collection_note_edit(state) {
        log.error("collection_note_editor_revision_rejected")
    }
    return editor
}

// Publish the placement-qualified reading-order toggle beside the editor's Done action.
presentation_prepare_note_order :: proc(
    state: ^core.Euclid_General_State, layout: Presentation_Note_Layout,
    frame: input.Input_Frame, parent: viewmodel.Ui_Node_Id) -> uiwidgets.Checkbox_Result {
    note := &state^.ui_runtime.library.collection_note
    id: viewmodel.Ui_Node_Id = {
        domain = .Presentation,
        local_id = viewmodel.LIBRARY_COLLECTION_NOTE_ORDER_ID,
        stable_id = note^.identity.entry_id,
        generation = note^.request_id,
    }
    scale := state^.ui_runtime.preferences.values.interface.text_size_percent
    label := viewmessages.shell_message(state, .Library_Notes_On_Top)
    result := uiwidgets.update_checkbox({
        id = viewmodel.LIBRARY_COLLECTION_NOTE_ORDER_ID,
        rect = layout.order_rect,
        checked = note^.notes_on_top,
        enabled = true,
        mouse = frame,
        interaction_space_rect = layout.editor_clip,
        interaction_enabled = layout.editor_clip.height > 0,
        label = label,
        font = font.cache_borrow(&state^.font_cache, .Regular),
        label_font_size = theme.ui_font_size(scale),
        label_offset_x = theme.ui_scaled_metric(8, scale),
        label_offset_y = max(0, (layout.order_rect.height-theme.ui_font_size(scale))*0.5),
        semantic_clip = layout.editor_clip,
    }, &state^.ui_runtime.input.press_owner)
    presentation_apply_note_order(state, parent, id, label, &result)
    return result
}

// Converge pointer and semantic toggles through the ordinary persisted note revision.
presentation_apply_note_order :: proc(
    state: ^core.Euclid_General_State, parent, id: viewmodel.Ui_Node_Id,
    label: string, result: ^uiwidgets.Checkbox_Result) {
    semantic := state^.ui_runtime.semantic_focus
    if result^.toggled || uisemantics.semantic_command_requested(semantic, id, .Toggle) {
        if !uilibrary.library_collection_note_toggle_order(state) {
            log.error("collection_note_order_revision_rejected")
        }
        result^.checked_out = state^.ui_runtime.library.collection_note.notes_on_top
    }
    states: viewmodel.Ui_Node_State = {.Visible, .Enabled, .Focusable, .Tab_Stop}
    if result^.checked_out {
        states += {.Checked}
    }
    _ = uisemantics.semantic_register_control(semantic, {
        id = id,
        parent = parent,
        role = .Checkbox,
        states = states,
        actions = {.Focus, .Toggle},
        region = .Presentation,
        traversal_order = 4,
        bounds = result^.control_geometry.bounds,
        clip_bounds = result^.control_geometry.clip_bounds,
        label = label,
    })
    _ = uisemantics.semantic_focus_for_press(semantic,
        &state^.ui_runtime.input.press_owner, .Checkbox,
        viewmodel.LIBRARY_COLLECTION_NOTE_ORDER_ID, id)
}

// Prepare and activate the editor's durable-completion control.
presentation_prepare_note_done :: proc(
    state: ^core.Euclid_General_State,
    layout: Presentation_Note_Layout,
    frame: input.Input_Frame,
    parent: viewmodel.Ui_Node_Id,
    editor: ^Presentation_Note_Editor_Preparation) {
    note := &state^.ui_runtime.library.collection_note
    editor^.done_params = {
        id = viewmodel.LIBRARY_COLLECTION_NOTE_DONE_ID,
        rect = layout.done_rect,
        label = viewmessages.shell_message(state, .Library_Done_Editing),
        enabled = true,
        mouse = frame,
        interaction_space_rect = layout.editor_clip,
        interaction_enabled = layout.editor_clip.width > 0 &&
            layout.editor_clip.height > 0,
        font = font.cache_borrow(&state^.font_cache, .Regular),
        font_resolver = font.cache_terminal_resolver(&state^.font_cache),
        semantics = {
            publish = true,
            focus = state^.ui_runtime.semantic_focus,
            id = {
                domain = .Presentation,
                local_id = viewmodel.LIBRARY_COLLECTION_NOTE_DONE_ID,
                stable_id = note^.identity.entry_id,
                generation = note^.request_id,
            },
            parent = parent,
            role = .Button,
            states = uiwidgets.button_semantic_states(true),
            region = .Presentation,
            traversal_order = 5,
            clip_bounds = layout.editor_clip,
            label = viewmessages.shell_message(state, .Library_Done_Editing),
        },
    }
    editor^.done = uiwidgets.update_text_button(
        editor^.done_params, &state^.ui_runtime.input.press_owner)
    if editor^.done.action.activated {
        _ = uilibrary.library_collection_note_done(state)
    }
}

// Bind stable semantic identity and bounded editing storage for one frame.
presentation_note_input_params :: proc(
    state: ^core.Euclid_General_State, parent: viewmodel.Ui_Node_Id,
    layout: Presentation_Note_Layout, frame: input.Input_Frame,
    buffer: []u8) -> uiwidgets.Input_Box_Params {
    note := &state^.ui_runtime.library.collection_note
    id: viewmodel.Ui_Node_Id = {
        domain = .Presentation,
        local_id = viewmodel.LIBRARY_COLLECTION_NOTE_INPUT_ID,
        stable_id = note^.identity.entry_id,
        generation = note^.request_id,
    }
    text_percent := state^.ui_runtime.preferences.values.interface.text_size_percent
    return {
        rect = layout.editor_panel,
        clip_rect = layout.editor_clip,
        descriptor = {
            id = id,
            text_run_id = {
                domain = .Presentation,
                local_id = 6424,
                stable_id = note^.identity.entry_id,
                generation = note^.request_id,
            },
            parent = parent,
            region = .Presentation,
            traversal_order = 3,
            label = viewmessages.shell_message(state, .Library_Edit_Notes),
            text = string(buffer[:note^.text_length]),
            mode = .Editable,
            content_revision = note^.revision,
        },
        semantic_focus = state^.ui_runtime.semantic_focus,
        state = &note^.input,
        frame = frame,
        text_input_id = viewmodel.LIBRARY_COLLECTION_NOTE_INPUT_ID,
        focused = state^.ui_runtime.semantic_focus^.logical_focus == id,
        pointer_routed = true,
        padding = .Default,
        column_advance = theme.ui_scaled_metric(theme.TEXT_WRAP_ADVANCE, text_percent),
        font_size = theme.ui_font_size(text_percent),
        font = font.cache_borrow(&state^.font_cache, .Regular),
        resolver = font.cache_terminal_resolver(&state^.font_cache),
        edit_target = {buffer, &note^.text_length},
        multiline = true,
    }
}

// Restrict one scrolled content region to the viewport that owns its surface.
presentation_intersection :: proc(
    content, viewport: geometry.Rectangle) -> geometry.Rectangle {
    x := max(content.x, viewport.x)
    y := max(content.y, viewport.y)
    right := min(content.x+content.width, viewport.x+viewport.width)
    bottom := min(content.y+content.height, viewport.y+viewport.height)
    return {x, y, max(0, right-x), max(0, bottom-y)}
}

//   Resolve copy and selection interaction against prepared presentation layout.
prepare_presentation_content_interaction :: proc(
    state: ^core.Euclid_General_State,
    request: Presentation_Content_Interaction) -> ui_dynview.Dynview_Selection_View {
    ui_runtime := &state^.ui_runtime
    content := ui_dynview.dynview_selection_content(
        &state^.dynview, request.view_text)
    selection := &ui_runtime^.presentation.selection
    ui_dynview.dynview_selection_reconcile(selection, content)
    presentation_update_selection_mouse(state, request, content)
    if request.keyboard_enabled {
        ui_dynview.dynview_selection_update_keyboard(
            &state^.dynview, selection, content,
            request.view_text, request.mouse_input)
    }
    return request.selection_view
}

// Route pointer selection through the single composed document viewport.
presentation_update_selection_mouse :: proc(
    state: ^core.Euclid_General_State,
    request: Presentation_Content_Interaction,
    content: ui_dynview.Dynview_Selection_Content) {
    runtime := &state^.ui_runtime
    owner := &runtime^.input.press_owner
    point := uiwidgets.input_frame_mouse_position(request.mouse_input)
    original_capture := owner^.kind == .Dynview_Selection && owner^.id == 1001
    original_hit := geometry.rectangle_contains(request.original_screen, point)
    if original_hit || original_capture {
        ui_dynview.dynview_selection_update_mouse({
            runtime = &state^.dynview,
            selection = &runtime^.presentation.selection,
            press_owner = owner,
            content = content,
            view = request.selection_view,
            frame = request.mouse_input,
            selection_id = 1001,
        })
    }
}

// Intersect document content with the stationary reading or authoring viewport.
presentation_interaction_views :: proc(
    layout: Presentation_Interaction_Layout) -> Presentation_Interaction_Views {
    text_panel := layout.text_panel
    note_layout := layout.note_layout
    scroll := layout.scroll
    row_height := theme.ui_scaled_metric(
        theme.TEXT_ROW_HEIGHT, layout.text_percent)
    wrap_advance := theme.ui_scaled_metric(
        theme.TEXT_WRAP_ADVANCE, layout.text_percent)
    padding := theme.ui_scaled_metric(theme.TEXT_PADDING, layout.text_percent)
    original_screen := presentation_intersection(
        note_layout.original_panel, geometry.Rectangle(text_panel))
    return {
        selection = {
            panel = {
                note_layout.original_panel.x,
                text_panel.y,
                note_layout.original_panel.width,
                scroll.view_rect.height,
            },
            scroll_y = scroll.scroll_y_out-
                (note_layout.original_panel.y-text_panel.y),
            text_padding = padding,
            row_height = row_height,
            wrap_advance = wrap_advance,
            fallback_text = layout.view_text,
        },
        original_screen = original_screen,
    }
}

// Prepare note-aware content and scroll bounds for one interactive frame.
presentation_prepare_interaction_layout :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame) -> Presentation_Interaction_Layout {
    text_panel := uiwidgets.text_content_panel(panel)
    view_text := julia.current_view_snapshot_text(state)
    text_percent := state^.ui_runtime.preferences.values.interface.text_size_percent
    original_height := presentation_original_content_height(state, text_panel, view_text)
    note := &state^.ui_runtime.library.collection_note
    editing := presentation_note_is_current(state) && note^.editing
    note_layout := presentation_note_edit_layout(
        text_panel, note^.split_ratio, text_percent) if editing else
        presentation_note_reading_layout(text_panel, original_height)
    if note_layout.editing {
        note_layout = presentation_note_splitter_update(state, text_panel, mouse_input)
    }
    content_height := note_layout.content_height
    scroll_panel := geometry.Rectangle(text_panel)
    if note_layout.editing {
        scroll_panel = note_layout.original_panel
        content_height = original_height
    }
    state^.ui_runtime.presentation.text_scroll_max =
        max(0, content_height-scroll_panel.height)
    scroll_step := dynlayout.presentation_scroll_step_or_fallback(
        &state^.dynview, theme.TEXT_ROW_HEIGHT)
    scroll := prepare_presentation_scroll(
        state, scroll_panel, content_height, scroll_step, mouse_input)
    return {
        text_panel = text_panel,
        view_text = view_text,
        note_layout = note_layout,
        scroll = scroll,
        text_percent = text_percent,
    }
}

//   Resolve post-layout presentation interaction before rendering.
prepare_presentation_interaction :: proc(
    state: ^core.Euclid_General_State,
    panel: geometry.Rectangle,
    mouse_input: input.Input_Frame,
    keyboard_enabled: bool) -> Presentation_Preparation {
    if state != nil {
        state^.ui_runtime.presentation.text_scroll_max = 0
    }
    if state == nil || state^.julia_interface == nil ||
       uiterminal.is_terminal_selected(state) {
        return {}
    }
    if !ui_presentation_is_visible(&state^.ui_runtime.presentation) {
        return {}
    }
    layout := presentation_prepare_interaction_layout(state, panel, mouse_input)
    text_panel := layout.text_panel
    view_text := layout.view_text
    note_layout := layout.note_layout
    scroll := layout.scroll
    views := presentation_interaction_views(layout)
    selection_view := prepare_presentation_content_interaction(state, {
        scroll = scroll,
        view_text = view_text,
        selection_view = views.selection,
        original_screen = views.original_screen,
        mouse_input = mouse_input,
        keyboard_enabled = keyboard_enabled,
    })
    register_presentation_semantics(state, text_panel, scroll)
    editor := presentation_prepare_note_mode(state, note_layout, mouse_input)
    return {
        active = true,
        text_panel = geometry.Rectangle(text_panel),
        view_text = view_text,
        scroll = scroll,
        selection_view = selection_view,
        note_layout = note_layout,
        note_input_params = editor.input_params,
        note_input = editor.input,
        note_done_params = editor.done_params,
        note_done = editor.done,
        note_order = editor.order,
    }

}

// Prepare active editing or retire stale pointer geometry when returning to reading.
presentation_prepare_note_mode :: proc(
    state: ^core.Euclid_General_State, layout: Presentation_Note_Layout,
    frame: input.Input_Frame) -> Presentation_Note_Editor_Preparation {
    if layout.editing {
        return presentation_prepare_note_editor(state, layout, frame)
    }
    note := &state^.ui_runtime.library.collection_note
    note^.editor_rect = {}
    note^.editor_clip_rect = {}
    note^.splitter_rect = {}
    note^.done_rect = {}
    note^.order_rect = {}
    note^.splitter_hovered = false
    return {}
}
