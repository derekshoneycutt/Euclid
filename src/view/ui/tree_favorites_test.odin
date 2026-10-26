#+test
package ui

import bridgemodel "../../bridge/model"
import collectionmodel "../../collections"
import testing "core:testing"
import viewmodel "model"
import uilibrary "library"
import uuid "core:encoding/uuid"
import runtime "base:runtime"
import uisemantics "semantics"
import contentdata "../../core/content"
import storage "../../core/storage"

Tree_Projection_Test_Allocator_State :: struct {
    backing_allocator: runtime.Allocator,
}

Tree_Favorites_Stable_Nodes :: struct {
    first_key: uuid.Identifier,
    second_key: uuid.Identifier,
    first: ^viewmodel.Ui_Tree_Item,
    second: ^viewmodel.Ui_Tree_Item,
    build_count: u64,
}

Tree_Projection_Pool_Consumption :: struct {
    block_count: int,
    allocation_error: runtime.Allocator_Error,
}

// Fail projection-owner growth while forwarding releases to its original owner.
tree_projection_test_failing_allocator :: proc(
    allocator_data: rawptr,
    mode: runtime.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr,
    old_size: int,
    location: runtime.Source_Code_Location = #caller_location) ->
        ([]byte, runtime.Allocator_Error) {
    state := cast(^Tree_Projection_Test_Allocator_State)allocator_data
    if mode == .Alloc || mode == .Alloc_Non_Zeroed {
        return nil, .Out_Of_Memory
    }
    return state.backing_allocator.procedure(
        state.backing_allocator.data, mode, size, alignment,
        old_memory, old_size, location)
}

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
    entry_id: uuid.Identifier = {}
    entry_id[0] = 91
    assert(collectionmodel.favorites_add(
        collections, entry_id, nodes[2].stable_id) == .None)
    return {
        ji = ji,
        ui_runtime = runtime,
        collections = collections,
        collections_revision = 1,
        scroll_y = &runtime^.library.tree.scroll_y,
        list_panel = {0, 0, 240, 240},
        visibility = {
            search = &runtime^.library.search,
        },
    }
}

// Construct a distinct valid Favorites placement for capacity fixtures.
tree_favorites_test_entry :: proc(index: int) -> collectionmodel.Entry {
    entry: collectionmodel.Entry
    entry.id[0] = 128
    entry.id[1] = byte(index + 1)
    entry.id[2] = byte((index + 1) >> 8)
    entry.collection_id = collectionmodel.FAVORITES_COLLECTION_ID
    entry.animation_id[0] = 64
    entry.animation_id[1] = byte(index + 1)
    entry.animation_id[2] = byte((index + 1) >> 8)
    entry.kind = .Animation
    entry.sibling_order = i64(index)
    return entry
}

// Release a test Library's owned records and its test-allocated owner record.
tree_favorites_destroy_set :: proc(set: ^collectionmodel.Set) {
    collectionmodel.destroy(set)
    free(set, context.allocator)
}

// tree_favorites_expect_semantic_order checks member count and current linked order.
tree_favorites_expect_semantic_order :: proc(
    t: ^testing.T, params: uilibrary.Tree_List_Params, expected: [3]u8) {
    snapshot := uisemantics.semantic_snapshot(params.ui_runtime^.semantic_focus)
    parent: viewmodel.Ui_Node_Id = {
        domain = .Animation_Tree,
        stable_id = collectionmodel.FAVORITES_COLLECTION_ID,
    }
    count := 0
    for node in snapshot^.nodes[:snapshot^.node_count] {
        if node.role != .Tree_Item || node.parent != parent {
            continue
        }
        testing.expect_value(t, node.position_in_set, u32(count + 1))
        testing.expect_value(t, node.set_size, u32(3))
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
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.library.tree.selected_item_id
    toggle := uilibrary.tree_actions_semantic_id(params,
        selected, uilibrary.TREE_ACTION_TOGGLE)
    tree_favorites_expect_action_disclosure(t, semantic, toggle, selected)
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

// Verify localized disclosure text and hierarchy before the drawer opens.
tree_favorites_expect_action_disclosure :: proc(
    t: ^testing.T, semantic: ^viewmodel.Ui_Semantic_Focus_State,
    toggle: viewmodel.Ui_Node_Id, selected: uuid.Identifier) {
    snapshot := uisemantics.semantic_snapshot(semantic)
    node := snapshot^.nodes[uisemantics.semantic_node_index(snapshot, toggle)]
    testing.expect_value(t, uisemantics.semantic_node_text(
        snapshot, node.label_offset, node.label_length), "Actions for Animation")
    testing.expect_value(t, node.parent.stable_id, selected)
    testing.expect_value(t, node.controls.local_id, uilibrary.TREE_ACTION_DRAWER)
    testing.expect(t, .Expanded not_in node.states)
}

// Verify admitted requests cannot act after closing, deselection, clipping, or reload.
@(test)
tree_favorites_actions_reject_stale_queued_activations :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    selected := state^.ui_runtime.library.tree.selected_item_id
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
    state^.ui_runtime.library.tree.selected_item_id = nodes[0].stable_id
    testing.expect(t, uilibrary.tree_actions_command_item(params, toggle) == nil)
    state^.ui_runtime.library.tree.selected_item_id = selected
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
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    state^.ui_runtime.semantic_focus = semantic
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_actions_test_fixture(state, &ji, &nodes)
    selected := state^.ui_runtime.library.tree.selected_item_id
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
    selected := params.ui_runtime^.library.tree.selected_item_id
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
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    params := tree_favorites_fixture(&runtime, &ji, &nodes, collections)
    defer viewmodel.ui_tree_projection_destroy(&runtime.library.tree.projection)
    missing_entry, missing_animation: uuid.Identifier
    missing_entry[0], missing_animation[0] = 92, 99
    assert(collectionmodel.favorites_add(
        collections, missing_entry, missing_animation) == .None)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    projection := &runtime.library.tree.projection
    terminal := uilibrary.tree_projection_find(projection, nodes[1].stable_id)
    root := uilibrary.tree_projection_find(projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    favorites := uilibrary.tree_projection_find(
        projection, collectionmodel.FAVORITES_COLLECTION_ID)
    placement := uilibrary.tree_projection_find(projection, collections^.entries[0].id)
    unavailable := uilibrary.tree_projection_find(projection, missing_entry)
    testing.expect_value(t, projection.items[terminal].next_sibling, root)
    testing.expect_value(t, projection.items[root].first_child, favorites)
    testing.expect_value(t, projection.items[favorites].first_child, placement)
    testing.expect(t, projection.items[unavailable].selectable)
    testing.expect_value(t, uilibrary.tree_item_label(
        &ji, projection.items[unavailable]), "Unavailable animation")
    testing.expect(t, !projection.items[root].expanded)
    testing.expect(t, !projection.items[favorites].expanded)
    testing.expect_value(t, uilibrary.tree_projection_visible_count(
        projection, params.visibility), 4)
    projection.items[root].expanded = true
    projection.items[favorites].expanded = true
    testing.expect_value(t, uilibrary.tree_projection_visible_count(
        projection, params.visibility), 7)
}

// Verify labels borrow custom names from the collection owner, not a stack copy.
@(test)
tree_favorites_custom_labels_remain_stable_across_resolution :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    params := tree_favorites_fixture(&runtime, &ji, &nodes, collections)
    defer viewmodel.ui_tree_projection_destroy(&runtime.library.tree.projection)

    second_entry: uuid.Identifier = {}
    second_entry[0] = 92
    testing.expect_value(t, collectionmodel.favorites_add(
        collections, second_entry, nodes[0].stable_id), collectionmodel.Policy_Error.None)
    tree_favorites_test_set_entry_name(
        t, collections, collections^.entries[0].id, "First saved name")
    tree_favorites_test_set_entry_name(
        t, collections, second_entry, "Second saved name")
    testing.expect(t, uilibrary.tree_projection_prepare(params))

    first_index := uilibrary.tree_projection_find(
        &runtime.library.tree.projection, collections^.entries[0].id)
    second_index := uilibrary.tree_projection_find(
        &runtime.library.tree.projection, second_entry)
    first := uilibrary.tree_item_label(
        &ji, runtime.library.tree.projection.items[first_index], collections)
    second := uilibrary.tree_item_label(
        &ji, runtime.library.tree.projection.items[second_index], collections)
    testing.expect_value(t, second, "Second saved name")
    testing.expect_value(t, first, "First saved name")
}

// Set a placement label through its captured identity, checking each policy result.
tree_favorites_test_set_entry_name :: proc(
    t: ^testing.T,
    collections: ^collectionmodel.Set,
    entry_id: uuid.Identifier,
    name: string) {
    identity, identity_error :=
        collectionmodel.placement_identity_for_entry(collections, entry_id)
    testing.expect_value(t, identity_error, collectionmodel.Policy_Error.None)
    testing.expect_value(t, collectionmodel.placement_entry_name_set(
        collections, identity, transmute([]u8)name, len(name)),
        collectionmodel.Policy_Error.None)
}

// Keep placement nodes stable while additions and local names change.
@(test)
tree_favorites_local_add_and_rename_preserve_nodes :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    params := tree_favorites_fixture(&runtime, &ji, &nodes, collections)
    defer viewmodel.ui_tree_projection_destroy(&runtime.library.tree.projection)
    testing.expect(t, uilibrary.tree_projection_prepare(params))

    projection := &runtime.library.tree.projection
    first_key := collections^.entries[0].id
    first_node := projection.items[uilibrary.tree_projection_find(projection, first_key)]
    initial_build_count := projection.build_count
    second_key: uuid.Identifier = {}
    second_key[0] = 92
    testing.expect_value(t, collectionmodel.favorites_add(
        collections, second_key, nodes[0].stable_id), collectionmodel.Policy_Error.None)
    params.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    second_node :=
        projection.items[uilibrary.tree_projection_find(projection, second_key)]
    testing.expect_value(t,
        projection.items[uilibrary.tree_projection_find(projection, first_key)],
        first_node)
    tree_favorites_test_rename_entry(
        t, collections, first_key, "Retained label")
    params.collections_revision += 1
    topology_revision := projection.topology_revision
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, projection.topology_revision, topology_revision)
    testing.expect_value(t, uilibrary.tree_item_label(&ji, first_node, collections),
        "Retained label")
    testing.expect_value(t, projection.build_count, initial_build_count)
}

// Rename one placement through its identity-qualified in-memory mutation.
tree_favorites_test_rename_entry :: proc(
    t: ^testing.T,
    collections: ^collectionmodel.Set,
    entry_id: uuid.Identifier,
    name: string) {
    identity, identity_error :=
        collectionmodel.placement_identity_for_entry(collections, entry_id)
    testing.expect_value(t, identity_error, collectionmodel.Policy_Error.None)
    rename, rename_error := collectionmodel.make_placement_name_mutation(
        identity, name)
    testing.expect_value(t, rename_error, collectionmodel.Mutation_Error.None)
    testing.expect_value(t, collectionmodel.apply_mutation(collections, rename),
        collectionmodel.Mutation_Error.None)
}

// Keep placement nodes stable while local sibling order changes.
@(test)
tree_favorites_local_move_preserves_nodes_and_build_count :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    params := tree_favorites_fixture(&runtime, &ji, &nodes, collections)
    defer viewmodel.ui_tree_projection_destroy(&runtime.library.tree.projection)
    testing.expect(t, uilibrary.tree_projection_prepare(params))

    projection := &runtime.library.tree.projection
    stable := tree_favorites_test_add_move_pair(
        t, &params, collections, &nodes)
    tree_favorites_test_expect_moved_pair(t, projection, stable)
}

// Add the second placement and move the first below it without rebuilding.
tree_favorites_test_add_move_pair :: proc(
    t: ^testing.T,
    params: ^uilibrary.Tree_List_Params,
    collections: ^collectionmodel.Set,
    nodes: ^[3]bridgemodel.Euclid_Julia_Animation_Interface) ->
    Tree_Favorites_Stable_Nodes {
    first_key := collections^.entries[0].id
    first_identity, identity_error :=
        collectionmodel.placement_identity_for_entry(collections, first_key)
    testing.expect_value(t, identity_error, collectionmodel.Policy_Error.None)
    second_key: uuid.Identifier = {}
    second_key[0] = 92
    testing.expect_value(t, collectionmodel.favorites_add(
        collections, second_key, nodes[0].stable_id), collectionmodel.Policy_Error.None)
    params^.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params^))
    projection := &params^.ui_runtime^.library.tree.projection
    stable: Tree_Favorites_Stable_Nodes = {
        first_key = first_key,
        second_key = second_key,
        first = projection.items[uilibrary.tree_projection_find(projection, first_key)],
        second = projection.items[uilibrary.tree_projection_find(projection, second_key)],
        build_count = projection.build_count,
    }
    move, move_error := collectionmodel.make_placement_move(
        collections, first_identity, .Down)
    testing.expect_value(t, move_error, collectionmodel.Policy_Error.None)
    testing.expect_value(t, collectionmodel.apply_mutation(collections, move),
        collectionmodel.Mutation_Error.None)
    params^.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params^))
    return stable
}

// Assert local reorder changed links but retained both nodes and build count.
tree_favorites_test_expect_moved_pair :: proc(
    t: ^testing.T,
    projection: ^viewmodel.Ui_Tree_Projection,
    stable: Tree_Favorites_Stable_Nodes) {
    favorites := uilibrary.tree_projection_find(
        projection, collectionmodel.FAVORITES_COLLECTION_ID)
    testing.expect_value(t, projection.items[favorites].first_child,
        uilibrary.tree_projection_find(projection, stable.second_key))
    testing.expect_value(t,
        projection.items[projection.items[favorites].first_child].next_sibling,
        uilibrary.tree_projection_find(projection, stable.first_key))
    testing.expect_value(t,
        projection.items[uilibrary.tree_projection_find(projection, stable.first_key)],
        stable.first)
    testing.expect_value(t,
        projection.items[uilibrary.tree_projection_find(projection, stable.second_key)],
        stable.second)
    testing.expect_value(t, projection.build_count, stable.build_count)
}

// Verify search hides Favorites without losing its explicit expansion state.
@(test)
tree_favorites_search_hides_and_restores_the_subtree :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    params := tree_favorites_fixture(&runtime, &ji, &nodes, collections)
    defer viewmodel.ui_tree_projection_destroy(&runtime.library.tree.projection)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    projection := &runtime.library.tree.projection
    root := uilibrary.tree_projection_find(
        projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    favorites := uilibrary.tree_projection_find(
        projection, collectionmodel.FAVORITES_COLLECTION_ID)
    projection.items[root].expanded = true
    projection.items[favorites].expanded = true
    search := &runtime.library.search
    defer viewmodel.library_search_destroy(search)
    testing.expect(t, viewmodel.library_search_reserve_ids(search, false, 1))
    search.visible_ids[0] = nodes[0].stable_id
    search.visible_id_count = 1
    search.active = true
    testing.expect_value(t, uilibrary.tree_projection_visible_count(
        projection, params.visibility), 1)
    runtime.library.search.active = false
    testing.expect_value(t, uilibrary.tree_projection_visible_count(
        projection, params.visibility), 6)
}

// Verify placement selection resolves playback separately and clears on removal.
@(test)
tree_favorites_selection_and_reload_use_canonical_targets :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    params := tree_favorites_fixture(&runtime, &ji, &nodes, collections)
    defer viewmodel.ui_tree_projection_destroy(&runtime.library.tree.projection)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    placement_key := collections^.entries[0].id
    placement_index := uilibrary.tree_projection_find(
        &runtime.library.tree.projection, placement_key)
    uilibrary.tree_select_item(params,
        runtime.library.tree.projection.items[placement_index])
    testing.expect_value(t, ji.selected_animation, &nodes[2])
    testing.expect_value(t, runtime.library.tree.selected_item_id, placement_key)
    nodes[2].name = "Reloaded animation"
    ji.content_generation += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    placement_index = uilibrary.tree_projection_find(
        &runtime.library.tree.projection, placement_key)
    testing.expect(t, placement_index != uilibrary.TREE_NO_ITEM)
    testing.expect_value(t, uilibrary.tree_item_label(
        &ji, runtime.library.tree.projection.items[placement_index], collections),
        "Reloaded animation")
    testing.expect_value(t, runtime.library.tree.selected_item_id, placement_key)
    testing.expect(t, collectionmodel.favorites_remove(
        collections, placement_key) == .None)
    params.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, runtime.library.tree.selected_item_id, uuid.Identifier{})
    testing.expect_value(t, ji.selected_animation, &nodes[2])
}

// Reject a queued command after removal and re-addition under a new placement UUID.
@(test)
tree_favorites_stale_command_rejected_after_node_retirement :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    params := tree_favorites_fixture(&runtime, &ji, &nodes, collections)
    defer viewmodel.ui_tree_projection_destroy(&runtime.library.tree.projection)
    testing.expect(t, uilibrary.tree_projection_prepare(params))

    old_key := collections^.entries[0].id
    runtime.library.tree.selected_item_id = old_key
    root := uilibrary.tree_projection_find(
        &runtime.library.tree.projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    favorites := uilibrary.tree_projection_find(
        &runtime.library.tree.projection, collectionmodel.FAVORITES_COLLECTION_ID)
    runtime.library.tree.projection.items[root].expanded = true
    runtime.library.tree.projection.items[favorites].expanded = true
    stale_command := uilibrary.tree_actions_semantic_id(
        params, old_key, uilibrary.TREE_ACTION_TOGGLE)
    old_node := runtime.library.tree.projection.items[
        uilibrary.tree_projection_find(&runtime.library.tree.projection, old_key)]
    testing.expect(t,
        uilibrary.tree_actions_command_item(params, stale_command) == old_node)
    testing.expect_value(t, collectionmodel.favorites_remove(
        collections, old_key), collectionmodel.Policy_Error.None)
    params.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    new_key: uuid.Identifier = {}
    new_key[0] = 93
    tree_favorites_test_readd_and_reject_stale(
        t, &params, &runtime, new_key, stale_command)
}

// Re-add under a fresh identity and prove the retired command stays invalid.
tree_favorites_test_readd_and_reject_stale :: proc(
    t: ^testing.T,
    params: ^uilibrary.Tree_List_Params,
    runtime: ^viewmodel.Euclid_Ui_Runtime_State,
    new_key: uuid.Identifier,
    stale_command: viewmodel.Ui_Node_Id) {
    testing.expect_value(t, collectionmodel.favorites_add(
        params^.collections, new_key, params^.ji^.animation_head.stable_id),
        collectionmodel.Policy_Error.None)
    params^.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params^))
    runtime^.library.tree.selected_item_id = new_key
    new_node := runtime^.library.tree.projection.items[
        uilibrary.tree_projection_find(&runtime^.library.tree.projection, new_key)]
    testing.expect(t, new_node != nil)
    testing.expect(t,
        uilibrary.tree_actions_command_item(params^, stale_command) == nil)
}

// Preserve the currently published projection when a candidate generation is invalid.
@(test)
tree_favorites_failed_generation_preserves_live_projection :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    params := tree_favorites_fixture(&runtime, &ji, &nodes, collections)
    defer viewmodel.ui_tree_projection_destroy(&runtime.library.tree.projection)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    projection := &runtime.library.tree.projection
    stable_node := projection.items[0]
    stable_generation := projection.content_generation

    ji.content_generation += 1
    ji.animation_count += 1
    staged: viewmodel.Ui_Tree_Projection
    testing.expect(t, uilibrary.tree_projection_begin(params, projection, &staged))
    defer viewmodel.ui_tree_projection_destroy(&staged)
    has_terminal: bool
    testing.expect(t, !uilibrary.tree_projection_registry_info(&ji, &has_terminal))
    testing.expect(t, projection.valid)
    testing.expect_value(t, projection.content_generation, stable_generation)
    testing.expect_value(t, projection.items[0], stable_node)
}

// Reject an allocation-starved topology patch without changing accepted data or nodes.
@(test)
tree_favorites_allocation_rejection_preserves_live_state :: proc(t: ^testing.T) {
    runtime_state: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    params := tree_favorites_fixture(&runtime_state, &ji, &nodes, collections)
    defer viewmodel.ui_tree_projection_destroy(
        &runtime_state.library.tree.projection)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    tree_favorites_test_exhaust_pool_and_reject_add(
        t, &runtime_state.library.tree.projection, collections, &nodes[0])
}

// Exhaust TLSF backing storage, reject a tree patch, and restore the allocator.
tree_favorites_test_exhaust_pool_and_reject_add :: proc(
    t: ^testing.T,
    projection: ^viewmodel.Ui_Tree_Projection,
    collections: ^collectionmodel.Set,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface) {
    original_count := projection.count
    original_node := projection.items[0]
    failure_state: Tree_Projection_Test_Allocator_State = {
        backing_allocator = projection.allocator.backing_allocator,
    }
    projection.allocator.backing_allocator = {
        procedure = tree_projection_test_failing_allocator,
        data = &failure_state,
    }
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    blocks: [1024][]u8
    consumption := tree_favorites_test_allocate_until_failure(&blocks, allocator)
    testing.expect(t,
        consumption.block_count > 0 && consumption.block_count < len(blocks))
    testing.expect(t, consumption.allocation_error != nil)
    entry_id: uuid.Identifier = {}
    entry_id[0] = 94
    tree_favorites_test_expect_allocation_rejected_add(
        t, projection, collections, animation, entry_id)

    for block in blocks[:consumption.block_count] {
        delete(block, allocator)
    }
    projection.allocator.backing_allocator = failure_state.backing_allocator
}

// Consume reusable pool space until its backing allocator rejects growth.
tree_favorites_test_allocate_until_failure :: proc(
    blocks: ^[1024][]u8,
    allocator: runtime.Allocator) -> Tree_Projection_Pool_Consumption {
    result: Tree_Projection_Pool_Consumption
    for index in 0..<len(blocks^) {
        block, error := make([]u8, 64, allocator)
        if error != nil {
            result.allocation_error = error
            break
        }
        blocks^[index] = block
        result.block_count += 1
    }
    return result
}

// Verify a failed local add leaves the accepted projection and collection intact.
tree_favorites_test_expect_allocation_rejected_add :: proc(
    t: ^testing.T,
    projection: ^viewmodel.Ui_Tree_Projection,
    collections: ^collectionmodel.Set,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface,
    entry_id: uuid.Identifier) {
    original_count := projection.count
    original_node := projection.items[0]
    mutation: collectionmodel.Mutation = {
        kind = .Add_Favorite,
        placement = {
            collection_id = collectionmodel.FAVORITES_COLLECTION_ID,
            entry_id = entry_id,
        },
        entry_id = entry_id,
        animation_id = animation.stable_id,
    }
    testing.expect_value(t, viewmodel.ui_tree_projection_prepare_mutation(
        projection, mutation, animation.name),
        collectionmodel.Mutation_Error.Allocation_Failed)
    testing.expect_value(t, projection.count, original_count)
    testing.expect_value(t, projection.items[0], original_node)
    testing.expect_value(t, projection.prepared_node_count, 0)
    testing.expect(t, !projection.mutation_prepared)
    testing.expect_value(t, collections^.entry_count, 1)
}

// Verify dynamic projection storage admits more nodes than the former fixed bound.
@(test)
tree_favorites_projection_grows_past_fixed_capacity :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    node: bridgemodel.Euclid_Julia_Animation_Interface
    node.stable_id[0] = 1
    ji.animation_head = &node
    ji.animation_count = 1
    ji.content_generation = 1
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    collectionmodel.initialize(collections)
    for index in 0..<viewmodel.UI_TREE_NODE_CAPACITY {
        testing.expect_value(t, collectionmodel.append_entry(
            collections, tree_favorites_test_entry(index)),
            collectionmodel.Policy_Error.None)
    }
    params: uilibrary.Tree_List_Params = {
        ji = &ji,
        ui_runtime = &runtime,
        collections = collections,
        collections_revision = 1,
    }
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, runtime.library.tree.projection.count,
        viewmodel.UI_TREE_NODE_CAPACITY + 3)
    testing.expect(t, runtime.library.tree.projection.valid)
}

// Grow past the former bound without moving unaffected node addresses.
@(test)
tree_favorites_projection_growth_preserves_node_addresses :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    node: bridgemodel.Euclid_Julia_Animation_Interface
    node.stable_id[0] = 1
    ji.animation_head = &node
    ji.animation_count = 1
    ji.content_generation = 1
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    collectionmodel.initialize(collections)
    for index in 0..<viewmodel.UI_TREE_NODE_CAPACITY-3 {
        testing.expect_value(t, collectionmodel.append_entry(
            collections, tree_favorites_test_entry(index)),
            collectionmodel.Policy_Error.None)
    }
    params: uilibrary.Tree_List_Params = {
        ji = &ji,
        ui_runtime = &runtime,
        collections = collections,
        collections_revision = 1,
    }
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, runtime.library.tree.projection.count, 512)
        stable_node := runtime.library.tree.projection.items[0]
        stable_id := stable_node.key
        testing.expect_value(t, collectionmodel.append_entry(
            collections, tree_favorites_test_entry(collections^.entry_count)),
            collectionmodel.Policy_Error.None)
        params.collections_revision += 1
        testing.expect(t, uilibrary.tree_projection_prepare(params))
        testing.expect_value(t, runtime.library.tree.projection.count, 513)
        testing.expect(t, runtime.library.tree.projection.valid)
        testing.expect_value(t, runtime.library.tree.projection.items[0], stable_node)
        testing.expect_value(t, runtime.library.tree.projection.items[0].key, stable_id)
}

// Keep expanded Collections and Favorites choices through a temporarily empty projection.
@(test)
tree_favorites_expansion_survives_empty_session :: proc(t: ^testing.T) {
    runtime: viewmodel.Euclid_Ui_Runtime_State
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    collections := new(collectionmodel.Set, context.allocator)
    defer tree_favorites_destroy_set(collections)
    params := tree_favorites_fixture(&runtime, &ji, &nodes, collections)
    defer viewmodel.ui_tree_projection_destroy(&runtime.library.tree.projection)
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    root := uilibrary.tree_projection_find(
        &runtime.library.tree.projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    favorites := uilibrary.tree_projection_find(
        &runtime.library.tree.projection, collectionmodel.FAVORITES_COLLECTION_ID)
    runtime.library.tree.projection.items[root].expanded = true
    runtime.library.tree.projection.items[favorites].expanded = true
    entry := collections^.entries[0]
    testing.expect_value(t, collectionmodel.favorites_remove(
        collections, entry.id), collectionmodel.Policy_Error.None)
    params.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    testing.expect_value(t, runtime.library.tree.projection.count, len(nodes) + 1)
    testing.expect_value(t, collectionmodel.favorites_add(
        collections, entry.id, entry.animation_id), collectionmodel.Policy_Error.None)
    params.collections_revision += 1
    testing.expect(t, uilibrary.tree_projection_prepare(params))
    root = uilibrary.tree_projection_find(
        &runtime.library.tree.projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    favorites = uilibrary.tree_projection_find(
        &runtime.library.tree.projection, collectionmodel.FAVORITES_COLLECTION_ID)
    testing.expect(t, runtime.library.tree.projection.items[root].expanded)
    testing.expect(t, runtime.library.tree.projection.items[favorites].expanded)
}
