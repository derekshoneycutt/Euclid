package ui

import viewterminalmodel "../terminal/model"
import viewmodel "../model"

import "../../core"
import geometry "../../core/geometry"
import termemulator "../../terminal/emulator"
import termhist "../../terminal/history"
import "../font"
import "../input"
import "../native"
import terminalview "../terminal"

// UI-facing actions produced by one terminal input frame.
Terminal_Frame_Update :: terminalview.Terminal_Frame_Update

// Frame-local Terminal layout and interaction prepared before rendering.
Terminal_Prepared_Frame :: struct {
    available: bool,
    bounds: geometry.Rectangle,
    layout: terminalview.Terminal_Draw_Layout,
    scroll: Scroll_Container_Update_Result,
    content_frame: input.Input_Frame,
    hyperlink_hover: terminalview.Terminal_Link_Hit,
    geometry_change: terminalview.Terminal_Geometry_Change,
    editable_descriptor: viewmodel.Ui_Editable_Text_Descriptor,
    editable_geometry: viewmodel.Ui_Editable_Text_Geometry,
}

// Scroll result and routed Terminal content input prepared together.
Terminal_Scroll_Preparation :: struct {
    scroll: Scroll_Container_Update_Result,
    content_frame: input.Input_Frame,
}

// Inputs needed to route Terminal content after committing prepared scrolling.
Terminal_Content_Route :: struct {
    resolved: input.Input_Frame,
    bounds: geometry.Rectangle,
    layout: terminalview.Terminal_Draw_Layout,
    child_pointer_capture: bool,
    over_track: bool,
}

// terminal_semantic_id identifies one replaceable Terminal animation session.
terminal_semantic_id :: #force_inline proc(
    state: ^core.Euclid_General_State) -> viewmodel.Ui_Node_Id {
    if state == nil {
        return {}
    }
    return {domain = .Terminal, local_id = 0,
        generation = state^.terminal.animation_generation}
}

// terminal_editable_cursor_row resolves the cursor's physical row and row start.
terminal_editable_cursor_row :: proc(text: string, cursor: int) -> (int, int) {
    row := 0
    line_start := 0
    for byte, index in text[:cursor] {
        if byte == '\n' {
            row += 1
            line_start = index + 1
        }
    }
    return row, line_start
}

// Build caret and selection geometry for committed Terminal text.
terminal_editable_text_geometry :: proc(
    state: ^core.Euclid_General_State,
    layout: terminalview.Terminal_Draw_Layout,
    scroll: Scroll_Container_Update_Result, text: string, cursor: int) ->
        viewmodel.Ui_Editable_Text_Geometry {
    term := &state^.terminal
    row, line_start := terminal_editable_cursor_row(text, cursor)
    prefix := terminalview.TERMINAL_CONTINUATION_PROMPT
    if row == 0 {
        prefix = terminalview.terminal_primary_prompt_prefix(term)
    }
    column := input_box_byte_column(text[line_start:cursor], cursor - line_start)
    prefix_columns := input_box_byte_column(prefix, len(prefix))
    column_width := terminalview.terminal_column_width(layout.regular)
    origin_y := scroll.view_rect.y - scroll.scroll_y_out
    caret := viewmodel.Rectangle{
        layout.padded_bounds.x + f32(prefix_columns + column) * column_width,
        origin_y + f32(layout.line_count + row) * layout.line_height,
        max(f32(1), column_width), layout.line_height,
    }
    control := scroll.control_geometry
    return {
        control = control, caret = caret,
        selection = {caret.x, caret.y, 0, caret.height},
        cursor_column = input_box_byte_column(text, cursor),
        anchor_column = input_box_byte_column(text, cursor),
    }
}

// terminal_editable_text_adapter exposes committed prompt input without preview text.
terminal_editable_text_adapter :: proc(
    state: ^core.Euclid_General_State,
    layout: terminalview.Terminal_Draw_Layout,
    scroll: Scroll_Container_Update_Result) ->
        (viewmodel.Ui_Editable_Text_Descriptor, viewmodel.Ui_Editable_Text_Geometry) {
    term := &state^.terminal
    if term.history == nil {
        return {}, {}
    }
    text := termhist.termhist_current_text(term.history)
    cursor := input_box_clamp_boundary(text, termhist.termhist_cursor(term.history))
    geometry := terminal_editable_text_geometry(state, layout, scroll, text, cursor)
    descriptor := viewmodel.Ui_Editable_Text_Descriptor{
        id = terminal_semantic_id(state), region = .Presentation,
        label = "Terminal input", text = text, mode = .Editable,
        cursor_byte = cursor, anchor_byte = cursor,
        content_revision = termhist.termhist_content_revision(term.history),
    }
    return descriptor, geometry
}

// register_terminal_semantics publishes one application-level Terminal surface.
register_terminal_semantics :: proc(
    state: ^core.Euclid_General_State,
    bounds: geometry.Rectangle,
    scroll: Scroll_Container_Update_Result) {
    id := terminal_semantic_id(state)
    _ = semantic_register_control(state^.ui_runtime.semantic_focus, {
        id = id, role = .Terminal,
        states = {.Visible, .Enabled, .Focusable, .Tab_Stop},
        actions = {.Focus, .Scroll}, region = .Presentation, traversal_order = 0,
        bounds = viewmodel.Rectangle(bounds),
        clip_bounds = viewmodel.Rectangle(bounds),
        numeric_range = {f64(scroll.minimum), f64(scroll.maximum),
            f64(scroll.scroll_y_out), f64(scroll.step), scroll.orientation, true},
        label = "Terminal",
    })
    semantic := state^.ui_runtime.semantic_focus
    needs_initial_focus := !state^.ui_runtime.terminal_semantic_focus_initialized ||
        state^.ui_runtime.terminal_semantic_focus_generation !=
            state^.terminal.animation_generation
    if needs_initial_focus ||
        state^.ui_runtime.interaction.logical_focus.kind == .Terminal &&
        semantic^.logical_focus.domain != .Terminal {
        if semantic_request_pointer_focus(semantic, id) {
            state^.ui_runtime.terminal_semantic_focus_initialized = true
            state^.ui_runtime.terminal_semantic_focus_generation =
                state^.terminal.animation_generation
        }
    }
}

// Return the fixed terminal content rectangle inside the former text panel.
terminal_content_panel :: proc(panel: geometry.Rectangle) -> geometry.Rectangle {
    return view_text_content_panel(panel)
}

// Update Terminal from one routed frame using the bounds later supplied to drawing.
terminal_update :: proc(
    term: ^viewterminalmodel.Terminal_State, frame: input.Input_Frame,
    font_face: font.Font_Face, bounds: geometry.Rectangle) -> Terminal_Frame_Update {
    resolved := terminalview.terminal_resolve_mouse_frame(
        term, frame, bounds)
    return terminalview.terminal_update(term, {
        frame = resolved,
        now = frame.sample_time_seconds,
        font = font_face,
        bounds = bounds,
        update_geometry = false,
    })
}

// Return the bounded output row count currently visible to the terminal UI.
terminal_line_count :: proc(term: ^viewterminalmodel.Terminal_State) -> int {
    return terminalview.terminal_line_count(term)
}

// Return one terminal output row as selectable UTF-8 text.
terminal_line_text :: proc(term: ^viewterminalmodel.Terminal_State, line: int) -> string {
    return terminalview.terminal_line_text(term, line)
}

// Return the fixed semantic colors used by Terminal presentation.
terminal_draw_theme :: proc() -> terminalview.Terminal_Draw_Theme {
    return {
        default_foreground = terminalview.Color(UI_TEXT_COLOR),
        cursor_foreground = terminalview.Color(terminalview.TERMINAL_CURSOR_TEXT_COLOR),
        selection_foreground = terminalview.Color{255, 255, 255, 255},
        selection_background = terminalview.Color{82, 96, 112, 255},
    }
}

// Filter Terminal pointer fields for focused routing tests and isolated callers.
terminal_filter_content_pointer :: proc(
    frame: input.Input_Frame, bounds: geometry.Rectangle,
    local_capture: bool, child_capture: bool) -> input.Input_Frame {
    fields := ui_terminal_captured_pointer_fields(local_capture, child_capture)
    return input.input_frame_filter_pointer(
        frame, fields, {bounds.x - 1, bounds.y - 1})
}

// Resolve wheel input admitted to the local scroll container.
terminal_scroll_wheel_delta :: #force_inline proc(
    frame: input.Input_Frame,
    over_track: bool,
    child_owns_mouse: bool) -> f32 {
    if over_track || !child_owns_mouse || .Shift in frame.mouse_modifiers {
        return frame.mouse_wheel_delta
    }
    return 0
}

// Persist prepared scrolling and remove locally owned input from the content frame.
terminal_commit_prepared_scroll :: proc(
    state: ^core.Euclid_General_State,
    route: Terminal_Content_Route,
    scroll: Scroll_Container_Update_Result) -> input.Input_Frame {
    state^.ui_runtime.terminal_scroll_dragging = scroll.state_out.is_dragging_thumb
    state^.ui_runtime.terminal_scroll_drag_off = scroll.state_out.drag_offset_y
    terminalview.terminal_commit_scroll(
        &state^.terminal, scroll.scroll_y_out, route.layout.content_height)
    ui_refine_terminal_scroll_route(&state^.ui_runtime, route.over_track,
        scroll.pointer_reserved, route.resolved.mouse_wheel_delta != 0)
    local_capture := state^.terminal.view_selection_dragging ||
        state^.terminal.hyperlink_pressed != 0
    return ui_route_terminal_content_frame(&state^.ui_runtime, route.resolved,
        geometry.Rectangle(route.bounds), {
            local_capture = local_capture,
            child_capture = route.child_pointer_capture,
            wheel_consumed = scroll.wheel_consumed,
        })
}

// Resolve Terminal scrollbar and content wheel ownership for one frame.
terminal_scroll_input :: proc(
    term: ^viewterminalmodel.Terminal_State,
    resolved: input.Input_Frame, over_track: bool) -> input.Input_Frame {
    mode := termemulator.interpreter_input_mode(&term.output_interpreter)
    child_owns_mouse := mode.mouse_tracking != .None && mode.mouse_sgr_encoding
    result := resolved
    result.mouse_wheel_delta = terminal_scroll_wheel_delta(
        resolved, over_track, child_owns_mouse)
    return result
}

// Resolve Terminal scrollbar and content wheel ownership for one frame.
terminal_prepare_scroll :: proc(
    state: ^core.Euclid_General_State,
    resolved: input.Input_Frame,
    layout: terminalview.Terminal_Draw_Layout,
    bounds: geometry.Rectangle,
    child_pointer_capture: bool) -> Terminal_Scroll_Preparation {
    term := &state^.terminal
    initial_scroll := terminalview.terminal_initial_scroll_offset(
        term, layout.padded_bounds, layout.content_height)
    max_scroll := max(0.0, layout.content_height - layout.padded_bounds.height)
    preview := build_vertical_scrollbar(
        {geometry.Rectangle(layout.padded_bounds), layout.content_height,
            initial_scroll, max_scroll},
        SCROLLBAR_WIDTH, SCROLLBAR_THUMB_MIN_HEIGHT)
    mouse := input_frame_mouse_position(resolved)
    over_track := preview.has_scrollbar && geometry.rectangle_contains(
        preview.track_rect, mouse)
    scroll_frame := terminal_scroll_input(term, resolved, over_track)
    scroll := scroll_container_update({
        id = 1002, rect = geometry.Rectangle(layout.padded_bounds),
        scroll_y_in = initial_scroll,
        content_height = layout.content_height, mouse_input = scroll_frame,
        interaction_space_rect = bounds,
        wheel_step = layout.line_height * WHEEL_SCROLL_MULTIPLIER,
        press_owner = &state^.ui_runtime.ui_press_owner,
        state_in = {state^.ui_runtime.terminal_scroll_dragging,
            state^.ui_runtime.terminal_scroll_drag_off},
        semantic_focus = state^.ui_runtime.semantic_focus,
        semantic_id = terminal_semantic_id(state),
    })
    route := Terminal_Content_Route{
        resolved, bounds, layout,
        child_pointer_capture, over_track}
    content_frame := terminal_commit_prepared_scroll(state, route, scroll)
    return {scroll, content_frame}
}

// Prepare Terminal geometry, scroll ownership, and routed content input.
terminal_prepare_frame :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    font_face: font.Font_Face, bounds: geometry.Rectangle,
    child_pointer_capture: bool) -> Terminal_Prepared_Frame {
    term := &state^.terminal
    geometry_change := terminalview.terminal_update_geometry(
        term, font_face, geometry.Rectangle(bounds))
    resolver := font.cache_terminal_resolver(&state^.font_cache)
    layout := terminalview.terminal_draw_layout(
        term, resolver, bounds, terminal_draw_theme())
    layout.terminal_focused = state^.ui_runtime.interaction_frame.terminal_focused
    resolved := terminalview.terminal_resolve_mouse_frame(
        term, frame, bounds)
    prepared_scroll := terminal_prepare_scroll(
        state, resolved, layout, bounds, child_pointer_capture)
    hover := terminalview.terminal_hyperlink_hover_hit(
        term, prepared_scroll.content_frame, geometry.Rectangle(bounds))
    descriptor, text_geometry := terminal_editable_text_adapter(
        state, layout, prepared_scroll.scroll)
    return {true, bounds, layout, prepared_scroll.scroll,
        prepared_scroll.content_frame, hover, geometry_change,
        descriptor, text_geometry}
}

// terminal_draw_encoded emits one prepared Terminal surface into the SDL encoder.
terminal_draw_encoded :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Terminal_Prepared_Frame) {
    term := &state^.terminal
    if encoder == nil || !term.initialized || !prepared.available {
        return
    }
    resolver := font.cache_terminal_resolver(&state^.font_cache)
    layout := prepared.layout
    layout.encoder = encoder
    scroll := prepared.scroll
    origin := geometry.Vector2{
        scroll.view_rect.x,
        scroll.view_rect.y - scroll.scroll_y_out,
    }
    _ = native.draw_encoder_push_scissor(
        encoder, geometry.Rectangle(scroll.view_rect))
    terminalview.terminal_draw_content(
        term, resolver, term.raster_renderer, {
            encoder = encoder,
            layout = layout,
            origin = origin,
            bounds = prepared.bounds,
            frame = prepared.content_frame,
            hyperlink_hover = prepared.hyperlink_hover,
        })
    _ = native.draw_encoder_pop_scissor(encoder)
    terminalview.terminal_draw_overlays(term, resolver, layout)
    draw_encoded_scrollbar(encoder, scroll.scrollbar)
}
