package gif

// This just encodes gif files. We use the standard allocator in the current context, freeing
// when aborted or ended.

import "../core"

import "core:mem"

GIF_LZW_TABLE_CAPACITY :: 4096
GIF_LZW_STRIDE :: 256
GIF_MAX_TABLE_BYTES :: (1 << 16) + 1
GIF_COLOR_DEPTH_TABLE_SIZE :: 17
GIF_DITHER_TILE_SIZE :: 4
GIF_DITHER_SHIFT :: 12
GIF_MAX_PIXELS :: 268435456
GIF_HEADER_SIZE :: 32
GIF_FRAME_DEPTH_BIAS :: 160

GIF_GCE_INTRODUCER :: 0x21
GIF_GCE_LABEL :: 0xF9
GIF_GCE_BLOCK_SIZE :: 0x04
GIF_GCE_PACKED_DISPOSE_BACKGROUND_NO_TRANSPARENCY :: 0x05
GIF_GCE_PACKED_DISPOSE_BACKGROUND_TRANSPARENCY :: 0x09
GIF_GCE_TRANSPARENT_INDEX_DEFAULT :: 0x00
GIF_GCE_BLOCK_TERMINATOR :: 0x00

GIF_IMAGE_SEPARATOR :: 0x2C
GIF_IMAGE_LOCAL_COLOR_TABLE_FLAG :: 0x80

GIF_TRAILER :: 0x3B

GifEncodeResult :: core.Gif_Encode_Result
GifEncodeFrame :: core.Gif_Encode_Frame
Gif_Encode_Buffer :: core.Gif_Encode_Buffer
Gif_Encode_State :: core.Gif_Encode_State

#assert((GIF_DITHER_TILE_SIZE & (GIF_DITHER_TILE_SIZE - 1)) == 0)


Gif_Lzw_State :: struct {
    length: int,
    stride: int,
}

Gif_Rgb :: struct {
    R: u8,
    G: u8,
    B: u8,
}

Gif_Encode_Cook_Attempt :: struct {
    used_count: int,
    depth: int,
    r_bits: int,
    g_bits: int,
    b_bits: int,
}

Gif_Encode_Palette_Build :: struct {
    tlb_size: int,
    table_idx: int,
    has_transparent_pixels: bool,
}

Gif_Encode_Bitstream_State :: struct {
    buffer: []u8,
    stream_length: int,
    bit_accum: u64,
    bit_count: int,
    clear_code: int,
    end_code: int,
}

//   Initialize GIF encoder state for a new output stream.
//
// Parameters:
//   - state: Encoder state to initialize/reset.
//   - width: Frame width in pixels; must be within GIF limits.
//   - height: Frame height in pixels; must be within GIF limits.
//
// Returns:
//   - ok: true when state and header allocation succeed, otherwise false.
gif_encode_begin :: proc(state: ^Gif_Encode_State, width, height: int) -> bool {
    if width < 1 || height < 1 || width > 65535 || height > 65535 ||
       width >= GIF_MAX_PIXELS / height {
        state.list_head = nil
        state.list_tail = nil
        return false
    }

    gif_encode_free_state(state)

    state.width = width
    state.height = height
    state.alpha_threshold = 0
    state.use_bgra = false
    state.frames_submitted = 0

    state.lzw_mem = make([]i16, GIF_LZW_TABLE_CAPACITY * GIF_LZW_STRIDE)
    state.tlb_mem = make([]u8, GIF_MAX_TABLE_BYTES)
    state.used_mem = make([]u8, GIF_MAX_TABLE_BYTES)

    pixel_count := width * height
    state.previous_frame.pixels = make([]u32, pixel_count)
    state.current_frame.pixels = make([]u32, pixel_count)

    if len(state.lzw_mem) == 0 || len(state.tlb_mem) == 0 || len(state.used_mem) == 0 ||
       len(state.previous_frame.pixels) == 0 || len(state.current_frame.pixels) == 0 {
        gif_encode_free_state(state)
        return false
    }

    header, ok := gif_encode_new_buffer(GIF_HEADER_SIZE)
    if !ok || header == nil {
        gif_encode_free_state(state)
        return false
    }

    out := header.data
    if !gif_encode_write_logical_screen_and_netscape_ext(out, width, height) {
        gif_encode_free_buffer(header)
        gif_encode_free_state(state)
        return false
    }

    gif_encode_push_buffer(state, header)
    return true
}

//   Encode and append one frame to an initialized GIF stream.
//
// Parameters:
//   - state: Active encoder state created by gif_encode_begin.
//   - pixel_data: Pointer to source RGBA/BGRA pixel bytes.
//   - centiseconds_per_frame: GIF frame delay in centiseconds.
//   - quality: Quantization quality in range [1, 16] (clamped internally).
//   - pitch_in_bytes: Row stride in bytes; 0 uses width * 4.
//
// Returns:
//   - ok: true when the frame is encoded and appended, otherwise false.
gif_encode_frame :: proc(
    state: ^Gif_Encode_State,
    pixel_data: rawptr,
    centiseconds_per_frame: int,
    quality: int,
    pitch_in_bytes: int) -> bool {
    if state.list_head == nil || pixel_data == nil {
        return false
    }

    quality_clamped := clamp(quality, 1, 16)

    pitch := pitch_in_bytes
    if pitch == 0 {
        pitch = state.width * 4
    }

    base := uintptr(pixel_data)
    if pitch < 0 {
        base += uintptr((-pitch) * (state.height - 1))
    }
    raw := transmute([^]u8)base

    next_depth := gif_encode_next_frame_depth(
        quality_clamped,
        state.frames_submitted,
        state.previous_frame.depth,
        state.previous_frame.count,
    )

    gif_encode_cook_frame(
        &state.current_frame,
        raw,
        state.used_mem,
        state.width,
        state.height,
        pitch,
        state.use_bgra,
        state.alpha_threshold,
        next_depth,
    )

    node, ok := gif_encode_compress_frame(state, state.current_frame, centiseconds_per_frame)
    if !ok || node == nil {
        gif_encode_free_state(state)
        return false
    }

    gif_encode_push_buffer(state, node)

    tmp := state.previous_frame
    state.previous_frame = state.current_frame
    state.current_frame = tmp

    state.frames_submitted += 1
    return true
}

//   Finalize the GIF stream and return a contiguous encoded byte buffer.
//
// Parameters:
//   - state: Encoder state holding accumulated header and frame chunks.
//
// Returns:
//   - result: Encoded GIF bytes and length; empty result on failure or no data.
//
// Notes:
//   - This call clears encoder state regardless of success.
gif_encode_end :: proc(state: ^Gif_Encode_State) -> GifEncodeResult {
    if state.list_head == nil {
        return GifEncodeResult{}
    }

    total := 1
    for n := state.list_head; n != nil; n = n.next {
        total += n.size
    }

    out := make([]u8, total)
    if len(out) == 0 {
        gif_encode_free_state(state)
        return GifEncodeResult{}
    }

    w := 0
    for n := state.list_head; n != nil; n = n.next {
        mem.copy(rawptr(&out[w]), rawptr(&n.data[0]), n.size)
        w += n.size
    }

    out[w] = GIF_TRAILER
    w += 1

    gif_encode_free_state(state)

    return GifEncodeResult{
        data = out,
        data_size = w,
    }
}

//   Release heap memory owned by a GifEncodeResult.
//
// Parameters:
//   - result: Output result previously returned from gif_encode_end.
//
// Returns:
//   - none.
gif_encode_free :: proc(result: ^GifEncodeResult) {
    if result == nil {
        return
    }
    if len(result.data) > 0 {
        delete(result.data)
    }
    result^ = {}
}



//   Compute the number of bits required to represent a positive integer.
gif_encode_bit_log :: #force_inline proc(i: int) -> int {
    v := i
    if v <= 0 {
        return 0
    }

    out := 0
    for v > 0 {
        v >>= 1
        out += 1
    }
    return out
}

//   Allocate a new linked-list buffer node for encoded GIF data.
//
// Notes:
//   - Caller owns the returned node and must free it with gif_encode_free_buffer.
gif_encode_new_buffer :: proc(size: int) -> (^Gif_Encode_Buffer, bool) {
    n := new(Gif_Encode_Buffer)
    if n == nil {
        return nil, false
    }

    n.data = make([]u8, size)
    if len(n.data) != size {
        free(n)
        return nil, false
    }

    n.size = size
    n.next = nil
    return n, true
}

//   Free a linked-list buffer node and its byte slice.
gif_encode_free_buffer :: proc(node: ^Gif_Encode_Buffer) {
    if node == nil {
        return
    }
    if len(node.data) > 0 {
        delete(node.data)
    }
    free(node)
}

//   Append a buffer node to the encoder output list.
gif_encode_push_buffer :: proc(state: ^Gif_Encode_State, node: ^Gif_Encode_Buffer) {
    if state.list_head == nil {
        state.list_head = node
        state.list_tail = node
        return
    }

    state.list_tail.next = node
    state.list_tail = node
}

//   Pop and return the head buffer node from the encoder output list.
gif_encode_pop_head_buffer :: proc(state: ^Gif_Encode_State) -> ^Gif_Encode_Buffer {
    if state.list_head == nil {
        return nil
    }

    n := state.list_head
    state.list_head = n.next
    n.next = nil

    if state.list_head == nil {
        state.list_tail = nil
    }

    return n
}

//   Release all encoder-owned allocations and reset state fields.
//
// Notes:
//   - After this call, state is zeroed and no previous buffers remain valid.
gif_encode_free_state :: proc(state: ^Gif_Encode_State) {
    delete(state.previous_frame.pixels)
    delete(state.current_frame.pixels)
    delete(state.lzw_mem)
    delete(state.tlb_mem)
    delete(state.used_mem)

    n := state.list_head
    for n != nil {
        next := n.next
        gif_encode_free_buffer(n)
        n = next
    }

    state^ = {}
}

//   Reset LZW table memory and initialize active table metadata.
gif_encode_lzw_reset :: proc(lzw_mem: []i16, lzw: ^Gif_Lzw_State, table_size: int, stride: int) {
    for i := 0; i < len(lzw_mem); i += 1 {
        lzw_mem[i] = -1
    }
    lzw.length = table_size + 2
    lzw.stride = stride
}

//   Write one variable-width code into the LZW bitstream accumulator.
//
// Notes:
//   - Returns false when the destination stream buffer is full.
gif_encode_write_code_bits :: proc(
    stream: []u8,
    stream_len: ^int,
    bit_accum: ^u64,
    bit_count: ^int,
    code: int,
    width: int) -> bool {
    bit_accum^ |= (u64(code) << u32(bit_count^))
    bit_count^ += width

    for bit_count^ >= 8 {
        if stream_len^ >= len(stream) {
            return false
        }
        stream[stream_len^] = u8(bit_accum^ & 0xFF)
        stream_len^ += 1
        bit_accum^ >>= 8
        bit_count^ -= 8
    }
    return true
}

//   Flush remaining buffered bits into the output stream.
//
// Notes:
//   - Returns false when the destination stream buffer is full.
gif_encode_flush_code_bits :: proc(
    stream: []u8,
    stream_len: ^int,
    bit_accum: ^u64,
    bit_count: ^int) -> bool {
    for bit_count^ > 0 {
        if stream_len^ >= len(stream) {
            return false
        }
        stream[stream_len^] = u8(bit_accum^ & 0xFF)
        stream_len^ += 1
        bit_accum^ >>= 8
        if bit_count^ >= 8 {
            bit_count^ -= 8
        } else {
            bit_count^ = 0
        }
    }
    return true
}

//   Write a 16-bit little-endian integer into a byte slice.
gif_encode_write_u16le :: #force_inline proc(dst: []u8, offset: int, value: int) -> bool {
    if offset < 0 || offset + 1 >= len(dst) {
        return false
    }
    dst[offset + 0] = u8(value & 0xFF)
    dst[offset + 1] = u8((value >> 8) & 0xFF)
    return true
}

//   Resolve per-channel quantization bit depths for a chosen GIF palette depth.
gif_encode_depth_bits :: #force_inline proc(depth: int, use_bgra: bool) -> (int, int, int) {
    rdepths := [GIF_COLOR_DEPTH_TABLE_SIZE]int{0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5}
    gdepths := [GIF_COLOR_DEPTH_TABLE_SIZE]int{0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6}
    bdepths := [GIF_COLOR_DEPTH_TABLE_SIZE]int{0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5}

    if use_bgra {
        return bdepths[depth], gdepths[depth], rdepths[depth]
    }
    return rdepths[depth], gdepths[depth], bdepths[depth]
}

//   Return ordered-dither kernel value for a tile-relative pixel position.
gif_encode_dither_kernel_value :: #force_inline proc(dx, dy: int) -> int {
    idx := dy * GIF_DITHER_TILE_SIZE + dx
    switch idx {
    case 0: return 0 << GIF_DITHER_SHIFT
    case 1: return 8 << GIF_DITHER_SHIFT
    case 2: return 2 << GIF_DITHER_SHIFT
    case 3: return 10 << GIF_DITHER_SHIFT
    case 4: return 12 << GIF_DITHER_SHIFT
    case 5: return 4 << GIF_DITHER_SHIFT
    case 6: return 14 << GIF_DITHER_SHIFT
    case 7: return 6 << GIF_DITHER_SHIFT
    case 8: return 3 << GIF_DITHER_SHIFT
    case 9: return 11 << GIF_DITHER_SHIFT
    case 10: return 1 << GIF_DITHER_SHIFT
    case 11: return 9 << GIF_DITHER_SHIFT
    case 12: return 15 << GIF_DITHER_SHIFT
    case 13: return 7 << GIF_DITHER_SHIFT
    case 14: return 13 << GIF_DITHER_SHIFT
    case 15: return 5 << GIF_DITHER_SHIFT
    }
    return 0
}

//   Clear palette-used flags for the active palette size.
gif_encode_clear_used_entries :: #force_inline proc(used: []u8, palette_size: int) {
    for i := 0; i < palette_size; i += 1 {
        used[i] = 0
    }
}

//   Dither and quantize raw RGBA/BGRA pixels into palette indices.
//
// Notes:
//   - Transparent pixels are mapped to the final palette slot.
gif_encode_dither_and_quantize_pixels :: proc(
    cooked: []u32,
    raw_pixels: [^]u8,
    width: int,
    height: int,
    pitch: int,
    rbits: int,
    gbits: int,
    bbits: int,
    palette_size: int,
    rmul: int,
    gmul: int,
    bmul: int,
    gmask: int,
    bmask: int,
    alpha_threshold: int) {
    for y := 0; y < height; y += 1 {
        for x := 0; x < width; x += 1 {
            pixel_idx := y * pitch + x * 4
            p0 := int(raw_pixels[pixel_idx + 0])
            p1 := int(raw_pixels[pixel_idx + 1])
            p2 := int(raw_pixels[pixel_idx + 2])
            p3 := int(raw_pixels[pixel_idx + 3])

            if p3 < alpha_threshold {
                cooked[y * width + x] = u32(palette_size - 1)
                continue
            }

            dx := x & (GIF_DITHER_TILE_SIZE - 1)
            dy := y & (GIF_DITHER_TILE_SIZE - 1)
            k := gif_encode_dither_kernel_value(dx, dy)

            bq := (
                min(65535, p2 * bmul + (k >> u32(bbits))) >> u32(16 - rbits - gbits - bbits)
            ) & bmask
            gq := (min(65535, p1 * gmul + (k >> u32(gbits))) >> u32(16 - rbits - gbits)) & gmask
            rq := (min(65535, p0 * rmul + (k >> u32(rbits))) >> u32(16 - rbits))

            cooked[y * width + x] = u32(bq | gq | rq)
        }
    }
}

//   Mark palette indices observed in the cooked frame pixel buffer.
gif_encode_mark_used_palette_entries :: #force_inline proc(
    cooked: []u32,
    used: []u8,
    total_pixels: int) {
    for i := 0; i < total_pixels; i += 1 {
        used[int(cooked[i])] = 1
    }
}

//   Count non-transparent palette entries marked as used.
gif_encode_count_used_palette_entries :: #force_inline proc(used: []u8, palette_size: int) -> int {
    used_count := 0
    for i := 0; i < palette_size - 1; i += 1 {
        used_count += int(used[i])
    }
    return used_count
}

//   Choose the next frame quantization depth from quality and prior frame stats.
gif_encode_next_frame_depth :: #force_inline proc(
    quality_clamped: int,
    frames_submitted: int,
    prev_depth: int,
    prev_count: int) -> int {
    if frames_submitted <= 0 {
        return quality_clamped
    }

    return min(quality_clamped, prev_depth + GIF_FRAME_DEPTH_BIAS / max(1, prev_count))
}

//   Write GIF logical screen descriptor and Netscape looping extension.
gif_encode_write_logical_screen_and_netscape_ext :: proc(
    out: []u8,
    width: int,
    height: int) -> bool {
    if len(out) < GIF_HEADER_SIZE {
        return false
    }

    gif89a_header := [6]u8{'G', 'I', 'F', '8', '9', 'a'}
    for i := 0; i < len(gif89a_header); i += 1 {
        out[i] = gif89a_header[i]
    }

    if !gif_encode_write_u16le(out, 6, width) {
        return false
    }
    if !gif_encode_write_u16le(out, 8, height) {
        return false
    }

    out[10] = 0x70
    out[11] = 0x00
    out[12] = 0x00

    gif_netscape_app_ext := [19]u8{
        0x21, 0xFF, 0x0B, 'N', 'E', 'T', 'S', 'C', 'A', 'P',
        'E', '2', '.', '0', 0x03, 0x01, 0x00, 0x00, 0x00,
    }
    for i := 0; i < len(gif_netscape_app_ext); i += 1 {
        out[13 + i] = gif_netscape_app_ext[i]
    }

    return true
}

//   Attempt to cook one frame at a specific quantization depth.
//
// Notes:
//   - Produces palette usage counts used by depth backoff logic.
gif_encode_try_cook_depth :: proc(
    frame: ^GifEncodeFrame,
    raw_pixels: [^]u8,
    used: []u8,
    width: int,
    height: int,
    pitch: int,
    current_depth: int,
    alpha_threshold: int,
    use_bgra: bool) -> Gif_Encode_Cook_Attempt {
    rbits, gbits, bbits := gif_encode_depth_bits(current_depth, use_bgra)

    palette_size := (1 << u32(rbits + gbits + bbits)) + 1
    gif_encode_clear_used_entries(used, palette_size)

    rdiff := (1 << u32(8 - rbits)) - 1
    gdiff := (1 << u32(8 - gbits)) - 1
    bdiff := (1 << u32(8 - bbits)) - 1

    rmul := int((255.0 - f64(rdiff)) / 255.0 * 257.0)
    gmul := int((255.0 - f64(gdiff)) / 255.0 * 257.0)
    bmul := int((255.0 - f64(bdiff)) / 255.0 * 257.0)

    gmask := ((1 << u32(gbits)) - 1) << u32(rbits)
    bmask := ((1 << u32(bbits)) - 1) << u32(rbits + gbits)

    gif_encode_dither_and_quantize_pixels(
        frame.pixels,
        raw_pixels,
        width,
        height,
        pitch,
        rbits,
        gbits,
        bbits,
        palette_size,
        rmul,
        gmul,
        bmul,
        gmask,
        bmask,
        alpha_threshold,
    )

    total_pixels := width * height
    gif_encode_mark_used_palette_entries(frame.pixels, used, total_pixels)

    return Gif_Encode_Cook_Attempt{
        used_count = gif_encode_count_used_palette_entries(used, palette_size),
        depth = current_depth,
        r_bits = rbits,
        g_bits = gbits,
        b_bits = bbits,
    }
}

//   Cook one frame by reducing depth until palette usage fits GIF limits.
gif_encode_cook_frame :: proc(
    frame: ^GifEncodeFrame,
    raw_pixels: [^]u8,
    used: []u8,
    width: int,
    height: int,
    pitch: int,
    use_bgra: bool,
    alpha_threshold: int,
    depth: int) {
    current_depth := depth

    for {
        attempt := gif_encode_try_cook_depth(
            frame,
            raw_pixels,
            used,
            width,
            height,
            pitch,
            current_depth,
            alpha_threshold,
            use_bgra,
        )

        if !(attempt.used_count >= 256 && current_depth > 1) {
            frame.depth = attempt.depth
            frame.count = attempt.used_count
            frame.r_bits = attempt.r_bits
            frame.g_bits = attempt.g_bits
            frame.b_bits = attempt.b_bits
            frame.is_cooked = true
            return
        }

        current_depth -= 1
    }
}

//   Initialize LZW output bitstream state and emit initial clear code.
gif_encode_begin_lzw_bitstream :: proc(
    state: ^Gif_Encode_State,
    table_size: int,
    bs: ^Gif_Encode_Bitstream_State) -> bool {
    bitstream_capacity := state.width * state.height * 2 + 4096
    buf := make([]u8, bitstream_capacity)
    if len(buf) == 0 {
        return false
    }

    lzw := Gif_Lzw_State{}
    gif_encode_lzw_reset(state.lzw_mem, &lzw, table_size, GIF_LZW_STRIDE)

    bs^ = Gif_Encode_Bitstream_State{
        buffer = buf,
        stream_length = 0,
        bit_accum = 0,
        bit_count = 0,
        clear_code = table_size,
        end_code = table_size + 1,
    }

    clear_width := gif_encode_bit_log(lzw.length - 1)
    if !gif_encode_write_code_bits(
        bs.buffer,
        &bs.stream_length,
        &bs.bit_accum,
        &bs.bit_count,
        bs.clear_code,
        clear_width,
    ) {
        delete(bs.buffer)
        return false
    }

    return true
}

//   Walk cooked frame pixels and emit LZW codes into the bitstream.
//
// Notes:
//   - Can reuse previous-frame matches when frames are marked compatible.
gif_encode_lzw_walk_pixels :: proc(
    state: ^Gif_Encode_State,
    frame: GifEncodeFrame,
    table_size: int,
    frames_compatible: bool,
    bs: ^Gif_Encode_Bitstream_State) -> bool {
    lzw_mem := state.lzw_mem
    lzw := Gif_Lzw_State{}
    gif_encode_lzw_reset(lzw_mem, &lzw, table_size, GIF_LZW_STRIDE)

    tlb := state.tlb_mem
    prev := state.previous_frame

    first_color := int(tlb[int(frame.pixels[0])])
    if frames_compatible && frame.pixels[0] == prev.pixels[0] {
        first_color = 0
    }
    if first_color < 0 || first_color >= lzw.stride {
        return false
    }
    last_code := first_color

    pixel_count := state.width * state.height
    for i := 1; i < pixel_count; i += 1 {
        color := int(tlb[int(frame.pixels[i])])
        if frames_compatible && frame.pixels[i] == prev.pixels[i] {
            color = 0
        }

        if color < 0 || color >= lzw.stride {
            return false
        }
        if last_code < 0 || last_code >= GIF_LZW_TABLE_CAPACITY {
            return false
        }

        entry_idx := last_code * lzw.stride + color
        if entry_idx < 0 || entry_idx >= len(lzw_mem) {
            return false
        }
        code := int(lzw_mem[entry_idx])

        if code < 0 {
            code_bits := gif_encode_bit_log(lzw.length - 1)
            if !gif_encode_write_code_bits(
                bs.buffer,
                &bs.stream_length,
                &bs.bit_accum,
                &bs.bit_count,
                last_code,
                code_bits,
            ) {
                return false
            }

            if lzw.length > (GIF_LZW_TABLE_CAPACITY - 1) {
                if !gif_encode_write_code_bits(
                    bs.buffer,
                    &bs.stream_length,
                    &bs.bit_accum,
                    &bs.bit_count,
                    bs.clear_code,
                    code_bits,
                ) {
                    return false
                }
                gif_encode_lzw_reset(lzw_mem, &lzw, table_size, GIF_LZW_STRIDE)
            } else {
                lzw_mem[entry_idx] = i16(lzw.length)
                lzw.length += 1
            }

            last_code = color
        } else {
            last_code = code
        }
    }

    last_width := min(12, gif_encode_bit_log(lzw.length - 1))
    if !gif_encode_write_code_bits(
        bs.buffer,
        &bs.stream_length,
        &bs.bit_accum,
        &bs.bit_count,
        last_code,
        last_width,
    ) {
        return false
    }

    end_width := min(12, gif_encode_bit_log(lzw.length))
    if !gif_encode_write_code_bits(
        bs.buffer,
        &bs.stream_length,
        &bs.bit_accum,
        &bs.bit_count,
        bs.end_code,
        end_width,
    ) {
        return false
    }

    return gif_encode_flush_code_bits(bs.buffer, &bs.stream_length, &bs.bit_accum, &bs.bit_count)
}

//   Build local color table and lookup mapping for a cooked frame.
gif_encode_build_palette_table :: proc(
    state: ^Gif_Encode_State,
    frame: GifEncodeFrame,
    table: ^[256]Gif_Rgb,
    out: ^Gif_Encode_Palette_Build) -> bool {
    total_bits := frame.r_bits + frame.g_bits + frame.b_bits
    tlb_size := (1 << u32(total_bits)) + 1
    if tlb_size <= 0 || tlb_size > len(state.tlb_mem) {
        return false
    }

    tlb := state.tlb_mem
    used := state.used_mem

    table_idx := 1
    tlb[tlb_size - 1] = 0

    for i := 0; i < tlb_size - 1; i += 1 {
        if used[i] == 0 {
            continue
        }

        tlb[i] = u8(table_idx)

        rmask := (1 << u32(frame.r_bits)) - 1
        gmask := (1 << u32(frame.g_bits)) - 1

        r := i & rmask
        g := (i >> u32(frame.r_bits)) & gmask
        b := i >> u32(frame.r_bits + frame.g_bits)

        r <<= u32(8 - frame.r_bits)
        g <<= u32(8 - frame.g_bits)
        b <<= u32(8 - frame.b_bits)

        rr := 
            u8(r | (r >> u32(frame.r_bits)) | (r >> u32(frame.r_bits * 2)) | (r >> u32(frame.r_bits * 3)))
        gg :=
            u8(g | (g >> u32(frame.g_bits)) | (g >> u32(frame.g_bits * 2)) | (g >> u32(frame.g_bits * 3)))
        bb :=
            u8(b | (b >> u32(frame.b_bits)) | (b >> u32(frame.b_bits * 2)) | (b >> u32(frame.b_bits * 3)))

        if state.use_bgra {
            table^[table_idx] = Gif_Rgb{R = bb, G = gg, B = rr}
        } else {
            table^[table_idx] = Gif_Rgb{R = rr, G = gg, B = bb}
        }

        table_idx += 1
    }

    out.tlb_size = tlb_size
    out.table_idx = table_idx
    out.has_transparent_pixels = used[tlb_size - 1] != 0
    return true
}

//   Encode cooked frame pixels into a raw LZW bitstream buffer.
gif_encode_lzw_to_bitstream :: proc(
    state: ^Gif_Encode_State,
    frame: GifEncodeFrame,
    table_size: int,
    frames_compatible: bool,
    bitstream: ^[]u8,
    stream_len: ^int) -> bool {
    writer := Gif_Encode_Bitstream_State{}
    if !gif_encode_begin_lzw_bitstream(state, table_size, &writer) {
        return false
    }

    ok := gif_encode_lzw_walk_pixels(state, frame, table_size, frames_compatible, &writer)
    if !ok {
        delete(writer.buffer)
        return false
    }

    bitstream^ = writer.buffer
    stream_len^ = writer.stream_length
    return true
}

//   Write GIF graphics control extension for one frame chunk.
gif_encode_write_graphics_control_extension :: proc(
    state: ^Gif_Encode_State,
    out: []u8,
    w: ^int,
    has_transparent_pixels: bool,
    centiseconds: int) -> bool {
    out[w^ + 0] = GIF_GCE_INTRODUCER
    out[w^ + 1] = GIF_GCE_LABEL
    out[w^ + 2] = GIF_GCE_BLOCK_SIZE
    out[w^ + 3] = GIF_GCE_PACKED_DISPOSE_BACKGROUND_NO_TRANSPARENCY
    if !gif_encode_write_u16le(out, w^ + 4, centiseconds) {
        return false
    }
    out[w^ + 6] = GIF_GCE_TRANSPARENT_INDEX_DEFAULT
    out[w^ + 7] = GIF_GCE_BLOCK_TERMINATOR
    if has_transparent_pixels && state.frames_submitted > 0 && state.list_tail != nil {
        state.list_tail.data[3] = GIF_GCE_PACKED_DISPOSE_BACKGROUND_TRANSPARENCY
    }
    w^ += 8
    return true
}

//   Write GIF image descriptor for one frame chunk.
gif_encode_write_image_descriptor :: proc(
    state: ^Gif_Encode_State,
    out: []u8,
    w: ^int,
    table_bits: int) -> bool {
    out[w^ + 0] = GIF_IMAGE_SEPARATOR
    if !gif_encode_write_u16le(out, w^ + 1, 0) ||
       !gif_encode_write_u16le(out, w^ + 3, 0) ||
       !gif_encode_write_u16le(out, w^ + 5, state.width) ||
       !gif_encode_write_u16le(out, w^ + 7, state.height) {
        return false
    }
    out[w^ + 9] = GIF_IMAGE_LOCAL_COLOR_TABLE_FLAG | u8(table_bits - 1)
    w^ += 10
    return true
}

//   Write local color table bytes into the frame output buffer.
gif_encode_write_local_color_table :: proc(
    out: []u8,
    w: ^int,
    table: [256]Gif_Rgb,
    table_size: int) {
    for i := 0; i < table_size; i += 1 {
        out[w^ + i * 3 + 0] = table[i].R
        out[w^ + i * 3 + 1] = table[i].G
        out[w^ + i * 3 + 2] = table[i].B
    }
    w^ += table_size * 3
}

//   Write LZW image data as GIF sub-blocks into the frame output buffer.
gif_encode_write_image_data_blocks :: proc(
    out: []u8,
    w: ^int,
    bitstream: []u8,
    stream_len: int,
    table_bits: int) {
    out[w^] = u8(table_bits)
    w^ += 1

    src := 0
    for src < stream_len {
        n := min(255, stream_len - src)
        out[w^] = u8(n)
        w^ += 1
        mem.copy(rawptr(&out[w^]), rawptr(&bitstream[src]), n)
        w^ += n
        src += n
    }

    out[w^] = 0
    w^ += 1
}

//   Assemble one encoded frame chunk from palette and compressed bitstream data.
gif_encode_build_frame_chunk :: proc(
    state: ^Gif_Encode_State,
    table: [256]Gif_Rgb,
    table_size: int,
    table_bits: int,
    has_transparent_pixels: bool,
    bitstream: []u8,
    stream_len: int,
    centiseconds: int) -> (^Gif_Encode_Buffer, bool) {
    local_table_bytes := table_size * 3
    sub_blocks := (stream_len + 254) / 255
    frame_chunk_size :=
        8 +
        10 +
        local_table_bytes +
        1 +
        (stream_len + sub_blocks) +
        1

    node, ok := gif_encode_new_buffer(frame_chunk_size)
    if !ok || node == nil {
        return nil, false
    }

    out := node.data
    w := 0

    if !gif_encode_write_graphics_control_extension(
        state,
        out,
        &w,
        has_transparent_pixels,
        centiseconds,
    ) {
        gif_encode_free_buffer(node)
        return nil, false
    }

    if !gif_encode_write_image_descriptor(state, out, &w, table_bits) {
        gif_encode_free_buffer(node)
        return nil, false
    }

    gif_encode_write_local_color_table(out, &w, table, table_size)
    gif_encode_write_image_data_blocks(out, &w, bitstream, stream_len, table_bits)

    node.size = w
    return node, true
}

//   Compress one cooked frame into a linked-list output buffer node.
gif_encode_compress_frame :: proc(
    state: ^Gif_Encode_State,
    frame: GifEncodeFrame,
    centiseconds: int) -> (^Gif_Encode_Buffer, bool) {
    if !frame.is_cooked {
        return nil, false
    }

    table := [256]Gif_Rgb{}
    palette := Gif_Encode_Palette_Build{}
    if !gif_encode_build_palette_table(state, frame, &table, &palette) {
        return nil, false
    }

    table_bits := max(2, gif_encode_bit_log(palette.table_idx - 1))
    table_size := 1 << u32(table_bits)

    prev := state.previous_frame
    has_same_pal :=
        frame.r_bits == prev.r_bits && frame.g_bits == prev.g_bits && frame.b_bits == prev.b_bits
    frames_compatible := has_same_pal && !palette.has_transparent_pixels && state.frames_submitted > 0

    bitstream: []u8 = nil
    stream_len := 0
    if !gif_encode_lzw_to_bitstream(
        state,
        frame,
        table_size,
        frames_compatible,
        &bitstream,
        &stream_len,
    ) {
        return nil, false
    }
    defer delete(bitstream)

    node, ok := gif_encode_build_frame_chunk(
        state,
        table,
        table_size,
        table_bits,
        palette.has_transparent_pixels,
        bitstream,
        stream_len,
        centiseconds,
    )
    if !ok || node == nil {
        return nil, false
    }

    return node, true
}
