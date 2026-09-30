package native_accessibility

import "core:testing"

Macos_Test_Fixture :: struct {
    has_content_view: bool,
    has_window_class: bool,
    install_succeeds: bool,
    create_succeeds: bool,
    events_present: bool,
    installs: int,
    creates: int,
    updates: int,
    focus_updates: int,
    raises: int,
    frees: int,
}

MACOS_TEST_FAILURE_FIXTURES :: [5]Macos_Test_Fixture{
    {has_content_view = true, has_window_class = true,
        install_succeeds = true, create_succeeds = true},
    {has_window_class = true, install_succeeds = true, create_succeeds = true},
    {has_content_view = true, install_succeeds = true, create_succeeds = true},
    {has_content_view = true, has_window_class = true, create_succeeds = true},
    {has_content_view = true, has_window_class = true, install_succeeds = true},
}

MACOS_TEST_FAILURE_STAGES :: [5]Macos_Failure_Stage{
    .Cocoa_Property_Lookup,
    .Adapter_Creation,
    .Window_Class_Discovery,
    .Focus_Forwarder_Installation,
    .Adapter_Creation,
}

// macos_test_content_view simulates native content-view admission.
macos_test_content_view :: proc(user_data, _: rawptr) -> rawptr {
    fixture := cast(^Macos_Test_Fixture)user_data
    if fixture^.has_content_view {return user_data}
    return nil
}

// macos_test_window_class simulates runtime window-class discovery.
macos_test_window_class :: proc(
    user_data, _: rawptr) -> (rawptr, cstring) {
    fixture := cast(^Macos_Test_Fixture)user_data
    if fixture^.has_window_class {return user_data, "EuclidTestWindow"}
    return nil, nil
}

// macos_test_install records one attempted irreversible class mutation.
macos_test_install :: proc(user_data: rawptr, _: cstring) -> bool {
    fixture := cast(^Macos_Test_Fixture)user_data
    fixture^.installs += 1
    return fixture^.install_succeeds
}

// macos_test_create simulates native adapter construction.
macos_test_create :: proc(user_data, _: rawptr, _: ^Adapter) -> rawptr {
    fixture := cast(^Macos_Test_Fixture)user_data
    fixture^.creates += 1
    if fixture^.create_succeeds {return user_data}
    return nil
}

// macos_test_events returns one opaque transferred event when enabled.
macos_test_events :: proc(fixture: ^Macos_Test_Fixture) -> rawptr {
    return rawptr(fixture) if fixture^.events_present else nil
}

// macos_test_update records one native tree update.
macos_test_update :: proc(user_data, _: rawptr, _: ^Adapter) -> rawptr {
    fixture := cast(^Macos_Test_Fixture)user_data
    fixture^.updates += 1
    return macos_test_events(fixture)
}

// macos_test_update_focus records one native host-focus update.
macos_test_update_focus :: proc(user_data, _: rawptr, _: bool) -> rawptr {
    fixture := cast(^Macos_Test_Fixture)user_data
    fixture^.focus_updates += 1
    return macos_test_events(fixture)
}

// macos_test_raise consumes one simulated transferred event object.
macos_test_raise :: proc(user_data, _: rawptr) {
    fixture := cast(^Macos_Test_Fixture)user_data
    fixture^.raises += 1
}

// macos_test_free records one simulated native adapter release.
macos_test_free :: proc(user_data, _: rawptr) {
    fixture := cast(^Macos_Test_Fixture)user_data
    fixture^.frees += 1
}

// macos_test_operations binds deterministic lifecycle operations to one fixture.
macos_test_operations :: proc(
    fixture: ^Macos_Test_Fixture) -> Macos_Adapter_Operations {
    return {
        user_data = fixture,
        content_view = macos_test_content_view,
        window_class = macos_test_window_class,
        install_focus_forwarder = macos_test_install,
        create = macos_test_create,
        update = macos_test_update,
        update_focus = macos_test_update_focus,
        raise_events = macos_test_raise,
        free = macos_test_free,
    }
}

// macos_test_tree_input returns one rooted representative animation button.
macos_test_tree_input :: proc(
    controls: []Adapter_Control_Input) -> Adapter_Tree_Input {
    return {
        root_bounds = {0, 0, 800, 600},
        window_focused = true,
        controls = controls,
    }
}

// macos_test_expect_event_delivery checks update suppression and event ownership.
macos_test_expect_event_delivery :: proc(
    t: ^testing.T, fixture: ^Macos_Test_Fixture, owner: ^Adapter,
    operations: Macos_Adapter_Operations) {
    macos_adapter_notify_control_update_with_operations(owner, operations)
    macos_adapter_notify_control_update_with_operations(owner, operations)
    testing.expect_value(t, fixture^.updates, 1)
    testing.expect_value(t, fixture^.raises, 1)
    macos_adapter_update_focus_with_operations(owner, false, operations)
    testing.expect_value(t, fixture^.focus_updates, 1)
    testing.expect_value(t, fixture^.raises, 2)
    fixture^.events_present = false
    macos_adapter_update_focus_with_operations(owner, true, operations)
    testing.expect_value(t, fixture^.focus_updates, 2)
    testing.expect_value(t, fixture^.raises, 2)
}

// macos_test_expect_teardown checks native release and callback closure.
macos_test_expect_teardown :: proc(
    t: ^testing.T, fixture: ^Macos_Test_Fixture, first, second: ^Adapter,
    operations: Macos_Adapter_Operations) {
    macos_adapter_destroy_with_operations(first, operations)
    macos_adapter_destroy_with_operations(second, operations)
    testing.expect_value(t, fixture^.frees, 2)
    testing.expect(t, first^.native == nil)
    testing.expect(t, accesskit_activation_callback(first) == nil)
}

// Verify partial native admission failures close callbacks with typed stages.
@(test)
macos_adapter_partial_admission_failures_are_typed :: proc(t: ^testing.T) {
    controls := [1]Adapter_Control_Input{{
        identity = {domain = .Ui, owner_domain = 1, local_id = 2101},
        control = {
            role = .Button, bounds = {10, 10, 170, 42},
            label = "Restart animation", actions = {.Focus, .Activate},
            enabled = true, focusable = true,
        },
    }}
    input := macos_test_tree_input(controls[:])
    expected_stages := MACOS_TEST_FAILURE_STAGES
    process_state := new(Adapter_Process_State, context.allocator)
    defer free(process_state, context.allocator)
    for fixture_input, index in MACOS_TEST_FAILURE_FIXTURES {
        fixture := fixture_input
        owner := new(Adapter, context.allocator)
        window := rawptr(&fixture)
        if index == 0 {window = nil}
        testing.expect(t, !macos_adapter_publish_controls_with_operations(
            owner, window, input, macos_test_operations(&fixture), process_state))
        diagnostics := adapter_macos_failures_snapshot(owner)
        testing.expect_value(
            t, diagnostics.last_stage, expected_stages[index])
        testing.expect_value(t, diagnostics.count, 1)
        testing.expect(t, accesskit_activation_callback(owner) == nil)
        free(owner, context.allocator)
    }
}

// Verify sessions deduplicate class setup and own all native transfers.
@(test)
macos_adapter_lifecycle_owns_updates_focus_events_and_teardown :: proc(
    t: ^testing.T) {
    fixture := Macos_Test_Fixture{
        has_content_view = true,
        has_window_class = true,
        install_succeeds = true,
        create_succeeds = true,
        events_present = true,
    }
    operations := macos_test_operations(&fixture)
    controls := [1]Adapter_Control_Input{{
        identity = {domain = .Ui, owner_domain = 1, local_id = 2101},
        control = {
            role = .Button, bounds = {10, 10, 170, 42},
            label = "Restart animation", actions = {.Focus, .Activate},
            enabled = true, focusable = true, focused = true,
        },
    }}
    input := macos_test_tree_input(controls[:])
    process_state := new(Adapter_Process_State, context.allocator)
    defer free(process_state, context.allocator)
    first := new(Adapter, context.allocator)
    defer free(first, context.allocator)
    second := new(Adapter, context.allocator)
    defer free(second, context.allocator)
    testing.expect(t, macos_adapter_publish_controls_with_operations(
        first, rawptr(&fixture), input, operations, process_state))
    testing.expect(t, macos_adapter_publish_controls_with_operations(
        second, rawptr(&fixture), input, operations, process_state))
    testing.expect_value(t, fixture.installs, 1)
    testing.expect_value(t, fixture.creates, 2)

    macos_test_expect_event_delivery(t, &fixture, first, operations)

    action: Adapter_Action
    testing.expect_value(t,
        adapter_drain_action(first, &action), Adapter_Action_Status.Empty)
    macos_test_expect_teardown(t, &fixture, first, second, operations)
}