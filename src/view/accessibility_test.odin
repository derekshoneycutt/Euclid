package view

import accessibility "../accessibility"
import testing "core:testing"
import uiaccessibility "ui/accessibility"
import viewmodel "ui/model"
import uisemantics "ui/semantics"
import native_accessibility "native/accessibility"

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
    defer viewmodel.ui_semantic_focus_destroy(semantic)
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
    defer viewmodel.ui_semantic_focus_destroy(semantic)
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

// Verify committed projections exceed old limits while retaining logical offscreen items.
@(test)
accessibility_projection_uses_reusable_native_owner_workspace :: proc(t: ^testing.T) {
    semantic := new(viewmodel.Ui_Semantic_Focus_State, context.allocator)
    defer free(semantic, context.allocator)
    defer viewmodel.ui_semantic_focus_destroy(semantic)
    owner := new(native_accessibility.Adapter, context.allocator)
    defer free(owner, context.allocator)
    defer native_accessibility.adapter_close_admission(owner)
    label := make([]u8, 70000, context.allocator)
    defer delete(label, context.allocator)
    for &byte in label {
        byte = 'x'
    }
    accessibility_test_publish_large_tree(t, semantic, string(label))
    controls, ready := uiaccessibility.accessibility_project_controls(semantic, owner)
    testing.expect(t, ready)
    testing.expect_value(t, len(controls), 5001)
    testing.expect_value(t, controls[5000].control.label, string(label))
    testing.expect_value(t, controls[5000].control.position_in_set, u32(5000))
    testing.expect_value(t, controls[5000].parent_identity,
        uiaccessibility.accessibility_ui_identity(
            {domain = .Animation_Tree, local_id = 1, generation = 9}))
    testing.expect(t,
        native_accessibility.adapter_publish_controls(owner, {controls = controls}))
    native_accessibility.adapter_projection_release(owner)
    testing.expect_value(t, owner^.projection_workspace[5000].control.label, "")
    testing.expect_value(t, owner^.staged_controls[5000].label, "")
    accessibility_test_expect_workspace_reuse(t, semantic, owner)
}

// Register logical offscreen descendants with a label beyond the former text ceiling.
accessibility_test_publish_large_tree :: proc(
    t: ^testing.T, semantic: ^viewmodel.Ui_Semantic_Focus_State, label: string) {
    tree := viewmodel.Ui_Node_Id{domain = .Animation_Tree, local_id = 1, generation = 9}
    testing.expect(t, uisemantics.semantic_begin(semantic))
    testing.expect_value(t, uisemantics.semantic_register_control(semantic, {
        id = tree, role = .Tree, states = {.Visible, .Enabled},
        label = "Library", bounds = {0, 0, 200, 200},
        clip_bounds = {0, 0, 200, 200},
    }), viewmodel.Ui_Semantic_Status.Ok)
    for index in 0..<5000 {
        testing.expect_value(t, uisemantics.semantic_register_control(semantic, {
            id = {domain = .Animation_Tree, local_id = u64(index + 2), generation = 9},
            parent = tree, role = .Tree_Item, states = {.Visible, .Enabled},
            label = index == 4999 ? label : "Committed item",
            bounds = {0, f32(index * 24), 200, 24},
            clip_bounds = {0, 0, 200, 200}, level = 2,
            position_in_set = u32(index + 1), set_size = 5000,
        }), viewmodel.Ui_Semantic_Status.Ok)
    }
    testing.expect_value(t,
        uisemantics.semantic_publish(semantic), viewmodel.Ui_Semantic_Status.Ok)
}

// Unchanged native publication reuses both the projection workspace and accepted lease.
accessibility_test_expect_workspace_reuse :: proc(
    t: ^testing.T, semantic: ^viewmodel.Ui_Semantic_Focus_State,
    owner: ^native_accessibility.Adapter) {
    first_address := raw_data(owner^.projection_workspace)
    high_water := owner^.memory.peak_allocation_count
    again, second_ready :=
        uiaccessibility.accessibility_project_controls(semantic, owner)
    testing.expect(t, second_ready)
    testing.expect_value(t, raw_data(again), first_address)
    testing.expect(t,
        native_accessibility.adapter_publish_controls(owner, {controls = again}))
    testing.expect_value(t, owner^.memory.peak_allocation_count, high_water)
    native_accessibility.adapter_projection_release(owner)
}
