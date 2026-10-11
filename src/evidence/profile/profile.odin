package profile

// Package profile provides optional timing evidence that never defines correctness.

import spall "core:prof/spall"

PROFILE_BUFFER_BYTES :: 64 * 1024

// Timing implementation selected for one producer-owned profiler state.
Backend :: enum u8 {
    None,
    Spall,
}

// Per-thread timing state with fixed inline Spall buffering.
//
// A live state is owned by one producer thread and must remain at a stable address
// because spall_buffer references buffer_storage. Separate producers require separate
// states and output streams.
State :: struct {
    // Active facade implementation; None makes every recording operation a no-op.
    backend : Backend,

    // Spall file context and buffered writer initialized together for one stream.
    spall_context : spall.Context,
    spall_buffer : spall.Buffer,

    // Fixed producer-local storage that keeps event buffering off general allocators.
    buffer_storage : [PROFILE_BUFFER_BYTES]byte,

    // Number of begun zones not yet ended by this producer.
    zone_depth : int,
}

//   Reset profiling to the disabled no-op backend.
//
// Parameters:
//   - state: Non-nil destination that is not currently owning an active backend.
//
// Side effects:
//   - Clears all backend resources and zone accounting from the state value.
//
// Notes:
//   - Destroy an active Spall backend before resetting it so its stream is flushed.
init_none :: proc(state: ^State) {
    state^ = {}
}

//   Open a Spall stream using caller-owned per-thread buffer storage.
//
// Parameters:
//   - state: Non-nil, inactive destination that will own the stream and buffer.
//   - path: Output file opened by the Spall context.
//
// Returns:
//   - True after the stream and buffer are ready; false with no active backend.
//
// Side effects:
//   - Clears state, opens the output stream, and binds its writer to inline storage.
//
// Notes:
//   - On buffer initialization failure, the newly opened context is closed before return.
//   - The state must remain address-stable and be used only by its producer thread.
init_spall :: proc(state: ^State, path: string) -> bool {
    state^ = {}
    spall_context, context_ok := spall.context_create_with_scale(path, false, 1)
    if !context_ok {
        return false
    }
    spall_buffer, buffer_ok := spall.buffer_create(state.buffer_storage[:])
    if !buffer_ok {
        spall.context_destroy(&spall_context)
        return false
    }
    state.spall_context = spall_context
    state.spall_buffer = spall_buffer
    state.backend = .Spall
    return true
}

//   Flush and close the selected backend; no-op state needs no cleanup.
//
// Parameters:
//   - state: Producer-owned profiler state; nil is accepted as already destroyed.
//
// Side effects:
//   - Closes unmatched zones, flushes and destroys Spall resources, then clears state.
//
// Notes:
//   - Destruction must run on the state owner after its final recording operation.
destroy :: proc(state: ^State) {
    if state == nil {
        return
    }
    if state.backend == .Spall {
        for state.zone_depth > 0 {
            spall._buffer_end(&state.spall_context, &state.spall_buffer)
            state.zone_depth -= 1
        }
        spall.buffer_destroy(&state.spall_context, &state.spall_buffer)
        spall.context_destroy(&state.spall_context)
    }
    state^ = {}
}

//   Begin one static-name timing zone when profiling is enabled.
//
// Parameters:
//   - state: Producer-owned profiler state; nil or disabled state is accepted.
//   - name: Stable zone label written to the active timing stream.
//
// Side effects:
//   - Appends a begin event and increments unmatched-zone depth for Spall.
zone_begin :: proc(state: ^State, name: string) {
    if state == nil || state.backend != .Spall {
        return
    }
    spall._buffer_begin(&state.spall_context, &state.spall_buffer, name)
    state.zone_depth += 1
}

//   End the innermost timing zone when profiling is enabled.
//
// Parameters:
//   - state: Producer-owned profiler state; nil or disabled state is accepted.
//
// Side effects:
//   - Appends an end event and decrements unmatched-zone depth when a zone is open.
//
// Notes:
//   - An unmatched end is ignored so optional instrumentation remains nonfatal.
zone_end :: proc(state: ^State) {
    if state == nil || state.backend != .Spall || state.zone_depth == 0 {
        return
    }
    spall._buffer_end(&state.spall_context, &state.spall_buffer)
    state.zone_depth -= 1
}

//   Name the current producer thread in the active Spall stream.
//
// Parameters:
//   - state: Producer-owned profiler state; nil or disabled state is accepted.
//   - name: Stable display name for the calling producer thread.
//
// Side effects:
//   - Appends thread-name metadata when Spall is active.
thread_name :: proc(state: ^State, name: string) {
    if state == nil || state.backend != .Spall {
        return
    }
    spall._buffer_name_thread(&state.spall_context, &state.spall_buffer, name)
}

//   Mark one frame as a zero-duration static-name occurrence.
//
// Parameters:
//   - state: Producer-owned profiler state; nil or disabled state is accepted.
//
// Side effects:
//   - Emits a balanced zone named "frame" when timing capture is active.
frame :: proc(state: ^State) {
    zone_begin(state, "frame")
    zone_end(state)
}

//   Record a static diagnostic marker when the backend supports timing events.
//
// Parameters:
//   - state: Producer-owned profiler state; nil or disabled state is accepted.
//   - name: Stable label represented as a zero-duration timing zone.
//
// Side effects:
//   - Emits one balanced named zone when timing capture is active.
message :: proc(state: ^State, name: string) {
    zone_begin(state, name)
    zone_end(state)
}

//   Accept a scalar counter without affecting runtime behavior.
//
// Parameters:
//   - state: Profiler state reserved for a backend that supports counters.
//   - name: Stable counter identity.
//   - value: Scalar sample associated with the counter.
//
// Notes:
//   - Spall v1 has no counter record, so this common facade operation is a no-op.
counter :: proc(_: ^State, _: string, _: i64) {}
