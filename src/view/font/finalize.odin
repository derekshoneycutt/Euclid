package font

// Font_Texture_Finalize_Request identifies one upload and optional completion owner.
Font_Texture_Finalize_Request :: struct {
    identity: u64,
    generation: u64,
    completion: Font_Texture_Completion_Handler,
    completion_data: rawptr,
}

// prepared_is_valid checks one complete CPU atlas before native publication.
prepared_is_valid :: proc(prepared: ^Prepared_Font) -> bool {
    if prepared == nil || prepared.base_size <= 0 || prepared.glyph_count <= 0 ||
        prepared.atlas_width <= 0 || prepared.atlas_height <= 0 {
        return false
    }
    glyph_count := int(prepared.glyph_count)
    pixel_count := int(prepared.atlas_width * prepared.atlas_height * 2)
    if len(prepared.glyphs) != glyph_count ||
        len(prepared.rectangles) != glyph_count ||
        len(prepared.atlas_pixels) != pixel_count {
        return false
    }
    if prepared.complete_face {
        for glyph, index in prepared.glyphs {
            if glyph.glyph_id != u32(index) {return false}
        }
    }
    return true
}

// finalize_texture creates and uploads one immutable-size atlas transactionally.
finalize_texture :: proc(
    prepared: ^Prepared_Font, operations: Font_Texture_Operations,
    request: Font_Texture_Finalize_Request) -> (Font_Texture, bool) {
    if !prepared_is_valid(prepared) || operations.create == nil ||
        operations.upload == nil || operations.release == nil ||
        request.generation == 0 {
        return {}, false
    }
    texture := operations.create(operations.user_data,
        u32(prepared.atlas_width), u32(prepared.atlas_height))
    if texture.handle == nil || texture.width != u32(prepared.atlas_width) ||
        texture.height != u32(prepared.atlas_height) ||
        !operations.upload(operations.user_data, {
            texture = texture,
            pixels = prepared.atlas_pixels,
            identity = request.identity,
            generation = request.generation,
            completion = request.completion,
            completion_data = request.completion_data,
        }) {
        if texture.handle != nil {operations.release(operations.user_data, texture)}
        return {}, false
    }
    return texture, true
}

// prepared_face binds validated portable metrics to one uploaded atlas.
prepared_face :: proc(
    prepared: ^Prepared_Font, texture: Font_Texture) -> (Font_Face, bool) {
    if !prepared_is_valid(prepared) || texture.handle == nil {return {}, false}
    space_advance: i32
    for glyph in prepared.glyphs {
        if glyph.value == ' ' {
            space_advance = glyph.advance_x
            break
        }
    }
    if space_advance <= 0 {
        return {}, false
    }
    return {
        base_size = prepared.base_size,
        glyph_count = prepared.glyph_count,
        glyph_padding = prepared.padding,
        space_advance = space_advance,
        texture = texture,
    }, true
}

// finalize_face uploads one seed atlas and returns its portable face metrics.
finalize_face :: proc(
    prepared: ^Prepared_Font, operations: Font_Texture_Operations,
    identity, generation: u64) -> (Font_Face, bool) {
    texture, uploaded := finalize_texture(
        prepared, operations, {identity = identity, generation = generation})
    if !uploaded {return {}, false}
    face, valid := prepared_face(prepared, texture)
    if !valid {operations.release(operations.user_data, texture)}
    return face, valid
}