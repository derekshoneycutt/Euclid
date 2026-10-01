#+test
package main

import accesskit "../libs/accesskit"

import "core:testing"

// Verify the Odin declarations match the tagged AccessKit C ABI layouts.
@(test)
accesskit_substrate_matches_tagged_abi :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(accesskit.Action), 1)
    testing.expect_value(t, size_of(accesskit.Role), 1)
    testing.expect_value(t, size_of(accesskit.Tree_Id), 16)
    testing.expect_value(t, size_of(accesskit.Rect), 32)
    testing.expect_value(t, size_of(accesskit.Text_Position), 16)
    testing.expect_value(t, size_of(accesskit.Action_Data), 40)
    testing.expect_value(t, size_of(accesskit.Action_Request), 80)
}

// Verify the pinned shared library can create, query, and free owned storage.
@(test)
accesskit_substrate_calls_pinned_library :: proc(t: ^testing.T) {
    node := accesskit.accesskit_node_new(.Button)
    testing.expect(t, node != nil)
    testing.expect_value(t,
        accesskit.accesskit_node_role(node), accesskit.Role.Button)
    accesskit.accesskit_node_free(node)

    rect := accesskit.accesskit_rect_new(1, 2, 3, 4)
    testing.expect_value(t, rect, accesskit.Rect{1, 2, 3, 4})
}

// Verify a complete static root and child transfer ownership into one tree update.
@(test)
accesskit_substrate_builds_static_tree_update :: proc(t: ^testing.T) {
    root_id := accesskit.Node_Id(1)
    child_id := accesskit.Node_Id(2)
    root := accesskit.accesskit_node_new(.Unknown)
    child := accesskit.accesskit_node_new(.Label)
    testing.expect(t, root != nil && child != nil)
    if root == nil || child == nil {
        return
    }
    accesskit.accesskit_node_set_children(root, 1, &child_id)
    accesskit.accesskit_node_set_value_with_length(child, "Euclid", 6)
    accesskit.accesskit_node_set_bounds(child, {0, 0, 100, 40})
    update := accesskit.accesskit_tree_update_with_capacity_and_focus(2, root_id)
    testing.expect(t, update != nil)
    if update == nil {
        accesskit.accesskit_node_free(root)
        accesskit.accesskit_node_free(child)
        return
    }
    accesskit.accesskit_tree_update_push_node(update, root_id, root)
    accesskit.accesskit_tree_update_push_node(update, child_id, child)
    accesskit.accesskit_tree_update_set_tree_id(update, {})
    accesskit.accesskit_tree_update_free(update)
}