package view_tests

import "core:testing"

import app_core "../../src/core"
import app_view_core "../../src/view/core"
import app_dynview "../../src/view/ui/dynview"
import app_ui "../../src/view/ui"

import rl "vendor:raylib"

@(test)
ui_regions_baseline_is_valid_and_consistent :: proc(t: ^testing.T) {
    // Verifies baseline UI region construction is internally consistent and matches fixed panel sizing contracts.
    regions := app_ui.compute_ui_regions(.Baseline)

    testing.expect(t, app_ui.validate_ui_regions(regions))
    testing.expect_value(t, regions.world_rect.width, app_ui.VIEW_WIDTH)
    testing.expect_value(t, regions.world_rect.height, app_ui.VIEW_HEIGHT)
    testing.expect_value(t, regions.tree_rect.x, app_ui.VIEW_WIDTH + app_ui.TREE_PANEL_PADDING)
    testing.expect_value(t, regions.text_rect.y, app_ui.VIEW_HEIGHT + app_ui.TREE_PANEL_PADDING)
    testing.expect_value(t, regions.settings_rect.width, regions.gif_rect.width)
    testing.expect_value(t, regions.settings_rect.height, regions.gif_rect.height)
    testing.expect(t, regions.scratchpad_rect.width >= 0)
    testing.expect(t, regions.scratchpad_rect.height >= 0)
}

@(test)
validate_ui_regions_rejects_negative_dimensions :: proc(t: ^testing.T) {
    // Ensures region validation fails when any panel rectangle has negative width or height.
    regions := app_core.Ui_Regions{}
    regions.world_rect = rl.Rectangle{0, 0, -1, 10}

    testing.expect(t, !app_ui.validate_ui_regions(regions))

    regions.world_rect = rl.Rectangle{0, 0, 1, 10}
    regions.tree_rect = rl.Rectangle{0, 0, 10, -1}
    testing.expect(t, !app_ui.validate_ui_regions(regions))
}

@(test)
scrollbar_thumb_math_clamps_and_positions_correctly :: proc(t: ^testing.T) {
    // Checks scrollbar thumb sizing and placement clamp correctly across top, bottom, and constructed panel geometry.
    thumb_h := app_ui.scrollbar_thumb_height(100, 1000, 24)
    testing.expect(t, thumb_h >= 24)
    testing.expect(t, thumb_h <= 100)

    y_top := app_ui.scrollbar_thumb_y(50, 100, thumb_h, 0, 300)
    y_bottom := app_ui.scrollbar_thumb_y(50, 100, thumb_h, 300, 300)
    testing.expect_value(t, y_top, f32(50))
    testing.expect_value(t, y_bottom, f32(150) - thumb_h)

    panel := rl.Rectangle{10, 20, 200, 120}
    track, thumb, built_thumb_h, has_scrollbar := app_ui.build_vertical_scrollbar(
        panel, 480, 60, 360, 8, 24)
    testing.expect(t, has_scrollbar)
    testing.expect_value(t, track.x, panel.x + panel.width - 8)
    testing.expect_value(t, built_thumb_h, thumb.height)
}

@(test)
text_wrapping_helpers_handle_empty_and_long_tokens :: proc(t: ^testing.T) {
    // Validates wrapping helpers handle empty input and long tokens while still advancing span boundaries.
    testing.expect_value(t, app_view_core.chars_per_text_row(0, 8), 1)
    testing.expect_value(t, app_view_core.count_wrapped_text_rows("", 20), 1)

    text := "supercalifragilistic"
    line_start, line_end, next_start := app_view_core.next_wrapped_text_span(text, 0, 4)

    testing.expect_value(t, line_start, 0)
    testing.expect(t, line_end > line_start)
    testing.expect(t, next_start > line_start)

    rows := app_view_core.count_wrapped_text_rows("aaaa bbbb cccc", 4)
    testing.expect(t, rows >= 3)
}

seed_tree_node :: proc(
    ji: ^app_core.Euclid_Julia_Interface,
    id: int,
    parent_id: int,
    first_child_id: int,
    next_sibling: int,
    expanded: bool) {
    ji.animations[id].parent_id = parent_id
    ji.animations[id].first_child_id = first_child_id
    ji.animations[id].next_sibling = next_sibling
    ji.animations[id].is_expanded = expanded
}

@(test)
tree_row_count_respects_expansion_state :: proc(t: ^testing.T) {
    // Verifies visible tree row counting respects node expansion state and first-child expansion helper behavior.
    ji := app_core.Euclid_Julia_Interface{}
    ji.next_animation_index = 3

    // root(0) -> child(1) -> sibling(2)
    seed_tree_node(&ji, 0, -1, 1, -1, true)
    seed_tree_node(&ji, 1, 0, -1, 2, false)
    seed_tree_node(&ji, 2, 0, -1, -1, false)

    count_expanded := app_ui.count_visible_tree_rows_all_roots(&ji)
    testing.expect_value(t, count_expanded, 3)

    ji.animations[0].is_expanded = false
    count_collapsed := app_ui.count_visible_tree_rows_all_roots(&ji)
    testing.expect_value(t, count_collapsed, 1)

    testing.expect_value(t, app_ui.expanded_first_child_id(false, 1), -1)
    testing.expect_value(t, app_ui.expanded_first_child_id(true, 1), 1)
}

@(test)
build_tree_view_panels_clamps_small_panels :: proc(t: ^testing.T) {
    // Confirms tiny tree panels still produce a fixed-height toolbar and non-negative list viewport dimensions.
    panel := rl.Rectangle{0, 0, 8, 8}
    toolbar, list := app_ui.build_tree_view_panels(panel)

    testing.expect(t, toolbar.height == app_ui.TREE_TOOLBAR_HEIGHT)
    testing.expect(t, list.width >= 0)
    testing.expect(t, list.height >= 0)
}

@(test)
input_box_utf8_helpers_preserve_codepoint_boundaries :: proc(t: ^testing.T) {
    // Ensures UTF-8 cursor movement, backspace, and replacement operations preserve codepoint boundaries.
    buffer: [32]u8
    text_len := 0
    caret := 0

    app_ui.input_box_replace_text(buffer[:], &text_len, &caret, "αβ")
    testing.expect_value(t, text_len, len("αβ"))
    testing.expect_value(t, caret, len("αβ"))

    prev_start := app_ui.input_box_prev_codepoint_start(buffer[:], 0, caret)
    testing.expect_value(t, prev_start, len("α"))

    app_ui.input_box_backspace_codepoint(buffer[:], &text_len, &caret)
    testing.expect_value(t, string(buffer[:text_len]), "α")
    testing.expect_value(t, caret, len("α"))

    replaced := app_ui.input_box_replace_byte_range(
        buffer[:],
        &text_len,
        &caret,
        0,
        text_len,
        "γ")
    testing.expect(t, replaced)
    testing.expect_value(t, string(buffer[:text_len]), "γ")
    testing.expect_value(t, caret, len("γ"))
}

@(test)
scratchpad_completion_payload_parses_and_applies :: proc(t: ^testing.T) {
    // Verifies completion payload parsing extracts start, end, and replacement text from the wire format.
    start, ending, replacement, ok := app_ui.scratchpad_parse_completion_payload("2\n5\npoint!")
    testing.expect(t, ok)
    testing.expect_value(t, start, 2)
    testing.expect_value(t, ending, 5)
    testing.expect_value(t, replacement, "point!")
}

@(test)
scratchpad_parse_non_negative_int_rejects_non_digits :: proc(t: ^testing.T) {
    // Confirms non-digit characters invalidate scratchpad non-negative integer parsing.
    _, ok := app_ui.scratchpad_parse_non_negative_int("12x")
    testing.expect(t, !ok)
}

@(test)
input_box_backspace_codepoint_removes_multibyte_cursor :: proc(t: ^testing.T) {
    // Checks backspace removes one full multibyte codepoint and updates caret to the previous codepoint start.
    buffer: [8]u8
    text_len := 0
    caret := 0

    app_ui.input_box_replace_text(buffer[:], &text_len, &caret, "αβ")
    caret = text_len
    app_ui.input_box_backspace_codepoint(buffer[:], &text_len, &caret)

    testing.expect_value(t, string(buffer[:text_len]), "α")
    testing.expect_value(t, caret, 2)
}

@(test)
tree_row_count_guard_stops_recursive_walks :: proc(t: ^testing.T) {
    // Verifies row counting guard limits recursive traversal depth to prevent runaway tree walks.
    ji := app_core.Euclid_Julia_Interface{}
    ji.next_animation_index = 2
    seed_tree_node(&ji, 0, -1, 1, -1, true)
    seed_tree_node(&ji, 1, 0, -1, -1, true)

    testing.expect_value(t, app_ui.count_visible_tree_rows_limited(&ji, 0, 1), 1)
}

@(test)
input_box_insert_text_at_caret_inserts_in_middle :: proc(t: ^testing.T) {
    // Ensures inserting text at an interior caret position shifts existing bytes and advances caret correctly.
    buffer: [32]u8
    text_len := 0
    caret := 0

    app_ui.input_box_replace_text(buffer[:], &text_len, &caret, "ab")
    caret = 1

    inserted := app_ui.input_box_insert_text_at_caret(
        buffer[:],
        &text_len,
        &caret,
        "XYZ")

    testing.expect(t, inserted)
    testing.expect_value(t, string(buffer[:text_len]), "aXYZb")
    testing.expect_value(t, caret, 4)
}

@(test)
input_box_insert_text_at_caret_truncates_on_utf8_boundary :: proc(t: ^testing.T) {
    // Validates insertion truncates safely at UTF-8 boundaries when destination capacity is limited.
    buffer: [5]u8
    text_len := 0
    caret := 0

    app_ui.input_box_replace_text(buffer[:], &text_len, &caret, "ab")

    inserted := app_ui.input_box_insert_text_at_caret(
        buffer[:],
        &text_len,
        &caret,
        "αβ")

    testing.expect(t, inserted)
    testing.expect_value(t, string(buffer[:text_len]), "abα")
    testing.expect_value(t, text_len, len("abα"))
    testing.expect_value(t, caret, len("abα"))
}

@(test)
input_box_insert_text_at_caret_noop_when_no_capacity :: proc(t: ^testing.T) {
    // Confirms insertion is rejected without mutating text when there is no remaining buffer capacity.
    buffer: [2]u8
    text_len := 0
    caret := 0

    app_ui.input_box_replace_text(buffer[:], &text_len, &caret, "ab")

    inserted := app_ui.input_box_insert_text_at_caret(
        buffer[:],
        &text_len,
        &caret,
        "Z")

    testing.expect(t, !inserted)
    testing.expect_value(t, string(buffer[:text_len]), "ab")
    testing.expect_value(t, text_len, 2)
    testing.expect_value(t, caret, 2)
}

@(test)
input_box_replace_byte_range_supports_utf8_safe_replacement :: proc(t: ^testing.T) {
    // Checks byte-range replacement swaps UTF-8 content and repositions caret to the end of replacement text.
    buffer: [16]u8
    text_len := 0
    caret := 0

    app_ui.input_box_replace_text(buffer[:], &text_len, &caret, "αβ")
    replaced := app_ui.input_box_replace_byte_range(
        buffer[:],
        &text_len,
        &caret,
        0,
        text_len,
        "γ")

    testing.expect(t, replaced)
    testing.expect_value(t, string(buffer[:text_len]), "γ")
    testing.expect_value(t, caret, len("γ"))
}

@(test)
scratchpad_completion_payload_rejects_missing_separator :: proc(t: ^testing.T) {
    // Verifies malformed completion payloads without all required separators are rejected.
    _, _, _, ok := app_ui.scratchpad_parse_completion_payload("1\n2")
    testing.expect(t, !ok)
}

@(test)
font_weight_resolution_prefers_heaviest_requested_flag :: proc(t: ^testing.T) {
    // Ensures font-weight resolution chooses the heaviest requested weight when multiple flags are set.
    flags := app_core.Font_Variant_Flags(
        u32(app_core.Font_Variant_Flags.Light) |
        u32(app_core.Font_Variant_Flags.Bold) |
        u32(app_core.Font_Variant_Flags.Italic))

    resolved := app_view_core.font_resolve_weight_from_flags(flags)
    testing.expect_value(t, resolved, app_core.Font_Weight.Bold)

    heavier := app_core.Font_Variant_Flags(
        u32(flags) |
        u32(app_core.Font_Variant_Flags.ExtraBold) |
        u32(app_core.Font_Variant_Flags.Black))
    resolved_heavier := app_view_core.font_resolve_weight_from_flags(heavier)
    testing.expect_value(t, resolved_heavier, app_core.Font_Weight.Black)
}

@(test)
dynview_text_span_and_script_attach_helpers_respect_bounds :: proc(t: ^testing.T) {
    // Validates dynview text span extraction bounds checks and script-attach plain-text fallback behavior.
    buffer := app_core.Ui_Dynview_Command_Buffer{}
    text := "abc"
    for i in 0..<len(text) {
        buffer.text_bytes[i] = u8(text[i])
    }
    buffer.text_bytes_len = len(text)

    span := app_dynview.text_span_from_buffer(&buffer, 1, 2)
    testing.expect_value(t, span, "bc")

    out_of_bounds := app_dynview.text_span_from_buffer(&buffer, 2, 5)
    testing.expect_value(t, out_of_bounds, "")

    cmd := app_core.Ui_Dynview_Command{
        script_base_text_offset = 0,
        script_base_text_len = 3,
        script_sup_text_offset = 1,
        script_sup_text_len = 1,
    }
    plain_text := app_dynview.script_attach_plain_text(&buffer, cmd)
    testing.expect_value(t, plain_text, "abc")
}

@(test)
dynview_layout_prepare_style_placement_forces_line_break_and_indent :: proc(t: ^testing.T) {
    // Verifies style placement can force a line break and apply configured indentation at the next line start.
    cache := new(app_core.Ui_Dynview_Compile_Cache)
    defer free(cache)
    state := app_dynview.Dynview_Layout_State{col = 2, line_index = 0}
    acc := app_dynview.Dynview_Layout_Line_Accumulator{item_start = 0, item_count = 1}
    style := app_dynview.Dynview_Text_Style{force_line_start = true, indent_cols = 3}

    status := app_dynview.layout_prepare_style_placement(cache, &state, &acc, style, 12)

    testing.expect_value(t, status, app_dynview.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache.layout_line_count, 1)
    testing.expect_value(t, state.line_index, 1)
    testing.expect_value(t, state.col, 3)
    testing.expect_value(t, cache.layout_lines[0].item_count, 1)
}

@(test)
dynview_layout_push_item_records_block_and_column_metadata :: proc(t: ^testing.T) {
    // Confirms pushed layout items capture block metadata and advance line-column bookkeeping correctly.
    cache := new(app_core.Ui_Dynview_Compile_Cache)
    defer free(cache)
    state := app_dynview.Dynview_Layout_State{active_block_id = 7, line_index = 2, col = 1}
    acc := app_dynview.Dynview_Layout_Line_Accumulator{}
    item := app_core.Ui_Dynview_Layout_Item{
        style_id = app_dynview.DYNVIEW_STYLE_OUTPUT,
        col_span = 3,
        ascent = 8,
        descent = 2,
    }

    status := app_dynview.layout_push_item(cache, &state, &acc, item)

    testing.expect_value(t, status, app_dynview.DYNVIEW_STATUS_OK)
    testing.expect_value(t, cache.layout_item_count, 1)
    testing.expect_value(t, cache.layout_items[0].block_id, 7)
    testing.expect_value(t, cache.layout_items[0].col_start, 1)
    testing.expect_value(t, state.col, 4)
    testing.expect_value(t, acc.item_count, 1)
}

@(test)
dynview_layout_consume_text_run_wraps_and_places_segments :: proc(t: ^testing.T) {
    // Checks wrapped text-run consumption emits layout items and lines with a valid reported last line index.
    cache := new(app_core.Ui_Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_panel_width = 48
    cache.last_wrap_advance = 8
    cache.last_font_size = 12

    state := app_dynview.Dynview_Layout_State{}
    acc := app_dynview.Dynview_Layout_Line_Accumulator{}
    cmd := app_core.Ui_Dynview_Command{style_id = app_dynview.DYNVIEW_STYLE_OUTPUT}
    style := app_dynview.style_by_id(app_dynview.DYNVIEW_STYLE_OUTPUT)

    status, last_line := app_dynview.layout_consume_text_run(
        cache,
        &state,
        &acc,
        cmd,
        "hello world",
        style,
        12)

    testing.expect_value(t, status, app_dynview.DYNVIEW_STATUS_OK)
    testing.expect(t, cache.layout_item_count > 0)
    testing.expect(t, cache.layout_line_count > 0)
    testing.expect(t, last_line >= 0)
}

@(test)
dynview_math_helpers_scale_script_geometry :: proc(t: ^testing.T) {
    // Ensures script math helper outputs produce sensible ascent, descent, offsets, and visual padding values.
    style := app_dynview.style_by_id(app_dynview.DYNVIEW_STYLE_BOLD)
    ascent, descent := app_dynview.style_ascent_descent(style, 12)

    testing.expect(t, ascent > descent)
    testing.expect(t, ascent > 8)

    script_font_size, sup_raise_px, sub_drop_px := app_dynview.script_draw_offsets(12, 1.0, 0.25, 0.25)
    top_pad, bottom_pad := app_dynview.script_visual_padding(script_font_size)

    testing.expect(t, script_font_size > 1.0)
    testing.expect(t, sup_raise_px >= 0)
    testing.expect(t, sub_drop_px >= 0)
    testing.expect(t, top_pad > 0)
    testing.expect(t, bottom_pad > 0)
}

@(test)
dynview_math_size_helpers_scale_with_content_and_kind :: proc(t: ^testing.T) {
    // Verifies delimiter and large-operator sizing helpers scale with content height and operator kind.
    style := app_dynview.style_by_id(app_dynview.DYNVIEW_STYLE_OUTPUT)

    width_none := app_dynview.stretch_delimiter_width(style, 8, 16, 10, app_dynview.DELIMITER_KIND_NONE)
    width_paren := app_dynview.stretch_delimiter_width(style, 8, 16, 50, app_dynview.DELIMITER_KIND_LEFT_PAREN)
    width_bigger := app_dynview.stretch_delimiter_width(style, 8, 16, 120, app_dynview.DELIMITER_KIND_LEFT_PAREN)

    testing.expect_value(t, width_none, f32(0))
    testing.expect(t, width_paren > 0)
    testing.expect(t, width_bigger > width_paren)

    glyph_scale_sum := app_dynview.large_op_glyph_scale(app_dynview.LARGE_OP_KIND_SUM)
    glyph_scale_int := app_dynview.large_op_glyph_scale(app_dynview.LARGE_OP_KIND_INT)
    limit_scale := app_dynview.large_op_limit_scale(0.8)
    gap := app_dynview.large_op_limit_gap_for_kind(app_dynview.LARGE_OP_KIND_INT, 16, 0.25)

    testing.expect(t, glyph_scale_sum > 1)
    testing.expect(t, glyph_scale_int > glyph_scale_sum)
    testing.expect(t, limit_scale > 0)
    testing.expect(t, gap > 0)
}

@(test)
dynview_measure_math_program_aggregates_child_metrics :: proc(t: ^testing.T) {
    // Confirms math program measurement aggregates child command metrics into non-zero outer dimensions.
    cache := new(app_core.Ui_Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_wrap_advance = 8
    cache^.math_program_count = 1
    cache^.math_command_count = 1

    buffer := app_core.Ui_Dynview_Command_Buffer{}
    buffer.text_bytes[0] = 'a'
    buffer.text_bytes[1] = 'b'
    buffer.text_bytes_len = 2

    cache^.math_commands[0] = app_core.Ui_Dynview_Command{
        kind = .TextRun,
        style_id = app_dynview.DYNVIEW_STYLE_OUTPUT,
        text_offset = 0,
        text_len = 2,
    }

    program := &cache^.math_programs[0]
    program^.valid = true
    program^.command_start = 0
    program^.command_count = 1

    ok := app_dynview.measure_math_program(cache, &buffer, program, 12)

    testing.expect(t, ok)
    testing.expect(t, program.draw_width > 0)
    testing.expect(t, program.ascent > 0)
    testing.expect(t, program.descent > 0)
}

@(test)
dynview_math_spacing_helpers_produce_stable_positive_sizes :: proc(t: ^testing.T) {
    // Checks fraction and radical spacing helpers return positive values and scale upward with larger inputs.
    side_pad_small := app_dynview.fraction_side_padding(10, 4)
    side_pad_large := app_dynview.fraction_side_padding(24, 10)
    vert_gap_small := app_dynview.fraction_vertical_gap(10)
    vert_gap_large := app_dynview.fraction_vertical_gap(24)

    testing.expect(t, side_pad_small > 0)
    testing.expect(t, side_pad_large > side_pad_small)
    testing.expect(t, vert_gap_small > 0)
    testing.expect(t, vert_gap_large > vert_gap_small)

    lead_width := app_dynview.radical_lead_width(16, 8)
    front_pad, back_pad := app_dynview.radical_side_paddings(16, 8)
    testing.expect(t, lead_width > 0)
    testing.expect(t, front_pad > 0)
    testing.expect(t, back_pad > 0)
}

@(test)
dynview_large_operator_gap_for_integral_is_tighter_than_sum :: proc(t: ^testing.T) {
    // Verifies integral stacked-limit gap is intentionally tighter than the sum/product stacked-limit gap.
    gap_sum := app_dynview.large_op_limit_gap_for_kind(app_dynview.LARGE_OP_KIND_SUM, 16, 0.25)
    gap_int := app_dynview.large_op_limit_gap_for_kind(app_dynview.LARGE_OP_KIND_INT, 16, 0.25)

    testing.expect(t, gap_sum > 0)
    testing.expect(t, gap_int > 0)
    testing.expect(t, gap_int < gap_sum)
}

@(test)
dynview_measure_math_program_rejects_invalid_shapes :: proc(t: ^testing.T) {
    // Ensures math program measurement rejects invalid or out-of-range command windows.
    cache := new(app_core.Ui_Dynview_Compile_Cache)
    defer free(cache)

    buffer := app_core.Ui_Dynview_Command_Buffer{}

    invalid_program := app_core.Ui_Dynview_Math_Program{}
    invalid_program.valid = false
    testing.expect(t, !app_dynview.measure_math_program(cache, &buffer, &invalid_program, 12))

    invalid_program.valid = true
    invalid_program.command_start = 0
    invalid_program.command_count = 0
    testing.expect(t, !app_dynview.measure_math_program(cache, &buffer, &invalid_program, 12))

    cache^.math_command_count = 1
    invalid_program.command_start = 1
    invalid_program.command_count = 1
    testing.expect(t, !app_dynview.measure_math_program(cache, &buffer, &invalid_program, 12))
}

@(test)
dynview_measure_math_program_sums_multiple_command_widths :: proc(t: ^testing.T) {
    // Confirms measured width increases when additional child commands are included in the same math program.
    cache := new(app_core.Ui_Dynview_Compile_Cache)
    defer free(cache)
    cache^.last_wrap_advance = 8
    cache^.math_program_count = 2
    cache^.math_command_count = 2

    buffer := app_core.Ui_Dynview_Command_Buffer{}
    buffer.text_bytes[0] = 'a'
    buffer.text_bytes[1] = 'b'
    buffer.text_bytes[2] = 'c'
    buffer.text_bytes_len = 3

    cache^.math_commands[0] = app_core.Ui_Dynview_Command{
        kind = .TextRun,
        style_id = app_dynview.DYNVIEW_STYLE_OUTPUT,
        text_offset = 0,
        text_len = 2,
    }
    cache^.math_commands[1] = app_core.Ui_Dynview_Command{
        kind = .TextRun,
        style_id = app_dynview.DYNVIEW_STYLE_OUTPUT,
        text_offset = 2,
        text_len = 1,
    }

    one_cmd := &cache^.math_programs[0]
    one_cmd^.valid = true
    one_cmd^.command_start = 0
    one_cmd^.command_count = 1

    two_cmd := &cache^.math_programs[1]
    two_cmd^.valid = true
    two_cmd^.command_start = 0
    two_cmd^.command_count = 2

    ok_one := app_dynview.measure_math_program(cache, &buffer, one_cmd, 12)
    ok_two := app_dynview.measure_math_program(cache, &buffer, two_cmd, 12)

    testing.expect(t, ok_one)
    testing.expect(t, ok_two)
    testing.expect(t, two_cmd.draw_width > one_cmd.draw_width)
}

@(test)
dynview_reset_cache_clears_layout_state :: proc(t: ^testing.T) {
    // Verifies layout cache reset clears counters, aggregate metrics, and layout validity state.
    cache := new(app_core.Ui_Dynview_Compile_Cache)
    defer free(cache)
    cache^.layout_line_count = 2
    cache.layout_item_count = 3
    cache.layout_total_height = 9
    cache.layout_average_line_height = 4
    cache.layout_is_valid = true

    app_dynview.layout_reset_cache(cache)

    testing.expect_value(t, cache.layout_line_count, 0)
    testing.expect_value(t, cache.layout_item_count, 0)
    testing.expect_value(t, cache.layout_total_height, f32(0))
    testing.expect_value(t, cache.layout_average_line_height, f32(0))
    testing.expect(t, !cache.layout_is_valid)
}

@(test)
dynview_custom_font_style_flags_decode_correctly :: proc(t: ^testing.T) {
    // Checks custom-font style ids decode expected flags and non-custom ids do not use that decoding path.
    custom_flags := app_core.Font_Variant_Flags(
        u32(app_core.Font_Variant_Flags.Light) |
        u32(app_core.Font_Variant_Flags.Bold) |
        u32(app_core.Font_Variant_Flags.Italic))

    style_id := app_dynview.DYNVIEW_STYLE_CUSTOM_FONT | i32(u32(custom_flags) & u32(app_dynview.DYNVIEW_STYLE_CUSTOM_FONT_MASK))
    style, ok := app_dynview.style_from_custom_font_flags(style_id)

    testing.expect(t, ok)
    testing.expect(t, style.italic)
    testing.expect_value(t, style.font_flags, custom_flags)
    testing.expect_value(t, style.wrap_scale, f32(1.0))
    testing.expect_value(t, style.line_height_multiplier, f32(1.0))

    // Non-custom style ids should not decode through the custom-font flag path.
    _, normal_ok := app_dynview.style_from_custom_font_flags(app_dynview.DYNVIEW_STYLE_OUTPUT)
    testing.expect(t, !normal_ok)
}
