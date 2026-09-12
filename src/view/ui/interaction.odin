package ui

import "../../core"
import "../input"

import rl "vendor:raylib"

UI_PRESENTATION_SCROLLBAR_ID :: 1001
UI_TERMINAL_SCROLLBAR_ID :: 1002
UI_TREE_SCROLLBAR_ID :: 1003

// Inputs needed to resolve one immutable device frame against current UI geometry.
Ui_Interaction_Route_Input :: struct {
    frame: Input_Frame,
    terminal_present: bool,
    capture: core.Ui_Press_Owner_State,
}

// Capture and wheel facts needed to filter one resolved Terminal frame.
Ui_Terminal_Content_Route_Input :: struct {
    local_capture: bool,
    child_capture: bool,
    wheel_consumed: bool,
}

// Return one target with its focus owner and optional stable interaction identity.
ui_interaction_target :: #force_inline proc(
    kind: core.Ui_Interaction_Target_Kind,
    focus: core.Ui_Focus_Kind = .None,
    id: int = 0) -> core.Ui_Interaction_Target {
    return {kind = kind, focus = {kind = focus}, id = id}
}

// Classify legacy singleton capture until widget call sites register with the router.
ui_capture_target :: proc(
    capture: core.Ui_Press_Owner_State) -> core.Ui_Interaction_Target {
    if !capture.active { return {} }
    switch capture.kind {
    case .Splitter:
        return ui_interaction_target(.Splitter, id = capture.id)
    case .Scrollbar:
        focus := core.Ui_Focus_Kind.Tree
        if capture.id == UI_PRESENTATION_SCROLLBAR_ID { focus = .Presentation }
        if capture.id == UI_TERMINAL_SCROLLBAR_ID { focus = .Terminal }
        return ui_interaction_target(.Scrollbar, focus, capture.id)
    case .Dynview_Selection:
        return ui_interaction_target(.Control, .Presentation, capture.id)
    case .None:
        return {}
    case .List_Item, .Icon_Button, .Text_Button, .Checkbox, .Slider:
        return ui_interaction_target(.Control, .Tree, capture.id)
    }
    return {}
}

// Resolve the topmost static target under the current pointer sample.
ui_hover_target :: proc(
    runtime: ^core.Euclid_Ui_Runtime_State,
    frame: Input_Frame,
    terminal_present: bool) -> core.Ui_Interaction_Target {
    mouse := input_frame_mouse_position(frame)
    if !splitters_locked_for_gif(runtime^.gif_capture_phase) {
        axis, hovered := splitter_hovered_axis(mouse,
            runtime^.vertical_split_x, runtime^.horizontal_split_y)
        if hovered {
            id := SPLITTER_VERTICAL_PRESS_ID
            if axis == .Horizontal { id = SPLITTER_HORIZONTAL_PRESS_ID }
            return ui_interaction_target(.Splitter, id = id)
        }
    }
    regions := runtime^.ui_regions
    if terminal_present && rl.CheckCollisionPointRec(mouse, regions.terminal_rect) {
        return ui_interaction_target(.Panel_Content, .Terminal)
    }
    if rl.CheckCollisionPointRec(mouse, regions.text_rect) {
        return ui_interaction_target(.Panel_Content, .Presentation)
    }
    if rl.CheckCollisionPointRec(mouse, regions.tree_rect) {
        return ui_interaction_target(.Panel_Content, .Tree)
    }
    if rl.CheckCollisionPointRec(mouse, regions.world_rect) {
        return ui_interaction_target(.World)
    }
    return {}
}

// Resolve persistent logical focus from presentation and routed press transitions.
ui_route_logical_focus :: proc(
    runtime: ^core.Euclid_Ui_Runtime_State,
    input: Ui_Interaction_Route_Input,
    pointer_target: core.Ui_Interaction_Target) -> core.Ui_Focus_Target {
    result := runtime^.interaction.logical_focus
    terminal_present := input.terminal_present
    if terminal_present && !runtime^.interaction.terminal_was_present {
        result = {kind = .Terminal}
    } else if !terminal_present && result.kind == .Terminal {
        result = {}
    }
    if input_frame_left_pressed(input.frame) && !input.capture.active {
        result = pointer_target.focus
    }
    return result
}

// Return whether Terminal is the active and valid keyboard focus target.
ui_terminal_effectively_focused :: #force_inline proc(
    logical_focus: core.Ui_Focus_Target,
    window_focused: bool,
    terminal_present: bool) -> bool {
    return window_focused && terminal_present &&
        logical_focus.kind == .Terminal
}

// Reconcile persistent logical focus and this frame's effective Terminal focus.
ui_route_interaction_frame :: proc(
    runtime: ^core.Euclid_Ui_Runtime_State,
    input: Ui_Interaction_Route_Input) -> core.Ui_Interaction_Frame {
    hover := ui_hover_target(runtime, input.frame, input.terminal_present)
    capture := ui_capture_target(input.capture)
    pointer_target := hover
    if capture.kind != .None { pointer_target = capture }
    logical_focus := ui_route_logical_focus(runtime, input, pointer_target)
    terminal_focused := ui_terminal_effectively_focused(
        logical_focus, input.frame.window_focused, input.terminal_present)
    wheel_target: core.Ui_Interaction_Target
    if input.frame.mouse_wheel_delta != 0 && capture.kind == .None {
        wheel_target = hover
    }
    result := core.Ui_Interaction_Frame{
        logical_focus = logical_focus,
        hover = hover,
        pointer_capture = capture,
        pointer_target = pointer_target,
        wheel_target = wheel_target,
        terminal_focus_changed = terminal_focused !=
            runtime^.interaction.terminal_effectively_focused,
        terminal_focused = terminal_focused,
    }
    if input.frame.window_focused {
        result.effective_focus = logical_focus
    }
    ui_refresh_surface_interaction(&result)
    runtime^.interaction.logical_focus = logical_focus
    runtime^.interaction.terminal_was_present = input.terminal_present
    runtime^.interaction.terminal_effectively_focused = terminal_focused
    runtime^.interaction_frame = result
    return result
}

// Route focus through the full interaction result for isolated callers and tests.
ui_reconcile_focus :: proc(
    runtime: ^core.Euclid_Ui_Runtime_State,
    frame: Input_Frame,
    terminal_present: bool) -> core.Ui_Interaction_Frame {
    return ui_route_interaction_frame(runtime, {
        frame = frame,
        terminal_present = terminal_present,
        capture = runtime^.ui_press_owner,
    })
}

// Refresh narrow surface eligibility after static or layout-dependent routing.
ui_refresh_surface_interaction :: proc(frame: ^core.Ui_Interaction_Frame) {
    frame^.terminal = {
        keyboard = frame^.effective_focus.kind == .Terminal,
        pointer = frame^.pointer_target.focus.kind == .Terminal,
        wheel = frame^.wheel_target.focus.kind == .Terminal,
    }
    frame^.presentation = {
        keyboard = frame^.effective_focus.kind == .Presentation,
        pointer = frame^.pointer_target.focus.kind == .Presentation,
        wheel = frame^.wheel_target.focus.kind == .Presentation,
    }
    frame^.tree = {
        keyboard = frame^.effective_focus.kind == .Tree,
        pointer = frame^.pointer_target.focus.kind == .Tree,
        wheel = frame^.wheel_target.focus.kind == .Tree,
    }
}

// Refine the static Terminal panel target with prepared scrollbar geometry.
ui_refine_terminal_scroll_route :: proc(
    runtime: ^core.Euclid_Ui_Runtime_State,
    over_track: bool,
    pointer_reserved: bool,
    wheel_present: bool) {
    frame := &runtime^.interaction_frame
    scrollbar := ui_interaction_target(
        .Scrollbar, .Terminal, UI_TERMINAL_SCROLLBAR_ID)
    if over_track { frame^.hover = scrollbar }
    capture := frame^.pointer_capture
    capture_allows_scrollbar := capture.kind == .None ||
        capture.kind == .Scrollbar && capture.focus.kind == .Terminal
    if pointer_reserved && capture_allows_scrollbar {
        frame^.pointer_target = scrollbar
    }
    if over_track && wheel_present && capture.kind == .None {
        frame^.wheel_target = scrollbar
    }
    ui_refresh_surface_interaction(frame)
}

// Return pointer fields required to finish admitted local or child transactions.
ui_terminal_captured_pointer_fields :: proc(
    local_capture: bool,
    child_capture: bool) -> input.Input_Pointer_Fields {
    fields: input.Input_Pointer_Fields
    if local_capture { fields += {.Screen_Position, .Release_Edges} }
    if child_capture {
        fields += {.Motion, .Release_Edges, .Levels, .Terminal_Position,
            .Terminal_Ownership}
    }
    return fields
}

// Route one resolved frame to Terminal content from the shared interaction result.
ui_route_terminal_content_frame :: proc(
    runtime: ^core.Euclid_Ui_Runtime_State,
    frame: Input_Frame,
    bounds: rl.Rectangle,
    route: Ui_Terminal_Content_Route_Input) -> Input_Frame {
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