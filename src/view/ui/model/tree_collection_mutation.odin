package viewmodel

import collections "../../../collections"
import storage "../../../core/storage"
import uuid "core:encoding/uuid"

// Publish admitted head topology edits through their allocation-free owner operations.
ui_tree_projection_publish_head :: proc(
    runtime: ^Euclid_Ui_Runtime_State, mutation: collections.Mutation) -> bool {
    projection := &runtime.library.tree.projection
    switch mutation.kind {
    case .Create_Collection:
        return ui_tree_projection_commit_collection(projection, mutation)
    case .Reorder_Collections:
        return ui_tree_projection_move_relative(
            projection, ui_tree_projection_find(projection, mutation.collection_id),
            ui_tree_projection_find(projection, mutation.sibling_collection_id),
            mutation.direction)
    case .Delete_Collection:
        return ui_tree_projection_delete_collection(runtime, mutation.collection_id)
    case .Add_Favorite, .Remove_Favorite, .Reorder_Siblings,
        .Set_Entry_Name, .Set_Collection_Name,
        .Add_Collection_Animation, .Remove_Collection_Animation:
    }
    return false
}

// Admit only live custom heads and reserve shared motion before accepting an order edit.
ui_tree_projection_prepare_head_edit :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation) -> collections.Mutation_Error {
    index := ui_tree_projection_find(projection, mutation.collection_id)
    if !ui_tree_projection_is_custom_head(projection, index) {
        return .Policy
    }
    if mutation.kind == .Reorder_Collections {
        sibling := ui_tree_projection_find(projection, mutation.sibling_collection_id)
        if !ui_tree_projection_is_custom_head(projection, sibling) ||
            projection.items[index].parent != projection.items[sibling].parent {
            return .Policy
        }
        if !ui_tree_projection_reserve_reorder(projection, projection.count) {
            return .Allocation_Failed
        }
    }
    return .None
}

// Identify linked custom heads beneath the permanent root, never Favorites.
ui_tree_projection_is_custom_head :: proc(
    projection: ^Ui_Tree_Projection, index: int) -> bool {
    return index != UI_TREE_NO_ITEM && projection.items[index].kind == .Collection &&
        projection.items[index].key != collections.FAVORITES_COLLECTION_ID &&
        projection.items[index].parent ==
            ui_tree_projection_find(projection, TREE_COLLECTIONS_ROOT_ID) &&
        ui_tree_projection_is_linked(projection, index)
}

// Reserve an empty custom head and its frame workspaces before accepting its data.
ui_tree_projection_prepare_collection :: proc(
    projection: ^Ui_Tree_Projection,
    mutation: collections.Mutation) -> collections.Mutation_Error {
    root := ui_tree_projection_find(projection, TREE_COLLECTIONS_ROOT_ID)
    if root == UI_TREE_NO_ITEM || mutation.collection_id == (uuid.Identifier{}) ||
        mutation.collection_id == TREE_COLLECTIONS_ROOT_ID ||
        mutation.collection_id == collections.FAVORITES_COLLECTION_ID ||
        ui_tree_projection_find(projection, mutation.collection_id) != UI_TREE_NO_ITEM {
        return .Policy
    }
    required := projection.count + 1
    if !ui_tree_projection_reserve(projection, required) ||
        !ui_tree_projection_reserve_motion(projection, required) ||
        !ui_tree_projection_reserve_prepared_rows(projection, false, required) ||
        !ui_tree_projection_reserve_prepared_rows(projection, true, required) ||
        !ui_tree_projection_reserve_traversal(projection, required) {
        return .Allocation_Failed
    }
    allocator := storage.tlsf_owner_allocator(&projection.allocator)
    node, ok := ui_tree_projection_make_node({
        key = mutation.collection_id,
        kind = .Collection,
        parent = root,
        first_child = UI_TREE_NO_ITEM,
        last_child = UI_TREE_NO_ITEM,
        next_sibling = UI_TREE_NO_ITEM,
        selectable = true,
    }, "", allocator)
    if !ok {
        return .Allocation_Failed
    }
    if !ui_tree_projection_stage_node(projection, node) {
        return .Allocation_Failed
    }
    return .None
}

// Link an admitted custom head after existing destinations without replacing nodes.
ui_tree_projection_commit_collection :: proc(
    projection: ^Ui_Tree_Projection, mutation: collections.Mutation) -> bool {
    _, ok := ui_tree_projection_commit_prepared_nodes(projection)
    if !ok {
        return false
    }
    root := ui_tree_projection_find(projection, TREE_COLLECTIONS_ROOT_ID)
    index := ui_tree_projection_find(projection, mutation.collection_id)
    if root == UI_TREE_NO_ITEM || index == UI_TREE_NO_ITEM {
        return false
    }
    parent := projection.items[root]
    if parent.last_child == UI_TREE_NO_ITEM {
        parent.first_child = index
    } else {
        projection.items[parent.last_child].next_sibling = index
    }
    parent.last_child = index
    return true
}
