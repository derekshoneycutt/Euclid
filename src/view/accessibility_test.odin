package view

import accessibility "../accessibility"
import testing "core:testing"
import uiaccessibility "ui/accessibility"
import viewmodel "ui/model"
import uisemantics "ui/semantics"

// Verify absent semantic relations remain absent across native projection.
@(test)
accessibility_ui_identity_preserves_empty_sentinel :: proc(t: ^testing.T) {
    testing.expect_value(t, uiaccessibility.accessibility_ui_identity({}),
        accessibility.Qualified_Identity{})
}

// Verify disclosure facts and clipped bounds survive the shared native projection.
@(test)
accessibility_favorites_disclosure_preserves_identity_relation_and_state :: proc(
    t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    placement := viewmodel.Ui_Node_Id{domain = .Animation_Tree}
    placement.stable_id[0] = 91
    toggle := viewmodel.Ui_Node_Id{
        domain = .Library_Action, local_id = 1, stable_id = placement.stable_id,
        generation = 7}
    drawer := toggle
    drawer.local_id = 4
    testing.expect(t, uisemantics.semantic_begin(semantic))
    testing.expect_value(t, uisemantics.semantic_register_control(semantic, {
        id = toggle, parent = placement, controls = drawer, role = .Button,
        states = {.Visible, .Enabled, .Focusable, .Expanded},
        actions = {.Focus, .Activate, .Expand, .Collapse},
        bounds = {10, 20, 22, 24}, clip_bounds = {12, 22, 100, 100},
        label = "Actions for Line",
    }), viewmodel.Ui_Semantic_Status.Ok)
    semantic^.logical_focus = toggle
    snapshot := uisemantics.semantic_staging_snapshot(semantic)
    record := uiaccessibility.accessibility_control_input(
        semantic, snapshot, snapshot^.nodes[0], .Button)
    testing.expect_value(t, record.identity.stable_uuid, cast([16]u8)placement.stable_id)
    testing.expect_value(t, record.identity.generation, u64(7))
    testing.expect_value(t, record.controls_identity.local_id, u64(4))
    testing.expect_value(t, record.parent_identity.owner_domain,
        u16(viewmodel.Ui_Node_Domain.Animation_Tree))
    testing.expect_value(t, record.control.label, "Actions for Line")
    testing.expect_value(t, record.control.bounds, accessibility.Bounds{12, 22, 32, 44})
    testing.expect(t, record.control.expanded && record.control.focused)
    testing.expect(t, .Expand in record.control.actions &&
        .Collapse in record.control.actions)
}

// Verify disabled move buttons retain their label but advertise no operable action.
@(test)
accessibility_favorites_disabled_move_is_not_focusable :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    testing.expect(t, uisemantics.semantic_begin(semantic))
    testing.expect_value(t, uisemantics.semantic_register_control(semantic, {
        id = {domain = .Library_Action, local_id = 2}, role = .Button,
        states = {.Visible}, bounds = {10, 20, 80, 24},
        clip_bounds = {0, 0, 200, 200}, label = "Move Up",
    }), viewmodel.Ui_Semantic_Status.Ok)
    snapshot := uisemantics.semantic_staging_snapshot(semantic)
    record := uiaccessibility.accessibility_control_record(
        semantic, snapshot, snapshot^.nodes[0], .Button)
    testing.expect_value(t, record.label, "Move Up")
    testing.expect(t, !record.enabled && !record.focusable)
    testing.expect_value(t, record.actions, accessibility.Publication_Action_Set{})
}
