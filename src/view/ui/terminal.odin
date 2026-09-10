package ui

import "../../core"
import "../font"
import "../input"
import terminalview "../terminal"

import rl "vendor:raylib"

// UI-facing actions produced by one terminal input frame.
Terminal_Frame_Update :: terminalview.Terminal_Frame_Update

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
        update_geometry = true,
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

// Draw one terminal through Euclid's fixed text-panel scrolling container.
terminal_scroll_begin :: proc(
    state: ^core.Euclid_General_State,
    layout: terminalview.Terminal_Draw_Layout,
    bounds: rl.Rectangle, frame: input.Input_Frame) -> Scroll_Container_Begin_Result {
    return scroll_container_begin(Scroll_Container_Begin_Params{
        id = 1002,
        rect = layout.padded_bounds,
        scroll_y_in = terminalview.terminal_initial_scroll_offset(
            &state^.terminal, layout.padded_bounds, layout.content_height),
        content_height_hint = layout.content_height,
        mouse_input = frame,
        interaction_space_rect = bounds,
        wheel_step = layout.line_height * WHEEL_SCROLL_MULTIPLIER,
        press_owner = &state^.ui_runtime.ui_press_owner,
    })
}

// Draw one terminal through Euclid's fixed text-panel scrolling container.
terminal_draw :: proc(
    state: ^core.Euclid_General_State, bounds: rl.Rectangle,
    frame: input.Input_Frame) {
    term := &state^.terminal
    if !term.initialized { return }
    resolver := font.cache_terminal_resolver(&state^.font_cache)
    theme := terminalview.Terminal_Draw_Theme{
        default_foreground = UI_TEXT_COLOR,
        cursor_foreground = terminalview.TERMINAL_CURSOR_TEXT_COLOR,
        selection_foreground = rl.WHITE,
        selection_background = rl.Color{82, 96, 112, 255},
    }
    layout := terminalview.terminal_draw_layout(term, resolver, bounds, theme)
    scroll_begin := terminal_scroll_begin(state, layout, bounds, frame)
    origin := rl.Vector2{
        scroll_begin.view_rect.x,
        scroll_begin.view_rect.y - scroll_begin.scroll_y_out,
    }
    resolved := terminalview.terminal_resolve_mouse_frame(term, frame, bounds)
    terminalview.terminal_draw_content(
        term, resolver, term.raster_renderer, {
            layout = layout, origin = origin, bounds = bounds, frame = resolved})
    scroll_end := scroll_container_end(Scroll_Container_End_Params{
        scroll_ref = scroll_begin.scroll_ref,
        content_height_final = layout.content_height,
        scroll_y_in = scroll_begin.scroll_y_out,
        mouse_input = frame,
        interaction_space_rect = bounds,
        press_owner = &state^.ui_runtime.ui_press_owner,
    })
    terminalview.terminal_commit_scroll(
        term, scroll_end.scroll_y_out, layout.content_height)
    terminalview.terminal_draw_overlays(term, layout)
}
