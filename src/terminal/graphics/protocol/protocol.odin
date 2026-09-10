// Package termgraphicsprotocol owns terminal graphics wire state and bounded queues.
package termgraphicsprotocol

import termattachment "../../attachment"
import termmodel "../../model"

// Fixed framing limits independent of encoded attachment payload quotas.
GRAPHICS_HEADER_BYTE_CAPACITY :: 1024
GRAPHICS_FRAME_CAPACITY :: 4
GRAPHICS_DECODE_REQUEST_CAPACITY :: 4
KITTY_GRAPHICS_RESPONSE_CAPACITY :: 16
KITTY_ANIMATION_COMMAND_CAPACITY :: 16
KITTY_MUTATION_REQUEST_CAPACITY :: 16
KITTY_IMAGE_IDENTITY_CAPACITY :: 256
KITTY_PLACEMENT_IDENTITY_CAPACITY :: 1024

// Kitty image, placement, and animation actions implemented by terminal semantics.
Kitty_Graphics_Action :: enum u8 {
    Transmit,
    Transmit_And_Place,
    Place,
    Delete,
    Query,
    Frame,
    Animate,
    Compose,
}

// Parsed, bounded controls for one supported Kitty command.
Kitty_Controls :: struct {
    action: Kitty_Graphics_Action,
    format: int,
    width: int,
    height: int,
    columns: int,
    rows: int,
    source_x: int,
    source_y: int,
    source_width: int,
    source_height: int,
    offset_x: int,
    offset_y: int,
    z_index: i32,
    gap_ms: i32,
    base_frame: int,
    edit_frame: int,
    current_frame: int,
    animation_state: int,
    loop_count: u32,
    background_rgba: u32,
    composition_mode: int,
    gap_specified: bool,
    background_specified: bool,
    preserve_cursor: bool,
    image_id: u32,
    image_number: u32,
    placement_id: u32,
    quiet: int,
    delete_selector: u8,
    zlib_compressed: bool,
    more: bool,
    valid: bool,
}

// Completed wire transaction awaiting Phase 4 protocol semantics.
Graphics_Frame_Kind :: enum u8 {
    Kitty,
    Sixel,
    Iterm2_File,
    Iterm2_Multipart_File,
    Iterm2_File_Part,
    Iterm2_File_End,
}

// Bounded immutable framing result with transfer ownership passed to its consumer.
Graphics_Frame :: struct {
    // Protocol classification and producer correlation.
    kind: Graphics_Frame_Kind,
    producer: termmodel.Terminal_Producer,

    // Decoded or raw transfer and protocol control bytes.
    transfer_id: termattachment.Transfer_Id,
    header: [GRAPHICS_HEADER_BYTE_CAPACITY]u8,
    header_byte_count: int,
}

// Encoded or indexed preparation category consumed by Phase 5 workers.
Graphics_Decode_Kind :: enum u8 {
    Kitty_Png,
    Kitty_Zlib_Rgb,
    Kitty_Zlib_Rgba,
    Sixel,
    Iterm2_Image,
    Iterm2_Gif_Preflight,
    Iterm2_Animated_Gif,
}

// Bounded immutable decode input with synchronous placement intent.
Graphics_Decode_Request :: struct {
    // Work classification, transfer ownership, target generation, and producer correlation.
    kind: Graphics_Decode_Kind,
    producer: termmodel.Terminal_Producer,
    transfer_id: termattachment.Transfer_Id,
    attachment_id: termattachment.Attachment_Id,
    mutation_sequence: u64,

    // Declared dimensions and encoded byte validation.
    width: int,
    height: int,
    declared_byte_count: int,

    // Placement intent committed synchronously before asynchronous preparation.
    place: bool,
    geometry: termattachment.Placement_Geometry,
    preserve_aspect_ratio: bool,
    width_percent: int,
    height_percent: int,

    // Sixel indexed-raster color and background semantics.
    palette: [256]u32,
    palette_count: int,
    transparent_background: bool,

    // Optional Kitty protocol identities retained for publication correlation.
    image_id: u32,
    image_number: u32,
    placement_id: u32,
}

// Stable Kitty acknowledgement classification retained without arbitrary text.
Kitty_Graphics_Response_Status :: enum u8 {
    Ok,
    Invalid,
    Not_Found,
    Unsupported,
    Capacity_Exceeded,
}

// Display-owned effect retained after one ordered Kitty timeline mutation.
Kitty_Animation_Command_Kind :: enum u8 {
    Refresh,
    Control,
}

// Exact-generation command consumed by display playback in terminal stream order.
Kitty_Animation_Command :: struct {
    attachment_id: termattachment.Attachment_Id,
    kind: Kitty_Animation_Command_Kind,
    current_frame: int,
    animation_state: int,
}

// Store mutation category serialized per terminal stream before display effects.
Kitty_Mutation_Kind :: enum u8 {
    Frame,
    Compose,
    Control,
    Delete,
}

// Exact-generation Kitty mutation retained until prior preparation has completed.
Kitty_Mutation_Request :: struct {
    sequence: u64,
    attachment_id: termattachment.Attachment_Id,
    temporary_attachment_id: termattachment.Attachment_Id,
    transfer_id: termattachment.Transfer_Id,
    controls: Kitty_Controls,
    kind: Kitty_Mutation_Kind,
    ready: bool,
}

// Decoded bytes and initialized length for one canonical Base64 quantum.
Graphics_Base64_Quantum :: struct {
    bytes: [3]u8,
    byte_count: int,
}

// Producer-correlated values sufficient to encode one bounded Kitty response.
Kitty_Graphics_Response :: struct {
    producer: termmodel.Terminal_Producer,
    image_id: u32,
    image_number: u32,
    placement_id: u32,
    status: Kitty_Graphics_Response_Status,
}

// Protocol image identity mapped to one current internal generation.
Kitty_Image_Identity :: struct {
    image_id: u32,
    image_number: u32,
    attachment_id: termattachment.Attachment_Id,
    active: bool,
}

// Protocol placement identity mapped to one current internal generation.
Kitty_Placement_Identity :: struct {
    placement_id: u32,
    image_id: u32,
    internal_id: termattachment.Placement_Id,
    active: bool,
}

// Retained incremental graphics parser and completed transaction queues.
Graphics_Parser_State :: struct {
    // Borrowed attachment store and active transfer ownership.
    store: ^termattachment.Store,
    transfer_id: termattachment.Transfer_Id,
    semantics_enabled: bool,

    // Current protocol header and incremental Base64 quantum.
    header: [GRAPHICS_HEADER_BYTE_CAPACITY]u8,
    header_byte_count: int,
    base64_quantum: [4]u8,
    base64_quantum_count: int,
    base64_finished: bool,
    invalid: bool,

    // Completed frames retained in admission order.
    frames: [GRAPHICS_FRAME_CAPACITY]Graphics_Frame,
    frame_count: int,

    // Validated work awaiting finite CPU preparation.
    decode_requests: [GRAPHICS_DECODE_REQUEST_CAPACITY]Graphics_Decode_Request,
    decode_request_count: int,

    // Active iTerm2 multipart transfer assembled before one decode request.
    iterm_multipart_transfer_id: termattachment.Transfer_Id,
    iterm_multipart_producer: termmodel.Terminal_Producer,
    iterm_multipart_request: Graphics_Decode_Request,
    iterm_multipart_active: bool,

    // Bounded Kitty replies retained in admission order.
    kitty_responses: [KITTY_GRAPHICS_RESPONSE_CAPACITY]Kitty_Graphics_Response,
    kitty_response_count: int,

    // Ordered animation effects retained until the display service commits them.
    kitty_animation_commands: [KITTY_ANIMATION_COMMAND_CAPACITY]Kitty_Animation_Command,
    kitty_animation_command_count: int,

    // Store mutations retained in terminal stream order across worker preparation.
    kitty_mutation_requests: [KITTY_MUTATION_REQUEST_CAPACITY]Kitty_Mutation_Request,
    kitty_mutation_request_count: int,
    kitty_mutation_sequence: u64,

    // Kitty protocol identity maps retained independently from store slots.
    kitty_images: [KITTY_IMAGE_IDENTITY_CAPACITY]Kitty_Image_Identity,
    kitty_placements: [KITTY_PLACEMENT_IDENTITY_CAPACITY]Kitty_Placement_Identity,

    // Active direct-transfer chunk assembly retained across APC sequences.
    kitty_chunk_frame: Graphics_Frame,
    kitty_chunk_controls: Kitty_Controls,
    kitty_chunk_producer: termmodel.Terminal_Producer,
    kitty_chunk_active: bool,

    // Content-free lifetime diagnostics.
    frame_rejection_count: u64,
    gif_preflight_acceptance_count: u64,
    gif_preflight_rejection_count: u64,
    kitty_response_rejection_count: u64,
    kitty_response_stale_discard_count: u64,
}

// Report whether one more ordered Kitty store mutation can be retained.
graphics_parser_mutation_request_has_capacity :: proc(
    state: ^Graphics_Parser_State) -> bool {
    return state != nil &&
        state.kitty_mutation_request_count < len(state.kitty_mutation_requests)
}

// Retain one Kitty store mutation and assign its nonzero stream sequence.
graphics_parser_queue_mutation_request :: proc(
    state: ^Graphics_Parser_State, request: Kitty_Mutation_Request) -> (u64, bool) {
    if !graphics_parser_mutation_request_has_capacity(state) { return 0, false }
    state.kitty_mutation_sequence += 1
    if state.kitty_mutation_sequence == 0 { state.kitty_mutation_sequence = 1 }
    candidate := request
    candidate.sequence = state.kitty_mutation_sequence
    state.kitty_mutation_requests[state.kitty_mutation_request_count] = candidate
    state.kitty_mutation_request_count += 1
    return candidate.sequence, true
}

// Mark one retained encoded mutation ready after exact temporary-target preparation.
graphics_parser_mark_mutation_ready :: proc(
    state: ^Graphics_Parser_State, sequence: u64,
    temporary_attachment_id: termattachment.Attachment_Id) -> bool {
    if state == nil || sequence == 0 { return false }
    for &request in state.kitty_mutation_requests[:state.kitty_mutation_request_count] {
        if request.sequence == sequence &&
            request.temporary_attachment_id == temporary_attachment_id {
            request.ready = true
            return true
        }
    }
    return false
}

// Take only the ready head mutation, preserving terminal stream order.
graphics_parser_take_mutation_request :: proc(
    state: ^Graphics_Parser_State) -> (Kitty_Mutation_Request, bool) {
    if state == nil || state.kitty_mutation_request_count == 0 ||
        !state.kitty_mutation_requests[0].ready {
        return {}, false
    }
    request := state.kitty_mutation_requests[0]
    for index in 1..<state.kitty_mutation_request_count {
        state.kitty_mutation_requests[index - 1] =
            state.kitty_mutation_requests[index]
    }
    state.kitty_mutation_request_count -= 1
    state.kitty_mutation_requests[state.kitty_mutation_request_count] = {}
    return request, true
}

// Cancel one retained mutation and release its direct or temporary input ownership.
graphics_parser_cancel_mutation_request :: proc(
    state: ^Graphics_Parser_State, sequence: u64) -> bool {
    if state == nil || sequence == 0 { return false }
    for index in 0..<state.kitty_mutation_request_count {
        request := state.kitty_mutation_requests[index]
        if request.sequence != sequence { continue }
        if state.store != nil && request.transfer_id.generation != 0 {
            termattachment.transfer_remove(state.store, request.transfer_id)
        }
        if state.store != nil &&
            request.temporary_attachment_id.generation != 0 {
            graphics_discard_pending_attachment(
                state, request.temporary_attachment_id)
        }
        for follower in index + 1..<state.kitty_mutation_request_count {
            state.kitty_mutation_requests[follower - 1] =
                state.kitty_mutation_requests[follower]
        }
        state.kitty_mutation_request_count -= 1
        state.kitty_mutation_requests[state.kitty_mutation_request_count] = {}
        return true
    }
    return false
}

// Cancel every retained mutation in FIFO order during owner teardown.
graphics_parser_cancel_all_mutation_requests :: proc(
    state: ^Graphics_Parser_State) {
    for state != nil && state.kitty_mutation_request_count > 0 {
        graphics_parser_cancel_mutation_request(
            state, state.kitty_mutation_requests[0].sequence)
    }
}

// Report whether one more ordered Kitty animation effect can be retained.
graphics_parser_animation_command_has_capacity :: proc(
    state: ^Graphics_Parser_State) -> bool {
    return state != nil &&
        state.kitty_animation_command_count < len(state.kitty_animation_commands)
}

// Retain one exact-generation Kitty animation effect in terminal stream order.
graphics_parser_queue_animation_command :: proc(
    state: ^Graphics_Parser_State, command: Kitty_Animation_Command) -> bool {
    if !graphics_parser_animation_command_has_capacity(state) ||
        command.attachment_id.generation == 0 {
        return false
    }
    state.kitty_animation_commands[state.kitty_animation_command_count] = command
    state.kitty_animation_command_count += 1
    return true
}

// Remove and return the oldest retained Kitty animation effect.
graphics_parser_take_animation_command :: proc(
    state: ^Graphics_Parser_State) -> (Kitty_Animation_Command, bool) {
    if state == nil || state.kitty_animation_command_count == 0 { return {}, false }
    command := state.kitty_animation_commands[0]
    for index in 1..<state.kitty_animation_command_count {
        state.kitty_animation_commands[index - 1] =
            state.kitty_animation_commands[index]
    }
    state.kitty_animation_command_count -= 1
    state.kitty_animation_commands[state.kitty_animation_command_count] = {}
    return command, true
}

// Initialize retained graphics framing over one attachment store.
//
// Parameters:
//   - state: Zero-valued destination framing state.
//   - store: Attachment store borrowed for the framing-state lifetime.
//
// Returns:
//   - True after initialization; false for nil or already initialized state.
graphics_parser_init :: proc(
    state: ^Graphics_Parser_State, store: ^termattachment.Store) -> bool {
    if state == nil || store == nil || state.store != nil {
        return false
    }
    state.store = store
    return true
}

// Abort the active wire transaction and release any partial transfer.
//
// Parameters:
//   - state: Framing state whose current candidate is abandoned; nil is accepted.
//
// Side effects:
//   - Removes the active transfer and clears only per-sequence storage.
graphics_parser_abort :: proc(state: ^Graphics_Parser_State) {
    if state == nil {
        return
    }
    if state.store != nil && state.transfer_id.generation != 0 {
        termattachment.transfer_remove(state.store, state.transfer_id)
    }
    state.transfer_id = {}
    state.header = {}
    state.header_byte_count = 0
    state.base64_quantum = {}
    state.base64_quantum_count = 0
    state.base64_finished = false
    state.invalid = false
}

// Release active and queued transfer ownership before retained storage disappears.
//
// Parameters:
//   - state: Framing state being destroyed; nil is accepted.
//
// Side effects:
//   - Removes every active or completed transfer and resets the complete state.
graphics_parser_destroy :: proc(state: ^Graphics_Parser_State) {
    if state == nil {
        return
    }
    graphics_parser_abort(state)
    if state.store != nil {
        for index in 0..<state.frame_count {
            id := state.frames[index].transfer_id
            if id.generation != 0 {
                termattachment.transfer_remove(state.store, id)
            }
        }
        for index in 0..<state.decode_request_count {
            request := state.decode_requests[index]
            if request.transfer_id.generation != 0 {
                termattachment.transfer_remove(state.store, request.transfer_id)
            }
            if request.attachment_id.generation != 0 {
                graphics_discard_pending_attachment(state, request.attachment_id)
            }
        }
        graphics_parser_cancel_all_mutation_requests(state)
        if state.iterm_multipart_transfer_id.generation != 0 {
            termattachment.transfer_remove(
                state.store, state.iterm_multipart_transfer_id)
        }
            if state.kitty_chunk_frame.transfer_id.generation != 0 {
                termattachment.transfer_remove(
                state.store, state.kitty_chunk_frame.transfer_id)
            }
    }
    state^ = {}
}

// Remove one attachment and every protocol identity or placement retaining it.
graphics_discard_attachment :: proc(
    state: ^Graphics_Parser_State, attachment_id: termattachment.Attachment_Id) {
    removed_image_id: u32
    for &identity in state.kitty_images {
        if identity.active && identity.attachment_id == attachment_id {
            removed_image_id = identity.image_id
            identity = {}
        }
    }
    for &identity in state.kitty_placements {
        if identity.active && identity.image_id == removed_image_id {
            identity = {}
        }
    }
    termattachment.placements_remove_attachment(state.store, attachment_id)
    termattachment.attachment_set_protocol_retained(
        state.store, attachment_id, false)
    termattachment.attachment_remove(state.store, attachment_id)
}

// Release preparation ownership and discard its attachment generation.
graphics_discard_pending_attachment :: proc(
    state: ^Graphics_Parser_State, attachment_id: termattachment.Attachment_Id) {
    termattachment.attachment_preparation_release(state.store, attachment_id)
    graphics_discard_attachment(state, attachment_id)
}

// Begin one bounded attachment transfer for an identified graphics payload.
//
// Returns:
//   - True when the store admitted a maximum-bounded transfer; false otherwise.
//
// Side effects:
//   - Acquires active transfer ownership or marks the candidate invalid.
graphics_parser_begin_transfer :: proc(
    state: ^Graphics_Parser_State,
    origin: termattachment.Protocol_Origin) -> bool {
    if state == nil || state.store == nil || state.transfer_id.generation != 0 {
        if state != nil {
            state.invalid = true
        }
        return false
    }
    id, outcome := termattachment.transfer_begin(
        state.store, origin, state.store.limits.transfer_byte_limit)
    if outcome != .Admitted {
        state.invalid = true
        return false
    }
    state.transfer_id = id
    return true
}

// Append one protocol-control byte to the bounded current header.
//
// Returns:
//   - True after append; false after capacity is exhausted.
graphics_parser_append_header :: proc(
    state: ^Graphics_Parser_State, byte: u8) -> bool {
    if state == nil || state.header_byte_count >= len(state.header) {
        if state != nil {
            state.invalid = true
        }
        return false
    }
    state.header[state.header_byte_count] = byte
    state.header_byte_count += 1
    return true
}

// Decode one standard Base64 alphabet byte into its six-bit value.
graphics_base64_value :: proc(byte: u8) -> (u8, bool) {
    if byte >= 'A' && byte <= 'Z' { return byte - 'A', true }
    if byte >= 'a' && byte <= 'z' { return byte - 'a' + 26, true }
    if byte >= '0' && byte <= '9' { return byte - '0' + 52, true }
    if byte == '+' { return 62, true }
    if byte == '/' { return 63, true }
    return 0, false
}

// Decode one complete canonical Base64 quantum without mutating parser state.
graphics_decode_base64_quantum :: proc(
    quantum: [4]u8) -> (Graphics_Base64_Quantum, bool) {
    padding := 0
    if quantum[3] == '=' { padding += 1 }
    if quantum[2] == '=' { padding += 1 }
    first, first_ok := graphics_base64_value(quantum[0])
    second, second_ok := graphics_base64_value(quantum[1])
    third, third_ok := graphics_base64_value(quantum[2])
    fourth, fourth_ok := graphics_base64_value(quantum[3])
    if padding == 2 {
        third, third_ok = 0, true
        fourth, fourth_ok = 0, true
    } else if padding == 1 {
        fourth, fourth_ok = 0, true
    }
    if !first_ok || !second_ok || !third_ok || !fourth_ok ||
        (padding == 2 && second & 0x0f != 0) ||
        (padding == 1 && third & 0x03 != 0) {
        return {}, false
    }
    return {
        bytes = {
            first << 2 | second >> 4,
            second << 4 | third >> 2,
            third << 6 | fourth,
        },
        byte_count = 3 - padding,
    }, true
}

// Decode and append one complete canonical Base64 quantum.
//
// Returns:
//   - True after appending one through three bytes; false for spelling, tail-bit,
//     or transfer-capacity failure.
graphics_parser_flush_base64_quantum :: proc(
    state: ^Graphics_Parser_State) -> bool {
    quantum := state.base64_quantum
    decoded, valid := graphics_decode_base64_quantum(quantum)
    if !valid || decoded.byte_count < len(decoded.bytes) && state.base64_finished {
        return false
    }
    if termattachment.transfer_append(
        state.store, state.transfer_id,
        decoded.bytes[:decoded.byte_count]) != .Admitted {
        return false
    }
    state.base64_quantum = {}
    state.base64_quantum_count = 0
    state.base64_finished = decoded.byte_count < len(decoded.bytes)
    return true
}

// Consume one Base64 payload byte across arbitrary stream boundaries.
//
// Returns:
//   - True while canonical decoding remains valid; false after terminal padding,
//     invalid spelling, or transfer pressure.
graphics_parser_ingest_base64 :: proc(
    state: ^Graphics_Parser_State, byte: u8) -> bool {
    if state == nil || state.invalid ||
        state.transfer_id.generation == 0 ||
        state.base64_finished {
        return false
    }
    if byte != '=' {
        _, valid := graphics_base64_value(byte)
        if !valid {
            state.invalid = true
            return false
        }
    } else if state.base64_quantum_count < 2 {
        state.invalid = true
        return false
    }
    state.base64_quantum[state.base64_quantum_count] = byte
    state.base64_quantum_count += 1
    if state.base64_quantum_count == len(state.base64_quantum) &&
        !graphics_parser_flush_base64_quantum(state) {
        state.invalid = true
        return false
    }
    return true
}

// Append one raw protocol payload byte without growing the active transfer.
//
// Returns:
//   - True after append; false for absent transfer or capacity pressure.
graphics_parser_ingest_raw :: proc(
    state: ^Graphics_Parser_State, byte: u8) -> bool {
    if state == nil || state.invalid || state.transfer_id.generation == 0 {
        return false
    }
    source := [1]u8{byte}
    if termattachment.transfer_append(
        state.store, state.transfer_id, source[:]) != .Admitted {
        state.invalid = true
        return false
    }
    return true
}

// Report whether the current header begins with one exact ASCII prefix.
graphics_parser_header_has_prefix :: proc(
    state: ^Graphics_Parser_State, prefix: string) -> bool {
    if state == nil || state.header_byte_count < len(prefix) {
        return false
    }
    for byte, index in transmute([]u8)prefix {
        if state.header[index] != byte {
            return false
        }
    }
    return true
}

// Report whether the current header exactly equals one ASCII value.
graphics_parser_header_equals :: proc(
    state: ^Graphics_Parser_State, expected: string) -> bool {
    return state != nil && state.header_byte_count == len(expected) &&
        graphics_parser_header_has_prefix(state, expected)
}

// Commit one completely framed transaction into the bounded result queue.
//
// Returns:
//   - True after queue admission; false after malformed framing or queue pressure.
//
// Side effects:
//   - Transfers active payload ownership to the queued frame on success; otherwise
//     releases it. Per-sequence parser storage is cleared in either case.
graphics_parser_finish_frame :: proc(
    state: ^Graphics_Parser_State, kind: Graphics_Frame_Kind,
    producer: termmodel.Terminal_Producer, base64_payload: bool) -> bool {
    valid := state != nil && !state.invalid &&
        (!base64_payload || state.base64_quantum_count == 0) &&
        state.frame_count < len(state.frames)
    if !valid {
        if state != nil {
            state.frame_rejection_count += 1
            graphics_parser_abort(state)
        }
        return false
    }
    frame := &state.frames[state.frame_count]
    frame.kind = kind
    frame.producer = producer
    frame.transfer_id = state.transfer_id
    copy(frame.header[:], state.header[:state.header_byte_count])
    frame.header_byte_count = state.header_byte_count
    state.frame_count += 1
    state.transfer_id = {}
    state.header = {}
    state.header_byte_count = 0
    state.base64_quantum = {}
    state.base64_quantum_count = 0
    state.base64_finished = false
    state.invalid = false
    return true
}

// Remove and return the oldest completed frame.
//
// Returns:
//   - One frame and true, or empty and false when no frame is queued.
//
// Notes:
//   - The caller assumes ownership of a nonzero transfer and must remove it.
graphics_parser_take_frame :: proc(
    state: ^Graphics_Parser_State) -> (Graphics_Frame, bool) {
    if state == nil || state.frame_count == 0 {
        return {}, false
    }
    frame := state.frames[0]
    for index in 1..<state.frame_count {
        state.frames[index - 1] = state.frames[index]
    }
    state.frame_count -= 1
    state.frames[state.frame_count] = {}
    return frame, true
}

// Report whether one decode request can be admitted without mutation.
graphics_parser_decode_request_has_capacity :: proc(
    state: ^Graphics_Parser_State) -> bool {
    return state != nil &&
        state.decode_request_count < len(state.decode_requests)
}

// Queue one validated decode request while transferring payload ownership.
graphics_parser_queue_decode_request :: proc(
    state: ^Graphics_Parser_State, request: Graphics_Decode_Request) -> bool {
    attachment_valid := request.attachment_id.generation != 0
    attachment_expected := request.kind != .Iterm2_Gif_Preflight
    if state == nil || request.transfer_id.generation == 0 ||
        attachment_valid != attachment_expected ||
        state.decode_request_count >= len(state.decode_requests) {
        return false
    }
    state.decode_requests[state.decode_request_count] = request
    state.decode_request_count += 1
    return true
}

// Remove and return the oldest decode request with transfer ownership.
graphics_parser_take_decode_request :: proc(
    state: ^Graphics_Parser_State) -> (Graphics_Decode_Request, bool) {
    if state == nil || state.decode_request_count == 0 {
        return {}, false
    }
    request := state.decode_requests[0]
    for index in 1..<state.decode_request_count {
        state.decode_requests[index - 1] = state.decode_requests[index]
    }
    state.decode_request_count -= 1
    state.decode_requests[state.decode_request_count] = {}
    return request, true
}

// Queue one bounded producer-correlated Kitty response value.
//
// Returns:
//   - True after admission; false when the response queue is full.
graphics_parser_queue_kitty_response :: proc(
    state: ^Graphics_Parser_State, response: Kitty_Graphics_Response) -> bool {
    if state == nil || state.kitty_response_count >= len(state.kitty_responses) {
        if state != nil {
            state.kitty_response_rejection_count += 1
        }
        return false
    }
    state.kitty_responses[state.kitty_response_count] = response
    state.kitty_response_count += 1
    return true
}

// Remove and return the oldest bounded Kitty response value.
graphics_parser_take_kitty_response :: proc(
    state: ^Graphics_Parser_State) -> (Kitty_Graphics_Response, bool) {
    if state == nil || state.kitty_response_count == 0 {
        return {}, false
    }
    response := state.kitty_responses[0]
    for index in 1..<state.kitty_response_count {
        state.kitty_responses[index - 1] = state.kitty_responses[index]
    }
    state.kitty_response_count -= 1
    state.kitty_responses[state.kitty_response_count] = {}
    return response, true
}

// Read the oldest Kitty graphics response without removing it.
graphics_parser_peek_kitty_response :: proc(
    state: ^Graphics_Parser_State) -> (Kitty_Graphics_Response, bool) {
    if state == nil || state.kitty_response_count == 0 {
        return {}, false
    }
    return state.kitty_responses[0], true
}

// Remove the oldest Kitty graphics response after delivery or stale rejection.
graphics_parser_pop_kitty_response :: proc(state: ^Graphics_Parser_State) -> bool {
    if state == nil || state.kitty_response_count == 0 { return false }
    for index in 1..<state.kitty_response_count {
        state.kitty_responses[index - 1] = state.kitty_responses[index]
    }
    state.kitty_response_count -= 1
    state.kitty_responses[state.kitty_response_count] = {}
    return true
}