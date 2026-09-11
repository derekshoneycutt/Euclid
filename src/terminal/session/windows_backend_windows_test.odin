#+build windows
#+test
package termsession

import protocol "../../core/protocol"
import "core:testing"
import "core:time"

// Poll one real ConPTY session to completion while retaining bounded output.
windows_terminal_test_poll_session :: proc(
    manager: ^Terminal_Session_Manager,
    output: ^[TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8) ->
    (int, Terminal_Session_Update) {
    output_count := 0
    deadline := time.tick_since({}) + 5 * time.Second
    for time.tick_since({}) < deadline {
        update := terminal_session_update(manager)
        count := min(update.output_count, len(output) - output_count)
        copy(output[output_count:], update.output[:count])
        output_count += count
        if update.completion_available {
            return output_count, update
        }
        time.sleep(time.Millisecond)
    }
    return output_count, {}
}

// Build a plan for one script hosted by the in-box Windows command interpreter.
windows_terminal_test_command_plan :: proc(
    t: ^testing.T, script: string) -> Process_Plan {
    arguments := [4]string{"cmd.exe", "/d", "/c", script}
    result := process_plan_build(arguments[:], "C:/", nil)
    testing.expect_value(t, result.kind, Process_Plan_Result_Kind.Success)
    testing.expect_value(t, result.error, Process_Plan_Error.None)
    return result.plan
}

// Verify a real ConPTY child completes with its exit status and releases launch state.
@(test)
windows_terminal_test_completion_and_exit :: proc(t: ^testing.T) {
    plan := windows_terminal_test_command_plan(t,
        "exit /b 7")

    backend: Windows_Terminal_Backend
    testing.expect(t, windows_terminal_backend_init(&backend))
    defer windows_terminal_backend_destroy(&backend)
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, windows_terminal_backend_make(&backend)))
    request := Terminal_Session_Begin_Request{
        request_id = protocol.Request_Id(2001),
        owner = TEST_SESSION_OWNER,
        plan = plan,
        dimensions = TEST_SESSION_DIMENSIONS,
    }
    result := terminal_session_begin(&manager, &request)
    testing.expect(t, result.accepted)

    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    _, update := windows_terminal_test_poll_session(&manager, &output)
    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.kind,
        Terminal_Session_Completion_Kind.Exited)
    testing.expect_value(t, update.completion.status, i32(7))
    testing.expect_value(t, len(backend.workspace), 0)
}

// Verify runtime resize and forced cancellation complete teardown exactly once.
@(test)
windows_terminal_test_resize_and_cancel :: proc(t: ^testing.T) {
    plan := windows_terminal_test_command_plan(t,
        "ping -n 30 127.0.0.1 >nul")
    backend: Windows_Terminal_Backend
    testing.expect(t, windows_terminal_backend_init(&backend))
    defer windows_terminal_backend_destroy(&backend)
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, windows_terminal_backend_make(&backend)))
    request := Terminal_Session_Begin_Request{
        request_id = protocol.Request_Id(2004),
        owner = TEST_SESSION_OWNER,
        plan = plan,
        dimensions = TEST_SESSION_DIMENSIONS,
    }
    result := terminal_session_begin(&manager, &request)
    testing.expect(t, result.accepted)
    testing.expect_value(t, terminal_session_resize(&manager, {
        owner = TEST_SESSION_OWNER,
        operation_id = result.operation_id,
        geometry_generation = 1,
        dimensions = {columns = 100, rows = 30},
    }), Terminal_Session_Rejection.None)
    testing.expect_value(t, terminal_session_signal(&manager, {
        owner = TEST_SESSION_OWNER,
        operation_id = result.operation_id,
        signal = .Force_Terminate,
    }), Terminal_Session_Rejection.None)

    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    _, update := windows_terminal_test_poll_session(&manager, &output)
    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.kind,
        Terminal_Session_Completion_Kind.Cancelled)
    testing.expect_value(t, len(backend.workspace), 0)
    testing.expect(t, !terminal_session_update(&manager).completion_available)
}

// Verify a bare system executable resolves from the inherited Windows PATH.
@(test)
windows_terminal_test_bare_cmd_resolves :: proc(t: ^testing.T) {
    arguments := [4]string{"cmd.exe", "/d", "/c", "exit 0"}
    plan := process_plan_build(arguments[:], "C:/", nil)
    backend: Windows_Terminal_Backend
    testing.expect(t, windows_terminal_backend_init(&backend))
    defer windows_terminal_backend_destroy(&backend)
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, windows_terminal_backend_make(&backend)))
    request := Terminal_Session_Begin_Request{
        request_id = protocol.Request_Id(2002),
        owner = TEST_SESSION_OWNER,
        plan = plan.plan,
        dimensions = TEST_SESSION_DIMENSIONS,
    }
    result := terminal_session_begin(&manager, &request)
    testing.expect(t, result.accepted)

    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    _, update := windows_terminal_test_poll_session(&manager, &output)

    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.kind,
        Terminal_Session_Completion_Kind.Exited)
    testing.expect_value(t, update.completion.status, i32(0))
    testing.expect_value(t, len(backend.workspace), 0)
}

// Verify missing bare names reject before any Windows session resources remain live.
@(test)
windows_terminal_test_bare_executable_not_found :: proc(t: ^testing.T) {
    arguments := [1]string{"euclid-command-that-does-not-exist.exe"}
    plan := process_plan_build(arguments[:], "C:/", nil)
    backend: Windows_Terminal_Backend
    testing.expect(t, windows_terminal_backend_init(&backend))
    defer windows_terminal_backend_destroy(&backend)
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, windows_terminal_backend_make(&backend)))
    request := Terminal_Session_Begin_Request{
        request_id = protocol.Request_Id(2003),
        owner = TEST_SESSION_OWNER,
        plan = plan.plan,
        dimensions = TEST_SESSION_DIMENSIONS,
    }

    result := terminal_session_begin(&manager, &request)

    testing.expect(t, !result.accepted)
    testing.expect_value(t, result.rejection,
        Terminal_Session_Rejection.Executable_Not_Found)
    testing.expect(t, !backend.active)
    testing.expect_value(t, len(backend.workspace), 0)
}