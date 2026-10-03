package font

import fontmodel "model"

import "core:mem"

// Empty pixels reserved around each glyph during row packing.
FONT_GLYPH_PADDING :: i32(4)

// Opaque white marker dimensions written into the atlas bottom-right corner.
FONT_ATLAS_CORNER_SIZE :: 3

// Caller-owned cancellation query used at bounded font-preparation checkpoints.
Font_Prepare_Cancel_Proc :: #type proc(user_data: rawptr) -> bool

// Optional cooperative cancellation capability borrowed for one preparation call.
Font_Prepare_Cancellation :: struct {
    user_data: rawptr,
    requested: Font_Prepare_Cancel_Proc,
}

// Result of cancellable glyph layout before atlas allocation.
Font_Prepare_Layout_Result :: struct {
    width: i32,
    height: i32,
    ready: bool,
}

// Immutable CPU preparation request; path/codepoints are borrowed for the call/task lifetime.
Font_Prepare_Request :: struct {
    key: Font_Key,
    generation: u64,
    path: string,
    pixel_size: i32,
    codepoints: []rune,
    complete_face: bool,
    cancellation: Font_Prepare_Cancellation,
}

// Immutable subset request whose glyph IDs are borrowed for the preparation call.
Font_Glyph_Page_Request :: struct {
    key: Font_Key,
    generation: u64,
    path: string,
    pixel_size: i32,
    glyph_ids: []u32,
    cancellation: Font_Prepare_Cancellation,
}

Prepared_Font_Allocation_Mode :: fontmodel.Prepared_Font_Allocation_Mode
Prepared_Glyph :: fontmodel.Prepared_Glyph
Prepared_Rectangle :: fontmodel.Prepared_Rectangle
Prepared_Font :: fontmodel.Prepared_Font

//   Query an optional caller-owned cancellation capability.
prepare_cancellation_requested :: proc(
    cancellation: Font_Prepare_Cancellation) -> bool {
    return cancellation.requested != nil &&
        cancellation.requested(cancellation.user_data)
}

//   Release every allocation owned by a prepared CPU font result.
//
// Side effects:
//   - Individually deletes slices in `.Individual` mode; arena mode only clears the
//     record because the owning arena performs bulk reclamation.
prepare_destroy :: proc(prepared: ^Prepared_Font) {
    if prepared == nil {
        return
    }
    if prepared.allocation_mode == .Individual {
        delete(prepared.atlas_pixels, prepared.allocator)
        delete(prepared.glyphs, prepared.allocator)
        delete(prepared.rectangles, prepared.allocator)
    }
    prepared^ = {}
}

//   Lay out prepared glyphs and commit stable result metadata.
prepare_commit_layout :: proc(
    request: Font_Prepare_Request, prepared: ^Prepared_Font) -> bool {
    layout := prepare_layout(
        prepared.glyphs, request.pixel_size, prepared.rectangles,
        request.cancellation)
    if !layout.ready {
        return false
    }
    prepared.key = request.key
    prepared.generation = request.generation
    prepared.base_size = request.pixel_size
    prepared.glyph_count = i32(len(prepared.glyphs))
    prepared.padding = FONT_GLYPH_PADDING
    prepared.atlas_width = layout.width
    prepared.atlas_height = layout.height
    return true
}

//   Count mapped glyphs and allocate their parallel metadata slices.
prepare_allocate_glyph_metadata :: proc(
    face: ^Font_Freetype_Face, request: Font_Prepare_Request,
    prepared: ^Prepared_Font, allocator: mem.Allocator) -> bool {
    if prepare_cancellation_requested(request.cancellation) {
        return false
    }
    glyph_count := int(face.info.glyph_count) if request.complete_face else
        prepare_count_glyphs(face, request.codepoints)
    return glyph_count > 0 &&
        glyph_count <= fontmodel.FONT_RASTER_GLYPH_RECORD_CAPACITY &&
        prepare_allocate_metadata(prepared, glyph_count, allocator)
}

//   Populate one opened FreeType face into prepared CPU atlas ownership.
prepare_populate :: proc(
    face: ^Font_Freetype_Face, request: Font_Prepare_Request,
    prepared: ^Prepared_Font, allocator: mem.Allocator) -> bool {

    if !prepare_allocate_glyph_metadata(face, request, prepared, allocator) {
        prepare_destroy(prepared)
        return false
    }
    prepared.face_glyph_count = i32(face.info.glyph_count)
    prepared.raster_ascent = face.raster_ascent
    metrics_ready := prepare_complete_glyph_metrics(
        face, request, prepared.glyphs) if request.complete_face else
        prepare_glyph_metrics(face, request, prepared.glyphs)
    if !metrics_ready {
        prepare_destroy(prepared)
        return false
    }
    if !prepare_commit_layout(request, prepared) {
        prepare_destroy(prepared)
        return false
    }
    if !prepare_allocate_atlas(prepared, allocator) {
        return false
    }
    if !prepare_render_atlas(face, prepared, request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    return true
}

//   Prepare one FreeType-backed font without native GPU calls.
//
// Parameters:
//   - request: Valid borrowed source path, positive size, and nonempty codepoint policy.
//   - prepared: Destination reset to owned result state before allocation begins.
//   - allocator: Allocation source retained in the result.
//   - allocation_mode: Slice cleanup policy matching the allocator's lifetime.
//
// Returns:
//   - True for a complete CPU font; false after rollback/clear where required.
//
// Notes:
//   - This worker-safe path performs file I/O and rasterization but no GPU calls.
prepare :: proc(
    request: Font_Prepare_Request, prepared: ^Prepared_Font,
    allocator: mem.Allocator,
    allocation_mode := Prepared_Font_Allocation_Mode.Individual) -> bool {

    if prepared == nil || request.pixel_size <= 0 ||
        (!request.complete_face && len(request.codepoints) == 0) {
        return false
    }
    prepared^ = {
        allocator = allocator,
        allocation_mode = allocation_mode,
        complete_face = request.complete_face,
    }
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    face: Font_Freetype_Face
    if !font_freetype_face_open(
        request.path, request.pixel_size, allocator, allocation_mode, &face) {
        return false
    }
    defer font_freetype_face_close(&face, allocator, allocation_mode)
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    return prepare_populate(&face, request, prepared, allocator)
}

//   Report whether one page request contains unique in-range glyph IDs.
//
// Returns:
//   - True for a nonempty bounded set of unique in-range glyph IDs.
prepare_glyph_page_request_is_valid :: proc(
    face: ^Font_Freetype_Face, glyph_ids: []u32) -> bool {

    if face == nil || face.handle == nil || len(glyph_ids) == 0 ||
        len(glyph_ids) > FONT_GLYPH_PAGE_REQUEST_CAPACITY {
        return false
    }
    for glyph_id, index in glyph_ids {
        if glyph_id >= face.info.glyph_count {
            return false
        }
        for previous in glyph_ids[:index] {
            if previous == glyph_id {
                return false
            }
        }
    }
    return true
}

//   Populate compact page-local metrics while preserving original face glyph IDs.
prepare_glyph_page_metrics :: proc(
    face: ^Font_Freetype_Face,
    glyph_ids: []u32, glyphs: []Prepared_Glyph,
    cancellation: Font_Prepare_Cancellation) -> bool {

    for glyph_id, index in glyph_ids {
        if prepare_cancellation_requested(cancellation) {
            return false
        }
        glyph, valid := prepare_face_glyph_metric(face, glyph_id)
        if !valid {
            return false
        }
        glyphs[index] = glyph
    }
    return true
}

//   Allocate, lay out, and rasterize one validated glyph page.
prepare_glyph_page_populate :: proc(
    face: ^Font_Freetype_Face, request: Font_Glyph_Page_Request,
    prepared: ^Prepared_Font, allocator: mem.Allocator) -> bool {

    if !prepare_glyph_page_request_is_valid(face, request.glyph_ids) ||
        !prepare_allocate_metadata(prepared, len(request.glyph_ids), allocator) {
        prepare_destroy(prepared)
        return false
    }
    prepared.face_glyph_count = i32(face.info.glyph_count)
    prepared.raster_ascent = face.raster_ascent
    if !prepare_glyph_page_metrics(
        face, request.glyph_ids, prepared.glyphs,
        request.cancellation) || !prepare_commit_layout({
        key = request.key,
        generation = request.generation,
        pixel_size = request.pixel_size,
        cancellation = request.cancellation,
    }, prepared) {
        prepare_destroy(prepared)
        return false
    }
    if !prepare_allocate_atlas(prepared, allocator) {
        return false
    }
    if !prepare_render_atlas(face, prepared, request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    return true
}

//   Parse, rasterize, and pack one bounded glyph-ID subset without GPU calls.
//
// Returns:
//   - True for a complete compact CPU page; false after owned-result rollback.
prepare_glyph_page :: proc(
    request: Font_Glyph_Page_Request, prepared: ^Prepared_Font,
    allocator: mem.Allocator,
    allocation_mode := Prepared_Font_Allocation_Mode.Individual) -> bool {

    if prepared == nil || request.pixel_size <= 0 || len(request.path) == 0 {
        return false
    }
    prepared^ = {
        allocator = allocator,
        allocation_mode = allocation_mode,
    }
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    face: Font_Freetype_Face
    if !font_freetype_face_open(
        request.path, request.pixel_size, allocator, allocation_mode, &face) {
        return false
    }
    defer font_freetype_face_close(&face, allocator, allocation_mode)
    if prepare_cancellation_requested(request.cancellation) {
        prepare_destroy(prepared)
        return false
    }
    return prepare_glyph_page_populate(&face, request, prepared, allocator)
}

//   Allocate prepared metadata while preserving individual-allocation rollback.
//
// Returns:
//   - True after equal-length glyph and rectangle slices are owned by `prepared`.
prepare_allocate_metadata :: proc(
    prepared: ^Prepared_Font, glyph_count: int,
    allocator: mem.Allocator) -> bool {

    glyphs, glyphs_error := make([]Prepared_Glyph, glyph_count, allocator)
    if glyphs_error != nil {
        return false
    }
    prepared.glyphs = glyphs
    rectangles, rectangles_error := make(
        []Prepared_Rectangle, glyph_count, allocator)
    if rectangles_error != nil {
        prepare_destroy(prepared)
        return false
    }
    prepared.rectangles = rectangles
    return true
}

//   Allocate the prepared atlas while preserving individual-allocation rollback.
//
// Returns:
//   - True after allocating exactly `width * height * 2` zeroed bytes.
prepare_allocate_atlas :: proc(
    prepared: ^Prepared_Font, allocator: mem.Allocator) -> bool {

    atlas_size := int(prepared.atlas_width*prepared.atlas_height*2)
    atlas_pixels, atlas_error := make([]u8, atlas_size, allocator)
    if atlas_error != nil {
        prepare_destroy(prepared)
        return false
    }
    prepared.atlas_pixels = atlas_pixels
    return true
}

//   Count requested codepoints represented by real glyphs in the font.
//
// Returns:
//   - Number of codepoints whose FreeType glyph index is greater than zero.
prepare_count_glyphs :: proc(
    face: ^Font_Freetype_Face, codepoints: []rune) -> int {

    result := 0
    for codepoint in codepoints {
        glyph_id, mapped := font_freetype_glyph_index(face, codepoint)
        if !mapped {
            return -1
        }
        if glyph_id > 0 {
            result += 1
        }
    }
    return result
}

//   Derive metrics and synthesized space bitmap dimensions.
//
// Returns:
//   - True when every pre-counted real glyph receives one output record.
prepare_glyph_metrics :: proc(
    face: ^Font_Freetype_Face, request: Font_Prepare_Request,
    glyphs: []Prepared_Glyph) -> bool {

    glyph_index := 0
    for codepoint in request.codepoints {
        if prepare_cancellation_requested(request.cancellation) {
            return false
        }
        glyph_id, mapped := font_freetype_glyph_index(face, codepoint)
        if !mapped {
            return false
        }
        if glyph_id == 0 {
            continue
        }
        glyph, valid := prepare_glyph_metric(face, codepoint, glyph_id)
        if !valid {
            return false
        }
        glyphs[glyph_index] = glyph
        glyph_index += 1
    }
    return glyph_index == len(glyphs)
}

//   Populate metrics for every face glyph ID, including missing glyph ID zero.
prepare_complete_glyph_metrics :: proc(
    face: ^Font_Freetype_Face, request: Font_Prepare_Request,
    glyphs: []Prepared_Glyph) -> bool {

    if len(glyphs) != int(face.info.glyph_count) {
        return false
    }
    for &glyph, glyph_index in glyphs {
        if prepare_cancellation_requested(request.cancellation) {
            return false
        }
        candidate, valid := prepare_face_glyph_metric(face, u32(glyph_index))
        if !valid {
            return false
        }
        glyph = candidate
    }
    for codepoint in request.codepoints {
        if prepare_cancellation_requested(request.cancellation) {
            return false
        }
        glyph_id, mapped := font_freetype_glyph_index(face, codepoint)
        if !mapped {
            return false
        }
        if glyph_id > 0 {
            glyphs[int(glyph_id)].value = codepoint
        }
    }
    return true
}

//   Calculate one face glyph's compatible advance, offsets, and bitmap bounds.
prepare_face_glyph_metric :: proc(
    face: ^Font_Freetype_Face, glyph_id: u32) -> (Prepared_Glyph, bool) {

    advance, metrics_ready := font_freetype_glyph_advance(face, glyph_id)
    if !metrics_ready {
        return {}, false
    }
    bitmap, rendered := font_freetype_render_glyph(face, glyph_id)
    if !rendered {
        return {}, false
    }
    result := Prepared_Glyph{
        value = rune(-1 - i32(glyph_id)),
        glyph_id = glyph_id,
        bitmap_width = i32(bitmap.width),
        bitmap_height = i32(bitmap.rows),
    }
    if result.bitmap_width > 0 && result.bitmap_height > 0 {
        result.offset_x = bitmap.bitmap_left
        result.offset_y = i32(face.raster_ascent) - bitmap.bitmap_top
    }
    result.advance_x = i32(f32(advance) * face.scale)
    return result, true
}

//   Calculate one glyph's cache-compatible offsets, advance, and bitmap bounds.
//
// Notes:
//   - ASCII and ideographic spaces synthesize empty full-height rectangles using
//     horizontal advance; nonempty glyph offsets are adjusted by scaled ascent.
//
// Returns:
//   - Complete CPU metrics for the requested represented codepoint.
prepare_glyph_metric :: proc(
    face: ^Font_Freetype_Face, codepoint: rune,
    glyph_id: u32) -> (Prepared_Glyph, bool) {

    advance, metrics_ready := font_freetype_glyph_advance(face, glyph_id)
    if !metrics_ready {
        return {}, false
    }
    result := Prepared_Glyph{
        value = codepoint,
        glyph_id = glyph_id,
    }
    if codepoint == ' ' || codepoint == rune(0x3000) {
        result.advance_x = i32(f32(advance) * face.scale)
        result.bitmap_width = result.advance_x
        result.bitmap_height = face.pixel_size
        return result, true
    }
    bitmap, rendered := font_freetype_render_glyph(face, glyph_id)
    if !rendered {
        return {}, false
    }
    result.offset_x = bitmap.bitmap_left
    result.bitmap_width = i32(bitmap.width)
    result.bitmap_height = i32(bitmap.rows)
    if result.bitmap_width > 0 && result.bitmap_height > 0 {
        result.advance_x = i32(f32(advance) * face.scale)
        result.offset_y = i32(face.raster_ascent) - bitmap.bitmap_top
    }
    return result, true
}

//   Estimate power-of-two atlas dimensions from prepared glyph area.
prepare_initial_atlas_size :: proc(
    glyphs: []Prepared_Glyph,
    pixel_size: i32) -> (i32, i32) {
    total_area := f32(0)
    minimum_width := i32(1)
    for glyph in glyphs {
        padded_width := glyph.bitmap_width + 2*FONT_GLYPH_PADDING
        padded_height := max(glyph.bitmap_height, pixel_size) +
            2*FONT_GLYPH_PADDING
        total_area += f32(padded_width*padded_height)
        minimum_width = max(minimum_width, padded_width)
    }
    atlas_width := i32(1)
    for atlas_width < minimum_width ||
        f32(atlas_width*atlas_width) < total_area*1.2 {
        atlas_width *= 2
    }
    atlas_height := atlas_width
    if total_area < f32(atlas_width*atlas_width/2) {
        atlas_height /= 2
    }
    return atlas_width, atlas_height
}

//   Apply the cache's row-packing and atlas-growth policy.
//
// Parameters:
//   - glyphs: Prepared metrics to place in order.
//   - pixel_size: Positive base font height used for row spacing.
//   - rectangles: Output parallel to glyphs.
//
// Returns:
//   - Power-of-two atlas width and dynamically doubled height containing every glyph.
prepare_layout :: proc(
    glyphs: []Prepared_Glyph, pixel_size: i32,
    rectangles: []Prepared_Rectangle,
    cancellation: Font_Prepare_Cancellation = {}) -> Font_Prepare_Layout_Result {

    atlas_width, atlas_height := prepare_initial_atlas_size(glyphs, pixel_size)
    offset_x := FONT_GLYPH_PADDING
    offset_y := FONT_GLYPH_PADDING
    row_height := i32(0)
    for glyph, index in glyphs {
        if prepare_cancellation_requested(cancellation) {
            return {}
        }
        if offset_x > FONT_GLYPH_PADDING &&
            offset_x+glyph.bitmap_width+FONT_GLYPH_PADDING > atlas_width {
            offset_x = FONT_GLYPH_PADDING
            offset_y += row_height + 2*FONT_GLYPH_PADDING
            row_height = 0
        }
        for offset_y+glyph.bitmap_height+FONT_GLYPH_PADDING > atlas_height {
            atlas_height *= 2
        }
        rectangles[index] = {
            x = offset_x,
            y = offset_y,
            width = glyph.bitmap_width,
            height = glyph.bitmap_height,
        }
        row_height = max(row_height, glyph.bitmap_height)
        offset_x += glyph.bitmap_width + 2*FONT_GLYPH_PADDING
    }
    return {width = atlas_width, height = atlas_height, ready = true}
}

//   Initialize the atlas gray channel while observing cancellation once per row.
prepare_initialize_atlas :: proc(
    prepared: ^Prepared_Font,
    cancellation: Font_Prepare_Cancellation) -> bool {
    for row in 0..<int(prepared.atlas_height) {
        if prepare_cancellation_requested(cancellation) {
            return false
        }
        for column in 0..<int(prepared.atlas_width) {
            pixel_index := row*int(prepared.atlas_width) + column
            prepared.atlas_pixels[pixel_index*2] = 255
        }
    }
    return true
}

//   Rasterize each nonempty glyph while observing cancellation between glyphs.
prepare_render_glyphs :: proc(
    face: ^Font_Freetype_Face, prepared: ^Prepared_Font,
    cancellation: Font_Prepare_Cancellation) -> bool {
    for glyph, index in prepared.glyphs {
        if prepare_cancellation_requested(cancellation) {
            return false
        }
        if glyph.value == ' ' || glyph.value == rune(0x3000) ||
            glyph.bitmap_width == 0 || glyph.bitmap_height == 0 {
            continue
        }
        bitmap, rendered := font_freetype_render_glyph(face, glyph.glyph_id)
        if !rendered || !prepare_copy_freetype_bitmap(
            bitmap, prepared.rectangles[index], prepared) {
            return false
        }
    }
    return true
}

//   Mark the atlas validation corner after every glyph is complete.
prepare_mark_atlas_corner :: proc(prepared: ^Prepared_Font) {
    for corner_y in 0..<FONT_ATLAS_CORNER_SIZE {
        for corner_x in 0..<FONT_ATLAS_CORNER_SIZE {
            x := prepared.atlas_width - 1 - i32(corner_x)
            y := prepared.atlas_height - 1 - i32(corner_y)
            prepared.atlas_pixels[
                int((y*prepared.atlas_width + x)*2 + 1)] = 255
        }
    }
}

//   Rasterize glyph alpha into the atlas and add its white validation corner.
//
// Side effects:
//   - Sets every gray channel byte to 255, writes non-space FreeType coverage into
//     alpha, and marks the bottom-right corner opaque for downstream validation.
prepare_render_atlas :: proc(
    face: ^Font_Freetype_Face, prepared: ^Prepared_Font,
    cancellation: Font_Prepare_Cancellation = {}) -> bool {
    if !prepare_initialize_atlas(prepared, cancellation) ||
        !prepare_render_glyphs(face, prepared, cancellation) {
        return false
    }
    prepare_mark_atlas_corner(prepared)
    return true
}

//   Copy one borrowed grayscale FreeType bitmap into the atlas alpha channel.
//
// Side effects:
//   - Copies only pixels whose rectangle-derived destination lies inside atlas bounds.
prepare_copy_freetype_bitmap :: proc(
    bitmap: Font_Freetype_Bitmap, rectangle: Prepared_Rectangle,
    prepared: ^Prepared_Font) -> bool {

    if bitmap.width != u32(rectangle.width) ||
        bitmap.rows != u32(rectangle.height) || bitmap.pixels == nil {
        return false
    }
    pitch := i64(bitmap.pitch)
    if pitch < 0 {
        pitch = -pitch
    }
    if pitch < i64(bitmap.width) ||
        u64(pitch) * u64(bitmap.rows) > bitmap.byte_length {
        return false
    }
    for row in 0..<int(bitmap.rows) {
        source_row := row
        if bitmap.pitch < 0 {
            source_row = int(bitmap.rows) - row - 1
        }
        for column in 0..<int(bitmap.width) {
            destination_x := rectangle.x + i32(column)
            destination_y := rectangle.y + i32(row)
            if destination_x >= 0 && destination_x < prepared.atlas_width &&
                destination_y >= 0 && destination_y < prepared.atlas_height {
                source_index := source_row*int(pitch) + column
                destination_index :=
                    (destination_y*prepared.atlas_width + destination_x)*2 + 1
                prepared.atlas_pixels[int(destination_index)] =
                    bitmap.pixels[source_index]
            }
        }
    }
    return true
}
