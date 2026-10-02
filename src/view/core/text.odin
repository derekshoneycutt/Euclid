package view_core

import dyncore "../../dynview/core"
import view_font "../font"
import native "../native"
import color "../../core/color"
import geometry "../../core/geometry"

import "core:math"

//   Draw environment for wrapped text content: the clipping panel, scroll
//   offset, font, and typography metrics, grouped so the draw call passes one
//   coherent value.
Wrapped_Text_Content_Params :: struct {
    encoder: ^native.Draw_Encoder,
    panel : geometry.Rectangle,
    scroll_y : f32,
    font : view_font.Font_Face,
    text_padding : f32,
    text_row_height : f32,
    text_color : color.Color_RGBA8,
    wrap_advance : f32,
    font_size : f32,
    font_cache : ^view_font.Font_Cache,
    font_key : view_font.Font_Key,
}


//   Font and size pair for UI text draw calls.
Ui_Text_Font :: struct {
    font : view_font.Font_Face,
    font_size : f32,
}

//   Complete inputs for one atomic shaped-or-unshaped text draw.
Shaped_Text_Draw :: struct {
    encoder: ^native.Draw_Encoder,
    resolver: view_font.Font_Resolver,
    key: view_font.Font_Key,
    text: string,
    position: geometry.Vector2,
    color: color.Color_RGBA8,
    font: Ui_Text_Font,
}

//   Complete inputs for one page-aware unshaped text draw.
Unshaped_Text_Draw :: struct {
    encoder: ^native.Draw_Encoder,
    resolver: view_font.Font_Resolver,
    key: view_font.Font_Key,
    text: string,
    position: geometry.Vector2,
    color: color.Color_RGBA8,
    font: Ui_Text_Font,
}

UI_TEXT_GLYPH_SELECTION_CAPACITY :: 4096

//   One immutable cached shaped run ready for proportional glyph drawing.
Cached_Shaped_Run_Draw :: struct {
    encoder: ^native.Draw_Encoder,
    resolver: view_font.Font_Resolver,
    key: view_font.Font_Key,
    glyphs: []view_font.Shaped_Glyph,
    position: geometry.Vector2,
    color: color.Color_RGBA8,
    font_size: f32,
    base_pixel_size: f32,
}

//   Immutable cached monospace run plus its source text and cell pitch.
Cached_Monospace_Run_Draw :: struct {
    shaped: Cached_Shaped_Run_Draw,
    text: string,
    column_advance: f32,
}

//   Pixel placement and next pen position for one cached shaped glyph.
Cached_Glyph_Placement :: struct {
    position: geometry.Vector2,
    next_pen_x: f32,
}

//   Complete inputs for one normalized resolved-glyph draw.
Resolved_Glyph_Draw :: struct {
    encoder: ^native.Draw_Encoder,
    resolved: view_font.Resolved_Glyph,
    position: geometry.Vector2,
    font_size: f32,
    color: color.Color_RGBA8,
    x_offset: i32,
    y_offset: i32,
}

//   Atlas and destination rectangles validated for one resolved glyph.
Resolved_Glyph_Quad :: struct {
    destination: geometry.Rectangle,
    uv: geometry.Rectangle,
    valid: bool,
}

//   Resolved codepoint draw data plus original residency and drawability state.
Codepoint_Resolution :: struct {
    glyph: view_font.Resolved_Glyph,
    status: view_font.Font_Glyph_Resolve_Status,
    drawable: bool,
}

//   Prepared raster and complete selection for one cached monospace run.
Cached_Monospace_Preflight :: struct {
    raster_request: view_font.Font_Raster_Request,
    selection: view_font.Font_Raster_Selection,
    ready: bool,
}

//   Prepared bounded glyph IDs and one complete raster for unshaped text.
Unshaped_Glyph_Preflight :: struct {
    glyph_count: int,
    all_resident: bool,
    selection: view_font.Font_Raster_Selection,
    ready: bool,
}

//   Validated shaped-run inputs ready for coherent glyph resolution.
Shaped_Run_Preflight :: struct {
    glyphs: []view_font.Shaped_Glyph,
    column_advance: f32,
    raster_request: view_font.Font_Raster_Request,
    selection: view_font.Font_Raster_Selection,
    reason: view_font.Shape_Fallback_Reason,
    ready: bool,
}

// Bind logical font size and actual encoder scale to the cache's face generation.
ui_text_raster_request :: proc(
    resolver: view_font.Font_Resolver, key: view_font.Font_Key,
    font_size: f32, encoder: ^native.Draw_Encoder) ->
    (view_font.Font_Raster_Request, bool) {

    if font_size <= 0 {
        return {}, false
    }
    scene_scale := f32(1)
    if encoder != nil && encoder.logical_extent.x > 0 &&
        encoder.logical_extent.y > 0 {
        scene_scale = max(
            f32(encoder.physical_extent[0])/encoder.logical_extent.x,
            f32(encoder.physical_extent[1])/encoder.logical_extent.y)
    }
    if resolver.request_raster == nil {
        return {key = key, logical_size = font_size,
            scene_pixels_per_logical_unit = scene_scale}, true
    }
    return resolver.request_raster(
        resolver.user_data, key, font_size, scene_scale)
}

//   Wrap a font with the default UI text size.
ui_text_font :: #force_inline proc(font: view_font.Font_Face) -> Ui_Text_Font {
    return Ui_Text_Font{font = font, font_size = TREE_FONT_SIZE}
}

//   Record one shaped-text fallback without retaining source content.
ui_text_shape_fallback :: proc(
    resolver: view_font.Font_Resolver, reason: view_font.Shape_Fallback_Reason) {

    if resolver.record_shape_fallback != nil {
        resolver.record_shape_fallback(resolver.user_data, reason)
    }
}

//   Report whether one byte offset begins a complete UTF-8 codepoint.
ui_text_cluster_is_valid :: proc(text: string, cluster: u32) -> bool {
    if int(cluster) >= len(text) {
        return false
    }
    bytes := transmute([]u8)text
    byte := bytes[int(cluster)]
    return byte & 0xc0 != 0x80
}

//   Map one valid UTF-8 byte cluster to its source codepoint column.
ui_text_cluster_column :: proc(text: string, cluster: u32) -> (int, bool) {
    if !ui_text_cluster_is_valid(text, cluster) {
        return 0, false
    }
    return dyncore.text_codepoint_count_span(text, 0, int(cluster)), true
}

//   Resolve Euclid's stb-scaled monospace column width from the finalized atlas.
ui_text_column_advance :: proc(
    atlas: view_font.Font_Face, font_size: f32) -> (f32, bool) {
    if atlas.space_advance <= 0 || atlas.base_size <= 0 {
        return 0, false
    }
    return f32(atlas.space_advance)*
        font_size/f32(atlas.base_size), true
}

// ui_text_measure_monospace returns one UTF-8 run width under fixed spacing.
ui_text_measure_monospace :: proc(
    text: string, atlas: view_font.Font_Face,
    font_size, spacing: f32) -> (f32, bool) {
    advance, valid := ui_text_column_advance(atlas, font_size)
    count := dyncore.text_codepoint_count_span(text, 0, len(text))
    if !valid || count < 0 {
       return 0, false
    }
    if count == 0 {
       return 0, true
    }
    return f32(count)*advance + f32(count - 1)*spacing, true
}

//   Validate a complete horizontal monospace shape result before drawing.
ui_text_shape_is_valid :: proc(
    text: string, glyphs: []view_font.Shaped_Glyph,
    glyph_count: int) -> bool {

    if glyph_count <= 0 || glyph_count > len(glyphs) {
        return false
    }
    codepoint_count := dyncore.text_codepoint_count_span(text, 0, len(text))
    if codepoint_count <= 0 {
        return false
    }
    total_advance := i64(0)
    for glyph in glyphs[:glyph_count] {
        if glyph.y_advance != 0 || glyph.x_advance <= 0 ||
            !ui_text_cluster_is_valid(text, glyph.cluster) {
            return false
        }
        total_advance += i64(glyph.x_advance)
    }
    return total_advance == i64(glyphs[0].x_advance)*i64(codepoint_count)
}

//   Draw one normalized resident glyph with optional HarfBuzz offsets.
ui_text_draw_resolved_glyph :: proc(draw: Resolved_Glyph_Draw) {
    quad := ui_text_resolved_glyph_quad(draw)
    if !quad.valid {
        return
    }
    resolved := draw.resolved
    _ = native.draw_encoder_texture_quad(draw.encoder,
        quad.destination, quad.uv, draw.color,
        {texture = resolved.texture.handle, sampler = .Linear})
}

// Build the destination and atlas coordinates for a normalized resident glyph.
ui_text_resolved_glyph_quad :: proc(draw: Resolved_Glyph_Draw) -> Resolved_Glyph_Quad {

    resolved := draw.resolved
    if draw.encoder == nil || resolved.texture.handle == nil ||
        resolved.texture.width == 0 || resolved.texture.height == 0 {
        return {}
    }
    destination, valid := ui_text_resolved_glyph_destination(draw)
    if !valid {
        return {}
    }
    texture_width := f32(resolved.texture.width)
    texture_height := f32(resolved.texture.height)
    return {
        destination = destination,
        uv = {
            resolved.source.x/texture_width,
            resolved.source.y/texture_height,
            resolved.source.width/texture_width,
            resolved.source.height/texture_height,
        },
        valid = true,
    }
}

// Convert canonical bitmap metrics and shaping offsets into a snapped quad origin.
ui_text_resolved_glyph_destination :: proc(draw: Resolved_Glyph_Draw) -> (
    geometry.Rectangle, bool) {

    resolved := draw.resolved
    if resolved.raster_pixel_height <= 0 {
        return {}, false
    }
    scale, valid_scale := ui_text_resolved_raster_scale(draw)
    if !valid_scale {
        return {}, false
    }
    offset_scale := draw.font_size/f32(view_font.JULIA_MONO_FONT_SIZE)/64
    bitmap_top, valid_top := view_font.font_raster_bitmap_top_logical(
        {
            line_top = draw.position.y,
            logical_size = draw.font_size,
            canonical_pixel_height = resolved.canonical_pixel_height,
            canonical_ascent = resolved.canonical_raster_ascent,
            bitmap_offset_y = resolved.offset_y,
            raster_pixel_height = u32(resolved.raster_pixel_height),
            raster_ascent = resolved.raster_ascent,
        })
    if !valid_top {
        return {}, false
    }
    destination := geometry.Rectangle{
        x = draw.position.x + f32(resolved.offset_x)*scale +
            f32(draw.x_offset)*offset_scale,
        y = bitmap_top + f32(draw.y_offset)*offset_scale,
        width = resolved.source.width*scale,
        height = resolved.source.height*scale,
    }
    origin := ui_text_snap_glyph_origin(
        draw.encoder, {destination.x, destination.y})
    destination.x = origin.x
    destination.y = origin.y
    return destination, true
}

// Convert one resolved raster texel to logical units for the current draw size.
ui_text_resolved_raster_scale :: proc(draw: Resolved_Glyph_Draw) -> (f32, bool) {
    return view_font.font_raster_metric_to_logical(
        1, draw.font_size, u32(draw.resolved.raster_pixel_height))
}

// Align a glyph bitmap origin to the physical pixel grid without changing layout.
ui_text_snap_glyph_origin :: proc(
    encoder: ^native.Draw_Encoder,
    position: geometry.Vector2) -> geometry.Vector2 {

    if encoder == nil || encoder.logical_extent.x <= 0 ||
        encoder.logical_extent.y <= 0 {
        return position
    }
    scale_x := f64(encoder.physical_extent[0])/f64(encoder.logical_extent.x)
    scale_y := f64(encoder.physical_extent[1])/f64(encoder.logical_extent.y)
    return {
        f32(math.floor(f64(position.x)*scale_x + 0.5)/scale_x),
        f32(math.floor(f64(position.y)*scale_y + 0.5)/scale_y),
    }
}

//   Convert one cached 26.6 glyph position and advance to pixel coordinates.
ui_text_cached_glyph_placement :: #force_inline proc(
    glyph: view_font.Shaped_Glyph,
    pen_x, top_y, font_size, base_pixel_size: f32) -> Cached_Glyph_Placement {

    scale := font_size/base_pixel_size/64
    return {
        position = {
            pen_x + f32(glyph.x_offset)*scale,
            top_y + f32(glyph.y_offset)*scale,
        },
        next_pen_x = pen_x + f32(glyph.x_advance)*scale,
    }
}

//   Place one shaped JuliaMono glyph on its authoritative source-codepoint column.
ui_text_cached_monospace_glyph_placement :: #force_inline proc(
    request: Cached_Monospace_Run_Draw,
    glyph: view_font.Shaped_Glyph) -> (geometry.Vector2, bool) {

    shaped := request.shaped
    column, valid := ui_text_cluster_column(request.text, glyph.cluster)
    if !valid || request.column_advance <= 0 || shaped.font_size <= 0 ||
        shaped.base_pixel_size <= 0 {
        return {}, false
    }
    offset_scale := shaped.font_size/shaped.base_pixel_size/64
    return {
        shaped.position.x + f32(column)*request.column_advance +
            f32(glyph.x_offset)*offset_scale,
        shaped.position.y + f32(glyph.y_offset)*offset_scale,
    }, true
}

//   Convert a measured ink-top position to the resident font's stable line top.
ui_text_cached_run_line_top :: #force_inline proc(
    ink_top, ink_ascent, raster_ascent, font_size, base_pixel_size: f32) -> f32 {

    scale := font_size/base_pixel_size
    baseline := ink_top + ink_ascent*scale
    return baseline - raster_ascent*scale
}

//   Draw one sealed shaped run without reshaping or reconstructing its advances.
//
// Returns:
//   - True only when every cached glyph was resident and the complete run was drawn.
ui_text_cached_shaped_run :: proc(request: Cached_Shaped_Run_Draw) -> bool {
    if request.resolver.resolve_glyph == nil || len(request.glyphs) == 0 ||
        request.font_size <= 0 || request.base_pixel_size <= 0 {
        return false
    }
    raster_request, request_valid := ui_text_raster_request(
        request.resolver, request.key, request.font_size, request.encoder)
    if !request_valid {
        return false
    }
    selection, selected := ui_text_shape_glyphs_are_resident(
        request.resolver, request.key, request.glyphs, raster_request)
    if !selected {
        return false
    }
    pen_x := request.position.x
    for glyph in request.glyphs {
        resolved, resident := ui_text_resolve_selected_glyph(
            request.resolver, request.key, glyph.glyph_id,
            raster_request, selection)
        assert(resident)
        placement := ui_text_cached_glyph_placement(
            glyph, pen_x, request.position.y,
            request.font_size, request.base_pixel_size)
        ui_text_draw_resolved_glyph({
            encoder = request.encoder,
            resolved = resolved,
            position = placement.position,
            font_size = request.font_size,
            color = request.color,
        })
        pen_x = placement.next_pen_x
    }
    return true
}

//   Draw one sealed JuliaMono run on the source-column grid used by the terminal.
ui_text_cached_monospace_run :: proc(
    request: Cached_Monospace_Run_Draw) -> bool {
    shaped := request.shaped
    preflight := ui_text_cached_monospace_preflight(request)
    if !preflight.ready {
        return false
    }
    for glyph in shaped.glyphs {
        resolved, resident := ui_text_resolve_selected_glyph(
            shaped.resolver, shaped.key, glyph.glyph_id,
            preflight.raster_request, preflight.selection)
        assert(resident)
        position, valid := ui_text_cached_monospace_glyph_placement(
            request, glyph)
        assert(valid)
        ui_text_draw_resolved_glyph({
            encoder = shaped.encoder,
            resolved = resolved,
            position = position,
            font_size = shaped.font_size,
            color = shaped.color,
        })
    }
    return true
}

// Validate the run and pin one raster containing every cached monospace glyph.
ui_text_cached_monospace_preflight :: proc(
    request: Cached_Monospace_Run_Draw) -> Cached_Monospace_Preflight {

    shaped := request.shaped
    if shaped.resolver.resolve_glyph == nil || len(shaped.glyphs) == 0 ||
        len(request.text) == 0 || request.column_advance <= 0 ||
        shaped.font_size <= 0 || shaped.base_pixel_size <= 0 {
        return {}
    }
    raster_request, valid := ui_text_raster_request(
        shaped.resolver, shaped.key, shaped.font_size, shaped.encoder)
    if !valid || !ui_text_shape_clusters_are_valid(request.text, shaped.glyphs) {
        return {}
    }
    selection, selected := ui_text_shape_glyphs_are_resident(
        shaped.resolver, shaped.key, shaped.glyphs, raster_request)
    return {raster_request, selection, selected}
}

//   Resolve one codepoint or the resident replacement glyph while recording demand.
ui_text_resolve_codepoint :: proc(
    resolver: view_font.Font_Resolver, key: view_font.Font_Key,
    codepoint: rune,
    raster_request: view_font.Font_Raster_Request) -> Codepoint_Resolution {

    if resolver.resolve_codepoint == nil {
        return {status = .Unsupported}
    }
    resolved, status := resolver.resolve_codepoint(
        resolver.user_data, key, codepoint, raster_request)
    if status == .Resident {
        return {glyph = resolved, status = status, drawable = true}
    }
    replacement, replacement_status := resolver.resolve_codepoint(
        resolver.user_data, key, rune(0xfffd), raster_request)
    return {
        glyph = replacement,
        status = status,
        drawable = replacement_status == .Resident,
    }
}

//   Draw UTF-8 without shaping while resolving every rune through glyph pages.
ui_text_unshaped_paged :: proc(
    request: Unshaped_Text_Draw) -> bool {
    raster_request, request_valid := ui_text_raster_request(
        request.resolver, request.key, request.font.font_size, request.encoder)
    if !request_valid {
        return false
    }
    glyph_ids: [UI_TEXT_GLYPH_SELECTION_CAPACITY]u32
    preflight := ui_text_unshaped_preflight(request, raster_request, &glyph_ids)
    if !preflight.ready {
        return false
    }
    if !ui_text_draw_unshaped_glyphs(
        request, raster_request, preflight.selection,
        glyph_ids[:preflight.glyph_count]) {
        return false
    }
    return preflight.all_resident
}

// Collect drawable glyphs and select one raster containing the complete run.
ui_text_unshaped_preflight :: proc(
    request: Unshaped_Text_Draw,
    raster_request: view_font.Font_Raster_Request,
    glyph_ids: ^[UI_TEXT_GLYPH_SELECTION_CAPACITY]u32) -> Unshaped_Glyph_Preflight {

    if len(request.text) > UI_TEXT_GLYPH_SELECTION_CAPACITY {
        return {}
    }
    count := 0
    all_resident := true
    for codepoint in request.text {
        resolution := ui_text_resolve_codepoint(
            request.resolver, request.key, codepoint, raster_request)
        if !resolution.drawable {
            return {}
        }
        all_resident = all_resident && resolution.status == .Resident
        glyph_ids[count] = resolution.glyph.glyph_id
        count += 1
    }
    selection, selected := ui_text_select_glyph_ids(
        request.resolver, request.key, glyph_ids[:count], raster_request)
    if !selected {
        return {}
    }
    return {count, all_resident, selection, true}
}

// Resolve and emit every glyph from the preselected raster instance.
ui_text_draw_unshaped_glyphs :: proc(
    request: Unshaped_Text_Draw,
    raster_request: view_font.Font_Raster_Request,
    selection: view_font.Font_Raster_Selection,
    glyph_ids: []u32) -> bool {

    draw_x := request.position.x
    for glyph_id in glyph_ids {
        resolved, resident := ui_text_resolve_selected_glyph(
            request.resolver, request.key, glyph_id, raster_request, selection)
        if !resident {
            return false
        }
        ui_text_draw_resolved_glyph({
            encoder = request.encoder,
            resolved = resolved,
            position = {draw_x, request.position.y},
            font_size = request.font.font_size,
            color = request.color,
        })
        draw_x += f32(resolved.canonical_advance_x)*
            request.font.font_size/f32(view_font.JULIA_MONO_FONT_SIZE)
    }
    return true
}

//   Draw one shaped request through page-aware unshaped glyph resolution.
ui_text_draw_unshaped :: #force_inline proc(request: Shaped_Text_Draw) {
    _ = ui_text_unshaped_paged({
        encoder = request.encoder,
        resolver = request.resolver,
        key = request.key,
        text = request.text,
        position = request.position,
        color = request.color,
        font = request.font,
    })
}

//   Validate every output cluster before any shaped glyph reaches the screen.
ui_text_shape_clusters_are_valid :: proc(
    text: string, glyphs: []view_font.Shaped_Glyph) -> bool {

    for glyph in glyphs {
        _, valid := ui_text_cluster_column(text, glyph.cluster)
        if !valid {
            return false
        }
    }
    return true
}

//   Draw one fully validated shaped run on Euclid's fixed source-column grid.
ui_text_draw_shaped_run :: proc(
    request: Shaped_Text_Draw, glyphs: []view_font.Shaped_Glyph,
    column_advance: f32,
    raster_request: view_font.Font_Raster_Request,
    selection: view_font.Font_Raster_Selection) {

    for glyph in glyphs {
        column, _ := ui_text_cluster_column(request.text, glyph.cluster)
        resolved, resident := ui_text_resolve_selected_glyph(
            request.resolver, request.key, glyph.glyph_id,
            raster_request, selection)
        assert(resident)
        ui_text_draw_resolved_glyph({
            encoder = request.encoder,
            resolved = resolved,
            position = geometry.Vector2{
                request.position.x + f32(column)*column_advance,
                request.position.y,
            },
            font_size = request.font.font_size,
            color = request.color,
            x_offset = glyph.x_offset,
            y_offset = glyph.y_offset,
        })
    }
}

//   Resolve every shaped glyph before drawing to preserve whole-run fallback.
ui_text_shape_glyphs_are_resident :: proc(
    resolver: view_font.Font_Resolver, key: view_font.Font_Key,
    glyphs: []view_font.Shaped_Glyph,
    raster_request: view_font.Font_Raster_Request) -> (
        view_font.Font_Raster_Selection, bool) {

    if resolver.resolve_glyph == nil {
        return {}, false
    }
    glyph_ids: [UI_TEXT_GLYPH_SELECTION_CAPACITY]u32
    if len(glyphs) > len(glyph_ids) {
        return {}, false
    }
    for glyph, index in glyphs {
        glyph_ids[index] = glyph.glyph_id
    }
    return ui_text_select_glyph_ids(
        resolver, key, glyph_ids[:len(glyphs)], raster_request)
}

// Select one raster containing the complete glyph-ID sequence.
ui_text_select_glyph_ids :: proc(
    resolver: view_font.Font_Resolver, key: view_font.Font_Key,
    glyph_ids: []u32, raster_request: view_font.Font_Raster_Request) -> (
        view_font.Font_Raster_Selection, bool) {

    if len(glyph_ids) == 0 || resolver.resolve_glyph == nil {
        return {}, false
    }
    if resolver.select_glyph_raster != nil {
        return resolver.select_glyph_raster(
            resolver.user_data, key, glyph_ids, raster_request)
    }
    first: view_font.Resolved_Glyph
    for glyph_id, index in glyph_ids {
        resolved, resident := resolver.resolve_glyph(
            resolver.user_data, key, glyph_id, raster_request)
        if !resident {
            return {}, false
        }
        if index == 0 {
            first = resolved
        } else if !ui_text_glyphs_share_raster(first, resolved) {
            return {}, false
        }
    }
    selection := ui_text_raster_selection(first)
    return selection, selection.pixel_height > 0
}

// Resolve one glyph and enforce the selected run identity.
ui_text_resolve_selected_glyph :: proc(
    resolver: view_font.Font_Resolver, key: view_font.Font_Key,
    glyph_id: u32, raster_request: view_font.Font_Raster_Request,
    selection: view_font.Font_Raster_Selection) -> (view_font.Resolved_Glyph, bool) {

    if resolver.resolve_selected_glyph != nil {
        return resolver.resolve_selected_glyph(
            resolver.user_data, key, glyph_id, raster_request, selection)
    }
    resolved, resident := resolver.resolve_glyph(
        resolver.user_data, key, glyph_id, raster_request)
    return resolved, resident && ui_text_glyph_matches_selection(resolved, selection)
}

// Compare the exact raster identity of two resolved glyphs.
ui_text_glyphs_share_raster :: #force_inline proc(
    first, next: view_font.Resolved_Glyph) -> bool {

    return first.raster_slot_index == next.raster_slot_index &&
        first.raster_slot_incarnation == next.raster_slot_incarnation &&
        first.raster_pixel_height == next.raster_pixel_height
}

// Convert one resolved glyph's identity to a reusable run selection.
ui_text_raster_selection :: #force_inline proc(
    glyph: view_font.Resolved_Glyph) -> view_font.Font_Raster_Selection {

    return {
        slot_index = glyph.raster_slot_index,
        slot_incarnation = glyph.raster_slot_incarnation,
        pixel_height = u32(glyph.raster_pixel_height),
    }
}

// Confirm one resolved glyph belongs to the selected raster instance.
ui_text_glyph_matches_selection :: #force_inline proc(
    glyph: view_font.Resolved_Glyph,
    selection: view_font.Font_Raster_Selection) -> bool {

    return glyph.raster_slot_index == selection.slot_index &&
        glyph.raster_slot_incarnation == selection.slot_incarnation &&
        u32(glyph.raster_pixel_height) == selection.pixel_height
}

//   Record one rejection and draw the complete run through the fallback path.
ui_text_shaped_fallback :: proc(
    request: Shaped_Text_Draw, reason: view_font.Shape_Fallback_Reason) -> bool {

    ui_text_shape_fallback(request.resolver, reason)
    ui_text_draw_unshaped(request)
    return false
}

// Validate shaped output and preserve its canonical glyph slice and advance.
ui_text_shaped_geometry_preflight :: proc(
    request: Shaped_Text_Draw) -> Shaped_Run_Preflight {

    resolver := request.resolver
    result := Shaped_Run_Preflight{reason = .Invalid_Result}
    if len(request.text) > len(resolver.workspace) {
        result.reason = .Workspace_Overflow
        return result
    }
    glyph_count, shaped := resolver.shape(
        resolver.user_data, request.key, request.text, resolver.workspace)
    if !shaped || !ui_text_shape_is_valid(
        request.text, resolver.workspace, glyph_count) {
        return result
    }
    column_advance, advance_valid := ui_text_column_advance(
        request.font.font, request.font.font_size)
    if !advance_valid {
        return result
    }
    glyphs := resolver.workspace[:glyph_count]
    if !ui_text_shape_clusters_are_valid(request.text, glyphs) {
        result.reason = .Invalid_Cluster
        return result
    }
    result.glyphs = glyphs
    result.column_advance = column_advance
    result.ready = true
    return result
}

// Select one resident raster that contains every validated shaped glyph.
ui_text_shaped_preflight :: proc(
    request: Shaped_Text_Draw) -> Shaped_Run_Preflight {

    result := ui_text_shaped_geometry_preflight(request)
    if !result.ready {
        return result
    }
    resolver := request.resolver
    raster_request, request_valid := ui_text_raster_request(
        resolver, request.key, request.font.font_size, request.encoder)
    if !request_valid {
        return result
    }
    selection, selected := ui_text_shape_glyphs_are_resident(
        resolver, request.key, result.glyphs, raster_request)
    if !selected {
        result.reason = .Pending_Glyph
        result.ready = false
        return result
    }
    result.raster_request = raster_request
    result.selection = selection
    return result
}

//   Shape and draw one UTF-8 run, falling back atomically to ordinary text encoding.
ui_text_shaped_f32 :: proc(
    request: Shaped_Text_Draw) -> bool {

    resolver := request.resolver
    if len(request.text) < 2 || resolver.shape == nil {
        ui_text_draw_unshaped(request)
        return false
    }
    preflight := ui_text_shaped_preflight(request)
    if !preflight.ready {
        return ui_text_shaped_fallback(request, preflight.reason)
    }
    ui_text_draw_shaped_run(
        request, preflight.glyphs, preflight.column_advance,
        preflight.raster_request, preflight.selection)
    return true
}

//   Integer-coordinate shaped counterpart to `ui_text`.
ui_text_shaped :: proc(
    request: Shaped_Text_Draw) -> bool {

    return ui_text_shaped_f32(request)
}

//   Draw one visible wrapped row through the configured font path.
draw_wrapped_text_row :: proc(
    text: string, row_y: f32, params: Wrapped_Text_Content_Params) {

    text_font := Ui_Text_Font{params.font, params.font_size}
    position := geometry.Vector2{params.panel.x + params.text_padding, row_y}
    if params.font_cache == nil {
        return
    }
    resolver := view_font.cache_terminal_resolver(params.font_cache)
    ui_text_shaped({
        encoder = params.encoder,
        resolver = resolver,
        key = params.font_key,
        text = text,
        position = position,
        color = params.text_color,
        font = text_font,
    })
}

//   Draw wrapped text rows clipped to the visible panel area.
draw_wrapped_text_content :: proc(
    text: string,
    params: Wrapped_Text_Content_Params) {

    panel := params.panel
    text_padding := params.text_padding
    text_row_height := params.text_row_height

    max_chars := dyncore.chars_per_text_row(
        panel.width - text_padding * 2, params.wrap_advance)
    start := 0
    row := 0

    if len(text) == 0 {
       return
    }

    for start < len(text) {
        span := dyncore.next_wrapped_text_span(text, start, max_chars)
        row_y := panel.y + text_padding + f32(row) * text_row_height -
            params.scroll_y

        if row_y + text_row_height >= panel.y && row_y <= panel.y + panel.height {
            draw_wrapped_text_row(
                text[span.line_start:span.line_end], row_y, params)
        }

        row += 1
        if span.next_start <= start {
            break
        }
        start = span.next_start
    }
}
