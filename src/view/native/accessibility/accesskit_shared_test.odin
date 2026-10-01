#+test
package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"

import "core:math"
import "core:testing"

Accesskit_Shared_Text_Fixture :: struct {
    owner_id: u64,
    text_run_id: u64,
    ok: bool,
}

// accesskit_shared_text_fixture publishes one editable owner and TextRun child.
accesskit_shared_text_fixture :: proc(owner: ^Adapter) -> Accesskit_Shared_Text_Fixture {
    owner_identity := portable.Qualified_Identity{
        domain = .Ui, owner_domain = 7, local_id = 6401}
    text_identity := portable.Qualified_Identity{
        domain = .Ui, owner_domain = 7, local_id = 6410}
    controls := [2]Adapter_Control_Input{
        {identity = owner_identity, control = {
            role = .Search_Input, bounds = {10, 10, 220, 40}, value = "aβc",
            actions = {.Replace_Selected_Text, .Set_Text_Selection},
            enabled = true, focusable = true, text_present = true,
            text_cursor_byte = 4, text_anchor_byte = 4}},
        {identity = text_identity, parent_identity = owner_identity, control = {
            role = .Text_Run, bounds = {14, 14, 216, 36}, value = "aβc",
            enabled = true, text_present = true}},
    }
    ok := adapter_publish_controls(owner, {
        root_bounds = {0, 0, 800, 600}, controls = controls[:]})
    return {owner^.control_native_ids[0], owner^.control_native_ids[1], ok}
}

// accesskit_shared_builds_complete_static_tree verifies static translation.
@(test)
accesskit_shared_builds_complete_static_tree :: proc(t: ^testing.T) {
    publication: portable.Static_Publication
    testing.expect_value(t,
        portable.publication_build(&publication, 800, 600, true),
        portable.Publication_Status.Ok)
    update := accesskit_tree_update(&publication)
    testing.expect(t, update != nil)
    if update != nil {
       accesskit.accesskit_tree_update_free(update)
    }
}

// accesskit_shared_scales_logical_bounds verifies the physical-pixel contract.
@(test)
accesskit_shared_scales_logical_bounds :: proc(t: ^testing.T) {
    bounds := accesskit_physical_bounds({10, 20, 110, 60}, 2)
    testing.expect_value(t, bounds.x0, f64(20))
    testing.expect_value(t, bounds.y0, f64(40))
    testing.expect_value(t, bounds.x1, f64(220))
    testing.expect_value(t, bounds.y1, f64(120))
}

// accesskit_shared_builds_mixed_control_tree verifies Phase 2 control translation.
@(test)
accesskit_shared_builds_mixed_control_tree :: proc(t: ^testing.T) {
    controls := [6]portable.Control_Publication_Input{
        {native_id = 2, role = .Button, bounds = {10, 10, 50, 34},
            label = "Restart animation", actions = {.Focus, .Activate},
            enabled = true, focusable = true, focused = true},
        {native_id = 3, role = .Checkbox, bounds = {10, 40, 160, 64},
            label = "Limit frame rate", actions = {.Focus, .Toggle},
            enabled = true, focusable = true, checked = true},
        {native_id = 4, role = .Slider, bounds = {10, 70, 180, 94},
            label = "Maximum dust", value = "50000",
            actions = {.Focus, .Increment, .Decrement},
            range = {0, 100000, 50000, 1000, false, true},
            enabled = true, focusable = true},
        {native_id = 5, controls_native_id = 6, role = .Accordion_Header,
            bounds = {200, 10, 360, 34}, label = "Save GIF",
            actions = {.Focus, .Activate}, enabled = true, focusable = true,
            expanded = true},
        {native_id = 6, role = .Panel, bounds = {200, 40, 360, 120},
            label = "GIF capture settings", enabled = true},
        {native_id = 7, parent_native_id = 6, role = .Status,
            bounds = {210, 80, 350, 104}, label = "GIF capture saving",
            enabled = true, busy = true},
    }
    publication: portable.Control_Tree_Publication
    testing.expect_value(t, portable.control_tree_build(&publication, {
        root_bounds = {0, 0, 800, 600}, window_focused = true,
        controls = controls[:],
    }), portable.Publication_Status.Ok)
    update := accesskit_control_tree_update(&publication)
    testing.expect(t, update != nil)
    if update != nil {
       accesskit.accesskit_tree_update_free(update)
    }
}

// accesskit_shared_builds_search_tree_hierarchy verifies nested translation.
@(test)
accesskit_shared_builds_search_tree_hierarchy :: proc(t: ^testing.T) {
    controls := [4]portable.Control_Publication_Input{
        {native_id = 2, role = .Search_Input, bounds = {10, 10, 220, 40},
            label = "Search animations", enabled = true, focusable = true},
        {native_id = 3, role = .Tree, bounds = {10, 48, 280, 400},
            label = "Animation library", active_descendant_native_id = 5,
            enabled = true, focusable = true},
        {native_id = 4, parent_native_id = 3, role = .Tree_Item,
            bounds = {10, 48, 280, 72}, label = "Elements", enabled = true},
        {native_id = 5, parent_native_id = 4, role = .Tree_Item,
            bounds = {26, 72, 280, 96}, label = "Proposition I",
            enabled = true, selected = true},
    }
    publication: portable.Control_Tree_Publication
    testing.expect_value(t, portable.control_tree_build(&publication, {
        root_bounds = {0, 0, 800, 600}, controls = controls[:],
    }), portable.Publication_Status.Ok)
    update := accesskit_control_tree_update(&publication)
    testing.expect(t, update != nil)
    if update != nil {
       accesskit.accesskit_tree_update_free(update)
    }
}

// accesskit_shared_tree_scroll_supports_set_value verifies composite AX ranges.
@(test)
accesskit_shared_tree_scroll_supports_set_value :: proc(t: ^testing.T) {
    node := accesskit.accesskit_node_new(.Tree)
    testing.expect(t, node != nil)
    if node == nil {
       return
    }
    defer accesskit.accesskit_node_free(node)
    accesskit_configure_control_actions(node, {.Scroll})
    testing.expect(t, accesskit.accesskit_node_supports_action(node, .Scroll_Up))
    testing.expect(t, accesskit.accesskit_node_supports_action(node, .Scroll_Down))
    testing.expect(t, accesskit.accesskit_node_supports_action(node, .Set_Value))
}

// accesskit_shared_resolves_hierarchy_and_retires_ids verifies ID ownership.
@(test)
accesskit_shared_resolves_hierarchy_and_retires_ids :: proc(t: ^testing.T) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    defer adapter_close_admission(owner)
    tree_identity := portable.Qualified_Identity{
        domain = .Ui, owner_domain = 8, local_id = 1}
    item_identity := portable.Qualified_Identity{
        domain = .Ui, owner_domain = 8, local_id = 2}
    controls := [2]Adapter_Control_Input{
        {identity = tree_identity, active_descendant_identity = item_identity,
            control = {role = .Tree, bounds = {10, 10, 280, 400},
                label = "Animation library", enabled = true, focusable = true}},
        {identity = item_identity, parent_identity = tree_identity,
            control = {role = .Tree_Item, bounds = {10, 10, 280, 34},
                label = "Elements", enabled = true}},
    }
    input := Adapter_Tree_Input{
        root_bounds = {0, 0, 800, 600}, controls = controls[:],
    }
    testing.expect(t, adapter_publish_controls(owner, input))
    publication := &owner^.control_publication.current
    retired_id := publication^.controls[1].native_id
    testing.expect_value(t, publication^.controls[1].parent_native_id,
        publication^.controls[0].native_id)
    testing.expect_value(t, publication^.controls[0].active_descendant_native_id,
        publication^.controls[1].native_id)
    controls[0].active_descendant_identity = {}
    input.controls = controls[:1]
    testing.expect(t, adapter_publish_controls(owner, input))
    _, found := portable.native_id_lookup(&owner^.native_ids, retired_id)
    testing.expect(t, !found)
}

// accesskit_shared_validates_numeric_actions verifies finite range validation.
@(test)
accesskit_shared_validates_numeric_actions :: proc(t: ^testing.T) {
    control := portable.Control_Publication{
        role = .Slider, enabled = true, actions = {.Set_Value},
        range = {0, 100, 25, 1, false, true},
    }
    request := portable.Queued_Action{numeric_value = 42, has_numeric_value = true}
    action: Adapter_Action
    testing.expect_value(t,
        adapter_validate_numeric_action(&control, request, &action),
        Adapter_Action_Status.Ok)
    testing.expect_value(t, action.numeric_value, f64(42))
    request.numeric_value = 101
    testing.expect_value(t,
        adapter_validate_numeric_action(&control, request, &action),
        Adapter_Action_Status.Invalid_Value)
    request.numeric_value = math.nan_f64()
    testing.expect_value(t,
        adapter_validate_numeric_action(&control, request, &action),
        Adapter_Action_Status.Invalid_Value)
    request.numeric_value = math.inf_f64(1)
    testing.expect_value(t,
        adapter_validate_numeric_action(&control, request, &action),
        Adapter_Action_Status.Invalid_Value)
}

// accesskit_shared_routes_text_actions verifies bounded UTF-8 and selection data.
@(test)
accesskit_shared_routes_text_actions :: proc(t: ^testing.T) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    defer adapter_close_admission(owner)
    fixture := accesskit_shared_text_fixture(owner)
    testing.expect(t, fixture.ok)
    replacement := "界"
    request := accesskit.Action_Request{action = .Replace_Selected_Text,
        target_node = accesskit.Node_Id(fixture.owner_id), data = {has_value = true,
            value = {tag = .Value}}}
    request.data.value.payload.value = cast(cstring)raw_data(replacement)
    testing.expect_value(t, accesskit_copy_action_request(owner, &request),
        portable.Action_Queue_Status.Ok)
    action: Adapter_Action
    testing.expect_value(t, adapter_drain_action(owner, &action),
        Adapter_Action_Status.Ok)
    testing.expect_value(t, action.kind, Adapter_Action_Kind.Replace_Selected_Text)
    testing.expect_value(t,
        string(action.payload[:action.payload_length]), replacement)

    request.action = .Set_Text_Selection
    request.data.value.tag = .Set_Text_Selection
    request.data.value.payload.set_text_selection = {
        anchor = {accesskit.Node_Id(fixture.text_run_id), 1},
        focus = {accesskit.Node_Id(fixture.text_run_id), 2}}
    testing.expect_value(t, accesskit_copy_action_request(owner, &request),
        portable.Action_Queue_Status.Ok)
    testing.expect_value(t, adapter_drain_action(owner, &action),
        Adapter_Action_Status.Ok)
    testing.expect_value(t, action.kind, Adapter_Action_Kind.Set_Text_Selection)
    testing.expect_value(t, action.selection_anchor, u16(1))
    testing.expect_value(t, action.selection_focus, u16(2))
    request.data.value.payload.set_text_selection.focus.node =
        accesskit.Node_Id(fixture.owner_id)
    testing.expect_value(t, accesskit_copy_action_request(owner, &request),
        portable.Action_Queue_Status.Invalid_Target)
}

// accesskit_shared_rejects_invalid_text verifies malformed UTF-8 rejection.
@(test)
accesskit_shared_rejects_invalid_text :: proc(t: ^testing.T) {
    control := portable.Control_Publication{
        actions = {.Replace_Selected_Text}, enabled = true}
    request := portable.Queued_Action{payload_length = 1}
    request.payload[0] = 0xff
    action: Adapter_Action
    testing.expect_value(t,
        adapter_validate_text_action(&control, request, &action),
        Adapter_Action_Status.Invalid_Value)
}

// accesskit_shared_validates_action_state verifies stale and unavailable actions.
@(test)
accesskit_shared_validates_action_state :: proc(t: ^testing.T) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    defer adapter_close_admission(owner)
    identity := portable.Qualified_Identity{
        domain = .Ui, local_id = 2101, generation = 4}
    input := portable.Button_Publication_Input{
        present = true, root_bounds = {0, 0, 800, 600},
        child_bounds = {16, 520, 48, 552}, label = "Restart animation",
        child_enabled = true, child_focusable = true,
        child_supports_focus = true, child_supports_activate = true,
    }
    testing.expect(t, adapter_publish_button(owner, input, identity))
    publication := owner^.publication.current
    request := portable.Queued_Action{kind = u16(accesskit.Action.Click),
        target_native_id = owner^.child_native_id,
        publication_generation = publication.generation - 1}
    action: Adapter_Action
    testing.expect_value(t,
        adapter_validate_action(owner, request, publication, &action),
        Adapter_Action_Status.Stale_Generation)
    request.publication_generation = publication.generation
    request.kind = u16(accesskit.Action.Expand)
    testing.expect_value(t,
        adapter_validate_action(owner, request, publication, &action),
        Adapter_Action_Status.Unsupported_Action)
    publication.child_enabled = false
    request.kind = u16(accesskit.Action.Click)
    testing.expect_value(t,
        adapter_validate_action(owner, request, publication, &action),
        Adapter_Action_Status.Disabled_Target)
    request.target_native_id += 1000
    testing.expect_value(t,
        adapter_validate_action(owner, request, publication, &action),
        Adapter_Action_Status.Unknown_Target)
}

// accesskit_shared_copies_bounded_request verifies copied callback ingress.
@(test)
accesskit_shared_copies_bounded_request :: proc(t: ^testing.T) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    defer adapter_close_admission(owner)
    testing.expect_value(t, portable.publication_build_button(
        &owner^.publication.current, {
            present = true, child_id = 2, root_bounds = {0, 0, 800, 600},
            child_bounds = {16, 520, 48, 552}, label = "Restart animation",
            window_focused = true, child_enabled = true,
        }), portable.Publication_Status.Ok)
    request := accesskit.Action_Request{
        action = .Click, target_node = accesskit.Node_Id(2),
    }
    testing.expect_value(t, accesskit_copy_action_request(owner, &request),
        portable.Action_Queue_Status.Ok)
    copied: portable.Queued_Action
    testing.expect(t, portable.action_queue_pop(&owner^.actions, &copied))
    testing.expect_value(t, copied.kind, u16(accesskit.Action.Click))
    testing.expect_value(t, copied.target_native_id, u64(2))
    testing.expect_value(t, copied.publication_generation, u64(1))
}

// accesskit_shared_rejects_late_activation verifies closed callback admission.
@(test)
accesskit_shared_rejects_late_activation :: proc(t: ^testing.T) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    testing.expect_value(t,
        portable.protected_publish(&owner^.publication, 800, 600, true),
        portable.Publication_Status.Ok)
    adapter_close_admission(owner)
    testing.expect(t, accesskit_activation_callback(owner) == nil)
    diagnostics := adapter_diagnostics_snapshot(owner)
    testing.expect_value(t, diagnostics.activations, u64(1))
    testing.expect_value(t, diagnostics.rejected_callbacks, u64(1))
}

// accesskit_shared_records_typed_macos_failures verifies typed diagnostics.
@(test)
accesskit_shared_records_typed_macos_failures :: proc(t: ^testing.T) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    adapter_record_macos_failure(owner, .Cocoa_Property_Lookup)
    adapter_record_macos_failure(owner, .Queued_Event_Raise)
    diagnostics := adapter_macos_failures_snapshot(owner)
    testing.expect_value(t, diagnostics.count, u64(2))
    testing.expect_value(t, diagnostics.last_stage,
        Macos_Failure_Stage.Queued_Event_Raise)
}