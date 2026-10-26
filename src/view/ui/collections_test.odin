#+test
package ui

import core "../../core"
import collections "../../collections"
import bridgemodel "../../bridge/model"
import userdata "../../userdata"
import uuid "core:encoding/uuid"
import testing "core:testing"
import log "core:log"
import storage "../../core/storage"
import uilibrary "library"
import viewmodel "model"
import uisemantics "semantics"
import viewpreferences "../preferences"

// Empty catalogue startup still prepares the root, while hover/expansion cannot create.
@(test)
tree_collections_root_is_always_present_but_creation_is_selected_only :: proc(
    t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    ji.animation_head = nil
    ji.animation_count = 0
    state^.ui_runtime.library.tree.selected_item_id = {}
    prepared := tree_actions_test_semantic_frame(t, &params)
    testing.expect_value(t, prepared.layout.count, 1)
    root := prepared.layout.rows[0].item
    testing.expect_value(t, root^.kind, viewmodel.Ui_Tree_Item_Kind.Collections)
    testing.expect(t, !prepared.layout.rows[0].actions.eligible)
    root^.expanded = true
    params.mouse_input.mouse_position = {30, 30}
    prepared = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, !prepared.layout.rows[0].actions.eligible)
    state^.ui_runtime.library.tree.selected_item_id = root^.key
    prepared = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, prepared.layout.rows[0].actions.eligible)
    testing.expect(t, uilibrary.tree_collection_create(params))
    prepared = tree_actions_test_semantic_frame(t, &params)
    row := tree_actions_test_row(&prepared.layout, root^.key)
    testing.expect(t, row != nil && !row^.actions.eligible)
}

// Prepare a fresh, empty Library with ordinary messages, playback and semantic owners.
tree_collections_fixture :: proc(
    t: ^testing.T, state: ^core.Euclid_General_State,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    nodes: ^[3]bridgemodel.Euclid_Julia_Animation_Interface) ->
        uilibrary.Tree_List_Params {
    tree_actions_test_registry(ji, nodes)
    testing.expect(t,
        collections.initialize(&state^.preferences_runtime.collections_state))
    state^.ui_runtime.semantic_focus = &state^.semantic_focus
    state^.ui_runtime.layout.active_accordion_section = .Library
    state^.ui_runtime.library.tree.selected_item_id = viewmodel.TREE_COLLECTIONS_ROOT_ID
    return {
        general_state = state,
        ji = ji,
        collections = &state^.preferences_runtime.collections_state,
        ui_runtime = &state^.ui_runtime,
        list_panel = {10, 20, 240, 500},
        scroll_y = &state^.ui_runtime.library.tree.scroll_y,
        mouse_input = {
            sample_time_seconds = 1,
            mouse_position = {-1, -1},
        },
        visibility = {
            search = &state^.ui_runtime.library.search,
        },
        reduce_motion = true,
    }
}

// A selected root alone exposes creation; accepted duplicate names keep distinct UUIDs.
@(test)
tree_collections_create_pointer_and_keyboard_without_playback :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    prepared := tree_actions_test_semantic_frame(t, &params)
    projection := &state^.ui_runtime.library.tree.projection
    builds := projection^.build_count
    root := projection^.items[uilibrary.tree_projection_find(
        projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)]
    row := tree_actions_test_row(&prepared.layout, root^.key)
    testing.expect(t, row != nil && row^.actions.eligible)
    bounds := uilibrary.tree_actions_screen_rect(
        row^.actions.toggle_rect, params.list_panel, params.scroll_y^)
    _ = tree_actions_test_semantic_click(t, &params, bounds)
    first := state^.ui_runtime.library.tree.selected_item_id
    tree_collections_expect_created(t, params, first)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
    testing.expect_value(t, projection^.build_count, builds)
    testing.expect_value(t, projection^.items[
        uilibrary.tree_projection_find(projection, root^.key)], root)
    uilibrary.tree_select_item(params, root)
    _ = tree_actions_test_semantic_frame(t, &params)
    state^.semantic_focus.logical_focus = uilibrary.tree_actions_semantic_id(
        params, root^.key, uilibrary.TREE_COLLECTION_CREATE)
    tree_actions_test_key(t, &params, .Enter)
    second := state^.ui_runtime.library.tree.selected_item_id
    tree_collections_expect_created(t, params, second)
    testing.expect(t, first != second)
    testing.expect_value(t, params.collections^.collection_count, 3)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
}

// Verify the useful empty head with its typed editor and no Favorites shell.
tree_collections_expect_created :: proc(
    t: ^testing.T, params: uilibrary.Tree_List_Params, id: uuid.Identifier) {
    runtime := params.ui_runtime
    testing.expect(t, id != viewmodel.TREE_COLLECTIONS_ROOT_ID)
    index := collections.find_collection(params.collections, id)
    testing.expect(t, index >= 0)
    testing.expect_value(t, string(params.collections^.collections[index].name),
        "New Collection")
    testing.expect(t, runtime^.library.actions.drawer.open)
    testing.expect_value(t, runtime^.library.actions.drawer.entry_id, id)
    testing.expect(t, runtime^.library.entry_name.active)
    testing.expect_value(t, runtime^.library.entry_name.target_kind,
        viewmodel.Ui_Library_Name_Target_Kind.Collection)
    snapshot := uisemantics.semantic_snapshot(runtime^.semantic_focus)
    testing.expect(t, uisemantics.semantic_node_index(snapshot,
        uilibrary.tree_actions_semantic_id(
            params, id, uilibrary.TREE_ENTRY_NAME_INPUT)) >= 0)
    testing.expect_value(t, uilibrary.tree_projection_find(
        &runtime^.library.tree.projection, collections.FAVORITES_COLLECTION_ID), -1)
}

// Native creation obeys clipping, search, selection, generation and drawer lifecycle.
@(test)
tree_collections_semantics_revalidate_context_and_disclosure :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    create := uilibrary.tree_actions_semantic_id(
        params, viewmodel.TREE_COLLECTIONS_ROOT_ID, uilibrary.TREE_COLLECTION_CREATE)
    testing.expect(t, uisemantics.semantic_apply_external_action(
        &state^.semantic_focus, create, .Activate))
    _ = tree_actions_test_semantic_frame(t, &params)
    id := state^.ui_runtime.library.tree.selected_item_id
    tree_collections_expect_created(t, params, id)
    toggle := uilibrary.tree_actions_semantic_id(params, id, uilibrary.TREE_ACTION_TOGGLE)
    tree_collections_expect_disclosure_cycle(t, &params, toggle)
    params.list_panel.height = 0
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, !uilibrary.tree_actions_command_visible(
        params, state^.ui_runtime.library.tree.projection.items[
            uilibrary.tree_projection_find(
                &state^.ui_runtime.library.tree.projection, id)],
        uilibrary.TREE_ACTION_TOGGLE))
    params.list_panel.height = 500
    state^.ui_runtime.library.search.active = true
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, !state^.ui_runtime.library.actions.drawer.open)
    testing.expect(t, uilibrary.tree_actions_command_item(params, toggle) == nil)
    state^.ui_runtime.library.search.active = false
    ji.content_generation += 1
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_actions_command_item(params, toggle) == nil)
    testing.expect_value(t, params.collections^.collection_count, 2)
}

// Native disclosure closes and reopens the same selected empty collection.
tree_collections_expect_disclosure_cycle :: proc(
    t: ^testing.T, params: ^uilibrary.Tree_List_Params,
    toggle: viewmodel.Ui_Node_Id) {
    testing.expect(t, uisemantics.semantic_apply_external_action(
        params^.ui_runtime^.semantic_focus, toggle, .Collapse))
    _ = tree_actions_test_semantic_frame(t, params)
    testing.expect(t, !params^.ui_runtime^.library.actions.drawer.open)
    testing.expect(t, uisemantics.semantic_apply_external_action(
        params^.ui_runtime^.semantic_focus, toggle, .Expand))
    _ = tree_actions_test_semantic_frame(t, params)
    testing.expect(t, params^.ui_runtime^.library.actions.drawer.open)
}

// Failed queue admission preserves data, selection, playback, topology and drawer.
@(test)
tree_collections_queue_rejection_is_transactional :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    store: userdata.Store
    state^.preferences_runtime.settings_store = &store
    defer state^.preferences_runtime.settings_store = nil
    state^.preferences_runtime.collection_mutation_count = collections.MUTATION_CAPACITY
    revision := state^.ui_runtime.library.tree.projection.topology_revision
    previous_logger := context.logger
    context.logger = log.nil_logger()
    testing.expect(t, !uilibrary.tree_collection_create(params))
    context.logger = previous_logger
    testing.expect_value(t, params.collections^.collection_count, 1)
    testing.expect_value(t, state^.ui_runtime.library.tree.selected_item_id,
        viewmodel.TREE_COLLECTIONS_ROOT_ID)
    testing.expect_value(t, ji.selected_animation, &nodes[1])
    testing.expect(t, !state^.ui_runtime.library.actions.drawer.open)
    testing.expect_value(t, state^.ui_runtime.library.tree.projection.topology_revision,
        revision)
}

// Favorites comes and goes before custom empty heads without retiring their identities.
@(test)
tree_collections_favorites_shell_preserves_custom_heads :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    projection := &state^.ui_runtime.library.tree.projection
    custom := projection^.items[uilibrary.tree_projection_find(
        projection, state^.ui_runtime.library.tree.selected_item_id)]
    entry: uuid.Identifier
    entry[0] = 91
    add: collections.Mutation = {
        kind = .Add_Favorite,
        entry_id = entry,
        animation_id = nodes[0].stable_id,
        placement = {
            collection_id = collections.FAVORITES_COLLECTION_ID,
            entry_id = entry,
        },
    }
    testing.expect_value(t, viewpreferences.settings_save_collection_mutation(
        state, add, "Animation"), collections.Mutation_Error.None)
    root := uilibrary.tree_projection_find(
        projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    favorites := uilibrary.tree_projection_find(
        projection, collections.FAVORITES_COLLECTION_ID)
    testing.expect_value(t, projection^.items[root].first_child, favorites)
    testing.expect_value(t, projection^.items[favorites].next_sibling,
        uilibrary.tree_projection_find(projection, custom^.key))
    tree_collections_expect_custom_survives_removal(t, params, add, custom)
}

// A content-generation rebuild restores an empty custom head's accepted label.
@(test)
tree_collections_reload_preserves_empty_head_label :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    id := state^.ui_runtime.library.tree.selected_item_id
    ji.content_generation += 1
    _ = tree_actions_test_semantic_frame(t, &params)
    projection := &state^.ui_runtime.library.tree.projection
    testing.expect_value(t,
        uilibrary.tree_item_label(&ji,
            projection^.items[uilibrary.tree_projection_find(projection, id)],
            params.collections),
        "New Collection")
}

// Retiring the Favorites shell preserves the custom node and both root endpoints.
tree_collections_expect_custom_survives_removal :: proc(
    t: ^testing.T, params: uilibrary.Tree_List_Params,
    add: collections.Mutation, custom: ^viewmodel.Ui_Tree_Item) {
    testing.expect_value(t,
        viewpreferences.settings_save_collection_mutation(
            params.general_state, {
                kind = .Remove_Favorite,
                entry_id = add.entry_id,
                placement = add.placement,
            }),
            collections.Mutation_Error.None)
    projection := &params.ui_runtime^.library.tree.projection
    root := uilibrary.tree_projection_find(
        projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    testing.expect_value(t,
        projection^.items[projection^.items[root].first_child], custom)
    testing.expect_value(t, projection^.items[root].last_child,
        uilibrary.tree_projection_find(projection, custom^.key))
}

// Projection allocation failure leaves no partial data or detached action owner.
@(test)
tree_collections_projection_failure_preserves_accepted_state :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    projection := &state^.ui_runtime.library.tree.projection
    failure_state: Tree_Projection_Test_Allocator_State = {
        backing_allocator = projection^.allocator.backing_allocator,
    }
    projection^.allocator.backing_allocator = {
        procedure = tree_projection_test_failing_allocator,
        data = &failure_state,
    }
    allocator := storage.tlsf_owner_allocator(&projection^.allocator)
    blocks: [1024][]u8
    consumed := tree_favorites_test_allocate_until_failure(&blocks, allocator)
    testing.expect(t, consumed.allocation_error != nil)
    previous_logger := context.logger
    context.logger = log.nil_logger()
    testing.expect(t, !uilibrary.tree_collection_create(params))
    context.logger = previous_logger
    testing.expect_value(t, params.collections^.collection_count, 1)
    testing.expect_value(t, projection^.prepared_node_count, 0)
    testing.expect(t, !projection^.mutation_prepared)
    for block in blocks[:consumed.block_count] {
        delete(block, allocator)
    }
    projection^.allocator.backing_allocator = failure_state.backing_allocator
    testing.expect(t, uilibrary.tree_collection_create(params))
}

// A model rejection frees the provisional head and preserves the prior topology.
@(test)
tree_collections_model_rejection_retires_provisional_node :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    _ = tree_actions_test_semantic_frame(t, &params)
    projection := &state^.ui_runtime.library.tree.projection
    count := projection^.count
    id: uuid.Identifier
    id[0] = 71
    mutation: collections.Mutation = {
        kind = .Create_Collection,
        collection_id = id,
        collection_name_length = 0,
    }
    testing.expect_value(t, viewpreferences.settings_save_collection_mutation(
        state, mutation), collections.Mutation_Error.Invalid_Name)
    testing.expect_value(t, projection^.count, count)
    testing.expect_value(t, projection^.prepared_node_count, 0)
    testing.expect(t, !projection^.mutation_prepared)
    testing.expect_value(t, params.collections^.collection_count, 1)
}

// The empty drawer uses ordinary motion in narrow panes and disappears on collapse.
@(test)
tree_collections_empty_drawer_motion_and_parent_collapse :: proc(t: ^testing.T) {
    state := make_shell_test_state(t)
    defer destroy_shell_test_state(state)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [3]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_collections_fixture(t, state, &ji, &nodes)
    params.reduce_motion = false
    params.list_panel.width = 100
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, uilibrary.tree_collection_create(params))
    testing.expect(t, state^.ui_runtime.library.actions.drawer.running)
    params.mouse_input.sample_time_seconds += 1
    prepared := tree_actions_test_semantic_frame(t, &params)
    id := state^.ui_runtime.library.tree.selected_item_id
    row := tree_actions_test_row(&prepared.layout, id)
    testing.expect(t, row != nil && row^.actions.open)
    testing.expect_value(t, row^.actions.height,
        uilibrary.tree_actions_full_height(params.list_panel.width, row^.depth) +
            uilibrary.TREE_ACTION_BUTTON_HEIGHT + uilibrary.TREE_ACTION_BUTTON_GAP)
    testing.expect(t, row^.actions.move_up_rect.width > 0)
    testing.expect(t, row^.actions.move_down_rect.y > row^.actions.move_up_rect.y)
    testing.expect(t, !row^.actions.move_up_enabled && !row^.actions.move_down_enabled)
    projection := &state^.ui_runtime.library.tree.projection
    root := uilibrary.tree_projection_find(projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    projection^.items[root].expanded = false
    params.mouse_input.sample_time_seconds += 1
    _ = tree_actions_test_semantic_frame(t, &params)
    testing.expect(t, !state^.ui_runtime.library.actions.drawer.open)
    testing.expect_value(t, state^.semantic_focus.logical_focus,
        uilibrary.tree_semantic_id())
}
