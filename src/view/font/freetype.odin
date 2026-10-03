package font

import freetype "../../../libs/freetype/bindings"
import fontmodel "model"

import "core:mem"
import "core:os"

FONT_FREETYPE_NATIVE_MEMORY_LIMIT_BYTES :: 64 * 1024 * 1024

Font_Freetype_Face :: struct {
    source: []u8,
    handle: ^freetype.Freetype_Face,
    info: freetype.Freetype_Info,
    pixel_size: i32,
    scale: f32,
    raster_ascent: f32,
}

Font_Freetype_Size_Result :: struct {
    scale: f32,
    raster_ascent: f32,
    ready: bool,
}

Font_Freetype_Bitmap :: freetype.Freetype_Bitmap

// Read one font source and release it on failure when individually allocated.
font_freetype_source_read :: proc(
    path: string, allocator: mem.Allocator,
    allocation_mode: Prepared_Font_Allocation_Mode) -> ([]u8, bool) {
    source, read_error := os.read_entire_file(path, allocator)
    if read_error == nil && len(source) > 0 {
        return source, true
    }
    if source != nil && allocation_mode == .Individual {
        delete(source, allocator)
    }
    return nil, false
}

// Release partial native acquisition before its borrowed source storage.
font_freetype_face_release_partial :: proc(
    source: []u8, handle: ^freetype.Freetype_Face,
    allocator: mem.Allocator,
    allocation_mode: Prepared_Font_Allocation_Mode) {
    when ODIN_OS == .Linux {
        if handle != nil {
            freetype.euclid_ft_close(handle)
        }
    }
    if allocation_mode == .Individual {
        delete(source, allocator)
    }
}

// Set the rounded 26.6 EM size while retaining the exact historical float scale.
font_freetype_face_configure :: proc(
    handle: ^freetype.Freetype_Face, info: freetype.Freetype_Info,
    pixel_size: i32) -> Font_Freetype_Size_Result {
    when ODIN_OS == .Linux {
        denominator := i64(info.hhea_ascender) - i64(info.hhea_descender)
        if info.glyph_count == 0 || info.units_per_em == 0 || denominator <= 0 {
            return {}
        }
        size_numerator := u64(info.units_per_em) * u64(pixel_size) * 64
        em_size_26_6 := (size_numerator + u64(denominator)/2) / u64(denominator)
        if em_size_26_6 == 0 || em_size_26_6 > u64(max(u32)) ||
            freetype.euclid_ft_set_em_size_26_6(handle, u32(em_size_26_6)) != .Ok {
            return {}
        }
        scale := f32(pixel_size) / f32(denominator)
        return {
            scale = scale,
            raster_ascent = f32(info.hhea_ascender) * scale,
            ready = true,
        }
    } else {
        return {}
    }
}

// Acquire, normalize, and publish one Linux face over caller-owned source bytes.
font_freetype_face_open_linux :: proc(
    source: []u8, pixel_size: i32,
    output: ^Font_Freetype_Face) -> bool {
    handle: ^freetype.Freetype_Face
    info: freetype.Freetype_Info
    status := freetype.euclid_ft_open(&source[0], u64(len(source)),
        FONT_FREETYPE_NATIVE_MEMORY_LIMIT_BYTES, &handle, &info)
    if status != .Ok {
        return false
    }
    size := font_freetype_face_configure(handle, info, pixel_size)
    if !size.ready {
        freetype.euclid_ft_close(handle)
        return false
    }
    output^ = {
        source = source,
        handle = handle,
        info = info,
        pixel_size = pixel_size,
        scale = size.scale,
        raster_ascent = size.raster_ascent,
    }
    return true
}

// Open one source with an operation-owned FreeType face and normalized size.
font_freetype_face_open :: proc(
    path: string, pixel_size: i32, allocator: mem.Allocator,
    allocation_mode: Prepared_Font_Allocation_Mode,
    output: ^Font_Freetype_Face) -> bool {

    if output == nil || len(path) == 0 || pixel_size <= 0 ||
        pixel_size > fontmodel.FONT_RASTER_MAX_PIXEL_HEIGHT {
        return false
    }
    output^ = {}
    source, source_ready := font_freetype_source_read(path, allocator, allocation_mode)
    if !source_ready {
        return false
    }
    when ODIN_OS == .Linux {
        if font_freetype_face_open_linux(source, pixel_size, output) {
            return true
        }
    }
    if allocation_mode == .Individual {
        delete(source, allocator)
    }
    return false
}

// Close the native face before releasing the source bytes it borrows.
font_freetype_face_close :: proc(
    face: ^Font_Freetype_Face, allocator: mem.Allocator,
    allocation_mode: Prepared_Font_Allocation_Mode) {

    if face == nil {
        return
    }
    font_freetype_face_release_partial(
        face.source, face.handle, allocator, allocation_mode)
    face^ = {}
}

// Resolve one Unicode codepoint through the admitted FreeType cmap.
font_freetype_glyph_index :: proc(
    face: ^Font_Freetype_Face, codepoint: rune) -> (u32, bool) {
    when ODIN_OS == .Linux {
        if face == nil || face.handle == nil || codepoint < 0 {
            return 0, false
        }
        glyph_id: u32
        status := freetype.euclid_ft_glyph_index(
            face.handle, u32(codepoint), &glyph_id)
        return glyph_id, status == .Ok
    } else {
        return 0, false
    }
}

// Read one glyph's unscaled horizontal advance in font units.
font_freetype_glyph_advance :: proc(
    face: ^Font_Freetype_Face, glyph_id: u32) -> (i32, bool) {
    when ODIN_OS == .Linux {
        if face == nil || face.handle == nil {
            return 0, false
        }
        advance, bearing: i32
        status := freetype.euclid_ft_glyph_metrics(
            face.handle, glyph_id, &advance, &bearing)
        return advance, status == .Ok
    } else {
        return 0, false
    }
}

// Render one glyph using the candidate's unhinted grayscale policy.
font_freetype_render_glyph :: proc(
    face: ^Font_Freetype_Face, glyph_id: u32) -> (Font_Freetype_Bitmap, bool) {
    when ODIN_OS == .Linux {
        if face == nil || face.handle == nil {
            return {}, false
        }
        bitmap: freetype.Freetype_Bitmap
        status := freetype.euclid_ft_render_gray(
            face.handle, glyph_id, .Unhinted, &bitmap)
        return bitmap, status == .Ok && bitmap.pixel_mode == 1
    } else {
        return {}, false
    }
}