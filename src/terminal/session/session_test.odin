package termsession

import protocol "../../core/protocol"
import "core:log"
import "core:strings"
import "core:testing"

TEST_SESSION_OWNER :: Session_Owner{id = 7, generation = 2}
TEST_SESSION_DIMENSIONS :: Terminal_Dimensions{columns = 128, rows = 34}

Terminal_Session_Test_Log_State :: struct {
    started_count : int,
    rejected_count : int,
    completed_count : int,
    correlated : bool,
}

// Capture session lifecycle records and their stable correlation metadata.
terminal_session_test_log_proc :: proc(
    data: rawptr, _: log.Level, text: string, _: log.Options,
    _ := #caller_location) {
    state := (^Terminal_Session_Test_Log_State)(data)
    if strings.contains(text, "terminal session started") {
        state^.started_count += 1
        state^.correlated = strings.contains(text, "request_id=11") &&
            strings.contains(text, "owner_id=7") &&
            strings.contains(text, "operation_generation=1")
    } else if strings.contains(text, "terminal session rejected") {
        state^.rejected_count += 1
    } else if strings.contains(text, "terminal session completed") {
        state^.completed_count += 1
    }
}

// Build one valid direct plan for operation tests.
termsession_test_plan :: proc() -> Process_Plan {
    arguments := [2]string{"tool", "a b|c"}
    result := process_plan_build(arguments[:], "/tmp", nil)
    return result.plan
}

// Begin one fake foreground session and return its stable operation identity.
termsession_test_begin :: proc(
    t: ^testing.T, manager: ^Terminal_Session_Manager,
    request_id: protocol.Request_Id = 11) -> Terminal_Session_Operation_Id {
    request := Terminal_Session_Begin_Request{
        request_id = request_id,
        owner = TEST_SESSION_OWNER,
        plan = termsession_test_plan(),
        dimensions = TEST_SESSION_DIMENSIONS,
    }
    result := terminal_session_begin(manager, &request)
    testing.expect(t, result.accepted)
    testing.expect_value(t, result.rejection, Terminal_Session_Rejection.None)
    return result.operation_id
}

// Verify invalid and stale requests fail before backend resource allocation.
@(test)
termsession_test_admission_precedes_backend_start :: proc(t: ^testing.T) {
    backend := Fake_Terminal_Backend{
        start_status = .Started, resize_succeeds = true}
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, fake_terminal_backend_make(&backend)))
    nil_request := terminal_session_begin(&manager, nil)
    testing.expect_value(t, nil_request.rejection,
        Terminal_Session_Rejection.Invalid_Request)
    request := Terminal_Session_Begin_Request{
        request_id = 1,
        owner = {id = 7, generation = 1},
        plan = termsession_test_plan(),
        dimensions = TEST_SESSION_DIMENSIONS,
    }

    stale := terminal_session_begin(&manager, &request)
    testing.expect_value(t, stale.rejection,
        Terminal_Session_Rejection.Stale_Owner)
    testing.expect_value(t, backend.start_count, 0)

    request.owner = TEST_SESSION_OWNER
    request.plan.argument_count = 0
    invalid := terminal_session_begin(&manager, &request)
    testing.expect_value(t, invalid.rejection,
        Terminal_Session_Rejection.Invalid_Plan)
    testing.expect_value(t, backend.start_count, 0)
}

// Verify backend failure preserves the last successfully applied geometry.
termsession_test_expect_resize_failure :: proc(
    t: ^testing.T, manager: ^Terminal_Session_Manager,
    backend: ^Fake_Terminal_Backend,
    request: Terminal_Session_Resize_Request) {
    backend.resize_succeeds = false
    failed := request
    failed.geometry_generation += 1
    log_state: Terminal_Session_Test_Log_State
    prior_logger := context.logger
    context.logger = log.Logger{
        procedure = terminal_session_test_log_proc,
        data = &log_state,
        lowest_level = .Debug,
    }
    testing.expect_value(t, terminal_session_resize(manager, failed),
        Terminal_Session_Rejection.Backend_Failure)
    context.logger = prior_logger
    testing.expect_value(t,
        manager.operation.applied_geometry_generation, request.geometry_generation)
}

// Verify resize applies only to the current operation and newer geometry generation.
@(test)
termsession_test_resize_is_correlated_and_ordered :: proc(t: ^testing.T) {
    backend := Fake_Terminal_Backend{
        start_status = .Started, resize_succeeds = true}
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, fake_terminal_backend_make(&backend)))
    operation_id := termsession_test_begin(t, &manager)
    request := Terminal_Session_Resize_Request{
        owner = TEST_SESSION_OWNER,
        operation_id = operation_id,
        geometry_generation = 2,
        dimensions = {columns = 100, rows = 30},
    }

    testing.expect_value(t, terminal_session_resize(&manager, request),
        Terminal_Session_Rejection.None)
    testing.expect_value(t, backend.resize_count, 1)
    testing.expect_value(t, backend.dimensions, request.dimensions)
    testing.expect_value(t, terminal_session_resize(&manager, request),
        Terminal_Session_Rejection.None)
    testing.expect_value(t, backend.resize_count, 1)
    termsession_test_expect_resize_failure(t, &manager, &backend, request)
    request.operation_id.generation += 1
    testing.expect_value(t, terminal_session_resize(&manager, request),
        Terminal_Session_Rejection.Stale_Operation)
}

// Verify a second foreground request is rejected without another backend start.
termsession_test_expect_foreground_busy :: proc(
    t: ^testing.T, manager: ^Terminal_Session_Manager,
    backend: ^Fake_Terminal_Backend) {
    request := Terminal_Session_Begin_Request{
        request_id = 12,
        owner = TEST_SESSION_OWNER,
        plan = termsession_test_plan(),
        dimensions = TEST_SESSION_DIMENSIONS,
    }
    result := terminal_session_begin(manager, &request)
    testing.expect_value(t, result.rejection,
        Terminal_Session_Rejection.Foreground_Busy)
    testing.expect_value(t, backend.start_count, 1)
}

// Verify one active session accepts input and emits bounded output.
termsession_test_expect_input_output :: proc(
    t: ^testing.T, manager: ^Terminal_Session_Manager,
    backend: ^Fake_Terminal_Backend,
    operation_id: Terminal_Session_Operation_Id) {
    input := Terminal_Session_Input_Request{
        owner = TEST_SESSION_OWNER,
        operation_id = operation_id,
        byte_count = 3,
    }
    copy(input.bytes[:], "abc")
    testing.expect_value(t, terminal_session_write_input(manager, &input),
        Terminal_Session_Rejection.None)
    testing.expect_value(t, string(backend.input[:backend.input_count]), "abc")
    fake_terminal_backend_queue_output(backend, "ready\n")
    update := terminal_session_update(manager)
    testing.expect_value(t, string(update.output[:update.output_count]), "ready\n")
    testing.expect(t, !update.completion_available)
}

// Verify backend completion restores Julia input and closes exactly once.
termsession_test_expect_completion :: proc(
    t: ^testing.T, manager: ^Terminal_Session_Manager,
    backend: ^Fake_Terminal_Backend) {
    fake_terminal_backend_finish(backend, {kind = .Exited, status = 3})
    completed := terminal_session_update(manager)
    testing.expect(t, completed.completion_available)
    testing.expect_value(t, completed.completion.kind,
        Terminal_Session_Completion_Kind.Exited)
    testing.expect_value(t, completed.completion.status, i32(3))
    testing.expect_value(t, manager.input_target, Terminal_Input_Target.Julia_Repl)
    testing.expect_value(t, backend.close_count, 1)
    testing.expect(t, !terminal_session_update(manager).completion_available)
}

// Verify foreground admission, input targeting, bounded output, and exact completion.
@(test)
termsession_test_fake_backend_lifecycle :: proc(t: ^testing.T) {
    log_state: Terminal_Session_Test_Log_State
    prior_logger := context.logger
    context.logger = log.Logger{
        procedure = terminal_session_test_log_proc,
        data = &log_state,
        lowest_level = .Debug,
    }
    defer context.logger = prior_logger

    backend := Fake_Terminal_Backend{start_status = .Started}
    manager: Terminal_Session_Manager
    terminal_session_init(
        &manager, TEST_SESSION_OWNER, fake_terminal_backend_make(&backend))
    operation_id := termsession_test_begin(t, &manager)
    testing.expect_value(t, manager.input_target,
        Terminal_Input_Target.Terminal_Session)
    termsession_test_expect_foreground_busy(t, &manager, &backend)
    termsession_test_expect_input_output(t, &manager, &backend, operation_id)
    termsession_test_expect_completion(t, &manager, &backend)
    testing.expect_value(t, log_state.started_count, 1)
    testing.expect_value(t, log_state.rejected_count, 1)
    testing.expect_value(t, log_state.completed_count, 1)
    testing.expect(t, log_state.correlated)
}

// Verify owner stop requests cancellation and completion reconciles once.
@(test)
termsession_test_owner_stop_cancels_without_transfer_or_detach :: proc(t: ^testing.T) {
    backend := Fake_Terminal_Backend{start_status = .Started}
    manager: Terminal_Session_Manager
    terminal_session_init(
        &manager, TEST_SESSION_OWNER, fake_terminal_backend_make(&backend))
    operation_id := termsession_test_begin(t, &manager, 21)

    testing.expect_value(t, terminal_session_transfer_owner(
        &manager, TEST_SESSION_OWNER, {id = 8, generation = 1}),
        Terminal_Session_Rejection.Unsupported)
    testing.expect_value(t, terminal_session_detach(&manager, operation_id),
        Terminal_Session_Rejection.Unsupported)
    testing.expect(t, terminal_session_owner_stopped(&manager, TEST_SESSION_OWNER))
    testing.expect(t, terminal_session_owner_stopped(&manager, TEST_SESSION_OWNER))
    testing.expect_value(t, backend.terminate_count, 1)

    fake_terminal_backend_finish(&backend, {kind = .Signalled, status = 15})
    update := terminal_session_update(&manager)
    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.kind,
        Terminal_Session_Completion_Kind.Cancelled)
    testing.expect_value(t, update.completion.owner, TEST_SESSION_OWNER)
    testing.expect_value(t, update.completion.operation_id, operation_id)
    testing.expect(t, !terminal_session_update(&manager).completion_available)
}

// Verify executable discovery failures remain explicit admission outcomes.
@(test)
termsession_test_executable_not_found_is_explicit :: proc(t: ^testing.T) {
    backend := Fake_Terminal_Backend{start_status = .Executable_Not_Found}
    manager: Terminal_Session_Manager
    terminal_session_init(
        &manager, TEST_SESSION_OWNER, fake_terminal_backend_make(&backend))
    request := Terminal_Session_Begin_Request{
        request_id = 31,
        owner = TEST_SESSION_OWNER,
        plan = termsession_test_plan(),
        dimensions = TEST_SESSION_DIMENSIONS,
    }

    result := terminal_session_begin(&manager, &request)

    testing.expect(t, !result.accepted)
    testing.expect_value(t, result.rejection,
        Terminal_Session_Rejection.Executable_Not_Found)
    testing.expect_value(t, backend.start_count, 1)
    testing.expect_value(t, manager.operation.state, Terminal_Session_State.Inactive)
}

// Build one active fake manager for bounded-close tests.
termsession_test_close_manager :: proc(
    t: ^testing.T, backend: ^Fake_Terminal_Backend) -> Terminal_Session_Manager {
    backend.start_status = .Started
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, fake_terminal_backend_make(backend)))
    termsession_test_begin(t, &manager)
    return manager
}

// Verify ordinary graceful completion closes directly without transfer.
@(test)
termsession_test_bounded_close_completes_gracefully :: proc(t: ^testing.T) {
    backend: Fake_Terminal_Backend
    manager := termsession_test_close_manager(t, &backend)
    registry: Process_Cleanup_Registry
    coordinator: Terminal_Process_Close_Coordinator

    testing.expect(t, terminal_process_close_begin(
        &coordinator, &manager, &registry,
        {generation = 2, now_ns = 100, graceful_ns = 10, final_ns = 20}))
    testing.expect_value(t, coordinator.phase,
        Terminal_Process_Close_Phase.Graceful_Requested)
    testing.expect_value(t, backend.terminate_count, 1)
    fake_terminal_backend_queue_output(&backend, "last")
    fake_terminal_backend_finish(&backend, {kind = .Exited, status = 0})

    update := terminal_process_close_advance(
        &coordinator, &manager, &registry, 105)
    testing.expect_value(t, string(update.output[:update.output_count]), "last")
    testing.expect(t, update.completion_available)
    testing.expect_value(t, coordinator.phase,
        Terminal_Process_Close_Phase.Complete)
    testing.expect_value(t, backend.force_terminate_count, 0)
    testing.expect_value(t, backend.close_count, 1)
    testing.expect_value(t, registry.entry_count, 0)
}

// Verify a live process is force-terminated at the graceful deadline.
@(test)
termsession_test_bounded_close_escalates_once :: proc(t: ^testing.T) {
    backend: Fake_Terminal_Backend
    manager := termsession_test_close_manager(t, &backend)
    registry: Process_Cleanup_Registry
    coordinator: Terminal_Process_Close_Coordinator
    terminal_process_close_begin(&coordinator, &manager, &registry,
        {generation = 2, now_ns = 100, graceful_ns = 10, final_ns = 20})

    terminal_process_close_advance(&coordinator, &manager, &registry, 109)
    testing.expect_value(t, backend.force_terminate_count, 0)
    terminal_process_close_advance(&coordinator, &manager, &registry, 110)
    testing.expect_value(t, backend.force_terminate_count, 1)
    testing.expect_value(t, coordinator.phase,
        Terminal_Process_Close_Phase.Force_Requested)
    terminal_process_close_advance(&coordinator, &manager, &registry, 111)
    testing.expect_value(t, backend.force_terminate_count, 1)
}

// Verify process exit enters bounded output reaping before final transfer.
@(test)
termsession_test_bounded_close_reaps_then_transfers :: proc(t: ^testing.T) {
    backend: Fake_Terminal_Backend
    manager := termsession_test_close_manager(t, &backend)
    registry: Process_Cleanup_Registry
    coordinator: Terminal_Process_Close_Coordinator
    terminal_process_close_begin(&coordinator, &manager, &registry,
        {generation = 2, now_ns = 100, graceful_ns = 10, final_ns = 20})
    backend.process_exited = true
    backend.exit = {kind = .Exited, status = 0}

    terminal_process_close_advance(&coordinator, &manager, &registry, 110)
    testing.expect_value(t, coordinator.phase, Terminal_Process_Close_Phase.Reaping)
    testing.expect_value(t, backend.force_terminate_count, 0)
    fake_terminal_backend_queue_output(&backend, "tail")
    update := terminal_process_close_advance(
        &coordinator, &manager, &registry, 120)

    testing.expect_value(t, string(update.output[:update.output_count]), "tail")
    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.kind,
        Terminal_Session_Completion_Kind.Infrastructure_Failure)
    testing.expect_value(t, coordinator.phase,
        Terminal_Process_Close_Phase.Transferred)
    testing.expect_value(t, backend.transfer_count, 1)
    testing.expect_value(t, backend.close_count, 0)
    testing.expect_value(t, registry.entry_count, 1)
}

// Verify backend signal failure transfers immediately without forgetting ownership.
@(test)
termsession_test_bounded_close_signal_failure_transfers :: proc(t: ^testing.T) {
    log_state: Terminal_Session_Test_Log_State
    prior_logger := context.logger
    context.logger = log.Logger{
        procedure = terminal_session_test_log_proc,
        data = &log_state,
        lowest_level = .Debug,
    }
    defer context.logger = prior_logger
    backend := Fake_Terminal_Backend{
        terminate_fails = true,
        force_terminate_fails = true,
    }
    manager := termsession_test_close_manager(t, &backend)
    registry: Process_Cleanup_Registry
    coordinator: Terminal_Process_Close_Coordinator

    testing.expect(t, terminal_process_close_begin(
        &coordinator, &manager, &registry,
        {generation = 2, now_ns = 100, graceful_ns = 10, final_ns = 20}))
    testing.expect_value(t, coordinator.phase,
        Terminal_Process_Close_Phase.Transferred)
    testing.expect_value(t, backend.transfer_count, 1)
    testing.expect_value(t, registry.entry_count, 1)
    testing.expect_value(t, manager.operation.state, Terminal_Session_State.Inactive)
}

// Verify a full cleanup registry leaves the active backend tracked for retry.
@(test)
termsession_test_bounded_close_registry_full_retains_operation :: proc(t: ^testing.T) {
    log_state: Terminal_Session_Test_Log_State
    prior_logger := context.logger
    context.logger = log.Logger{
        procedure = terminal_session_test_log_proc,
        data = &log_state,
        lowest_level = .Debug,
    }
    defer context.logger = prior_logger
    backend := Fake_Terminal_Backend{
        terminate_fails = true,
        force_terminate_fails = true,
    }
    manager := termsession_test_close_manager(t, &backend)
    registry: Process_Cleanup_Registry
    registry.entry_count = len(registry.entries)
    coordinator: Terminal_Process_Close_Coordinator

    testing.expect(t, terminal_process_close_begin(
        &coordinator, &manager, &registry,
        {generation = 2, now_ns = 100, graceful_ns = 10, final_ns = 20}))
    testing.expect_value(t, coordinator.phase,
        Terminal_Process_Close_Phase.Force_Requested)
    testing.expect_value(t, backend.transfer_count, 0)
    testing.expect(t, manager.operation.state != .Inactive)
}

// Verify completed fixed cleanup storage is reused by a later generation.
@(test)
termsession_test_cleanup_registry_reuses_completed_slot :: proc(t: ^testing.T) {
    registry: Process_Cleanup_Registry
    first := process_cleanup_registry_reserve(&registry, 2)
    testing.expect(t, first != nil)
    first.status = .Complete

    second := process_cleanup_registry_reserve(&registry, 3)

    testing.expect(t, second == first)
    testing.expect_value(t, second.generation, u64(3))
    testing.expect_value(t, second.status, Process_Cleanup_Status.Pending)
    testing.expect_value(t, registry.entry_count, 1)
}