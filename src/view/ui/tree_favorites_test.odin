#+test
package ui

import bridgemodel "../../bridge/model"
import collectionmodel "../../collections"
import testing "core:testing"
import viewmodel "model"
import uilibrary "library"
import uuid "core:encoding/uuid"

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
