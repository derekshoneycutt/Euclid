#+test
package view

import bridgemodel "../bridge/model"
import collections "../collections"
import core "../core"
import testing "core:testing"
import viewscenario "scenario"
import viewmodel "ui/model"

// Verify scenario order assertions follow authoritative sibling order after a swap.
@(test)
scenario_favorites_order_ignores_backing_storage_order :: proc(t: ^testing.T) {
    state := new(core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    nodes: [2]bridgemodel.Euclid_Julia_Animation_Interface
    nodes[0].name = "Point"
    nodes[1].name = "Line"
    nodes[0].stable_id[0] = 1
    nodes[1].stable_id[0] = 2
    nodes[0].next_in_registry = &nodes[1]
    ji := bridgemodel.Euclid_Julia_Interface{
        animation_head = &nodes[0],
        animation_count = 2,
    }
    state^.julia_interface = &ji
    set := &state^.preferences_runtime.collections_state
    collections.initialize(set)
    testing.expect_value(t, collections.favorites_add(
        set, nodes[0].stable_id, nodes[0].stable_id), collections.Policy_Error.None)
    testing.expect_value(t, collections.favorites_add(
        set, nodes[1].stable_id, nodes[1].stable_id), collections.Policy_Error.None)
    set^.entries[0].sibling_order = 2
    runtime := viewscenario.Scenario_Runtime{state = state}
    testing.expect(t, viewscenario.scenario_favorites_order(&runtime, "Line:Point"))
    testing.expect(t, !viewscenario.scenario_favorites_order(&runtime, "Point:Line"))
}

// Build an assertion fixture whose registry is borrowed until the caller frees the state.
scenario_favorites_assertion_fixture :: proc(
    ji: ^bridgemodel.Euclid_Julia_Interface) -> ^core.Euclid_General_State {
    state := new(core.Euclid_General_State, context.allocator)
    state^.julia_interface = ji
    set := &state^.preferences_runtime.collections_state
    collections.initialize(set)
    id := ji^.animation_head^.stable_id
    assert(collections.favorites_add(set, id, id) == .None)
    projection := &state^.ui_runtime.library.tree.projection
    assert(viewmodel.ui_tree_projection_init(projection))
    assert(viewmodel.ui_tree_projection_add_node(projection, {
        key = id,
        target_animation_id = id,
        kind = .Placement,
        parent = viewmodel.UI_TREE_NO_ITEM,
        first_child = viewmodel.UI_TREE_NO_ITEM,
        last_child = viewmodel.UI_TREE_NO_ITEM,
        next_sibling = viewmodel.UI_TREE_NO_ITEM,
        selectable = true,
    }, "Point") == 0)
    projection^.valid = true
    return state
}

// Release the isolated projection and Favorites fixture before freeing its root.
scenario_favorites_assertion_destroy :: proc(
    state: ^core.Euclid_General_State) {
    viewmodel.ui_tree_projection_destroy(
        &state^.ui_runtime.library.tree.projection)
    collections.destroy(&state^.preferences_runtime.collections_state)
    free(state, context.allocator)
}

// Reject missing baselines and distinguish stable placements from replacements.
@(test)
scenario_favorites_identity_assertions :: proc(t: ^testing.T) {
    node := bridgemodel.Euclid_Julia_Animation_Interface{name = "Point"}
    node.stable_id[0] = 1
    ji := bridgemodel.Euclid_Julia_Interface{animation_head = &node, animation_count = 1}
    state := scenario_favorites_assertion_fixture(&ji)
    defer scenario_favorites_assertion_destroy(state)
    runtime := viewscenario.Scenario_Runtime{state = state}
    testing.expect(t,
        !viewscenario.scenario_assert_favorites(
            &runtime, "same_placement:favorite:Point"))
    testing.expect(t, !viewscenario.scenario_assert_favorites(
        &runtime, "replaced:favorite:Point"))
    testing.expect(t, viewscenario.scenario_assert_favorites(
        &runtime, "remember:favorite:Point"))
    testing.expect(t, viewscenario.scenario_assert_favorites(
        &runtime, "same_placement:favorite:Point"))
    runtime.favorites_memory.placement[0] = 2
    testing.expect(t, viewscenario.scenario_assert_favorites(
        &runtime, "replaced:favorite:Point"))
    testing.expect(t, !viewscenario.scenario_assert_favorites(
        &runtime, "same_placement:favorite:Point"))
}

// Treat a closing drawer tail as closed rather than exposing inactive controls.
@(test)
scenario_favorites_drawer_assertions :: proc(t: ^testing.T) {
    node := bridgemodel.Euclid_Julia_Animation_Interface{name = "Point"}
    node.stable_id[0] = 1
    ji := bridgemodel.Euclid_Julia_Interface{animation_head = &node, animation_count = 1}
    state := scenario_favorites_assertion_fixture(&ji)
    defer scenario_favorites_assertion_destroy(state)
    runtime := viewscenario.Scenario_Runtime{state = state}
    state^.ui_runtime.library.actions.drawer = {entry_id = node.stable_id, open = true}
    testing.expect(t, viewscenario.scenario_assert_favorites(
        &runtime, "actions_open:favorite:Point"))
    testing.expect(t, !viewscenario.scenario_assert_favorites(
        &runtime, "actions_closed:favorite:Point"))
    state^.ui_runtime.library.actions.drawer.open = false
    state^.ui_runtime.library.actions.drawer.height = 16
    testing.expect(t, viewscenario.scenario_assert_favorites(
        &runtime, "actions_closed:favorite:Point"))
    testing.expect(t, !viewscenario.scenario_assert_favorites(
        &runtime, "actions_open:favorite:Point"))
}
