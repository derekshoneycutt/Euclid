package uilibrary

import bridgemodel "../../../bridge/model"
import collections "../../../collections"
import storage "../../../core/storage"
import viewmodel "../model"
import uuid "core:encoding/uuid"

// Add stored custom groups and placements to a newly staged projection.
tree_projection_add_custom_entries :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    previous: ^viewmodel.Ui_Tree_Projection,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    set: ^collections.Set) -> bool {
    missing := tree_projection_custom_entry_count(projection, set)
    if !viewmodel.ui_tree_projection_reserve(projection, projection^.count + missing) ||
        !viewmodel.ui_tree_projection_reserve_order_workspace(
            projection, set^.entry_count) {
        return false
    }
    for entry in set^.entries[:set^.entry_count] {
        owner := collections.find_collection(set, entry.collection_id)
        if owner < 0 || set^.collections[owner].role != .User {
            continue
        }
        if tree_projection_find(projection, entry.id) == TREE_NO_ITEM &&
            !tree_projection_add_custom_entry(projection, previous, ji, entry) {
            return false
        }
    }
    return tree_projection_link_custom_entries(projection, set)
}

// Count only entries owned by user collections and absent from the projection.
tree_projection_custom_entry_count :: proc(
    projection: ^viewmodel.Ui_Tree_Projection, set: ^collections.Set) -> int {
    count := 0
    for entry in set^.entries[:set^.entry_count] {
        collection_index := collections.find_collection(set, entry.collection_id)
        if collection_index >= 0 && set^.collections[collection_index].role == .User &&
            tree_projection_find(projection, entry.id) == TREE_NO_ITEM {
            count += 1
        }
    }
    return count
}

// Create one detached custom node, retaining canonical target labels when available.
tree_projection_add_custom_entry :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    previous: ^viewmodel.Ui_Tree_Projection,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    entry: collections.Entry) -> bool {
    target := tree_find_stable_id(ji, entry.animation_id)
    canonical_name := target^.name if target != nil else
        string(entry.canonical_name[:entry.canonical_name_length])
    kind := viewmodel.Ui_Tree_Item_Kind.Placement if
        entry.kind == .Animation else .Group
    retained := tree_projection_find(previous, entry.id)
    expanded := retained != TREE_NO_ITEM && previous^.items[retained].expanded
    return viewmodel.ui_tree_projection_add_node(projection, {
        key = entry.id, target_animation_id = entry.animation_id,
        kind = kind, parent = TREE_NO_ITEM,
        first_child = TREE_NO_ITEM, last_child = TREE_NO_ITEM,
        next_sibling = TREE_NO_ITEM, selectable = true, expanded = expanded,
    }, canonical_name) != TREE_NO_ITEM
}

// Rebuild custom child links from the model's independent sibling orders.
tree_projection_link_custom_entries :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set,
    update_revision: bool = false) -> bool {
    for collection in set^.collections[:set^.collection_count] {
        if collection.role != .User {
            continue
        }
        head := tree_projection_find(projection, collection.id)
        if head == TREE_NO_ITEM ||
            !tree_projection_link_custom_siblings(
                projection, set, {collection_id = collection.id}, head,
                update_revision) {
            return false
        }
    }
    for entry in set^.entries[:set^.entry_count] {
        owner := collections.find_collection(set, entry.collection_id)
        if entry.kind != .Group || owner < 0 ||
            set^.collections[owner].role != .User {
            continue
        }
        parent := tree_projection_find(projection, entry.id)
        if parent == TREE_NO_ITEM ||
            !tree_projection_link_custom_siblings(
                projection, set,
                {collection_id = entry.collection_id, parent_entry_id = entry.id}, parent,
                update_revision) {
            return false
        }
    }
    return true
}

// Link one ordered sibling scope without flattening nested groups.
tree_projection_link_custom_siblings :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set,
    scope: collections.Placement_Identity,
    parent_index: int,
    update_revision: bool) -> bool {
    count := tree_projection_sort_custom_sibling_indexes(
        projection, set, scope.collection_id, scope.parent_entry_id)
    changed := tree_projection_custom_sibling_order_changed(
        projection, set, parent_index, count)
    parent := projection^.items[parent_index]
    parent^.first_child, parent^.last_child = TREE_NO_ITEM, TREE_NO_ITEM
    for ordered_index in projection^.order_workspace[:count] {
        entry := set^.entries[ordered_index]
        child := tree_projection_find(projection, entry.id)
        if child == TREE_NO_ITEM {
            return false
        }
        projection^.items[child].parent = parent_index
        projection^.items[child].next_sibling = TREE_NO_ITEM
        tree_projection_link(projection, child, parent_index)
    }
    if update_revision && changed {
        projection^.topology_revision += 1
    }
    return true
}

// Compare one current sibling chain with the model's sorted entry indexes.
tree_projection_custom_sibling_order_changed :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set,
    parent_index, count: int) -> bool {
    current := projection^.items[parent_index].first_child
    for ordered_index in projection^.order_workspace[:count] {
        expected := tree_projection_find(projection, set^.entries[ordered_index].id)
        if current != expected {
            return true
        }
        current = projection^.items[current].next_sibling
    }
    return current != TREE_NO_ITEM
}

// Sort one collection-parent scope in reusable projection storage.
tree_projection_sort_custom_sibling_indexes :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set,
    collection_id, parent_id: uuid.Identifier) -> int {
    count := 0
    for entry, index in set^.entries[:set^.entry_count] {
        if entry.collection_id == collection_id && entry.parent_entry_id == parent_id {
            projection^.order_workspace[count] = index
            count += 1
        }
    }
    for index in 1..<count {
        current := projection^.order_workspace[index]
        position := index
        for position > 0 &&
            set^.entries[projection^.order_workspace[position - 1]].sibling_order >
                set^.entries[current].sibling_order {
            projection^.order_workspace[position] =
                projection^.order_workspace[position - 1]
            position -= 1
        }
        projection^.order_workspace[position] = current
    }
    return count
}

// Reconcile custom identities locally while preserving addresses of every survivor.
tree_projection_reconcile_custom_entries :: proc(
    params: Tree_List_Params,
    projection: ^viewmodel.Ui_Tree_Projection) -> bool {
    original_count := projection^.count
    original_revision := projection^.topology_revision
    if !tree_projection_reconcile_remove_stale_custom(projection, params.collections) ||
        !tree_projection_reconcile_add_custom(params, projection) {
        return false
    }
    if !tree_projection_link_custom_entries(
        projection, params.collections, true) {
        return false
    }
    if projection^.count != original_count &&
        projection^.topology_revision == original_revision {
        projection^.topology_revision += 1
    }
    return true
}

// Remove stale custom leaves before their missing groups and collection heads.
tree_projection_reconcile_remove_stale_custom :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set) -> bool {
    limit := projection^.count
    for _ in 0..<limit {
        removed := false
        for index := projection^.count - 1; index >= 0; index -= 1 {
            item := projection^.items[index]
            if !tree_projection_custom_node_is_stale(projection, set, index) ||
                item^.first_child != TREE_NO_ITEM {
                continue
            }
            if !viewmodel.ui_tree_projection_remove(projection, index) {
                return false
            }
            removed = true
            break
        }
        if !removed {
            return true
        }
    }
    return true
}

// Check whether one custom node or any owning custom ancestor disappeared.
tree_projection_custom_node_is_stale :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    set: ^collections.Set,
    index: int) -> bool {
    item := projection^.items[index]
    if item^.kind != .Collection && item^.kind != .Group &&
        item^.kind != .Placement {
        return false
    }
    head := index
    for _ in 0..<projection^.count {
        current := projection^.items[head]
        if current^.kind == .Collection {
            break
        }
        if current^.parent == TREE_NO_ITEM {
            return false
        }
        head = current^.parent
    }
    owner := projection^.items[head]
    if owner^.kind != .Collection || owner^.key == collections.FAVORITES_COLLECTION_ID {
        return false
    }
    if item^.kind == .Collection {
        collection_index := collections.find_collection(set, item^.key)
        return collection_index < 0 ||
            set^.collections[collection_index].role != .User
    }
    entry_index := collections.find_entry(set, item^.key)
    return entry_index < 0 ||
        set^.entries[entry_index].collection_id != owner^.key
}

// Stage missing custom entries before appending them to the accepted projection.
tree_projection_reconcile_add_custom :: proc(
    params: Tree_List_Params,
    projection: ^viewmodel.Ui_Tree_Projection) -> bool {
    missing := tree_projection_custom_entry_count(projection, params.collections)
    if missing == 0 {
        return true
    }
    if !viewmodel.ui_tree_projection_reserve(
        projection, projection^.count + missing) ||
        !viewmodel.ui_tree_projection_reserve_order_workspace(
            projection, params.collections^.entry_count) {
        return false
    }
    allocator := storage.tlsf_owner_allocator(&projection^.allocator)
    nodes := make([]^viewmodel.Ui_Tree_Item, missing, allocator)
    if len(nodes) != missing {
        return false
    }
    return tree_projection_reconcile_stage_custom(params, projection, nodes)
}

// Fill a detached batch and publish it only after identity validation succeeds.
tree_projection_reconcile_stage_custom :: proc(
    params: Tree_List_Params,
    projection: ^viewmodel.Ui_Tree_Projection,
    nodes: []^viewmodel.Ui_Tree_Item) -> bool {
    count := 0
    for entry in params.collections^.entries[:params.collections^.entry_count] {
        owner := collections.find_collection(params.collections, entry.collection_id)
        if owner < 0 || params.collections^.collections[owner].role != .User ||
            tree_projection_find(projection, entry.id) != TREE_NO_ITEM {
            continue
        }
        if !tree_projection_stage_custom_entry(
            projection, params.ji, entry, nodes, &count) {
            tree_projection_reconcile_free_nodes(projection, nodes, count)
            return false
        }
    }
    if !tree_projection_reconcile_nodes_are_unique(projection, nodes, count) ||
        !tree_projection_reconcile_commit_nodes(projection, nodes, count) {
        tree_projection_reconcile_free_nodes(projection, nodes, count)
        return false
    }
    delete(nodes, storage.tlsf_owner_allocator(&projection^.allocator))
    return true
}

// Create and retain one detached custom entry in the reconciliation batch.
tree_projection_stage_custom_entry :: proc(
    projection: ^viewmodel.Ui_Tree_Projection,
    ji: ^bridgemodel.Euclid_Julia_Interface,
    entry: collections.Entry,
    nodes: []^viewmodel.Ui_Tree_Item,
    count: ^int) -> bool {
    target := tree_find_stable_id(ji, entry.animation_id)
    canonical_name := target^.name if target != nil else
        string(entry.canonical_name[:entry.canonical_name_length])
    kind := viewmodel.Ui_Tree_Item_Kind.Placement if
        entry.kind == .Animation else .Group
    allocator := storage.tlsf_owner_allocator(&projection^.allocator)
    node, ok := viewmodel.ui_tree_projection_make_node({
        key = entry.id, target_animation_id = entry.animation_id,
        kind = kind, parent = TREE_NO_ITEM,
        first_child = TREE_NO_ITEM, last_child = TREE_NO_ITEM,
        next_sibling = TREE_NO_ITEM, selectable = true,
    }, canonical_name, allocator)
    if !ok {
        return false
    }
    nodes[count^] = node
    count^ += 1
    return true
}
