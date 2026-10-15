#+test
package ui

import bridgemodel "../../bridge/model"
import collectionmodel "../../collections"
import testing "core:testing"
import viewmodel "model"
import uilibrary "library"
import uuid "core:encoding/uuid"
import uisemantics "semantics"
import contentdata "../../core/content"

// tree_favorites_fixture builds a terminal-delimited catalogue and Favorites snapshot.
tree_favorites_fixture :: proc(
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    nodes: ^[3]bridgemodel.Euclid_Julia_Animation_Interface,
    collections: ^collectionmodel.Set) -> uilibrary.Tree_List_Params {
    ji^.animation_head = &nodes[0]
    ji^.animation_count = len(nodes^)
    ji^.content_generation = 1
    ji^.selected_animation = &nodes[0]
    for index in 0..<len(nodes^) {
        nodes[index].stable_id[0] = byte(index + 1)
        nodes[index].name = "Animation"
        nodes[index].node_kind = .Animation
        if index + 1 < len(nodes^) {
            nodes[index].next_in_registry = &nodes[index + 1]
        }

    }
    nodes[1].node_kind = .Terminal
    nodes[1].name = "Terminal"
    collectionmodel.initialize(collections)
    entry_id := uuid.Identifier{}
    entry_id[0] = 91
    assert(collectionmodel.favorites_add(
        collections, entry_id, nodes[2].stable_id) == .None)
    return {
        ji = ji, ui_runtime = runtime, collections = collections,
        collections_revision = 1, scroll_y = &runtime^.tree_scroll_y,
        list_panel = {0, 0, 240, 240},
        visibility = {search = &runtime^.library_search},
    }
}

// tree_favorites_expect_semantic_order checks member count and current linked order.
tree_favorites_expect_semantic_order :: proc(
    t: ^testing.T, params: uilibrary.Tree_List_Params, expected: [3]u8) {
    snapshot := uisemantics.semantic_snapshot(params.ui_runtime^.semantic_focus)
    parent := viewmodel.Ui_Node_Id{domain = .Animation_Tree,
        stable_id = collectionmodel.FAVORITES_COLLECTION_ID}
    count := 0
    for node in snapshot^.nodes[:snapshot^.node_count] {
        if node.role != .Tree_Item || node.parent != parent {
            continue
        }
        testing.expect_value(t, node.position_in_set, u16(count + 1))
        testing.expect_value(t, node.set_size, u16(3))
        testing.expect_value(t, node.id.stable_id[0], expected[count])
        count += 1
    }
    testing.expect_value(t, count, 3)
}

// Verify localization, disclosure relations, and published positions follow a native move.
@(test)
tree_favorites_actions_publish_owned_localized_controls_and_order :: proc(
    t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.selected_tree_item_id
    toggle := uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_TOGGLE)
    snapshot := uisemantics.semantic_snapshot(semantic)
    node := snapshot^.nodes[uisemantics.semantic_node_index(snapshot, toggle)]
    testing.expect_value(t, uisemantics.semantic_node_text(
        snapshot, node.label_offset, node.label_length), "Actions for Animation")
    testing.expect_value(t, node.parent.stable_id, selected)
    testing.expect_value(t, node.controls.local_id, uilibrary.TREE_ACTION_DRAWER)
    testing.expect(t, .Expanded not_in node.states)
    testing.expect(t,
        uisemantics.semantic_apply_external_action(semantic, toggle, .Expand))
    _ = tree_actions_test_semantic_frame(t, &params)
    tree_favorites_expect_semantic_order(t, params, {91, 92, 90})
    down := uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_DOWN)
    testing.expect(t,
        uisemantics.semantic_apply_external_action(semantic, down, .Activate))
    _ = tree_actions_test_semantic_frame(t, &params)
    tree_favorites_expect_semantic_order(t, params, {92, 91, 90})
    testing.expect(t,
        uisemantics.semantic_apply_external_action(semantic, toggle, .Collapse))
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t,
        !uisemantics.semantic_apply_external_action(semantic, down, .Activate))
}

// Verify admitted requests cannot act after closing, deselection, clipping, or reload.
@(test)
tree_favorites_actions_reject_stale_queued_activations :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.selected_tree_item_id
    toggle := uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_TOGGLE)
    testing.expect(t,
        uisemantics.semantic_apply_external_action(semantic, toggle, .Activate))
    _ = tree_actions_test_semantic_frame(t, &params)
    down := uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_DOWN)
    testing.expect(t,
        uisemantics.semantic_apply_external_action(semantic, down, .Activate))
    uilibrary.tree_actions_toggle(params, selected)
    revision := state^.preferences_runtime.collection_revision
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect_value(t, state^.preferences_runtime.collection_revision, revision)
    state^.ui_runtime.selected_tree_item_id = nodes[0].stable_id
    testing.expect(t, uilibrary.tree_actions_command_item(params, toggle) == nil)
    state^.ui_runtime.selected_tree_item_id = selected
    uilibrary.tree_actions_toggle(params, selected)
    _ = tree_actions_test_semantic_frame(t, &params)
    params.scroll_y^ = 10000
    testing.expect(t, !uilibrary.tree_actions_command_visible(params,
        uilibrary.tree_actions_command_item(params, down), uilibrary.TREE_ACTION_DOWN))
    ji.content_generation += 1
    testing.expect(t, uilibrary.tree_actions_command_item(params, down) == nil)
}

// Verify singleton endpoints remain visible and translated without entering traversal.
@(test)
tree_favorites_singleton_actions_localization_and_disabled_policy :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    selected := state^.ui_runtime.selected_tree_item_id
    testing.expect_value(t, collectionmodel.favorites_remove(params.collections,
        params.collections^.entries[0].id), collectionmodel.Policy_Error.None)
    testing.expect_value(t, collectionmodel.favorites_remove(params.collections,
        params.collections^.entries[1].id), collectionmodel.Policy_Error.None)
    state^.preferences_runtime.collection_revision += 1
    _ = tree_actions_test_semantic_frame(t, &params)
    uilibrary.tree_actions_toggle(params, selected)
    generation := state^.content_service.active_generation
    _, ordinal := contentdata.content_message_identity(.Library_Move_Up)
    reference := generation.data.translations[ordinal].template
    copy(generation.text_bytes[reference.offset:reference.offset + reference.length],
        "Earlier")
    state^.message_labels.shell_message_generation = 0
    _ = tree_actions_test_semantic_frame(t, &params)
    tree_favorites_expect_disabled_actions(t, params)
}

// tree_favorites_expect_disabled_actions checks singleton admission and translated labels.
tree_favorites_expect_disabled_actions :: proc(
    t: ^testing.T, params: uilibrary.Tree_List_Params) {
    semantic := params.ui_runtime^.semantic_focus
    snapshot := uisemantics.semantic_snapshot(semantic)
    selected := params.ui_runtime^.selected_tree_item_id
    for action in ([2]u64{uilibrary.TREE_ACTION_UP, uilibrary.TREE_ACTION_DOWN}) {
        id := uilibrary.tree_actions_semantic_id(params, selected, action)
        node := snapshot^.nodes[uisemantics.semantic_node_index(snapshot, id)]
        testing.expect(t, .Visible in node.states && .Enabled not_in node.states)
        testing.expect(t, .Tab_Stop not_in node.states && card(node.actions) == 0)
        testing.expect(t,
            !uisemantics.semantic_apply_external_action(semantic, id, .Activate))
        if action == uilibrary.TREE_ACTION_UP {
            testing.expect_value(t, uisemantics.semantic_node_text(
                snapshot, node.label_offset, node.label_length), "Earlier")
        }
    }
}

// Verify Collections follows Terminal and behaves as a collapsed searchable subtree.
@(test)
tree_favorites_projection_shares_order_expansion_and_search :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections: collectionmodel.Set
    params := tree_favorites_fixture(&runtime, &ji, &nodes, &collections)
    missing_entry, missing_animation: uuid.Identifier
    missing_entry[0], missing_animation[0] = 92, 99
    assert(collectionmodel.favorites_add(
        &collections, missing_entry, missing_animation) == .None)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    projection := &runtime.tree_projection
    terminal := uilibrary.tree_projection_find(projection, nodes[1].stable_id)
    root := uilibrary.tree_projection_find(projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    favorites := uilibrary.tree_projection_find(
        projection, collectionmodel.FAVORITES_COLLECTION_ID)
    placement := uilibrary.tree_projection_find(projection, collections.entries[0].id)
    unavailable := uilibrary.tree_projection_find(projection, missing_entry)
    testing.expect_value(t, projection.items[terminal].next_sibling, root)
    testing.expect_value(t, projection.items[root].first_child, favorites)
    testing.expect_value(t, projection.items[favorites].first_child, placement)
    testing.expect(t, projection.items[unavailable].selectable)
    testing.expect_value(t, uilibrary.tree_item_label(
        &ji, &projection.items[unavailable]), "Unavailable animation")
    testing.expect(t, !projection.items[root].expanded)
    testing.expect(t, !projection.items[favorites].expanded)
    testing.expect_value(t, uilibrary.tree_projection_visible_count(
        projection, params.visibility), 4)
    projection.items[root].expanded = true
    projection.items[favorites].expanded = true
    testing.expect_value(t, uilibrary.tree_projection_visible_count(
        projection, params.visibility), 7)
}

// Verify search hides Favorites without losing its explicit expansion state.
@(test)
tree_favorites_search_hides_and_restores_the_subtree :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections: collectionmodel.Set
    params := tree_favorites_fixture(&runtime, &ji, &nodes, &collections)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    projection := &runtime.tree_projection
    root := uilibrary.tree_projection_find(
        projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    favorites := uilibrary.tree_projection_find(
        projection, collectionmodel.FAVORITES_COLLECTION_ID)
    projection.items[root].expanded = true
    projection.items[favorites].expanded = true
    runtime.library_search.active = true
    runtime.library_search.visible_ids[0] = nodes[0].stable_id
    runtime.library_search.visible_id_count = 1
    testing.expect_value(t, uilibrary.tree_projection_visible_count(
        projection, params.visibility), 1)
    runtime.library_search.active = false
    testing.expect_value(t, uilibrary.tree_projection_visible_count(
        projection, params.visibility), 6)
}

// Verify placement selection resolves playback separately and clears on removal.
@(test)
tree_favorites_selection_and_reload_use_canonical_targets :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections: collectionmodel.Set
    params := tree_favorites_fixture(&runtime, &ji, &nodes, &collections)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    placement_key := collections.entries[0].id
    placement_index := uilibrary.tree_projection_find(
        &runtime.tree_projection, placement_key)
    uilibrary.tree_select_item(params,
        &runtime.tree_projection.items[placement_index])
    testing.expect_value(t, ji.selected_animation, &nodes[2])
    testing.expect_value(t, runtime.selected_tree_item_id, placement_key)
    nodes[2].name = "Reloaded animation"
    ji.content_generation += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    placement_index = uilibrary.tree_projection_find(
        &runtime.tree_projection, placement_key)
    testing.expect(t, placement_index != uilibrary.TREE_NO_ITEM)
    testing.expect_value(t, uilibrary.tree_item_label(
        &ji, &runtime.tree_projection.items[placement_index]), "Reloaded animation")
    testing.expect_value(t, runtime.selected_tree_item_id, placement_key)
    testing.expect(t, collectionmodel.favorites_remove(
        &collections, placement_key) == .None)
    params.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, runtime.selected_tree_item_id, uuid.Identifier{})
    testing.expect_value(t, ji.selected_animation, &nodes[2])
}

// Verify Favorites overflow rejects the whole staged projection without truncation.
@(test)
tree_favorites_projection_rejects_combined_capacity_overflow :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    node: bridgemodel.Euclid_Julia_Animation_Interface
    node.stable_id[0] = 1
    ji.animation_head = &node
    ji.animation_count = 1
    ji.content_generation = 1
    collections: collectionmodel.Set
    collectionmodel.initialize(&collections)
    collections.entry_count = viewmodel.UI_TREE_NODE_CAPACITY
    for index in 0..<collections.entry_count {
        entry := &collections.entries[index]
        entry.id[0] = 128
        entry.id[1] = byte(index + 1)
        entry.id[2] = byte((index + 1) >> 8)
        entry.collection_id = collectionmodel.FAVORITES_COLLECTION_ID
        entry.animation_id[0] = byte(index + 1)
        entry.kind = .Animation
        entry.sibling_order = i64(index)
    }
    params := uilibrary.Tree_List_Params{
        ji = &ji, ui_runtime = &runtime, collections = &collections,
        collections_revision = 1,
    }
    testing.expect(t, !uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, runtime.tree_projection.count, 0)
    testing.expect(t, !runtime.tree_projection.valid)
}

// Admit exactly 512 combined nodes and preserve the committed projection on the 513th.
@(test)
tree_favorites_projection_exact_capacity_is_transactional :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    node: bridgemodel.Euclid_Julia_Animation_Interface
    node.stable_id[0] = 1
    ji.animation_head = &node
    ji.animation_count = 1
    ji.content_generation = 1
    collections: collectionmodel.Set
    collectionmodel.initialize(&collections)
    collections.entry_count = viewmodel.UI_TREE_NODE_CAPACITY - 3
    for index in 0..=collections.entry_count {
        entry := &collections.entries[index]
        entry.id[0] = 128
        entry.id[1] = byte(index + 1)
        entry.id[2] = byte((index + 1) >> 8)
        entry.collection_id = collectionmodel.FAVORITES_COLLECTION_ID
        entry.animation_id[0] = 64
        entry.animation_id[1] = byte(index + 1)
        entry.animation_id[2] = byte((index + 1) >> 8)
        entry.kind = .Animation
        entry.sibling_order = i64(index)
    }
    params := uilibrary.Tree_List_Params{
        ji = &ji, ui_runtime = &runtime, collections = &collections,
        collections_revision = 1}
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, runtime.tree_projection.count, 512)
    collections.entry_count += 1
    params.collections_revision += 1
    testing.expect(t, !uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, runtime.tree_projection.count, 512)
    testing.expect(t, runtime.tree_projection.valid)
}

// Keep expanded Collections and Favorites choices through a temporarily empty projection.
@(test)
tree_favorites_expansion_survives_empty_session :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections: collectionmodel.Set
    params := tree_favorites_fixture(&runtime, &ji, &nodes, &collections)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    root := uilibrary.tree_projection_find(
        &runtime.tree_projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    favorites := uilibrary.tree_projection_find(
        &runtime.tree_projection, collectionmodel.FAVORITES_COLLECTION_ID)
    runtime.tree_projection.items[root].expanded = true
    runtime.tree_projection.items[favorites].expanded = true
    entry := collections.entries[0]
    testing.expect_value(t, collectionmodel.favorites_remove(
        &collections, entry.id), collectionmodel.Policy_Error.None)
    params.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, runtime.tree_projection.count, len(nodes))
    testing.expect_value(t, collectionmodel.favorites_add(
        &collections, entry.id, entry.animation_id), collectionmodel.Policy_Error.None)
    params.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect(t, runtime.tree_projection.items[root].expanded)
    testing.expect(t, runtime.tree_projection.items[favorites].expanded)
}
