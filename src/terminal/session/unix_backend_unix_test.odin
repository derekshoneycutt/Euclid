#+build linux, darwin
#+test
package termsession

import protocol "../../core/protocol"
import "core:testing"
import "core:strings"
import "core:thread"

// Submit one real process plan through foreground-session admission.
termsession_test_begin_unix :: proc(
    manager: ^Terminal_Session_Manager, plan: Process_Plan,
    request_id: protocol.Request_Id) -> Terminal_Session_Begin_Result {
    request := Terminal_Session_Begin_Request{
        request_id = request_id,
        owner = TEST_SESSION_OWNER,
        plan = plan,
        dimensions = TEST_SESSION_DIMENSIONS,
    }
    return terminal_session_begin(manager, &request)
}

// Poll a real PTY session to completion while retaining bounded fixture output.
termsession_test_poll_unix_session :: proc(
    manager: ^Terminal_Session_Manager,
    output: ^[TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8) -> (int, Terminal_Session_Update) {
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

// Poll until one output marker is observed or the fixture reaches its bound.
termsession_test_poll_unix_marker :: proc(
    manager: ^Terminal_Session_Manager, marker: string) -> bool {
    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    output_count := 0
    for _ in 0..<100000 {
        update := terminal_session_update(manager)
        count := min(update.output_count, len(output) - output_count)
        copy(output[output_count:], update.output[:count])
        output_count += count
        if strings.contains(string(output[:output_count]), marker) {
            return true
        }
        if update.completion_available {
            return false
        }
        thread.yield()
    }
    return false
}

// Verify a child observes a TTY and fixed dimensions through forkpty.
@(test)
termsession_test_unix_pty_dimensions_and_exit :: proc(t: ^testing.T) {
    arguments := [3]string{"/bin/sh", "-c", "test -t 0 && stty size; exit 7"}
    plan := process_plan_build(arguments[:], "/tmp", nil)
    testing.expect_value(t, plan.kind, Process_Plan_Result_Kind.Success)

    backend: Unix_Terminal_Backend
    testing.expect(t, unix_terminal_backend_init(&backend))
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, unix_terminal_backend_make(&backend)))
    result := termsession_test_begin_unix(&manager, plan.plan, 901)
    testing.expect(t, result.accepted)

    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    output_count, update := termsession_test_poll_unix_session(&manager, &output)

    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.kind,
        Terminal_Session_Completion_Kind.Exited)
    testing.expect_value(t, update.completion.status, i32(7))
    testing.expect_value(t, string(output[:output_count]), "34 128\r\n")
    testing.expect_value(t, len(backend.workspace), 0)
}

// Verify a runtime resize reaches the child as SIGWINCH with updated dimensions.
@(test)
termsession_test_unix_pty_resize_and_sigwinch :: proc(t: ^testing.T) {
    arguments := [3]string{
        "/bin/sh", "-c",
        "trap 'stty size; exit 0' WINCH; printf ready; while :; do :; done",
    }
    plan := process_plan_build(arguments[:], "/tmp", nil)
    backend: Unix_Terminal_Backend
    testing.expect(t, unix_terminal_backend_init(&backend))
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, unix_terminal_backend_make(&backend)))
    result := termsession_test_begin_unix(&manager, plan.plan, 910)
    testing.expect(t, result.accepted)
    testing.expect(t, termsession_test_poll_unix_marker(&manager, "ready"))

    rejection := terminal_session_resize(&manager, {
        owner = TEST_SESSION_OWNER,
        operation_id = result.operation_id,
        geometry_generation = 1,
        dimensions = {columns = 100, rows = 30},
    })
    testing.expect_value(t, rejection, Terminal_Session_Rejection.None)
    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    output_count, update := termsession_test_poll_unix_session(&manager, &output)

    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.status, i32(0))
    testing.expect_value(t, string(output[:output_count]), "30 100\r\n")
}

// Verify incremental input reaches the child and final output drains before close.
@(test)
termsession_test_unix_pty_input_and_output :: proc(t: ^testing.T) {
    arguments := [3]string{
        "/bin/sh", "-c", "IFS= read -r value; printf 'child:%s' \"$value\"",
    }
    plan := process_plan_build(arguments[:], "/tmp", nil)
    backend: Unix_Terminal_Backend
    testing.expect(t, unix_terminal_backend_init(&backend))
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, unix_terminal_backend_make(&backend)))
    result := termsession_test_begin_unix(&manager, plan.plan, 902)
    testing.expect(t, result.accepted)
    input_request := Terminal_Session_Input_Request{
        owner = TEST_SESSION_OWNER,
        operation_id = result.operation_id,
        byte_count = len("hello\n"),
    }
    copy(input_request.bytes[:], "hello\n")
    testing.expect_value(t, terminal_session_write_input(
        &manager, &input_request), Terminal_Session_Rejection.None)

    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    output_count, update := termsession_test_poll_unix_session(&manager, &output)

    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.status, i32(0))
    testing.expect_value(t, string(output[:output_count]), "hello\r\nchild:hello")
}

// Verify parent-side executable discovery rejects before creating a PTY child.
@(test)
termsession_test_unix_executable_not_found_before_launch :: proc(t: ^testing.T) {
    arguments := [1]string{"euclid-command-that-does-not-exist"}
    plan := process_plan_build(arguments[:], "/tmp", nil)
    backend: Unix_Terminal_Backend
    testing.expect(t, unix_terminal_backend_init(&backend))
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, unix_terminal_backend_make(&backend)))

    result := termsession_test_begin_unix(&manager, plan.plan, 903)

    testing.expect_value(t, result.rejection,
        Terminal_Session_Rejection.Executable_Not_Found)
    testing.expect(t, !backend.active)
    testing.expect_value(t, len(backend.workspace), 0)
}

// Verify SIGINT targets the child process group and final trap output drains.
@(test)
termsession_test_unix_interrupt_process_group :: proc(t: ^testing.T) {
    arguments := [3]string{
        "/bin/sh", "-c",
        "trap 'printf interrupted; exit 42' INT; printf ready; while :; do :; done",
    }
    plan := process_plan_build(arguments[:], "/tmp", nil)
    backend: Unix_Terminal_Backend
    testing.expect(t, unix_terminal_backend_init(&backend))
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, unix_terminal_backend_make(&backend)))
    result := termsession_test_begin_unix(&manager, plan.plan, 904)
    testing.expect(t, result.accepted)
    testing.expect(t, termsession_test_poll_unix_marker(&manager, "ready"))
    testing.expect_value(t, terminal_session_signal(&manager, {
        owner = TEST_SESSION_OWNER,
        operation_id = result.operation_id,
        signal = .Interrupt,
    }), Terminal_Session_Rejection.None)

    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    output_count, update := termsession_test_poll_unix_session(&manager, &output)

    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.status, i32(42))
    testing.expect(t, strings.contains(string(output[:output_count]), "interrupted"))
}

// Verify cwd and inherited-environment deltas are encoded before fork.
@(test)
termsession_test_unix_cwd_and_environment :: proc(t: ^testing.T) {
    arguments := [3]string{
        "/bin/sh", "-c", "printf '%s|%s' \"$PWD\" \"$EUCLID_PHASE9\"",
    }
    environment := [2]Environment_Change{
        {kind = .Set, key = "EUCLID_PHASE9", value = "superseded"},
        {kind = .Set, key = "EUCLID_PHASE9", value = "owned"},
    }
    plan := process_plan_build(arguments[:], "/tmp", environment[:])
    backend: Unix_Terminal_Backend
    testing.expect(t, unix_terminal_backend_init(&backend))
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, unix_terminal_backend_make(&backend)))
    result := termsession_test_begin_unix(&manager, plan.plan, 905)
    testing.expect(t, result.accepted)

    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    output_count, update := termsession_test_poll_unix_session(&manager, &output)

    testing.expect(t, update.completion_available)
    expected := "/private/tmp|owned" when ODIN_OS == .Darwin else "/tmp|owned"
    testing.expect_value(t, string(output[:output_count]), expected)
}

// Verify output larger than one update drains without unbounded retention.
@(test)
termsession_test_unix_output_saturation :: proc(t: ^testing.T) {
    arguments := [3]string{
        "/bin/sh", "-c", "dd if=/dev/zero bs=20000 count=1 2>/dev/null",
    }
    plan := process_plan_build(arguments[:], "/tmp", nil)
    backend: Unix_Terminal_Backend
    testing.expect(t, unix_terminal_backend_init(&backend))
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, unix_terminal_backend_make(&backend)))
    result := termsession_test_begin_unix(&manager, plan.plan, 906)
    testing.expect(t, result.accepted)

    total := 0
    completed := false
    for _ in 0..<100000 {
        update := terminal_session_update(&manager)
        total += update.output_count
        if update.completion_available {
            completed = true
            break
        }
        thread.yield()
    }

    testing.expect(t, completed)
    testing.expect_value(t, total, 20000)
    testing.expect_value(t, len(backend.workspace), 0)
}

// Verify graceful cancellation reports the owner-visible cancelled outcome.
@(test)
termsession_test_unix_graceful_termination :: proc(t: ^testing.T) {
    arguments := [3]string{"/bin/sh", "-c", "printf ready; while :; do :; done"}
    plan := process_plan_build(arguments[:], "/tmp", nil)
    backend: Unix_Terminal_Backend
    testing.expect(t, unix_terminal_backend_init(&backend))
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, unix_terminal_backend_make(&backend)))
    result := termsession_test_begin_unix(&manager, plan.plan, 907)
    testing.expect(t, result.accepted)
    testing.expect(t, termsession_test_poll_unix_marker(&manager, "ready"))
    testing.expect_value(t, terminal_session_signal(&manager, {
        owner = TEST_SESSION_OWNER,
        operation_id = result.operation_id,
        signal = .Terminate,
    }), Terminal_Session_Rejection.None)

    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    _, update := termsession_test_poll_unix_session(&manager, &output)

    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.kind,
        Terminal_Session_Completion_Kind.Cancelled)
    testing.expect_value(t, len(backend.workspace), 0)
}

// Verify one backend state repeatedly allocates, closes, and frees its workspace.
@(test)
termsession_test_unix_repeated_session_cleanup :: proc(t: ^testing.T) {
    arguments := [1]string{"/usr/bin/true"}
    plan := process_plan_build(arguments[:], "/tmp", nil)
    backend: Unix_Terminal_Backend
    testing.expect(t, unix_terminal_backend_init(&backend))
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, unix_terminal_backend_make(&backend)))
    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8

    for cycle in 0..<16 {
        result := termsession_test_begin_unix(
            &manager, plan.plan, protocol.Request_Id(1000 + cycle))
        testing.expect(t, result.accepted)
        _, update := termsession_test_poll_unix_session(&manager, &output)
        testing.expect(t, update.completion_available)
        testing.expect_value(t, len(backend.workspace), 0)
    }
}

// Verify forced termination ends a process that explicitly ignores SIGTERM.
@(test)
termsession_test_unix_forced_termination :: proc(t: ^testing.T) {
    arguments := [3]string{
        "/bin/sh", "-c", "trap '' TERM; printf ready; while :; do :; done",
    }
    plan := process_plan_build(arguments[:], "/tmp", nil)
    backend: Unix_Terminal_Backend
    testing.expect(t, unix_terminal_backend_init(&backend))
    manager: Terminal_Session_Manager
    testing.expect(t, terminal_session_init(
        &manager, TEST_SESSION_OWNER, unix_terminal_backend_make(&backend)))
    result := termsession_test_begin_unix(&manager, plan.plan, 908)
    testing.expect(t, result.accepted)
    testing.expect(t, termsession_test_poll_unix_marker(&manager, "ready"))
    testing.expect_value(t, terminal_session_signal(&manager, {
        owner = TEST_SESSION_OWNER,
        operation_id = result.operation_id,
        signal = .Terminate,
    }), Terminal_Session_Rejection.None)
    testing.expect_value(t, terminal_session_signal(&manager, {
        owner = TEST_SESSION_OWNER,
        operation_id = result.operation_id,
        signal = .Force_Terminate,
    }), Terminal_Session_Rejection.None)

    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    _, update := termsession_test_poll_unix_session(&manager, &output)

    testing.expect(t, update.completion_available)
    testing.expect_value(t, update.completion.kind,
        Terminal_Session_Completion_Kind.Cancelled)
    testing.expect_value(t, len(backend.workspace), 0)
}