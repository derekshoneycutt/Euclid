// Package termshellintegration owns bounded OSC 7/133 state and command indexing.
package termshellintegration

import "core:mem"
import termhyperlink "../hyperlink"
import termmodel "../model"

SHELL_CWD_URI_BYTE_CAPACITY :: 1024
SHELL_MARKER_PAYLOAD_BYTE_CAPACITY :: 32
SHELL_COMMAND_SEARCH_QUERY_BYTE_CAPACITY :: 256

// Parsed OSC 133 marker data committed only after complete validation.
Shell_Marker_Admission :: struct {
    kind: termmodel.Shell_Marker_Kind,
    status: i32,
    status_present: bool,
    valid: bool,
}

// Terminal-owned OSC 7/133 state with bounded transaction storage and telemetry.
Shell_Integration_State :: struct {
    // Fixed oldest-first command ring and separately retained active candidate.
    allocator: mem.Allocator,
    command_blocks: []termmodel.Command_Block,
    command_first: int,
    command_count: int,
    active_command: termmodel.Command_Block,
    active_command_present: bool,
    next_generation: u32,

    // Bounded local command-search query and current derived match identity.
    search_query: [SHELL_COMMAND_SEARCH_QUERY_BYTE_CAPACITY]u8,
    search_query_byte_count: int,
    search_editing: bool,
    search_match_generation: u32,
    search_match_byte_offset: int,

    // Last validated local working-directory URI observed from terminal output.
    observed_cwd_uri: [SHELL_CWD_URI_BYTE_CAPACITY]u8,
    observed_cwd_uri_byte_count: int,

    // Shared transactional payload storage for one active OSC 7 or OSC 133.
    candidate: [SHELL_CWD_URI_BYTE_CAPACITY]u8,
    candidate_byte_count: int,
    candidate_invalid: bool,

    // Content-free lifetime outcomes retained for terminal diagnostics.
    cwd_acceptance_count: u64,
    cwd_rejection_count: u64,
    marker_acceptance_count: u64,
    marker_rejection_count: u64,
    lifecycle_malformed_count: u64,
    command_eviction_count: u64,
}

// Allocate one fixed-capacity command-block ring for a terminal lifetime.
shell_integration_init :: proc(
    state: ^Shell_Integration_State, capacity: int,
    allocator: mem.Allocator) -> bool {
    if state == nil || capacity < 1 || len(state.command_blocks) != 0 {
        return false
    }
    blocks, allocation_error := make([]termmodel.Command_Block, capacity, allocator)
    if allocation_error != nil { return false }
    state^ = {allocator = allocator, command_blocks = blocks}
    return true
}

// Release command-block storage and clear all shell integration state.
shell_integration_destroy :: proc(state: ^Shell_Integration_State) {
    if state == nil { return }
    delete(state.command_blocks, state.allocator)
    state^ = {}
}

// Return one retained block in chronological order, including the active newest block.
shell_command_block :: proc(
    state: ^Shell_Integration_State,
    index: int) -> (termmodel.Command_Block, bool) {
    if state == nil || index < 0 { return {}, false }
    if index < state.command_count {
        slot := (state.command_first + index) % len(state.command_blocks)
        return state.command_blocks[slot], true
    }
    if index == state.command_count && state.active_command_present {
        return state.active_command, true
    }
    return {}, false
}

// Return the number of closed and active blocks currently available for navigation.
shell_command_block_count :: proc(state: ^Shell_Integration_State) -> int {
    if state == nil { return 0 }
    return state.command_count + int(state.active_command_present)
}

// Produce the next nonzero lifecycle generation.
shell_command_next_generation :: proc(state: ^Shell_Integration_State) -> u32 {
    state.next_generation += 1
    if state.next_generation == 0 { state.next_generation = 1 }
    return state.next_generation
}

// Append the active candidate to the bounded chronological ring and clear it.
shell_command_close_active :: proc(state: ^Shell_Integration_State) {
    if !state.active_command_present || len(state.command_blocks) == 0 { return }
    slot := (state.command_first + state.command_count) % len(state.command_blocks)
    if state.command_count == len(state.command_blocks) {
        slot = state.command_first
        if state.search_match_generation ==
            state.command_blocks[slot].generation {
            state.search_match_generation = 0
            state.search_match_byte_offset = 0
        }
        state.command_first = (state.command_first + 1) % len(state.command_blocks)
        state.command_eviction_count += 1
    } else {
        state.command_count += 1
    }
    state.command_blocks[slot] = state.active_command
    state.active_command = {}
    state.active_command_present = false
}

// Start one partial lifecycle candidate at a validated semantic marker.
shell_command_start :: proc(
    state: ^Shell_Integration_State, kind: termmodel.Shell_Marker_Kind,
    position: termmodel.Terminal_Semantic_Position) {
    state.active_command = {generation = shell_command_next_generation(state)}
    state.active_command_present = true
    state.active_command.present += {kind}
    switch kind {
    case .Prompt: state.active_command.prompt = position
    case .Command: state.active_command.command = position
    case .Execution: state.active_command.execution = position
    case .Finished: state.active_command.finished = position
    }
}

// Apply one forward lifecycle marker to the current active candidate.
shell_command_apply_marker :: proc(
    block: ^termmodel.Command_Block, admission: Shell_Marker_Admission,
    position: termmodel.Terminal_Semantic_Position) {
    block.present += {admission.kind}
    switch admission.kind {
    case .Command: block.command = position
    case .Execution: block.execution = position
    case .Finished:
        block.finished = position
        block.status = admission.status
        block.status_present = admission.status_present
    case .Prompt:
    }
}

// Report whether one marker repeats or regresses the active lifecycle.
shell_command_marker_malformed :: proc(
    block: ^termmodel.Command_Block, kind: termmodel.Shell_Marker_Kind) -> bool {
    return kind in block.present ||
        (kind == .Command && .Execution in block.present)
}

// Assemble one validated primary-screen marker into the bounded lifecycle index.
shell_command_admit_marker :: proc(
    state: ^Shell_Integration_State, admission: Shell_Marker_Admission,
    position: termmodel.Terminal_Semantic_Position) {
    if len(state.command_blocks) == 0 { return }
    if admission.kind == .Prompt {
        if state.active_command_present &&
            (.Command in state.active_command.present ||
             .Execution in state.active_command.present) {
            shell_command_close_active(state)
        }
        shell_command_start(state, .Prompt, position)
        return
    }
    if !state.active_command_present {
        shell_command_start(state, admission.kind, position)
    } else if shell_command_marker_malformed(
        &state.active_command, admission.kind) {
        state.lifecycle_malformed_count += 1
        shell_command_close_active(state)
        shell_command_start(state, admission.kind, position)
    } else {
        shell_command_apply_marker(&state.active_command, admission, position)
    }
    if admission.kind == .Finished { shell_command_close_active(state) }
}

// Remove blocks after their last semantic position leaves retained scrollback.
shell_command_evict_through :: proc(
    state: ^Shell_Integration_State, logical_line_id: i64) {
    if state == nil { return }
    for state.command_count > 0 {
        block := &state.command_blocks[state.command_first]
        last := shell_command_last_position(block)
        if i64(last.logical_line_id) > logical_line_id { break }
        if state.search_match_generation == block.generation {
            state.search_match_generation = 0
            state.search_match_byte_offset = 0
        }
        block^ = {}
        state.command_first = (state.command_first + 1) % len(state.command_blocks)
        state.command_count -= 1
        state.command_eviction_count += 1
    }
    if state.active_command_present &&
        i64(shell_command_last_position(
            &state.active_command).logical_line_id) <= logical_line_id {
        if state.search_match_generation == state.active_command.generation {
            state.search_match_generation = 0
            state.search_match_byte_offset = 0
        }
        state.active_command = {}
        state.active_command_present = false
        state.command_eviction_count += 1
    }
}

// Report whether a command generation remains in the closed ring or active candidate.
shell_command_generation_retained :: proc(
    state: ^Shell_Integration_State, generation: u32) -> bool {
    if state == nil || generation == 0 { return false }
    for index in 0..<state.command_count {
        slot := (state.command_first + index) % len(state.command_blocks)
        if state.command_blocks[slot].generation == generation { return true }
    }
    return state.active_command_present &&
        state.active_command.generation == generation
}

// Return the earliest semantic endpoint present in one command block.
shell_command_first_position :: proc(
    block: ^termmodel.Command_Block) -> termmodel.Terminal_Semantic_Position {
    if .Prompt in block.present { return block.prompt }
    if .Command in block.present { return block.command }
    if .Execution in block.present { return block.execution }
    return block.finished
}

// Return the latest semantic endpoint present in one command block.
shell_command_last_position :: proc(
    block: ^termmodel.Command_Block) -> termmodel.Terminal_Semantic_Position {
    if .Finished in block.present { return block.finished }
    if .Execution in block.present { return block.execution }
    if .Command in block.present { return block.command }
    return block.prompt
}

// Shift markers at or after an insertion point, dropping those past the row edge.
shell_markers_insert_columns :: proc(
    markers: ^termmodel.Shell_Row_Markers, start, amount, columns: int) {
    for kind in termmodel.Shell_Marker_Kind {
        if !markers.present[kind] || int(markers.columns[kind]) < start {
            continue
        }
        destination := int(markers.columns[kind]) + amount
        if destination >= columns {
            markers.present[kind] = false
        } else {
            markers.columns[kind] = u16(destination)
        }
    }
}

// Shift markers after a deleted range left and drop markers inside that range.
shell_markers_delete_columns :: proc(
    markers: ^termmodel.Shell_Row_Markers, start, amount, columns: int) {
    end := min(start + amount, columns)
    for kind in termmodel.Shell_Marker_Kind {
        if !markers.present[kind] || int(markers.columns[kind]) < start {
            continue
        }
        if int(markers.columns[kind]) < end {
            markers.present[kind] = false
        } else {
            markers.columns[kind] = u16(int(markers.columns[kind]) - amount)
        }
    }
}

// Commit one validated local file URI as display-observed working-directory state.
shell_integration_admit_cwd :: proc(
    state: ^Shell_Integration_State, uri: string) -> bool {
    if state == nil || len(uri) == 0 || len(uri) >= len(state.observed_cwd_uri) ||
        !termhyperlink.hyperlink_uri_valid(uri) {
        if state != nil {
            state.cwd_rejection_count += 1
        }
        return false
    }
    parsed, supported := termhyperlink.hyperlink_uri_scheme(uri)
    if !supported || parsed.scheme != .File {
        state.cwd_rejection_count += 1
        return false
    }
    state.observed_cwd_uri = {}
    copy(state.observed_cwd_uri[:], transmute([]u8)uri)
    state.observed_cwd_uri_byte_count = len(uri)
    state.cwd_acceptance_count += 1
    return true
}

// Parse one optional nonnegative decimal command status without partial results.
shell_integration_parse_status :: proc(bytes: []u8) -> (i32, bool) {
    if len(bytes) == 0 {
        return 0, false
    }
    value: u64
    for byte in bytes {
        if byte < '0' || byte > '9' {
            return 0, false
        }
        value = value * 10 + u64(byte - '0')
        if value > u64(max(i32)) {
            return 0, false
        }
    }
    return i32(value), true
}

// Parse one exact OSC 133 marker payload without mutating retained state.
shell_integration_parse_marker :: proc(payload: []u8) -> Shell_Marker_Admission {
    switch payload[0] {
    case 'A': return {kind = .Prompt, valid = len(payload) == 1}
    case 'B': return {kind = .Command, valid = len(payload) == 1}
    case 'C': return {kind = .Execution, valid = len(payload) == 1}
    case 'D':
        if len(payload) == 1 {
            return {kind = .Finished, valid = true}
        }
        if payload[1] != ';' { return {} }
        status, valid := shell_integration_parse_status(payload[2:])
        return {.Finished, status, valid, valid}
    }
    return {}
}
