package termsession

// Deterministic allocation-free backend state for session-manager tests.
Fake_Terminal_Backend :: struct {
    // Configured start outcome and most recently captured launch request.
    start_status: Backend_Start_Status,
    start_count: int,
    plan: Process_Plan,
    dimensions: Terminal_Dimensions,
    resize_succeeds: bool,
    resize_count: int,

    // Callback invocation telemetry.
    write_count: int,
    interrupt_count: int,
    terminate_count: int,
    force_terminate_count: int,
    transfer_count: int,
    close_count: int,

    // Cumulative bounded input capture.
    input: [1024]u8,
    input_count: int,

    // Single-transfer output queue consumed by the next poll.
    output: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8,
    output_count: int,

    // Configured completion withheld until explicitly marked ready.
    exit: Backend_Exit,
    process_exited: bool,
    output_drained: bool,
    terminate_fails: bool,
    force_terminate_fails: bool,
}

//   Record one fake resize and return its configured outcome.
fake_terminal_backend_resize :: proc(
    user_data: rawptr, dimensions: Terminal_Dimensions) -> bool {
    backend := (^Fake_Terminal_Backend)(user_data)
    backend.resize_count += 1
    if !backend.resize_succeeds {
        return false
    }
    backend.dimensions = dimensions
    return true
}

//   Record one fake launch without allocating platform resources.
//
// Parameters:
//   - user_data: Non-nil `^Fake_Terminal_Backend`.
//   - plan: Valid plan copied by value for assertions.
//   - dimensions: Positive viewport copied for assertions.
//
// Returns:
//   - The fake's configured start status.
//
// Side effects:
//   - Increments start count and snapshots the launch inputs.
fake_terminal_backend_start :: proc(
    user_data: rawptr, plan: ^Process_Plan,
    dimensions: Terminal_Dimensions) -> Backend_Start_Status {
    backend := (^Fake_Terminal_Backend)(user_data)
    backend.start_count += 1
    backend.plan = plan^
    backend.dimensions = dimensions
    return backend.start_status
}

//   Transfer queued fake output at most once.
//
// Parameters:
//   - user_data: Non-nil fake backend state.
//   - destination: Caller-owned output buffer.
//
// Returns:
//   - Number of queued bytes copied, bounded by destination length.
//
// Side effects:
//   - Clears the entire queued count after one poll.
fake_terminal_backend_poll_output :: proc(
    user_data: rawptr, destination: []u8) -> int {
    backend := (^Fake_Terminal_Backend)(user_data)
    count := min(len(destination), backend.output_count)
    copy(destination[:count], backend.output[:count])
    backend.output_count = 0
    return count
}

//   Append foreground input to bounded fake capture storage.
//
// Returns:
//   - True after copying all bytes; false without mutation when capacity is exceeded.
//
// Side effects:
//   - Advances input count and write-call telemetry on success.
fake_terminal_backend_write_input :: proc(
    user_data: rawptr, bytes: []u8) -> bool {
    backend := (^Fake_Terminal_Backend)(user_data)
    if backend.input_count + len(bytes) > len(backend.input) {
        return false
    }
    copy(backend.input[backend.input_count:], bytes)
    backend.input_count += len(bytes)
    backend.write_count += 1
    return true
}

//   Record one accepted interrupt request.
fake_terminal_backend_request_interrupt :: proc(user_data: rawptr) -> bool {
    backend := (^Fake_Terminal_Backend)(user_data)
    backend.interrupt_count += 1
    return true
}

//   Record one accepted graceful-termination request.
fake_terminal_backend_request_terminate :: proc(user_data: rawptr) -> bool {
    backend := (^Fake_Terminal_Backend)(user_data)
    backend.terminate_count += 1
    return !backend.terminate_fails
}

//   Record one accepted forced-termination request.
fake_terminal_backend_force_terminate :: proc(user_data: rawptr) -> bool {
    backend := (^Fake_Terminal_Backend)(user_data)
    backend.force_terminate_count += 1
    return !backend.force_terminate_fails
}

//   Poll the configured fake exit readiness without consuming it.
//
// Returns:
//   - The configured exit and its current readiness flag.
fake_terminal_backend_poll_exit :: proc(
    user_data: rawptr) -> Backend_Exit_Progress {
    backend := (^Fake_Terminal_Backend)(user_data)
    return {
        exit = backend.exit,
        process_exited = backend.process_exited,
        output_drained = backend.output_drained,
    }
}

//   Record deterministic resource closure and clear exit readiness.
fake_terminal_backend_close :: proc(user_data: rawptr) {
    backend := (^Fake_Terminal_Backend)(user_data)
    backend.close_count += 1
    backend.process_exited = false
    backend.output_drained = false
}

//   Transfer one fake operation into bounded application cleanup storage.
fake_terminal_backend_transfer :: proc(
    user_data: rawptr, registry: ^Process_Cleanup_Registry,
    generation: u64) -> bool {
    backend := (^Fake_Terminal_Backend)(user_data)
    entry := process_cleanup_registry_reserve(registry, generation)
    if entry == nil {
        return false
    }
    backend.transfer_count += 1
    backend.process_exited = false
    backend.output_drained = false
    return true
}

//   Build the common backend table around one fake mechanism state.
//
// Parameters:
//   - backend: Fake state that must outlive every use of the returned table.
//
// Returns:
//   - Complete callback table borrowing `backend` through `user_data`.
fake_terminal_backend_make :: proc(
    backend: ^Fake_Terminal_Backend) -> Terminal_Process_Backend {
    return {
        user_data = rawptr(backend),
        start = fake_terminal_backend_start,
        resize = fake_terminal_backend_resize,
        poll_output = fake_terminal_backend_poll_output,
        write_input = fake_terminal_backend_write_input,
        request_interrupt = fake_terminal_backend_request_interrupt,
        request_terminate = fake_terminal_backend_request_terminate,
        force_terminate = fake_terminal_backend_force_terminate,
        poll_exit = fake_terminal_backend_poll_exit,
        transfer = fake_terminal_backend_transfer,
        close = fake_terminal_backend_close,
    }
}

//   Replace queued output with one fragment for the next service update.
//
// Returns:
//   - True after copying text; false for nil or oversized input.
//
// Side effects:
//   - Overwrites prior queued bytes and count on success.
fake_terminal_backend_queue_output :: proc(
    backend: ^Fake_Terminal_Backend, text: string) -> bool {
    if backend == nil || len(text) > len(backend.output) {
        return false
    }
    copy(backend.output[:], transmute([]u8)text)
    backend.output_count = len(text)
    return true
}

//   Configure one fully reconciled exit for the next service update.
//
// Side effects:
//   - Replaces the configured exit and marks process exit and output drain complete.
fake_terminal_backend_finish :: proc(
    backend: ^Fake_Terminal_Backend, exit: Backend_Exit) {
    backend.exit = exit
    backend.process_exited = true
    backend.output_drained = true
}