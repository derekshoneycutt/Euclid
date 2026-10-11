package termsession

import protocol "../../core/protocol"

// Maximum output bytes returned by one session-manager update.
TERMINAL_SESSION_OUTPUT_MAX_BYTES :: 8 * 1024

// Maximum input bytes carried by one session input request.
TERMINAL_SESSION_INPUT_MAX_BYTES :: 256

// Maximum application-lived cleanup records retained after session transfer.
PROCESS_CLEANUP_REGISTRY_CAPACITY :: 4

// Fixed aligned opaque storage available to one platform cleanup record.
PROCESS_CLEANUP_TOKEN_WORDS :: 32

// Shared pseudoterminal viewport dimensions owned by the protocol boundary.
Terminal_Dimensions :: protocol.Terminal_Dimensions

// Result of acquiring all resources needed for one backend operation.
Backend_Start_Status :: enum u8 {
    Started,
    Executable_Not_Found,
    Resource_Unavailable,
    Internal_Failure,
}

// Mechanism-level classification of one fully reconciled process exit.
Backend_Exit_Kind :: enum u8 {
    Exited,
    Signalled,
    Infrastructure_Failure,
}

// Final backend outcome after the process exits and output reaches EOF.
Backend_Exit :: struct {
    kind: Backend_Exit_Kind,
    status: i32,
}

// Independently observed process and output reconciliation state.
Backend_Exit_Progress :: struct {
    exit: Backend_Exit,
    process_exited: bool,
    output_drained: bool,
}

// Lifecycle of one application-owned platform cleanup responsibility.
Process_Cleanup_Status :: enum u8 {
    Pending,
    Complete,
    Incomplete,
}

// Advance or release one opaque platform cleanup token without blocking.
Process_Cleanup_Handler :: proc(entry: ^Process_Cleanup_Entry) -> bool

// Fixed application-lived record for OS state transferred from one session backend.
Process_Cleanup_Entry :: struct {
    generation: u64,
    status: Process_Cleanup_Status,
    poll: Process_Cleanup_Handler,
    release: Process_Cleanup_Handler,
    token: [PROCESS_CLEANUP_TOKEN_WORDS]u64,
}

// Bounded owner of platform state that outlives a terminal-session generation.
Process_Cleanup_Registry :: struct {
    entries: [PROCESS_CLEANUP_REGISTRY_CAPACITY]Process_Cleanup_Entry,
    entry_count: int,
}

// Start one process from a validated owned plan and positive viewport dimensions.
Terminal_Backend_Start_Handler :: proc(
    user_data: rawptr, plan: ^Process_Plan,
    dimensions: Terminal_Dimensions) -> Backend_Start_Status

// Copy currently available output without blocking and return bytes written.
Terminal_Backend_Poll_Output_Handler :: proc(
    user_data: rawptr, destination: []u8) -> int

// Accept one bounded input fragment without retaining the caller's slice.
Terminal_Backend_Write_Input_Handler :: proc(
    user_data: rawptr, bytes: []u8) -> bool

// Apply positive character dimensions to one active pseudoterminal.
Terminal_Backend_Resize_Handler :: proc(
    user_data: rawptr, dimensions: Terminal_Dimensions) -> bool

// Request an interrupt from the active foreground process group.
Terminal_Backend_Request_Handler :: proc(user_data: rawptr) -> bool

// Report a final exit only after all process output has become pollable or drained.
Terminal_Backend_Poll_Exit_Handler :: proc(
    user_data: rawptr) -> Backend_Exit_Progress

// Release resources for the active or partially started backend operation.
Terminal_Backend_Close_Handler :: proc(user_data: rawptr)

// Transfer unreconciled platform state into application-owned fixed storage.
Terminal_Backend_Transfer_Handler :: proc(
    user_data: rawptr, registry: ^Process_Cleanup_Registry,
    generation: u64) -> bool

// Pluggable single-operation pseudoterminal mechanism contract.
//
// `user_data` owns implementation state and must outlive this table. Calls are
// serialized by the session manager. A successful start is paired with exactly one
// close after final exit reconciliation or manager destruction.
Terminal_Process_Backend :: struct {
    user_data: rawptr,
    start: Terminal_Backend_Start_Handler,
    resize: Terminal_Backend_Resize_Handler,
    poll_output: Terminal_Backend_Poll_Output_Handler,
    write_input: Terminal_Backend_Write_Input_Handler,
    request_interrupt: Terminal_Backend_Request_Handler,
    request_terminate: Terminal_Backend_Request_Handler,
    force_terminate: Terminal_Backend_Request_Handler,
    poll_exit: Terminal_Backend_Poll_Exit_Handler,
    transfer: Terminal_Backend_Transfer_Handler,
    close: Terminal_Backend_Close_Handler,
}

//   Return whether a backend table implements the complete mechanism contract.
//
// Parameters:
//   - backend: Candidate implementation table.
//
// Returns:
//   - True when user state and every required operation are non-nil.
terminal_process_backend_valid :: proc(backend: Terminal_Process_Backend) -> bool {
    return backend.user_data != nil && backend.start != nil &&
        backend.resize != nil && backend.poll_output != nil &&
        backend.write_input != nil &&
        backend.request_interrupt != nil && backend.request_terminate != nil &&
        backend.force_terminate != nil && backend.poll_exit != nil &&
        backend.transfer != nil && backend.close != nil
}

//   Reserve one fixed cleanup entry for a transferred session generation.
//
// Returns:
//   - A reset new or completed entry, or nil when the registry is absent or full.
process_cleanup_registry_reserve :: proc(
    registry: ^Process_Cleanup_Registry,
    generation: u64) -> ^Process_Cleanup_Entry {
    if registry == nil || generation == 0 {
        return nil
    }
    for index in 0..<registry.entry_count {
        entry := &registry.entries[index]
        if entry.status == .Complete {
            entry^ = {generation = generation, status = .Pending}
            return entry
        }
    }
    if registry.entry_count >= len(registry.entries) {
        return nil
    }
    entry := &registry.entries[registry.entry_count]
    entry^ = {generation = generation, status = .Pending}
    registry.entry_count += 1
    return entry
}

//   Poll every pending cleanup record once without blocking.
process_cleanup_registry_update :: proc(registry: ^Process_Cleanup_Registry) {
    if registry == nil {
        return
    }
    for index in 0..<registry.entry_count {
        entry := &registry.entries[index]
        if entry.status == .Pending && entry.poll != nil && entry.poll(entry) {
            entry.status = .Complete
        }
    }
}

//   Release every retained cleanup token and report unfinished records.
process_cleanup_registry_destroy :: proc(registry: ^Process_Cleanup_Registry) {
    if registry == nil {
        return
    }
    for index in 0..<registry.entry_count {
        entry := &registry.entries[index]
        if entry.status == .Pending {
            entry.status = .Incomplete
        }
        if entry.release != nil {
            entry.release(entry)
        }
    }
    registry^ = {}
}
