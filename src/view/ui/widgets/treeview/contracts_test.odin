#+test
package treeview

import model "model"
import testing "core:testing"

// test_node constructs application-independent identities and sentinel-only topology.
test_node :: proc(index: int) -> Node {
    key: model.Item_Key
    key[0] = u8(index + 1)
    key[1] = u8((index + 1) >> 8)
    return {
        key = key, semantic_id = {domain = .Application, local_id = u64(index + 1)},
        capture_id = index + 1, label = "Item",
        parent = model.NO_NODE, first_child = model.NO_NODE,
        next_sibling = model.NO_NODE, included = true, enabled = true, selectable = true,
    }
}

// Verify empty and full-capacity synthetic trees are admitted without allocation.
@(test)
description_admits_bounded_forests :: proc(t: ^testing.T) {
    testing.expect_value(t, description_status({first_root = model.NO_NODE}),
        Description_Status.Ok)
    nodes: [model.NODE_CAPACITY]Node
    for index in 0..<len(nodes) {
        nodes[index] = test_node(index)
        if index + 1 < len(nodes) {
            nodes[index].next_sibling = index + 1
        }
    }
    testing.expect_value(t, description_status({nodes = nodes[:], first_root = 0}),
        Description_Status.Ok)
    testing.expect_value(t, nodes[len(nodes) - 1].next_sibling, model.NO_NODE)
}

// Verify admission rejects out-of-range links, cycles, and unreachable nodes.
@(test)
description_rejects_invalid_topology :: proc(t: ^testing.T) {
    nodes := [2]Node{test_node(0), test_node(1)}
    description := Description{nodes = nodes[:], first_root = 0}
    testing.expect_value(t, description_status(description),
        Description_Status.Invalid_Topology)
    nodes[0].next_sibling = 2
    testing.expect_value(t, description_status(description),
        Description_Status.Invalid_Index)
    nodes[0].next_sibling = 1
    nodes[1].next_sibling = 0
    testing.expect_value(t, description_status(description),
        Description_Status.Invalid_Topology)
    nodes[1].next_sibling = model.NO_NODE
    nodes[1].parent = 0
    testing.expect_value(t, description_status(description),
        Description_Status.Invalid_Topology)
    nodes[0].next_sibling = model.NO_NODE
    nodes[0].first_child = 1
    testing.expect_value(t, description_status(description), Description_Status.Ok)
}

// Verify all identity surfaces reject aliases before input or semantic publication.
@(test)
description_rejects_identity_aliases :: proc(t: ^testing.T) {
    nodes := [2]Node{test_node(0), test_node(1)}
    nodes[0].next_sibling = 1
    description := Description{nodes = nodes[:], first_root = 0}
    nodes[1].key = nodes[0].key
    testing.expect_value(t, description_status(description),
        Description_Status.Duplicate_Identity)
    nodes[1] = test_node(1)
    nodes[1].semantic_id = nodes[0].semantic_id
    testing.expect_value(t, description_status(description),
        Description_Status.Duplicate_Identity)
    nodes[1] = test_node(1)
    nodes[1].capture_id = nodes[0].capture_id
    testing.expect_value(t, description_status(description),
        Description_Status.Duplicate_Identity)
    nodes[1] = test_node(1)
    nodes[1].key = {}
    testing.expect_value(t, description_status(description),
        Description_Status.Invalid_Identity)
}

// Verify the capacity boundary rejects excess storage rather than truncating topology.
@(test)
description_rejects_capacity_overflow :: proc(t: ^testing.T) {
    nodes: [model.NODE_CAPACITY + 1]Node
    testing.expect_value(t, description_status({nodes = nodes[:], first_root = 0}),
        Description_Status.Capacity_Exceeded)
}
