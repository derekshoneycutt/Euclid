package termgraphicssemantics

import termattachment "../../attachment"
import gfxprotocol "../protocol"

// Bounded Sixel semantics collected without expanding the indexed raster.
Sixel_Semantics :: struct {
    // Measured raster extent and optional dimensions declared by raster attributes.
    width: int,
    height: int,
    declared_width: int,
    declared_height: int,

    // Packed opaque RGBA palette entries referenced by the encoded Sixel stream.
    palette: [256]u32,
    palette_count: int,

    // Presentation metadata and whole-result validation state.
    transparent_background: bool,
    valid: bool,
}

// Bounded decimal parameter list parsed from one Sixel command.
Sixel_Parameters :: struct {
    // Fixed storage and occupied prefix; no command may retain arbitrary parameter text.
    values: [5]int,
    count: int,

    // True only when at least one decimal parameter was present.
    valid: bool,
}

// Mutable raster pen measured in output pixels from the Sixel origin.
Sixel_Pen :: struct {
    x: int,
    y: int,
}

//   Parse one nonnegative decimal parameter at a mutable stream position.
//
// Parameters:
//   - bytes: Borrowed Sixel command bytes.
//   - index: In/out offset advanced past every consumed decimal digit.
//
// Returns:
//   - The bounded native integer and true, or zero and false when no digit is present or
//     accumulation would overflow.
//
// Side effects:
//   - Advances `index` while scanning; overflow leaves it after the consumed prefix.
graphics_sixel_parse_number :: proc(
    bytes: []u8, index: ^int) -> (int, bool) {
    start := index^
    value := 0
    for index^ < len(bytes) && bytes[index^] >= '0' && bytes[index^] <= '9' {
        digit := int(bytes[index^] - '0')
        if value > (max(int) - digit) / 10 { return 0, false }
        value = value * 10 + digit
        index^ += 1
    }
    return value, index^ > start
}

//   Parse a bounded semicolon-separated Sixel parameter list.
//
// Parameters:
//   - bytes: Borrowed Sixel command bytes.
//   - index: In/out offset beginning at the first possible decimal digit.
//
// Returns:
//   - Up to five parsed values, their occupied count, and whether any value was present.
//
// Side effects:
//   - Advances `index` through consumed values and separators without allocating.
graphics_sixel_parse_parameters :: proc(
    bytes: []u8, index: ^int) -> Sixel_Parameters {
    result: Sixel_Parameters
    count := 0
    for count < len(result.values) {
        value, present := graphics_sixel_parse_number(bytes, index)
        if !present { break }
        result.values[count] = value
        count += 1
        if index^ >= len(bytes) || bytes[index^] != ';' { break }
        index^ += 1
    }
    result.count = count
    result.valid = count > 0
    return result
}

//   Convert one percentage RGB triplet to packed opaque RGBA.
//
// Parameters:
//   - red, green, blue: Color components in the inclusive range 0 through 100.
//
// Returns:
//   - Packed `0xRRGGBBFF` and true, or zero and false for an out-of-range component.
graphics_sixel_rgb :: proc(red, green, blue: int) -> (u32, bool) {
    if red < 0 || red > 100 || green < 0 || green > 100 ||
        blue < 0 || blue > 100 {
        return 0, false
    }
    r := u32(red * 255 / 100)
    g := u32(green * 255 / 100)
    b := u32(blue * 255 / 100)
    return r << 24 | g << 16 | b << 8 | 0xff, true
}

//   Convert one Sixel HLS definition to packed opaque RGBA.
//
// Parameters:
//   - hue: Hue angle in the inclusive range 0 through 360.
//   - lightness: Lightness percentage in the inclusive range 0 through 100.
//   - saturation: Saturation percentage in the inclusive range 0 through 100.
//
// Returns:
//   - Packed `0xRRGGBBFF` and true, or zero and false for an invalid component.
//
// Notes:
//   - Sixel HLS rotates the conventional hue origin by 120 degrees before conversion.
graphics_sixel_hls :: proc(hue, lightness, saturation: int) -> (u32, bool) {
    if hue < 0 || hue > 360 || lightness < 0 || lightness > 100 ||
        saturation < 0 || saturation > 100 {
        return 0, false
    }
    chroma := f32(1 - abs(f32(2 * lightness) / 100 - 1)) *
        f32(saturation) / 100
    sector := f32((hue + 120) % 360) / 60
    sector_remainder := sector - f32(int(sector / 2) * 2)
    second := chroma * f32(1 - abs(sector_remainder - 1))
    red, green, blue: f32
    if sector < 1 { red, green = chroma, second
    } else if sector < 2 { red, green = second, chroma
    } else if sector < 3 { green, blue = chroma, second
    } else if sector < 4 { green, blue = second, chroma
    } else if sector < 5 { red, blue = second, chroma
    } else { red, blue = chroma, second }
    match := f32(lightness) / 100 - chroma / 2
    return graphics_sixel_rgb(
        int((red + match) * 100), int((green + match) * 100),
        int((blue + match) * 100))
}

//   Validate and apply one Sixel palette selection or color definition.
//
// Parameters:
//   - semantics: In-progress bounded palette and palette occupancy.
//   - parameters: Parsed command values; element zero selects the palette register.
//   - count: Occupied prefix length in `parameters`.
//
// Returns:
//   - True for a valid register selection or complete RGB/HLS definition.
//
// Side effects:
//   - Extends `palette_count` for valid register indices and replaces the selected color
//     only after a complete color definition passes validation.
graphics_sixel_apply_palette :: proc(
    semantics: ^Sixel_Semantics, parameters: [5]int, count: int) -> bool {
    if count == 0 || parameters[0] < 0 || parameters[0] >= len(semantics.palette) {
        return false
    }
    index := parameters[0]
    semantics.palette_count = max(semantics.palette_count, index + 1)
    if count == 1 { return true }
    if count != 5 { return false }
    color: u32
    valid := false
    if parameters[1] == 2 {
        color, valid = graphics_sixel_rgb(
            parameters[2], parameters[3], parameters[4])
    } else if parameters[1] == 1 {
        color, valid = graphics_sixel_hls(
            parameters[2], parameters[3], parameters[4])
    }
    if valid { semantics.palette[index] = color }
    return valid
}

//   Account for one repeated Sixel data character at the current raster pen.
//
// Parameters:
//   - semantics: In-progress raster extent updated without expanding pixel indices.
//   - byte: Sixel data byte in the inclusive ASCII range `?` through `~`.
//   - repeat: Positive horizontal repetition count.
//   - x, y: Mutable pixel coordinates of the current raster pen.
//
// Returns:
//   - False for invalid data, nonpositive repetition, or horizontal overflow.
//
// Side effects:
//   - Advances `x` and grows measured width and six-pixel-band height.
graphics_sixel_apply_data :: proc(
    semantics: ^Sixel_Semantics, byte: u8, repeat: int,
    x, y: ^int) -> bool {
    if repeat <= 0 || byte < '?' || byte > '~' ||
        x^ > max(int) - repeat {
        return false
    }
    x^ += repeat
    semantics.width = max(semantics.width, x^)
    semantics.height = max(semantics.height, y^ + 6)
    return true
}

//   Apply one Sixel control command and consume any trailing parameters or data.
//
// Parameters:
//   - semantics: In-progress extent, declared dimensions, and palette state.
//   - bytes: Borrowed complete Sixel payload.
//   - command: Control byte already consumed by the outer parser.
//   - index: In/out offset immediately following `command`.
//   - pen: Mutable raster position affected by carriage return and next-line commands.
//
// Returns:
//   - True when the command and its complete argument sequence are supported and valid.
//
// Side effects:
//   - May advance `index`, move `pen`, define a palette register, or publish declared
//     raster dimensions.
graphics_sixel_apply_command :: proc(
    semantics: ^Sixel_Semantics, bytes: []u8, command: u8,
    index: ^int, pen: ^Sixel_Pen) -> bool {
    switch command {
    case '!':
        repeat, present := graphics_sixel_parse_number(bytes, index)
        if !present || index^ >= len(bytes) { return false }
        byte := bytes[index^]
        index^ += 1
        return graphics_sixel_apply_data(
            semantics, byte, repeat, &pen.x, &pen.y)
    case '$': pen.x = 0
    case '-': pen.x, pen.y = 0, pen.y + 6
    case '"':
        parameters := graphics_sixel_parse_parameters(bytes, index)
        if !parameters.valid || parameters.count != 4 ||
            parameters.values[2] <= 0 || parameters.values[3] <= 0 {
            return false
        }
        semantics.declared_width = parameters.values[2]
        semantics.declared_height = parameters.values[3]
    case '#':
        parameters := graphics_sixel_parse_parameters(bytes, index)
        return parameters.valid && graphics_sixel_apply_palette(
            semantics, parameters.values, parameters.count)
    case: return false
    }
    return true
}

//   Scan one framed Sixel payload into bounded decode metadata.
//
// Parameters:
//   - bytes: Borrowed encoded Sixel commands retained in the frame transfer.
//   - header: Borrowed DCS parameters used to select transparent background behavior.
//   - limits: Attachment dimension and total-pixel admission policy.
//
// Returns:
//   - Measured extent, declared extent, palette, and transparency with `valid` set only
//     when the entire stream is supported and remains within all limits.
//
// Notes:
//   - This pass deliberately records scalar semantics without allocating or expanding the
//     indexed raster; Phase 5 decoding owns expansion.
graphics_parse_sixel :: proc(
    bytes, header: []u8, limits: termattachment.Limits) -> Sixel_Semantics {
    semantics := Sixel_Semantics{valid = true}
    if len(header) >= 3 && header[2] == '2' {
        semantics.transparent_background = true
    }
    pen: Sixel_Pen
    index := 0
    for index < len(bytes) && semantics.valid {
        byte := bytes[index]
        index += 1
        switch byte {
        case '?'..='~':
            semantics.valid = graphics_sixel_apply_data(
                &semantics, byte, 1, &pen.x, &pen.y)
        case:
            semantics.valid = graphics_sixel_apply_command(
                &semantics, bytes, byte, &index, &pen)
        }
        if max(semantics.width, semantics.declared_width) > limits.dimension_limit ||
            max(semantics.height, semantics.declared_height) > limits.dimension_limit {
            semantics.valid = false
        }
    }
    semantics.width = max(semantics.width, semantics.declared_width)
    semantics.height = max(semantics.height, semantics.declared_height)
    semantics.valid = semantics.valid && semantics.width > 0 && semantics.height > 0 &&
        semantics.width <= limits.image_pixel_limit / semantics.height
    return semantics
}

//   Reserve, place, and queue one parsed Sixel generation at the current cursor.
//
// Returns:
//   - True only when both placement and decode request retain the new generation.
graphics_queue_sixel_decode :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame, semantics: Sixel_Semantics) -> bool {
    anchor, valid := graphics_context_anchor(semantics_context)
    if !valid { return false }
    attachment_id, status := graphics_reserve_pending_attachment(
        state, .Sixel, semantics.width, semantics.height, false)
    if status != .Ok { return false }
    request := gfxprotocol.Graphics_Decode_Request{
        kind = .Sixel, producer = frame.producer, transfer_id = frame.transfer_id,
        attachment_id = attachment_id, width = semantics.width, height = semantics.height,
        place = true,
        geometry = {
            screen = anchor.screen, logical_row = anchor.logical_row,
            column = anchor.column, pixel_width = semantics.width,
            pixel_height = semantics.height, sizing = .Explicit_Pixels,
            cursor = .Advance,
        },
        palette = semantics.palette, palette_count = semantics.palette_count,
        transparent_background = semantics.transparent_background,
    }
    _, placement_outcome := termattachment.placement_admit(state.store, {
        attachment_id = attachment_id, geometry = request.geometry,
        lifecycle = .Cursor_Anchored,
    })
    if placement_outcome == .Admitted &&
        gfxprotocol.graphics_parser_queue_decode_request(state, request) {
        return true
    }
    gfxprotocol.graphics_discard_pending_attachment(state, attachment_id)
    return false
}

//   Queue one validated Sixel decode request and commit synchronous cursor effects.
//
// Parameters:
//   - semantics_context: Capability supplying the stable cursor anchor and Sixel modes.
//   - state: Graphics parser state owning the frame transfer and decode-request queue.
//   - frame: Completed Sixel frame with producer correlation and encoded transfer.
//
// Returns:
//   - True only when the frame transfer is retained by a queued decode request.
//
// Side effects:
//   - Queues bounded Sixel metadata and advances the terminal cursor in stream order.
//     DECSDM scrolling leaves it below the raster; reset DECSDM leaves it on the final
//     occupied row so a following line feed moves below the raster. Mode 8452 leaves
//     the cursor immediately to the right of the raster.
graphics_apply_sixel_frame :: proc(
    semantics_context: ^Context, state: ^gfxprotocol.Graphics_Parser_State,
    frame: gfxprotocol.Graphics_Frame) -> bool {
    bytes, found := termattachment.transfer_bytes(state.store, frame.transfer_id)
    header := frame.header
    if !found { return false }
    semantics := graphics_parse_sixel(
        bytes, header[:frame.header_byte_count], state.store.limits)
    if !semantics.valid { return false }
    if !gfxprotocol.graphics_parser_decode_request_has_capacity(state) { return false }
    anchor, valid := graphics_context_anchor(semantics_context)
    if !valid || !graphics_queue_sixel_decode(semantics_context, state, frame, semantics) {
        return false
    }
    rows := graphics_placement_rows(
        semantics_context, {
            pixel_width = semantics.width,
            pixel_height = semantics.height,
            sizing = .Explicit_Pixels,
        }, {width = semantics.width, height = semantics.height})
    if anchor.sixel_scrolling_mode {
        graphics_kitty_advance_cursor(semantics_context, rows)
    } else if rows > 1 {
        graphics_kitty_advance_cursor(semantics_context, rows - 1)
    }
    if anchor.sixel_cursor_right_mode && semantics_context.cell_width != nil &&
        semantics_context.advance_columns != nil {
        cell_width, cell_width_valid :=
            semantics_context.cell_width(semantics_context.user_data)
        if cell_width_valid && cell_width > 0 {
            columns := (semantics.width + cell_width - 1) / cell_width
            semantics_context.advance_columns(
                semantics_context.user_data, columns)
        }
    }
    return true
}