package font

import "../../core"

import "core:c"

foreign import harfbuzz "system:harfbuzz"

// Opaque HarfBuzz font-data storage referenced by a face.
Harfbuzz_Blob :: struct {}

// Opaque HarfBuzz view of one font face within a blob.
Harfbuzz_Face :: struct {}

// Opaque HarfBuzz shaping font configured with OpenType behavior and pixel scale.
Harfbuzz_Font :: struct {}

// Opaque reusable HarfBuzz input and shaped-output buffer.
Harfbuzz_Buffer :: struct {}

// HarfBuzz policy controlling whether a blob copies or borrows source bytes.
Harfbuzz_Memory_Mode :: enum c.int {
    Duplicate = 0,
    Readonly = 1,
    Writable = 2,
    Readonly_May_Make_Writable = 3,
}

// ABI-compatible OpenType feature selection over a source byte interval.
Harfbuzz_Feature :: struct {
    tag: u32,
    value: u32,
    start: u32,
    end: u32,
}

// ABI-compatible HarfBuzz glyph identity and source-cluster record.
Harfbuzz_Glyph_Info :: struct {
    codepoint: u32,
    mask: u32,
    cluster: u32,
    private_a: u32,
    private_b: u32,
}

// ABI-compatible HarfBuzz glyph advances and offsets in configured font units.
Harfbuzz_Glyph_Position :: struct {
    x_advance: i32,
    y_advance: i32,
    x_offset: i32,
    y_offset: i32,
    private: i32,
}

Shaped_Glyph :: core.Shaped_Glyph
Font_Shaping_Resource :: core.Font_Shaping_Resource

foreign harfbuzz {
    hb_blob_create :: proc(
        data: rawptr, length: u32, mode: Harfbuzz_Memory_Mode,
        user_data, destroy: rawptr) -> ^Harfbuzz_Blob ---
    hb_blob_destroy :: proc(blob: ^Harfbuzz_Blob) ---
    hb_face_create :: proc(blob: ^Harfbuzz_Blob, index: u32) -> ^Harfbuzz_Face ---
    hb_face_destroy :: proc(face: ^Harfbuzz_Face) ---
    hb_face_get_glyph_count :: proc(face: ^Harfbuzz_Face) -> u32 ---
    hb_font_create :: proc(face: ^Harfbuzz_Face) -> ^Harfbuzz_Font ---
    hb_font_destroy :: proc(font: ^Harfbuzz_Font) ---
    hb_font_set_scale :: proc(font: ^Harfbuzz_Font, x_scale, y_scale: i32) ---
    hb_ot_font_set_funcs :: proc(font: ^Harfbuzz_Font) ---
    hb_buffer_create :: proc() -> ^Harfbuzz_Buffer ---
    hb_buffer_destroy :: proc(buffer: ^Harfbuzz_Buffer) ---
    hb_buffer_pre_allocate :: proc(buffer: ^Harfbuzz_Buffer, size: u32) -> c.int ---
    hb_buffer_clear_contents :: proc(buffer: ^Harfbuzz_Buffer) ---
    hb_buffer_add_utf8 :: proc(
        buffer: ^Harfbuzz_Buffer, text: cstring, text_length: c.int,
        item_offset: u32, item_length: c.int) ---
    hb_buffer_guess_segment_properties :: proc(buffer: ^Harfbuzz_Buffer) ---
    hb_buffer_get_length :: proc(buffer: ^Harfbuzz_Buffer) -> u32 ---
    hb_buffer_get_glyph_infos :: proc(
        buffer: ^Harfbuzz_Buffer, length: ^u32) -> [^]Harfbuzz_Glyph_Info ---
    hb_buffer_get_glyph_positions :: proc(
        buffer: ^Harfbuzz_Buffer,
        length: ^u32) -> [^]Harfbuzz_Glyph_Position ---
    hb_shape :: proc(
        font: ^Harfbuzz_Font, buffer: ^Harfbuzz_Buffer,
        features: [^]Harfbuzz_Feature, feature_count: u32) ---
}

//   Pack four ASCII bytes into HarfBuzz's canonical OpenType tag order.
//
// Parameters:
//   - a, b, c, d: Tag bytes ordered from most to least significant.
//
// Returns:
//   - One 32-bit OpenType tag suitable for `Harfbuzz_Feature.tag`.
harfbuzz_tag :: proc(a, b, c, d: u8) -> u32 {
    return u32(a) << 24 | u32(b) << 16 | u32(c) << 8 | u32(d)
}

//   Release every native handle owned by one shaper in reverse acquisition order.
//
// Parameters:
//   - shaper: Native shaping state to release; nil and zero values are accepted.
//
// Side effects:
//   - Releases the buffer, font, face, and blob references owned by `shaper`.
//   - Clears the complete destination so repeated destruction is safe.
//
// Notes:
//   - Releases the blob's duplicated source bytes.
harfbuzz_shaper_destroy :: proc(shaper: ^Font_Shaping_Resource) {
    if shaper == nil {
        return
    }
    if shaper.buffer != nil {
        hb_buffer_destroy(cast(^Harfbuzz_Buffer)shaper.buffer)
    }
    if shaper.font != nil {
        hb_font_destroy(cast(^Harfbuzz_Font)shaper.font)
    }
    if shaper.face != nil {
        hb_face_destroy(cast(^Harfbuzz_Face)shaper.face)
    }
    if shaper.blob != nil {
        hb_blob_destroy(cast(^Harfbuzz_Blob)shaper.blob)
    }
    shaper^ = {}
}

//   Configure font behavior and acquire the reusable shaping buffer.
harfbuzz_shaper_finish_init :: proc(
    shaper: ^Font_Shaping_Resource, pixel_size: i32) -> bool {

    hb_ot_font_set_funcs(cast(^Harfbuzz_Font)shaper.font)
    hb_font_set_scale(
        cast(^Harfbuzz_Font)shaper.font, pixel_size*64, pixel_size*64)
    shaper.buffer = hb_buffer_create()
    if shaper.buffer == nil || hb_buffer_pre_allocate(
        cast(^Harfbuzz_Buffer)shaper.buffer,
        u32(core.FONT_SHAPED_GLYPH_CAPACITY)) == 0 {
        harfbuzz_shaper_destroy(shaper)
        return false
    }
    return true
}

//   Acquire one reusable shaper for a single immutable font face.
//
// Parameters:
//   - source: Nonempty font bytes copied during this call.
//   - pixel_size: Positive raster source height; converted to HarfBuzz 26.6 units.
//   - shaper: Destination replaced with initialized native ownership on success.
//
// Returns:
//   - True when all native handles and OpenType font behavior are initialized.
//   - False for invalid input, a malformed face, or any native acquisition failure.
//
// Side effects:
//   - Clears `shaper` before acquisition and rolls back partial ownership on failure.
//
// Notes:
//   - The blob duplicates `source`; caller storage may be released after this call.
harfbuzz_shaper_init :: proc(
    source: []u8, pixel_size: i32, shaper: ^Font_Shaping_Resource) -> bool {

    if shaper == nil || len(source) == 0 || len(source) > int(max(u32)) ||
        pixel_size <= 0 || pixel_size > max(i32)/64 {
        return false
    }
    shaper^ = {}
    shaper.blob = hb_blob_create(
        raw_data(source), u32(len(source)), .Duplicate, nil, nil)
    if shaper.blob == nil {
        return false
    }
    shaper.face = hb_face_create(cast(^Harfbuzz_Blob)shaper.blob, 0)
    if shaper.face == nil ||
        hb_face_get_glyph_count(cast(^Harfbuzz_Face)shaper.face) == 0 {
        harfbuzz_shaper_destroy(shaper)
        return false
    }
    shaper.font = hb_font_create(cast(^Harfbuzz_Face)shaper.face)
    if shaper.font == nil {
        harfbuzz_shaper_destroy(shaper)
        return false
    }
    return harfbuzz_shaper_finish_init(shaper, pixel_size)
}

//   Copy one completed native shape result into caller-owned bounded storage.
//
// Parameters:
//   - buffer: HarfBuzz buffer containing glyph information and positions.
//   - output: Caller-owned destination whose capacity bounds the copied glyph count.
//
// Returns:
//   - Copied glyph count and true when all records fit and native arrays agree.
//   - Zero and false for empty, oversized, missing, or inconsistent native results.
//
// Side effects:
//   - Overwrites only the returned prefix of `output`; retains no destination pointer.
harfbuzz_copy_result :: proc(
    buffer: ^Harfbuzz_Buffer, output: []Shaped_Glyph) -> (int, bool) {

    glyph_count := hb_buffer_get_length(buffer)
    if glyph_count == 0 || int(glyph_count) > len(output) {
        return 0, false
    }
    info_count, position_count := glyph_count, glyph_count
    infos := hb_buffer_get_glyph_infos(buffer, &info_count)
    positions := hb_buffer_get_glyph_positions(buffer, &position_count)
    if infos == nil || positions == nil || info_count != glyph_count ||
       position_count != glyph_count {
        return 0, false
    }
    for index in 0..<int(glyph_count) {
        output[index] = {
            glyph_id = infos[index].codepoint,
            cluster = infos[index].cluster,
            x_advance = positions[index].x_advance,
            y_advance = positions[index].y_advance,
            x_offset = positions[index].x_offset,
            y_offset = positions[index].y_offset,
        }
    }
    return int(glyph_count), true
}

//   Shape borrowed UTF-8 into bounded presentation glyphs using JuliaMono `calt`.
//
// Parameters:
//   - shaper: Initialized native state whose buffer is reused by this call.
//   - text: Nonempty UTF-8 borrowed only for the duration of the native shape call.
//   - calt_enabled: Enables or disables contextual alternates for the complete input.
//   - output: Caller-owned shaped-glyph storage bounding native result publication.
//
// Returns:
//   - Shaped glyph count and true when the complete result fits in `output`.
//   - Zero and false for invalid state/input or an unusable native result.
//
// Side effects:
//   - Clears and repopulates the reusable HarfBuzz buffer owned by `shaper`.
//
// Notes:
//   - Glyph positions are signed 26.6 values at the pixel scale selected during init.
//   - Source bytes and semantic terminal cells are never modified.
harfbuzz_shape :: proc(
    shaper: ^Font_Shaping_Resource, text: string, calt_enabled: bool,
    output: []Shaped_Glyph) -> (int, bool) {

    if shaper == nil || len(text) == 0 || len(text) > int(max(c.int)) ||
        len(output) == 0 {
        return 0, false
    }
    if shaper.font == nil || shaper.buffer == nil {
        return 0, false
    }
    buffer := cast(^Harfbuzz_Buffer)shaper.buffer
    hb_buffer_clear_contents(buffer)
    hb_buffer_add_utf8(
        buffer, cstring(raw_data(text)), c.int(len(text)), 0, -1)
    hb_buffer_guess_segment_properties(buffer)
    feature := Harfbuzz_Feature{
        tag = harfbuzz_tag('c', 'a', 'l', 't'),
        value = 1 if calt_enabled else 0,
        end = max(u32),
    }
    hb_shape(cast(^Harfbuzz_Font)shaper.font, buffer, &feature, 1)
    return harfbuzz_copy_result(buffer, output)
}