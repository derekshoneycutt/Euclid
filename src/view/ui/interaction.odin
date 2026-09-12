package ui

import "../../core"

import rl "vendor:raylib"

// Return the logical focus target selected by a primary press.
ui_pressed_focus_target :: proc(
    runtime: ^core.Euclid_Ui_Runtime_State,
    frame: Input_Frame,
    terminal_present: bool) -> core.Ui_Focus_Target {
    if runtime^.ui_press_owner.active &&
        runtime^.ui_press_owner.kind == .Splitter {
        return {}
    }
    mouse := input_frame_mouse_position(frame)
    if terminal_present && rl.CheckCollisionPointRec(
        mouse, runtime^.ui_regions.terminal_rect) {
        return {kind = .Terminal}
    }
    if rl.CheckCollisionPointRec(mouse, runtime^.ui_regions.text_rect) {
        return {kind = .Presentation}
    }
    if rl.CheckCollisionPointRec(mouse, runtime^.ui_regions.tree_rect) {
        return {kind = .Tree}
    }
    return {}
}

// Resolve the persistent logical target from presentation and press transitions.
ui_reconcile_logical_focus :: proc(
    runtime: ^core.Euclid_Ui_Runtime_State,
    frame: Input_Frame,
    terminal_present: bool) -> core.Ui_Focus_Target {
    result := runtime^.interaction.logical_focus
    if terminal_present && !runtime^.interaction.terminal_was_present {
        result = {kind = .Terminal}
    } else if !terminal_present && result.kind == .Terminal {
        result = {}
    }
    if input_frame_left_pressed(frame) {
        result = ui_pressed_focus_target(runtime, frame, terminal_present)
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
ui_reconcile_focus :: proc(
    runtime: ^core.Euclid_Ui_Runtime_State,
    frame: Input_Frame,
    terminal_present: bool) -> core.Ui_Interaction_Frame {
    logical_focus := ui_reconcile_logical_focus(
        runtime, frame, terminal_present)
    terminal_focused := ui_terminal_effectively_focused(
        logical_focus, frame.window_focused, terminal_present)
    result := core.Ui_Interaction_Frame{
        logical_focus = logical_focus,
        terminal_focus_changed = terminal_focused !=
            runtime^.interaction.terminal_effectively_focused,
        terminal_focused = terminal_focused,
    }
    if frame.window_focused {
        result.effective_focus = logical_focus
    }
    runtime^.interaction.logical_focus = logical_focus
    runtime^.interaction.terminal_was_present = terminal_present
    runtime^.interaction.terminal_effectively_focused = terminal_focused
    runtime^.interaction_frame = result
    return result
}