package uiterminal

import geometry "../../../core/geometry"
import input "../../input"
import viewmodel "../model"

UI_TERMINAL_SCROLLBAR_ID :: 1002

// Capture and wheel facts needed to filter one resolved Terminal frame.
Ui_Terminal_Content_Route_Input :: struct {
    local_capture: bool,
    child_capture: bool,
    wheel_consumed: bool,
}

// Return whether Terminal is the active and valid keyboard focus target.
ui_terminal_effectively_focused :: #force_inline proc(
    logical_focus: viewmodel.Ui_Focus_Target,
    window_focused: bool,
    terminal_present, presentation_visible: bool) -> bool {
    return window_focused && terminal_present && presentation_visible &&
        logical_focus.kind == .Terminal
}

// Refine the static Terminal panel target with prepared scrollbar geometry.
ui_refine_terminal_scroll_route :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    over_track: bool,
    pointer_reserved: bool,
    wheel_present: bool) {
    frame := &runtime^.interaction_frame
    scrollbar := viewmodel.ui_interaction_target(
        .Scrollbar, .Terminal, UI_TERMINAL_SCROLLBAR_ID)
    if over_track {
        frame^.hover = scrollbar
    }
    capture := frame^.pointer_capture
    capture_allows_scrollbar := capture.kind == .None ||
        capture.kind == .Scrollbar && capture.focus.kind == .Terminal
    if pointer_reserved && capture_allows_scrollbar {
        frame^.pointer_target = scrollbar
    }
    if over_track && wheel_present && capture.kind == .None {
        frame^.wheel_target = scrollbar
    }
    viewmodel.ui_refresh_surface_interaction(frame)
}

// Return pointer fields required to finish admitted local or child transactions.
ui_terminal_captured_pointer_fields :: proc(
    local_capture: bool,
    child_capture: bool) -> input.Input_Pointer_Fields {
    fields: input.Input_Pointer_Fields
    if local_capture {
        fields += {.Screen_Position, .Release_Edges}
    }
    if child_capture {
        fields += {.Motion, .Release_Edges, .Levels, .Terminal_Position,
            .Terminal_Ownership}
    }
    return fields
}

// Route one resolved frame to Terminal content from the shared interaction result.
ui_route_terminal_content_frame :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    frame: input.Input_Frame,
    bounds: geometry.Rectangle,
    route: Ui_Terminal_Content_Route_Input) -> input.Input_Frame {
    if !runtime^.interaction_frame.terminal.pointer {
        fields := ui_terminal_captured_pointer_fields(
            route.local_capture, route.child_capture)
        return input.input_frame_filter_pointer(
            frame, fields, {bounds.x - 1, bounds.y - 1})
    }
    result := frame
    if route.wheel_consumed || !runtime^.interaction_frame.terminal.wheel {
        result.mouse_wheel_delta = 0
    }
    return result
}
