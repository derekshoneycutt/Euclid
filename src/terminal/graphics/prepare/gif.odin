package termgraphicsprepare

import "../../../taskpool"
import termattachment "../../attachment"

import "core:c"
import stbi "vendor:stb/image"

// Explicit limits applied before stb may allocate a complete animated GIF.
Gif_Animation_Limits :: struct {
    encoded_byte_limit: int,
    dimension_limit: int,
    image_pixel_limit: int,
    frame_limit: int,
    decoded_byte_limit: int,
    peak_byte_limit: int,
    min_frame_duration_ns: u64,
    max_frame_duration_ns: u64,
    duration_ns_limit: u64,
}

// Allocation-free metadata and exact decoded size for one admitted animated GIF.
Gif_Animation_Inspection :: struct {
    width: int,
    height: int,
    frame_count: int,
    decoded_byte_count: int,
    temporary_decode_byte_count: int,
    peak_byte_count: int,
    total_duration_ns: u64,
    repeat_count: int,
    has_loop_extension: bool,
    infinite: bool,
    valid: bool,
}

// Caller-owned exact destinations for one animated GIF decode.
Gif_Decode_Destination :: struct {
    frame_bytes: []u8,
    frames: []termattachment.Animation_Frame,
}

// Complete limits, metadata, and destinations for one preflighted GIF decode.
Gif_Preflighted_Decode_Request :: struct {
    limits: Gif_Animation_Limits,
    inspection: Gif_Animation_Inspection,
    destination: Gif_Decode_Destination,
    attachment_limits: termattachment.Limits,
}

// Mutable state for one allocation-free GIF block walk.
Gif_Walk_State :: struct {
    index: int,
    pending_delay_ms: int,
    repeat_count: int,
    has_loop_extension: bool,
    infinite: bool,
}

// Immutable policy and optional delay storage for one GIF marker transaction.
Gif_Walk_Marker_Request :: struct {
    limits: Gif_Animation_Limits,
    delays_ms: []int,
    expected_delays: [^]c.int,
}

// Convert attachment policy into the complete bounded GIF decode policy.
//
// Returns:
//   - Limits covering encoded input, retained canvases, temporary stb output,
//     frame occupancy, dimensions, and one normalized cycle duration.
gif_animation_limits :: proc(
    limits: termattachment.Limits) -> Gif_Animation_Limits {
    peak_byte_limit := limits.transfer_byte_limit
    if limits.cpu_byte_limit > max(int) - peak_byte_limit {
        peak_byte_limit = max(int)
    } else {
        peak_byte_limit += limits.cpu_byte_limit
    }
    if limits.animation_decode_byte_limit > max(int) - peak_byte_limit {
        peak_byte_limit = max(int)
    } else {
        peak_byte_limit += limits.animation_decode_byte_limit
    }
    return {
        encoded_byte_limit = limits.transfer_byte_limit,
        dimension_limit = limits.dimension_limit,
        image_pixel_limit = limits.image_pixel_limit,
        frame_limit = limits.animation_frame_limit,
        decoded_byte_limit = limits.cpu_byte_limit,
        peak_byte_limit = peak_byte_limit,
        min_frame_duration_ns = limits.animation_min_frame_duration_ns,
        max_frame_duration_ns = limits.animation_max_frame_duration_ns,
        duration_ns_limit = limits.animation_duration_ns_limit,
    }
}

// Read one little-endian GIF word from a previously bounds-checked offset.
gif_word :: proc(bytes: []u8, index: int) -> int {
    return int(bytes[index]) | int(bytes[index + 1]) << 8
}

// Skip one complete GIF data sub-block chain.
gif_skip_sub_blocks :: proc(bytes: []u8, index: ^int) -> bool {
    for {
        if index^ >= len(bytes) { return false }
        count := int(bytes[index^])
        index^ += 1
        if count == 0 { return true }
        if count > len(bytes) - index^ { return false }
        index^ += count
    }
}

// Skip a global or local color table selected by one packed descriptor byte.
gif_skip_color_table :: proc(bytes: []u8, index: ^int, packed: u8) -> bool {
    if packed & 0x80 == 0 { return true }
    byte_count := 3 * (1 << (u32(packed & 0x07) + 1))
    if byte_count > len(bytes) - index^ { return false }
    index^ += byte_count
    return true
}

// Consume one Graphic Control Extension and retain its delay for the next frame.
gif_walk_graphic_control :: proc(bytes: []u8, state: ^Gif_Walk_State) -> bool {
    if len(bytes) - state.index < 6 || bytes[state.index] != 4 ||
        bytes[state.index + 5] != 0 {
        return false
    }
    delay_cs := gif_word(bytes, state.index + 2)
    if delay_cs > max(int) / 10 { return false }
    state.pending_delay_ms = delay_cs * 10
    state.index += 6
    return true
}

// Consume one application extension and recover a Netscape-style loop count.
gif_walk_application :: proc(bytes: []u8, state: ^Gif_Walk_State) -> bool {
    if state.index >= len(bytes) { return false }
    identifier_count := int(bytes[state.index])
    state.index += 1
    if identifier_count > len(bytes) - state.index { return false }
    is_loop := identifier_count == 11 &&
        (string(bytes[state.index:state.index + 11]) == "NETSCAPE2.0" ||
        string(bytes[state.index:state.index + 11]) == "ANIMEXTS1.0")
    state.index += identifier_count
    found_loop := false
    for {
        if state.index >= len(bytes) { return false }
        count := int(bytes[state.index])
        state.index += 1
        if count == 0 { break }
        if count > len(bytes) - state.index { return false }
        if is_loop && !found_loop && count >= 3 && bytes[state.index] == 1 {
            if state.has_loop_extension { return false }
            state.repeat_count = gif_word(bytes, state.index + 1)
            state.has_loop_extension = true
            state.infinite = state.repeat_count == 0
            found_loop = true
        }
        state.index += count
    }
    return !is_loop || found_loop
}

// Consume one extension block while retaining animation metadata when relevant.
gif_walk_extension :: proc(bytes: []u8, state: ^Gif_Walk_State) -> bool {
    if state.index >= len(bytes) { return false }
    label := bytes[state.index]
    state.index += 1
    switch label {
    case 0xf9:
        return gif_walk_graphic_control(bytes, state)
    case 0xff:
        return gif_walk_application(bytes, state)
    case:
        return gif_skip_sub_blocks(bytes, &state.index)
    }
}

// Consume one image descriptor and its complete compressed-data block chain.
gif_walk_image :: proc(bytes: []u8, state: ^Gif_Walk_State) -> bool {
    if len(bytes) - state.index < 10 { return false }
    packed := bytes[state.index + 8]
    state.index += 9
    if !gif_skip_color_table(bytes, &state.index, packed) ||
        state.index >= len(bytes) {
        return false
    }
    state.index += 1
    return gif_skip_sub_blocks(bytes, &state.index)
}

// Finalize loop metadata and validate bounded finite playback duration.
gif_walk_finish :: proc(
    result: ^Gif_Animation_Inspection, state: Gif_Walk_State,
    limits: Gif_Animation_Limits, delay_count: int) -> bool {
    if result.frame_count == 0 || delay_count > 0 &&
        delay_count != result.frame_count {
        return false
    }
    result.repeat_count = state.repeat_count
    result.has_loop_extension = state.has_loop_extension
    result.infinite = state.infinite
    if !result.infinite {
        cycle_count := u64(result.repeat_count) + 1
        if result.total_duration_ns > limits.duration_ns_limit / cycle_count {
            return false
        }
    }
    result.valid = true
    return true
}

// Record and normalize one frame delay after its complete image block is valid.
gif_walk_record_frame :: proc(
    result: ^Gif_Animation_Inspection, state: ^Gif_Walk_State,
    limits: Gif_Animation_Limits, delays_ms: []int,
    expected_delays: [^]c.int) -> bool {
    if len(delays_ms) > 0 {
        delays_ms[result.frame_count] = state.pending_delay_ms
    }
    if expected_delays != nil &&
        int(expected_delays[result.frame_count]) != state.pending_delay_ms {
        return false
    }
    duration_ns, duration_valid := termattachment.animation_duration_from_units(
        u64(state.pending_delay_ms), 1000, {
            animation_min_frame_duration_ns = limits.min_frame_duration_ns,
            animation_max_frame_duration_ns = limits.max_frame_duration_ns,
        })
    if !duration_valid ||
        duration_ns > limits.duration_ns_limit - result.total_duration_ns {
        return false
    }
    result.total_duration_ns += duration_ns
    result.frame_count += 1
    state.pending_delay_ms = 0
    return true
}

// Report whether one GIF walk request is valid before reading stream metadata.
gif_walk_request_valid :: proc(
    bytes: []u8, limits: Gif_Animation_Limits,
    token: taskpool.Task_Cancellation_Token) -> bool {
    return !taskpool.task_cancellation_requested(token) && len(bytes) >= 14 &&
        encoded_image_format(bytes) == .Gif && limits.encoded_byte_limit > 0 &&
        len(bytes) <= limits.encoded_byte_limit && limits.dimension_limit > 0 &&
        limits.image_pixel_limit > 0 && limits.frame_limit > 0 &&
        limits.decoded_byte_limit > 0 && limits.peak_byte_limit > 0 &&
        limits.min_frame_duration_ns > 0 &&
        limits.max_frame_duration_ns >= limits.min_frame_duration_ns &&
        limits.duration_ns_limit > 0
}

// Walk a complete GIF stream and optionally copy one delay per image descriptor.
gif_walk_marker :: proc(
    bytes: []u8, request: Gif_Walk_Marker_Request, state: ^Gif_Walk_State,
    result: ^Gif_Animation_Inspection) -> (finished, valid: bool) {
    marker := bytes[state.index]
    state.index += 1
    if marker == 0x3b {
        valid = state.index == len(bytes) && gif_walk_finish(
            result, state^, request.limits, len(request.delays_ms))
        return true, valid
    }
    if marker == 0x21 {
        return false, gif_walk_extension(bytes, state)
    }
    if marker != 0x2c || result.frame_count >= request.limits.frame_limit ||
        len(request.delays_ms) > 0 && result.frame_count >= len(request.delays_ms) ||
        !gif_walk_image(bytes, state) {
        return false, false
    }
    return false, gif_walk_record_frame(
        result, state, request.limits, request.delays_ms, request.expected_delays)
}

// Walk a complete GIF stream and optionally copy one delay per image descriptor.
gif_walk :: proc(
    bytes: []u8, limits: Gif_Animation_Limits,
    delays_ms: []int, expected_delays: [^]c.int = nil,
    token: taskpool.Task_Cancellation_Token = {}) -> Gif_Animation_Inspection {
    if !gif_walk_request_valid(bytes, limits, token) {
        return {}
    }
    width := gif_word(bytes, 6)
    height := gif_word(bytes, 8)
    if width <= 0 || height <= 0 || width > limits.dimension_limit ||
        height > limits.dimension_limit || width > limits.image_pixel_limit / height {
        return {}
    }
    state := Gif_Walk_State{index = 13}
    if !gif_skip_color_table(bytes, &state.index, bytes[10]) { return {} }
    result := Gif_Animation_Inspection{width = width, height = height}
    for state.index < len(bytes) {
        if taskpool.task_cancellation_requested(token) { return {} }
        finished, valid := gif_walk_marker(
            bytes, {limits, delays_ms, expected_delays}, &state, &result)
        if !valid { return {} }
        if finished { return result }
    }
    return {}
}

// Inspect one complete GIF without allocating or interpreting compressed pixels.
inspect_gif_animation :: proc(
    bytes: []u8, limits: Gif_Animation_Limits,
    token: taskpool.Task_Cancellation_Token = {}) -> Gif_Animation_Inspection {
    result := gif_walk(bytes, limits, nil, nil, token)
    if !result.valid || result.frame_count > limits.decoded_byte_limit / 4 /
        result.height / result.width {
        return {}
    }
    result.decoded_byte_count = result.width * result.height * 4 * result.frame_count
    if result.frame_count > max(int) / int(size_of(c.int)) { return {} }
    delay_bytes := result.frame_count * int(size_of(c.int))
    if result.decoded_byte_count > max(int) - delay_bytes { return {} }
    result.temporary_decode_byte_count = result.decoded_byte_count + delay_bytes
    if len(bytes) > limits.peak_byte_limit ||
        result.decoded_byte_count > limits.peak_byte_limit - len(bytes) ||
        result.temporary_decode_byte_count >
            limits.peak_byte_limit - len(bytes) - result.decoded_byte_count {
        return {}
    }
    result.peak_byte_count = len(bytes) + result.decoded_byte_count +
        result.temporary_decode_byte_count
    return result
}

// Validate scalar preflight metadata against immutable input and exact destinations.
gif_preflight_matches_decode :: proc(
    bytes: []u8, limits: Gif_Animation_Limits,
    inspection: Gif_Animation_Inspection,
    destination: Gif_Decode_Destination) -> bool {
    if !inspection.valid || !gif_walk_request_valid(bytes, limits, {}) ||
        inspection.width != gif_word(bytes, 6) ||
        inspection.height != gif_word(bytes, 8) || inspection.frame_count <= 0 ||
        inspection.frame_count > limits.frame_limit ||
        inspection.width > limits.image_pixel_limit / inspection.height ||
        inspection.frame_count > limits.decoded_byte_limit / 4 /
            inspection.height / inspection.width {
        return false
    }
    decoded_byte_count := inspection.width * inspection.height * 4 *
        inspection.frame_count
    delay_byte_count := inspection.frame_count * int(size_of(c.int))
    temporary_byte_count := decoded_byte_count + delay_byte_count
    peak_byte_count := len(bytes) + decoded_byte_count + temporary_byte_count
    if inspection.decoded_byte_count != decoded_byte_count ||
        inspection.temporary_decode_byte_count != temporary_byte_count ||
        inspection.peak_byte_count != peak_byte_count ||
        peak_byte_count > limits.peak_byte_limit ||
        inspection.total_duration_ns > limits.duration_ns_limit ||
        inspection.infinite &&
            (!inspection.has_loop_extension || inspection.repeat_count != 0) ||
        !inspection.has_loop_extension &&
            (inspection.infinite || inspection.repeat_count != 0) ||
        len(destination.frame_bytes) != decoded_byte_count ||
        len(destination.frames) != inspection.frame_count {
        return false
    }
    return true
}

// Compare metadata produced by the complete post-stb stream walk.
gif_stream_metadata_matches :: proc(
    actual, preflight: Gif_Animation_Inspection) -> bool {
    return actual.valid && actual.width == preflight.width &&
        actual.height == preflight.height &&
        actual.frame_count == preflight.frame_count &&
        actual.total_duration_ns == preflight.total_duration_ns &&
        actual.repeat_count == preflight.repeat_count &&
        actual.has_loop_extension == preflight.has_loop_extension &&
        actual.infinite == preflight.infinite
}

// Decode one preflighted GIF into exact caller-owned pixels and frame descriptors.

// Build exact caller-owned frame descriptors from stb's validated delay table.
gif_stb_decode_matches :: proc(
    inspection: Gif_Animation_Inspection, width, height, frame_count: c.int,
    token: taskpool.Task_Cancellation_Token) -> bool {
    return !taskpool.task_cancellation_requested(token) &&
        int(width) == inspection.width && int(height) == inspection.height &&
        int(frame_count) == inspection.frame_count
}

// Build exact caller-owned frame descriptors from stb's validated delay table.
gif_build_frame_table :: proc(
    inspection: Gif_Animation_Inspection, destination: Gif_Decode_Destination,
    stb_delays: [^]c.int, attachment_limits: termattachment.Limits,
    token: taskpool.Task_Cancellation_Token) -> bool {
    canvas_byte_count := inspection.width * inspection.height * 4
    for index in 0..<inspection.frame_count {
        if taskpool.task_cancellation_requested(token) { return false }
        duration_ns, valid := termattachment.animation_duration_from_units(
            u64(stb_delays[index]), 1000, attachment_limits)
        if !valid { return false }
        destination.frames[index] = {
            pixels = {offset = index * canvas_byte_count, count = canvas_byte_count},
            duration_ns = duration_ns,
        }
    }
    return true
}

// Decode one preflighted GIF into exact caller-owned pixels and frame descriptors.
//
// Returns:
//   - True only when scalar preflight, stb output, and the post-stb stream walk agree.
decode_preflighted_gif_animation :: proc(
    bytes: []u8, request: Gif_Preflighted_Decode_Request,
    token: taskpool.Task_Cancellation_Token = {}) -> (Gif_Animation_Inspection, bool) {
    limits := request.limits
    inspection := request.inspection
    destination := request.destination
    if !gif_preflight_matches_decode(bytes, limits, inspection, destination) ||
        len(bytes) > int(max(c.int)) || taskpool.task_cancellation_requested(token) {
        return {}, false
    }
    width, height, frame_count, channels: c.int
    stb_delays: [^]c.int
    if taskpool.task_cancellation_requested(token) { return {}, false }
    pixels := stbi.load_gif_from_memory(
        raw_data(bytes), c.int(len(bytes)), &stb_delays,
        &width, &height, &frame_count, &channels, 4)
    if pixels == nil {
        if stb_delays != nil { stbi.image_free(stb_delays) }
        return {}, false
    }
    defer stbi.image_free(pixels)
    if stb_delays == nil { return {}, false }
    defer stbi.image_free(stb_delays)
    if !gif_stb_decode_matches(
        inspection, width, height, frame_count, token) {
        return {}, false
    }
    expected := gif_walk(bytes, limits, nil, stb_delays, token)
    if !gif_stream_metadata_matches(expected, inspection) { return {}, false }
    if !gif_build_frame_table(
        inspection, destination, stb_delays, request.attachment_limits, token) {
        return {}, false
    }
    if taskpool.task_cancellation_requested(token) { return {}, false }
    copy(destination.frame_bytes, pixels[:len(destination.frame_bytes)])
    return inspection, !taskpool.task_cancellation_requested(token)
}

// Inspect and decode a GIF for callers that do not already own preflight metadata.
decode_gif_animation :: proc(
    bytes: []u8, limits: Gif_Animation_Limits,
    destination: Gif_Decode_Destination,
    attachment_limits: termattachment.Limits,
    token: taskpool.Task_Cancellation_Token = {}) -> (Gif_Animation_Inspection, bool) {
    inspection := inspect_gif_animation(bytes, limits, token)
    if !inspection.valid { return {}, false }
    return decode_preflighted_gif_animation(bytes, {
        limits = limits,
        inspection = inspection,
        destination = destination,
        attachment_limits = attachment_limits,
    }, token)
}