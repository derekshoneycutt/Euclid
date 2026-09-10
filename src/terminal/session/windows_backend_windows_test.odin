#+build windows
#+test
package termsession

import protocol "../../core/protocol"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:thread"

WINDOWS_TERMINAL_TEST_FIXTURE_PATH :: ".build/test/conpty_fixture.exe"

// Poll one real ConPTY session to completion while retaining bounded output.
windows_terminal_test_poll_session :: proc(
    manager: ^Terminal_Session_Manager,
    output: ^[TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8) ->
    (int, Terminal_Session_Update) {
    output_count := 0
    for _ in 0..<100000 {
        update := terminal_session_update(manager)
        count := min(update.output_count, len(output) - output_count)
        copy(output[output_count:], update.output[:count])
        output_count += count
        if update.completion_available {
            return output_count, update
        }
        thread.yield()
    }
    return output_count, {}
}

// Build a bare-name fixture plan whose executable exists only on its child PATH.
windows_terminal_test_fixture_plan :: proc(t: ^testing.T) -> Process_Plan {
    fixture, fixture_error := filepath.abs(
        WINDOWS_TERMINAL_TEST_FIXTURE_PATH, context.temp_allocator)
    testing.expect(t, fixture_error == nil)
    fixture_directory, fixture_name := filepath.split(fixture)
    arguments := [1]string{fixture_name}
    environment := [1]Environment_Change{{
        kind = .Set,
        key = "PATH",
        value = fixture_directory,
    }}
    result := process_plan_build(arguments[:], "C:/", environment[:])
    testing.expect_value(t, result.kind, Process_Plan_Result_Kind.Success)
    testing.expect_value(t, result.error, Process_Plan_Error.None)
    return result.plan
}

// Verify a real ConPTY child observes initial dimensions and drains before exit.
@(test)
windows_terminal_test_dimensions_and_exit :: proc(t: ^testing.T) {
    plan := windows_terminal_test_fixture_plan(t)

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
    output_count, update := windows_terminal_test_poll_session(&manager, &output)
    text := string(output[:output_count])
    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.kind,
        Terminal_Session_Completion_Kind.Exited)
    testing.expect_value(t, update.completion.status, i32(7))
    testing.expect(t, strings.contains(text, "DIMENSIONS 128 34"))
    testing.expect_value(t, len(backend.workspace), 0)
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