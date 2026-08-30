package bridge

import "../core"

import "core:testing"

//   Verify programmatic selection synchronizes flags, ancestry, and reveal intent.
@(test)
programmatic_selection_synchronizes_tree_state :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State)
    defer free(state)
    ji := &state^.julia_interface_slots[0]
    state^.julia_interface = ji
    nodes: [3]core.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_count = len(nodes)
    nodes[0].next_in_registry = &nodes[1]
    nodes[1].next_in_registry = &nodes[2]
    nodes[0].first_child = &nodes[1]
    nodes[1].parent = &nodes[0]
    nodes[1].first_child = &nodes[2]
    nodes[2].parent = &nodes[1]
    nodes[0].is_selected = true

    testing.expect(t, select_animation_programmatically(state, &nodes[2]))
    testing.expect_value(t, ji.selected_animation, &nodes[2])
    testing.expect(t, !nodes[0].is_selected && !nodes[1].is_selected)
    testing.expect(t, nodes[2].is_selected)
    testing.expect(t, nodes[0].is_expanded && nodes[1].is_expanded)
    testing.expect(t, state^.ui_runtime.tree_reveal_pending)
    testing.expect_value(t,
        state^.ui_runtime.tree_reveal_stable_id, nodes[2].stable_id)
}

//   Verify a target outside the registry cannot disturb current selection.
@(test)
programmatic_selection_rejects_unregistered_target :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State)
    defer free(state)
    ji := &state^.julia_interface_slots[0]
    state^.julia_interface = ji
    selected, outsider: core.Euclid_Julia_Animation_Interface
    ji.animation_head = &selected
    ji.animation_count = 1
    ji.selected_animation = &selected
    selected.is_selected = true

    testing.expect(t, !select_animation_programmatically(state, &outsider))
    testing.expect_value(t, ji.selected_animation, &selected)
    testing.expect(t, selected.is_selected)
    testing.expect(t, !state^.ui_runtime.tree_reveal_pending)
}