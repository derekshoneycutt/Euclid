#+test
package view_core

import view_font "../font"
import native "../native"
import color "../../core/color"

import "core:testing"

Codepoint_Resolver_Test_State :: struct {
    requested_codepoint: rune,
    replacement_id: u32,
}

Cached_Glyph_Resolver_Test_State :: struct {
    calls: int,
    reject_glyph_id: u32,
}

// Verify shared UI glyph emission records linear texture filtering.
@(test)
text_test_resolved_glyph_uses_linear_sampling :: proc(t: ^testing.T) {
    vertices: [4]native.Draw_Vertex
    indices: [6]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    texture := rawptr(uintptr(1))
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))

    ui_text_draw_resolved_glyph({
        encoder = &encoder,
        resolved = {
            texture = {handle = texture, width = 32, height = 32},
            source = {x = 1, y = 2, width = 8, height = 10},
            raster_pixel_height = 32,
            raster_ascent = 24,
            canonical_pixel_height = 32,
            canonical_raster_ascent = 24,
        },
        font_size = 16,
        color = color.WHITE,
    })

    testing.expect_value(t, encoder.batch_count, 1)
    testing.expect_value(t, batches[0].sampler, native.Draw_Sampler.Linear)
}

// Verify bitmap metrics use raster height while HarfBuzz offsets stay canonical.
@(test)
text_test_resolved_glyph_separates_raster_and_shaping_scales :: proc(t: ^testing.T) {
    vertices: [4]native.Draw_Vertex
    indices: [6]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    texture := rawptr(uintptr(1))
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))

    ui_text_draw_resolved_glyph({
        encoder = &encoder,
        resolved = {
            texture = {handle = texture, width = 32, height = 32},
            source = {x = 1, y = 2, width = 8, height = 10},
            offset_x = 6,
            offset_y = 20,
            raster_pixel_height = 24,
            raster_ascent = 18,
            canonical_pixel_height = 32,
            canonical_raster_ascent = 24,
        },
        position = {10, 20},
        font_size = 12,
        color = color.WHITE,
        x_offset = 64,
    })

    testing.expect_value(t, encoder.batch_count, 1)
    testing.expect_value(t, vertices[0].position.x, f32(13))
    testing.expect_value(t, vertices[0].position.y, f32(30))
    testing.expect_value(t, vertices[1].position.x, f32(17))
}

// Verify glyph origins align independently on nonuniform physical transforms.
@(test)
text_test_glyph_origin_snaps_to_physical_grid :: proc(t: ^testing.T) {
    vertices: [4]native.Draw_Vertex
    indices: [6]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {150, 125}))

    snapped := ui_text_snap_glyph_origin(&encoder, {10.4, 20.4})
    testing.expect_value(t, snapped.x, f32(16)/f32(1.5))
    testing.expect_value(t, snapped.y, f32(20))
}

// Reject one requested glyph so cached drawing can prove atomic preflight fallback.
text_test_resolve_cached_glyph :: proc(
    user_data: rawptr, key: view_font.Font_Key,
    glyph_id: u32, _: view_font.Font_Raster_Request) ->
    (view_font.Resolved_Glyph, bool) {

    _ = key
    state := cast(^Cached_Glyph_Resolver_Test_State)user_data
    state^.calls += 1
    return {}, glyph_id != state^.reject_glyph_id
}

// Return pending for the requested rune and a resident sentinel for U+FFFD.
text_test_resolve_codepoint :: proc(
    user_data: rawptr, key: view_font.Font_Key,
    codepoint: rune, _: view_font.Font_Raster_Request) -> (
    view_font.Resolved_Glyph, view_font.Font_Glyph_Resolve_Status) {

    state := cast(^Codepoint_Resolver_Test_State)user_data
    state.requested_codepoint = codepoint
    if codepoint == rune(0xfffd) {
        return {
            advance_x = i32(state.replacement_id), raster_pixel_height = 32,
        }, .Resident
    }
    return {}, .Pending
}

// Verify HarfBuzz byte clusters map to Euclid codepoint columns.
@(test)
text_test_cluster_column :: proc(t: ^testing.T) {
    text: string = "aα=>"

    column, valid := ui_text_cluster_column(text, 0)
    testing.expect(t, valid)
    testing.expect_value(t, column, 0)

    column, valid = ui_text_cluster_column(text, 1)
    testing.expect(t, valid)
    testing.expect_value(t, column, 1)

    column, valid = ui_text_cluster_column(text, 3)
    testing.expect(t, valid)
    testing.expect_value(t, column, 2)

    _, valid = ui_text_cluster_column(text, 2)
    testing.expect(t, !valid)
}

// Verify pending direct text resolves to the resident replacement glyph.
@(test)
text_test_pending_codepoint_uses_replacement :: proc(t: ^testing.T) {
    state := Codepoint_Resolver_Test_State{replacement_id = 77}
    resolver := view_font.Font_Resolver{
        user_data = &state,
        resolve_codepoint = text_test_resolve_codepoint,
    }

    raster_request := view_font.Font_Raster_Request{
        key = .Regular, source_generation = 1,
        logical_size = 16, scene_pixels_per_logical_unit = 1,
        pixel_height = 16, policy = .Stb_Grayscale,
    }
    resolution := ui_text_resolve_codepoint(
        resolver, .Regular, 'α', raster_request)
    testing.expect(t, resolution.drawable)
    testing.expect_value(
        t, resolution.status, view_font.Font_Glyph_Resolve_Status.Pending)
    testing.expect_value(t, resolution.glyph.advance_x, i32(77))
    testing.expect_value(t, state.requested_codepoint, rune(0xfffd))
}

// Verify cached 26.6 offsets and advances scale from the shaping base size.
@(test)
text_test_cached_glyph_placement_uses_shaped_metrics :: proc(t: ^testing.T) {
    glyph := view_font.Shaped_Glyph{
        x_advance = 640,
        x_offset = 64,
        y_offset = -32,
    }

    placement := ui_text_cached_glyph_placement(glyph, 10, 20, 16, 32)

    testing.expect_value(t, placement.position.x, f32(10.5))
    testing.expect_value(t, placement.position.y, f32(19.75))
    testing.expect_value(t, placement.next_pen_x, f32(15))
}

// Verify cached JuliaMono glyphs use source columns instead of cumulative advances.
@(test)
text_test_cached_monospace_placement_uses_source_cluster :: proc(t: ^testing.T) {
    glyph := view_font.Shaped_Glyph{
        cluster = 3,
        x_advance = 700,
        x_offset = -32,
        y_offset = 64,
    }

    request := Cached_Monospace_Run_Draw{
        shaped = {position = {10, 20}, font_size = 16, base_pixel_size = 32},
        text = "α=>",
        column_advance = 8,
    }
    position, valid := ui_text_cached_monospace_glyph_placement(request, glyph)

    testing.expect(t, valid)
    testing.expect_value(t, position.x, f32(25.75))
    testing.expect_value(t, position.y, f32(20.5))
}

// Verify unlike ink bounds preserve one shared raster baseline.
@(test)
text_test_cached_run_line_top_uses_font_ascent :: proc(t: ^testing.T) {
    ordinary_top := ui_text_cached_run_line_top(10, 6, 24, 16, 32)
    punctuation_top := ui_text_cached_run_line_top(12, 2, 24, 16, 32)

    testing.expect_value(t, ordinary_top, f32(1))
    testing.expect_value(t, punctuation_top, ordinary_top)
}

// Verify one pending cached glyph rejects the complete run before drawing begins.
@(test)
text_test_cached_run_preflights_all_glyphs :: proc(t: ^testing.T) {
    state := Cached_Glyph_Resolver_Test_State{reject_glyph_id = 2}
    glyphs := []view_font.Shaped_Glyph{
        {glyph_id = 1, x_advance = 640},
        {glyph_id = 2, x_advance = 640},
    }
    resolver := view_font.Font_Resolver{
        user_data = &state,
        resolve_glyph = text_test_resolve_cached_glyph,
    }

    drawn := ui_text_cached_shaped_run({
        resolver = resolver, key = .Math_Regular, glyphs = glyphs,
        font_size = 32, base_pixel_size = 32})

    testing.expect(t, !drawn)
    testing.expect_value(t, state.calls, 2)
}