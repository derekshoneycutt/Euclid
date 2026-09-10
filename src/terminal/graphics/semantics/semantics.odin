package termgraphicssemantics

import termattachment "../../attachment"
import termmodel "../../model"
import termgraphicsprepare "../prepare"
import gfxprotocol "../protocol"

// Stable terminal anchor borrowed by graphics semantics at each synchronous effect.
Anchor :: struct {
    screen: termattachment.Screen_Identity,
    logical_row: i64,
    column: int,
    sixel_scrolling_mode: bool,
    sixel_cursor_right_mode: bool,
}

// Capabilities required to apply graphics semantics without owning an emulator.
Context :: struct {
    state: ^gfxprotocol.Graphics_Parser_State,
    user_data: rawptr,
    anchor: proc(user_data: rawptr) -> (Anchor, bool),
    cell_width: proc(user_data: rawptr) -> (int, bool),
    cell_height: proc(user_data: rawptr) -> (int, bool),
    advance_columns: proc(user_data: rawptr, columns: int),
    advance_rows: proc(user_data: rawptr, rows: int),
}

// Prepared attachment and placement state for one queued Kitty decode.
Kitty_Decode_Target :: struct {
    attachment_id: termattachment.Attachment_Id,
    dimensions: termattachment.Intrinsic_Metrics,
    kind: gfxprotocol.Graphics_Decode_Kind,
    status: gfxprotocol.Kitty_Graphics_Response_Status,
    place: bool,
}

// Attachment identities and decode metadata for one encoded Kitty frame transaction.
Kitty_Frame_Transaction :: struct {
    id: termattachment.Attachment_Id,
    temporary_id: termattachment.Attachment_Id,
    kind: gfxprotocol.Graphics_Decode_Kind,
    dimensions: termattachment.Intrinsic_Metrics,
}

// Synchronous result for a Kitty command handled without payload transmission.
Kitty_Non_Transmit_Result :: struct {
    status: gfxprotocol.Kitty_Graphics_Response_Status,
    retained: bool,
    handled: bool,
}

// Snapshot the active terminal anchor through the borrowed semantics_context capability.
graphics_context_anchor :: proc(semantics_context: ^Context) -> (Anchor, bool) {
    if semantics_context == nil || semantics_context.anchor == nil { return {}, false }
    return semantics_context.anchor(semantics_context.user_data)
}

//   Enable semantic consumption for subsequently completed graphics frames.
//
// Parameters:
//   - state: Graphics parser state to activate; nil is accepted as a no-op.
//
// Side effects:
//   - Sets the one-way semantic activation flag. Already queued framing-only results are
//     not consumed by this call.
graphics_semantics_enable :: proc(state: ^gfxprotocol.Graphics_Parser_State) {
    if state != nil {
        state.semantics_enabled = true
    }
}

//   Abort every incomplete graphics assembly spanning terminal sequences.
//
// Parameters:
//   - state: Graphics parser state owning Kitty chunks and iTerm2 multipart state.
//
// Side effects:
//   - Releases aggregate transfers and clears both assembly state machines. Nil is a
//     no-op.
graphics_semantics_abort_assemblies :: proc(
    state: ^gfxprotocol.Graphics_Parser_State) {
    if state == nil { return }
    graphics_kitty_abort_chunks(state)
    graphics_iterm2_abort_multipart(state)
}

//   Enforce producer correlation at a terminal-output ownership boundary.
//
// Parameters:
//   - state: Graphics parser state owning active cross-sequence assemblies.
//   - producer: Producer permitted to continue after the boundary.
//
// Side effects:
//   - Aborts and releases each active Kitty or iTerm2 aggregate whose recorded producer
//     differs from `producer`.
graphics_semantics_producer_boundary :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    producer: termmodel.Terminal_Producer) {
    if state == nil { return }
    if state.kitty_chunk_active && state.kitty_chunk_producer != producer {
        graphics_kitty_abort_chunks(state)
    }
    if state.iterm_multipart_active &&
        state.iterm_multipart_producer != producer {
        graphics_iterm2_abort_multipart(state)
    }
}

//   Parse an entire nonnegative decimal token into a native signed integer.
//
// Parameters:
//   - bytes: Borrowed ASCII token that must contain only decimal digits.
//
// Returns:
//   - The parsed value and true, or zero and false for empty, malformed, or overflowing
//     input.
graphics_parse_decimal :: proc(bytes: []u8) -> (int, bool) {
    if len(bytes) == 0 {
        return 0, false
    }
    value := 0
    for byte in bytes {
        if byte < '0' || byte > '9' || value > (max(int) - int(byte - '0')) / 10 {
            return 0, false
        }
        value = value * 10 + int(byte - '0')
    }
    return value, true
}

//   Parse an entire signed decimal token into the Kitty z-index range.
//
// Parameters:
//   - bytes: Borrowed ASCII digits with an optional leading minus sign.
//
// Returns:
//   - The parsed `i32` and true, or zero and false for malformed or out-of-range input.
graphics_parse_i32 :: proc(bytes: []u8) -> (i32, bool) {
    if len(bytes) == 0 { return 0, false }
    negative := bytes[0] == '-'
    digits := bytes[1:] if negative else bytes
    value, valid := graphics_parse_decimal(digits)
    limit := int(max(i32)) + (1 if negative else 0)
    if !valid || value > limit { return 0, false }
    signed := -i64(value) if negative else i64(value)
    return i32(signed), true
}

//   Parse one Kitty action value into an in-progress command.
graphics_parse_kitty_animation_action :: proc(
    controls: ^gfxprotocol.Kitty_Controls, value: u8) -> bool {
    switch value {
    case 'f': controls.action = .Frame
    case 'a': controls.action = .Animate
    case 'c': controls.action = .Compose
    case: return false
    }
    return true
}

//   Parse one Kitty action value into an in-progress command.
//
// Parameters:
//   - controls: Command controls whose action is replaced on success.
//   - value: Borrowed single-byte Kitty action code.
//
// Returns:
//   - True only for a supported image, placement, or animation action.
graphics_parse_kitty_action :: proc(
    controls: ^gfxprotocol.Kitty_Controls, value: []u8) -> bool {
    if len(value) != 1 { return false }
    switch value[0] {
    case 't': controls.action = .Transmit
    case 'T': controls.action = .Transmit_And_Place
    case 'p': controls.action = .Place
    case 'd': controls.action = .Delete
    case 'q': controls.action = .Query
    case: return graphics_parse_kitty_animation_action(controls, value[0])
    }
    return true
}

//   Apply one parsed Kitty format or geometry number for a recognized key.
//
// Parameters:
//   - controls: In-progress command controls mutated for a recognized key.
//   - key: Kitty control key selecting format, extent, crop, or offset.
//   - value: Previously validated nonnegative integer value.
//
// Returns:
//   - True when `key` belongs to this control group; false without mutation otherwise.
graphics_parse_kitty_extent_number :: proc(
    controls: ^gfxprotocol.Kitty_Controls, key: u8, value: int) -> bool {
    switch key {
    case 'f': controls.format = value
    case 's': controls.width = value
    case 'v': controls.height = value
    case 'c': controls.columns = value
    case 'r': controls.rows = value
    case: return false
    }
    return true
}

// Apply one parsed Kitty crop or offset number for a recognized key.
graphics_parse_kitty_crop_number :: proc(
    controls: ^gfxprotocol.Kitty_Controls, key: u8, value: int) -> bool {
    switch key {
    case 'x': controls.source_x = value
    case 'y': controls.source_y = value
    case 'w': controls.source_width = value
    case 'h': controls.source_height = value
    case 'X': controls.offset_x = value
    case 'Y': controls.offset_y = value
    case: return false
    }
    return true
}

// Apply one parsed Kitty format, extent, crop, or offset number.
graphics_parse_kitty_geometry_number :: proc(
    controls: ^gfxprotocol.Kitty_Controls, key: u8, value: int) -> bool {
    return graphics_parse_kitty_extent_number(controls, key, value) ||
        graphics_parse_kitty_crop_number(controls, key, value)
}

//   Apply one parsed Kitty identity, reply, continuation, or cursor number.
//
// Parameters:
//   - controls: In-progress command controls mutated only after range validation.
//   - key: Kitty control key selecting an identity or lifecycle field.
//   - value: Previously validated nonnegative integer value.
//
// Returns:
//   - True for a recognized value within its field range; false for an unknown key or
//     invalid `u32`, quiet-mode, boolean, or continuation value.
graphics_parse_kitty_u32_number :: proc(
    controls: ^gfxprotocol.Kitty_Controls, key: u8, value: int) -> bool {
    if value > int(max(u32)) { return false }
    switch key {
    case 'i': controls.image_id = u32(value)
    case 'I': controls.image_number = u32(value)
    case 'p': controls.placement_id = u32(value)
    case: return false
    }
    return true
}

// Apply one parsed Kitty quiet, continuation, or cursor-control number.
graphics_parse_kitty_mode_number :: proc(
    controls: ^gfxprotocol.Kitty_Controls, key: u8, value: int) -> bool {
    switch key {
    case 'q':
        if value > 2 { return false }
        controls.quiet = value
    case 'm':
        if value > 1 { return false }
        controls.more = value == 1
    case 'C':
        if value > 1 { return false }
        controls.preserve_cursor = value == 1
    case: return false
    }
    return true
}

// Apply one parsed Kitty identity, reply, continuation, or cursor number.
graphics_parse_kitty_identity_number :: proc(
    controls: ^gfxprotocol.Kitty_Controls, key: u8, value: int) -> bool {
    return graphics_parse_kitty_u32_number(controls, key, value) ||
        graphics_parse_kitty_mode_number(controls, key, value)
}

//   Validate and apply one Kitty `key=value` token to a command candidate.
//
// Parameters:
//   - controls: In-progress command controls receiving the recognized value.
//   - token: Borrowed token from a comma-delimited APC control header.
//
// Returns:
//   - True only when syntax, key, value form, and field range are supported.
//
// Side effects:
//   - Mutates at most the field selected by `token`; callers discard the whole candidate
//     when false is returned.
graphics_parse_kitty_raw_token :: proc(
    controls: ^gfxprotocol.Kitty_Controls, token: []u8) -> bool {
    if len(token) < 3 || token[1] != '=' { return false }
    key := token[0]
    value := token[2:]
    if key == 'a' { return graphics_parse_kitty_action(controls, value) }
    if key == 't' { return len(value) == 1 && value[0] == 'd' }
    if key == 'o' {
        controls.zlib_compressed = len(value) == 1 && value[0] == 'z'
        return controls.zlib_compressed
    }
    if key == 'd' {
        if len(value) != 1 { return false }
        controls.delete_selector = value[0]
        return true
    }
    if key == 'z' {
        parsed, valid := graphics_parse_i32(value)
        controls.z_index = parsed
        return valid
    }
    parsed, valid := graphics_parse_decimal(value)
    return valid &&
        (graphics_parse_kitty_geometry_number(controls, key, parsed) ||
         graphics_parse_kitty_identity_number(controls, key, parsed))
}

// Map overloaded Kitty controls after the order-independent header parse.
graphics_finalize_kitty_animation_controls :: proc(
    controls: ^gfxprotocol.Kitty_Controls) -> bool {
    switch controls.action {
    case .Frame:
        controls.base_frame = controls.columns
        controls.edit_frame = controls.rows
        controls.gap_ms = controls.z_index
        controls.gap_specified = controls.z_index != 0
        controls.composition_mode = controls.offset_x
        if controls.offset_y > int(max(u32)) { return false }
        controls.background_rgba = u32(controls.offset_y)
        controls.background_specified = controls.offset_y != 0
        return controls.composition_mode == 0 || controls.composition_mode == 1
    case .Animate:
        if controls.height > int(max(u32)) { return false }
        controls.current_frame = controls.columns
        controls.edit_frame = controls.rows
        controls.animation_state = controls.width
        controls.loop_count = u32(controls.height)
        controls.gap_ms = controls.z_index
        controls.gap_specified = controls.z_index != 0
        return controls.animation_state >= 0 && controls.animation_state <= 3
    case .Compose:
        controls.base_frame = controls.columns
        controls.edit_frame = controls.rows
        controls.composition_mode = 1 if controls.preserve_cursor else 0
        return controls.base_frame > 0 && controls.edit_frame > 0
    case .Transmit, .Transmit_And_Place, .Place, .Delete, .Query:
        return true
    }
    return false
}

// Translate one attachment mutation outcome into a precise Kitty status class.
graphics_kitty_mutation_status :: proc(
    outcome: termattachment.Animation_Mutation_Outcome) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    switch outcome {
    case .Found: return .Ok
    case .Stale, .Not_Found: return .Not_Found
    case .Invalid: return .Invalid
    case .Capacity_Exceeded, .Allocation_Failed: return .Capacity_Exceeded
    }
    return .Invalid
}

// Resolve the exact retained image generation required by animation actions.
graphics_kitty_animation_attachment :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls) -> (termattachment.Attachment_Id, bool) {
    if state == nil || controls.image_id != 0 && controls.image_number != 0 ||
        controls.image_id == 0 && controls.image_number == 0 {
        return {}, false
    }
    index := graphics_kitty_find_image(state, controls)
    if index < 0 { return {}, false }
    return state.kitty_images[index].attachment_id, true
}

// Report whether an earlier retained mutation blocks one exact image generation.
graphics_kitty_mutation_pending :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    id: termattachment.Attachment_Id) -> bool {
    for request in state.kitty_mutation_requests[:state.kitty_mutation_request_count] {
        if request.attachment_id == id { return true }
    }
    return false
}

// Retain one ready synchronous mutation behind earlier work for the same image.
graphics_kitty_defer_mutation :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    id: termattachment.Attachment_Id,
    controls: gfxprotocol.Kitty_Controls,
    kind: gfxprotocol.Kitty_Mutation_Kind,
    transfer_id: termattachment.Transfer_Id = {}) -> bool {
    _, queued := gfxprotocol.graphics_parser_queue_mutation_request(state, {
        attachment_id = id,
        transfer_id = transfer_id,
        controls = controls,
        kind = kind,
        ready = true,
    })
    return queued
}

// Retain one display refresh or control only after a timeline mutation commits.
graphics_kitty_queue_animation_command :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    command: gfxprotocol.Kitty_Animation_Command) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    return .Ok if gfxprotocol.graphics_parser_queue_animation_command(
        state, command) else .Capacity_Exceeded
}

// Apply one borrowed RGB/RGBA Kitty frame upload or edit transactionally.
graphics_kitty_apply_frame_payload :: proc(
    state: ^gfxprotocol.Graphics_Parser_State, payload: []u8,
    controls: gfxprotocol.Kitty_Controls) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    id, found := graphics_kitty_animation_attachment(state, controls)
    if !found { return .Not_Found }
    if !gfxprotocol.graphics_parser_animation_command_has_capacity(state) {
        return .Capacity_Exceeded
    }
    bytes_per_pixel := 3 if controls.format == 24 else 4
    if controls.format != 24 && controls.format != 32 ||
        controls.width <= 0 || controls.height <= 0 ||
        controls.width > max(int) / controls.height ||
        controls.width * controls.height > max(int) / bytes_per_pixel ||
        len(payload) != controls.width * controls.height * bytes_per_pixel {
        return .Invalid
    }
    outcome := termattachment.kitty_animation_mutate_frame(state.store, id, {
        pixels = payload,
        format = .Rgb8 if controls.format == 24 else .Rgba8,
        width = controls.width,
        height = controls.height,
        destination_x = controls.source_x,
        destination_y = controls.source_y,
        base_frame = controls.base_frame,
        edit_frame = controls.edit_frame,
        gap_ms = controls.gap_ms,
        gap_specified = controls.gap_specified,
        background_rgba = controls.background_rgba,
        overwrite = controls.composition_mode == 1,
    })
    status := graphics_kitty_mutation_status(outcome)
    if status != .Ok { return status }
    return graphics_kitty_queue_animation_command(state, {
        attachment_id = id, kind = .Refresh,
    })
}

// Resolve and apply one direct RGB/RGBA Kitty frame transfer.
graphics_kitty_apply_frame :: proc(
    state: ^gfxprotocol.Graphics_Parser_State, frame: gfxprotocol.Graphics_Frame,
    controls: gfxprotocol.Kitty_Controls) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    payload, found := termattachment.transfer_bytes(state.store, frame.transfer_id)
    if !found { return .Invalid }
    return graphics_kitty_apply_frame_payload(state, payload, controls)
}

// Retain one encoded Kitty frame behind an anonymous bounded worker destination.
graphics_kitty_queue_frame_transactions :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame,
    controls: gfxprotocol.Kitty_Controls,
    transaction: Kitty_Frame_Transaction) -> bool {
    mutation_controls := controls
    mutation_controls.width = transaction.dimensions.width
    mutation_controls.height = transaction.dimensions.height
    mutation_controls.format = 32
    mutation_controls.zlib_compressed = false
    sequence, queued := gfxprotocol.graphics_parser_queue_mutation_request(state, {
        attachment_id = transaction.id,
        temporary_attachment_id = transaction.temporary_id,
        controls = mutation_controls,
        kind = .Frame,
    })
    if !queued {
        termattachment.attachment_preparation_release(
            state.store, transaction.temporary_id)
        return false
    }
    queued = gfxprotocol.graphics_parser_queue_decode_request(state, {
        kind = transaction.kind,
        producer = frame.producer,
        transfer_id = frame.transfer_id,
        attachment_id = transaction.temporary_id,
        mutation_sequence = sequence,
        width = transaction.dimensions.width,
        height = transaction.dimensions.height,
    })
    if !queued { gfxprotocol.graphics_parser_cancel_mutation_request(state, sequence) }
    return queued
}

// Retain one encoded Kitty frame behind an anonymous bounded worker destination.
graphics_kitty_queue_encoded_frame :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame,
    controls: gfxprotocol.Kitty_Controls,
    id: termattachment.Attachment_Id) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    if !gfxprotocol.graphics_parser_decode_request_has_capacity(state) ||
        !gfxprotocol.graphics_parser_mutation_request_has_capacity(state) {
        return .Capacity_Exceeded
    }
    kind, supported := graphics_kitty_decode_kind(controls)
    if !supported { return .Unsupported }
    dimensions, valid := graphics_kitty_decode_dimensions(
        state, frame, controls, kind)
    if !valid { return .Invalid }
    temporary_id, status := graphics_reserve_pending_attachment(
        state, .Kitty, dimensions.width, dimensions.height, false)
    if status != .Ok { return status }
    queued := graphics_kitty_queue_frame_transactions(state, frame, controls, {
        id = id,
        temporary_id = temporary_id,
        kind = kind,
        dimensions = dimensions,
    })
    return .Ok if queued else .Capacity_Exceeded
}

// Release every direct or temporary input retained by one mutation request.
graphics_kitty_release_mutation_request :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    request: gfxprotocol.Kitty_Mutation_Request) {
    if request.transfer_id.generation != 0 {
        termattachment.transfer_remove(state.store, request.transfer_id)
    }
    if request.temporary_attachment_id.generation != 0 {
        termattachment.attachment_remove(
            state.store, request.temporary_attachment_id)
    }
}

// Apply one ready retained mutation and release all temporary input ownership.
graphics_kitty_execute_mutation_request :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    request: gfxprotocol.Kitty_Mutation_Request,
    prepared_payload: termattachment.Payload_View) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    controls := request.controls
    switch request.kind {
    case .Frame:
        if request.temporary_attachment_id.generation != 0 {
            return graphics_kitty_apply_frame_payload(
                state, prepared_payload.bytes, controls)
        }
        return graphics_kitty_apply_frame(
            state, {transfer_id = request.transfer_id}, controls)
    case .Compose: return graphics_kitty_apply_composition(state, controls)
    case .Control: return graphics_kitty_apply_animation_control(state, controls)
    case .Delete: return graphics_kitty_delete_animation_frames(state, controls)
    }
    return .Invalid
}

// Apply one ready retained mutation and release all temporary input ownership.
graphics_kitty_apply_mutation_request :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    request: gfxprotocol.Kitty_Mutation_Request) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    controls := request.controls
    current_id, current_found := graphics_kitty_animation_attachment(
        state, controls)
    if !current_found || current_id != request.attachment_id {
        graphics_kitty_release_mutation_request(state, request)
        return .Not_Found
    }
    prepared_payload: termattachment.Payload_View
    if request.temporary_attachment_id.generation != 0 {
        found: bool
        prepared_payload, found = termattachment.attachment_payload(
            state.store, request.temporary_attachment_id)
        if !found {
            graphics_kitty_release_mutation_request(state, request)
            return .Not_Found
        }
    }
    status := graphics_kitty_execute_mutation_request(
        state, request, prepared_payload)
    graphics_kitty_release_mutation_request(state, request)
    return status
}

// Apply one checked Kitty frame-to-frame composition transactionally.
graphics_kitty_apply_composition :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    id, found := graphics_kitty_animation_attachment(state, controls)
    if !found { return .Not_Found }
    if !gfxprotocol.graphics_parser_animation_command_has_capacity(state) {
        return .Capacity_Exceeded
    }
    metrics, metrics_found := termattachment.attachment_metrics(state.store, id)
    if !metrics_found { return .Not_Found }
    width := controls.source_width if controls.source_width > 0 else metrics.width
    height := controls.source_height if controls.source_height > 0 else metrics.height
    outcome := termattachment.kitty_animation_compose(state.store, id, {
        source_frame = controls.edit_frame,
        destination_frame = controls.base_frame,
        source_x = controls.offset_x,
        source_y = controls.offset_y,
        destination_x = controls.source_x,
        destination_y = controls.source_y,
        width = width,
        height = height,
        overwrite = controls.composition_mode == 1,
    })
    status := graphics_kitty_mutation_status(outcome)
    if status != .Ok { return status }
    return graphics_kitty_queue_animation_command(state, {
        attachment_id = id, kind = .Refresh,
    })
}

// Apply Kitty timeline controls and retain their display-owned playback effects.
graphics_kitty_apply_animation_control :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    id, found := graphics_kitty_animation_attachment(state, controls)
    if !found { return .Not_Found }
    if !gfxprotocol.graphics_parser_animation_command_has_capacity(state) {
        return .Capacity_Exceeded
    }
    outcome := termattachment.kitty_animation_control(
        state.store, id, {
            frame_number = controls.edit_frame,
            gap_ms = controls.gap_ms,
            gap_specified = controls.gap_specified,
            loop_count = controls.loop_count,
        })
    status := graphics_kitty_mutation_status(outcome)
    if status != .Ok { return status }
    return graphics_kitty_queue_animation_command(state, {
        attachment_id = id,
        kind = .Control,
        current_frame = controls.current_frame,
        animation_state = controls.animation_state,
    })
}

// Delete selected or all non-root animation frames and retain a display refresh.
graphics_kitty_delete_animation_frames :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    id, found := graphics_kitty_animation_attachment(state, controls)
    if !found { return .Not_Found }
    if !gfxprotocol.graphics_parser_animation_command_has_capacity(state) {
        return .Capacity_Exceeded
    }
    outcome := termattachment.kitty_animation_delete_frames(
        state.store, id, controls.rows, controls.delete_selector == 'F')
    status := graphics_kitty_mutation_status(outcome)
    if status != .Ok { return status }
    return graphics_kitty_queue_animation_command(state, {
        attachment_id = id, kind = .Refresh,
    })
}

//   Parse a complete Kitty control header without retaining its backing storage.
//
// Parameters:
//   - header: Borrowed comma-delimited APC control bytes from one completed frame.
//
// Returns:
//   - Valid controls after every token passes validation, or a zero value at the first
//     unsupported or malformed token. Omitted format defaults to RGBA (`f=32`).
graphics_parse_kitty_raw_controls :: proc(
    header: []u8) -> gfxprotocol.Kitty_Controls {
    controls := gfxprotocol.Kitty_Controls{format = 32}
    start := 0
    for index in 0..=len(header) {
        if index != len(header) && header[index] != ',' {
            continue
        }
        if !graphics_parse_kitty_raw_token(&controls, header[start:index]) {
            return {}
        }
        start = index + 1
    }
    if !graphics_finalize_kitty_animation_controls(&controls) { return {} }
    controls.valid = true
    return controls
}

//   Resolve a retained Kitty image by nonzero protocol ID or image number.
//
// Parameters:
//   - state: Graphics parser state owning the fixed identity table.
//   - controls: Command controls containing either selector.
//
// Returns:
//   - The active identity-table index, or -1 when neither selector resolves.
graphics_kitty_find_image :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls) -> int {
    for &identity, index in state.kitty_images {
        id_matches := controls.image_id != 0 &&
            identity.image_id == controls.image_id
        number_matches := controls.image_number != 0 &&
            identity.image_number == controls.image_number
        if identity.active && (id_matches || number_matches) {
            return index
        }
    }
    return -1
}

//   Remove one retained Kitty image generation and every placement that references it.
//
// Parameters:
//   - state: Graphics parser state owning protocol identities and attachment storage.
//   - index: Candidate index in the fixed Kitty image table.
//
// Returns:
//   - True when an active identity was removed; false for an invalid or inactive index.
//
// Side effects:
//   - Removes attachment placements, clears matching protocol placement identities,
//     releases protocol retention, and invalidates the attachment generation.
graphics_kitty_remove_image :: proc(
    state: ^gfxprotocol.Graphics_Parser_State, index: int) -> bool {
    if index < 0 || index >= len(state.kitty_images) ||
        !state.kitty_images[index].active {
        return false
    }
    identity := &state.kitty_images[index]
    termattachment.placements_remove_attachment(state.store, identity.attachment_id)
    for &placement in state.kitty_placements {
        if placement.active && placement.image_id == identity.image_id {
            placement = {}
        }
    }
    termattachment.attachment_set_protocol_retained(
        state.store, identity.attachment_id, false)
    termattachment.attachment_remove(state.store, identity.attachment_id)
    identity^ = {}
    return true
}

//   Publish one Kitty image identity, replacing a matching retained generation.
//
// Parameters:
//   - state: Graphics parser state owning the fixed image identity table.
//   - controls: Validated nonzero image ID or image number used as the protocol key.
//   - attachment_id: Newly admitted attachment generation to retain.
//
// Returns:
//   - True when a matching or inactive slot receives the identity; false when the table
//     has no available slot.
//
// Side effects:
//   - A matching identity is fully removed before the new generation is published.
graphics_kitty_store_image :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls,
    attachment_id: termattachment.Attachment_Id) -> bool {
    index := graphics_kitty_find_image(state, controls)
    if index >= 0 {
        graphics_kitty_remove_image(state, index)
    } else {
        for &identity, candidate in state.kitty_images {
            if !identity.active {
                index = candidate
                break
            }
        }
    }
    if index < 0 { return false }
    state.kitty_images[index] = {
        image_id = controls.image_id,
        image_number = controls.image_number,
        attachment_id = attachment_id,
        active = true,
    }
    return true
}

//   Publish one nonzero Kitty placement ID and its internal placement generation.
//
// Parameters:
//   - state: Graphics parser state owning protocol placement identities.
//   - controls: Validated placement and image identities from the command.
//   - placement_id: Newly admitted internal placement generation.
//
// Returns:
//   - True for an unaddressed placement or a stored protocol identity; false when no
//     identity slot remains.
//
// Side effects:
//   - Replaces and removes an existing placement with the same protocol placement ID.
graphics_kitty_store_placement :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls,
    placement_id: termattachment.Placement_Id) -> bool {
    if controls.placement_id == 0 { return true }
    for &identity in state.kitty_placements {
        if identity.active && identity.placement_id == controls.placement_id {
            termattachment.placement_remove(state.store, identity.internal_id)
            identity = {}
        }
    }
    for &identity in state.kitty_placements {
        if !identity.active {
            identity = {
                placement_id = controls.placement_id,
                image_id = controls.image_id,
                internal_id = placement_id,
                active = true,
            }
            return true
        }
    }
    return false
}

//   Translate attachment-store admission results to bounded Kitty reply status.
//
// Parameters:
//   - outcome: Typed validation, allocation, or capacity result from attachment storage.
//
// Returns:
//   - `.Ok`, `.Invalid`, or `.Capacity_Exceeded`; store details are intentionally not
//     exposed across the terminal protocol boundary.
graphics_kitty_admission_status :: proc(
    outcome: termattachment.Admission_Outcome) ->
        gfxprotocol.Kitty_Graphics_Response_Status {
    switch outcome {
    case .Capacity_Exceeded, .Byte_Limit_Exceeded, .Pixel_Limit_Exceeded,
         .Allocation_Failed, .No_Evictable_Entry:
        return .Capacity_Exceeded
    case .Invalid: return .Invalid
    case .Admitted: return .Ok
    }
    return .Invalid
}

// Resolve explicit or pixel-derived terminal rows for one raster placement.
//
// Returns:
//   - An explicit row span when present, otherwise the ceiling of displayed or intrinsic
//     pixel height over the committed cell height. Missing geometry conservatively uses
//     one row.
graphics_placement_rows :: proc(
    semantics_context: ^Context, geometry: termattachment.Placement_Geometry,
    dimensions: termattachment.Intrinsic_Metrics) -> int {
    if geometry.row_span > 0 { return geometry.row_span }
    pixel_height := geometry.pixel_height
    if pixel_height <= 0 { pixel_height = dimensions.height }
    if pixel_height <= 0 || semantics_context == nil ||
        semantics_context.cell_height == nil {
        return 1
    }
    cell_height, valid := semantics_context.cell_height(
        semantics_context.user_data)
    if !valid || cell_height <= 0 { return 1 }
    return max((pixel_height + cell_height - 1) / cell_height, 1)
}

//   Advance the terminal cursor for a committed graphics placement.
//
// Parameters:
//   - semantics_context: Borrowed terminal capability used to advance rows.
//   - rows: Requested cell-row allocation; zero still advances one row.
//
// Side effects:
//   - Applies index-forward once per requested row and may scroll terminal content.
graphics_kitty_advance_cursor :: proc(semantics_context: ^Context, rows: int) {
    if semantics_context != nil && semantics_context.advance_rows != nil {
        semantics_context.advance_rows(semantics_context.user_data, max(rows, 1))
    }
}

//   Snapshot Kitty placement intent at the current stable logical cursor anchor.
//
// Parameters:
//   - semantics_context: Borrowed terminal capability supplying the current stable anchor.
//   - controls: Validated destination, crop, offset, z-index, and cursor controls.
//
// Returns:
//   - Protocol-neutral placement geometry containing no native rendering resources.
graphics_kitty_geometry :: proc(
    semantics_context: ^Context,
    controls: gfxprotocol.Kitty_Controls) -> termattachment.Placement_Geometry {
    anchor, valid := graphics_context_anchor(semantics_context)
    if !valid { return {} }
    return {
        screen = anchor.screen,
        logical_row = anchor.logical_row,
        column = anchor.column,
        column_span = controls.columns,
        row_span = controls.rows,
        content_offset_x = controls.offset_x,
        content_offset_y = controls.offset_y,
        source = {
            x = controls.source_x,
            y = controls.source_y,
            width = controls.source_width,
            height = controls.source_height,
        },
        sizing = .Explicit_Cells,
        z_index = controls.z_index,
        cursor = .Preserve if controls.preserve_cursor else .Advance,
    }
}

//   Admit one placement for a resolved Kitty attachment at the current cursor anchor.
//
// Parameters:
//   - semantics_context: Capability supplying placement geometry and cursor mutation.
//   - state: Graphics parser state owning attachment and placement storage.
//   - controls: Validated placement identity, geometry, and cursor policy.
//   - attachment_id: Live attachment generation referenced by the placement.
//   - dimensions: Intrinsic raster dimensions used when no explicit height is supplied.
//
// Returns:
//   - Kitty reply status describing success, invalid input, or bounded capacity pressure.
//
// Side effects:
//   - Admits a placement, publishes its optional protocol identity, and advances the
//     cursor unless preservation was requested. Identity publication failure rolls back
//     the admitted placement.
graphics_kitty_place :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls,
    attachment_id: termattachment.Attachment_Id,
    dimensions: termattachment.Intrinsic_Metrics) ->
        gfxprotocol.Kitty_Graphics_Response_Status {
    geometry := graphics_kitty_geometry(semantics_context, controls)
    placement_id, outcome := termattachment.placement_admit(state.store, {
        attachment_id = attachment_id,
        geometry = geometry,
        lifecycle = .Addressable if controls.placement_id != 0 else .Cursor_Anchored,
    })
    if outcome != .Admitted {
        return graphics_kitty_admission_status(outcome)
    }
    if !graphics_kitty_store_placement(state, controls, placement_id) {
        termattachment.placement_remove(state.store, placement_id)
        return .Capacity_Exceeded
    }
    if !controls.preserve_cursor {
        rows := graphics_placement_rows(semantics_context, geometry, dimensions)
        if rows > 1 {
            graphics_kitty_advance_cursor(semantics_context, rows - 1)
        }
    }
    return .Ok
}

//   Reserve one exact pending RGBA attachment under store policy.
graphics_reserve_pending_attachment :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    origin: termattachment.Protocol_Origin,
    width, height: int, protocol_retained: bool) ->
    (termattachment.Attachment_Id, gfxprotocol.Kitty_Graphics_Response_Status) {
    if width <= 0 || height <= 0 || width > max(int) / height ||
        width * height > max(int) / 4 {
        return {}, .Invalid
    }
    attachment_id, outcome := termattachment.attachment_reserve(state.store, {
        metadata = {
            kind = .Raster,
            origin = origin,
            metrics = {width = width, height = height},
        },
        payload_byte_count = width * height * 4,
        payload_format = .Rgba8,
        payload_stride = width * 4,
        protocol_retained = protocol_retained,
    })
    return attachment_id, graphics_kitty_admission_status(outcome)
}

//   Resolve one supported Kitty transfer format to its worker decode kind.
//
// Returns:
//   - The selected kind and true, or a zero kind and false when unsupported.
graphics_kitty_decode_kind :: proc(
    controls: gfxprotocol.Kitty_Controls) -> (
        gfxprotocol.Graphics_Decode_Kind, bool) {
    if controls.format == 100 && !controls.zlib_compressed {
        return .Kitty_Png, true
    }
    if controls.format == 24 && controls.zlib_compressed {
        return .Kitty_Zlib_Rgb, true
    }
    if controls.format == 32 && controls.zlib_compressed {
        return .Kitty_Zlib_Rgba, true
    }
    return {}, false
}

//   Resolve declared or encoded Kitty dimensions under attachment limits.
//
// Returns:
//   - Positive preparation dimensions and true, or zero values and false.
graphics_kitty_decode_dimensions :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame,
    controls: gfxprotocol.Kitty_Controls,
    kind: gfxprotocol.Graphics_Decode_Kind) -> (
        termattachment.Intrinsic_Metrics, bool) {
    if kind != .Kitty_Png {
        return {width = controls.width, height = controls.height},
            controls.width > 0 && controls.height > 0
    }
    payload, found := termattachment.transfer_bytes(state.store, frame.transfer_id)
    inspection := termgraphicsprepare.inspect_image(payload, state.store.limits)
    if !found || !inspection.valid || inspection.format != .Png {
        return {}, false
    }
    return {width = inspection.width, height = inspection.height}, true
}

// Reserve and optionally identify and place one pending Kitty decode target.
graphics_prepare_kitty_decode_target :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls,
    target: Kitty_Decode_Target) -> Kitty_Decode_Target {
    result := target
    has_identity := controls.image_id != 0 || controls.image_number != 0
    attachment_id, status := graphics_reserve_pending_attachment(
        state, .Kitty, result.dimensions.width, result.dimensions.height, has_identity)
    result.status = status
    if status != .Ok { return result }
    result.attachment_id = attachment_id
    if has_identity && !graphics_kitty_store_image(state, controls, attachment_id) {
        gfxprotocol.graphics_discard_pending_attachment(state, attachment_id)
        result.status = .Capacity_Exceeded
        return result
    }
    result.place = controls.action == .Transmit_And_Place
    if result.place {
        status = graphics_kitty_place(
            semantics_context, state, controls, attachment_id, result.dimensions)
        if status != .Ok {
            gfxprotocol.graphics_discard_pending_attachment(
                state, attachment_id)
            result.status = status
            return result
        }
    }
    return result
}

// Build one protocol-neutral Kitty decode request from validated command state.
graphics_kitty_decode_request :: proc(
    semantics_context: ^Context, frame: gfxprotocol.Graphics_Frame,
    controls: gfxprotocol.Kitty_Controls,
    target: Kitty_Decode_Target) -> gfxprotocol.Graphics_Decode_Request {
    return {
        kind = target.kind, producer = frame.producer, transfer_id = frame.transfer_id,
        attachment_id = target.attachment_id, width = target.dimensions.width,
        height = target.dimensions.height, place = target.place,
        geometry = graphics_kitty_geometry(semantics_context, controls),
        preserve_aspect_ratio = true, image_id = controls.image_id,
        image_number = controls.image_number, placement_id = controls.placement_id,
    }
}

//   Queue one supported encoded Kitty payload after synchronous reservation and placement.
//
// Parameters:
//   - semantics_context: Capability used to snapshot geometry and advance the cursor.
//   - state: Graphics parser state owning the decode-request queue.
//   - frame: Completed frame supplying producer correlation and encoded transfer.
//   - controls: Validated PNG or zlib RGB/RGBA transmission controls.
//
// Returns:
//   - `.Ok` when the transfer is retained by a queued request, `.Unsupported` for an
//     unimplemented encoding combination, or `.Capacity_Exceeded` when the queue is full.
//
// Side effects:
//   - Queues a protocol-neutral decode request and advances the cursor for an immediate
//     placement unless preservation was requested.
graphics_queue_kitty_decode :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame,
    controls: gfxprotocol.Kitty_Controls) ->
        gfxprotocol.Kitty_Graphics_Response_Status {
    kind, supported := graphics_kitty_decode_kind(controls)
    if !supported { return .Unsupported }
    if !gfxprotocol.graphics_parser_decode_request_has_capacity(state) {
        return .Capacity_Exceeded
    }
    dimensions, dimensions_valid := graphics_kitty_decode_dimensions(
        state, frame, controls, kind)
    if !dimensions_valid { return .Invalid }
    target := graphics_prepare_kitty_decode_target(
        semantics_context, state, controls, {kind = kind, dimensions = dimensions})
    if target.status != .Ok { return target.status }
    request := graphics_kitty_decode_request(
        semantics_context, frame, controls, target)
    if !gfxprotocol.graphics_parser_queue_decode_request(state, request) {
        gfxprotocol.graphics_discard_pending_attachment(
            state, target.attachment_id)
        return .Capacity_Exceeded
    }
    return .Ok
}

// Delete one Kitty placement identity and its internal placement generation.
graphics_kitty_delete_placement :: proc(
    state: ^gfxprotocol.Graphics_Parser_State, placement_id: u32) -> bool {
    for &identity in state.kitty_placements {
        if identity.active && identity.placement_id == placement_id {
            termattachment.placement_remove(state.store, identity.internal_id)
            identity = {}
            return true
        }
    }
    return false
}

// Apply one Kitty identity-oriented deletion selector.
graphics_kitty_delete_identity :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    switch controls.delete_selector {
    case 'i', 'I':
        index := graphics_kitty_find_image(state, controls)
        if index < 0 { return .Invalid }
        graphics_kitty_remove_image(state, index)
    case 'p', 'P':
        if !graphics_kitty_delete_placement(state, controls.placement_id) {
            return .Invalid
        }
    case 'a', 'A':
        for index in 0..<len(state.kitty_images) {
            graphics_kitty_remove_image(state, index)
        }
    case: return .Unsupported
    }
    return .Ok
}

// Apply one Kitty position, row, column, or z-index deletion selector.
graphics_kitty_delete_position :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls,
    screen: termattachment.Screen_Identity, logical_row: i64, column: int) -> bool {
    switch controls.delete_selector {
    case 'c', 'C':
        termattachment.placements_remove_position(
            state.store, screen, logical_row, column)
    case 'x', 'X':
        termattachment.placements_remove_column(state.store, screen, column)
    case 'y', 'Y':
        termattachment.placements_remove_row_range(
            state.store, screen, logical_row, logical_row)
    case 'r', 'R':
        termattachment.placements_remove_row_range(
            state.store, screen, logical_row,
            logical_row + i64(max(controls.rows, 1) - 1))
    case 'z', 'Z':
        termattachment.placements_remove_z_index(
            state.store, screen, controls.z_index)
    case: return false
    }
    return true
}

//   Apply one supported Kitty image, placement, position, range, or z-index deletion.
//
// Parameters:
//   - semantics_context: Capability supplying current screen, logical row, and column.
//   - state: Graphics parser state owning protocol identities and attachment storage.
//   - controls: Validated selector and its image, placement, row-count, or z-index value.
//
// Returns:
//   - `.Ok` after a supported deletion, `.Invalid` for missing required identity or
//     terminal state, and `.Unsupported` for an unimplemented selector.
//
// Side effects:
//   - Invalidates matching identities and removes matching attachment placements from the
//     bounded store. Uppercase selector variants currently share lowercase behavior.
graphics_kitty_delete :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls) ->
        gfxprotocol.Kitty_Graphics_Response_Status {
    if state == nil || state.store == nil { return .Invalid }
    if controls.delete_selector == 'f' || controls.delete_selector == 'F' {
        return graphics_kitty_delete_animation_frames(state, controls)
    }
    if semantics_context == nil { return .Invalid }
    anchor, valid := graphics_context_anchor(semantics_context)
    if !valid { return .Invalid }
    if controls.delete_selector == 'i' || controls.delete_selector == 'I' ||
        controls.delete_selector == 'p' || controls.delete_selector == 'P' ||
        controls.delete_selector == 'a' || controls.delete_selector == 'A' {
        return graphics_kitty_delete_identity(state, controls)
    }
    return .Ok if graphics_kitty_delete_position(
        state, controls, anchor.screen, anchor.logical_row,
        anchor.column) else .Unsupported
}

//   Validate one direct raw Kitty raster against dimensions, crop, and exact byte count.
//
// Parameters:
//   - controls: Parsed raw RGB or RGBA format, dimensions, and source crop.
//   - payload: Borrowed decoded transfer bytes.
//   - found: Whether `payload` resolved from the frame's live transfer generation.
//
// Returns:
//   - The format's byte stride per pixel and true, or the candidate stride and false when
//     any geometry, overflow, transfer, or byte-count check fails.
graphics_validate_kitty_raw :: proc(
    controls: gfxprotocol.Kitty_Controls,
    payload: []u8, found: bool) -> (int, bool) {
    bytes_per_pixel := 3 if controls.format == 24 else 4
    invalid := (controls.format != 24 && controls.format != 32) ||
        controls.width <= 0 || controls.height <= 0 || !found ||
        controls.source_x > controls.width ||
        controls.source_y > controls.height ||
        controls.source_width > controls.width - controls.source_x ||
        controls.source_height > controls.height - controls.source_y ||
        controls.width > max(int) / controls.height ||
        controls.width * controls.height > max(int) / bytes_per_pixel ||
        len(payload) != controls.width * controls.height * bytes_per_pixel
    return bytes_per_pixel, !invalid
}

//   Copy one validated raw Kitty raster into attachment storage and publish its identity.
//
// Parameters:
//   - state: Graphics parser state owning attachment and Kitty identity storage.
//   - controls: Validated raster metadata and optional protocol identity.
//   - payload: Borrowed decoded bytes copied during attachment admission.
//   - bytes_per_pixel: Validated RGB or RGBA component stride.
//
// Returns:
//   - A live attachment generation and `.Ok`, or a zero identity with translated failure
//     status.
//
// Side effects:
//   - May evict eligible attachments and allocates an immutable payload copy. Identity
//     publication failure removes the new attachment before returning.
graphics_admit_kitty_raw :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls,
    payload: []u8, bytes_per_pixel: int) -> (
        termattachment.Attachment_Id,
        gfxprotocol.Kitty_Graphics_Response_Status) {
    attachment_id, outcome := termattachment.attachment_admit(state.store, {
        metadata = {
            kind = .Raster,
            origin = .Kitty,
            metrics = {width = controls.width, height = controls.height},
        },
        payload = payload,
        payload_format = .Rgb8 if controls.format == 24 else .Rgba8,
        payload_stride = controls.width * bytes_per_pixel,
        protocol_retained = controls.image_id != 0 || controls.image_number != 0,
    })
    if outcome != .Admitted {
        return {}, graphics_kitty_admission_status(outcome)
    }
    has_identity := controls.image_id != 0 || controls.image_number != 0
    if has_identity && !graphics_kitty_store_image(
        state, controls, attachment_id) {
        termattachment.attachment_set_protocol_retained(
            state.store, attachment_id, false)
        termattachment.attachment_remove(state.store, attachment_id)
        return {}, .Capacity_Exceeded
    }
    return attachment_id, .Ok
}

// Admit and apply one validated direct Kitty RGB or RGBA payload.
graphics_apply_kitty_raw :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame,
    controls: gfxprotocol.Kitty_Controls) ->
        gfxprotocol.Kitty_Graphics_Response_Status {
    payload, found := termattachment.transfer_bytes(state.store, frame.transfer_id)
    bytes_per_pixel, valid := graphics_validate_kitty_raw(controls, payload, found)
    if !valid { return .Invalid }
    attachment_id, status := graphics_admit_kitty_raw(
        state, controls, payload, bytes_per_pixel)
    if status != .Ok { return status }
    has_identity := controls.image_id != 0 || controls.image_number != 0
    if controls.action == .Transmit {
        if has_identity { return .Ok }
        termattachment.attachment_remove(state.store, attachment_id)
        return .Invalid
    }
    status = graphics_kitty_place(semantics_context, state, controls, attachment_id, {
        width = controls.width,
        height = controls.height,
    })
    if status != .Ok && !has_identity {
        termattachment.attachment_remove(state.store, attachment_id)
    }
    return status
}

// Apply one Kitty deletion, deferring animation-frame deletion behind pending work.
graphics_apply_kitty_delete_controls :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    if controls.delete_selector == 'f' || controls.delete_selector == 'F' {
        id, found := graphics_kitty_animation_attachment(state, controls)
        if !found { return .Not_Found }
        if graphics_kitty_mutation_pending(state, id) {
            return .Ok if graphics_kitty_defer_mutation(
                state, id, controls, .Delete) else .Capacity_Exceeded
        }
    }
    return graphics_kitty_delete(semantics_context, state, controls)
}

// Apply or retain one Kitty frame upload under exact-generation ordering.
graphics_apply_kitty_frame_controls :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame,
    controls: gfxprotocol.Kitty_Controls) ->
    (gfxprotocol.Kitty_Graphics_Response_Status, bool) {
    id, found := graphics_kitty_animation_attachment(state, controls)
    if !found { return .Not_Found, false }
    if controls.format == 100 || controls.zlib_compressed {
        status := graphics_kitty_queue_encoded_frame(state, frame, controls, id)
        return status, status == .Ok
    }
    if !graphics_kitty_mutation_pending(state, id) {
        return graphics_kitty_apply_frame(state, frame, controls), false
    }
    payload, payload_found := termattachment.transfer_bytes(
        state.store, frame.transfer_id)
    _, valid := graphics_validate_kitty_raw(controls, payload, payload_found)
    if !valid { return .Invalid, false }
    queued := graphics_kitty_defer_mutation(
        state, id, controls, .Frame, frame.transfer_id)
    return .Ok if queued else .Capacity_Exceeded, queued
}

// Apply or retain one Kitty playback-control or composition mutation.
graphics_apply_kitty_timeline_controls :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    controls: gfxprotocol.Kitty_Controls,
    kind: gfxprotocol.Kitty_Mutation_Kind) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    id, found := graphics_kitty_animation_attachment(state, controls)
    if !found { return .Not_Found }
    if graphics_kitty_mutation_pending(state, id) {
        return .Ok if graphics_kitty_defer_mutation(
            state, id, controls, kind) else .Capacity_Exceeded
    }
    return graphics_kitty_apply_animation_control(state, controls) if
        kind == .Control else graphics_kitty_apply_composition(state, controls)
}

//   Dispatch one parsed Kitty command and commit its synchronous semantic effects.
graphics_apply_kitty_non_transmit :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame,
    controls: gfxprotocol.Kitty_Controls) -> Kitty_Non_Transmit_Result {
    if controls.action == .Delete {
        return {status = graphics_apply_kitty_delete_controls(
            semantics_context, state, controls), handled = true}
    }
    if controls.action == .Frame {
        status, retained := graphics_apply_kitty_frame_controls(state, frame, controls)
        return {status = status, retained = retained, handled = true}
    }
    if controls.action == .Animate || controls.action == .Compose {
        kind: gfxprotocol.Kitty_Mutation_Kind = .Control
        if controls.action == .Compose { kind = .Compose }
        return {status = graphics_apply_kitty_timeline_controls(
            state, controls, kind), handled = true}
    }
    if controls.action == .Place {
        index := graphics_kitty_find_image(state, controls)
        if index < 0 || frame.transfer_id.generation != 0 {
            return {status = .Invalid, handled = true}
        }
        dimensions, found := termattachment.attachment_metrics(
            state.store, state.kitty_images[index].attachment_id)
        if !found { return {status = .Invalid, handled = true} }
        status := graphics_kitty_place(
            semantics_context, state, controls,
            state.kitty_images[index].attachment_id, dimensions)
        return {status = status, handled = true}
    }
    return {status = .Ok, handled = controls.action == .Query}
}

//   Dispatch one parsed Kitty command and commit its synchronous semantic effects.
//
// Parameters:
//   - semantics_context: Capability used for deletion, placement, and cursor effects.
//   - state: Graphics parser state owning transfers, identities, attachments, and queues.
//   - frame: Completed frame supplying the current transfer and producer correlation.
//   - controls: Parsed command controls, including whole-header validity.
//
// Returns:
//   - Kitty reply status plus true only when the frame transfer is retained by an encoded
//     decode request.
//
// Side effects:
//   - May delete state, place a retained image, queue encoded decoding, admit raw pixels,
//     replace identities, or advance the cursor. Failed anonymous placement removes its
//     otherwise unreachable attachment.
graphics_apply_kitty_controls :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame,
    controls: gfxprotocol.Kitty_Controls) -> (
        gfxprotocol.Kitty_Graphics_Response_Status, bool) {
    if !controls.valid { return .Invalid, false }
    result := graphics_apply_kitty_non_transmit(
        semantics_context, state, frame, controls)
    if result.handled { return result.status, result.retained }
    status := result.status
    if controls.format == 100 || controls.zlib_compressed {
        status = graphics_queue_kitty_decode(semantics_context, state, frame, controls)
        return status, status == .Ok
    }
    return graphics_apply_kitty_raw(semantics_context, state, frame, controls), false
}

//   Abort the active Kitty direct-transfer chunk assembly, if any.
//
// Parameters:
//   - state: Graphics parser state owning chunk correlation and aggregate transfer.
//
// Side effects:
//   - Releases the aggregate transfer and clears all chunk state. Calling this without an
//     active aggregate is safe.
graphics_kitty_abort_chunks :: proc(
    state: ^gfxprotocol.Graphics_Parser_State) {
    if state.kitty_chunk_frame.transfer_id.generation != 0 {
        termattachment.transfer_remove(
            state.store, state.kitty_chunk_frame.transfer_id)
    }
    state.kitty_chunk_frame = {}
    state.kitty_chunk_controls = {}
    state.kitty_chunk_producer = {}
    state.kitty_chunk_active = false
}

//   Append one completed Kitty frame payload to the active aggregate transfer.
//
// Parameters:
//   - state: Graphics parser state owning both source and aggregate transfers.
//   - frame: Completed continuation frame whose payload is borrowed for this call.
//
// Returns:
//   - True only when both transfer generations resolve and bounded append succeeds.
//
// Side effects:
//   - Extends the aggregate transfer; the frame transfer remains independently owned.
graphics_kitty_append_chunk :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame) -> bool {
    bytes, found := termattachment.transfer_bytes(state.store, frame.transfer_id)
    return found && termattachment.transfer_append(
        state.store, state.kitty_chunk_frame.transfer_id, bytes) == .Admitted
}

// Finalize and semantically apply the active Kitty chunk aggregate.
graphics_kitty_complete_chunks :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State) ->
    gfxprotocol.Kitty_Graphics_Response_Status {
    aggregate_frame := state.kitty_chunk_frame
    aggregate_controls := state.kitty_chunk_controls
    aggregate_controls.more = false
    state.kitty_chunk_frame = {}
    state.kitty_chunk_controls = {}
    state.kitty_chunk_producer = {}
    state.kitty_chunk_active = false
    status, retained := graphics_apply_kitty_controls(
        semantics_context, state, aggregate_frame, aggregate_controls)
    if !retained && aggregate_frame.transfer_id.generation != 0 {
        termattachment.transfer_remove(state.store, aggregate_frame.transfer_id)
    }
    return status
}

//   Apply one Kitty frame, assembling producer-correlated continuation chunks as needed.
//
// Parameters:
//   - semantics_context: Capability receiving synchronous placement and cursor effects.
//   - state: Graphics parser state owning chunk assembly and semantic stores.
//   - frame: Completed Kitty frame in terminal stream order.
//
// Returns:
//   - Kitty reply status plus true only when an unchunked frame transfer is retained by a
//     decode request. Aggregate transfer ownership is settled internally.
//
// Side effects:
//   - May allocate, extend, abort, or finalize one chunk aggregate. Finalization clears
//     assembly state before semantic dispatch and releases an unretained aggregate.
graphics_apply_kitty_frame :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame) -> (
        gfxprotocol.Kitty_Graphics_Response_Status, bool) {
    header := frame.header
    controls := graphics_parse_kitty_raw_controls(
        header[:frame.header_byte_count])
    if !controls.more && !state.kitty_chunk_active {
        return graphics_apply_kitty_controls(semantics_context, state, frame, controls)
    }
    if !state.kitty_chunk_active {
        aggregate, outcome := termattachment.transfer_begin(
            state.store, .Kitty, state.store.limits.transfer_byte_limit)
        if outcome != .Admitted { return .Capacity_Exceeded, false }
        state.kitty_chunk_frame = frame
        state.kitty_chunk_frame.transfer_id = aggregate
        state.kitty_chunk_controls = controls
        state.kitty_chunk_producer = frame.producer
        state.kitty_chunk_active = true
    } else if state.kitty_chunk_producer != frame.producer {
        graphics_kitty_abort_chunks(state)
        return .Invalid, false
    }
    if !graphics_kitty_append_chunk(state, frame) {
        graphics_kitty_abort_chunks(state)
        return .Capacity_Exceeded, false
    }
    if controls.more { return .Ok, false }
    return graphics_kitty_complete_chunks(semantics_context, state), false
}

//   Decide whether Kitty quiet mode permits one semantic response.
//
// Parameters:
//   - controls: Parsed command containing quiet mode 0, 1, or 2.
//   - status: Semantic result that would be returned to the producer.
//
// Returns:
//   - True for all mode-0 replies and mode-1 errors; mode 2 suppresses every reply.
graphics_kitty_response_allowed :: proc(
    controls: gfxprotocol.Kitty_Controls,
    status: gfxprotocol.Kitty_Graphics_Response_Status) -> bool {
    return controls.quiet == 0 || controls.quiet == 1 && status != .Ok
}

// Apply one completed graphics frame and report whether decoding retains its transfer.
graphics_semantics_apply_frame :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame) -> bool {
    if frame.kind == .Kitty {
        header := frame.header
        controls := graphics_parse_kitty_raw_controls(
            header[:frame.header_byte_count])
        status, retained := graphics_apply_kitty_frame(semantics_context, state, frame)
        if !controls.more && graphics_kitty_response_allowed(controls, status) {
            gfxprotocol.graphics_parser_queue_kitty_response(state, {
                producer = frame.producer, image_id = controls.image_id,
                image_number = controls.image_number,
                placement_id = controls.placement_id, status = status,
            })
        }
        return retained
    }
    if frame.kind == .Iterm2_File || frame.kind == .Iterm2_Multipart_File ||
        frame.kind == .Iterm2_File_Part || frame.kind == .Iterm2_File_End {
        return graphics_apply_iterm2_frame(semantics_context, state, frame)
    }
    if frame.kind == .Sixel {
        return graphics_apply_sixel_frame(semantics_context, state, frame)
    }
    return false
}

//   Consume and apply every completed graphics frame in terminal stream order.
//
// Parameters:
//   - semantics_context: Borrowed parser and terminal capabilities. Missing or disabled state is a
//     no-op.
//
// Side effects:
//   - Dispatches Kitty, iTerm2, and Sixel semantics; commits placement and cursor effects;
//     queues producer-correlated replies and decode requests; and releases every frame
//     transfer not explicitly retained by downstream decoding.
//
// Notes:
//   - This procedure runs synchronously at protocol terminators so later terminal bytes
//     observe the committed semantic state.
graphics_semantics_consume_frames :: proc(semantics_context: ^Context) {
    if semantics_context == nil || semantics_context.state == nil ||
        !semantics_context.state.semantics_enabled {
        return
    }
    state := semantics_context.state
    for {
        frame, available := gfxprotocol.graphics_parser_take_frame(state)
        if !available { break }
        retained := graphics_semantics_apply_frame(semantics_context, state, frame)
        if frame.transfer_id.generation != 0 && !retained {
            termattachment.transfer_remove(state.store, frame.transfer_id)
        }
    }
}