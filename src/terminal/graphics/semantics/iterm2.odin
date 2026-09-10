package termgraphicssemantics

import termattachment "../../attachment"
import termmodel "../../model"
import termgraphicsprepare "../prepare"
import gfxprotocol "../protocol"

// Parsed, bounded iTerm2 inline-image metadata retained without arbitrary strings.
Iterm2_Controls :: struct {
    // Optional payload size declared by the sender after base64 decoding.
    declared_byte_count: int,

    // Mutually independent cell, pixel, and percentage sizing requests.
    column_span: int,
    row_span: int,
    pixel_width: int,
    pixel_height: int,
    width_percent: int,
    height_percent: int,

    // Placement behavior selected by protocol metadata.
    inline_image: bool,
    preserve_aspect_ratio: bool,

    // Set only after the complete metadata header passes validation.
    valid: bool,
}

// Exact pending generation and worker kind selected by encoded-image admission.
Iterm2_Decode_Target :: struct {
    attachment_id: termattachment.Attachment_Id,
    kind: gfxprotocol.Graphics_Decode_Kind,
    valid: bool,
}

//   Compare borrowed protocol bytes with one exact ASCII string.
//
// Parameters:
//   - bytes: Borrowed bytes from a framed iTerm2 header.
//   - expected: ASCII token against which every byte is compared.
//
// Returns:
//   - True only when length and byte content are identical.
graphics_bytes_equal :: proc(bytes: []u8, expected: string) -> bool {
    if len(bytes) != len(expected) { return false }
    for byte, index in transmute([]u8)expected {
        if bytes[index] != byte { return false }
    }
    return true
}

//   Test borrowed protocol bytes for one exact ASCII suffix.
//
// Parameters:
//   - bytes: Borrowed bytes from a framed iTerm2 metadata value.
//   - suffix: ASCII suffix to compare at the end of `bytes`.
//
// Returns:
//   - True only when `bytes` is long enough and ends with `suffix`.
graphics_bytes_has_suffix :: proc(bytes: []u8, suffix: string) -> bool {
    if len(bytes) < len(suffix) { return false }
    return graphics_bytes_equal(bytes[len(bytes) - len(suffix):], suffix)
}

//   Parse one iTerm2 dimension and publish it to the matching scalar destination.
//
// Parameters:
//   - value: Borrowed `auto`, cell count, pixel count with `px`, or percentage.
//   - cells: Destination for an unqualified positive cell count.
//   - pixels: Destination for a positive pixel count.
//   - percent: Destination for a percentage in the inclusive range 1 through 100.
//
// Returns:
//   - True for `auto` or one valid positive dimension; false without publishing an
//     invalid value.
//
// Side effects:
//   - Writes exactly one destination for a numeric value; `auto` leaves all three zero.
graphics_iterm2_parse_dimension :: proc(
    value: []u8, cells, pixels, percent: ^int) -> bool {
    if graphics_bytes_equal(value, "auto") { return true }
    digits := value
    destination := cells
    if graphics_bytes_has_suffix(value, "px") {
        digits = value[:len(value) - 2]
        destination = pixels
    } else if len(value) > 0 && value[len(value) - 1] == '%' {
        digits = value[:len(value) - 1]
        destination = percent
    }
    parsed, valid := graphics_parse_decimal(digits)
    if !valid || parsed <= 0 || destination == percent && parsed > 100 {
        return false
    }
    destination^ = parsed
    return true
}

//   Apply one iTerm2 metadata token while tolerating extension keys.
//
// Parameters:
//   - controls: In-progress bounded metadata mutated for recognized keys.
//   - token: Borrowed `key=value` bytes, or an opaque token to ignore.
//
// Returns:
//   - False only when a recognized key has malformed or unsupported content.
//
// Side effects:
//   - Mutates the field selected by `inline`, `size`, `width`, `height`, or
//     `preserveAspectRatio`; unknown keys leave `controls` unchanged.
graphics_iterm2_parse_token :: proc(
    controls: ^Iterm2_Controls, token: []u8) -> bool {
    separator := -1
    for byte, index in token {
        if byte == '=' { separator = index; break }
    }
    if separator <= 0 { return true }
    key := token[:separator]
    value := token[separator + 1:]
    if graphics_bytes_equal(key, "inline") {
        controls.inline_image = graphics_bytes_equal(value, "1")
        return controls.inline_image || graphics_bytes_equal(value, "0")
    }
    if graphics_bytes_equal(key, "size") {
        parsed, valid := graphics_parse_decimal(value)
        controls.declared_byte_count = parsed
        return valid && parsed > 0
    }
    if graphics_bytes_equal(key, "width") {
        return graphics_iterm2_parse_dimension(
            value, &controls.column_span, &controls.pixel_width,
            &controls.width_percent)
    }
    if graphics_bytes_equal(key, "height") {
        return graphics_iterm2_parse_dimension(
            value, &controls.row_span, &controls.pixel_height,
            &controls.height_percent)
    }
    if graphics_bytes_equal(key, "preserveAspectRatio") {
        if graphics_bytes_equal(value, "0") {
            controls.preserve_aspect_ratio = false
            return true
        }
        return graphics_bytes_equal(value, "1")
    }
    return true
}

//   Parse one complete File or MultipartFile header into bounded scalar metadata.
//
// Parameters:
//   - header: Borrowed semicolon-delimited metadata bytes from a completed frame.
//
// Returns:
//   - Valid controls after every recognized token passes validation, or a zero value on
//     the first malformed recognized token.
graphics_iterm2_parse_controls :: proc(header: []u8) -> Iterm2_Controls {
    controls := Iterm2_Controls{preserve_aspect_ratio = true}
    start := 0
    for index in 0..=len(header) {
        if index != len(header) && header[index] != ';' { continue }
        if !graphics_iterm2_parse_token(&controls, header[start:index]) {
            return {}
        }
        start = index + 1
    }
    controls.valid = true
    return controls
}

//   Build an encoded-image decode request anchored at the current terminal cursor.
//
// Parameters:
//   - semantics_context: Borrowed terminal capability supplying the current stable anchor.
//   - frame: Completed frame supplying producer correlation and transfer ownership.
//   - controls: Validated iTerm2 sizing, placement, and aspect-ratio controls.
//
// Returns:
//   - A decode request that borrows no header storage and refers to the frame transfer by
//     generational identity.
//
// Notes:
//   - Explicit pixels take precedence over explicit cells, which take precedence over
//     intrinsic sizing.
graphics_iterm2_request :: proc(
    semantics_context: ^Context, frame: gfxprotocol.Graphics_Frame,
    controls: Iterm2_Controls) -> gfxprotocol.Graphics_Decode_Request {
    anchor, valid := graphics_context_anchor(semantics_context)
    if !valid { return {} }
    sizing := termattachment.Sizing_Mode.Intrinsic_Centered
    if controls.column_span > 0 || controls.row_span > 0 { sizing = .Explicit_Cells }
    if controls.pixel_width > 0 || controls.pixel_height > 0 { sizing = .Explicit_Pixels }
    return {
        kind = .Iterm2_Image,
        producer = frame.producer,
        transfer_id = frame.transfer_id,
        declared_byte_count = controls.declared_byte_count,
        place = controls.inline_image,
        geometry = {
            screen = anchor.screen,
            logical_row = anchor.logical_row,
            column = anchor.column,
            column_span = controls.column_span,
            row_span = controls.row_span,
            pixel_width = controls.pixel_width,
            pixel_height = controls.pixel_height,
            sizing = sizing,
            cursor = .Advance,
        },
        preserve_aspect_ratio = controls.preserve_aspect_ratio,
        width_percent = controls.width_percent,
        height_percent = controls.height_percent,
    }
}

// Reserve one static iTerm2 target after synchronous non-GIF inspection.
graphics_iterm2_reserve_static_target :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    inspection: termgraphicsprepare.Image_Inspection) -> Iterm2_Decode_Target {
    attachment_id, status := graphics_reserve_pending_attachment(
        state, .Iterm2, inspection.width, inspection.height, false)
    return {
        attachment_id = attachment_id,
        kind = .Iterm2_Image,
        valid = status == .Ok,
    }
}

//   Inspect and queue one complete iTerm2 encoded image.
graphics_iterm2_queue_static_request :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    prepared: gfxprotocol.Graphics_Decode_Request,
    inspection: termgraphicsprepare.Image_Inspection) ->
    (gfxprotocol.Graphics_Decode_Request, bool) {
    target := graphics_iterm2_reserve_static_target(state, inspection)
    if !target.valid { return prepared, false }
    request := prepared
    request.kind = target.kind
    request.attachment_id = target.attachment_id
    if request.place {
        _, outcome := termattachment.placement_admit(state.store, {
            attachment_id = target.attachment_id,
            geometry = request.geometry,
            lifecycle = .Cursor_Anchored,
        })
        if outcome != .Admitted {
            gfxprotocol.graphics_discard_pending_attachment(
                state, target.attachment_id)
            return request, false
        }
    }
    if gfxprotocol.graphics_parser_queue_decode_request(state, request) {
        return request, true
    }
    gfxprotocol.graphics_discard_pending_attachment(state, target.attachment_id)
    return request, false
}

//   Inspect and queue one complete iTerm2 encoded image.
//
// Returns:
//   - The inspected request and whether queue admission succeeded. A valid inspected
//     request is returned across bounded-resource failure so cursor effects remain exact.
graphics_iterm2_queue_request :: proc(
    state: ^gfxprotocol.Graphics_Parser_State,
    request: gfxprotocol.Graphics_Decode_Request) ->
    (gfxprotocol.Graphics_Decode_Request, bool) {
    bytes, found := termattachment.transfer_bytes(state.store, request.transfer_id)
    valid_size := request.declared_byte_count == 0 ||
        request.declared_byte_count == len(bytes)
    inspection := termgraphicsprepare.inspect_image(bytes, state.store.limits)
    if !found || !valid_size || !inspection.valid { return {}, false }
    prepared := request
    prepared.width = inspection.width
    prepared.height = inspection.height
    if !gfxprotocol.graphics_parser_decode_request_has_capacity(state) {
        return prepared, false
    }
    if inspection.format == .Gif {
        prepared.kind = .Iterm2_Gif_Preflight
        return prepared,
            gfxprotocol.graphics_parser_queue_decode_request(state, prepared)
    }
    return graphics_iterm2_queue_static_request(state, prepared, inspection)
}

// Advance to the final occupied row of one queued inline iTerm2 placement.
//
// Side effects:
//   - Advances by one less than the occupied row count when the request places inline
//     content; a following line feed moves below the image.
graphics_iterm2_advance_cursor :: proc(
    semantics_context: ^Context,
    request: gfxprotocol.Graphics_Decode_Request) {
    if !request.place { return }
    rows := graphics_placement_rows(
        semantics_context, request.geometry,
        {width = request.width, height = request.height})
    if rows > 1 {
        graphics_kitty_advance_cursor(semantics_context, rows - 1)
    }
}

//   Abort the active iTerm2 multipart assembly, if any.
//
// Parameters:
//   - state: Graphics parser state owning multipart correlation and transfer storage.
//
// Side effects:
//   - Releases the aggregate transfer and clears every multipart field. Calling this with
//     no active aggregate is safe.
graphics_iterm2_abort_multipart :: proc(state: ^gfxprotocol.Graphics_Parser_State) {
    if state.iterm_multipart_transfer_id.generation != 0 {
        termattachment.transfer_remove(
            state.store, state.iterm_multipart_transfer_id)
    }
    state.iterm_multipart_transfer_id = {}
    state.iterm_multipart_producer = {}
    state.iterm_multipart_request = {}
    state.iterm_multipart_active = false
}

//   Begin one producer-correlated iTerm2 multipart inline image.
//
// Parameters:
//   - semantics_context: Capability used to snapshot placement geometry.
//   - state: Graphics parser state that will own the aggregate transfer.
//   - frame: Completed MultipartFile header and its originating producer.
//
// Side effects:
//   - On valid inline metadata and available capacity, allocates an aggregate transfer and
//     records the immutable decode request. Invalid or overlapping starts are ignored.
graphics_iterm2_begin_multipart :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame) {
    header := frame.header
    controls := graphics_iterm2_parse_controls(
        header[:frame.header_byte_count])
    if !controls.valid || !controls.inline_image || state.iterm_multipart_active {
        return
    }
    transfer_id, outcome := termattachment.transfer_begin(
        state.store, .Iterm2, state.store.limits.transfer_byte_limit)
    if outcome != .Admitted { return }
    request := graphics_iterm2_request(semantics_context, frame, controls)
    request.transfer_id = transfer_id
    state.iterm_multipart_transfer_id = transfer_id
    state.iterm_multipart_producer = frame.producer
    state.iterm_multipart_request = request
    state.iterm_multipart_active = true
}

//   Append one framed FilePart payload to its matching multipart aggregate.
//
// Parameters:
//   - state: Graphics parser state owning the active aggregate transfer.
//   - frame: Completed part whose transfer bytes remain owned by the parser store.
//
// Side effects:
//   - Extends the aggregate on a producer match. A missing payload, producer mismatch, or
//     capacity failure aborts and releases the entire multipart assembly.
graphics_iterm2_append_part :: proc(
    state: ^gfxprotocol.Graphics_Parser_State, frame: gfxprotocol.Graphics_Frame) {
    if !state.iterm_multipart_active ||
        state.iterm_multipart_producer != frame.producer {
        graphics_iterm2_abort_multipart(state)
        return
    }
    bytes, found := termattachment.transfer_bytes(state.store, frame.transfer_id)
    if !found || termattachment.transfer_append(
        state.store, state.iterm_multipart_transfer_id, bytes) != .Admitted {
        graphics_iterm2_abort_multipart(state)
    }
}

//   Finish one multipart image after producer and declared-size validation.
//
// Parameters:
//   - semantics_context: Capability used to advance below a successful inline placement.
//   - state: Graphics parser state owning the aggregate and decode-request queue.
//   - producer: Producer identity from the terminating FileEnd frame.
//
// Side effects:
//   - Queues the retained aggregate for decoding on success. Any mismatch or queue failure
//     releases the aggregate; success transfers its lifetime to the decode request.
graphics_iterm2_finish_multipart :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    producer: termmodel.Terminal_Producer) {
    if !state.iterm_multipart_active ||
        state.iterm_multipart_producer != producer {
        graphics_iterm2_abort_multipart(state)
        return
    }
    request := state.iterm_multipart_request
    prepared, queued := graphics_iterm2_queue_request(state, request)
    if prepared.width > 0 && prepared.height > 0 {
        graphics_iterm2_advance_cursor(semantics_context, prepared)
    }
    if !queued {
        graphics_iterm2_abort_multipart(state)
        return
    }
    state.iterm_multipart_transfer_id = {}
    state.iterm_multipart_producer = {}
    state.iterm_multipart_request = {}
    state.iterm_multipart_active = false
}

//   Apply one completed iTerm2 frame to original or multipart semantic state.
//
// Parameters:
//   - semantics_context: Capability used to snapshot placement geometry.
//   - state: Graphics parser state owning transfers, multipart state, and decode requests.
//   - frame: Completed iTerm2 framing result in terminal stream order.
//
// Returns:
//   - True only when the frame's own transfer is retained by a queued original-image
//     decode request. Multipart aggregates have separate ownership and return false.
//
// Side effects:
//   - May begin, append, finish, or abort multipart state, or queue one original image.
graphics_apply_iterm2_frame :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame) -> bool {
    switch frame.kind {
    case .Iterm2_File:
        header := frame.header
        controls := graphics_iterm2_parse_controls(
            header[:frame.header_byte_count])
        if !controls.valid || !controls.inline_image {
            return false
        }
        request := graphics_iterm2_request(semantics_context, frame, controls)
        prepared, queued := graphics_iterm2_queue_request(state, request)
        if prepared.width > 0 && prepared.height > 0 {
            graphics_iterm2_advance_cursor(semantics_context, prepared)
        }
        return queued
    case .Iterm2_Multipart_File:
        graphics_iterm2_begin_multipart(semantics_context, state, frame)
    case .Iterm2_File_Part:
        graphics_iterm2_append_part(state, frame)
    case .Iterm2_File_End:
        graphics_iterm2_finish_multipart(semantics_context, state, frame.producer)
    case .Kitty, .Sixel:
    }
    return false
}