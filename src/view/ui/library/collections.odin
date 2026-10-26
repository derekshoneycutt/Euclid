package uilibrary

import collections "../../../collections"
import uuid "core:encoding/uuid"
import crypto "core:crypto"
import log "core:log"
import viewmodel "../model"
import viewmessages "../../messages"
import viewpreferences "../../preferences"
import storage "../../../core/storage"

// Test whether an optional system head has any retained placements.
tree_collection_has_entries :: proc(
    set: ^collections.Set, id: uuid.Identifier) -> bool {
    for entry in set^.entries[:set^.entry_count] {
        if entry.collection_id == id {
            return true
        }
    }
    return false
}

// Restore custom heads in durable order, including independently named empty heads.
tree_projection_add_custom_heads :: proc(
    projection, previous: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set, root: int) -> bool {
    count, ok := tree_collection_order_workspace(projection, set)
    if !ok {
        return false
    }
    for index in projection^.order_workspace[:count] {
        if tree_projection_add(projection, previous,
            {
                key = set^.collections[index].id,
                kind = .Collection,
                parent = root,
                selectable = true,
            }) == TREE_NO_ITEM {
            return false
        }
    }
    return true
}

// Sort custom collection indexes into reusable, display-owned preparation storage.
tree_collection_order_workspace :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set) -> (int, bool) {
    if !viewmodel.ui_tree_projection_reserve_order_workspace(
        projection, set^.collection_count) {
        return 0, false
    }
    count := 0
    for collection, index in set^.collections[:set^.collection_count] {
        if collection.role != .User {
            continue
        }
        position := count
        for position > 0 &&
            set^.collections[projection^.order_workspace[position - 1]].order >
                collection.order {
            projection^.order_workspace[position] =
                projection^.order_workspace[position - 1]
            position -= 1
        }
        projection^.order_workspace[position] = index
        count += 1
    }
    return count, true
}

// Admit externally loaded custom heads together before linking their durable order.
tree_projection_reconcile_custom_heads :: proc(
    projection: ^viewmodel.Ui_Tree_Projection, set: ^collections.Set) -> bool {
    original_count := projection^.count
    if !tree_projection_reconcile_remove_stale_custom(projection, set) {
        return false
    }
    count, ok := tree_collection_order_workspace(projection, set)
    if !ok {
        return false
    }
    missing := 0
    for index in projection^.order_workspace[:count] {
        if tree_projection_find(projection, set^.collections[index].id) == TREE_NO_ITEM {
            missing += 1
        }
    }
    order_changed := tree_projection_custom_heads_order_changed(
        projection, set, count)
    if missing > 0 &&
       !tree_projection_stage_custom_heads(projection, set, count, missing) {
        return false
    }
    tree_projection_link_custom_heads(projection, set, count)
    if missing > 0 || projection^.count != original_count || order_changed {
        projection^.topology_revision += 1
    }
    return true
}

// Restore the durable custom head order after the optional Favorites head.
tree_projection_link_custom_heads :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set, count: int) {
    root := tree_projection_find(projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    parent := projection^.items[root]
    favorites := tree_projection_find(projection, collections.FAVORITES_COLLECTION_ID)
    parent.first_child, parent.last_child = favorites, favorites
    if favorites != TREE_NO_ITEM {
        projection^.items[favorites].next_sibling = TREE_NO_ITEM
    }
    for index in projection^.order_workspace[:count] {
        node := tree_projection_find(projection, set^.collections[index].id)
        tree_projection_link(projection, node, root)
        projection^.items[node].next_sibling = TREE_NO_ITEM
    }
}

// Detect custom head order changes before accepted root links are rewritten.
tree_projection_custom_heads_order_changed :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set,
    count: int) -> bool {
    root := tree_projection_find(projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    if root == TREE_NO_ITEM {
        return true
    }
    current := projection^.items[root].first_child
    if current != TREE_NO_ITEM &&
        projection^.items[current].key == collections.FAVORITES_COLLECTION_ID {
        current = projection^.items[current].next_sibling
    }
    for order_index in 0..<count {
        if current == TREE_NO_ITEM ||
            projection^.items[current].key !=
                set^.collections[projection^.order_workspace[order_index]].id {
            return true
        }
        current = projection^.items[current].next_sibling
    }
    return current != TREE_NO_ITEM
}

// Allocate all absent heads before changing any accepted topology links.
tree_projection_stage_custom_heads :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set, count, missing: int) -> bool {
    if !viewmodel.ui_tree_projection_reserve(projection, projection^.count + missing) {
        return false
    }
    allocator := storage.tlsf_owner_allocator(&projection^.allocator)
    nodes := make([]^viewmodel.Ui_Tree_Item, missing, allocator)
    if len(nodes) != missing {
        return false
    }
    return tree_projection_stage_custom_head_nodes(projection, set, count, nodes)
}

// Fill and validate a detached head batch before publishing accepted node records.
tree_projection_stage_custom_head_nodes :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set, count: int,
    nodes: []^viewmodel.Ui_Tree_Item) -> bool {
    allocator := storage.tlsf_owner_allocator(&projection^.allocator)
    node_count := 0
    root := tree_projection_find(projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    for index in projection^.order_workspace[:count] {
        id := set^.collections[index].id
        if tree_projection_find(projection, id) != TREE_NO_ITEM {
            continue
        }
        node, ok := viewmodel.ui_tree_projection_make_node({
            key = id,
            kind = .Collection,
            selectable = true,
            parent = root,
            first_child = TREE_NO_ITEM,
            last_child = TREE_NO_ITEM,
            next_sibling = TREE_NO_ITEM,
        }, "", allocator)
        if !ok {
            tree_projection_reconcile_free_nodes(projection, nodes, node_count)
            return false
        }
        nodes[node_count] = node
        node_count += 1
    }
    if !tree_projection_reconcile_nodes_are_unique(projection, nodes, node_count) ||
        !tree_projection_reconcile_commit_nodes(projection, nodes, node_count) {
        tree_projection_reconcile_free_nodes(projection, nodes, node_count)
        return false
    }
    delete(nodes, allocator)
    return true
}

// Place Favorites before custom heads without disturbing their linked order.
tree_projection_place_favorites_first :: proc(
    projection: ^viewmodel.Ui_Tree_Projection, root, favorites: int) {
    parent := projection^.items[root]
    node := projection^.items[favorites]
    if parent.first_child == favorites {
        return
    }
    if parent.last_child == favorites {
        for index := parent.first_child; index != TREE_NO_ITEM;
            index = projection^.items[index].next_sibling {
            if projection^.items[index].next_sibling == favorites {
                projection^.items[index].next_sibling = TREE_NO_ITEM
                parent.last_child = index
                break
            }
        }
    }
    node.parent = root
    node.next_sibling = parent.first_child
    parent.first_child = favorites
    if parent.last_child == TREE_NO_ITEM {
        parent.last_child = favorites
    }
}

// Generate a secure UUID that cannot alias data or a current catalogue control.
tree_collection_new_id :: proc(params: Tree_List_Params) -> (uuid.Identifier, bool) {
    if !crypto.HAS_RAND_BYTES {
        return {}, false
    }
    for _ in 0..<4 {
        id: uuid.Identifier
        {
            context.random_generator = crypto.random_generator()
            id = uuid.generate_v4()
        }
        if id != (uuid.Identifier{}) &&
            collections.find_collection(params.collections, id) < 0 &&
            collections.find_entry(params.collections, id) < 0 &&
            tree_projection_find(&params.ui_runtime^.library.tree.projection, id) ==
                TREE_NO_ITEM {
            return id, true
        }
    }
    return {}, false
}

// Accept one selected-root creation, then reveal its empty drawer without playback.
tree_collection_create :: proc(params: Tree_List_Params) -> bool {
    if params.general_state == nil || params.collections == nil ||
        params.ui_runtime^.layout.active_accordion_section != .Library ||
        params.ui_runtime^.library.tree.selected_item_id !=
            viewmodel.TREE_COLLECTIONS_ROOT_ID ||
        params.visibility.search != nil && params.visibility.search^.active {
        log.error("library_collection_create_without_current_owner")
        return false
    }
    id, ok := tree_collection_new_id(params)
    if !ok {
        log.error("library_collection_create_identity_failed")
        return false
    }
    name := viewmessages.shell_message(params.general_state, .Library_New_Collection)
    mutation, failure := collections.make_collection_create_mutation(
        params.collections, id, name)
    if failure != .None {
        log.errorf("library_collection_create_rejected error=%v", failure)
        return false
    }
    result := viewpreferences.settings_save_collection_mutation(
        params.general_state, mutation)
    if result != .None {
        log.errorf("library_collection_create_rejected error=%v", result)
        return false
    }
    tree_collection_reveal_created(params, id)
    return true
}

// Transfer selection and focus only after the head and replay operation are accepted.
tree_collection_reveal_created :: proc(params: Tree_List_Params, id: uuid.Identifier) {
    runtime := params.ui_runtime
    projection := &runtime^.library.tree.projection
    root := tree_projection_find(projection, viewmodel.TREE_COLLECTIONS_ROOT_ID)
    projection^.items[root].expanded = true
    runtime^.library.tree.selected_item_id = id
    runtime^.library.tree.reveal_stable_id = id
    runtime^.library.tree.reveal_pending = true
    index := tree_projection_find(projection, id)
    tree_set_active_item(runtime, projection^.items[index], true)
    tree_actions_toggle(params, id)
    if runtime^.semantic_focus != nil {
        runtime^.semantic_focus^.logical_focus = tree_actions_semantic_id(
            params, id, TREE_ACTION_TOGGLE)
        runtime^.library.actions.reveal_pending = true
    }
}
