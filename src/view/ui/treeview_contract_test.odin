#+test
package ui

import bridgemodel "../../bridge/model"
import uilibrary "library"
import treeview "widgets/treeview"
import treeviewmodel "widgets/treeview/model"
import testing "core:testing"

// Verify catalogue UUIDs and existing semantic identities fit the independent contract.
@(test)
treeview_contract_preserves_library_item_identity :: proc(t: ^testing.T) {
    animation: bridgemodel.Euclid_Julia_Animation_Interface
    animation.stable_id[0] = 1
    semantic_id := uilibrary.tree_item_semantic_id(&animation)
    nodes := [1]treeview.Node{{
        key = animation.stable_id, semantic_id = semantic_id, capture_id = 1001,
        label = "Example", parent = treeviewmodel.NO_NODE,
        first_child = treeviewmodel.NO_NODE, next_sibling = treeviewmodel.NO_NODE,
        included = true, enabled = true, selectable = true,
    }}
    frame: treeview.Frame
    testing.expect_value(t, treeview.frame_begin(
        {nodes = nodes[:], first_root = 0}, &frame), treeview.Description_Status.Ok)
    testing.expect_value(t, frame.nodes[0].semantic_id, semantic_id)
    testing.expect_value(t, frame.nodes[0].key, animation.stable_id)
}
