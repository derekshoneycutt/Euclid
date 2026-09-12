package ui

import "../../core"
import termemulator "../../terminal/emulator"
import "../font"
import "../input"
import terminalview "../terminal"

import rl "vendor:raylib"

// UI-facing actions produced by one terminal input frame.
Terminal_Frame_Update :: terminalview.Terminal_Frame_Update

// Frame-local Terminal layout and interaction prepared before rendering.
Terminal_Prepared_Frame :: struct {
    available: bool,
    bounds: rl.Rectangle,
    layout: terminalview.Terminal_Draw_Layout,
    scroll: Scroll_Container_Update_Result,
    content_frame: input.Input_Frame,
    hyperlink_hover: terminalview.Terminal_Link_Hit,
    geometry_change: terminalview.Terminal_Geometry_Change,
}

// Scroll result and routed Terminal content input prepared together.
Terminal_Scroll_Preparation :: struct {
    scroll: Scroll_Container_Update_Result,
    content_frame: input.Input_Frame,
}

// Inputs needed to route Terminal content after committing prepared scrolling.
Terminal_Content_Route :: struct {
    resolved: input.Input_Frame,
    bounds: rl.Rectangle,
    layout: terminalview.Terminal_Draw_Layout,
    child_pointer_capture: bool,
    over_track: bool,
}

// Return the fixed terminal content rectangle inside the former text panel.
terminal_content_panel :: proc(panel: rl.Rectangle) -> rl.Rectangle {
    return view_text_content_panel(panel)
}

// Poll one terminal frame using the same bounds later supplied to drawing.
terminal_update :: proc(
    term: ^core.Terminal_State, frame: input.Input_Frame,
    font_face: rl.Font, bounds: rl.Rectangle) -> Terminal_Frame_Update {
    resolved := terminalview.terminal_resolve_mouse_frame(term, frame, bounds)
    return terminalview.terminal_update(term, {
        frame = resolved,
        now = frame.sample_time_seconds,
        font = font_face,
        bounds = bounds,
        update_geometry = false,
    })
}

// Return the bounded output row count currently visible to the terminal UI.
terminal_line_count :: proc(term: ^core.Terminal_State) -> int {
    return terminalview.terminal_line_count(term)
}

// Return one terminal output row as selectable UTF-8 text.
terminal_line_text :: proc(term: ^core.Terminal_State, line: int) -> string {
    return terminalview.terminal_line_text(term, line)
}

// Return the fixed semantic colors used by Terminal presentation.
terminal_draw_theme :: proc() -> terminalview.Terminal_Draw_Theme {
    return {
        default_foreground = UI_TEXT_COLOR,
        cursor_foreground = terminalview.TERMINAL_CURSOR_TEXT_COLOR,
        selection_foreground = rl.WHITE,
        selection_background = rl.Color{82, 96, 112, 255},
    }
}

// Filter Terminal pointer fields for focused routing tests and isolated callers.
terminal_filter_content_pointer :: proc(
    frame: input.Input_Frame, bounds: rl.Rectangle,
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
        route.bounds, {
            local_capture = local_capture,
            child_capture = route.child_pointer_capture,
            wheel_consumed = scroll.wheel_consumed,
        })
}

// Resolve Terminal scrollbar and content wheel ownership for one frame.
terminal_prepare_scroll :: proc(
    state: ^core.Euclid_General_State,
    resolved: input.Input_Frame,
    layout: terminalview.Terminal_Draw_Layout,
    bounds: rl.Rectangle,
    child_pointer_capture: bool) -> Terminal_Scroll_Preparation {
    term := &state^.terminal
    initial_scroll := terminalview.terminal_initial_scroll_offset(
        term, layout.padded_bounds, layout.content_height)
    max_scroll := max(0.0, layout.content_height - layout.padded_bounds.height)
    preview := build_vertical_scrollbar(
        {layout.padded_bounds, layout.content_height, initial_scroll, max_scroll},
        SCROLLBAR_WIDTH, SCROLLBAR_THUMB_MIN_HEIGHT)
    mouse := input_frame_mouse_position(resolved)
    over_track := preview.has_scrollbar && rl.CheckCollisionPointRec(
        mouse, preview.track_rect)
    mode := termemulator.interpreter_input_mode(&term.output_interpreter)
    child_owns_mouse := mode.mouse_tracking != .None && mode.mouse_sgr_encoding
    scroll_frame := resolved
    scroll_frame.mouse_wheel_delta = terminal_scroll_wheel_delta(
        resolved, over_track, child_owns_mouse)
    scroll := scroll_container_update({
        id = 1002, rect = layout.padded_bounds, scroll_y_in = initial_scroll,
        content_height = layout.content_height, mouse_input = scroll_frame,
        interaction_space_rect = bounds,
        wheel_step = layout.line_height * WHEEL_SCROLL_MULTIPLIER,
        press_owner = &state^.ui_runtime.ui_press_owner,
        state_in = {state^.ui_runtime.terminal_scroll_dragging,
            state^.ui_runtime.terminal_scroll_drag_off},
    })
    route := Terminal_Content_Route{
        resolved, bounds, layout, child_pointer_capture, over_track}
    content_frame := terminal_commit_prepared_scroll(state, route, scroll)
    return {scroll, content_frame}
}

// Prepare Terminal geometry, scroll ownership, and routed content input.
terminal_prepare_frame :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    font_face: rl.Font, bounds: rl.Rectangle,
    child_pointer_capture: bool) -> Terminal_Prepared_Frame {
    term := &state^.terminal
    geometry_change := terminalview.terminal_update_geometry(term, font_face, bounds)
    resolver := font.cache_terminal_resolver(&state^.font_cache)
    layout := terminalview.terminal_draw_layout(
        term, resolver, bounds, terminal_draw_theme())
    layout.terminal_focused = state^.ui_runtime.interaction_frame.terminal_focused
    resolved := terminalview.terminal_resolve_mouse_frame(term, frame, bounds)
    prepared_scroll := terminal_prepare_scroll(
        state, resolved, layout, bounds, child_pointer_capture)
    hover := terminalview.terminal_hyperlink_hover_hit(
        term, prepared_scroll.content_frame, bounds)
    return {true, bounds, layout, prepared_scroll.scroll,
        prepared_scroll.content_frame, hover, geometry_change}
}

// Draw one terminal through Euclid's fixed text-panel scrolling container.
terminal_draw :: proc(
    state: ^core.Euclid_General_State, prepared: Terminal_Prepared_Frame) {
    term := &state^.terminal
    if !term.initialized || !prepared.available { return }
    resolver := font.cache_terminal_resolver(&state^.font_cache)
    layout := prepared.layout
    scroll := prepared.scroll
    origin := rl.Vector2{
        scroll.view_rect.x,
        scroll.view_rect.y - scroll.scroll_y_out,
    }
    scroll_container_draw_begin(scroll)
    terminalview.terminal_draw_content(
        term, resolver, term.raster_renderer, {
            layout = layout,
            origin = origin,
            bounds = prepared.bounds,
            frame = prepared.content_frame,
            hyperlink_hover = prepared.hyperlink_hover,
        })
    scroll_container_draw_end(scroll)
    terminalview.terminal_draw_overlays(term, resolver, layout)
}
