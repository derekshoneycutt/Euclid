package core

import "../core/protocol"
import termsession "../terminal/session"

SHELL_SESSION_OWNER_ID :: u64(1)
SHELL_TERMINFO_NAME :: "euclid"
SHELL_TERMINFO_RELATIVE_DIRECTORY :: "assets/terminfo"

// Lifecycle of one foreground shell submission.
Shell_Launch_Phase :: enum u8 {
    Inactive,
    Running,
}

// Display-owned native shell service and one bounded foreground transaction.
Shell_Runtime :: struct {
    backend: termsession.Native_Terminal_Backend,
    session: termsession.Terminal_Session_Manager,
    phase: Shell_Launch_Phase,
    request_id: protocol.Request_Id,
    operation_id: termsession.Terminal_Session_Operation_Id,
    working_directory:
        [termsession.PROCESS_PLAN_WORKING_DIRECTORY_MAX_BYTES]u8,
    working_directory_byte_count: int,
    terminfo_directory:
        [termsession.PROCESS_PLAN_WORKING_DIRECTORY_MAX_BYTES]u8,
    terminfo_directory_byte_count: int,
}

// Return the absolute cwd snapshot owned by the shell runtime.
shell_working_directory :: proc(runtime: ^Shell_Runtime) -> string {
    if runtime == nil || runtime.working_directory_byte_count <= 0 ||
       runtime.working_directory_byte_count > len(runtime.working_directory) {
        return ""
    }
    return string(
        runtime.working_directory[:runtime.working_directory_byte_count])
}

// Return the absolute packaged terminfo directory captured at shell startup.
shell_terminfo_directory :: proc(runtime: ^Shell_Runtime) -> string {
    if runtime == nil || runtime.terminfo_directory_byte_count <= 0 {
        return ""
    }
    return string(runtime.terminfo_directory[:runtime.terminfo_directory_byte_count])
}