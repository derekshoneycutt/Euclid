#+test
package view_core

import view_font "../font"

import "core:testing"

Codepoint_Resolver_Test_State :: struct {
    requested_codepoint: rune,
    replacement_id: u32,
}

Cached_Glyph_Resolver_Test_State :: struct {
    calls: int,
    reject_glyph_id: u32,
}

// Reject one requested glyph so cached drawing can prove atomic preflight fallback.
text_test_resolve_cached_glyph :: proc(
    user_data: rawptr, key: view_font.Font_Key,
    glyph_id: u32) -> (view_font.Resolved_Glyph, bool) {

    _ = key
    state := cast(^Cached_Glyph_Resolver_Test_State)user_data
    state^.calls += 1
    return {}, glyph_id != state^.reject_glyph_id
}

// Return pending for the requested rune and a resident sentinel for U+FFFD.
text_test_resolve_codepoint :: proc(
    user_data: rawptr, key: view_font.Font_Key,
    codepoint: rune) -> (
    view_font.Resolved_Glyph, view_font.Font_Glyph_Resolve_Status) {

    state := cast(^Codepoint_Resolver_Test_State)user_data
    state.requested_codepoint = codepoint
    if codepoint == rune(0xfffd) {
        return {advance_x = i32(state.replacement_id), base_size = 32}, .Resident
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

    resolution := ui_text_resolve_codepoint(resolver, .Regular, 'α')
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