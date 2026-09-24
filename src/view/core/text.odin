package view_core

import dyncore "../../dynview/core"
import view_font "../font"
import native "../native"
import color "../../core/color"
import geometry "../../core/geometry"

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

//   Complete inputs for one page-aware unshaped codepoint draw.
Codepoint_Text_Draw :: struct {
    encoder: ^native.Draw_Encoder,
    resolver: view_font.Font_Resolver,
    key: view_font.Font_Key,
    codepoint: rune,
    position: geometry.Vector2,
    font_size: f32,
    color: color.Color_RGBA8,
}

//   Resolved codepoint draw data plus original residency and drawability state.
Codepoint_Resolution :: struct {
    glyph: view_font.Resolved_Glyph,
    status: view_font.Font_Glyph_Resolve_Status,
    drawable: bool,
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
    if atlas.spaceAdvance <= 0 || atlas.baseSize <= 0 {
        return 0, false
    }
    return f32(atlas.spaceAdvance)*
        font_size/f32(atlas.baseSize), true
}

// ui_text_measure_monospace returns one UTF-8 run width under fixed spacing.
ui_text_measure_monospace :: proc(
    text: string, atlas: view_font.Font_Face,
    font_size, spacing: f32) -> (f32, bool) {
    advance, valid := ui_text_column_advance(atlas, font_size)
    count := dyncore.text_codepoint_count_span(text, 0, len(text))
    if !valid || count < 0 {return 0, false}
    if count == 0 {return 0, true}
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
    resolved := draw.resolved
    if draw.encoder == nil || resolved.texture.handle == nil ||
        resolved.texture.width == 0 || resolved.texture.height == 0 {
        return
    }
    scale := draw.font_size/f32(resolved.base_size)
    offset_scale := scale/64
    destination := geometry.Rectangle{
        x = draw.position.x + f32(resolved.offset_x)*scale +
            f32(draw.x_offset)*offset_scale,
        y = draw.position.y + f32(resolved.offset_y)*scale +
            f32(draw.y_offset)*offset_scale,
        width = resolved.source.width*scale,
        height = resolved.source.height*scale,
    }
    texture_width := f32(resolved.texture.width)
    texture_height := f32(resolved.texture.height)
    uv := geometry.Rectangle{
        resolved.source.x/texture_width,
        resolved.source.y/texture_height,
        resolved.source.width/texture_width,
        resolved.source.height/texture_height,
    }
    _ = native.draw_encoder_texture_quad(draw.encoder, destination, uv,
        draw.color, resolved.texture.handle)
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
    if !ui_text_shape_glyphs_are_resident(
        request.resolver, request.key, request.glyphs) {
        return false
    }
    pen_x := request.position.x
    for glyph in request.glyphs {
        resolved, resident := request.resolver.resolve_glyph(
            request.resolver.user_data, request.key, glyph.glyph_id)
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
ui_text_cached_monospace_run :: proc(request: Cached_Monospace_Run_Draw) -> bool {
    shaped := request.shaped
    if shaped.resolver.resolve_glyph == nil || len(shaped.glyphs) == 0 ||
        len(request.text) == 0 || request.column_advance <= 0 ||
        shaped.font_size <= 0 || shaped.base_pixel_size <= 0 {
        return false
    }
    if !ui_text_shape_clusters_are_valid(request.text, shaped.glyphs) ||
        !ui_text_shape_glyphs_are_resident(
            shaped.resolver, shaped.key, shaped.glyphs) {
        return false
    }
    for glyph in shaped.glyphs {
        resolved, resident := shaped.resolver.resolve_glyph(
            shaped.resolver.user_data, shaped.key, glyph.glyph_id)
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

//   Resolve one codepoint or the resident replacement glyph while recording demand.
ui_text_resolve_codepoint :: proc(
    resolver: view_font.Font_Resolver, key: view_font.Font_Key,
    codepoint: rune) -> Codepoint_Resolution {

    if resolver.resolve_codepoint == nil {
        return {status = .Unsupported}
    }
    resolved, status := resolver.resolve_codepoint(
        resolver.user_data, key, codepoint)
    if status == .Resident {
        return {glyph = resolved, status = status, drawable = true}
    }
    replacement, replacement_status := resolver.resolve_codepoint(
        resolver.user_data, key, rune(0xfffd))
    return {
        glyph = replacement,
        status = status,
        drawable = replacement_status == .Resident,
    }
}

//   Draw one unshaped rune through cmap lookup and demand-loaded pages.
ui_text_codepoint_paged :: proc(draw: Codepoint_Text_Draw) -> bool {

    resolution := ui_text_resolve_codepoint(
        draw.resolver, draw.key, draw.codepoint)
    if !resolution.drawable {
        return false
    }
    ui_text_draw_resolved_glyph({
        encoder = draw.encoder,
        resolved = resolution.glyph,
        position = draw.position,
        font_size = draw.font_size,
        color = draw.color,
    })
    return resolution.status == .Resident
}

//   Draw UTF-8 without shaping while resolving every rune through glyph pages.
ui_text_unshaped_paged :: proc(request: Unshaped_Text_Draw) -> bool {
    draw_x := request.position.x
    all_resident := true
    for codepoint in request.text {
        resolution := ui_text_resolve_codepoint(
            request.resolver, request.key, codepoint)
        if !resolution.drawable {
            return false
        }
        all_resident = all_resident && resolution.status == .Resident
        ui_text_draw_resolved_glyph({
            encoder = request.encoder,
            resolved = resolution.glyph,
            position = {draw_x, request.position.y},
            font_size = request.font.font_size,
            color = request.color,
        })
        draw_x += f32(resolution.glyph.advance_x)*
            request.font.font_size/f32(resolution.glyph.base_size)
    }
    return all_resident
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
    column_advance: f32) {

    for glyph in glyphs {
        column, _ := ui_text_cluster_column(request.text, glyph.cluster)
        resolved, resident := request.resolver.resolve_glyph(
            request.resolver.user_data, request.key, glyph.glyph_id)
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
    glyphs: []view_font.Shaped_Glyph) -> bool {

    if resolver.resolve_glyph == nil {
        return false
    }
    for glyph in glyphs {
        _, resident := resolver.resolve_glyph(
            resolver.user_data, key, glyph.glyph_id)
        if !resident {
            return false
        }
    }
    return true
}

//   Record one rejection and draw the complete run through the fallback path.
ui_text_shaped_fallback :: proc(
    request: Shaped_Text_Draw, reason: view_font.Shape_Fallback_Reason) -> bool {

    ui_text_shape_fallback(request.resolver, reason)
    ui_text_draw_unshaped(request)
    return false
}

//   Shape and draw one UTF-8 run, falling back atomically to ordinary text encoding.
ui_text_shaped_f32 :: proc(
    request: Shaped_Text_Draw) -> bool {

    resolver := request.resolver
    text := request.text

    if len(text) < 2 || resolver.shape == nil {
        ui_text_draw_unshaped(request)
        return false
    }
    if len(text) > len(resolver.workspace) {
        return ui_text_shaped_fallback(request, .Workspace_Overflow)
    }
    glyph_count, shaped := resolver.shape(
        resolver.user_data, request.key, text, resolver.workspace)
    if !shaped || !ui_text_shape_is_valid(
        text, resolver.workspace, glyph_count) {
        return ui_text_shaped_fallback(request, .Invalid_Result)
    }
    column_advance, advance_valid := ui_text_column_advance(
        request.font.font, request.font.font_size)
    if !advance_valid {
        return ui_text_shaped_fallback(request, .Invalid_Result)
    }
    glyphs := resolver.workspace[:glyph_count]
    if !ui_text_shape_clusters_are_valid(text, glyphs) {
        return ui_text_shaped_fallback(request, .Invalid_Cluster)
    }
    if !ui_text_shape_glyphs_are_resident(resolver, request.key, glyphs) {
        return ui_text_shaped_fallback(request, .Pending_Glyph)
    }
    ui_text_draw_shaped_run(request, glyphs, column_advance)
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

    if len(text) == 0 {return}

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
