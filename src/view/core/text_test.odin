#+test
package view_core

import view_font "../font"

import "core:testing"

Codepoint_Resolver_Test_State :: struct {
    requested_codepoint: rune,
    replacement_id: u32,
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