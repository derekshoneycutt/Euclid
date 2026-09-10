#+build windows
package termsession

// TODO(terminal-platform/windows): Verify ConPTY resize, completion, and teardown
// against the Linux-proven session lifecycle. Run the terminal/session package tests
// and complete repository gate on Windows; remove after native evidence passes.

import vmem "core:mem/virtual"
import "core:log"
import "core:strings"
import "core:sync"
import windows "core:sys/windows"

// Bytes in the sole per-session Windows launch workspace.
WINDOWS_TERMINAL_WORKSPACE_BYTES :: 256 * 1024

// Virtual storage reserved once for the reusable workspace plus alignment.
WINDOWS_TERMINAL_WORKSPACE_ARENA_SIZE :: 320 * 1024

// Bytes retained in the fixed host-to-ConPTY input ring.
WINDOWS_TERMINAL_INPUT_CAPACITY :: 8 * 1024

// Bytes retained in the fixed ConPTY-to-host output ring.
WINDOWS_TERMINAL_OUTPUT_CAPACITY :: 64 * 1024

// Maximum merged environment entries before final block emission.
WINDOWS_TERMINAL_ENVIRONMENT_CAPACITY :: 2048

// Native UTF-16 command-line unit limit accepted below the Win32 maximum.
WINDOWS_TERMINAL_COMMAND_LINE_MAX_UNITS :: 32_767

// Native process-thread attribute identifier for pseudoconsole attachment.
WINDOWS_PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE :: uintptr(0x0002_0016)

// `CompareStringOrdinal` result indicating equality.
WINDOWS_COMPARE_EQUAL :: windows.c_int(2)

// Opaque native pseudoconsole handle owned independently from Win32 handles.
Windows_Pseudo_Console :: distinct rawptr

// Extended startup layout carrying a process-thread attribute list.
Windows_Startup_Info_Ex :: struct {
    startup_info: windows.STARTUPINFOW,
    attribute_list: rawptr,
}

// Borrowed UTF-16 environment entry awaiting sorted block emission.
Windows_Environment_Source :: struct {
    text: windows.LPCWSTR,
    unit_count: int,
}

// Workspace-backed UTF-16 conversion result excluding terminator units from count.
Windows_Utf16_Result :: struct {
    text: windows.LPCWSTR,
    unit_count: int,
    valid: bool,
}

// Windows-owned state for one foreground ConPTY process and its launch workspace.
//
// Public backend calls are serialized, while reader, writer, and close workers share
// queue state under `queue_mutex`. Synchronization objects persist in-place across
// sessions; reset clears operation fields without copying mutex/condition state.
Windows_Terminal_Backend :: struct {
    // Reusable native launch storage owned for the backend lifetime.
    workspace_arena: vmem.Arena,
    workspace_arena_initialized: bool,
    workspace_storage: []u8,
    workspace: []u8,
    workspace_used: int,

    // Workspace-backed process creation strings and final environment block.
    application_name: windows.LPCWSTR,
    command_line: windows.LPCWSTR,
    working_directory: windows.LPCWSTR,
    environment: rawptr,

    // Borrowed inherited/generated entries and encoded plan keys used during merge.
    environment_sources:
        [WINDOWS_TERMINAL_ENVIRONMENT_CAPACITY]Windows_Environment_Source,
    environment_source_count: int,
    environment_keys: [PROCESS_PLAN_ENVIRONMENT_CAPACITY]windows.LPCWSTR,
    environment_key_units: [PROCESS_PLAN_ENVIRONMENT_CAPACITY]int,

    // ConPTY attachment metadata, live channels, and process identity.
    attribute_list: rawptr,
    pseudo_console: Windows_Pseudo_Console,
    input_write: windows.HANDLE,
    output_read: windows.HANDLE,
    process: windows.HANDLE,
    process_id: windows.DWORD,

    // Independently serviced output, input, and pseudoconsole-close workers.
    reader_thread: windows.HANDLE,
    writer_thread: windows.HANDLE,
    close_thread: windows.HANDLE,
    input_event: windows.HANDLE,
    close_event: windows.HANDLE,

    // Shared queue synchronization; output-space wakes a blocked reader worker.
    queue_mutex: sync.Mutex,
    output_space: sync.Cond,

    // Fixed circular input and output queues protected by `queue_mutex`.
    input: [WINDOWS_TERMINAL_INPUT_CAPACITY]u8,
    input_start: int,
    input_count: int,
    output: [WINDOWS_TERMINAL_OUTPUT_CAPACITY]u8,
    output_start: int,
    output_count: int,

    // Cross-thread exit/EOF/close barrier and reusable operation lifecycle.
    process_exited: bool,
    output_eof: bool,
    pseudo_console_closed: bool,
    shutting_down: bool,
    exit: Backend_Exit,
    active: bool,
}

// Application-lived cleanup token for one transferred Windows process handle.
Windows_Process_Cleanup_Token :: struct {
    process: windows.HANDLE,
}

// Borrow the Windows token stored inline in one cleanup registry entry.
windows_process_cleanup_token :: proc(
    entry: ^Process_Cleanup_Entry) -> ^Windows_Process_Cleanup_Token {
    return (^Windows_Process_Cleanup_Token)(raw_data(entry.token[:]))
}

// Poll one transferred process handle without blocking and release it after exit.
windows_process_cleanup_poll :: proc(entry: ^Process_Cleanup_Entry) -> bool {
    token := windows_process_cleanup_token(entry)
    if token.process == nil {
        return true
    }
    if windows.WaitForSingleObject(token.process, 0) != windows.WAIT_OBJECT_0 {
        return false
    }
    windows.CloseHandle(token.process)
    token.process = nil
    return true
}

// Request final process termination and release the transferred native handle.
windows_process_cleanup_release :: proc(entry: ^Process_Cleanup_Entry) -> bool {
    token := windows_process_cleanup_token(entry)
    if token.process == nil {
        return true
    }
    windows.TerminateProcess(token.process, 1)
    complete := windows.WaitForSingleObject(token.process, 0) == windows.WAIT_OBJECT_0
    windows.CloseHandle(token.process)
    token.process = nil
    return complete
}

foreign import windows_kernel32 "system:kernel32.lib"

foreign windows_kernel32 {
    // Create one Windows pseudoconsole over caller-owned pipe endpoints.
    @(link_name="CreatePseudoConsole")
    windows_create_pseudo_console :: proc "system" (
        size: windows.COORD, input, output: windows.HANDLE,
        flags: windows.DWORD, console: ^Windows_Pseudo_Console) -> windows.HRESULT ---
    @(link_name="ResizePseudoConsole")
    windows_resize_pseudo_console :: proc "system" (
        console: Windows_Pseudo_Console,
        size: windows.COORD) -> windows.HRESULT ---
    // Close a pseudoconsole after its output is independently serviced.
    @(link_name="ClosePseudoConsole")
    windows_close_pseudo_console :: proc "system" (
        console: Windows_Pseudo_Console) ---
    // Query or initialize storage for process thread attributes.
    @(link_name="InitializeProcThreadAttributeList")
    windows_initialize_attribute_list :: proc "system" (
        list: rawptr, attribute_count: windows.DWORD, flags: windows.DWORD,
        byte_count: ^windows.SIZE_T) -> windows.BOOL ---
    // Attach one pseudoconsole handle to an extended startup attribute list.
    @(link_name="UpdateProcThreadAttribute")
    windows_update_attribute :: proc "system" (
        list: rawptr, flags: windows.DWORD, attribute: uintptr,
        value: rawptr, value_bytes: windows.SIZE_T, previous_value: rawptr,
        return_bytes: ^windows.SIZE_T) -> windows.BOOL ---
    // Release resources internal to an initialized attribute list.
    @(link_name="DeleteProcThreadAttributeList")
    windows_delete_attribute_list :: proc "system" (list: rawptr) ---
    // Compare bounded UTF-16 strings using Windows ordinal casing rules.
    @(link_name="CompareStringOrdinal")
    windows_compare_string_ordinal :: proc "system" (
        first: windows.LPCWSTR, first_count: windows.c_int,
        second: windows.LPCWSTR, second_count: windows.c_int,
        ignore_case: windows.BOOL) -> windows.c_int ---
    // Resolve one executable against a caller-supplied Windows search path.
    @(link_name="SearchPathW")
    windows_search_path :: proc "system" (
        path, file_name, extension: windows.LPCWSTR,
        buffer_count: windows.DWORD, buffer: windows.LPWSTR,
        file_part: ^windows.LPWSTR) -> windows.DWORD ---
    // Cancel a blocking synchronous operation issued by one worker thread.
    @(link_name="CancelSynchronousIo")
    windows_cancel_synchronous_io :: proc "system" (
        thread: windows.HANDLE) -> windows.BOOL ---
}

//   Initialize an idle Windows backend with one reusable native workspace.
//
// Returns:
//   - True after initialization; false for nil state or unavailable VM storage.
windows_terminal_backend_init :: proc(
    backend: ^Windows_Terminal_Backend) -> bool {
    if backend == nil {
        return false
    }
    backend^ = {}
    arena_error := vmem.arena_init_static(
        &backend.workspace_arena, WINDOWS_TERMINAL_WORKSPACE_ARENA_SIZE,
        WINDOWS_TERMINAL_WORKSPACE_ARENA_SIZE)
    if arena_error != nil {
        return false
    }
    allocator := vmem.arena_allocator(&backend.workspace_arena)
    storage, storage_error := make(
        []u8, WINDOWS_TERMINAL_WORKSPACE_BYTES, allocator)
    if storage_error != nil {
        vmem.arena_destroy(&backend.workspace_arena)
        backend^ = {}
        return false
    }
    backend.workspace_arena_initialized = true
    backend.workspace_storage = storage
    return true
}

//   Close one valid Win32 handle and clear its owner field.
//
// Side effects:
//   - Accepts nil and `INVALID_HANDLE_VALUE`; always leaves the field nil.
windows_terminal_close_handle :: proc(handle: ^windows.HANDLE) {
    if handle^ != nil && handle^ != windows.INVALID_HANDLE_VALUE {
        windows.CloseHandle(handle^)
    }
    handle^ = nil
}

//   Delete launch metadata and release the sole session workspace allocation.
//
// Side effects:
//   - Invalidates all UTF-16 pointers, environment sources, and attribute metadata.
windows_terminal_release_workspace :: proc(backend: ^Windows_Terminal_Backend) {
    if backend.attribute_list != nil {
        windows_delete_attribute_list(backend.attribute_list)
    }
    backend.workspace = nil
    backend.workspace_used = 0
    backend.application_name = nil
    backend.command_line = nil
    backend.working_directory = nil
    backend.environment = nil
    backend.environment_sources = {}
    backend.environment_source_count = 0
    backend.environment_keys = {}
    backend.environment_key_units = {}
    backend.attribute_list = nil
}

//   Reset reusable session fields without copying initialized synchronization state.
//
// Side effects:
//   - Clears all operation handles, queues, flags, and exit state while preserving
//     allocator, mutex, and condition-variable identity.
windows_terminal_reset_session_state :: proc(backend: ^Windows_Terminal_Backend) {
    backend.pseudo_console = nil
    backend.input_write = nil
    backend.output_read = nil
    backend.process = nil
    backend.process_id = 0
    backend.reader_thread = nil
    backend.writer_thread = nil
    backend.close_thread = nil
    backend.input_event = nil
    backend.close_event = nil
    backend.input_start = 0
    backend.input_count = 0
    backend.output_start = 0
    backend.output_count = 0
    backend.process_exited = false
    backend.output_eof = false
    backend.pseudo_console_closed = false
    backend.shutting_down = false
    backend.exit = {}
    backend.active = false
}

//   Align the next workspace region without allocating.
//
// Returns:
//   - True after advancing to the requested boundary; false when beyond capacity.
windows_terminal_workspace_align :: proc(
    backend: ^Windows_Terminal_Backend, alignment: int) -> bool {
    aligned := (backend.workspace_used + alignment - 1) & ~(alignment - 1)
    if aligned > len(backend.workspace) {
        return false
    }
    backend.workspace_used = aligned
    return true
}

//   Encode UTF-8 text and terminators into the bounded session workspace.
//
// Returns:
//   - Stable UTF-16 pointer/count and true, or an invalid result on conversion/capacity failure.
windows_terminal_workspace_utf16 :: proc(
    backend: ^Windows_Terminal_Backend, text: string,
    extra_terminators := 1) -> Windows_Utf16_Result {
    if !windows_terminal_workspace_align(backend, align_of(windows.WCHAR)) {
        return {}
    }
    remaining := backend.workspace[backend.workspace_used:]
    capacity := len(remaining) / size_of(windows.WCHAR)
    if capacity < extra_terminators {
        return {}
    }
    output := ([^]windows.WCHAR)(raw_data(remaining))
    count := windows.MultiByteToWideChar(
        windows.CP_UTF8, windows.MB_ERR_INVALID_CHARS,
        raw_data(text), windows.c_int(len(text)), output,
        windows.c_int(capacity - extra_terminators))
    if count <= 0 && len(text) > 0 {
        return {}
    }
    if int(count) + extra_terminators > capacity {
        return {}
    }
    for index in 0..<extra_terminators {
        output[int(count) + index] = 0
    }
    backend.workspace_used +=
        (int(count) + extra_terminators) * size_of(windows.WCHAR)
    return {
        text = windows.LPCWSTR(output),
        unit_count = int(count),
        valid = true,
    }
}

//   Build a mutable UTF-16 command line from the plan's owned arguments.
//
// Returns:
//   - True after CRT encoding and UTF-16 conversion within the native unit limit.
windows_terminal_build_command_line :: proc(
    backend: ^Windows_Terminal_Backend, plan: ^Process_Plan) -> bool {
    start := backend.workspace_used
    destination := backend.workspace[start:]
    used, encoded := windows_terminal_encode_command_line(plan, destination)
    if !encoded {
        return false
    }
    backend.workspace_used = start + used
    result := windows_terminal_workspace_utf16(
        backend, string(destination[:used]))
    if !result.valid ||
       result.unit_count >= WINDOWS_TERMINAL_COMMAND_LINE_MAX_UNITS {
        return false
    }
    backend.command_line = result.text
    return true
}

//   Find the key length of one native Windows environment entry.
//
// Notes:
//   - A leading `=` belongs to Windows drive-current-directory pseudo-variables.
windows_terminal_environment_key_units :: proc(
    entry: windows.LPCWSTR, unit_count: int) -> int {
    units := ([^]windows.WCHAR)(entry)
    start := 1 if unit_count > 0 && units[0] == '=' else 0
    for index in start..<unit_count {
        if units[index] == '=' {
            return index
        }
    }
    return unit_count
}

//   Compare two environment keys using Windows ordinal case-insensitive semantics.
windows_terminal_environment_keys_equal :: proc(
    first: windows.LPCWSTR, first_units: int,
    second: windows.LPCWSTR, second_units: int) -> bool {
    return windows_compare_string_ordinal(
        first, windows.c_int(first_units), second,
        windows.c_int(second_units), true) == WINDOWS_COMPARE_EQUAL
}

//   Encode plan environment keys once for native merge comparisons.
//
// Returns:
//   - True after all keys become stable workspace-backed UTF-16 strings.
windows_terminal_encode_environment_keys :: proc(
    backend: ^Windows_Terminal_Backend, plan: ^Process_Plan) -> bool {
    for index in 0..<plan.environment_count {
        change, valid := process_plan_environment_change(plan, index)
        if !valid {
            return false
        }
        result := windows_terminal_workspace_utf16(backend, change.key)
        if !result.valid {
            return false
        }
        backend.environment_keys[index] = result.text
        backend.environment_key_units[index] = result.unit_count
    }
    return true
}

//   Return whether any plan mutation replaces or removes one inherited entry.
windows_terminal_environment_overridden :: proc(
    backend: ^Windows_Terminal_Backend, plan: ^Process_Plan,
    entry: windows.LPCWSTR, unit_count: int) -> bool {
    key_units := windows_terminal_environment_key_units(entry, unit_count)
    for index in 0..<plan.environment_count {
        if windows_terminal_environment_keys_equal(
            entry, key_units, backend.environment_keys[index],
            backend.environment_key_units[index]) {
            return true
        }
    }
    return false
}

//   Return whether a later case-insensitive mutation supersedes an earlier one.
//
// Notes:
//   - Last mutation wins for duplicate Windows environment keys.
windows_terminal_environment_change_superseded :: proc(
    backend: ^Windows_Terminal_Backend, plan: ^Process_Plan,
    index: int) -> bool {
    for later in index + 1..<plan.environment_count {
        if windows_terminal_environment_keys_equal(
            backend.environment_keys[index],
            backend.environment_key_units[index],
            backend.environment_keys[later],
            backend.environment_key_units[later]) {
            return true
        }
    }
    return false
}

//   Append one borrowed entry to the fixed environment source table.
//
// Returns:
//   - True after append; false when source capacity is exhausted.
windows_terminal_add_environment_source :: proc(
    backend: ^Windows_Terminal_Backend, text: windows.LPCWSTR,
    unit_count: int) -> bool {
    if backend.environment_source_count >=
       WINDOWS_TERMINAL_ENVIRONMENT_CAPACITY {
        return false
    }
    backend.environment_sources[backend.environment_source_count] = {
        text = text,
        unit_count = unit_count,
    }
    backend.environment_source_count += 1
    return true
}

//   Collect inherited entries not replaced or removed by the plan.
//
// Notes:
//   - Collected pointers borrow the `GetEnvironmentStringsW` block only until final
//     environment emission completes in `windows_terminal_build_environment`.
//
// Returns:
//   - True after collection, including when inheritance is disabled.
windows_terminal_collect_inherited_environment :: proc(
    backend: ^Windows_Terminal_Backend, plan: ^Process_Plan,
    inherited: windows.LPWCH) -> bool {
    if !plan.inherit_environment {
        return true
    }
    inherited_units := ([^]windows.WCHAR)(inherited)
    offset := 0
    for inherited_units[offset] != 0 {
        unit_count := 0
        for inherited_units[offset + unit_count] != 0 {
            unit_count += 1
        }
        entry := windows.LPCWSTR(&inherited_units[offset])
        if !windows_terminal_environment_overridden(
            backend, plan, entry, unit_count) &&
           !windows_terminal_add_environment_source(
               backend, entry, unit_count) {
            return false
        }
        offset += unit_count + 1
    }
    return true
}

//   Encode one `key=value` environment entry into launch workspace.
//
// Returns:
//   - Stable UTF-16 entry/count and true, or an invalid result on failure.
windows_terminal_workspace_environment_change :: proc(
    backend: ^Windows_Terminal_Backend,
    key, value: string) -> Windows_Utf16_Result {
    if !windows_terminal_workspace_align(backend, align_of(windows.WCHAR)) {
        return {}
    }
    start := backend.workspace_used
    remaining := backend.workspace[start:]
    output := ([^]windows.WCHAR)(raw_data(remaining))
    capacity := len(remaining) / size_of(windows.WCHAR)
    key_units := windows.MultiByteToWideChar(
        windows.CP_UTF8, windows.MB_ERR_INVALID_CHARS,
        raw_data(key), windows.c_int(len(key)), output,
        windows.c_int(capacity))
    if key_units <= 0 || int(key_units) + 2 > capacity {
        return {}
    }
    output[key_units] = '='
    value_units := windows.MultiByteToWideChar(
        windows.CP_UTF8, windows.MB_ERR_INVALID_CHARS,
        raw_data(value), windows.c_int(len(value)), &output[key_units + 1],
        windows.c_int(capacity - int(key_units) - 2))
    if value_units <= 0 && len(value) > 0 {
        return {}
    }
    unit_count := int(key_units + value_units) + 1
    output[unit_count] = 0
    backend.workspace_used += (unit_count + 1) * size_of(windows.WCHAR)
    return {
        text = windows.LPCWSTR(output),
        unit_count = unit_count,
        valid = true,
    }
}

//   Collect final last-change-wins `.Set` mutations into the source table.
//
// Returns:
//   - True after encoding surviving entries; false on conversion or capacity failure.
windows_terminal_collect_plan_environment :: proc(
    backend: ^Windows_Terminal_Backend, plan: ^Process_Plan) -> bool {
    for index in 0..<plan.environment_count {
        change, valid := process_plan_environment_change(plan, index)
        if !valid || change.kind == .Unset ||
           windows_terminal_environment_change_superseded(
               backend, plan, index) {
            continue
        }
        result := windows_terminal_workspace_environment_change(
            backend, change.key, change.value)
        if !result.valid || !windows_terminal_add_environment_source(
            backend, result.text, result.unit_count) {
            return false
        }
    }
    return true
}

//   Sort environment entries according to Windows ordinal casing rules.
//
// Side effects:
//   - Reorders only source descriptors; pointed-to UTF-16 storage remains stable.
windows_terminal_sort_environment :: proc(backend: ^Windows_Terminal_Backend) {
    for index in 1..<backend.environment_source_count {
        source := backend.environment_sources[index]
        destination := index
        for destination > 0 {
            previous := backend.environment_sources[destination - 1]
            order := windows_compare_string_ordinal(
                previous.text, windows.c_int(previous.unit_count),
                source.text, windows.c_int(source.unit_count), true)
            if order <= WINDOWS_COMPARE_EQUAL {
                break
            }
            backend.environment_sources[destination] = previous
            destination -= 1
        }
        backend.environment_sources[destination] = source
    }
}

//   Emit a contiguous double-NUL-terminated UTF-16 environment block.
//
// Returns:
//   - True after copying every sorted source and assigning `backend.environment`.
windows_terminal_emit_environment :: proc(
    backend: ^Windows_Terminal_Backend) -> bool {
    if !windows_terminal_workspace_align(backend, align_of(windows.WCHAR)) {
        return false
    }
    start := backend.workspace_used
    destination := ([^]windows.WCHAR)(
        raw_data(backend.workspace[backend.workspace_used:]))
    capacity := (len(backend.workspace) - backend.workspace_used) /
        size_of(windows.WCHAR)
    used := 0
    for source in backend.environment_sources[:backend.environment_source_count] {
        if used + source.unit_count + 1 >= capacity {
            return false
        }
           source_units := ([^]windows.WCHAR)(source.text)
           copy(destination[used:used + source.unit_count],
               source_units[:source.unit_count])
        used += source.unit_count
        destination[used] = 0
        used += 1
    }
    if used + 1 >= capacity {
        return false
    }
    destination[used] = 0
    destination[used + 1] = 0
    backend.workspace_used += (used + 2) * size_of(windows.WCHAR)
    backend.environment = rawptr(&backend.workspace[start])
    return true
}

//   Snapshot, merge, sort, and emit the complete launch environment.
//
// Notes:
//   - Matching and ordering use Windows ordinal case-insensitive rules; plan mutations
//     override inherited entries and duplicate mutations use last-change-wins policy.
//
// Returns:
//   - True after the inherited environment block is released and an owned launch block exists.
windows_terminal_build_environment :: proc(
    backend: ^Windows_Terminal_Backend, plan: ^Process_Plan) -> bool {
    if !windows_terminal_encode_environment_keys(backend, plan) {
        return false
    }
    inherited := windows.GetEnvironmentStringsW()
    if inherited == nil {
        return false
    }
    collected := windows_terminal_collect_inherited_environment(
        backend, plan, inherited)
    built := false
    if collected && windows_terminal_collect_plan_environment(backend, plan) {
        windows_terminal_sort_environment(backend)
        built = windows_terminal_emit_environment(backend)
    }
    released := bool(windows.FreeEnvironmentStringsW(inherited))
    return built && released
}

//   Find one case-insensitive value in the emitted UTF-16 environment block.
//
// Returns:
//   - A borrowed null-terminated value, or nil when the key is absent.
windows_terminal_environment_value :: proc(
    backend: ^Windows_Terminal_Backend, key: []windows.WCHAR) -> windows.LPCWSTR {
    units := ([^]windows.WCHAR)(backend.environment)
    offset := 0
    for units[offset] != 0 {
        unit_count := 0
        for units[offset + unit_count] != 0 {
            unit_count += 1
        }
        entry := windows.LPCWSTR(&units[offset])
        key_units := windows_terminal_environment_key_units(entry, unit_count)
        if key_units == len(key) && windows_compare_string_ordinal(
            entry, windows.c_int(key_units), windows.LPCWSTR(raw_data(key)),
            windows.c_int(len(key)), true) == WINDOWS_COMPARE_EQUAL {
            return windows.LPCWSTR(&units[offset + key_units + 1])
        }
        offset += unit_count + 1
    }
    return nil
}

//   Resolve argument zero against the planned cwd or effective child PATH.
//
// Returns:
//   - Started after retaining an absolute executable path, executable-not-found when
//     discovery fails, or resource-unavailable when workspace capacity is exhausted.
windows_terminal_resolve_executable :: proc(
    backend: ^Windows_Terminal_Backend, executable: string) -> Backend_Start_Status {
    path_key := [4]windows.WCHAR{'P', 'A', 'T', 'H'}
    search_path := windows_terminal_environment_value(backend, path_key[:])
    if strings.index_byte(executable, '/') >= 0 ||
       strings.index_byte(executable, '\\') >= 0 {
        search_path = backend.working_directory
    }
    if !windows_terminal_workspace_align(backend, align_of(windows.WCHAR)) {
        return .Resource_Unavailable
    }
    destination := ([^]windows.WCHAR)(
        raw_data(backend.workspace[backend.workspace_used:]))
    capacity := (len(backend.workspace) - backend.workspace_used) /
        size_of(windows.WCHAR)
    extension := [5]windows.WCHAR{'.', 'e', 'x', 'e', 0}
    count := windows_search_path(
        search_path, backend.application_name,
        windows.LPCWSTR(&extension[0]), windows.DWORD(capacity),
        windows.LPWSTR(destination), nil)
    if count == 0 {
        return .Executable_Not_Found
    }
    if int(count) >= capacity {
        return .Resource_Unavailable
    }
    backend.application_name = windows.LPCWSTR(destination)
    backend.workspace_used += (int(count) + 1) * size_of(windows.WCHAR)
    return .Started
}

//   Populate reusable launch storage before acquiring OS resources.
//
// Returns:
//   - Started after all launch values and an absolute executable are workspace-backed;
//     otherwise a precise discovery or capacity failure.
//
// Side effects:
//   - Borrows the reusable backend workspace; caller performs rollback on failure.
windows_terminal_prepare_launch :: proc(
    backend: ^Windows_Terminal_Backend,
    plan: ^Process_Plan) -> Backend_Start_Status {
    if len(backend.workspace_storage) != WINDOWS_TERMINAL_WORKSPACE_BYTES {
        return .Resource_Unavailable
    }
    backend.workspace = backend.workspace_storage
    executable := process_plan_argument(plan, 0)
    executable_result := windows_terminal_workspace_utf16(backend, executable)
    if !executable_result.valid {
        return .Resource_Unavailable
    }
    backend.application_name = executable_result.text
    directory_result := windows_terminal_workspace_utf16(
        backend, process_plan_working_directory(plan))
    if !directory_result.valid ||
       !windows_terminal_build_command_line(backend, plan) {
        return .Resource_Unavailable
    }
    backend.working_directory = directory_result.text
    if !windows_terminal_build_environment(backend, plan) {
        return .Resource_Unavailable
    }
    return windows_terminal_resolve_executable(backend, executable)
}

//   Create inheritable ConPTY channels with non-inheritable host endpoints.
//
// Returns:
//   - True when both pipe pairs exist and host-owned ends cannot be inherited.
windows_terminal_create_pipes :: proc(
    backend: ^Windows_Terminal_Backend,
    pseudo_input: ^windows.HANDLE,
    pseudo_output: ^windows.HANDLE) -> bool {
    attributes := windows.SECURITY_ATTRIBUTES {
        nLength = windows.DWORD(size_of(windows.SECURITY_ATTRIBUTES)),
        bInheritHandle = true,
    }
    if !windows.CreatePipe(pseudo_input, &backend.input_write, &attributes, 0) {
        return false
    }
    if !windows.CreatePipe(&backend.output_read, pseudo_output, &attributes, 0) {
        return false
    }
    return bool(windows.SetHandleInformation(
        backend.input_write, windows.HANDLE_FLAG_INHERIT, 0) &&
        windows.SetHandleInformation(
            backend.output_read, windows.HANDLE_FLAG_INHERIT, 0))
}

//   Build the single pseudoconsole process attribute in workspace storage.
//
// Returns:
//   - True after native sizing, initialization, and ConPTY attachment succeed.
windows_terminal_create_attribute_list :: proc(
    backend: ^Windows_Terminal_Backend) -> bool {
    byte_count: windows.SIZE_T
    windows_initialize_attribute_list(nil, 1, 0, &byte_count)
    if !windows_terminal_workspace_align(backend, align_of(uintptr)) ||
       backend.workspace_used + int(byte_count) > len(backend.workspace) {
        return false
    }
    backend.attribute_list = raw_data(backend.workspace[backend.workspace_used:])
    backend.workspace_used += int(byte_count)
    if !windows_initialize_attribute_list(
        backend.attribute_list, 1, 0, &byte_count) {
        backend.attribute_list = nil
        return false
    }
    return bool(windows_update_attribute(
        backend.attribute_list, 0,
        WINDOWS_PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
        rawptr(backend.pseudo_console), size_of(backend.pseudo_console), nil, nil))
}

//   Launch the direct child with prepared ConPTY startup information.
//
// Returns:
//   - `.Started` with retained process handle/id, executable-not-found for native path
//     failures, or resource-unavailable for other creation failures.
//
// Side effects:
//   - Closes the initial process thread handle immediately after successful creation.
windows_terminal_start_process :: proc(
    backend: ^Windows_Terminal_Backend) -> Backend_Start_Status {
    startup := Windows_Startup_Info_Ex {
        startup_info = {cb = windows.DWORD(size_of(Windows_Startup_Info_Ex))},
        attribute_list = backend.attribute_list,
    }
    process_info: windows.PROCESS_INFORMATION
    created := windows.CreateProcessW(
        backend.application_name, backend.command_line, nil, nil, false,
        windows.CREATE_UNICODE_ENVIRONMENT |
            windows.EXTENDED_STARTUPINFO_PRESENT,
        backend.environment, backend.working_directory,
        &startup.startup_info, &process_info)
    if !created {
        error_code := windows.GetLastError()
        log.errorf(
            "CreateProcessW failed process_id=%d error_code=%d",
            backend.process_id, error_code)
        if error_code == windows.ERROR_FILE_NOT_FOUND {
            return .Executable_Not_Found
        }
        return .Resource_Unavailable
    }
    backend.process = process_info.hProcess
    backend.process_id = process_info.dwProcessId
    windows.CloseHandle(process_info.hThread)
    return .Started
}

//   Append bytes to a fixed circular queue while its owning mutex is held.
//
// Notes:
//   - Caller guarantees source fits free capacity; data may wrap once at ring end.
windows_terminal_ring_write :: proc "contextless" (
    ring: []u8, start, count: int, source: []u8) {
    write_start := (start + count) % len(ring)
    first_count := min(len(source), len(ring) - write_start)
    copy(ring[write_start:write_start + first_count], source[:first_count])
    copy(ring[:len(source) - first_count], source[first_count:])
}

//   Copy bytes from a fixed circular queue while its owning mutex is held.
//
// Notes:
//   - Caller advances start/count after this non-mutating copy operation.
windows_terminal_ring_read :: proc "contextless" (
    ring: []u8, start: int, destination: []u8) {
    first_count := min(len(destination), len(ring) - start)
    copy(destination[:first_count], ring[start:start + first_count])
    copy(destination[first_count:], ring[:len(destination) - first_count])
}

//   Drain ConPTY output independently into the bounded output ring.
//
// Notes:
//   - Blocks on `ReadFile` and on a full output ring; shutdown broadcasts the condition.
//
// Side effects:
//   - Appends under `queue_mutex` and sets `output_eof` when the pipe closes or fails.
windows_terminal_reader_thread :: proc "system" (data: rawptr) -> windows.DWORD {
    backend := (^Windows_Terminal_Backend)(data)
    buffer: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    for {
        byte_count: windows.DWORD
        if !windows.ReadFile(
            backend.output_read, raw_data(buffer[:]), windows.DWORD(len(buffer)),
            &byte_count, nil) || byte_count == 0 {
            sync.mutex_lock(&backend.queue_mutex)
            backend.output_eof = true
            sync.cond_broadcast(&backend.output_space)
            sync.mutex_unlock(&backend.queue_mutex)
            return 0
        }
        offset := 0
        for offset < int(byte_count) {
            sync.mutex_lock(&backend.queue_mutex)
            for backend.output_count == len(backend.output) &&
                !backend.shutting_down {
                sync.cond_wait(&backend.output_space, &backend.queue_mutex)
            }
            if backend.shutting_down {
                sync.mutex_unlock(&backend.queue_mutex)
                break
            }
            copied := min(
                int(byte_count) - offset,
                len(backend.output) - backend.output_count)
            windows_terminal_ring_write(
                backend.output[:], backend.output_start,
                backend.output_count, buffer[offset:offset + copied])
            backend.output_count += copied
            sync.mutex_unlock(&backend.queue_mutex)
            offset += copied
        }
    }
}

//   Service queued ConPTY input independently of display-thread polling.
//
// Notes:
//   - Waits on a manual-reset event, removes queued bytes under the mutex, then performs
//     potentially blocking writes without holding shared queue state.
windows_terminal_writer_thread :: proc "system" (data: rawptr) -> windows.DWORD {
    backend := (^Windows_Terminal_Backend)(data)
    buffer: [TERMINAL_SESSION_OUTPUT_MAX_BYTES]u8
    for {
        windows.WaitForSingleObject(backend.input_event, windows.INFINITE)
        sync.mutex_lock(&backend.queue_mutex)
        if backend.shutting_down {
            sync.mutex_unlock(&backend.queue_mutex)
            return 0
        }
        copied := min(backend.input_count, len(buffer))
        windows_terminal_ring_read(
            backend.input[:], backend.input_start, buffer[:copied])
        backend.input_start = (backend.input_start + copied) % len(backend.input)
        backend.input_count -= copied
        if backend.input_count == 0 {
            windows.ResetEvent(backend.input_event)
        }
        sync.mutex_unlock(&backend.queue_mutex)
        offset := 0
        for offset < copied {
            byte_count: windows.DWORD
            if !windows.WriteFile(
                backend.input_write, raw_data(buffer[offset:copied]),
                windows.DWORD(copied - offset), &byte_count, nil) ||
               byte_count == 0 {
                return 0
            }
            offset += int(byte_count)
        }
    }
}

//   Close the pseudoconsole without blocking process-exit polling.
//
// Side effects:
//   - Waits for one close request, closes ConPTY, and publishes closed state under mutex.
windows_terminal_close_thread :: proc "system" (data: rawptr) -> windows.DWORD {
    backend := (^Windows_Terminal_Backend)(data)
    windows.WaitForSingleObject(backend.close_event, windows.INFINITE)
    windows_close_pseudo_console(backend.pseudo_console)
    sync.mutex_lock(&backend.queue_mutex)
    backend.pseudo_console = nil
    backend.pseudo_console_closed = true
    sync.mutex_unlock(&backend.queue_mutex)
    return 0
}

//   Create fixed-context reader, writer, and lifecycle workers.
//
// Returns:
//   - True only when both events and all three worker handles are created.
windows_terminal_start_workers :: proc(
    backend: ^Windows_Terminal_Backend) -> bool {
    backend.input_event = windows.CreateEventW(nil, true, false, nil)
    backend.close_event = windows.CreateEventW(nil, true, false, nil)
    if backend.input_event == nil || backend.close_event == nil {
        return false
    }
    backend.reader_thread = windows.CreateThread(
        nil, 0, windows_terminal_reader_thread, backend, 0, nil)
    backend.writer_thread = windows.CreateThread(
        nil, 0, windows_terminal_writer_thread, backend, 0, nil)
    backend.close_thread = windows.CreateThread(
        nil, 0, windows_terminal_close_thread, backend, 0, nil)
    return backend.reader_thread != nil && backend.writer_thread != nil &&
        backend.close_thread != nil
}

//   Ask the lifecycle worker to close the pseudoconsole exactly once.
//
// Side effects:
//   - Signals `close_event` only while a close worker exists and closure is unpublished.
windows_terminal_request_pseudo_console_close :: proc(
    backend: ^Windows_Terminal_Backend) {
    sync.mutex_lock(&backend.queue_mutex)
    requested := backend.close_event != nil &&
        !backend.pseudo_console_closed
    sync.mutex_unlock(&backend.queue_mutex)
    if requested {
        windows.SetEvent(backend.close_event)
    }
}

//   Join and close one optional raw Win32 worker handle.
//
// Side effects:
//   - Waits indefinitely for worker exit and leaves the handle field nil.
windows_terminal_join_worker :: proc(handle: ^windows.HANDLE) {
    if handle^ != nil {
        windows.WaitForSingleObject(handle^, windows.INFINITE)
        windows_terminal_close_handle(handle)
    }
}

//   Stop, join, and close all independently serviced channels.
//
// Side effects:
//   - Publishes shutdown, wakes blocked workers, closes ConPTY, cancels blocked input
//     I/O, joins every worker, and closes all worker-owned pipe/event handles.
windows_terminal_stop_workers :: proc(backend: ^Windows_Terminal_Backend) {
    sync.mutex_lock(&backend.queue_mutex)
    backend.shutting_down = true
    sync.cond_broadcast(&backend.output_space)
    sync.mutex_unlock(&backend.queue_mutex)
    if backend.input_event != nil {
        windows.SetEvent(backend.input_event)
    }
    if backend.close_thread != nil {
        windows_terminal_request_pseudo_console_close(backend)
        windows_terminal_join_worker(&backend.close_thread)
    } else if backend.pseudo_console != nil {
        windows_close_pseudo_console(backend.pseudo_console)
        backend.pseudo_console = nil
        backend.pseudo_console_closed = true
    }
    windows_terminal_close_handle(&backend.input_write)
    if backend.writer_thread != nil {
        windows_cancel_synchronous_io(backend.writer_thread)
    }
    windows_terminal_join_worker(&backend.writer_thread)
    windows_terminal_join_worker(&backend.reader_thread)
    windows_terminal_close_handle(&backend.output_read)
    windows_terminal_close_handle(&backend.input_event)
    windows_terminal_close_handle(&backend.close_event)
}

//   Request worker shutdown and consume handles only after zero-time join checks pass.
//
// Returns:
//   - True after every helper thread has stopped and all channel handles are released.
windows_terminal_poll_workers_stopped :: proc(
    backend: ^Windows_Terminal_Backend) -> bool {
    sync.mutex_lock(&backend.queue_mutex)
    backend.shutting_down = true
    sync.cond_broadcast(&backend.output_space)
    sync.mutex_unlock(&backend.queue_mutex)
    if backend.input_event != nil {
        windows.SetEvent(backend.input_event)
    }
    windows_terminal_request_pseudo_console_close(backend)
    windows_terminal_close_handle(&backend.input_write)
    if backend.writer_thread != nil {
        windows_cancel_synchronous_io(backend.writer_thread)
    }
    handles := [3]windows.HANDLE{
        backend.close_thread,
        backend.writer_thread,
        backend.reader_thread,
    }
    for handle in handles {
        if handle != nil &&
           windows.WaitForSingleObject(handle, 0) != windows.WAIT_OBJECT_0 {
            return false
        }
    }
    windows_terminal_close_handle(&backend.close_thread)
    windows_terminal_close_handle(&backend.writer_thread)
    windows_terminal_close_handle(&backend.reader_thread)
    windows_terminal_close_handle(&backend.output_read)
    windows_terminal_close_handle(&backend.input_event)
    windows_terminal_close_handle(&backend.close_event)
    return true
}

//   Create a pseudoconsole, close transferred pipe ends, and attach launch metadata.
//
// Returns:
//   - True when ConPTY creation and attribute-list attachment both succeed.
//
// Side effects:
//   - Always closes the two handles whose ownership is transferred to ConPTY.
windows_terminal_prepare_pseudo_console :: proc(
    backend: ^Windows_Terminal_Backend, dimensions: Terminal_Dimensions,
    pseudo_input, pseudo_output: windows.HANDLE) -> bool {
    size := windows.COORD {
        X = windows.SHORT(dimensions.columns),
        Y = windows.SHORT(dimensions.rows),
    }
    result := windows_create_pseudo_console(
        size, pseudo_input, pseudo_output, 0, &backend.pseudo_console)
    windows.CloseHandle(pseudo_input)
    windows.CloseHandle(pseudo_output)
    return result >= 0 && windows_terminal_create_attribute_list(backend)
}

//   Roll back every acquired startup resource in reverse ownership order.
//
// Side effects:
//   - Stops workers or directly closes partial channels, releases workspace, and resets
//     reusable operation state while preserving synchronization object identity.
windows_terminal_abort_start :: proc(
    backend: ^Windows_Terminal_Backend, workers_started: bool) {
    if workers_started {
        windows_terminal_stop_workers(backend)
    } else {
        if backend.pseudo_console != nil {
            windows_close_pseudo_console(backend.pseudo_console)
            backend.pseudo_console = nil
        }
        windows_terminal_close_handle(&backend.input_write)
        windows_terminal_close_handle(&backend.output_read)
    }
    windows_terminal_release_workspace(backend)
    windows_terminal_reset_session_state(backend)
}

//   Transactionally create channels, pseudoconsole, workers, and child process.
//
// Parameters:
//   - user_data: Initialized idle `^Windows_Terminal_Backend`.
//   - plan: Canonically validated owned process plan.
//   - dimensions: Positive initial ConPTY dimensions.
//
// Returns:
//   - `.Started` only after all resources and the process are live; otherwise a precise
//     status after complete rollback.
windows_terminal_backend_start :: proc(
    user_data: rawptr, plan: ^Process_Plan,
    dimensions: Terminal_Dimensions) -> Backend_Start_Status {
    backend := (^Windows_Terminal_Backend)(user_data)
    if backend == nil || backend.active ||
       process_plan_validate(plan) != .None {
        return .Internal_Failure
    }
    prepare_status := windows_terminal_prepare_launch(backend, plan)
    if prepare_status != .Started {
        windows_terminal_release_workspace(backend)
        return prepare_status
    }
    pseudo_input, pseudo_output: windows.HANDLE
    if !windows_terminal_create_pipes(backend, &pseudo_input, &pseudo_output) {
        windows_terminal_close_handle(&pseudo_input)
        windows_terminal_close_handle(&pseudo_output)
        windows_terminal_abort_start(backend, false)
        return .Resource_Unavailable
    }
    if !windows_terminal_prepare_pseudo_console(
        backend, dimensions, pseudo_input, pseudo_output) {
        windows_terminal_abort_start(backend, false)
        return .Resource_Unavailable
    }
    if !windows_terminal_start_workers(backend) {
        windows_terminal_abort_start(backend, true)
        return .Resource_Unavailable
    }
    status := windows_terminal_start_process(backend)
    if status != .Started {
        windows_terminal_abort_start(backend, true)
        return status
    }
    backend.active = true
    return .Started
}

//   Apply character dimensions to the active pseudoconsole.
windows_terminal_backend_resize :: proc(
    user_data: rawptr, dimensions: Terminal_Dimensions) -> bool {
    backend := (^Windows_Terminal_Backend)(user_data)
    if backend == nil || !backend.active || backend.shutting_down ||
        backend.pseudo_console == nil || dimensions.columns == 0 ||
        dimensions.rows == 0 {
        return false
    }
    size := windows.COORD{
        X = i16(dimensions.columns),
        Y = i16(dimensions.rows),
    }
    return windows_resize_pseudo_console(backend.pseudo_console, size) >= 0
}

//   Pop currently buffered ConPTY output without blocking the caller.
//
// Returns:
//   - Number of bytes copied from the output ring, or zero when unavailable/inactive.
//
// Side effects:
//   - Advances the output ring under mutex and signals capacity to the reader worker.
windows_terminal_backend_poll_output :: proc(
    user_data: rawptr, destination: []u8) -> int {
    backend := (^Windows_Terminal_Backend)(user_data)
    if backend == nil || !backend.active || len(destination) == 0 {
        return 0
    }
    sync.mutex_lock(&backend.queue_mutex)
    copied := min(len(destination), backend.output_count)
    windows_terminal_ring_read(
        backend.output[:], backend.output_start, destination[:copied])
    backend.output_start = (backend.output_start + copied) % len(backend.output)
    backend.output_count -= copied
    if copied > 0 {
        sync.cond_signal(&backend.output_space)
    }
    sync.mutex_unlock(&backend.queue_mutex)
    return copied
}

//   Queue bounded input for the independent writer worker.
//
// Returns:
//   - True after accepting every byte, or false for empty/inactive/shutdown/full state.
//
// Side effects:
//   - Appends under mutex and signals the writer's manual-reset event.
windows_terminal_backend_write_input :: proc(
    user_data: rawptr, bytes: []u8) -> bool {
    backend := (^Windows_Terminal_Backend)(user_data)
    if backend == nil || !backend.active || len(bytes) == 0 {
        return false
    }
    sync.mutex_lock(&backend.queue_mutex)
    accepted := !backend.shutting_down &&
        len(bytes) <= len(backend.input) - backend.input_count
    if accepted {
        windows_terminal_ring_write(
            backend.input[:], backend.input_start, backend.input_count, bytes)
        backend.input_count += len(bytes)
        windows.SetEvent(backend.input_event)
    }
    sync.mutex_unlock(&backend.queue_mutex)
    return accepted
}

//   Deliver terminal interrupt input as the ETX control character.
//
// Returns:
//   - The input queue's acceptance result for byte `0x03`.
windows_terminal_backend_request_interrupt :: proc(user_data: rawptr) -> bool {
    interrupt := [1]u8{3}
    return windows_terminal_backend_write_input(user_data, interrupt[:])
}

//   Request graceful session teardown by closing the pseudoconsole.
//
// Returns:
//   - True after accepting a close request for an active backend.
windows_terminal_backend_request_terminate :: proc(user_data: rawptr) -> bool {
    backend := (^Windows_Terminal_Backend)(user_data)
    if backend == nil || !backend.active {
        return false
    }
    windows_terminal_request_pseudo_console_close(backend)
    return true
}

//   Force child termination through the process handle.
//
// Returns:
//   - True when `TerminateProcess` accepts exit status 1 for an active process.
windows_terminal_backend_force_terminate :: proc(user_data: rawptr) -> bool {
    backend := (^Windows_Terminal_Backend)(user_data)
    if backend == nil || !backend.active || backend.process == nil {
        return false
    }
    return bool(windows.TerminateProcess(backend.process, 1))
}

//   Reconcile process exit only after pseudoconsole EOF and output drain.
//
// Returns:
//   - Captured exit and true only when the process exited, ConPTY close completed,
//     output reached EOF, and the output ring is empty.
//
// Side effects:
//   - Captures process status once and requests asynchronous pseudoconsole closure.
windows_terminal_backend_poll_exit :: proc(
    user_data: rawptr) -> Backend_Exit_Progress {
    backend := (^Windows_Terminal_Backend)(user_data)
    if backend == nil || !backend.active {
        return {}
    }
    if !backend.process_exited &&
       windows.WaitForSingleObject(backend.process, 0) == windows.WAIT_OBJECT_0 {
        status: windows.DWORD
        if windows.GetExitCodeProcess(backend.process, &status) {
            backend.exit = {kind = .Exited, status = i32(status)}
        } else {
            backend.exit = {kind = .Infrastructure_Failure}
        }
        backend.process_exited = true
        windows_terminal_request_pseudo_console_close(backend)
    }
    sync.mutex_lock(&backend.queue_mutex)
    output_drained := backend.output_eof &&
        backend.pseudo_console_closed && backend.output_count == 0
    sync.mutex_unlock(&backend.queue_mutex)
    return {
        exit = backend.exit,
        process_exited = backend.process_exited,
        output_drained = output_drained,
    }
}

//   Idempotently stop workers, close OS resources, and free launch storage.
//
// Side effects:
//   - Force-stops an unreconciled child, joins workers, closes process/channels, releases
//     workspace, and resets operation fields for backend reuse.
windows_terminal_backend_close :: proc(user_data: rawptr) {
    backend := (^Windows_Terminal_Backend)(user_data)
    if backend == nil {
        return
    }
    if backend.active && !backend.process_exited && backend.process != nil {
        windows.TerminateProcess(backend.process, 1)
        windows.WaitForSingleObject(backend.process, windows.INFINITE)
    }
    if backend.reader_thread != nil || backend.writer_thread != nil ||
       backend.close_thread != nil {
        windows_terminal_stop_workers(backend)
    }
    windows_terminal_close_handle(&backend.process)
    windows_terminal_release_workspace(backend)
    windows_terminal_reset_session_state(backend)
}

//   Move an unreconciled process into fixed cleanup storage after helpers stop.
//
// Returns:
//   - True after ownership transfer; false while helper threads run or storage is full.
windows_terminal_backend_transfer :: proc(
    user_data: rawptr, registry: ^Process_Cleanup_Registry,
    generation: u64) -> bool {
    backend := (^Windows_Terminal_Backend)(user_data)
    if backend == nil || !backend.active ||
       !windows_terminal_poll_workers_stopped(backend) {
        return false
    }
    entry := process_cleanup_registry_reserve(registry, generation)
    if entry == nil {
        return false
    }
    token := windows_process_cleanup_token(entry)
    token.process = backend.process
    entry.poll = windows_process_cleanup_poll
    entry.release = windows_process_cleanup_release
    backend.process = nil
    windows_terminal_release_workspace(backend)
    windows_terminal_reset_session_state(backend)
    return true
}

// Release reusable Windows backend storage after the final session close.
windows_terminal_backend_destroy :: proc(backend: ^Windows_Terminal_Backend) {
    if backend == nil {
        return
    }
    windows_terminal_backend_close(backend)
    if backend.workspace_arena_initialized {
        vmem.arena_destroy(&backend.workspace_arena)
    }
    backend^ = {}
}

//   Expose the Windows ConPTY implementation through the common backend contract.
//
// Returns:
//   - Complete callback table borrowing `backend` through `user_data`.
windows_terminal_backend_make :: proc(
    backend: ^Windows_Terminal_Backend) -> Terminal_Process_Backend {
    return {
        user_data = backend,
        start = windows_terminal_backend_start,
        resize = windows_terminal_backend_resize,
        poll_output = windows_terminal_backend_poll_output,
        write_input = windows_terminal_backend_write_input,
        request_interrupt = windows_terminal_backend_request_interrupt,
        request_terminate = windows_terminal_backend_request_terminate,
        force_terminate = windows_terminal_backend_force_terminate,
        poll_exit = windows_terminal_backend_poll_exit,
        transfer = windows_terminal_backend_transfer,
        close = windows_terminal_backend_close,
    }
}