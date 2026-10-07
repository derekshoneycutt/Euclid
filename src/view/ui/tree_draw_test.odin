#+test
package ui

import "core:testing"
import bridgemodel "../../bridge/model"
import app_core "../../core"
import geometry "../../core/geometry"
import "../native"

// Verify held feedback follows capture ownership, hover, and primary-button state.
@(test)
tree_pressed_feedback_requires_owned_hover :: proc(t: ^testing.T) {
    runtime := make_baseline_ui_runtime()
    node, other: bridgemodel.Euclid_Julia_Animation_Interface
    params := Tree_List_Params{ui_runtime = &runtime,
        mouse_input = {mouse_down = {.Left}}}
    testing.expect_value(t, tree_pressed_node(params, &node), nil)
    runtime.ui_press_owner = {
        active = true, kind = .List_Item, id = tree_node_press_id(&node)}
    testing.expect_value(t, tree_pressed_node(params, &node), &node)
    testing.expect_value(t, tree_pressed_node(params, &other), nil)
    testing.expect_value(t, tree_pressed_node(params, nil), nil)
    params.mouse_input.mouse_down = {}
    testing.expect_value(t, tree_pressed_node(params, &node), nil)
    params.mouse_input.mouse_down = {.Left}
    runtime.ui_press_owner.kind = .None
    testing.expect_value(t, tree_pressed_node(params, &node), nil)
}

// Verify pressed rows receive a subtle overlay without changing selection chrome.
@(test)
tree_draw_encodes_pressed_row_overlay :: proc(t: ^testing.T) {
    vertices: [8]native.Draw_Vertex
    indices: [12]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    node: bridgemodel.Euclid_Julia_Animation_Interface
    row := geometry.Rectangle{10, 20, 100, TREE_ROW_HEIGHT}
    ctx := Encoded_Tree_Walk_Context{state = state,
        encoder = &encoder, panel = row, pressed_node = &node}
    selections := [2]bool{false, true}
    for selected in selections {
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {200, 200}, {200, 200}))
        node.is_selected = selected
        draw_encoded_tree_row(ctx, &node, 0, row.y)
        offset := 0
        if selected {
            offset = 4
            testing.expect_value(t, vertices[0].color, UI_BORDER_COLOR)
        }
        testing.expect_value(t, encoder.vertex_count, offset + 4)
        testing.expect_value(t, vertices[offset].position,
            geometry.Vector2{row.x, row.y})
        highlight := UI_TEXT_COLOR
        highlight.a = 24
        testing.expect_value(t, vertices[offset].color, highlight)
    }
}
