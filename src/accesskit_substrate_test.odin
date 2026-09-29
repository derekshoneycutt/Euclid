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