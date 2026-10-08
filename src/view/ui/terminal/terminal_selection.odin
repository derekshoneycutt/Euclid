package uiterminal

import core "../../../core"

//   Return whether the selected catalog node owns the Terminal surface.
is_terminal_selected :: #force_inline proc(state: ^core.Euclid_General_State) -> bool {
    return state != nil && state^.julia_interface != nil &&
        state^.julia_interface^.selected_animation != nil &&
        state^.julia_interface^.selected_animation^.node_kind == .Terminal
}
