package scenario

// Package scenario validates and executes bounded semantic workflows.

import "../observe"
import trace "../trace"
import json "core:encoding/json"

SCENARIO_COMMAND_CAPACITY :: 128
SCENARIO_TEXT_CAPACITY :: 256
SCENARIO_NAME_CAPACITY :: 64
SCENARIO_DEFAULT_TIMEOUT_MS :: u32(5_000)
SCENARIO_MAX_TIMEOUT_MS :: u32(60_000)
SCENARIO_SOURCE_MAX_BYTES :: 64 * 1024
SCENARIO_LINE_MAX_BYTES :: 1024

// Stable public scenario spelling paired with its typed evidence identity.
Event_Kind_Entry :: struct {
    name : string,
    kind : trace.Kind,
}

// Event names accepted by `wait_event`; spellings are part of the scenario format.
EVENT_KINDS :: [?]Event_Kind_Entry {
    {"runtime_ready", .Runtime_Ready},
    {"runtime_reload_committed", .Runtime_Reload_Committed},
    {"runtime_reload_rolled_back", .Runtime_Reload_Rolled_Back},
    {"animation_selected", .Animation_Selected},
    {"animation_cycle_boundary", .Animation_Cycle_Boundary},
    {"scene_batch_committed", .Scene_Batch_Committed},
    {"constraint_solve_completed", .Constraint_Solve_Completed},
    {"dynview_published", .Dynview_Published},
    {"scratchpad_completed", .Scratchpad_Completed},
    {"frame_presented", .Frame_Presented},
    {"capture_completed", .Capture_Completed},
    {"gif_completed", .Gif_Completed},
    {"checkpoint_stored", .Checkpoint_Stored},
    {"runtime_shutdown_complete", .Runtime_Shutdown_Complete},
}

// Stable semantic operation represented by one validated scenario command.
Command_Kind :: enum u8 {
    Reset_Animation,
    Select_Animation,
    Reload_Runtime,
    Submit_Scratchpad,
    Pause_Simulation,
    Resume_Simulation,
    Request_Screenshot,
    Start_Gif,
    Stop_Gif,
    Wait_Event,
    Wait_State,
    Assert_State,
    Checkpoint,
    Allocation_Checkpoint,
    Assert_Allocation_Baseline,
    Assert_No_Bad_Frees,
    Shutdown,
}

// Stable reason a bounded JSON Lines source could not become a complete program.
Parse_Error :: enum u8 {
    None,
    Too_Many_Commands,
    Invalid_Json,
    Invalid_Command,
    Text_Too_Long,
    Name_Too_Long,
    Invalid_Timeout,
    Source_Too_Long,
    Line_Too_Long,
}

// Lifecycle of one runner from initialization through a terminal outcome.
//
// Inconclusive means required evidence was unavailable, not that behavior passed
// or failed.
Run_Status :: enum u8 {
    Ready,
    Running,
    Passed,
    Failed,
    Inconclusive,
}

// Fixed inline storage for a command payload or predicate name.
//
// The initialized prefix is not NUL-terminated; count selects the valid bytes.
Text :: struct {
    // Inline bytes and initialized prefix length.
    bytes : [SCENARIO_TEXT_CAPACITY]u8,
    count : int,
}

// Fixed inline storage for an action alias or correlation reference.
//
// The initialized prefix is not NUL-terminated; count selects the valid bytes.
Name :: struct {
    // Inline bytes and initialized prefix length.
    bytes : [SCENARIO_NAME_CAPACITY]u8,
    count : int,
}

// Fully validated, allocation-free scenario instruction.
Command :: struct {
    // Operation identity and its inline payload or predicate text.
    kind : Command_Kind,
    text : Text,

    // Optional produced alias and alias required by a later event wait.
    alias : Name,
    correlation : Name,

    // Bounded wait duration in milliseconds; nonwait commands leave this zero.
    timeout_ms : u32,
}

// Fixed-capacity scenario program produced from one complete JSON Lines source.
Program :: struct {
    // Command storage; only the count-selected prefix is initialized.
    commands : [SCENARIO_COMMAND_CAPACITY]Command,
    count : int,
}

// Runtime binding from one inline scenario name to an existing correlation ID.
Alias :: struct {
    name : Name,
    correlation : trace.Identity,
}

// Result returned by one synchronous owner-routed scenario action.
Action_Result :: struct {
    accepted: bool,
    correlation: trace.Identity,
}

// Synchronous runtime action boundary used by the runner.
Action_Proc :: proc(user_data: rawptr, command: ^Command) -> Action_Result

// Optional runtime action destination supplied by the owner control loop.
Action_Sink :: struct {
    // Opaque state interpreted exclusively by the callback implementation.
    user_data : rawptr,

    // Synchronous action callback; nil leaves ordinary actions without correlation.
    issue : Action_Proc,
}

// Borrowed observations and action boundary for one runner advancement.
Runner_Frame :: struct {
    now_ns : u64,
    events : []trace.Event,
    display : observe.Display,
    actions : Action_Sink,
}

// Owner-controlled execution state for one validated fixed program.
Runner :: struct {
    // Immutable command program copied into the runner at initialization.
    program : Program,

    // Bounded action-alias registry; only the alias_count prefix is initialized.
    aliases : [SCENARIO_COMMAND_CAPACITY]Alias,
    alias_count : int,

    // Lifecycle and next command index. Terminal statuses are sticky.
    status : Run_Status,
    step : int,

    // Cursor into the cumulative trace snapshot and active monotonic wait deadline.
    trace_cursor : int,
    deadline_ns : u64,

    // Cumulative assertion and failure evidence for the current run.
    assertion_count : u32,
    failure_count : u32,
}

// Temporary JSON decoding shape for exactly one source line.
//
// Action fields are mutually exclusive after validation. Dynamic strings borrow
// decoder-managed storage only until command_from_raw copies accepted values inline.
Raw_Command :: struct {
    // Named payload-free action selected through the public `do` field.
    action : string `json:"do"`,

    // Text-bearing runtime and capture actions.
    select_animation : string,
    scratchpad : string,
    screenshot : string,
    start_gif : string,

    // Event waits and display-state predicates.
    wait_event : string,
    wait_state : string,
    assert_state : string,

    // State checkpoint action.
    checkpoint : string,

    // Allocation checkpoint and assertion actions.
    allocation_checkpoint : string,
    assert_allocation_baseline : string,
    assert_no_bad_frees : bool,

    // Optional produced alias, event correlation reference, and wait bound.
    alias : string `json:"as"`,
    correlation : string,
    timeout_ms : u32,

    // Payload-free terminal action represented directly in JSON.
    shutdown : bool,
}

//   Parse and validate a complete bounded JSON Lines program.
//
// Parameters:
//   - source: Complete borrowed UTF-8 scenario source.
//   - program: Destination replaced only with commands parsed before an error.
//
// Returns:
//   - Stable parse outcome; `.None` means the complete source was accepted.
//
// Side effects:
//   - Clears program before parsing and retains the valid command prefix on error.
//   - Uses the context temporary allocator while decoding individual JSON objects.
//
// Notes:
//   - Empty lines are ignored. Every nonempty line must contain exactly one action.
//   - All retained command data is copied into program-owned fixed storage.
parse :: proc(source: string, program: ^Program) -> Parse_Error {
    program^ = {}
    if len(source) > SCENARIO_SOURCE_MAX_BYTES {
        return .Source_Too_Long
    }
    line_start := 0
    bytes := transmute([]u8)source
    for line_end := 0; line_end <= len(bytes); line_end += 1 {
        if line_end < len(bytes) && bytes[line_end] != '\n' {
            continue
        }
        line := source[line_start:line_end]
        line_start = line_end + 1
        if len(line) == 0 {
            continue
        }
        if len(line) > SCENARIO_LINE_MAX_BYTES {
            return .Line_Too_Long
        }
        if program.count == SCENARIO_COMMAND_CAPACITY {
            return .Too_Many_Commands
        }
        raw: Raw_Command
        if json.unmarshal_string(line, &raw, allocator = context.temp_allocator) != nil {
            return .Invalid_Json
        }
        command, command_error := command_from_raw(raw)
        if command_error != .None {
            return command_error
        }
        program.commands[program.count] = command
        program.count += 1
    }
    return .None
}

//   Initialize one runner over a validated fixed program.
//
// Parameters:
//   - runner: Owner-controlled destination replaced with fresh execution state.
//   - program: Validated fixed program copied into the runner.
//
// Side effects:
//   - Clears aliases, progress, deadlines, and counters, then sets status to Ready.
runner_init :: proc(runner: ^Runner, program: Program) {
    runner^ = {program = program, status = .Ready}
}

//   Mark the current runner command as failed and stop command advancement.
runner_fail :: proc(runner: ^Runner) -> bool {
    runner.failure_count += 1
    runner.status = .Failed
    return false
}

//   Advance one event wait or retain the current command while waiting.
runner_update_event_wait :: proc(
    runner: ^Runner, command: ^Command, frame: Runner_Frame) -> bool {
    if runner.deadline_ns == 0 {
        runner.deadline_ns = deadline_from(frame.now_ns, command.timeout_ms)
    }
    if !runner_match_event(runner, command, frame.events) {
        runner_wait_or_fail(runner, frame.now_ns)
        return false
    }
    return true
}

//   Advance one observed-state wait or retain the current command while waiting.
runner_update_state_wait :: proc(
    runner: ^Runner, command: ^Command, frame: Runner_Frame) -> bool {
    if runner.deadline_ns == 0 {
        runner.deadline_ns = deadline_from(frame.now_ns, command.timeout_ms)
    }
    if !state_matches(text_string(&command.text), frame.display) {
        runner_wait_or_fail(runner, frame.now_ns)
        return false
    }
    return true
}

//   Evaluate one assertion against the bounded display observation.
runner_assert_state :: proc(
    runner: ^Runner, command: ^Command, display: observe.Display) -> bool {
    runner.assertion_count += 1
    if !state_matches(text_string(&command.text), display) {
        return runner_fail(runner)
    }
    return true
}

//   Evaluate one assertion through the owner-provided action boundary.
runner_assert_action :: proc(
    runner: ^Runner, command: ^Command, actions: Action_Sink) -> bool {
    runner.assertion_count += 1
    if actions.issue == nil || !actions.issue(actions.user_data, command).accepted {
        return runner_fail(runner)
    }
    return true
}

//   Issue one ordinary action and retain any requested correlation alias.
runner_issue_action :: proc(
    runner: ^Runner, command: ^Command, actions: Action_Sink) -> bool {
    result := Action_Result{accepted = actions.issue != nil}
    if actions.issue != nil {
        result = actions.issue(actions.user_data, command)
    }
    if !result.accepted {
        return runner_fail(runner)
    }
    if command.alias.count > 0 && result.correlation.id != 0 &&
        !runner_store_alias(runner, &command.alias, result.correlation) {
        return runner_fail(runner)
    }
    return true
}

//   Execute the current command and report whether advancement may continue.
runner_update_command :: proc(
    runner: ^Runner, command: ^Command, frame: Runner_Frame) -> bool {
    switch command.kind {
    case .Wait_Event:
        return runner_update_event_wait(runner, command, frame)
    case .Wait_State:
        return runner_update_state_wait(runner, command, frame)
    case .Assert_State:
        return runner_assert_state(runner, command, frame.display)
    case .Assert_Allocation_Baseline, .Assert_No_Bad_Frees:
        return runner_assert_action(runner, command, frame.actions)
    case .Reset_Animation, .Select_Animation, .Reload_Runtime,
         .Submit_Scratchpad, .Pause_Simulation, .Resume_Simulation,
         .Request_Screenshot, .Start_Gif, .Stop_Gif, .Checkpoint,
         .Allocation_Checkpoint, .Shutdown:
        return runner_issue_action(runner, command, frame.actions)
    }
    return false
}

//   Advance semantic work until waiting, terminal success, or failure.
//
// Parameters:
//   - runner: Scenario state owned by the calling control loop.
//   - frame: Current time, evidence, observations, and ordinary action boundary.
//
// Returns:
//   - Current runner status after bounded progress.
//
// Side effects:
//   - Advances commands and the trace cursor, invokes actions synchronously, stores
//     aliases, updates assertion counters, and transitions runner status.
//
// Notes:
//   - `events` is a stable cumulative snapshot for one run and may only grow.
//   - A loss of required trace evidence immediately makes the run Inconclusive.
//   - Terminal statuses are sticky; later calls return without invoking actions.
runner_update :: proc(
    runner: ^Runner, frame: Runner_Frame) -> Run_Status {
    if runner.status == .Passed || runner.status == .Failed ||
        runner.status == .Inconclusive {
        return runner.status
    }
    if !frame.display.required_evidence_complete {
        runner.status = .Inconclusive
        return runner.status
    }
    runner.status = .Running
    for runner.step < runner.program.count {
        command := &runner.program.commands[runner.step]
        if !runner_update_command(runner, command, frame) {
            return runner.status
        }
        runner.step += 1
        runner.deadline_ns = 0
    }
    runner.status = .Passed
    return runner.status
}

//   Select one nonempty text-bearing raw command field.
raw_text_command_select :: proc(
    source: string, kind: Command_Kind, command: ^Command) -> int {
    if len(source) == 0 {
        return 0
    }
    command.kind = kind
    command.text, _ = text_copy(source)
    return 1
}

//   Select one supported payload-free Euclid action name.
raw_action_command_select :: proc(source: string, command: ^Command) -> int {
    if len(source) == 0 {
        return 0
    }
    switch source {
    case "reset_animation": command.kind = .Reset_Animation
    case "reload_runtime": command.kind = .Reload_Runtime
    case "pause_simulation": command.kind = .Pause_Simulation
    case "resume_simulation": command.kind = .Resume_Simulation
    case "stop_gif": command.kind = .Stop_Gif
    case:
        return 2
    }
    command.text, _ = text_copy(source)
    return 1
}

//   Select every populated action field and return the number selected.
raw_command_select :: proc(raw: Raw_Command, command: ^Command) -> int {
    selected := 0
    selected += raw_action_command_select(raw.action, command)
    selected += raw_text_command_select(
        raw.select_animation, .Select_Animation, command)
    selected += raw_text_command_select(raw.scratchpad, .Submit_Scratchpad, command)
    selected += raw_text_command_select(
        raw.screenshot, .Request_Screenshot, command)
    selected += raw_text_command_select(raw.start_gif, .Start_Gif, command)
    selected += raw_text_command_select(raw.wait_event, .Wait_Event, command)
    selected += raw_text_command_select(raw.wait_state, .Wait_State, command)
    selected += raw_text_command_select(raw.assert_state, .Assert_State, command)
    selected += raw_text_command_select(raw.checkpoint, .Checkpoint, command)
    selected += raw_text_command_select(raw.allocation_checkpoint,
        .Allocation_Checkpoint, command)
    selected += raw_text_command_select(raw.assert_allocation_baseline,
        .Assert_Allocation_Baseline, command)
    if raw.assert_no_bad_frees {
        command.kind = .Assert_No_Bad_Frees
        selected += 1
    }
    if raw.shutdown {
        command.kind = .Shutdown
        selected += 1
    }
    return selected
}

//   Convert one decoded JSON object into exactly one bounded command.
//
// Parameters:
//   - raw: Temporary decoded fields from one nonempty JSON Lines record.
//
// Returns:
//   - The fixed command and None, or a zero command and stable validation error.
//
// Notes:
//   - Exactly one action field must be selected. Waits receive the default timeout
//     when omitted and reject values beyond the configured maximum.
command_from_raw :: proc(raw: Raw_Command) -> (Command, Parse_Error) {
    command: Command
    selected := raw_command_select(raw, &command)
    if selected != 1 {
        return {}, .Invalid_Command
    }
    if len(text_string(&command.text)) == 0 &&
        !command_kind_allows_empty_text(command.kind) {
        return {}, .Text_Too_Long
    }
    command.alias, _ = name_copy(raw.alias)
    command.correlation, _ = name_copy(raw.correlation)
    if len(raw.alias) > SCENARIO_NAME_CAPACITY ||
        len(raw.correlation) > SCENARIO_NAME_CAPACITY {
        return {}, .Name_Too_Long
    }
    command.timeout_ms = raw.timeout_ms
    if command.kind == .Wait_Event || command.kind == .Wait_State {
        if command.timeout_ms == 0 {
            command.timeout_ms = SCENARIO_DEFAULT_TIMEOUT_MS
        }
        if command.timeout_ms > SCENARIO_MAX_TIMEOUT_MS {
            return {}, .Invalid_Timeout
        }
    }
    return command, .None
}

//   Report whether one command intentionally carries no text payload.
command_kind_allows_empty_text :: proc(kind: Command_Kind) -> bool {
    switch kind {
    case .Assert_No_Bad_Frees, .Shutdown:
        return true
    case .Reset_Animation, .Select_Animation, .Reload_Runtime,
         .Submit_Scratchpad, .Pause_Simulation, .Resume_Simulation,
         .Request_Screenshot, .Start_Gif, .Stop_Gif, .Wait_Event,
         .Wait_State, .Assert_State, .Checkpoint, .Allocation_Checkpoint,
         .Assert_Allocation_Baseline:
        return false
    }
    return false
}

//   Copy borrowed text into fixed command storage.
//
// Parameters:
//   - source: Borrowed command payload bytes to copy.
//
// Returns:
//   - Inline text and true, or zero text and false when capacity is exceeded.
text_copy :: proc(source: string) -> (Text, bool) {
    if len(source) > SCENARIO_TEXT_CAPACITY {
        return {}, false
    }
    result: Text
    copy(result.bytes[:], transmute([]u8)source)
    result.count = len(source)
    return result, true
}

//   Copy borrowed text into fixed alias storage.
//
// Parameters:
//   - source: Borrowed alias bytes to copy.
//
// Returns:
//   - Inline name and true, or zero name and false when capacity is exceeded.
name_copy :: proc(source: string) -> (Name, bool) {
    if len(source) > SCENARIO_NAME_CAPACITY {
        return {}, false
    }
    result: Name
    copy(result.bytes[:], transmute([]u8)source)
    result.count = len(source)
    return result, true
}

//   Return a borrowed string over fixed text storage.
//
// Parameters:
//   - text: Fixed text whose initialized prefix will be exposed.
//
// Returns:
//   - A string borrowing the initialized inline bytes.
//
// Notes:
//   - The result remains valid only while text storage remains alive and stable.
text_string :: proc(text: ^Text) -> string {
    return string(text.bytes[:text.count])
}

//   Return a borrowed string over fixed name storage.
//
// Parameters:
//   - name: Fixed name whose initialized prefix will be exposed.
//
// Returns:
//   - A string borrowing the initialized inline bytes.
//
// Notes:
//   - The result remains valid only while name storage remains alive and stable.
name_string :: proc(name: ^Name) -> string {
    return string(name.bytes[:name.count])
}

//   Compute a saturating monotonic deadline from bounded milliseconds.
//
// Parameters:
//   - now_ns: Current monotonic timestamp in nanoseconds.
//   - timeout_ms: Nonnegative bounded duration in milliseconds.
//
// Returns:
//   - now_ns plus the converted duration, saturated at the maximum u64 value.
deadline_from :: proc(now_ns: u64, timeout_ms: u32) -> u64 {
    duration := u64(timeout_ms) * 1_000_000
    if now_ns > max(u64) - duration {
        return max(u64)
    }
    return now_ns + duration
}

//   Resolve a wait correlation and scan newly supplied events.
//
// Parameters:
//   - runner: Active runner owning the cumulative trace cursor and aliases.
//   - command: Current Wait_Event command.
//   - events: Stable cumulative event snapshot that may only grow.
//
// Returns:
//   - True when a matching event is consumed; false while absent or after failure.
//
// Side effects:
//   - Advances trace_cursor across every inspected event. Invalid event names or aliases
//     fail the runner; a cursor beyond the snapshot makes evidence Inconclusive.
runner_match_event :: proc(
    runner: ^Runner, command: ^Command, events: []trace.Event) -> bool {
    if runner.trace_cursor > len(events) {
        runner.status = .Inconclusive
        return false
    }
    expected_kind, valid := event_kind(text_string(&command.text))
    if !valid {
        runner.status = .Failed
        runner.failure_count += 1
        return false
    }
    correlation, correlation_valid := runner_alias_correlation(
        runner, &command.correlation)
    if !correlation_valid {
        runner.status = .Failed
        runner.failure_count += 1
        return false
    }
    for index in runner.trace_cursor..<len(events) {
        event := events[index]
        runner.trace_cursor = index + 1
        if event.kind == expected_kind &&
            (correlation.id == 0 ||
                (event.correlation_kind == correlation.kind &&
                 event.correlation == correlation.id &&
                 event.generation == correlation.generation)) {
            return true
        }
    }
    return false
}

//   Convert one stable script event name into vocabulary identity.
//
// Parameters:
//   - name: Public scenario event spelling.
//
// Returns:
//   - The trace kind and true, or Unknown and false for unsupported names.
event_kind :: proc(name: string) -> (trace.Kind, bool) {
    for entry in EVENT_KINDS {
        if entry.name == name {
            return entry.kind, true
        }
    }
    return .Unknown, false
}

//   Evaluate one stable scalar-state predicate.
//
// Parameters:
//   - name: Public scenario state-predicate spelling.
//   - display: Current pointer-free display observation.
//
// Returns:
//   - True when the named predicate currently holds; false for unknown names.
state_matches :: proc(name: string, display: observe.Display) -> bool {
    switch name {
    case "runtime_ready": return display.runtime_lifecycle == .Ready
    case "runtime_idle": return display.active_runtime_request_id == 0
    case "animation_idle": return !display.animation_tick_pending
    case "scratchpad_idle": return display.scratchpad_idle
    case "simulation_paused": return display.simulation_paused
    case "simulation_running": return !display.simulation_paused
    case "dynview_enabled": return display.dynview_enabled
    case "gif_active": return display.gif_capture_active
    case "gif_idle": return !display.gif_capture_active
    }
    return false
}

//   Return running before the deadline and fail at or after it.
//
// Parameters:
//   - runner: Active runner with an established monotonic deadline.
//   - now_ns: Current monotonic timestamp in nanoseconds.
//
// Returns:
//   - Existing terminal status, Running before the deadline, or Failed at timeout.
//
// Side effects:
//   - At timeout, increments failure_count and makes the runner status Failed.
runner_wait_or_fail :: proc(runner: ^Runner, now_ns: u64) -> Run_Status {
    if runner.status == .Failed || runner.status == .Inconclusive {
        return runner.status
    }
    if now_ns >= runner.deadline_ns {
        runner.failure_count += 1
        runner.status = .Failed
    }
    return runner.status
}

//   Store or replace one bounded action alias.
//
// Parameters:
//   - runner: Runner owning the fixed alias registry.
//   - name: Nonempty inline alias identity.
//   - correlation: Existing runtime correlation produced by the action sink.
//
// Returns:
//   - True after replacement or append; false when registry capacity is exhausted.
//
// Side effects:
//   - Replaces a matching correlation or appends one copied alias entry.
runner_store_alias :: proc(
    runner: ^Runner, name: ^Name, correlation: trace.Identity) -> bool {
    for &entry in runner.aliases[:runner.alias_count] {
        if name_string(&entry.name) == name_string(name) {
            entry.correlation = correlation
            return true
        }
    }
    if runner.alias_count < len(runner.aliases) {
        runner.aliases[runner.alias_count] = {name = name^, correlation = correlation}
        runner.alias_count += 1
        return true
    }
    return false
}

//   Resolve one alias, with an empty name representing no correlation constraint.
//
// Parameters:
//   - runner: Runner owning previously produced action aliases.
//   - name: Alias reference to resolve; an empty name selects wildcard correlation.
//
// Returns:
//   - Correlation and true for an empty or known name; zero and false if unknown.
runner_alias_correlation :: proc(
    runner: ^Runner, name: ^Name) -> (trace.Identity, bool) {
    if name.count == 0 {
        return {}, true
    }
    for &entry in runner.aliases[:runner.alias_count] {
        if name_string(&entry.name) == name_string(name) {
            return entry.correlation, true
        }
    }
    return {}, false
}
