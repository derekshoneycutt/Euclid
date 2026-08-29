package font

import rl "vendor:raylib"

// Pair of raylib-owned metadata arrays transferred into one finalized font.
Font_Finalized_Metadata :: struct {
    glyphs: [^]rl.GlyphInfo,
    rectangles: [^]rl.Rectangle,
}

//   Upload one prepared glyph page without allocating raylib font metadata.
//
// Returns:
//   - A valid immutable texture and true, or zero and false after rollback.
finalize_glyph_page :: proc(
    prepared: ^Prepared_Font) -> (rl.Texture2D, bool) {

    if prepared == nil || !prepared_is_valid(prepared) ||
        prepared.complete_face {
        return {}, false
    }
    image := rl.Image{
        data = raw_data(prepared.atlas_pixels),
        width = prepared.atlas_width,
        height = prepared.atlas_height,
        mipmaps = 1,
        format = .UNCOMPRESSED_GRAY_ALPHA,
    }
    texture := rl.LoadTextureFromImage(image)
    if !rl.IsTextureValid(texture) ||
        texture.width != prepared.atlas_width ||
        texture.height != prepared.atlas_height ||
        texture.format != rl.PixelFormat.UNCOMPRESSED_GRAY_ALPHA {
        if rl.IsTextureValid(texture) {
            rl.UnloadTexture(texture)
        }
        return {}, false
    }
    return texture, true
}

//   Build and validate one display-owned raylib font from prepared CPU data.
//
// Parameters:
//   - prepared: Complete CPU result consumed only after successful finalization.
//   - font: Destination assigned only after the candidate passes all validation.
//
// Returns:
//   - True after metadata/texture ownership transfers to `font`; false after rolling
//     back partial GPU/raylib resources while leaving prepared ownership with caller.
//
// Notes:
//   - Must run on the display thread with a live raylib graphics context.
finalize :: proc(prepared: ^Prepared_Font, font: ^rl.Font) -> bool {
    if prepared == nil || font == nil || !prepared_is_valid(prepared) {
        return false
    }

    metadata, metadata_valid := finalized_metadata_create(prepared)
    if !metadata_valid {
        return false
    }

    atlas := rl.Image{
        data = raw_data(prepared.atlas_pixels),
        width = prepared.atlas_width,
        height = prepared.atlas_height,
        mipmaps = 1,
        format = .UNCOMPRESSED_GRAY_ALPHA,
    }
    candidate := rl.Font{
        baseSize = prepared.base_size,
        glyphCount = prepared.glyph_count,
        glyphPadding = prepared.padding,
        texture = rl.LoadTextureFromImage(atlas),
        recs = metadata.rectangles,
        glyphs = metadata.glyphs,
    }
    if !finalized_is_valid(candidate, prepared) {
        finalized_destroy(candidate)
        return false
    }

    font^ = candidate
    prepare_destroy(prepared)
    return true
}

//   Allocate and populate raylib-owned glyph and rectangle metadata.
//
// Returns:
//   - Two arrays compatible with `rl.UnloadFont` and true, or empty/false after freeing
//     either partial allocation.
finalized_metadata_create :: proc(
    prepared: ^Prepared_Font) -> (Font_Finalized_Metadata, bool) {

    result := Font_Finalized_Metadata{
        glyphs = cast([^]rl.GlyphInfo)rl.MemAlloc(
            u32(prepared.glyph_count)*u32(size_of(rl.GlyphInfo))),
        rectangles = cast([^]rl.Rectangle)rl.MemAlloc(
            u32(prepared.glyph_count)*u32(size_of(rl.Rectangle))),
    }
    if result.glyphs == nil || result.rectangles == nil {
        if result.glyphs != nil {
            rl.MemFree(result.glyphs)
        }
        if result.rectangles != nil {
            rl.MemFree(result.rectangles)
        }
        return {}, false
    }
    for index in 0..<int(prepared.glyph_count) {
        glyph := prepared.glyphs[index]
        result.glyphs[index] = {
            value = glyph.value,
            offsetX = glyph.offset_x,
            offsetY = glyph.offset_y,
            advanceX = glyph.advance_x,
        }
        rectangle := prepared.rectangles[index]
        result.rectangles[index] = {
            x = f32(rectangle.x),
            y = f32(rectangle.y),
            width = f32(rectangle.width),
            height = f32(rectangle.height),
        }
    }
    return result, true
}

//   Check that a prepared result is internally complete before GPU upload.
//
// Returns:
//   - True for positive dimensions/count and exact glyph, rectangle, and RG-byte lengths.
prepared_is_valid :: proc(prepared: ^Prepared_Font) -> bool {
    if prepared.base_size <= 0 || prepared.glyph_count <= 0 ||
        prepared.atlas_width <= 0 || prepared.atlas_height <= 0 {
        return false
    }
    glyph_count := int(prepared.glyph_count)
    pixel_count := int(prepared.atlas_width*prepared.atlas_height*2)
    if len(prepared.glyphs) != glyph_count ||
        len(prepared.rectangles) != glyph_count ||
        len(prepared.atlas_pixels) != pixel_count {
        return false
    }
    if prepared.complete_face {
        for glyph, index in prepared.glyphs {
            if glyph.glyph_id != u32(index) {
                return false
            }
        }
    }
    return true
}

//   Validate uploaded texture dimensions and copied raylib metadata.
//
// Returns:
//   - True when raylib resource validity, gray-alpha texture shape, and every metadata
//     field exactly match the prepared source.
finalized_is_valid :: proc(
    font: rl.Font, prepared: ^Prepared_Font) -> bool {

    if !rl.IsFontValid(font) || !rl.IsTextureValid(font.texture) ||
        font.texture.width != prepared.atlas_width ||
        font.texture.height != prepared.atlas_height ||
        font.texture.format != rl.PixelFormat.UNCOMPRESSED_GRAY_ALPHA {
        return false
    }
    for index in 0..<int(prepared.glyph_count) {
        glyph := prepared.glyphs[index]
        rectangle := prepared.rectangles[index]
        if font.glyphs[index].value != glyph.value ||
            font.glyphs[index].offsetX != glyph.offset_x ||
            font.glyphs[index].offsetY != glyph.offset_y ||
            font.glyphs[index].advanceX != glyph.advance_x ||
            font.recs[index].x != f32(rectangle.x) ||
            font.recs[index].y != f32(rectangle.y) ||
            font.recs[index].width != f32(rectangle.width) ||
            font.recs[index].height != f32(rectangle.height) {
            return false
        }
    }
    return true
}

//   Release a partially or fully built finalized font without publication.
//
// Side effects:
//   - Unloads a valid texture and frees non-nil raylib metadata pointers independently.
finalized_destroy :: proc(font: rl.Font) {
    if rl.IsTextureValid(font.texture) {
        rl.UnloadTexture(font.texture)
    }
    if font.glyphs != nil {
        rl.MemFree(font.glyphs)
    }
    if font.recs != nil {
        rl.MemFree(font.recs)
    }
}
