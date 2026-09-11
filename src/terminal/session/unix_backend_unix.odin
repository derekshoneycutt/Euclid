#+build linux, darwin
package termsession

import "core:c"
import vmem "core:mem/virtual"
import "core:strings"
import "core:sys/posix"

// Bytes in the sole per-session Linux native-string workspace.
UNIX_TERMINAL_WORKSPACE_BYTES :: 192 * 1024

// Virtual storage reserved once for the reusable workspace plus alignment.
UNIX_TERMINAL_WORKSPACE_ARENA_SIZE :: 256 * 1024

// Maximum effective child environment entries, excluding the trailing nil pointer.
UNIX_TERMINAL_ENVIRONMENT_CAPACITY :: 1024

// Maximum input bytes retained while the nonblocking PTY is backpressured.
UNIX_TERMINAL_INPUT_CAPACITY :: 8 * 1024

// Maximum bytes in one executable path candidate including its NUL terminator.
UNIX_TERMINAL_PATH_MAX_BYTES :: 4 * 1024

// Native `winsize` layout passed to `forkpty`; character dimensions are authoritative.
Unix_Winsize :: struct {
    rows: u16,
    columns: u16,
    x_pixels: u16,
    y_pixels: u16,
}

#assert(size_of(Unix_Winsize) == 8)

when ODIN_OS == .Linux {
    // Linux request from asm-generic/ioctls.h.
    UNIX_TIOCSWINSZ :: c.ulong(0x5414)
} else when ODIN_OS == .Darwin {
    // Darwin request from _IOW('t', 103, struct winsize) in sys/ttycom.h.
    UNIX_TIOCSWINSZ :: c.ulong(0x80087467)
}

// Unix-owned state for one foreground PTY process and its launch workspace.
//
// The backend is driven serially by the session owner. One per-session workspace
// owns every C string passed across `forkpty`; it remains alive through child launch
// and is released by close or failed-start rollback.
Unix_Terminal_Backend :: struct {
    // Reusable native launch storage owned for the backend lifetime.
    workspace_arena: vmem.Arena,
    workspace_arena_initialized: bool,
    workspace_storage: []u8,
    workspace: []u8,
    workspace_used: int,

    // NUL-terminated argv/environment tables and resolved launch strings.
    arguments: [PROCESS_PLAN_ARGUMENT_CAPACITY + 1]cstring,
    environment: [UNIX_TERMINAL_ENVIRONMENT_CAPACITY + 1]cstring,
    environment_count: int,
    executable: cstring,
    working_directory: cstring,

    // Active PTY endpoint and child process-group leader.
    master: posix.FD,
    child: posix.pid_t,

    // Input retained until the nonblocking PTY accepts it.
    input: [UNIX_TERMINAL_INPUT_CAPACITY]u8,
    input_count: int,

    // Exit/EOF reconciliation; completion requires both observations.
    child_exited: bool,
    output_eof: bool,
    exit: Backend_Exit,
    active: bool,
}

// Application-lived cleanup token for one transferred Unix process and PTY.
Unix_Process_Cleanup_Token :: struct {
    child: posix.pid_t,
    master: posix.FD,
    child_reaped: bool,
    output_eof: bool,
}

//   Borrow the Unix token stored inline in one cleanup registry entry.
unix_process_cleanup_token :: proc(
    entry: ^Process_Cleanup_Entry) -> ^Unix_Process_Cleanup_Token {
    return (^Unix_Process_Cleanup_Token)(raw_data(entry.token[:]))
}

//   Drain PTY output and poll child reaping once without blocking.
//
// Returns:
//   - True after both the child and PTY endpoint are reconciled.
unix_process_cleanup_poll :: proc(entry: ^Process_Cleanup_Entry) -> bool {
    token := unix_process_cleanup_token(entry)
    if !token.child_reaped && token.child > 0 {
        status: c.int
        result := posix.waitpid(token.child, &status, {.NOHANG})
        token.child_reaped = result == token.child ||
            (result == posix.pid_t(-1) && posix.errno() != .EINTR)
    }
    if !token.output_eof && token.master != posix.FD(-1) {
        buffer: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
        count := posix.read(
            token.master, raw_data(buffer[:]), c.size_t(len(buffer)))
        token.output_eof = count == 0 ||
            (count < 0 && posix.errno() == .EIO)
    }
    if token.child_reaped && token.output_eof {
        if token.master != posix.FD(-1) {
            posix.close(token.master)
            token.master = posix.FD(-1)
        }
        return true
    }
    return false
}

//   Force-signal and release one transferred Unix cleanup token without waiting.
//
// Returns:
//   - True after local descriptor ownership is released.
unix_process_cleanup_release :: proc(entry: ^Process_Cleanup_Entry) -> bool {
    token := unix_process_cleanup_token(entry)
    if !token.child_reaped && token.child > 0 {
        posix.kill(-token.child, .SIGKILL)
        status: c.int
        posix.waitpid(token.child, &status, {.NOHANG})
    }
    if token.master != posix.FD(-1) {
        posix.close(token.master)
    }
    token^ = {master = posix.FD(-1)}
    return true
}

foreign import unix_libc "system:c"

foreign unix_libc {
    // Create a controlling PTY and child session using parent-prepared launch state.
    @(link_name="forkpty")
    unix_forkpty :: proc(
        master: ^c.int, name: [^]c.char, terminal: rawptr,
        dimensions: ^Unix_Winsize) -> posix.pid_t ---
    when ODIN_OS == .Darwin {
        @(link_name="ioctl")
        unix_ioctl :: proc(
            descriptor: c.int, request: c.ulong,
            #c_vararg arguments: ..any) -> c.int ---
    } else {
        @(link_name="ioctl")
        unix_ioctl :: proc(
            descriptor: c.int, request: c.ulong, argument: rawptr) -> c.int ---
    }
}

//   Initialize an idle Unix backend with one reusable native workspace.
//
// Returns:
//   - True after initialization; false for nil state or unavailable VM storage.
//
// Side effects:
//   - Resets backend state and establishes `-1` as the closed PTY descriptor sentinel.
unix_terminal_backend_init :: proc(
    backend: ^Unix_Terminal_Backend) -> bool {
    if backend == nil {
        return false
    }
    backend^ = {master = posix.FD(-1)}
    arena_error := vmem.arena_init_static(
        &backend.workspace_arena, UNIX_TERMINAL_WORKSPACE_ARENA_SIZE,
        UNIX_TERMINAL_WORKSPACE_ARENA_SIZE)
    if arena_error != nil {
        return false
    }
    allocator := vmem.arena_allocator(&backend.workspace_arena)
    storage, storage_error := make(
        []u8, UNIX_TERMINAL_WORKSPACE_BYTES, allocator)
    if storage_error != nil {
        vmem.arena_destroy(&backend.workspace_arena)
        backend^ = {master = posix.FD(-1)}
        return false
    }
    backend.workspace_arena_initialized = true
    backend.workspace_storage = storage
    return true
}

//   Release the sole workspace allocation and reset transient launch storage.
//
// Side effects:
//   - Invalidates all argv, environment, executable, and cwd pointers into workspace.
unix_terminal_backend_release_workspace :: proc(backend: ^Unix_Terminal_Backend) {
    backend.workspace = nil
    backend.workspace_used = 0
    backend.arguments = {}
    backend.environment = {}
    backend.environment_count = 0
    backend.executable = nil
    backend.working_directory = nil
}

//   Copy one string into the session workspace with a native NUL terminator.
//
// Returns:
//   - Stable workspace-backed C string and true, or nil and false when full.
//
// Side effects:
//   - Advances workspace usage only after capacity is known to be sufficient.
unix_terminal_workspace_string :: proc(
    backend: ^Unix_Terminal_Backend, text: string) -> (cstring, bool) {
    end := backend.workspace_used + len(text) + 1
    if end > len(backend.workspace) {
        return nil, false
    }
    start := backend.workspace_used
    copy(backend.workspace[start:end - 1], transmute([]u8)text)
    backend.workspace[end - 1] = 0
    backend.workspace_used = end
    return cstring(&backend.workspace[start]), true
}

//   Return whether one native `key=value` entry has the exact requested key.
unix_terminal_environment_key_matches :: proc(entry: string, key: string) -> bool {
    separator := strings.index_byte(entry, '=')
    return separator == len(key) && separator >= 0 && entry[:separator] == key
}

//   Return whether any plan mutation replaces or removes an inherited key.
unix_terminal_environment_overridden :: proc(
    plan: ^Process_Plan, entry: string) -> bool {
    for index in 0..<plan.environment_count {
        change, valid := process_plan_environment_change(plan, index)
        if valid && unix_terminal_environment_key_matches(entry, change.key) {
            return true
        }
    }
    return false
}

//   Return whether a later plan mutation supersedes the indexed key.
//
// Notes:
//   - Last mutation wins when a plan contains duplicate environment keys.
unix_terminal_environment_change_superseded :: proc(
    plan: ^Process_Plan, index: int, key: string) -> bool {
    for later in index + 1..<plan.environment_count {
        change, valid := process_plan_environment_change(plan, later)
        if valid && change.key == key {
            return true
        }
    }
    return false
}

//   Append one native environment entry to the fixed table and workspace.
//
// Returns:
//   - True after copying and maintaining the trailing nil pointer; false when full.
unix_terminal_append_environment :: proc(
    backend: ^Unix_Terminal_Backend, entry: string) -> bool {
    if backend.environment_count >= UNIX_TERMINAL_ENVIRONMENT_CAPACITY {
        return false
    }
    copied, valid := unix_terminal_workspace_string(backend, entry)
    if !valid {
        return false
    }
    backend.environment[backend.environment_count] = copied
    backend.environment_count += 1
    backend.environment[backend.environment_count] = nil
    return true
}

//   Append one `key=value` entry without temporary concatenation.
//
// Returns:
//   - True after atomic capacity checks and commit; false without mutation when full.
unix_terminal_append_environment_change :: proc(
    backend: ^Unix_Terminal_Backend, key, value: string) -> bool {
    if backend.environment_count >= UNIX_TERMINAL_ENVIRONMENT_CAPACITY {
        return false
    }
    byte_count := len(key) + 1 + len(value)
    end := backend.workspace_used + byte_count + 1
    if end > len(backend.workspace) {
        return false
    }
    start := backend.workspace_used
    copy(backend.workspace[start:], key)
    backend.workspace[start + len(key)] = '='
    copy(backend.workspace[start + len(key) + 1:], value)
    backend.workspace[end - 1] = 0
    backend.environment[backend.environment_count] =
        cstring(&backend.workspace[start])
    backend.environment_count += 1
    backend.environment[backend.environment_count] = nil
    backend.workspace_used = end
    return true
}

//   Freeze the effective child environment before acquiring OS resources.
//
// Notes:
//   - Inherited entries overridden by any plan mutation are omitted; surviving `.Set`
//     mutations are appended with last mutation winning, while `.Unset` emits nothing.
//
// Returns:
//   - True after constructing a nil-terminated native environment table.
unix_terminal_build_environment :: proc(
    backend: ^Unix_Terminal_Backend, plan: ^Process_Plan) -> bool {
    if plan.inherit_environment {
        for index := 0; posix.environ[index] != nil; index += 1 {
            entry := string(posix.environ[index])
            if unix_terminal_environment_overridden(plan, entry) {
                continue
            }
            if !unix_terminal_append_environment(backend, entry) {
                return false
            }
        }
    }
    for index in 0..<plan.environment_count {
        change, valid := process_plan_environment_change(plan, index)
        if !valid || change.kind == .Unset ||
           unix_terminal_environment_change_superseded(plan, index, change.key) {
            continue
        }
        if !unix_terminal_append_environment_change(
            backend, change.key, change.value) {
            return false
        }
    }
    return true
}

//   Freeze argv and cwd into the per-session native workspace.
//
// Returns:
//   - True after constructing nil-terminated argv and stable cwd; false when full.
unix_terminal_build_arguments :: proc(
    backend: ^Unix_Terminal_Backend, plan: ^Process_Plan) -> bool {
    for index in 0..<plan.argument_count {
        argument, valid := unix_terminal_workspace_string(
            backend, process_plan_argument(plan, index))
        if !valid {
            return false
        }
        backend.arguments[index] = argument
    }
    backend.arguments[plan.argument_count] = nil
    cwd, valid := unix_terminal_workspace_string(
        backend, process_plan_working_directory(plan))
    if !valid {
        return false
    }
    backend.working_directory = cwd
    return true
}

//   Return PATH from the completed child environment.
//
// Returns:
//   - Borrowed value after `PATH=`, or `/bin:/usr/bin` when no entry survives.
unix_terminal_environment_path :: proc(backend: ^Unix_Terminal_Backend) -> string {
    for index in 0..<backend.environment_count {
        entry := string(backend.environment[index])
        if unix_terminal_environment_key_matches(entry, "PATH") {
            return entry[len("PATH="):]
        }
    }
    return "/bin:/usr/bin"
}

//   Test one executable candidate and retain its absolute launch path on success.
//
// Notes:
//   - Relative candidates are resolved against the planned working directory.
//
// Returns:
//   - True when `access(X_OK)` succeeds and the path fits remaining workspace.
unix_terminal_try_executable :: proc(
    backend: ^Unix_Terminal_Backend, candidate: string) -> bool {
    if len(candidate) == 0 {
        return false
    }
    buffer: [UNIX_TERMINAL_PATH_MAX_BYTES]u8
    path := candidate
    if candidate[0] != '/' {
        cwd := string(backend.working_directory)
        count := len(cwd) + 1 + len(candidate)
        if count >= len(buffer) {
            return false
        }
        copy(buffer[:], cwd)
        buffer[len(cwd)] = '/'
        copy(buffer[len(cwd) + 1:], candidate)
        path = string(buffer[:count])
    }
    if len(path) >= len(buffer) {
        return false
    }
    copy(buffer[:], path)
    buffer[len(path)] = 0
    if posix.access(cstring(&buffer[0]), {.X_OK}) != .OK {
        return false
    }
    executable, valid := unix_terminal_workspace_string(backend, path)
    if valid {
        backend.executable = executable
    }
    return valid
}

//   Resolve a direct executable against the effective child PATH.
//
// Returns:
//   - True after retaining an executable path; false when no candidate is executable.
unix_terminal_resolve_executable :: proc(
    backend: ^Unix_Terminal_Backend, executable: string) -> bool {
    if strings.index_byte(executable, '/') >= 0 {
        return unix_terminal_try_executable(backend, executable)
    }
    path := unix_terminal_environment_path(backend)
    remaining := path
    for {
        separator := strings.index_byte(remaining, ':')
        directory := remaining
        if separator >= 0 {
            directory = remaining[:separator]
        }
        if len(directory) == 0 {
            directory = "."
        }
        candidate_bytes: [UNIX_TERMINAL_PATH_MAX_BYTES]u8
        candidate_count := len(directory) + 1 + len(executable)
        if candidate_count < len(candidate_bytes) {
            copy(candidate_bytes[:], directory)
            candidate_bytes[len(directory)] = '/'
            copy(candidate_bytes[len(directory) + 1:], executable)
        }
        if candidate_count < len(candidate_bytes) && unix_terminal_try_executable(
            backend, string(candidate_bytes[:candidate_count])) {
            return true
        }
        if separator < 0 {
            return false
        }
        remaining = remaining[separator + 1:]
    }
}

//   Roll back a child that cannot be admitted after `forkpty` succeeds.
//
// Side effects:
//   - Kills the entire child process group, synchronously reaps its leader, closes the
//     PTY master, and releases launch workspace.
unix_terminal_abort_child :: proc(
    backend: ^Unix_Terminal_Backend, child: posix.pid_t, master: posix.FD) {
    posix.kill(-child, .SIGKILL)
    status: c.int
    for {
        result := posix.waitpid(child, &status, {})
        if result == child || (result == posix.pid_t(-1) && posix.errno() != .EINTR) {
            break
        }
    }
    posix.close(master)
    unix_terminal_backend_release_workspace(backend)
}

//   Prepare every workspace-backed launch value before `forkpty`.
//
// Returns:
//   - `.Started` when native argv, environment, cwd, and executable are ready;
//     otherwise a precise pre-fork resource or discovery failure.
//
// Side effects:
//   - Borrows the reusable backend workspace and rolls it back on failure.
unix_terminal_prepare_launch :: proc(
    backend: ^Unix_Terminal_Backend, plan: ^Process_Plan) -> Backend_Start_Status {
    if len(backend.workspace_storage) != UNIX_TERMINAL_WORKSPACE_BYTES {
        return .Resource_Unavailable
    }
    backend.workspace = backend.workspace_storage
    if !unix_terminal_build_arguments(backend, plan) ||
       !unix_terminal_build_environment(backend, plan) {
        unix_terminal_backend_release_workspace(backend)
        return .Resource_Unavailable
    }
    if !unix_terminal_resolve_executable(
        backend, process_plan_argument(plan, 0)) {
        unix_terminal_backend_release_workspace(backend)
        return .Executable_Not_Found
    }
    return .Started
}

//   Configure and register the parent's nonblocking PTY master after fork.
//
// Returns:
//   - `.Started` after activating parent state; `.Internal_Failure` after full rollback.
unix_terminal_register_parent :: proc(
    backend: ^Unix_Terminal_Backend, child: posix.pid_t,
    master: posix.FD) -> Backend_Start_Status {
    flags := posix.fcntl(master, .GETFL)
    if flags < 0 || posix.fcntl(
        master, .SETFL, flags | c.int(posix.O_Flags{.NONBLOCK})) < 0 {
        unix_terminal_abort_child(backend, child, master)
        return .Internal_Failure
    }
    backend.master = master
    backend.child = child
    backend.active = true
    return .Started
}

//   Enter the prepared directory and replace the forked child with its executable.
//
// Side effects:
//   - Never returns; exits with 126 for directory failure or 127 for exec failure.
unix_terminal_exec_child :: proc(
    backend: ^Unix_Terminal_Backend, directory: posix.FD) {
    if posix.fchdir(directory) != .OK {
        posix._exit(126)
    }
    posix.close(directory)
    posix.execve(
        backend.executable, &backend.arguments[0], &backend.environment[0])
    posix._exit(127)
}

//   Start one child attached to a fixed-size pseudoterminal.
//
// Parameters:
//   - user_data: Initialized idle `^Unix_Terminal_Backend`.
//   - plan: Canonically validated owned process plan.
//   - dimensions: Positive initial PTY character dimensions.
//
// Returns:
//   - Backend start status after complete parent registration or rollback.
//
// Side effects:
//   - Resolves launch state before fork, creates a child session/process group, changes
//     child cwd, calls `execve`, and retains a nonblocking parent PTY master.
unix_terminal_backend_start :: proc(
    user_data: rawptr, plan: ^Process_Plan,
    dimensions: Terminal_Dimensions) -> Backend_Start_Status {
    backend := (^Unix_Terminal_Backend)(user_data)
    if backend == nil || backend.active || len(backend.workspace) != 0 {
        return .Internal_Failure
    }
    if status := unix_terminal_prepare_launch(backend, plan); status != .Started {
        return status
    }
    directory := posix.open(backend.working_directory, {.DIRECTORY})
    if directory == posix.FD(-1) {
        unix_terminal_backend_release_workspace(backend)
        return .Resource_Unavailable
    }
    window := Unix_Winsize{
        rows = dimensions.rows,
        columns = dimensions.columns,
    }
    master: c.int
    child := unix_forkpty(&master, nil, nil, &window)
    if child == posix.pid_t(-1) {
        posix.close(directory)
        unix_terminal_backend_release_workspace(backend)
        return .Resource_Unavailable
    }
    if child == 0 {
        unix_terminal_exec_child(backend, directory)
    }
    posix.close(directory)
    return unix_terminal_register_parent(backend, child, posix.FD(master))
}

//   Apply character dimensions to the active PTY and notify its foreground group.
unix_terminal_backend_resize :: proc(
    user_data: rawptr, dimensions: Terminal_Dimensions) -> bool {
    backend := (^Unix_Terminal_Backend)(user_data)
    if backend == nil || !backend.active || backend.master < 0 ||
        dimensions.columns == 0 || dimensions.rows == 0 {
        return false
    }
    size := Unix_Winsize{
        rows = dimensions.rows,
        columns = dimensions.columns,
    }
    return unix_ioctl(c.int(backend.master), UNIX_TIOCSWINSZ, &size) == 0
}

//   Flush as much queued input as the nonblocking PTY currently accepts.
//
// Returns:
//   - True when input is drained or temporarily backpressured; false on terminal I/O failure.
//
// Side effects:
//   - Removes each successfully written prefix from the bounded input queue.
unix_terminal_backend_flush_input :: proc(backend: ^Unix_Terminal_Backend) -> bool {
    for backend.input_count > 0 {
        written := posix.write(
            backend.master, &backend.input[0], c.size_t(backend.input_count))
        if written > 0 {
            count := int(written)
            for index in 0..<backend.input_count - count {
                backend.input[index] = backend.input[index + count]
            }
            backend.input_count -= count
            continue
        }
        if written < 0 &&
           (posix.errno() == .EAGAIN || posix.errno() == .EWOULDBLOCK ||
            posix.errno() == .EINTR) {
            return true
        }
        return false
    }
    return true
}

//   Poll one bounded output fragment without blocking the display owner.
//
// Returns:
//   - Number of bytes read into destination, or zero when unavailable/finished.
//
// Side effects:
//   - Opportunistically flushes input and records PTY EOF on zero, `EIO`, or fatal
//     input failure. Retryable read errors leave state active.
unix_terminal_backend_poll_output :: proc(
    user_data: rawptr, destination: []u8) -> int {
    backend := (^Unix_Terminal_Backend)(user_data)
    if backend == nil || !backend.active || backend.output_eof ||
       len(destination) == 0 {
        return 0
    }
    if !unix_terminal_backend_flush_input(backend) {
        backend.output_eof = true
        return 0
    }
    count := posix.read(backend.master, raw_data(destination), c.size_t(len(destination)))
    if count > 0 {
        return int(count)
    }
    if count == 0 || (count < 0 && posix.errno() == .EIO) {
        backend.output_eof = true
    }
    return 0
}

//   Queue bounded input and opportunistically write it to the PTY master.
//
// Returns:
//   - True when all bytes are accepted into backend custody; false for inactive/EOF,
//     capacity exhaustion, or fatal PTY write failure.
unix_terminal_backend_write_input :: proc(
    user_data: rawptr, bytes: []u8) -> bool {
    backend := (^Unix_Terminal_Backend)(user_data)
    if backend == nil || !backend.active || backend.output_eof ||
       backend.input_count + len(bytes) > len(backend.input) {
        return false
    }
    copy(backend.input[backend.input_count:], bytes)
    backend.input_count += len(bytes)
    return unix_terminal_backend_flush_input(backend)
}

//   Deliver one POSIX signal to the entire `forkpty` process group.
//
// Returns:
//   - True when `kill(-child, signal)` succeeds for an active backend.
unix_terminal_backend_signal :: proc(
    backend: ^Unix_Terminal_Backend, signal: posix.Signal) -> bool {
    return backend != nil && backend.active &&
        posix.kill(-backend.child, signal) == .OK
}

//   Request terminal-style `SIGINT` interruption of the foreground process group.
unix_terminal_backend_request_interrupt :: proc(user_data: rawptr) -> bool {
    return unix_terminal_backend_signal(
        (^Unix_Terminal_Backend)(user_data), .SIGINT)
}

//   Request graceful `SIGTERM` termination of the foreground process group.
unix_terminal_backend_request_terminate :: proc(user_data: rawptr) -> bool {
    return unix_terminal_backend_signal(
        (^Unix_Terminal_Backend)(user_data), .SIGTERM)
}

//   Force `SIGKILL` termination after graceful policy expires.
unix_terminal_backend_force_terminate :: proc(user_data: rawptr) -> bool {
    return unix_terminal_backend_signal(
        (^Unix_Terminal_Backend)(user_data), .SIGKILL)
}

//   Poll child status while withholding completion until final PTY EOF.
//
// Returns:
//   - Reconciled exit and true only after both child reaping and output EOF; otherwise
//     the current partial exit state and false.
//
// Side effects:
//   - Performs nonblocking `waitpid` once per update until exit is captured.
unix_terminal_backend_poll_exit :: proc(
    user_data: rawptr) -> Backend_Exit_Progress {
    backend := (^Unix_Terminal_Backend)(user_data)
    if backend == nil || !backend.active {
        return {}
    }
    if !backend.child_exited {
        status: c.int
        result := posix.waitpid(backend.child, &status, {.NOHANG})
        if result == backend.child {
            backend.child_exited = true
            if posix.WIFEXITED(status) {
                backend.exit = {
                    kind = .Exited,
                    status = i32(posix.WEXITSTATUS(status)),
                }
            } else if posix.WIFSIGNALED(status) {
                backend.exit = {
                    kind = .Signalled,
                    status = i32(posix.WTERMSIG(status)),
                }
            } else {
                backend.exit = {kind = .Infrastructure_Failure}
            }
        } else if result == posix.pid_t(-1) && posix.errno() != .EINTR {
            backend.child_exited = true
            backend.exit = {kind = .Infrastructure_Failure}
        }
    }
    return {
        exit = backend.exit,
        process_exited = backend.child_exited,
        output_drained = backend.output_eof,
    }
}

//   Close all Unix resources and reset the backend for reuse.
//
// Side effects:
//   - Closes the PTY master, releases the active workspace view, preserves reusable
//     VM storage, and restores the closed descriptor sentinel.
unix_terminal_backend_close :: proc(user_data: rawptr) {
    backend := (^Unix_Terminal_Backend)(user_data)
    if backend == nil {
        return
    }
    if backend.master != posix.FD(-1) {
        posix.close(backend.master)
    }
    unix_terminal_backend_release_workspace(backend)
    backend.master = posix.FD(-1)
    backend.child = 0
    backend.input = {}
    backend.input_count = 0
    backend.child_exited = false
    backend.output_eof = false
    backend.exit = {}
    backend.active = false
}

//   Move unreconciled child and PTY ownership into application cleanup storage.
//
// Returns:
//   - True after transfer and reusable backend reset; false when registry storage is full.
unix_terminal_backend_transfer :: proc(
    user_data: rawptr, registry: ^Process_Cleanup_Registry,
    generation: u64) -> bool {
    backend := (^Unix_Terminal_Backend)(user_data)
    if backend == nil || !backend.active {
        return false
    }
    entry := process_cleanup_registry_reserve(registry, generation)
    if entry == nil {
        return false
    }
    token := unix_process_cleanup_token(entry)
    token^ = {
        child = backend.child,
        master = backend.master,
        child_reaped = backend.child_exited,
        output_eof = backend.output_eof,
    }
    entry.poll = unix_process_cleanup_poll
    entry.release = unix_process_cleanup_release
    unix_terminal_backend_release_workspace(backend)
    backend.master = posix.FD(-1)
    backend.child = 0
    backend.input = {}
    backend.input_count = 0
    backend.child_exited = false
    backend.output_eof = false
    backend.exit = {}
    backend.active = false
    return true
}

// Release reusable Unix backend storage after the final session close.
unix_terminal_backend_destroy :: proc(backend: ^Unix_Terminal_Backend) {
    if backend == nil {
        return
    }
    unix_terminal_backend_close(backend)
    if backend.workspace_arena_initialized {
        vmem.arena_destroy(&backend.workspace_arena)
    }
    backend^ = {master = posix.FD(-1)}
}

//   Bind one Unix PTY state object to the common backend contract.
//
// Returns:
//   - Complete callback table borrowing `backend` through `user_data`.
unix_terminal_backend_make :: proc(
    backend: ^Unix_Terminal_Backend) -> Terminal_Process_Backend {
    return {
        user_data = rawptr(backend),
        start = unix_terminal_backend_start,
        resize = unix_terminal_backend_resize,
        poll_output = unix_terminal_backend_poll_output,
        write_input = unix_terminal_backend_write_input,
        request_interrupt = unix_terminal_backend_request_interrupt,
        request_terminate = unix_terminal_backend_request_terminate,
        force_terminate = unix_terminal_backend_force_terminate,
        poll_exit = unix_terminal_backend_poll_exit,
        transfer = unix_terminal_backend_transfer,
        close = unix_terminal_backend_close,
    }
}