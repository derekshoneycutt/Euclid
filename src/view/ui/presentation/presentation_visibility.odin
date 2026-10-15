package uipresentation

import viewmodel "../model"
import uiterminal "../terminal"

UI_PRESENTATION_SCROLLBAR_ID :: 1001

// presentation_cancel_geometry_capture ends scroll and selection drags on invalidation.
presentation_cancel_geometry_capture :: proc(
    presentation: ^viewmodel.Ui_Presentation_Interaction_State) {
    presentation^.scroll_dragging = false
    presentation^.scroll_drag_off = 0
    presentation^.selection.dragging = false
}

// Report the display-owned presentation visibility published for this frame.
ui_presentation_is_visible :: #force_inline proc(
    presentation: ^viewmodel.Ui_Presentation_Interaction_State) -> bool {
    return presentation != nil && presentation^.visible
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
