package gif

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

GifEncodeResult :: core.GifEncodeResult
GifEncodeFrame :: core.GifEncodeFrame
GifEncodeBuffer :: core.GifEncodeBuffer
GifEncodeState :: core.GifEncodeState

#assert((GIF_DITHER_TILE_SIZE & (GIF_DITHER_TILE_SIZE - 1)) == 0)


GifLzwState :: struct {
    Len: int,
    Stride: int,
}

GifRgb :: struct {
    R: u8,
    G: u8,
    B: u8,
}

GifEncodeCookAttempt :: struct {
    UsedCount: int,
    Depth: int,
    RBits: int,
    GBits: int,
    BBits: int,
}

GifEncodePaletteBuild :: struct {
    TlbSize: int,
    TableIdx: int,
    HasTransparentPixels: bool,
}

GifEncodeBitstreamState :: struct {
    Buffer: []u8,
    StreamLen: int,
    BitAccum: u64,
    BitCount: int,
    ClearCode: int,
    EndCode: int,
}

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

gif_encode_new_buffer :: proc(size: int) -> (^GifEncodeBuffer, bool) {
    n := new(GifEncodeBuffer)
    if n == nil {
        return nil, false
    }

    n.Data = make([]u8, size)
    if len(n.Data) != size {
        free(n)
        return nil, false
    }

    n.Size = size
    n.Next = nil
    return n, true
}

gif_encode_free_buffer :: proc(node: ^GifEncodeBuffer) {
    if node == nil {
        return
    }
    if len(node.Data) > 0 {
        delete(node.Data)
    }
    free(node)
}

gif_encode_push_buffer :: proc(state: ^GifEncodeState, node: ^GifEncodeBuffer) {
    if state.ListHead == nil {
        state.ListHead = node
        state.ListTail = node
        return
    }

    state.ListTail.Next = node
    state.ListTail = node
}

gif_encode_pop_head_buffer :: proc(state: ^GifEncodeState) -> ^GifEncodeBuffer {
    if state.ListHead == nil {
        return nil
    }

    n := state.ListHead
    state.ListHead = n.Next
    n.Next = nil

    if state.ListHead == nil {
        state.ListTail = nil
    }

    return n
}

gif_encode_free_state :: proc(state: ^GifEncodeState) {
    delete(state.PreviousFrame.Pixels)
    delete(state.CurrentFrame.Pixels)
    delete(state.LzwMem)
    delete(state.TlbMem)
    delete(state.UsedMem)

    n := state.ListHead
    for n != nil {
        next := n.Next
        gif_encode_free_buffer(n)
        n = next
    }

    state^ = {}
}

gif_encode_lzw_reset :: proc(lzw_mem: []i16, lzw: ^GifLzwState, table_size: int, stride: int) {
    for i := 0; i < len(lzw_mem); i += 1 {
        lzw_mem[i] = -1
    }
    lzw.Len = table_size + 2
    lzw.Stride = stride
}

gif_encode_write_code_bits :: proc(
    stream: []u8,
    stream_len: ^int,
    bit_accum: ^u64,
    bit_count: ^int,
    code: int,
    width: int,
) -> bool {
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

gif_encode_flush_code_bits :: proc(
    stream: []u8,
    stream_len: ^int,
    bit_accum: ^u64,
    bit_count: ^int,
) -> bool {
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

gif_encode_write_u16le :: #force_inline proc(dst: []u8, offset: int, value: int) -> bool {
    if offset < 0 || offset + 1 >= len(dst) {
        return false
    }
    dst[offset + 0] = u8(value & 0xFF)
    dst[offset + 1] = u8((value >> 8) & 0xFF)
    return true
}

gif_encode_depth_bits :: #force_inline proc(depth: int, use_bgra: bool) -> (int, int, int) {
    rdepths := [GIF_COLOR_DEPTH_TABLE_SIZE]int{0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5}
    gdepths := [GIF_COLOR_DEPTH_TABLE_SIZE]int{0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6}
    bdepths := [GIF_COLOR_DEPTH_TABLE_SIZE]int{0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5}

    if use_bgra {
        return bdepths[depth], gdepths[depth], rdepths[depth]
    }
    return rdepths[depth], gdepths[depth], bdepths[depth]
}

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

gif_encode_clear_used_entries :: #force_inline proc(used: []u8, palette_size: int) {
    for i := 0; i < palette_size; i += 1 {
        used[i] = 0
    }
}

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
    alpha_threshold: int,
) {
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

gif_encode_mark_used_palette_entries :: #force_inline proc(
    cooked: []u32,
    used: []u8,
    total_pixels: int,
) {
    for i := 0; i < total_pixels; i += 1 {
        used[int(cooked[i])] = 1
    }
}

gif_encode_count_used_palette_entries :: #force_inline proc(used: []u8, palette_size: int) -> int {
    used_count := 0
    for i := 0; i < palette_size - 1; i += 1 {
        used_count += int(used[i])
    }
    return used_count
}

gif_encode_next_frame_depth :: #force_inline proc(
    quality_clamped: int,
    frames_submitted: int,
    prev_depth: int,
    prev_count: int,
) -> int {
    if frames_submitted <= 0 {
        return quality_clamped
    }

    // Heuristic inherited from original encoder: fewer colors in the previous
    // frame permit a deeper search budget for the next frame.
    return min(quality_clamped, prev_depth + GIF_FRAME_DEPTH_BIAS / max(1, prev_count))
}

gif_encode_write_logical_screen_and_netscape_ext :: proc(
    out: []u8,
    width: int,
    height: int,
) -> bool {
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

gif_encode_try_cook_depth :: proc(
    frame: ^GifEncodeFrame,
    raw_pixels: [^]u8,
    used: []u8,
    width: int,
    height: int,
    pitch: int,
    current_depth: int,
    alpha_threshold: int,
    use_bgra: bool,
) -> GifEncodeCookAttempt {
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
        frame.Pixels,
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
    gif_encode_mark_used_palette_entries(frame.Pixels, used, total_pixels)

    return GifEncodeCookAttempt{
        UsedCount = gif_encode_count_used_palette_entries(used, palette_size),
        Depth = current_depth,
        RBits = rbits,
        GBits = gbits,
        BBits = bbits,
    }
}

gif_encode_cook_frame :: proc(
    frame: ^GifEncodeFrame,
    raw_pixels: [^]u8,
    used: []u8,
    width: int,
    height: int,
    pitch: int,
    use_bgra: bool,
    alpha_threshold: int,
    depth: int,
) {
    current_depth := depth

    // TODO SIMD: evaluate a future SIMD implementation here.
    // We intentionally keep only scalar cooking for now.

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

        if !(attempt.UsedCount >= 256 && current_depth > 1) {
            frame.Depth = attempt.Depth
            frame.Count = attempt.UsedCount
            frame.RBits = attempt.RBits
            frame.GBits = attempt.GBits
            frame.BBits = attempt.BBits
            frame.IsCooked = true
            return
        }

        current_depth -= 1
    }
}

gif_encode_begin_lzw_bitstream :: proc(
    state: ^GifEncodeState,
    table_size: int,
    bs: ^GifEncodeBitstreamState,
) -> bool {
    bitstream_capacity := state.Width * state.Height * 2 + 4096
    buf := make([]u8, bitstream_capacity)
    if len(buf) == 0 {
        return false
    }

    lzw := GifLzwState{}
    gif_encode_lzw_reset(state.LzwMem, &lzw, table_size, GIF_LZW_STRIDE)

    bs^ = GifEncodeBitstreamState{
        Buffer = buf,
        StreamLen = 0,
        BitAccum = 0,
        BitCount = 0,
        ClearCode = table_size,
        EndCode = table_size + 1,
    }

    clear_width := gif_encode_bit_log(lzw.Len - 1)
    if !gif_encode_write_code_bits(
        bs.Buffer,
        &bs.StreamLen,
        &bs.BitAccum,
        &bs.BitCount,
        bs.ClearCode,
        clear_width,
    ) {
        delete(bs.Buffer)
        return false
    }

    return true
}

gif_encode_lzw_walk_pixels :: proc(
    state: ^GifEncodeState,
    frame: GifEncodeFrame,
    table_size: int,
    frames_compatible: bool,
    bs: ^GifEncodeBitstreamState,
) -> bool {
    lzw_mem := state.LzwMem
    lzw := GifLzwState{}
    gif_encode_lzw_reset(lzw_mem, &lzw, table_size, GIF_LZW_STRIDE)

    tlb := state.TlbMem
    prev := state.PreviousFrame

    first_color := int(tlb[int(frame.Pixels[0])])
    if frames_compatible && frame.Pixels[0] == prev.Pixels[0] {
        first_color = 0
    }
    if first_color < 0 || first_color >= lzw.Stride {
        return false
    }
    last_code := first_color

    pixel_count := state.Width * state.Height
    for i := 1; i < pixel_count; i += 1 {
        color := int(tlb[int(frame.Pixels[i])])
        if frames_compatible && frame.Pixels[i] == prev.Pixels[i] {
            color = 0
        }

        if color < 0 || color >= lzw.Stride {
            return false
        }
        if last_code < 0 || last_code >= GIF_LZW_TABLE_CAPACITY {
            return false
        }

        entry_idx := last_code * lzw.Stride + color
        if entry_idx < 0 || entry_idx >= len(lzw_mem) {
            return false
        }
        code := int(lzw_mem[entry_idx])

        if code < 0 {
            code_bits := gif_encode_bit_log(lzw.Len - 1)
            if !gif_encode_write_code_bits(
                bs.Buffer,
                &bs.StreamLen,
                &bs.BitAccum,
                &bs.BitCount,
                last_code,
                code_bits,
            ) {
                return false
            }

            if lzw.Len > (GIF_LZW_TABLE_CAPACITY - 1) {
                if !gif_encode_write_code_bits(
                    bs.Buffer,
                    &bs.StreamLen,
                    &bs.BitAccum,
                    &bs.BitCount,
                    bs.ClearCode,
                    code_bits,
                ) {
                    return false
                }
                gif_encode_lzw_reset(lzw_mem, &lzw, table_size, GIF_LZW_STRIDE)
            } else {
                lzw_mem[entry_idx] = i16(lzw.Len)
                lzw.Len += 1
            }

            last_code = color
        } else {
            last_code = code
        }
    }

    last_width := min(12, gif_encode_bit_log(lzw.Len - 1))
    if !gif_encode_write_code_bits(
        bs.Buffer,
        &bs.StreamLen,
        &bs.BitAccum,
        &bs.BitCount,
        last_code,
        last_width,
    ) {
        return false
    }

    end_width := min(12, gif_encode_bit_log(lzw.Len))
    if !gif_encode_write_code_bits(
        bs.Buffer,
        &bs.StreamLen,
        &bs.BitAccum,
        &bs.BitCount,
        bs.EndCode,
        end_width,
    ) {
        return false
    }

    return gif_encode_flush_code_bits(bs.Buffer, &bs.StreamLen, &bs.BitAccum, &bs.BitCount)
}

gif_encode_build_palette_table :: proc(
    state: ^GifEncodeState,
    frame: GifEncodeFrame,
    table: ^[256]GifRgb,
    out: ^GifEncodePaletteBuild,
) -> bool {
    total_bits := frame.RBits + frame.GBits + frame.BBits
    tlb_size := (1 << u32(total_bits)) + 1
    if tlb_size <= 0 || tlb_size > len(state.TlbMem) {
        return false
    }

    tlb := state.TlbMem
    used := state.UsedMem

    table_idx := 1
    tlb[tlb_size - 1] = 0

    for i := 0; i < tlb_size - 1; i += 1 {
        if used[i] == 0 {
            continue
        }

        tlb[i] = u8(table_idx)

        rmask := (1 << u32(frame.RBits)) - 1
        gmask := (1 << u32(frame.GBits)) - 1

        r := i & rmask
        g := (i >> u32(frame.RBits)) & gmask
        b := i >> u32(frame.RBits + frame.GBits)

        r <<= u32(8 - frame.RBits)
        g <<= u32(8 - frame.GBits)
        b <<= u32(8 - frame.BBits)

        rr := u8(
            r | (r >> u32(frame.RBits)) | (r >> u32(frame.RBits * 2)) | (r >> u32(frame.RBits * 3))
        )
        gg := u8(
            g | (g >> u32(frame.GBits)) | (g >> u32(frame.GBits * 2)) | (g >> u32(frame.GBits * 3))
        )
        bb := u8(
            b | (b >> u32(frame.BBits)) | (b >> u32(frame.BBits * 2)) | (b >> u32(frame.BBits * 3))
        )

        if state.UseBGRA {
            table^[table_idx] = GifRgb{R = bb, G = gg, B = rr}
        } else {
            table^[table_idx] = GifRgb{R = rr, G = gg, B = bb}
        }

        table_idx += 1
    }

    out.TlbSize = tlb_size
    out.TableIdx = table_idx
    out.HasTransparentPixels = used[tlb_size - 1] != 0
    return true
}

gif_encode_lzw_to_bitstream :: proc(
    state: ^GifEncodeState,
    frame: GifEncodeFrame,
    table_size: int,
    frames_compatible: bool,
    bitstream: ^[]u8,
    stream_len: ^int,
) -> bool {
    writer := GifEncodeBitstreamState{}
    if !gif_encode_begin_lzw_bitstream(state, table_size, &writer) {
        return false
    }

    ok := gif_encode_lzw_walk_pixels(state, frame, table_size, frames_compatible, &writer)
    if !ok {
        delete(writer.Buffer)
        return false
    }

    bitstream^ = writer.Buffer
    stream_len^ = writer.StreamLen
    return true
}

gif_encode_write_graphics_control_extension :: proc(
    state: ^GifEncodeState,
    out: []u8,
    w: ^int,
    has_transparent_pixels: bool,
    centiseconds: int,
) -> bool {
    out[w^ + 0] = GIF_GCE_INTRODUCER
    out[w^ + 1] = GIF_GCE_LABEL
    out[w^ + 2] = GIF_GCE_BLOCK_SIZE
    out[w^ + 3] = GIF_GCE_PACKED_DISPOSE_BACKGROUND_NO_TRANSPARENCY
    if !gif_encode_write_u16le(out, w^ + 4, centiseconds) {
        return false
    }
    out[w^ + 6] = GIF_GCE_TRANSPARENT_INDEX_DEFAULT
    out[w^ + 7] = GIF_GCE_BLOCK_TERMINATOR
    if has_transparent_pixels && state.FramesSubmitted > 0 && state.ListTail != nil {
        state.ListTail.Data[3] = GIF_GCE_PACKED_DISPOSE_BACKGROUND_TRANSPARENCY
    }
    w^ += 8
    return true
}

gif_encode_write_image_descriptor :: proc(
    state: ^GifEncodeState,
    out: []u8,
    w: ^int,
    table_bits: int,
) -> bool {
    out[w^ + 0] = GIF_IMAGE_SEPARATOR
    if !gif_encode_write_u16le(out, w^ + 1, 0) ||
       !gif_encode_write_u16le(out, w^ + 3, 0) ||
       !gif_encode_write_u16le(out, w^ + 5, state.Width) ||
       !gif_encode_write_u16le(out, w^ + 7, state.Height) {
        return false
    }
    out[w^ + 9] = GIF_IMAGE_LOCAL_COLOR_TABLE_FLAG | u8(table_bits - 1)
    w^ += 10
    return true
}

gif_encode_write_local_color_table :: proc(
    out: []u8,
    w: ^int,
    table: [256]GifRgb,
    table_size: int,
) {
    for i := 0; i < table_size; i += 1 {
        out[w^ + i * 3 + 0] = table[i].R
        out[w^ + i * 3 + 1] = table[i].G
        out[w^ + i * 3 + 2] = table[i].B
    }
    w^ += table_size * 3
}

gif_encode_write_image_data_blocks :: proc(
    out: []u8,
    w: ^int,
    bitstream: []u8,
    stream_len: int,
    table_bits: int,
) {
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

gif_encode_build_frame_chunk :: proc(
    state: ^GifEncodeState,
    table: [256]GifRgb,
    table_size: int,
    table_bits: int,
    has_transparent_pixels: bool,
    bitstream: []u8,
    stream_len: int,
    centiseconds: int,
) -> (^GifEncodeBuffer, bool) {
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

    out := node.Data
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

    node.Size = w
    return node, true
}

gif_encode_compress_frame :: proc(
    state: ^GifEncodeState,
    frame: GifEncodeFrame,
    centiseconds: int,
) -> (^GifEncodeBuffer, bool) {
    if !frame.IsCooked {
        return nil, false
    }

    table := [256]GifRgb{}
    palette := GifEncodePaletteBuild{}
    if !gif_encode_build_palette_table(state, frame, &table, &palette) {
        return nil, false
    }

    table_bits := max(2, gif_encode_bit_log(palette.TableIdx - 1))
    table_size := 1 << u32(table_bits)

    prev := state.PreviousFrame
    has_same_pal :=
        frame.RBits == prev.RBits && frame.GBits == prev.GBits && frame.BBits == prev.BBits
    frames_compatible := has_same_pal && !palette.HasTransparentPixels && state.FramesSubmitted > 0

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
        palette.HasTransparentPixels,
        bitstream,
        stream_len,
        centiseconds,
    )
    if !ok || node == nil {
        return nil, false
    }

    return node, true
}

gif_encode_begin :: proc(state: ^GifEncodeState, width, height: int) -> bool {
    if width < 1 || height < 1 || width > 65535 || height > 65535 ||
       width >= GIF_MAX_PIXELS / height {
        state.ListHead = nil
        state.ListTail = nil
        return false
    }

    gif_encode_free_state(state)

    state.Width = width
    state.Height = height
    state.AlphaThreshold = 0
    state.UseBGRA = false
    state.FramesSubmitted = 0

    state.LzwMem = make([]i16, GIF_LZW_TABLE_CAPACITY * GIF_LZW_STRIDE)
    state.TlbMem = make([]u8, GIF_MAX_TABLE_BYTES)
    state.UsedMem = make([]u8, GIF_MAX_TABLE_BYTES)

    pixel_count := width * height
    state.PreviousFrame.Pixels = make([]u32, pixel_count)
    state.CurrentFrame.Pixels = make([]u32, pixel_count)

    if len(state.LzwMem) == 0 || len(state.TlbMem) == 0 || len(state.UsedMem) == 0 ||
       len(state.PreviousFrame.Pixels) == 0 || len(state.CurrentFrame.Pixels) == 0 {
        gif_encode_free_state(state)
        return false
    }

    header, ok := gif_encode_new_buffer(GIF_HEADER_SIZE)
    if !ok || header == nil {
        gif_encode_free_state(state)
        return false
    }

    out := header.Data
    if !gif_encode_write_logical_screen_and_netscape_ext(out, width, height) {
        gif_encode_free_buffer(header)
        gif_encode_free_state(state)
        return false
    }

    gif_encode_push_buffer(state, header)
    return true
}

gif_encode_frame :: proc(
    state: ^GifEncodeState,
    pixel_data: rawptr,
    centiseconds_per_frame: int,
    quality: int,
    pitch_in_bytes: int,
) -> bool {
    if state.ListHead == nil || pixel_data == nil {
        return false
    }

    quality_clamped := clamp(quality, 1, 16)

    pitch := pitch_in_bytes
    if pitch == 0 {
        pitch = state.Width * 4
    }

    base := uintptr(pixel_data)
    if pitch < 0 {
        base += uintptr((-pitch) * (state.Height - 1))
    }
    raw := transmute([^]u8)base

    next_depth := gif_encode_next_frame_depth(
        quality_clamped,
        state.FramesSubmitted,
        state.PreviousFrame.Depth,
        state.PreviousFrame.Count,
    )

    gif_encode_cook_frame(
        &state.CurrentFrame,
        raw,
        state.UsedMem,
        state.Width,
        state.Height,
        pitch,
        state.UseBGRA,
        state.AlphaThreshold,
        next_depth,
    )

    node, ok := gif_encode_compress_frame(state, state.CurrentFrame, centiseconds_per_frame)
    if !ok || node == nil {
        gif_encode_free_state(state)
        return false
    }

    gif_encode_push_buffer(state, node)

    tmp := state.PreviousFrame
    state.PreviousFrame = state.CurrentFrame
    state.CurrentFrame = tmp

    state.FramesSubmitted += 1
    return true
}

gif_encode_end :: proc(state: ^GifEncodeState) -> GifEncodeResult {
    if state.ListHead == nil {
        return GifEncodeResult{}
    }

    total := 1
    for n := state.ListHead; n != nil; n = n.Next {
        total += n.Size
    }

    out := make([]u8, total)
    if len(out) == 0 {
        gif_encode_free_state(state)
        return GifEncodeResult{}
    }

    w := 0
    for n := state.ListHead; n != nil; n = n.Next {
        mem.copy(rawptr(&out[w]), rawptr(&n.Data[0]), n.Size)
        w += n.Size
    }

    out[w] = GIF_TRAILER
    w += 1

    gif_encode_free_state(state)

    return GifEncodeResult{
        Data = out,
        DataSize = w,
    }
}

gif_encode_free :: proc(result: ^GifEncodeResult) {
    if result == nil {
        return
    }
    if len(result.Data) > 0 {
        delete(result.Data)
    }
    result^ = {}
}
