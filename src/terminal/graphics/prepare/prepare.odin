// Package termgraphicsprepare performs bounded CPU raster preparation without display resources.
package termgraphicsprepare

import "../../../taskpool"
import termattachment "../../attachment"
import termgraphicsnative "../native"

import "core:c"
import stbi "vendor:stb/image"

// Encoded image formats admitted by static terminal graphics protocols.
Encoded_Image_Format :: enum u8 {
    Unknown,
    Png,
    Jpeg,
    Gif,
}

// Finite CPU preparation selected after synchronous protocol validation.
Prepare_Kind :: enum u8 {
    Encoded_Image,
    Animated_Gif,
    Zlib_Rgb,
    Zlib_Rgba,
    Sixel,
}

// Bounded scalar result of inspecting an encoded image header.
Image_Inspection :: struct {
    format: Encoded_Image_Format,
    width: int,
    height: int,
    valid: bool,
}

// Bounded dimensions extracted without allocating decoder state.
Image_Dimensions :: struct {
    width: int,
    height: int,
    valid: bool,
}

// Complete borrowed input and exclusive output for one finite preparation.
Prepare_Request :: struct {
    // Work classification and encoded or command input borrowed through task join.
    kind: Prepare_Kind,
    input: []u8,

    // Exact output geometry and mutable RGBA destination reserved before submission.
    width: int,
    height: int,
    output: []u8,
    animation_frames: []termattachment.Animation_Frame,
    attachment_limits: termattachment.Limits,
    gif_inspection: Gif_Animation_Inspection,

    // Final Sixel palette metadata and initial background policy.
    palette: [256]u32,
    palette_count: int,
    transparent_background: bool,
}

// Mutable Sixel raster state used only during one worker preparation.
Sixel_State :: struct {
    x: int,
    y: int,
    selected_color: int,
    palette: [256]u32,
}

// Read one big-endian 16-bit value from a validated byte offset.
read_u16_be :: proc(bytes: []u8, offset: int) -> int {
    return int(bytes[offset]) << 8 | int(bytes[offset + 1])
}

// Read one big-endian 32-bit value from a validated byte offset.
read_u32_be :: proc(bytes: []u8, offset: int) -> u32 {
    return u32(bytes[offset]) << 24 | u32(bytes[offset + 1]) << 16 |
        u32(bytes[offset + 2]) << 8 | u32(bytes[offset + 3])
}

// Return whether one JPEG marker carries frame dimensions.
jpeg_is_start_of_frame :: proc(marker: u8) -> bool {
    return marker >= 0xc0 && marker <= 0xcf &&
        marker != 0xc4 && marker != 0xc8 && marker != 0xcc
}

// Read dimensions from one validated JPEG start-of-frame segment.
jpeg_frame_dimensions :: proc(
    bytes: []u8, index, segment_length: int) -> Image_Dimensions {
    if segment_length < 8 || bytes[index + 2] == 0 { return {} }
    height := read_u16_be(bytes, index + 3)
    width := read_u16_be(bytes, index + 5)
    return {width, height, width > 0 && height > 0}
}

// Read dimensions from one bounded JPEG marker stream before scan data begins.
jpeg_dimensions :: proc(bytes: []u8) -> Image_Dimensions {
    if len(bytes) < 4 || bytes[0] != 0xff || bytes[1] != 0xd8 { return {} }
    index := 2
    for index < len(bytes) {
        for index < len(bytes) && bytes[index] == 0xff { index += 1 }
        if index >= len(bytes) { return {} }
        marker := bytes[index]
        index += 1
        if marker == 0x00 || marker == 0xd9 || marker == 0xda { return {} }
        if marker == 0x01 || marker >= 0xd0 && marker <= 0xd7 { continue }
        if index > len(bytes) - 2 { return {} }
        segment_length := read_u16_be(bytes, index)
        if segment_length < 2 || segment_length > len(bytes) - index { return {} }
        if jpeg_is_start_of_frame(marker) {
            return jpeg_frame_dimensions(bytes, index, segment_length)
        }
        index += segment_length
    }
    return {}
}

// Read dimensions from one canonical PNG, JPEG, or GIF header.
encoded_image_dimensions :: proc(
    bytes: []u8, format: Encoded_Image_Format) -> Image_Dimensions {
    switch format {
    case .Png:
        if len(bytes) < 24 || read_u32_be(bytes, 8) != 13 ||
            string(bytes[12:16]) != "IHDR" { return {} }
        width := read_u32_be(bytes, 16)
        height := read_u32_be(bytes, 20)
        if width == 0 || height == 0 ||
            u64(width) > u64(max(int)) || u64(height) > u64(max(int)) {
            return {}
        }
        return {int(width), int(height), true}
    case .Jpeg:
        return jpeg_dimensions(bytes)
    case .Gif:
        if len(bytes) < 10 { return {} }
        width := int(bytes[6]) | int(bytes[7]) << 8
        height := int(bytes[8]) | int(bytes[9]) << 8
        return {width, height, width > 0 && height > 0}
    case .Unknown:
        return {}
    }
    return {}
}

//   Classify one supported encoded image from its canonical signature.
//
// Returns:
//   - PNG, JPEG, GIF, or Unknown without reading beyond `bytes`.
encoded_image_format :: proc(bytes: []u8) -> Encoded_Image_Format {
    if len(bytes) >= 8 && bytes[0] == 0x89 && bytes[1] == 'P' &&
        bytes[2] == 'N' && bytes[3] == 'G' && bytes[4] == 0x0d &&
        bytes[5] == 0x0a && bytes[6] == 0x1a && bytes[7] == 0x0a {
        return .Png
    }
    if len(bytes) >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 &&
        bytes[2] == 0xff {
        return .Jpeg
    }
    if len(bytes) >= 6 &&
        (string(bytes[:6]) == "GIF87a" || string(bytes[:6]) == "GIF89a") {
        return .Gif
    }
    return .Unknown
}

//   Inspect encoded dimensions synchronously under attachment policy.
//
// Parameters:
//   - bytes: Borrowed complete encoded image.
//   - limits: Dimension, pixel, and decoded CPU-byte policy.
//
// Returns:
//   - Valid format and dimensions only when the complete supported header is bounded
//     and an exact RGBA result fits every configured limit.
inspect_image :: proc(
    bytes: []u8, limits: termattachment.Limits) -> Image_Inspection {
    format := encoded_image_format(bytes)
    if format == .Unknown { return {} }
    dimensions := encoded_image_dimensions(bytes, format)
    if !dimensions.valid || dimensions.width > limits.dimension_limit ||
        dimensions.height > limits.dimension_limit ||
        dimensions.width > limits.image_pixel_limit / dimensions.height ||
        dimensions.width > limits.cpu_byte_limit / dimensions.height / 4 {
        return {}
    }
    return {
        format = format,
        width = dimensions.width,
        height = dimensions.height,
        valid = true,
    }
}

//   Decode one inspected PNG, JPEG, or GIF first frame into exact RGBA storage.
prepare_encoded_image :: proc(
    request: ^Prepare_Request,
    token: taskpool.Task_Cancellation_Token = {}) -> bool {
    if taskpool.task_cancellation_requested(token) { return false }
    inspection := inspect_image(request.input, {
        attachment_capacity = 1,
        placement_capacity = 1,
        transfer_capacity = 1,
        transfer_byte_limit = max(len(request.input), 1),
        dimension_limit = max(request.width, request.height),
        image_pixel_limit = request.width * request.height,
        cpu_byte_limit = len(request.output),
        gpu_byte_limit = len(request.output),
    })
    if !inspection.valid || inspection.width != request.width ||
        inspection.height != request.height ||
        taskpool.task_cancellation_requested(token) {
        return false
    }
    native_format: termgraphicsnative.Static_Image_Format
    switch inspection.format {
    case .Png: native_format = .Png
    case .Jpeg: native_format = .Jpeg
    case .Gif: native_format = .Gif
    case .Unknown: return false
    }
    decoded := termgraphicsnative.decode_static_image(
        request.input, request.output, request.width, request.height, native_format)
    return decoded && !taskpool.task_cancellation_requested(token)
}

// Decode one admitted animated GIF into reserved canvases and descriptors.
//
// Returns:
//   - True only after preflight, SDL_image pixels, encoded timing, and normalized
//     frame descriptors agree with the exact reserved destinations.
prepare_animated_gif :: proc(
    request: ^Prepare_Request,
    token: taskpool.Task_Cancellation_Token = {}) -> bool {
    if len(request.animation_frames) <= 1 { return false }
    inspection, decoded := decode_preflighted_gif_animation(
        request.input, {
            limits = gif_animation_limits(request.attachment_limits),
            inspection = request.gif_inspection,
            destination = {
                frame_bytes = request.output,
                frames = request.animation_frames,
            },
            attachment_limits = request.attachment_limits,
        }, token)
    return decoded && inspection.width == request.width &&
        inspection.height == request.height
}

//   Expand one zlib stream into an exact raw RGB or RGBA destination.
prepare_zlib :: proc(
    request: ^Prepare_Request, bytes_per_pixel: int,
    token: taskpool.Task_Cancellation_Token = {}) -> bool {
    expected := request.width * request.height * bytes_per_pixel
    if expected <= 0 || len(request.output) != request.width * request.height * 4 {
        return false
    }
    if taskpool.task_cancellation_requested(token) { return false }
    decoded := stbi.zlib_decode_buffer(
        raw_data(request.output), c.int(expected), raw_data(request.input),
        c.int(len(request.input)))
    if int(decoded) != expected || taskpool.task_cancellation_requested(token) {
        return false
    }
    for pixel := request.width * request.height - 1; pixel >= 0; pixel -= 1 {
        if pixel % request.width == request.width - 1 &&
            taskpool.task_cancellation_requested(token) {
            return false
        }
        source := pixel * bytes_per_pixel
        destination := pixel * 4
        red := request.output[source]
        green := request.output[source + 1]
        blue := request.output[source + 2]
        alpha := request.output[source + 3] if bytes_per_pixel == 4 else u8(255)
        request.output[destination] = red
        request.output[destination + 1] = green
        request.output[destination + 2] = blue
        request.output[destination + 3] = alpha
    }
    return true
}

//   Parse one decimal Sixel parameter at a mutable byte offset.
sixel_number :: proc(bytes: []u8, index: ^int) -> (int, bool) {
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

//   Parse up to five semicolon-delimited Sixel command values.
sixel_parameters :: proc(bytes: []u8, index: ^int) -> ([5]int, int) {
    values: [5]int
    count := 0
    for count < len(values) {
        value, present := sixel_number(bytes, index)
        if !present { break }
        values[count] = value
        count += 1
        if index^ >= len(bytes) || bytes[index^] != ';' { break }
        index^ += 1
    }
    return values, count
}

//   Store one packed Sixel color into an RGBA output pixel.
sixel_write_color :: proc(output: []u8, pixel: int, color: u32) {
    offset := pixel * 4
    output[offset] = u8(color >> 24)
    output[offset + 1] = u8(color >> 16)
    output[offset + 2] = u8(color >> 8)
    output[offset + 3] = u8(color)
}

//   Convert one Sixel HLS definition to packed opaque RGBA.
//
// Returns:
//   - Packed `0xRRGGBBFF` and true, or zero and false for an invalid component.
sixel_hls :: proc(hue, lightness, saturation: int) -> (u32, bool) {
    if hue < 0 || hue > 360 || lightness < 0 || lightness > 100 ||
        saturation < 0 || saturation > 100 {
        return 0, false
    }
    chroma := f32(1 - abs(f32(2 * lightness) / 100 - 1)) *
        f32(saturation) / 100
    sector := f32((hue + 120) % 360) / 60
    remainder := sector - f32(int(sector / 2) * 2)
    second := chroma * f32(1 - abs(remainder - 1))
    red, green, blue: f32
    if sector < 1 { red, green = chroma, second
    } else if sector < 2 { red, green = second, chroma
    } else if sector < 3 { green, blue = chroma, second
    } else if sector < 4 { green, blue = second, chroma
    } else if sector < 5 { red, blue = second, chroma
    } else { red, blue = chroma, second }
    match := f32(lightness) / 100 - chroma / 2
    packed := u32(int((red + match) * 255)) << 24 |
        u32(int((green + match) * 255)) << 16 |
        u32(int((blue + match) * 255)) << 8 | 0xff
    return packed, true
}

//   Paint one repeated Sixel data byte within the exact output extent.
sixel_paint :: proc(
    request: ^Prepare_Request, state: ^Sixel_State,
    byte: u8, repeat: int) -> bool {
    if byte < '?' || byte > '~' || repeat <= 0 ||
        state.x > request.width - repeat {
        return false
    }
    color := state.palette[state.selected_color]
    if color == 0 { color = 0x000000ff }
    bits := byte - '?'
    for column in 0..<repeat {
        for bit in 0..<6 {
            row := state.y + bit
            if bits & (u8(1) << u8(bit)) != 0 && row < request.height {
                sixel_write_color(
                    request.output, row * request.width + state.x + column, color)
            }
        }
    }
    state.x += repeat
    return true
}

//   Apply one Sixel palette selection or RGB/HLS definition.
sixel_palette :: proc(
    state: ^Sixel_State, values: [5]int, count: int) -> bool {
    if count == 0 || values[0] < 0 || values[0] >= len(state.palette) {
        return false
    }
    state.selected_color = values[0]
    if count == 1 { return true }
    if count != 5 { return false }
    if values[1] == 2 {
        if min(values[2], values[3], values[4]) < 0 ||
            max(values[2], values[3], values[4]) > 100 {
            return false
        }
        red := u32(values[2] * 255 / 100)
        green := u32(values[3] * 255 / 100)
        blue := u32(values[4] * 255 / 100)
        state.palette[values[0]] = red << 24 | green << 16 | blue << 8 | 0xff
        return true
    }
    if values[1] == 1 {
        color, valid := sixel_hls(values[2], values[3], values[4])
        if valid { state.palette[values[0]] = color }
        return valid
    }
    return false
}

// Apply one Sixel data or control byte at the mutable input position.
sixel_apply_command :: proc(
    request: ^Prepare_Request, state: ^Sixel_State, index: ^int) -> bool {
    byte := request.input[index^]
    index^ += 1
    if byte >= '?' && byte <= '~' {
        return sixel_paint(request, state, byte, 1)
    }
    switch byte {
    case '!':
        repeat, present := sixel_number(request.input, index)
        if !present || index^ >= len(request.input) { return false }
        byte = request.input[index^]
        index^ += 1
        return sixel_paint(request, state, byte, repeat)
    case '$': state.x = 0
    case '-': state.x, state.y = 0, state.y + 6
    case '#':
        values, count := sixel_parameters(request.input, index)
        return sixel_palette(state, values, count)
    case '"':
        _, count := sixel_parameters(request.input, index)
        return count == 4
    case: return false
    }
    return true
}

//   Expand one validated Sixel stream into exact RGBA storage.
prepare_sixel :: proc(
    request: ^Prepare_Request,
    token: taskpool.Task_Cancellation_Token = {}) -> bool {
    background := u32(0) if request.transparent_background else u32(0x000000ff)
    for row in 0..<request.height {
        if taskpool.task_cancellation_requested(token) { return false }
        for column in 0..<request.width {
            sixel_write_color(
                request.output, row * request.width + column, background)
        }
    }
    state := Sixel_State{palette = request.palette}
    index := 0
    for index < len(request.input) {
        if taskpool.task_cancellation_requested(token) { return false }
        if !sixel_apply_command(request, &state, &index) { return false }
    }
    return true
}

//   Perform one finite CPU raster preparation without calling display APIs.
//
// Returns:
//   - True only when the complete input produces the exact preallocated RGBA output.
prepare :: proc(
    request: ^Prepare_Request,
    token: taskpool.Task_Cancellation_Token = {}) -> bool {
    if request == nil || request.width <= 0 || request.height <= 0 ||
        request.width > max(int) / request.height ||
        request.width * request.height > max(int) / 4 {
        return false
    }
    if taskpool.task_cancellation_requested(token) { return false }
    if request.kind == .Animated_Gif {
        return prepare_animated_gif(request, token)
    }
    if len(request.output) != request.width * request.height * 4 { return false }
    switch request.kind {
    case .Encoded_Image: return prepare_encoded_image(request, token)
    case .Animated_Gif: return false
    case .Zlib_Rgb: return prepare_zlib(request, 3, token)
    case .Zlib_Rgba: return prepare_zlib(request, 4, token)
    case .Sixel: return prepare_sixel(request, token)
    }
    return false
}