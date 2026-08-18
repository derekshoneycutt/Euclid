package view_tests

import "core:testing"

import app_core "../../src/core"
import app_bridge "../../src/bridge"
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
    scrollbar := app_ui.build_vertical_scrollbar(panel, 480, 60, 360, 8, 24)
    testing.expect(t, scrollbar.has_scrollbar)
    testing.expect_value(t, scrollbar.track_rect.x, panel.x + panel.width - 8)
    testing.expect_value(t, scrollbar.thumb_height, scrollbar.thumb_rect.height)
}

seed_tree_node :: proc(
    node: ^app_core.Euclid_Julia_Animation_Interface,
    parent: ^app_core.Euclid_Julia_Animation_Interface,
    first_child: ^app_core.Euclid_Julia_Animation_Interface,
    next_sibling: ^app_core.Euclid_Julia_Animation_Interface,
    expanded: bool) {

    node^.parent = parent
    node^.first_child = first_child
    node^.next_sibling = next_sibling
    node^.is_expanded = expanded
}

@(test)
tree_row_count_respects_expansion_state :: proc(t: ^testing.T) {
    // Verifies visible tree row counting respects node expansion state and first-child expansion helper behavior.
    ji := app_core.Euclid_Julia_Interface{}
    nodes: [3]app_core.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_tail = &nodes[2]
    ji.animation_count = 3

    nodes[0].next_in_registry = &nodes[1]
    nodes[1].next_in_registry = &nodes[2]

    // root(0) -> child(1) -> sibling(2)
    seed_tree_node(&nodes[0], nil, &nodes[1], nil, true)
    seed_tree_node(&nodes[1], &nodes[0], nil, &nodes[2], false)
    seed_tree_node(&nodes[2], &nodes[0], nil, nil, false)

    count_expanded := app_ui.count_visible_tree_rows_all_roots(&ji)
    testing.expect_value(t, count_expanded, 3)

    nodes[0].is_expanded = false
    count_collapsed := app_ui.count_visible_tree_rows_all_roots(&ji)
    testing.expect_value(t, count_collapsed, 1)

    testing.expect_value(t, app_ui.expanded_first_child(&nodes[1]), nil)
    nodes[0].is_expanded = true
    testing.expect_value(t, app_ui.expanded_first_child(&nodes[0]), &nodes[1])
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
terminal_input_layout_wraps_multiline_utf8_caret :: proc(t: ^testing.T) {
    text := "abcd\nαβγδε"
    buffer := transmute([]u8)text

    first_wrap := app_ui.terminal_input_position(buffer, len(text), 4, 4)
    second_line_caret := app_ui.terminal_input_position(buffer, len(text), len(text), 4)

    testing.expect_value(t, first_wrap, app_ui.Terminal_Input_Position{1, 0})
    testing.expect_value(t, second_line_caret, app_ui.Terminal_Input_Position{2, 1})
    testing.expect_value(t, app_ui.terminal_input_row_count(buffer, len(text), len(text), 4), 3)
}

@(test)
terminal_input_cell_maps_to_utf8_byte_caret :: proc(t: ^testing.T) {
    text := "abcd\nαβγδε"
    buffer := transmute([]u8)text

    caret := app_ui.terminal_input_byte_offset_at(buffer, len(text), 4, 2, 1)

    testing.expect_value(t, caret, len(text))
}

@(test)
scratchpad_bottom_detection_uses_terminal_epsilon :: proc(t: ^testing.T) {
    testing.expect(t, app_ui.scratchpad_scroll_is_at_bottom(99.6, 100))
    testing.expect(t, !app_ui.scratchpad_scroll_is_at_bottom(99.0, 100))
}

@(test)
scratchpad_completion_payload_parses_and_applies :: proc(t: ^testing.T) {
    // Verifies completion payload parsing extracts start, end, and replacement text from the wire format.
    completion := app_ui.scratchpad_parse_completion_payload("2\n5\npoint!")
    testing.expect(t, completion.ok)
    testing.expect_value(t, completion.replace_start, 2)
    testing.expect_value(t, completion.replace_end, 5)
    testing.expect_value(t, completion.replacement, "point!")
}

@(test)
scratchpad_parse_non_negative_int_rejects_non_digits :: proc(t: ^testing.T) {
    // Confirms non-digit characters invalidate scratchpad non-negative integer parsing.
    _, ok := app_ui.scratchpad_parse_non_negative_int("12x")
    testing.expect(t, !ok)
}

@(test)
scratchpad_prompt_tracks_input_mode :: proc(t: ^testing.T) {
    testing.expect_value(t, app_ui.scratchpad_prompt(.Julia), "julia> ")
    testing.expect_value(t, app_ui.scratchpad_prompt(.Help), "help?> ")
}

@(test)
scratchpad_history_payload_restores_mode_and_text :: proc(t: ^testing.T) {
    history := app_ui.scratchpad_parse_history_payload("1\n@time")
    testing.expect(t, history.ok)
    testing.expect_value(t, history.mode, app_core.Scratchpad_Input_Mode.Help)
    testing.expect_value(t, history.text, "@time")

    missing_separator := app_ui.scratchpad_parse_history_payload("1@time")
    testing.expect(t, !missing_separator.ok)
    unknown_mode := app_ui.scratchpad_parse_history_payload("2\n@time")
    testing.expect(t, !unknown_mode.ok)
}

@(test)
scratchpad_question_mark_enters_help_mode :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{}
    app_ui.input_box_replace_text(
        ui_runtime.scratchpad_input[:], &ui_runtime.scratchpad_input_len,
        &ui_runtime.scratchpad_input_cursor, "?")

    changed := app_ui.apply_scratchpad_mode_transition(
        &ui_runtime, app_ui.Input_Box_Result{}, 0, 0)

    testing.expect(t, changed)
    testing.expect_value(t, ui_runtime.scratchpad_input_mode,
        app_core.Scratchpad_Input_Mode.Help)
    testing.expect_value(t, ui_runtime.scratchpad_input_len, 0)
    testing.expect_value(t, ui_runtime.scratchpad_input_cursor, 0)
}

@(test)
scratchpad_pasted_question_mark_stays_in_julia_mode :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{}
    app_ui.input_box_replace_text(
        ui_runtime.scratchpad_input[:], &ui_runtime.scratchpad_input_len,
        &ui_runtime.scratchpad_input_cursor, "?")

    changed := app_ui.apply_scratchpad_mode_transition(
        &ui_runtime, app_ui.Input_Box_Result{paste_applied = true}, 0, 0)

    testing.expect(t, !changed)
    testing.expect_value(t, ui_runtime.scratchpad_input_mode,
        app_core.Scratchpad_Input_Mode.Julia)
    testing.expect_value(t, ui_runtime.scratchpad_input_len, 1)
}

@(test)
scratchpad_empty_backspace_exits_help_mode :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{scratchpad_input_mode = .Help}

    changed := app_ui.apply_scratchpad_mode_transition(
        &ui_runtime, app_ui.Input_Box_Result{backspace_pressed = true}, 0, 0)

    testing.expect(t, changed)
    testing.expect_value(t, ui_runtime.scratchpad_input_mode,
        app_core.Scratchpad_Input_Mode.Julia)
}

seed_scratchpad_async_result :: proc(
    slot: ^app_bridge.Scratchpad_Async_Slot, text: string) {

    slot^.result_len = len(text)
    copy(slot^.result[:slot^.result_len], transmute([]u8)text)
}

@(test)
scratchpad_stale_submit_preserves_newer_input :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{}
    app_ui.input_box_replace_text(
        ui_runtime.scratchpad_input[:], &ui_runtime.scratchpad_input_len,
        &ui_runtime.scratchpad_input_cursor, "new input")
    ui_runtime.scratchpad_input_generation = 2
    ui_runtime.scratchpad_pending_submit_request_id = 9
    slot := app_bridge.Scratchpad_Async_Slot{
        kind = .Submit,
        request_id = 9,
        input_generation = 1,
        parse_result = app_bridge.SCRATCHPAD_PARSE_COMPLETE,
        succeeded = true,
    }

    app_ui.apply_scratchpad_async_result(&ui_runtime, &slot)

    testing.expect_value(t, string(ui_runtime.scratchpad_input[:ui_runtime.scratchpad_input_len]),
        "new input")
    testing.expect_value(t, ui_runtime.scratchpad_pending_submit_request_id, u64(0))
}

@(test)
scratchpad_incomplete_submit_appends_newline :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{}
    app_ui.input_box_replace_text(
        ui_runtime.scratchpad_input[:], &ui_runtime.scratchpad_input_len,
        &ui_runtime.scratchpad_input_cursor, "begin")
    ui_runtime.scratchpad_input_generation = 4
    slot := app_bridge.Scratchpad_Async_Slot{
        kind = .Submit,
        input_generation = 4,
        parse_result = app_bridge.SCRATCHPAD_PARSE_INCOMPLETE,
    }

    app_ui.apply_scratchpad_async_result(&ui_runtime, &slot)

    testing.expect_value(t, string(ui_runtime.scratchpad_input[:ui_runtime.scratchpad_input_len]),
        "begin\n")
    testing.expect_value(t, ui_runtime.scratchpad_input_generation, u64(5))
}

@(test)
scratchpad_completion_requires_latest_request :: proc(t: ^testing.T) {
    ui_runtime := app_core.Euclid_Ui_Runtime_State{}
    app_ui.input_box_replace_text(
        ui_runtime.scratchpad_input[:], &ui_runtime.scratchpad_input_len,
        &ui_runtime.scratchpad_input_cursor, "EuclidRep")
    ui_runtime.scratchpad_input_generation = 3
    ui_runtime.scratchpad_latest_completion_request_id = 12
    stale_slot := app_bridge.Scratchpad_Async_Slot{
        kind = .Complete, request_id = 11, input_generation = 3}
    seed_scratchpad_async_result(&stale_slot, "0\n9\nEuclidREPL")
    latest_slot := app_bridge.Scratchpad_Async_Slot{
        kind = .Complete, request_id = 12, input_generation = 3}
    seed_scratchpad_async_result(&latest_slot, "0\n9\nEuclidREPL")

    app_ui.apply_scratchpad_async_result(&ui_runtime, &stale_slot)
    testing.expect_value(t, string(ui_runtime.scratchpad_input[:ui_runtime.scratchpad_input_len]),
        "EuclidRep")

    app_ui.apply_scratchpad_async_result(&ui_runtime, &latest_slot)
    testing.expect_value(t, string(ui_runtime.scratchpad_input[:ui_runtime.scratchpad_input_len]),
        "EuclidREPL")
    testing.expect_value(t, ui_runtime.scratchpad_input_generation, u64(4))
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
    nodes: [2]app_core.Euclid_Julia_Animation_Interface
    ji.animation_head = &nodes[0]
    ji.animation_tail = &nodes[1]
    ji.animation_count = 2

    nodes[0].next_in_registry = &nodes[1]

    seed_tree_node(&nodes[0], nil, &nodes[1], nil, true)
    seed_tree_node(&nodes[1], &nodes[0], nil, nil, true)

    testing.expect_value(t, app_ui.count_visible_tree_rows_limited(&ji, &nodes[0], 1), 1)
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
    invalid_completion := app_ui.scratchpad_parse_completion_payload("1\n2")
    testing.expect(t, !invalid_completion.ok)
}

