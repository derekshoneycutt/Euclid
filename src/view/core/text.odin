package view_core

import "../../dynview"
import view_font "../font"

import "core:strings"

import rl "vendor:raylib"

//   Draw environment for wrapped text content: the clipping panel, scroll
//   offset, font, and typography metrics, grouped so the draw call passes one
//   coherent value.
Wrapped_Text_Content_Params :: struct {
    panel : rl.Rectangle,
    scroll_y : f32,
    font : rl.Font,
    text_padding : f32,
    text_row_height : f32,
    text_color : rl.Color,
    wrap_advance : f32,
    font_size : f32,
    font_cache : ^view_font.Font_Cache,
    font_key : view_font.Font_Key,
}


//   Font and size pair for UI text draw calls.
Ui_Text_Font :: struct {
    font : rl.Font,
    font_size : f32,
}

//   Complete inputs for one atomic shaped-or-unshaped text draw.
Shaped_Text_Draw :: struct {
    resolver: view_font.Font_Resolver,
    key: view_font.Font_Key,
    text: string,
    position: rl.Vector2,
    color: rl.Color,
    font: Ui_Text_Font,
}

//   Wrap a font with the default UI text size.
ui_text_font :: #force_inline proc(font: rl.Font) -> Ui_Text_Font {
    return Ui_Text_Font{font = font, font_size = TREE_FONT_SIZE}
}

//   Draw UTF-8 UI text using temp C-string conversion.
ui_text :: #force_inline proc(
    text: string, x, y: int, color: rl.Color, font: Ui_Text_Font) {
    cloned := strings.clone_to_cstring(text, context.temp_allocator)
    position := rl.Vector2{f32(x), f32(y)}
    rl.DrawTextEx(font.font, cloned, position, font.font_size, 0, color)
}

//   Draw UTF-8 UI text using float coordinates to avoid pixel snap artifacts.
ui_text_f32 :: #force_inline proc(
    text: string, x, y: f32, color: rl.Color, font: Ui_Text_Font) {
    cloned := strings.clone_to_cstring(text, context.temp_allocator)
    position := rl.Vector2{x, y}
    rl.DrawTextEx(font.font, cloned, position, font.font_size, 0, color)
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
    return dynview.text_codepoint_count_span(text, 0, int(cluster)), true
}

//   Resolve Euclid's stb-scaled monospace column width from the finalized atlas.
ui_text_column_advance :: proc(atlas: rl.Font, font_size: f32) -> (f32, bool) {
    space_index := int(rl.GetGlyphIndex(atlas, ' '))
    if space_index < 0 || space_index >= int(atlas.glyphCount) ||
        atlas.glyphs[space_index].advanceX <= 0 || atlas.baseSize <= 0 {
        return 0, false
    }
    return f32(atlas.glyphs[space_index].advanceX)*
        font_size/f32(atlas.baseSize), true
}

//   Validate a complete horizontal monospace shape result before drawing.
ui_text_shape_is_valid :: proc(
    text: string, glyphs: []view_font.Shaped_Glyph,
    glyph_count: int, atlas: rl.Font) -> bool {

    if glyph_count <= 0 || glyph_count > len(glyphs) ||
        !rl.IsFontValid(atlas) {
        return false
    }
    codepoint_count := dynview.text_codepoint_count_span(text, 0, len(text))
    if codepoint_count <= 0 {
        return false
    }
    total_advance := i64(0)
    for glyph in glyphs[:glyph_count] {
        if glyph.glyph_id >= u32(atlas.glyphCount) || glyph.y_advance != 0 ||
            glyph.x_advance <= 0 ||
            !ui_text_cluster_is_valid(text, glyph.cluster) {
            return false
        }
        total_advance += i64(glyph.x_advance)
    }
    return total_advance == i64(glyphs[0].x_advance)*i64(codepoint_count)
}

//   Draw one shaped glyph directly from its complete glyph-ID atlas.
ui_text_draw_shaped_glyph :: proc(
    atlas: rl.Font, glyph: view_font.Shaped_Glyph,
    position: rl.Vector2, font_size: f32, color: rl.Color) {

    source := atlas.recs[glyph.glyph_id]
    metric := atlas.glyphs[glyph.glyph_id]
    scale := font_size/f32(atlas.baseSize)
    offset_scale := scale/64
    destination := rl.Rectangle{
        x = position.x + f32(metric.offsetX)*scale +
            f32(glyph.x_offset)*offset_scale,
        y = position.y + f32(metric.offsetY)*scale +
            f32(glyph.y_offset)*offset_scale,
        width = source.width*scale,
        height = source.height*scale,
    }
    rl.DrawTexturePro(atlas.texture, source, destination, {}, 0, color)
}

//   Draw one shaped request through the ordinary raylib text path.
ui_text_draw_unshaped :: #force_inline proc(request: Shaped_Text_Draw) {
    ui_text_f32(request.text, request.position.x, request.position.y,
        request.color, request.font)
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
        ui_text_draw_shaped_glyph(
            request.font.font, glyph, rl.Vector2{
                request.position.x + f32(column)*column_advance,
                request.position.y,
            }, request.font.font_size, request.color)
    }
}

//   Shape and draw one UTF-8 run, falling back atomically to ordinary raylib text.
ui_text_shaped_f32 :: proc(
    request: Shaped_Text_Draw) -> bool {

    resolver := request.resolver
    text := request.text

    if len(text) < 2 || resolver.shape == nil {
        ui_text_draw_unshaped(request)
        return false
    }
    if len(text) > len(resolver.workspace) {
        ui_text_shape_fallback(resolver, .Workspace_Overflow)
        ui_text_draw_unshaped(request)
        return false
    }
    glyph_count, shaped := resolver.shape(
        resolver.user_data, request.key, text, resolver.workspace)
    if !shaped || !ui_text_shape_is_valid(
        text, resolver.workspace, glyph_count, request.font.font) {
        ui_text_shape_fallback(resolver, .Invalid_Result)
        ui_text_draw_unshaped(request)
        return false
    }
    column_advance, advance_valid := ui_text_column_advance(
        request.font.font, request.font.font_size)
    if !advance_valid {
        ui_text_shape_fallback(resolver, .Invalid_Result)
        ui_text_draw_unshaped(request)
        return false
    }
    glyphs := resolver.workspace[:glyph_count]
    if !ui_text_shape_clusters_are_valid(text, glyphs) {
        ui_text_shape_fallback(resolver, .Invalid_Cluster)
        ui_text_draw_unshaped(request)
        return false
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
    position := rl.Vector2{params.panel.x + params.text_padding, row_y}
    if params.font_cache == nil {
        ui_text_f32(text, position.x, position.y, params.text_color, text_font)
        return
    }
    resolver := view_font.cache_terminal_resolver(params.font_cache)
    ui_text_shaped({
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

    max_chars := dynview.chars_per_text_row(
        panel.width - text_padding * 2, params.wrap_advance)
    start := 0
    row := 0

    if len(text) == 0 {
        ui_text("", int(panel.x + text_padding), int(panel.y + text_padding),
            params.text_color, Ui_Text_Font{params.font, params.font_size})
        return
    }

    for start < len(text) {
        span := dynview.next_wrapped_text_span(text, start, max_chars)
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
