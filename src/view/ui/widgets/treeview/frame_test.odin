#+test
package treeview

import model "model"
import testing "core:testing"

// test_nested_nodes supplies a synthetic folder, child, and independent root.
test_nested_nodes :: proc() -> [3]Node {
    result := [3]Node{test_node(0), test_node(1), test_node(2)}
    result[0].first_child = 1
    result[0].next_sibling = 2
    result[0].selectable = false
    result[1].parent = 0
    return result
}

// Verify working effects remain ordered without mutating authoritative caller facts.
@(test)
frame_preserves_order_and_borrows_only_labels :: proc(t: ^testing.T) {
    nodes := test_nested_nodes()
    frame: Frame
    testing.expect_value(t, frame_begin({nodes = nodes[:], first_root = 0}, &frame),
        Description_Status.Ok)
    testing.expect_value(t, frame_issue(&frame,
        {kind = .Set_Expanded, key = nodes[0].key, expanded = true}), Intent_Status.Ok)
    rows := logical_rows(frame_description(&frame))
    testing.expect_value(t, rows.count, 3)
    testing.expect_value(t, rows.indices[1], 1)
    selections := [2]int{1, 2}
    for index in selections {
        testing.expect_value(t, frame_issue(&frame,
            {kind = .Select, key = nodes[index].key}), Intent_Status.Ok)
    }
    testing.expect_value(t, frame.intent_count, 3)
    testing.expect_value(t, frame.intents[1].key, nodes[1].key)
    testing.expect_value(t, frame.intents[2].key, nodes[2].key)
    testing.expect(t, frame.nodes[2].selected && !frame.nodes[1].selected)
    testing.expect(t, !nodes[0].expanded && !nodes[1].selected && !nodes[2].selected)
    nodes[2].key = {}
    testing.expect_value(t, frame.nodes[2].key, frame.intents[2].key)
}

// Verify exact intent capacity admits every slot and rejects without partial mutation.
@(test)
frame_intent_overflow_is_transactional :: proc(t: ^testing.T) {
    nodes := test_nested_nodes()
    frame: Frame
    testing.expect_value(t, frame_begin({nodes = nodes[:], first_root = 0}, &frame),
        Description_Status.Ok)
    for index in 0..<INTENT_CAPACITY {
        testing.expect_value(t, frame_issue(&frame,
            {kind = .Select, key = nodes[1 + index % 2].key}), Intent_Status.Ok)
    }
    selected := frame.nodes[1].selected
    testing.expect_value(t, frame_issue(&frame,
        {kind = .Select, key = nodes[1].key}), Intent_Status.Capacity_Exceeded)
    testing.expect_value(t, frame.intent_count, INTENT_CAPACITY)
    testing.expect_value(t, frame.nodes[1].selected, selected)
}

// Verify rejected capability and admission leave the working frame unchanged.
@(test)
frame_rejection_preserves_working_facts :: proc(t: ^testing.T) {
    nodes := test_nested_nodes()
    frame: Frame
    testing.expect_value(t, frame_begin({nodes = nodes[:], first_root = 0}, &frame),
        Description_Status.Ok)
    testing.expect_value(t, frame_issue(&frame,
        {kind = .Select, key = nodes[0].key}), Intent_Status.Unsupported_Action)
    testing.expect_value(t, frame_issue(&frame,
        {kind = .Set_Expanded, key = nodes[1].key}), Intent_Status.Unsupported_Action)
    testing.expect_value(t, frame_issue(&frame, {kind = .Select}),
        Intent_Status.Unknown_Item)
    frame.nodes[1].enabled = false
    testing.expect_value(t, frame_issue(&frame,
        {kind = .Select, key = nodes[1].key}), Intent_Status.Disabled_Item)
    nodes[1].parent = model.NO_NODE
    testing.expect_value(t, frame_begin({nodes = nodes[:], first_root = 0}, &frame),
        Description_Status.Invalid_Topology)
    testing.expect_value(t, frame.nodes[1].parent, 0)
    testing.expect_value(t, frame.intent_count, 0)
}

// Verify independent widget instances keep active and reveal identities isolated.
@(test)
tree_instances_keep_independent_roving_state :: proc(t: ^testing.T) {
    nodes := test_nested_nodes()
    description := Description{nodes = nodes[:], first_root = 0}
    first, second: model.State
    set_active(&first, nodes[2], true)
    set_active(&second, nodes[0], false)
    testing.expect_value(t, resolve_active(description, &first), 2)
    testing.expect_value(t, resolve_active(description, &second), 0)
    testing.expect(t, first.reveal_pending && !second.reveal_pending)
    nodes[0].included = false
    testing.expect_value(t, resolve_active(description, &second), 2)
    testing.expect_value(t, second.active_key, nodes[0].key)
}

// Verify forced expansion does not become stored user expansion on collapse.
@(test)
logical_rows_respect_forced_expansion_and_inclusion :: proc(t: ^testing.T) {
    nodes := test_nested_nodes()
    description := Description{nodes = nodes[:], first_root = 0}
    rows := logical_rows(description)
    testing.expect_value(t, rows.count, 2)
    nodes[0].forced_expanded = true
    rows = logical_rows(description)
    testing.expect_value(t, rows.count, 3)
    testing.expect(t, !nodes[0].expanded)
    nodes[1].included = false
    rows = logical_rows(description)
    testing.expect_value(t, rows.count, 2)
    testing.expect_value(t, rows.indices[1], 2)
}
