package viewmodel



// Return one target with its focus owner and optional stable interaction identity.
ui_interaction_target :: #force_inline proc(
    kind: Ui_Interaction_Target_Kind,
    focus: Ui_Focus_Kind = .None,
    id: int = 0) -> Ui_Interaction_Target {
    return {kind = kind, focus = {kind = focus, id = id}, id = id}
}

// Refresh narrow surface eligibility after static or layout-dependent routing.
ui_refresh_surface_interaction :: proc(frame: ^Ui_Interaction_Frame) {
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
    frame^.accordion = {
        keyboard = frame^.effective_focus.kind == .Accordion,
        pointer = frame^.pointer_target.focus.kind == .Accordion ||
            frame^.pointer_target.focus.kind == .Input_Box,
        wheel = frame^.wheel_target.focus.kind == .Accordion,
    }
}
