package uipresentation

import viewmodel "../model"
import uiterminal "../terminal"

UI_PRESENTATION_SCROLLBAR_ID :: 1001

// Compute presentation visibility from the resolved composition.
ui_composition_presentation_visible :: #force_inline proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    return runtime^.current_layout_mode == .Landscape ||
        runtime^.active_accordion_section == .View
}

// Report the display-owned presentation visibility published for this frame.
ui_presentation_is_visible :: #force_inline proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    return runtime != nil && runtime^.presentation_visible
}

// Return whether shared capture belongs to hidden Presentation or Terminal UI.
ui_presentation_owns_capture :: proc(
    owner: viewmodel.Ui_Press_Owner_State) -> bool {
    if owner.kind == .Dynview_Selection {
        return true
    }
    return owner.kind == .Scrollbar &&
        (owner.id == UI_PRESENTATION_SCROLLBAR_ID ||
         owner.id == uiterminal.UI_TERMINAL_SCROLLBAR_ID)
}

// Clear focus and pointer transactions when composition hides the presentation.
ui_hide_presentation_interaction :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) {
    if ui_presentation_owns_capture(runtime^.ui_press_owner) {
        runtime^.ui_press_owner = {}
    }
    runtime^.text_scroll_dragging = false
    runtime^.text_scroll_drag_off = 0
    runtime^.terminal_scroll_dragging = false
    runtime^.terminal_scroll_drag_off = 0
    runtime^.dynview_selection.dragging = false
    focus := runtime^.interaction.logical_focus.kind
    if focus == .Terminal || focus == .Presentation {
        runtime^.interaction.logical_focus = {}
    }
    frame := &runtime^.interaction_frame
    was_terminal_focused := frame^.terminal_focused ||
        runtime^.interaction.terminal_effectively_focused
    frame^.logical_focus = runtime^.interaction.logical_focus
    frame^.effective_focus = runtime^.interaction.logical_focus
    frame^.terminal_focused = false
    frame^.terminal_focus_changed = was_terminal_focused
    frame^.terminal = {}
    frame^.presentation = {}
    runtime^.interaction.terminal_effectively_focused = false
}

// Publish current composition visibility and reconcile hidden interaction once.
ui_publish_presentation_visibility :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State) -> bool {
    visible := ui_composition_presentation_visible(runtime)
    if runtime^.presentation_visible == visible {
        return false
    }
    runtime^.presentation_visible = visible
    if !visible {
        ui_hide_presentation_interaction(runtime)
    }
    return true
}
