package viewmodel

import uuid "core:encoding/uuid"

// Retire a custom subtree leaf-first, preserving every surviving node's address.
ui_tree_projection_delete_collection :: proc(
    runtime: ^Euclid_Ui_Runtime_State, id: uuid.Identifier) -> bool {
    projection := &runtime.library.tree.projection
    head := ui_tree_projection_find(projection, id)
    if !ui_tree_projection_is_custom_head(projection, head) {
        return false
    }
    replacement := ui_tree_collection_delete_neighbor(projection, head)
    limit := projection.count
    runtime.library.actions.reorder = {}
    for _ in 0..<limit {
        head = ui_tree_projection_find(projection, id)
        if head == UI_TREE_NO_ITEM {
            return true
        }
        leaf := head
        for _ in 0..<limit {
            child := projection.items[leaf].first_child
            if child == UI_TREE_NO_ITEM {
                break
            }
            leaf = child
        }
        ui_tree_collection_retire_identity(
            runtime, projection.items[leaf].key, replacement)
        if !ui_tree_projection_remove(projection, leaf) {
            return false
        }
    }
    return ui_tree_projection_find(projection, id) == UI_TREE_NO_ITEM
}

// Prefer the next head, previous head, then permanent Collections for repaired focus.
ui_tree_collection_delete_neighbor :: proc(
    projection: ^Ui_Tree_Projection, head: int) -> uuid.Identifier {
    item := projection.items[head]
    parent := projection.items[item.parent]
    if !parent.expanded {
        return TREE_COLLECTIONS_ROOT_ID
    }
    if item.next_sibling != UI_TREE_NO_ITEM {
        return projection.items[item.next_sibling].key
    }
    previous := UI_TREE_NO_ITEM
    for index := parent.first_child; index != UI_TREE_NO_ITEM && index != head;
        index = projection.items[index].next_sibling {
        previous = index
    }
    return projection.items[previous].key if previous != UI_TREE_NO_ITEM else
        TREE_COLLECTIONS_ROOT_ID
}

// Drop all session borrowers before node release and repair only references to this UUID.
ui_tree_collection_retire_identity :: proc(
    runtime: ^Euclid_Ui_Runtime_State, removed, replacement: uuid.Identifier) {
    if runtime.library.tree.selected_item_id == removed {
        runtime.library.tree.selected_item_id = replacement
        runtime.library.tree.reveal_stable_id = replacement
        runtime.library.tree.reveal_pending = true
    }
    if runtime.library.tree.reveal_stable_id == removed {
        runtime.library.tree.reveal_stable_id = replacement
        runtime.library.tree.reveal_pending = true
    }
    if runtime.library.entry_name.entry_id == removed {
        runtime.library.entry_name = {}
    }
    if runtime.library.actions.delete_confirmation.collection_id == removed {
        runtime.library.actions.delete_confirmation = {}
    }
    if runtime.library.actions.drawer.entry_id == removed {
        runtime.library.actions = {}
        runtime.input.press_owner = {}
    }
    semantic := runtime.semantic_focus
    if semantic == nil {
        return
    }
    if semantic.active_tree_item == removed {
        semantic.active_tree_item = replacement
    }
    if semantic.logical_focus.stable_id == removed {
        semantic.logical_focus = {domain = .Animation_Tree, local_id = 1}
        semantic.active_tree_item = replacement
        semantic.last_region = .Accordion_Content
        semantic.last_traversal_order = 3
        runtime.library.tree.reveal_stable_id = replacement
        runtime.library.tree.reveal_pending = true
    }
}
