package termsession

import "../shell"
import "core:unicode/utf8"

// Maximum argv entries inherited from bounded shell resolution.
PROCESS_PLAN_ARGUMENT_CAPACITY :: shell.SHELL_RESOLVED_ARGUMENT_CAPACITY

// Maximum UTF-8 bytes in one process argument.
PROCESS_PLAN_ARGUMENT_MAX_BYTES :: 4 * 1024

// Maximum combined UTF-8 argument bytes in one owned plan.
PROCESS_PLAN_ARGUMENT_TOTAL_MAX_BYTES :: shell.SHELL_RESOLVED_BYTE_CAPACITY

// Maximum UTF-8 bytes in the absolute launch directory.
PROCESS_PLAN_WORKING_DIRECTORY_MAX_BYTES :: 4 * 1024

// Maximum ordered environment mutations in one plan.
PROCESS_PLAN_ENVIRONMENT_CAPACITY :: 64

// Maximum combined UTF-8 key/value bytes for environment mutations.
PROCESS_PLAN_ENVIRONMENT_TOTAL_MAX_BYTES :: 16 * 1024

// Supported process creation strategy; direct launch performs no shell evaluation.
Process_Plan_Execution_Mode :: enum u8 {
    Direct,
}

// Supported terminal attachment policy for directly launched processes.
Process_Plan_Terminal_Mode :: enum u8 {
    Foreground_Pseudoterminal,
}

// Supported process-completion reporting policy.
Process_Plan_Exit_Policy :: enum u8 {
    Report_Status,
}

// Mutation applied to the inherited or initially empty process environment.
Environment_Change_Kind :: enum u8 {
    Set,
    Unset,
}

// Transient environment mutation copied into a process plan during construction.
//
// `value` is ignored for `.Unset`; keys must be nonempty UTF-8 without NUL or `=`.
Environment_Change :: struct {
    kind: Environment_Change_Kind,
    key: string,
    value: string,
}

// Half-open byte span into one of a process plan's owned byte arrays.
Process_Plan_Text :: struct {
    start: u16,
    end: u16,
}

// Owned environment mutation represented by spans into `Process_Plan.environment_bytes`.
Process_Plan_Environment_Change :: struct {
    kind: Environment_Change_Kind,
    key: Process_Plan_Text,
    value: Process_Plan_Text,
}

// Self-contained bounded process-launch specification.
//
// All strings are copied into inline byte arrays and referenced by offsets, so the
// plan can be copied by value without borrowing builder inputs. Valid plans always
// request direct foreground pseudoterminal execution with status reporting.
Process_Plan :: struct {
    // Ordered argv storage; argument zero is the executable name or path.
    argument_bytes: [PROCESS_PLAN_ARGUMENT_TOTAL_MAX_BYTES]u8,
    arguments: [PROCESS_PLAN_ARGUMENT_CAPACITY]Process_Plan_Text,
    argument_count: int,
    argument_byte_count: int,

    // Absolute launch directory stored as one contiguous UTF-8 string.
    working_directory_bytes: [PROCESS_PLAN_WORKING_DIRECTORY_MAX_BYTES]u8,
    working_directory_byte_count: int,

    // Ordered environment deltas and their shared owned text arena.
    environment_bytes: [PROCESS_PLAN_ENVIRONMENT_TOTAL_MAX_BYTES]u8,
    environment: [PROCESS_PLAN_ENVIRONMENT_CAPACITY]Process_Plan_Environment_Change,
    environment_count: int,
    environment_byte_count: int,
    inherit_environment: bool,

    // Explicit launch policies constrained to the currently supported variants.
    execution_mode: Process_Plan_Execution_Mode,
    terminal_mode: Process_Plan_Terminal_Mode,
    exit_policy: Process_Plan_Exit_Policy,
}

// Canonical reason a process plan cannot be built or admitted.
Process_Plan_Error :: enum u8 {
    None,
    Empty_Arguments,
    Too_Many_Arguments,
    Empty_Executable,
    Argument_Too_Long,
    Arguments_Too_Long,
    Invalid_Argument,
    Invalid_Working_Directory,
    Working_Directory_Too_Long,
    Too_Many_Environment_Changes,
    Invalid_Environment_Key,
    Invalid_Environment_Value,
    Environment_Too_Long,
}

// Discriminator for process-plan construction.
Process_Plan_Result_Kind :: enum u8 {
    Success,
    Error,
}

// Owned process-plan construction result.
//
// `plan` is meaningful for `.Success`; `error` is meaningful for `.Error`.
Process_Plan_Result :: struct {
    kind: Process_Plan_Result_Kind,
    plan: Process_Plan,
    error: Process_Plan_Error,
}

//   Validate argument descriptors and bytes owned by a process plan.
//
// Parameters:
//   - plan: Non-nil candidate plan.
//
// Returns:
//   - `.None` when argv spans, limits, UTF-8, and executable requirements hold;
//     otherwise the first canonical argument error.
process_plan_validate_arguments :: proc(plan: ^Process_Plan) -> Process_Plan_Error {
    if plan.argument_count <= 0 {
        return .Empty_Arguments
    }
    if plan.argument_count > len(plan.arguments) {
        return .Too_Many_Arguments
    }
    if plan.argument_byte_count < 0 ||
       plan.argument_byte_count > len(plan.argument_bytes) {
        return .Arguments_Too_Long
    }
    for index in 0..<plan.argument_count {
        text := plan.arguments[index]
        if text.end < text.start || int(text.end) > plan.argument_byte_count {
            return .Invalid_Argument
        }
        argument := string(plan.argument_bytes[text.start:text.end])
        if index == 0 && len(argument) == 0 {
            return .Empty_Executable
        }
        if len(argument) > PROCESS_PLAN_ARGUMENT_MAX_BYTES {
            return .Argument_Too_Long
        }
        if !process_plan_text_valid(argument) {
            return .Invalid_Argument
        }
    }
    return .None
}

//   Validate environment descriptors and bytes owned by a process plan.
//
// Parameters:
//   - plan: Non-nil candidate plan.
//
// Returns:
//   - `.None` when all spans and environment mutations are valid; otherwise the
//     first canonical environment error.
process_plan_validate_environment :: proc(plan: ^Process_Plan) -> Process_Plan_Error {
    if plan.environment_count < 0 ||
       plan.environment_count > len(plan.environment) {
        return .Too_Many_Environment_Changes
    }
    if plan.environment_byte_count < 0 ||
       plan.environment_byte_count > len(plan.environment_bytes) {
        return .Environment_Too_Long
    }
    for index in 0..<plan.environment_count {
        entry := plan.environment[index]
        if entry.key.end < entry.key.start ||
           entry.value.end < entry.value.start ||
           int(entry.key.end) > plan.environment_byte_count ||
           int(entry.value.end) > plan.environment_byte_count {
            return .Environment_Too_Long
        }
        change, valid := process_plan_environment_change(plan, index)
        if !valid || len(change.key) == 0 || !process_plan_text_valid(change.key) {
            return .Invalid_Environment_Key
        }
        for byte in transmute([]u8)change.key {
            if byte == '=' {
                return .Invalid_Environment_Key
            }
        }
        if change.kind == .Set && !process_plan_text_valid(change.value) {
            return .Invalid_Environment_Value
        }
    }
    return .None
}

//   Validate a complete owned plan before any backend resource allocation.
//
// Parameters:
//   - plan: Candidate self-contained launch plan; nil is invalid.
//
// Returns:
//   - `.None` only when argv, absolute directory, environment, and policy invariants hold.
process_plan_validate :: proc(plan: ^Process_Plan) -> Process_Plan_Error {
    if plan == nil {
        return .Empty_Arguments
    }
    if error := process_plan_validate_arguments(plan); error != .None {
        return error
    }
    if plan.working_directory_byte_count < 0 ||
       plan.working_directory_byte_count > len(plan.working_directory_bytes) {
        return .Working_Directory_Too_Long
    }
    if !process_plan_absolute_path_valid(process_plan_working_directory(plan)) {
        return .Invalid_Working_Directory
    }
    if error := process_plan_validate_environment(plan); error != .None {
        return error
    }
    if plan.execution_mode != .Direct ||
       plan.terminal_mode != .Foreground_Pseudoterminal ||
       plan.exit_policy != .Report_Status {
        return .Invalid_Argument
    }
    return .None
}

//   Validate top-level transient build inputs before copying any bytes.
//
// Parameters:
//   - arguments: Ordered transient argv views.
//   - working_directory: Absolute transient launch directory.
//   - environment: Ordered transient environment mutations.
//
// Returns:
//   - `.None` when collection counts and directory constraints permit construction.
process_plan_validate_build_inputs :: proc(
    arguments: []string, working_directory: string,
    environment: []Environment_Change) -> Process_Plan_Error {
    if len(arguments) == 0 {
        return .Empty_Arguments
    }
    if len(arguments) > PROCESS_PLAN_ARGUMENT_CAPACITY {
        return .Too_Many_Arguments
    }
    if len(working_directory) > PROCESS_PLAN_WORKING_DIRECTORY_MAX_BYTES {
        return .Working_Directory_Too_Long
    }
    if !process_plan_absolute_path_valid(working_directory) {
        return .Invalid_Working_Directory
    }
    if len(environment) > PROCESS_PLAN_ENVIRONMENT_CAPACITY {
        return .Too_Many_Environment_Changes
    }
    return .None
}

//   Return whether text can cross a native process boundary unchanged.
//
// Parameters:
//   - text: Candidate UTF-8 byte string.
//
// Returns:
//   - True for valid UTF-8 containing no embedded NUL byte.
process_plan_text_valid :: proc(text: string) -> bool {
    if !utf8.valid_string(text) {
        return false
    }
    for byte in transmute([]u8)text {
        if byte == 0 {
            return false
        }
    }
    return true
}

//   Return whether a platform-neutral path is recognizably absolute.
//
// Parameters:
//   - path: Candidate UTF-8 path.
//
// Returns:
//   - True for a valid POSIX `/...` path or drive-qualified `X:/...`/`X:\\...` path.
process_plan_absolute_path_valid :: proc(path: string) -> bool {
    if len(path) == 0 || !process_plan_text_valid(path) {
        return false
    }
    if path[0] == '/' {
        return true
    }
    return len(path) >= 3 &&
        ((path[0] >= 'A' && path[0] <= 'Z') ||
         (path[0] >= 'a' && path[0] <= 'z')) &&
        path[1] == ':' && (path[2] == '/' || path[2] == '\\')
}

//   Append one validated argument to the plan's owned argv storage.
//
// Parameters:
//   - plan: Plan currently under construction.
//   - text: Transient argument copied before return.
//   - index: Destination descriptor index; zero identifies the executable.
//
// Returns:
//   - `.None` after commit, otherwise a length, encoding, or executable error.
//
// Side effects:
//   - Advances argument count and byte usage only after all checks succeed.
process_plan_append_argument :: proc(
    plan: ^Process_Plan, text: string, index: int) -> Process_Plan_Error {
    if len(text) > PROCESS_PLAN_ARGUMENT_MAX_BYTES {
        return .Argument_Too_Long
    }
    if !process_plan_text_valid(text) {
        return .Invalid_Argument
    }
    if index == 0 && len(text) == 0 {
        return .Empty_Executable
    }
    end := plan.argument_byte_count + len(text)
    if end > len(plan.argument_bytes) {
        return .Arguments_Too_Long
    }
    copy(plan.argument_bytes[plan.argument_byte_count:end], transmute([]u8)text)
    plan.arguments[index] = {
        start = u16(plan.argument_byte_count),
        end = u16(end),
    }
    plan.argument_count += 1
    plan.argument_byte_count = end
    return .None
}

//   Append one validated environment mutation to owned plan storage.
//
// Parameters:
//   - plan: Plan currently under construction.
//   - change: Transient mutation whose key and set-value are copied before return.
//   - index: Destination environment descriptor index.
//
// Returns:
//   - `.None` after commit, otherwise the canonical key, value, or capacity error.
//
// Side effects:
//   - Advances environment count and byte usage only after all checks succeed.
process_plan_append_environment :: proc(
    plan: ^Process_Plan, change: Environment_Change,
    index: int) -> Process_Plan_Error {
    if len(change.key) == 0 || !process_plan_text_valid(change.key) {
        return .Invalid_Environment_Key
    }
    for byte in transmute([]u8)change.key {
        if byte == '=' {
            return .Invalid_Environment_Key
        }
    }
    if change.kind == .Set && !process_plan_text_valid(change.value) {
        return .Invalid_Environment_Value
    }
    value := change.value if change.kind == .Set else ""
    end := plan.environment_byte_count + len(change.key) + len(value)
    if end > len(plan.environment_bytes) {
        return .Environment_Too_Long
    }
    key_end := plan.environment_byte_count + len(change.key)
    copy(plan.environment_bytes[plan.environment_byte_count:key_end],
        transmute([]u8)change.key)
    copy(plan.environment_bytes[key_end:end], transmute([]u8)value)
    plan.environment[index] = {
        kind = change.kind,
        key = {start = u16(plan.environment_byte_count), end = u16(key_end)},
        value = {start = u16(key_end), end = u16(end)},
    }
    plan.environment_count += 1
    plan.environment_byte_count = end
    return .None
}

//   Build a self-contained process plan from transient launch views.
//
// Parameters:
//   - arguments: Ordered argv; element zero names the executable.
//   - working_directory: Absolute launch directory copied into the result.
//   - environment: Ordered environment mutations copied into the result.
//   - inherit_environment: Whether native launch begins from the parent environment.
//
// Returns:
//   - `.Success` with a fully owned canonical plan, or `.Error` with the first failure.
process_plan_build :: proc(
    arguments: []string, working_directory: string,
    environment: []Environment_Change,
    inherit_environment := true) -> Process_Plan_Result {
    result := Process_Plan_Result{kind = .Error}
    if error := process_plan_validate_build_inputs(
        arguments, working_directory, environment); error != .None {
        result.error = error
        return result
    }
    for argument, index in arguments {
        if error := process_plan_append_argument(&result.plan, argument, index);
            error != .None {
            result.error = error
            return result
        }
    }
    copy(result.plan.working_directory_bytes[:], transmute([]u8)working_directory)
    result.plan.working_directory_byte_count = len(working_directory)
    for change, index in environment {
        if error := process_plan_append_environment(&result.plan, change, index);
            error != .None {
            result.error = error
            return result
        }
    }
    result.plan.inherit_environment = inherit_environment
    result.plan.execution_mode = .Direct
    result.plan.terminal_mode = .Foreground_Pseudoterminal
    result.plan.exit_policy = .Report_Status
    result.kind = .Success
    return result
}

//   Freeze one bounded resolved shell command into an owned process plan.
//
// Parameters:
//   - command: Resolved command whose argument views are consumed synchronously.
//   - working_directory: Absolute launch directory copied into the result.
//   - environment: Ordered transient environment mutations.
//   - inherit_environment: Whether native launch begins from the parent environment.
//
// Returns:
//   - The same owned success/error result as `process_plan_build`.
process_plan_build_resolved :: proc(
    command: ^shell.Resolved_Command, working_directory: string,
    environment: []Environment_Change,
    inherit_environment := true) -> Process_Plan_Result {
    if command == nil || command.argument_count <= 0 {
        return {kind = .Error, error = .Empty_Arguments}
    }
    if command.argument_count > PROCESS_PLAN_ARGUMENT_CAPACITY {
        return {kind = .Error, error = .Too_Many_Arguments}
    }
    arguments: [PROCESS_PLAN_ARGUMENT_CAPACITY]string
    for index in 0..<command.argument_count {
        arguments[index] = shell.resolved_command_argument_text(command, index)
    }
    return process_plan_build(
        arguments[:command.argument_count], working_directory,
        environment, inherit_environment)
}

//   Return one argument from storage owned by the plan.
//
// Parameters:
//   - plan: Valid source plan.
//   - index: Zero-based argument index.
//
// Returns:
//   - A borrowed plan-owned string, or empty for nil/out-of-range input.
process_plan_argument :: proc(plan: ^Process_Plan, index: int) -> string {
    if plan == nil || index < 0 || index >= plan.argument_count {
        return ""
    }
    text := plan.arguments[index]
    return string(plan.argument_bytes[text.start:text.end])
}

//   Return the absolute working directory owned by the plan.
//
// Parameters:
//   - plan: Valid source plan.
//
// Returns:
//   - A borrowed plan-owned string, or empty for nil input.
process_plan_working_directory :: proc(plan: ^Process_Plan) -> string {
    if plan == nil {
        return ""
    }
    return string(plan.working_directory_bytes[:plan.working_directory_byte_count])
}

//   Return one environment mutation from plan-owned storage.
//
// Parameters:
//   - plan: Valid source plan.
//   - index: Zero-based environment mutation index.
//
// Returns:
//   - A mutation whose strings borrow the plan and true, or an empty value and false.
process_plan_environment_change :: proc(
    plan: ^Process_Plan, index: int) -> (Environment_Change, bool) {
    if plan == nil || index < 0 || index >= plan.environment_count {
        return {}, false
    }
    entry := plan.environment[index]
    return {
        kind = entry.kind,
        key = string(plan.environment_bytes[entry.key.start:entry.key.end]),
        value = string(plan.environment_bytes[entry.value.start:entry.value.end]),
    }, true
}