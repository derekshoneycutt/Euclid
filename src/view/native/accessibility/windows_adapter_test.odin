package native_accessibility

import accesskit "../../../../libs/accesskit"
import portable "../../../accessibility"
import "core:testing"

Windows_Test_Fixture :: struct {
    create_succeeds: bool,
    events_present: bool,
    activation_complete: bool,
    closed_before_free: bool,
    creates: int,
    updates: int,
    raises: int,
    frees: int,
    owner: ^Adapter,
}

// windows_test_create simulates constructor activation and native admission.
windows_test_create :: proc(user_data, _: rawptr, owner: ^Adapter) -> rawptr {
    fixture := cast(^Windows_Test_Fixture)user_data
    fixture^.creates += 1
    fixture^.owner = owner
    update := accesskit_activation_callback(owner)
    fixture^.activation_complete = update != nil
    if update != nil {accesskit.accesskit_tree_update_free(update)}
    if fixture^.create_succeeds {return user_data}
    return nil
}

// windows_test_update records one changed-generation native update.
windows_test_update :: proc(user_data, _: rawptr, _: ^Adapter) -> rawptr {
    fixture := cast(^Windows_Test_Fixture)user_data
    fixture^.updates += 1
    return user_data if fixture^.events_present else nil
}

// windows_test_raise consumes one simulated transferred event object.
windows_test_raise :: proc(user_data, _: rawptr) {
    fixture := cast(^Windows_Test_Fixture)user_data
    fixture^.raises += 1
}

// windows_test_free verifies callback closure before native release.
windows_test_free :: proc(user_data, _: rawptr) {
    fixture := cast(^Windows_Test_Fixture)user_data
    fixture^.closed_before_free = accesskit_activation_callback(fixture^.owner) == nil
    fixture^.frees += 1
}

// windows_test_operations binds deterministic lifecycle operations to one fixture.
windows_test_operations :: proc(
    fixture: ^Windows_Test_Fixture) -> Windows_Adapter_Operations {
    return {
        user_data = fixture,
        create = windows_test_create,
        update = windows_test_update,
        raise_events = windows_test_raise,
        free = windows_test_free,
    }
}

// windows_test_tree_input returns one complete rooted control projection.
windows_test_tree_input :: proc(
    controls: []Adapter_Control_Input) -> Adapter_Tree_Input {
    return {
        root_bounds = {0, 0, 800, 600},
        bounds_scale = 1,
        window_focused = true,
        controls = controls,
    }
}

// windows_test_restart_controls returns one representative owner button.
windows_test_restart_controls :: proc() -> [1]Adapter_Control_Input {
    return {{
        identity = {domain = .Ui, owner_domain = 1, local_id = 2101},
        control = {
            role = .Button, bounds = {10, 10, 170, 42},
            label = "Restart animation", actions = {.Focus, .Activate},
            enabled = true, focusable = true,
        },
    }}
}

// windows_test_expect_missing_hwnd verifies terminal property-lookup failure.
windows_test_expect_missing_hwnd :: proc(
    t: ^testing.T, input: Adapter_Tree_Input,
    fixture: ^Windows_Test_Fixture) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    operations := windows_test_operations(fixture)
    testing.expect(t, !windows_adapter_publish_controls_with_operations(
        owner, nil, input, operations))
    diagnostics := adapter_windows_failures_snapshot(owner)
    testing.expect_value(t, diagnostics.last_stage,
        Windows_Failure_Stage.Hwnd_Property_Lookup)
    testing.expect_value(t, diagnostics.count, u64(1))
    testing.expect(t, accesskit_activation_callback(owner) == nil)
    testing.expect(t, !windows_adapter_publish_controls_with_operations(
        owner, rawptr(fixture), input, operations))
    testing.expect_value(t, fixture^.creates, 0)
}

// windows_test_expect_invalid_publication verifies pre-admission validation.
windows_test_expect_invalid_publication :: proc(
    t: ^testing.T, input: Adapter_Tree_Input,
    fixture: ^Windows_Test_Fixture) {
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    invalid_input := input
    invalid_input.root_bounds = {10, 10, 0, 0}
    testing.expect(t, !windows_adapter_publish_controls_with_operations(
        owner, rawptr(fixture), invalid_input,
        windows_test_operations(fixture)))
    diagnostics := adapter_windows_failures_snapshot(owner)
    testing.expect_value(t, diagnostics.last_stage,
        Windows_Failure_Stage.Initial_Publication)
}

// windows_test_expect_constructor_failure verifies activation then unwind.
windows_test_expect_constructor_failure :: proc(
    t: ^testing.T, input: Adapter_Tree_Input) {
    fixture: Windows_Test_Fixture
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)
    testing.expect(t, !windows_adapter_publish_controls_with_operations(
        owner, rawptr(&fixture), input, windows_test_operations(&fixture)))
    diagnostics := adapter_windows_failures_snapshot(owner)
    testing.expect_value(t, diagnostics.last_stage,
        Windows_Failure_Stage.Adapter_Creation)
    testing.expect_value(t, fixture.creates, 1)
    testing.expect(t, fixture.activation_complete)
    testing.expect(t, accesskit_activation_callback(owner) == nil)
}

// Verify admission failures are typed, terminal, and callback-safe.
@(test)
windows_adapter_admission_failures_are_terminal_and_typed :: proc(t: ^testing.T) {
    testing.expect(t, !windows_adapter_admit_with_operations(nil, nil, {}))
    controls := windows_test_restart_controls()
    input := windows_test_tree_input(controls[:])
    fixture := Windows_Test_Fixture{create_succeeds = true}
    windows_test_expect_missing_hwnd(t, input, &fixture)
    windows_test_expect_invalid_publication(t, input, &fixture)
    windows_test_expect_constructor_failure(t, input)
}

// windows_test_expect_updates verifies suppression and queued-event ownership.
windows_test_expect_updates :: proc(
    t: ^testing.T, fixture: ^Windows_Test_Fixture, owner: ^Adapter,
    operations: Windows_Adapter_Operations,
    controls: ^[1]Adapter_Control_Input) {
    input := windows_test_tree_input(controls^[:])
    testing.expect(t, windows_adapter_publish_controls_with_operations(
        owner, rawptr(fixture), input, operations))
    testing.expect_value(t, fixture^.updates, 0)
    controls^[0].control.focused = true
    testing.expect(t, windows_adapter_publish_controls_with_operations(
        owner, rawptr(fixture), windows_test_tree_input(controls^[:]), operations))
    testing.expect_value(t, fixture^.updates, 1)
    testing.expect_value(t, fixture^.raises, 1)
    fixture^.events_present = false
    controls^[0].control.focused = false
    testing.expect(t, windows_adapter_publish_controls_with_operations(
        owner, rawptr(fixture), windows_test_tree_input(controls^[:]), operations))
    testing.expect_value(t, fixture^.updates, 2)
    testing.expect_value(t, fixture^.raises, 1)
}

// windows_test_expect_action_and_teardown verifies ingress and release ordering.
windows_test_expect_action_and_teardown :: proc(
    t: ^testing.T, fixture: ^Windows_Test_Fixture, owner: ^Adapter,
    operations: Windows_Adapter_Operations) {
    request := accesskit.Action_Request{
        action = .Click,
        target_node = accesskit.Node_Id(2),
    }
    testing.expect_value(t, accesskit_copy_action_request(owner, &request),
        portable.Action_Queue_Status.Ok)
    action: Adapter_Action
    testing.expect_value(t, adapter_drain_action(owner, &action),
        Adapter_Action_Status.Ok)
    testing.expect_value(t, action.kind, Adapter_Action_Kind.Activate)
    windows_adapter_destroy_with_operations(owner, operations)
    windows_adapter_destroy_with_operations(owner, operations)
    testing.expect(t, fixture^.closed_before_free)
    testing.expect_value(t, fixture^.frees, 1)
    testing.expect(t, accesskit_activation_callback(owner) == nil)
}

// Verify one session owns updates, actions, events, and idempotent teardown.
@(test)
windows_adapter_lifecycle_owns_updates_actions_and_teardown :: proc(t: ^testing.T) {
    fixture := Windows_Test_Fixture{
        create_succeeds = true,
        events_present = true,
    }
    operations := windows_test_operations(&fixture)
    controls := windows_test_restart_controls()
    input := windows_test_tree_input(controls[:])
    owner := new(Adapter, context.allocator)
    defer free(owner, context.allocator)

    testing.expect(t, windows_adapter_publish_controls_with_operations(
        owner, rawptr(&fixture), input, operations))
    testing.expect_value(t, fixture.creates, 1)
    testing.expect(t, fixture.activation_complete)
    testing.expect(t, !windows_adapter_admit_with_operations(
        owner, rawptr(&fixture), operations))
    windows_test_expect_updates(t, &fixture, owner, operations, &controls)
    windows_test_expect_action_and_teardown(t, &fixture, owner, operations)
}