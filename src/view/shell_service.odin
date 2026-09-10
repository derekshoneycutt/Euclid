package view

import "../core"
import shell "../terminal/shell"
import termsession "../terminal/session"
import "input"
import terminalview "terminal"

import "core:fmt"
import "core:os"
import "core:path/filepath"

// Initialize the display-owned native shell backend and immutable launch context.
shell_service_runtime_init :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil ||
       !termsession.native_terminal_backend_init(&state^.shell.backend) {
        return false
    }
    if !termsession.terminal_session_init(
        &state^.shell.session, {id = core.SHELL_SESSION_OWNER_ID, generation = 1},
        termsession.native_terminal_backend_make(&state^.shell.backend)) {
        termsession.native_terminal_backend_destroy(&state^.shell.backend)
        return false
    }
    directory, error := os.get_working_directory(context.temp_allocator)
    if error != nil || !shell_service_store_paths(state, directory) {
        shell_service_runtime_destroy(state)
        return false
    }
    return true
}

// Rebind foreground operation identity to one Terminal animation generation.
shell_service_begin_generation :: proc(
    state: ^core.Euclid_General_State, generation: u64) -> bool {
    if state == nil || generation == 0 {
        return false
    }
    termsession.terminal_session_destroy(&state^.shell.session)
    state^.shell.phase = .Inactive
    return termsession.terminal_session_init(&state^.shell.session,
        {id = core.SHELL_SESSION_OWNER_ID, generation = generation},
        termsession.native_terminal_backend_make(&state^.shell.backend))
}

// Capture the bounded shell cwd and optional packaged terminfo directory.
shell_service_store_paths :: proc(
    state: ^core.Euclid_General_State, directory: string) -> bool {
    runtime := &state^.shell
    if len(directory) == 0 || len(directory) > len(runtime^.working_directory) {
        return false
    }
    copy(runtime^.working_directory[:], transmute([]u8)directory)
    runtime^.working_directory_byte_count = len(directory)
    paths := [2]string{directory, core.SHELL_TERMINFO_RELATIVE_DIRECTORY}
    terminfo, error := filepath.join(paths[:], context.temp_allocator)
    if error == nil && os.is_directory(terminfo) &&
       len(terminfo) <= len(runtime^.terminfo_directory) {
        copy(runtime^.terminfo_directory[:], transmute([]u8)terminfo)
        runtime^.terminfo_directory_byte_count = len(terminfo)
    }
    return true
}

// Tear down any foreground process before releasing its native backend.
shell_service_runtime_destroy :: proc(state: ^core.Euclid_General_State) {
    if state == nil {
        return
    }
    termsession.terminal_session_destroy(&state^.shell.session)
    termsession.native_terminal_backend_destroy(&state^.shell.backend)
    state^.shell = {}
}

// Append a shell failure and restore the editable prompt.
shell_service_fail :: proc(state: ^core.Euclid_General_State, message: string) {
    terminalview.terminal_append_ansi_output(&state^.terminal, message)
    terminalview.terminal_append_ansi_output(&state^.terminal, "\n")
    terminalview.terminal_complete_eval(&state^.terminal)
    state^.shell.phase = .Inactive
}

// Build terminal environment changes for one native child.
shell_service_environment :: proc(
    state: ^core.Euclid_General_State) -> ([3]termsession.Environment_Change, int) {
    changes: [3]termsession.Environment_Change
    changes[0] = {kind = .Set, key = "TERM", value = core.SHELL_TERMINFO_NAME}
    terminfo := core.shell_terminfo_directory(&state^.shell)
    if len(terminfo) > 0 {
        changes[1] = {kind = .Set, key = "TERMINFO", value = terminfo}
        changes[2] = {kind = .Set, key = "COLORTERM", value = "truecolor"}
        return changes, 3
    }
    changes[1] = {kind = .Set, key = "COLORTERM", value = "truecolor"}
    return changes, 2
}

// Admit one frozen process plan and retain its native operation identity.
shell_service_begin_plan :: proc(
    state: ^core.Euclid_General_State, plan: termsession.Process_Plan) -> bool {
    result := termsession.terminal_session_begin(&state^.shell.session,
        &termsession.Terminal_Session_Begin_Request{
            request_id = state^.terminal.pending_eval_request_id,
            owner = state^.shell.session.owner,
            plan = plan,
            dimensions = state^.terminal.geometry.dimensions,
            geometry_generation = state^.terminal.geometry.generation,
        })
    if !result.accepted {
        shell_service_fail(state, fmt.tprintf(
            "error: command launch rejected: %v", result.rejection))
        return false
    }
    state^.shell.request_id = result.request_id
    state^.shell.operation_id = result.operation_id
    state^.shell.phase = .Running
    return true
}

// Parse and launch one literal shell-mode submission through the native PTY backend.
shell_service_submit :: proc(
    state: ^core.Euclid_General_State, source: string) -> bool {
    if state == nil || state^.shell.phase != .Inactive ||
       !terminalview.terminal_begin_eval(&state^.terminal, source) {
        return false
    }
    parsed := shell.shell_parse(source)
    if parsed.kind == .Empty {
        terminalview.terminal_complete_eval(&state^.terminal)
        return true
    }
    if parsed.kind != .Success || parsed.template.interpolation_count != 0 {
        shell_service_fail(state, "error: unsupported shell syntax")
        return false
    }
    resolved := shell.shell_resolve(&parsed.template, nil)
    if resolved.kind != .Success {
        shell_service_fail(state, "error: command cannot resolve arguments")
        return false
    }
    environment, count := shell_service_environment(state)
    plan := termsession.process_plan_build_resolved(
        &resolved.command, core.shell_working_directory(&state^.shell),
        environment[:count])
    if plan.kind != .Success {
        shell_service_fail(state, "error: command cannot form a process plan")
        return false
    }
    return shell_service_begin_plan(state, plan.plan)
}

// Publish newer Terminal geometry to the active native operation.
shell_service_resize :: proc(
    state: ^core.Euclid_General_State,
    change: terminalview.Terminal_Geometry_Change) {
    if !change.changed {
        return
    }
    _ = termsession.terminal_session_resize(&state^.shell.session, {
        owner = state^.shell.session.owner,
        operation_id = state^.shell.operation_id,
        geometry_generation = change.generation,
        dimensions = change.current,
    })
}

// Encode and deliver one resolved input frame to the active native operation.
shell_service_input :: proc(
    state: ^core.Euclid_General_State, runtime: ^input.Input_Runtime,
    frame: input.Input_Frame) {
    if runtime == nil {
        return
    }
    _ = input.input_runtime_set_owner(runtime, {
        kind = .Terminal_Session,
        id = u64(state^.shell.operation_id.slot),
        generation = state^.shell.operation_id.generation,
    })
    input.input_terminal_enqueue_interpreter_frame(
        runtime, &state^.terminal.output_interpreter, frame)
    bytes: [termsession.TERMINAL_SESSION_INPUT_MAX_BYTES]u8
    count := input.input_runtime_copy_queued_bytes(runtime, bytes[:])
    if count == 0 {
        return
    }
    request := termsession.Terminal_Session_Input_Request{
        owner = state^.shell.session.owner,
        operation_id = state^.shell.operation_id,
        byte_count = count,
    }
    copy(request.bytes[:], bytes[:count])
    if termsession.terminal_session_write_input(
        &state^.shell.session, &request) == .None {
        _ = input.input_runtime_pop_queued_bytes(runtime, count)
    } else {
        runtime^.byte_delivery_rejection_count += 1
    }
}

// Drain one native PTY update, forward input, and reconcile final completion.
shell_service_update :: proc(
    state: ^core.Euclid_General_State, runtime: ^input.Input_Runtime = nil,
    frame: input.Input_Frame = {},
    geometry_change: terminalview.Terminal_Geometry_Change = {},
    admit_input: bool = false) {
    if state == nil || state^.shell.phase != .Running {
        return
    }
    update := termsession.terminal_session_update(&state^.shell.session)
    if update.output_count > 0 {
        terminalview.terminal_append_ansi_output(
            &state^.terminal, string(update.output[:update.output_count]), {
                kind = .Terminal_Session,
                id = u64(state^.shell.operation_id.slot),
                generation = state^.shell.operation_id.generation,
            })
    }
    if !update.completion_available {
        shell_service_resize(state, geometry_change)
        if admit_input {
            shell_service_input(state, runtime, frame)
        }
        return
    }
    if update.completion.status != 0 {
        terminalview.terminal_append_ansi_output(&state^.terminal, fmt.tprintf(
            "\n[process exited with status %d]", update.completion.status))
    }
    terminalview.terminal_complete_eval(&state^.terminal)
    state^.shell.phase = .Inactive
    state^.shell.request_id = 0
    state^.shell.operation_id = {}
    if runtime != nil {
        _ = input.input_runtime_set_owner(runtime, {})
    }
}