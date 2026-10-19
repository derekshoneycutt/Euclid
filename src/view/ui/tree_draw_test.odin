#+test
package ui

import testing "core:testing"
import bridgemodel "../../bridge/model"
import app_core "../../core"
import geometry "../../core/geometry"
import native "../native"
import theme "theme"
import uilibrary "library"
import viewmodel "model"
import uuid "core:encoding/uuid"
import input "../input"

// Verify held feedback follows capture ownership, hover, and primary-button state.
@(test)
tree_pressed_feedback_requires_owned_hover :: proc(t: ^testing.T) {
    owner: viewmodel.Ui_Press_Owner_State
    node, other: viewmodel.Ui_Tree_Item
    node.key[0], other.key[0] = 1, 2
    node.kind, other.kind = .Animation, .Animation
    node.first_child, other.first_child = uilibrary.TREE_NO_ITEM, uilibrary.TREE_NO_ITEM
    frame := input.Input_Frame{mouse_down = {.Left}}
    testing.expect_value(t, uilibrary.tree_pressed_item(owner, frame, &node), nil)
    owner = {
        active = true, kind = .List_Item, id = uilibrary.tree_placement_press_id(&node)}
    testing.expect_value(t, uilibrary.tree_pressed_item(owner, frame, &node), &node)
    testing.expect_value(t, uilibrary.tree_pressed_item(owner, frame, &other), nil)
    testing.expect_value(t, uilibrary.tree_pressed_item(owner, frame, nil), nil)
    frame.mouse_down = {}
    testing.expect_value(t, uilibrary.tree_pressed_item(owner, frame, &node), nil)
    frame.mouse_down = {.Left}
    owner.kind = .None
    testing.expect_value(t, uilibrary.tree_pressed_item(owner, frame, &node), nil)
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
    node: viewmodel.Ui_Tree_Item
    node.key[0] = 1
    node.kind = .Animation
    node.first_child = uilibrary.TREE_NO_ITEM
    row := geometry.Rectangle{10, 20, 100, theme.TREE_ROW_HEIGHT}
    ctx := uilibrary.Encoded_Tree_Walk_Context{state = state,
        encoder = &encoder, panel = row, row_height = theme.TREE_ROW_HEIGHT,
        pressed_node = &node}
    selections := [2]bool{false, true}
    for selected in selections {
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {200, 200}, {200, 200}))
        state^.ui_runtime.library.tree.selected_item_id =
            node.key if selected else uuid.Identifier{}
        uilibrary.draw_encoded_tree_row(ctx, &node, 0, row.y)
        offset := 0
        if selected {
            offset = 4
            testing.expect_value(t,
                vertices[0].color, theme.UI_TREE_SELECTION_BACKGROUND_COLOR)
        }
        testing.expect_value(t, encoder.vertex_count, offset + 4)
        testing.expect_value(t, vertices[offset].position,
            geometry.Vector2{row.x, row.y})
        highlight := theme.UI_SELECTED_HOVER_COLOR if selected else theme.UI_HOVER_COLOR
        testing.expect_value(t, vertices[offset].color, highlight)
    }
}

// Verify selected disclosures use readable rose text independently of keyboard focus.
@(test)
tree_draw_selected_disclosure_preserves_keyboard_focus :: proc(t: ^testing.T) {
    vertices: [128]native.Draw_Vertex
    indices: [256]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    focus := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(focus, context.allocator)
    node := viewmodel.Ui_Tree_Item{first_child = 0}
    node.key[0] = 1
    state^.ui_runtime.semantic_focus = focus
    focus^.window_focused = true
    focus^.focus_origin = .Keyboard
    focus^.logical_focus = uilibrary.tree_semantic_id()
    focus^.active_tree_item = node.key
    for selected in ([2]bool{false, true}) {
        testing.expect(t, native.draw_encoder_begin(&encoder,
            {vertices[:], indices[:], batches[:], commands[:], nil},
            {200, 200}, {200, 200}))
        state^.ui_runtime.library.tree.selected_item_id =
            node.key if selected else uuid.Identifier{}
        uilibrary.draw_encoded_tree_row({
            state = state, encoder = &encoder,
            panel = {10, 20, 100, theme.TREE_ROW_HEIGHT},
            row_height = theme.TREE_ROW_HEIGHT}, &node, 0, 20, true)
        testing.expect(t, encoder.vertex_count > 16)
        tint := theme.UI_TREE_SELECTION_TEXT_COLOR if selected else theme.UI_TEXT_COLOR
        testing.expect_value(t, vertices[encoder.vertex_count - 1].color, tint)
        ring_start := 4 if selected else 0
        testing.expect_value(t, vertices[ring_start].color, theme.UI_TEXT_COLOR)
        testing.expect_value(t,
            vertices[ring_start + 8].color, theme.UI_SELECTION_TEXT_COLOR)
    }
}

// Verify prepared tree chrome balances scissors and never advances motion or retained scrolling.
@(test)
tree_draw_prepared_geometry_is_observational :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    ji: bridgemodel.Euclid_Julia_Interface
    nodes: [6]bridgemodel.Euclid_Julia_Animation_Interface
    params := tree_transition_fixture(&state^.ui_runtime, &ji, nodes[:])
    state^.julia_interface = &ji
    prepared: uilibrary.Tree_List_Preparation
    uilibrary.prepare_tree_list_panel(params, &prepared)
    nodes[0].is_expanded = false
    uilibrary.prepare_tree_list_panel(params, &prepared)
    before := state^.ui_runtime.library.motion.branches[0]
    state^.ui_runtime.library.tree.scroll_y = 400
    vertices: [256]native.Draw_Vertex
    indices: [512]u32
    batches: [64]native.Draw_Batch
    commands: [64]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {800, 800}, {800, 800}))
    uilibrary.draw_encoded_tree_geometry(state, &encoder, &prepared)
    testing.expect_value(t, encoder.scissor_count, 1)
    testing.expect_value(t, encoder.statistics.scissor_overflows, u32(0))
    testing.expect_value(t, encoder.statistics.command_overflows, u32(0))
    testing.expect_value(t, state^.ui_runtime.library.tree.scroll_y, f32(400))
    testing.expect_value(t, state^.ui_runtime.library.motion.branches[0], before)
}
