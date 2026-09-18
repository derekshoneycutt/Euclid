package input

import "core:mem"

import "../../core/protocol"

// Maximum device-independent events retained in one device-poll frame.
INPUT_EVENT_CAPACITY :: 128

// Maximum synthetic events retained across frame boundaries.
INPUT_INJECTED_EVENT_CAPACITY :: 512

// Maximum encoded terminal bytes retained across display frames.
INPUT_BYTE_QUEUE_CAPACITY :: 64 * 1024

// Largest paste payload that leaves room for both bracketed-paste delimiters.
INPUT_PASTE_MAX_BYTES :: INPUT_BYTE_QUEUE_CAPACITY - 12

// Maximum active or staged bindings in one hotkey registry generation.
INPUT_HOTKEY_CAPACITY :: 32

// Display-lifetime fixed storage for input capture and queued terminal bytes.
//
// One instance is allocated before the display loop and reused until orderly
// shutdown. Frame views borrow its storage and remain valid only until the next poll.
Input_Runtime :: struct {
    // Current device-frame events and cumulative overflow evidence.
    events: [INPUT_EVENT_CAPACITY]Input_Event,
    event_count: int,
    event_overflow_count: u64,
    event_frame_overflowed: bool,
    correlation_accepted_count: u64,
    correlation_ambiguous_count: u64,

    // Synthetic events awaiting transfer into a later device frame.
    injected_events: [INPUT_INJECTED_EVENT_CAPACITY]Input_Event,
    injected_event_count: int,
    injected_event_rejection_count: u64,

    // Last window-focus sample used to report real transitions exactly once.
    window_focus_known: bool,
    window_focused: bool,

    // Last device-pointer sample used to distinguish real movement from mere polling.
    mouse_position_known: bool,
    device_mouse_position: Input_Position,

    // Owner-bound circular terminal-byte storage, destination identity, and
    // cumulative queue, delivery, paste-admission, and stale-discard diagnostics.
    byte_queue: [INPUT_BYTE_QUEUE_CAPACITY]u8,
    byte_queue_start: int,
    byte_queue_count: int,
    byte_queue_high_water: int,
    byte_queue_rejection_count: u64,
    input_fallback_count: u64,
    input_atomic_rejection_count: u64,
    byte_delivery_rejection_count: u64,
    paste_admission_count: u64,
    paste_rejection_count: u64,
    stale_byte_discard_count: u64,
    owner: Input_Owner,

    // Owner-bound application mouse capture and deferred release delivery.
    mouse_captured: Input_Mouse_Buttons,
    mouse_pending_releases: Input_Mouse_Buttons,
    mouse_release_positions: [3]Input_Terminal_Position,
    mouse_last_position: Input_Terminal_Position,
    mouse_last_position_valid: bool,
    mouse_last_pixel_coordinates: bool,

    // Last atomically accepted hotkey snapshot.
    active_bindings: [INPUT_HOTKEY_CAPACITY]Input_Hotkey_Binding,
    active_binding_count: int,
    active_registry_generation: u64,

    // In-progress snapshot and its first validation failure.
    staging_bindings: [INPUT_HOTKEY_CAPACITY]Input_Hotkey_Binding,
    staging_indexes: [INPUT_HOTKEY_CAPACITY]bool,
    staging_binding_count: int,
    staging_expected_count: int,
    staging_registry_generation: u64,
    staging_reason: protocol.Hotkey_Registry_Reason,
    staging_offending_index: i32,

    // Cumulative whole-snapshot transaction outcomes.
    registry_acceptance_count: u64,
    registry_rejection_count: u64,
    registry_abandonment_count: u64,
}

// Candidate indexes and counts collected for one conservative reconciliation pass.
Input_Event_Correlation_Candidates :: struct {
    physical_index: int,
    physical_count: int,
    text_start: int,
    text_count: int,
}

// Outcome of classifying one frame's conservative correlation evidence.
Input_Event_Correlation_Status :: enum u8 {
    None,
    Ambiguous,
    Accepted,
}

// Fixed frame-local record of events already consumed by an extended encoder.
Input_Event_Claim_State :: struct {
    claimed: [INPUT_EVENT_CAPACITY]bool,
}

// Record one window-focus sample and return current state plus transition status.
input_runtime_update_window_focus :: proc(
    runtime: ^Input_Runtime, focused: bool) -> (current, changed: bool) {
    if runtime == nil {
        return focused, false
    }
    changed = runtime.window_focus_known && runtime.window_focused != focused
    runtime.window_focus_known = true
    runtime.window_focused = focused
    return focused, changed
}

// Record one device-pointer sample and report movement after initialization.
//
// Parameters:
//   - runtime: Display-owned pointer history; nil cannot retain a sample.
//   - position: Current screen-space device position.
//
// Returns:
//   - True only when a preceding sample exists and differs from position.
//
// Side effects:
//   - Stores position as the next frame's comparison baseline.
input_runtime_update_mouse_position :: proc(
    runtime: ^Input_Runtime, position: Input_Position) -> bool {
    if runtime == nil {
        return false
    }
    moved := runtime.mouse_position_known &&
        runtime.device_mouse_position != position
    runtime.mouse_position_known = true
    runtime.device_mouse_position = position
    return moved
}

// Allocate one zeroed fixed-layout input runtime for the display lifetime.
//
// Parameters:
//   - allocator: Allocator that owns the returned runtime storage.
//
// Returns:
//   - Newly allocated zeroed runtime, or nil when allocation fails.
//
// Side effects:
//   - Allocates one Input_Runtime through allocator.
input_runtime_create :: proc(allocator: mem.Allocator) -> ^Input_Runtime {
    return new(Input_Runtime, allocator)
}

// Release a display-owned input runtime through its creating allocator.
//
// Parameters:
//   - runtime: Runtime allocated by input_runtime_create; nil is accepted.
//   - allocator: The same allocator used to create runtime.
//
// Side effects:
//   - Invalidates runtime and every slice borrowed from it.
input_runtime_destroy :: proc(runtime: ^Input_Runtime, allocator: mem.Allocator) {
    if runtime == nil {
        return
    }
    free(runtime, allocator)
}

// Reset frame-local capture while preserving queues and lifetime diagnostics.
//
// Parameters:
//   - runtime: Display-owned input state to prepare for a new poll.
//
// Returns:
//   - True when runtime exists and frame storage was prepared.
//
// Side effects:
//   - Moves the oldest bounded synthetic-event prefix into the current frame.
//   - Invalidates slices previously returned by input_runtime_events.
input_runtime_begin_frame :: proc(runtime: ^Input_Runtime) -> bool {
    if runtime == nil {
        return false
    }
    count := min(runtime.injected_event_count, len(runtime.events))
    copy(runtime.events[:count], runtime.injected_events[:count])
    runtime.event_count = count
    runtime.event_frame_overflowed = false
    copy(runtime.injected_events[:], runtime.injected_events[count:
        runtime.injected_event_count])
    runtime.injected_event_count -= count
    return true
}

// Retain one complete synthetic event sequence for ordinary next-frame polling.
//
// Parameters:
//   - runtime: Display-owned input state retaining the event sequence.
//   - events: Nonempty borrowed sequence copied before return.
//
// Returns:
//   - True when the complete sequence fits; false without partial admission.
//
// Side effects:
//   - Increments injected_event_rejection_count when non-nil storage rejects input.
input_runtime_inject_events :: proc(
    runtime: ^Input_Runtime, events: []Input_Event) -> bool {
    if runtime == nil || len(events) == 0 ||
        len(events) > len(runtime.injected_events) - runtime.injected_event_count {
        if runtime != nil {
            runtime.injected_event_rejection_count += 1
        }
        return false
    }
    start := runtime.injected_event_count
    for event, index in events {
        synthetic := event
        synthetic.origin = .Synthetic
        synthetic.correlation = {}
        runtime.injected_events[start + index] = synthetic
    }
    runtime.injected_event_count += len(events)
    return true
}

// Append one input event or record bounded capture pressure.
//
// Parameters:
//   - runtime: Display-owned input state for the current device frame.
//   - event: Device-independent event copied into frame storage.
//
// Returns:
//   - True when retained; false for nil or full storage.
//
// Side effects:
//   - Increments event_overflow_count when non-nil frame storage is full.
input_runtime_append_event :: proc(
    runtime: ^Input_Runtime, event: Input_Event) -> bool {
    if runtime == nil || runtime.event_count >= len(runtime.events) {
        if runtime != nil {
            runtime.event_overflow_count += 1
            runtime.event_frame_overflowed = true
        }
        return false
    }
    runtime.events[runtime.event_count] = event
    runtime.event_count += 1
    return true
}

// Report whether one device key can plausibly produce a text event.
input_event_is_text_candidate :: proc(event: Input_Event) -> bool {
    if event.origin != .Device ||
        (event.kind != .Press && event.kind != .Repeat) {
        return false
    }
    return event.key >= .Space && event.key <= .Grave ||
        event.key >= .Keypad0 && event.key <= .Keypad_Equal &&
        event.key != .Keypad_Enter
}

// Collect device-originated physical and text candidates from current frame storage.
input_runtime_correlation_candidates :: proc(
    runtime: ^Input_Runtime) -> Input_Event_Correlation_Candidates {
    candidates := Input_Event_Correlation_Candidates{
        physical_index = -1,
        text_start = -1,
    }
    for event, index in runtime.events[:runtime.event_count] {
        if input_event_is_text_candidate(event) {
            candidates.physical_index = index
            candidates.physical_count += 1
        } else if event.origin == .Device && event.kind == .Text &&
            event.codepoint != 0 {
            if candidates.text_start < 0 { candidates.text_start = index }
            candidates.text_count += 1
        }
    }
    return candidates
}

// Clear frame-local correlation metadata before one reconciliation pass.
input_runtime_reset_correlations :: proc(runtime: ^Input_Runtime) {
    for &event in runtime.events[:runtime.event_count] {
        event.correlation = {}
    }
}

// Publish one physical/bounded-text correlation and update diagnostics.
input_runtime_accept_correlation :: proc(
    runtime: ^Input_Runtime, candidates: Input_Event_Correlation_Candidates) {
    physical := &runtime.events[candidates.physical_index]
    physical.correlation = {
        partner_index = u16(candidates.text_start),
        partner_count = u16(candidates.text_count),
        valid = true,
    }
    for index in candidates.text_start..<candidates.text_start + candidates.text_count {
        runtime.events[index].correlation = {
            partner_index = u16(candidates.physical_index),
            partner_count = 1,
            valid = true,
        }
    }
    runtime.correlation_accepted_count += 1
}

// Classify whether current candidates support one trustworthy frame-local pair.
input_runtime_correlation_status :: proc(
    runtime: ^Input_Runtime,
    candidates: Input_Event_Correlation_Candidates) -> Input_Event_Correlation_Status {
    has_candidate := candidates.physical_count > 0 || candidates.text_count > 0
    if runtime.event_frame_overflowed {
        return .Ambiguous if has_candidate else .None
    }
    if candidates.physical_count == 0 || candidates.text_count == 0 {
        return .None
    }
    if candidates.physical_count != 1 || candidates.text_count == 0 {
        return .Ambiguous
    }
    physical := runtime.events[candidates.physical_index]
    for index in candidates.text_start..<candidates.text_start + candidates.text_count {
        if physical.modifiers != runtime.events[index].modifiers {
            return .Ambiguous
        }
    }
    return .Accepted
}

// Correlate one unambiguous device physical/text pair without inferring OS order.
//
// Parameters:
//   - runtime: Current fixed event frame and cumulative correlation diagnostics.
//
// Side effects:
//   - Clears stale correlation metadata, records one reciprocal pair when evidence is
//     sufficient, and increments accepted or ambiguous count at most once per frame.
input_runtime_reconcile_events :: proc(runtime: ^Input_Runtime) {
    if runtime == nil {
        return
    }
    input_runtime_reset_correlations(runtime)
    candidates := input_runtime_correlation_candidates(runtime)
    switch input_runtime_correlation_status(runtime, candidates) {
    case .None:
        return
    case .Ambiguous:
        runtime.correlation_ambiguous_count += 1
    case .Accepted:
        input_runtime_accept_correlation(runtime, candidates)
    }
}

// Return whether every correlated text event is valid and unclaimed.
input_event_text_claims_valid :: proc(
    frame: Input_Frame, physical_index, text_start, text_count: int,
    state: ^Input_Event_Claim_State) -> bool {
    for index in text_start..<text_start + text_count {
        text := frame.events[index]
        if text.kind != .Text || state.claimed[index] ||
            !text.correlation.valid ||
            text.correlation.partner_index != u16(physical_index) {
            return false
        }
    }
    return true
}

// Atomically mark one correlated physical/text group after protocol-byte admission.
//
// Parameters:
//   - frame: Frame containing reciprocal correlation metadata.
//   - event_index: Index of either event in the pair.
//   - state: Frame-local fixed claim state mutated only on success.
//
// Returns:
//   - True when every valid unclaimed group index is marked; otherwise false.
input_event_claim_pair :: proc(
    frame: Input_Frame, event_index: int, state: ^Input_Event_Claim_State) -> bool {
    if state == nil || event_index < 0 || event_index >= len(frame.events) {
        return false
    }
    event := frame.events[event_index]
    if !event.correlation.valid || state.claimed[event_index] {
        return false
    }
    physical_index := event_index
    if event.kind == .Text {
        physical_index = int(event.correlation.partner_index)
    }
    if physical_index < 0 || physical_index >= len(frame.events) ||
        frame.events[physical_index].kind == .Text || state.claimed[physical_index] {
        return false
    }
    physical := frame.events[physical_index]
    text_start := int(physical.correlation.partner_index)
    text_count := max(int(physical.correlation.partner_count), 1)
    if !physical.correlation.valid || text_start < 0 ||
        text_start + text_count > len(frame.events) {
        return false
    }
    if !input_event_text_claims_valid(
        frame, physical_index, text_start, text_count, state) { return false }
    state.claimed[physical_index] = true
    for index in text_start..<text_start + text_count {
        state.claimed[index] = true
    }
    return true
}

// Borrow the valid input-event prefix until the next frame reset.
//
// Parameters:
//   - runtime: Runtime owning the current frame storage.
//
// Returns:
//   - Borrowed current-frame events, or nil for a nil runtime.
//
// Notes:
//   - The returned slice aliases runtime and becomes stale at the next frame reset.
input_runtime_events :: proc(runtime: ^Input_Runtime) -> []Input_Event {
    if runtime == nil {
        return nil
    }
    return runtime.events[:runtime.event_count]
}

// Change byte ownership, discarding anything retained for a stale consumer.
//
// Parameters:
//   - runtime: Display-owned input state containing the retained byte queue.
//   - owner: Complete destination identity for subsequent queued bytes.
//
// Returns:
//   - True when runtime exists; repeated assignment of the same owner is a no-op.
//
// Side effects:
//   - Clears queued bytes on an owner change and records the discarded byte count.
input_runtime_set_owner :: proc(
    runtime: ^Input_Runtime, owner: Input_Owner) -> bool {
    if runtime == nil {
        return false
    }
    if runtime.owner == owner {
        return true
    }
    runtime.stale_byte_discard_count += u64(runtime.byte_queue_count)
    runtime.byte_queue_start = 0
    runtime.byte_queue_count = 0
    runtime.mouse_captured = {}
    runtime.mouse_pending_releases = {}
    runtime.mouse_release_positions = {}
    runtime.mouse_last_position = {}
    runtime.mouse_last_position_valid = false
    runtime.mouse_last_pixel_coordinates = false
    runtime.owner = owner
    return true
}

// Atomically append one complete byte sequence to the circular queue.
//
// Parameters:
//   - runtime: Owner-bound byte queue receiving the sequence.
//   - bytes: Nonempty borrowed sequence copied before return.
//
// Returns:
//   - True when every byte fits; false without partial admission.
//
// Side effects:
//   - Updates queue depth and high-water accounting on success.
//   - Increments byte_queue_rejection_count when capacity rejects the sequence.
input_runtime_enqueue_bytes :: proc(runtime: ^Input_Runtime, bytes: []u8) -> bool {
    if runtime == nil || len(bytes) == 0 {
        return false
    }
    if len(bytes) > len(runtime.byte_queue) - runtime.byte_queue_count {
        runtime.byte_queue_rejection_count += 1
        return false
    }
    end := (runtime.byte_queue_start + runtime.byte_queue_count) %
        len(runtime.byte_queue)
    first_count := min(len(bytes), len(runtime.byte_queue) - end)
    copy(runtime.byte_queue[end:end + first_count], bytes[:first_count])
    copy(runtime.byte_queue[:], bytes[first_count:])
    runtime.byte_queue_count += len(bytes)
    runtime.byte_queue_high_water = max(
        runtime.byte_queue_high_water, runtime.byte_queue_count)
    return true
}

// Copy the oldest retained bytes into caller storage without consuming them.
//
// Parameters:
//   - runtime: Runtime owning the circular byte queue.
//   - destination: Caller-owned output storage.
//
// Returns:
//   - Number of bytes copied from the queue head.
//
// Side effects:
//   - Overwrites only the returned prefix of destination.
input_runtime_copy_queued_bytes :: proc(
    runtime: ^Input_Runtime, destination: []u8) -> int {
    if runtime == nil || len(destination) == 0 || runtime.byte_queue_count == 0 {
        return 0
    }
    count := min(len(destination), runtime.byte_queue_count)
    first_count := min(count, len(runtime.byte_queue) - runtime.byte_queue_start)
    copy(destination[:first_count],
        runtime.byte_queue[runtime.byte_queue_start:
            runtime.byte_queue_start + first_count])
    copy(destination[first_count:count], runtime.byte_queue[:count - first_count])
    return count
}

// Consume an accepted byte prefix from the circular queue.
//
// Parameters:
//   - runtime: Runtime owning the circular byte queue.
//   - count: Number of oldest bytes already accepted by the current owner.
//
// Returns:
//   - True when count is within the retained prefix; false without mutation.
//
// Side effects:
//   - Advances or resets the queue head and decreases retained byte count.
input_runtime_pop_queued_bytes :: proc(runtime: ^Input_Runtime, count: int) -> bool {
    if runtime == nil || count < 0 || count > runtime.byte_queue_count {
        return false
    }
    runtime.byte_queue_start = (runtime.byte_queue_start + count) %
        len(runtime.byte_queue)
    runtime.byte_queue_count -= count
    if runtime.byte_queue_count == 0 {
        runtime.byte_queue_start = 0
    }
    return true
}

// Begin one complete hotkey snapshot, abandoning any older incomplete staging.
//
// Parameters:
//   - runtime: Display-owned registry state to reset for staging.
//   - command: Generation identity and declared entry count.
//
// Side effects:
//   - Clears staging storage while preserving the active registry.
//   - Records abandonment and initial transaction validation failures.
input_runtime_begin_registry :: proc(
    runtime: ^Input_Runtime, command: protocol.Hotkey_Registry_Begin) {
    if runtime.staging_registry_generation != 0 &&
        runtime.staging_binding_count != runtime.staging_expected_count {
        runtime.registry_abandonment_count += 1
    }
    runtime.staging_bindings = {}
    runtime.staging_indexes = {}
    runtime.staging_binding_count = 0
    runtime.staging_expected_count = int(command.expected_count)
    runtime.staging_registry_generation = command.generation
    runtime.staging_reason = .None
    runtime.staging_offending_index = -1
    if command.generation == 0 ||
        command.generation <= runtime.active_registry_generation {
        runtime.staging_reason = .Invalid_Generation
    } else if command.expected_count < 0 ||
        command.expected_count > INPUT_HOTKEY_CAPACITY {
        runtime.staging_reason = .Invalid_Count
    }
}

// Convert one protocol key into the portable input vocabulary.
//
// Parameters:
//   - key: Protocol key value received from the worker boundary.
//
// Returns:
//   - Corresponding input key and true, or zero and false when unsupported.
input_hotkey_key :: proc(key: protocol.Hotkey_Key) -> (Input_Key, bool) {
    if key >= .A && key <= .Z {
        return Input_Key(int(Input_Key.A) + int(key) - int(protocol.Hotkey_Key.A)), true
    }
    if key >= .F1 && key <= .F12 {
        return Input_Key(
            int(Input_Key.F1) + int(key) - int(protocol.Hotkey_Key.F1)), true
    }
    return {}, false
}

// Record the first staging failure while retaining the active snapshot.
//
// Parameters:
//   - runtime: Registry state for the current staging transaction.
//   - reason: Stable protocol reason for rejecting the transaction.
//   - index: Offending entry index, or a negative value for transaction failure.
//
// Side effects:
//   - Stores only the first failure so later validation cannot obscure its cause.
input_runtime_reject_registry :: proc(
    runtime: ^Input_Runtime, reason: protocol.Hotkey_Registry_Reason,
    index: i32) {
    if runtime.staging_reason == .None {
        runtime.staging_reason = reason
        runtime.staging_offending_index = index
    }
}

// Validate protocol values independent of transaction index state.
//
// Parameters:
//   - command: Candidate entry whose semantic chord and scope are validated.
//
// Returns:
//   - Portable binding with None, or zero binding with the rejection reason.
//
// Notes:
//   - Reserved-global chords require multiple modifiers and cannot shadow built-ins.
input_registry_binding :: proc(command: protocol.Hotkey_Registry_Entry) ->
    (Input_Hotkey_Binding, protocol.Hotkey_Registry_Reason) {
    key, key_valid := input_hotkey_key(command.key)
    if !key_valid {
        return {}, .Unknown_Key
    }
    if command.action != .Toggle_Terminal {
        return {}, .Unknown_Action
    }
    modifiers := transmute(Input_Modifiers)command.modifiers
    if command.modifiers == 0 || command.modifiers & ~u8(0x0f) != 0 {
        return {}, .Invalid_Modifiers
    }
    if command.scope != .Application && command.scope != .Reserved_Global {
        return {}, .Invalid_Scope
    }
    if command.scope == .Reserved_Global && card(modifiers) < 2 {
        return {}, .Invalid_Modifiers
    }
    if command.scope == .Reserved_Global &&
        (key == .C || key == .V) && modifiers == {.Control, .Shift} {
        return {}, .Builtin_Conflict
    }
    return {
        action = command.action, key = key,
        modifiers = modifiers, scope = command.scope,
    }, .None
}

// Validate and stage one indexed semantic binding.
//
// Parameters:
//   - runtime: Registry state for the current staging transaction.
//   - command: Indexed entry belonging to the declared generation.
//
// Side effects:
//   - Retains one valid unique entry, or records the first transaction failure.
//   - Never changes the active registry.
input_runtime_stage_registry_entry :: proc(
    runtime: ^Input_Runtime, command: protocol.Hotkey_Registry_Entry) {
    if command.generation != runtime.staging_registry_generation {
        input_runtime_reject_registry(runtime, .Invalid_Generation, command.index)
        return
    }
    if command.index < 0 || command.index >= i32(runtime.staging_expected_count) {
        input_runtime_reject_registry(runtime, .Invalid_Index, command.index)
        return
    }
    index := int(command.index)
    if runtime.staging_indexes[index] {
        input_runtime_reject_registry(runtime, .Duplicate_Index, command.index)
        return
    }
    binding, reason := input_registry_binding(command)
    if reason != .None {
        input_runtime_reject_registry(runtime, reason, command.index)
        return
    }
    for staged, staged_index in runtime.staging_bindings {
        if runtime.staging_indexes[staged_index] &&
            staged.key == binding.key && staged.modifiers == binding.modifiers {
            input_runtime_reject_registry(runtime, .Duplicate_Chord, command.index)
            return
        }
    }
    runtime.staging_bindings[index] = binding
    runtime.staging_indexes[index] = true
    runtime.staging_binding_count += 1
}

// Atomically publish one complete valid snapshot and report its disposition.
//
// Parameters:
//   - runtime: Registry state containing active and staged snapshots.
//   - command: Commit request identifying the staged generation.
//
// Returns:
//   - Correlated acceptance result and first stable rejection detail.
//
// Side effects:
//   - Replaces the active registry only when the complete staged snapshot is valid.
//   - Increments exactly one acceptance or rejection counter.
input_runtime_commit_registry :: proc(
    runtime: ^Input_Runtime,
    command: protocol.Hotkey_Registry_Commit) -> protocol.Hotkey_Registry_Result {
    if command.generation != runtime.staging_registry_generation {
        input_runtime_reject_registry(runtime, .Invalid_Generation, -1)
    } else if runtime.staging_binding_count != runtime.staging_expected_count {
        input_runtime_reject_registry(runtime, .Incomplete, -1)
    }
    result := protocol.Hotkey_Registry_Result{
        generation = command.generation,
        reason = runtime.staging_reason,
        offending_index = runtime.staging_offending_index,
    }
    if result.reason != .None {
        runtime.registry_rejection_count += 1
        return result
    }
    runtime.active_bindings = runtime.staging_bindings
    runtime.active_binding_count = runtime.staging_binding_count
    runtime.active_registry_generation = command.generation
    runtime.registry_acceptance_count += 1
    result.accepted = true
    return result
}

