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

// Return a frame copy that cannot drive Terminal content pointer interaction.
terminal_frame_without_content_pointer :: proc(
    frame: input.Input_Frame, bounds: rl.Rectangle) -> input.Input_Frame {
    result := frame
    result.mouse_moved = false
    result.mouse_pressed = {}
    result.mouse_down = {}
    result.mouse_wheel_delta = 0
    result.mouse_position = {bounds.x - 1, bounds.y - 1}
    result.terminal_mouse_inside = false
    result.terminal_mouse_owned = false
    return result
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
    resolved: input.Input_Frame,
    bounds: rl.Rectangle,
    layout: terminalview.Terminal_Draw_Layout,
    scroll: Scroll_Container_Update_Result) -> input.Input_Frame {
    state^.ui_runtime.terminal_scroll_dragging = scroll.state_out.is_dragging_thumb
    state^.ui_runtime.terminal_scroll_drag_off = scroll.state_out.drag_offset_y
    terminalview.terminal_commit_scroll(
        &state^.terminal, scroll.scroll_y_out, layout.content_height)
    if scroll.pointer_reserved {
        return terminal_frame_without_content_pointer(resolved, bounds)
    }
    result := resolved
    if scroll.wheel_consumed { result.mouse_wheel_delta = 0 }
    return result
}

// Resolve Terminal scrollbar and content wheel ownership for one frame.
terminal_prepare_scroll :: proc(
    state: ^core.Euclid_General_State,
    resolved: input.Input_Frame,
    layout: terminalview.Terminal_Draw_Layout,
    bounds: rl.Rectangle) -> Terminal_Scroll_Preparation {
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
    content_frame := terminal_commit_prepared_scroll(
        state, resolved, bounds, layout, scroll)
    return {scroll, content_frame}
}

// Prepare Terminal geometry, scroll ownership, and routed content input.
terminal_prepare_frame :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    font_face: rl.Font, bounds: rl.Rectangle) -> Terminal_Prepared_Frame {
    term := &state^.terminal
    geometry_change := terminalview.terminal_update_geometry(term, font_face, bounds)
    resolver := font.cache_terminal_resolver(&state^.font_cache)
    layout := terminalview.terminal_draw_layout(
        term, resolver, bounds, terminal_draw_theme())
    layout.terminal_focused = state^.ui_runtime.interaction_frame.terminal_focused
    resolved := terminalview.terminal_resolve_mouse_frame(term, frame, bounds)
    prepared_scroll := terminal_prepare_scroll(state, resolved, layout, bounds)
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
