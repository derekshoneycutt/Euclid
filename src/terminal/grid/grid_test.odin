#+test
package termgrid

import "core:mem"
import "core:testing"
import "core:unicode/utf8"
import termmodel "../model"
import termpalette "../palette"

Scrollback_Test_State :: struct {
    rows: [8][8]Cell,
    widths: [8]int,
    wrapped: [8]bool,
    shell_markers: [8]termmodel.Shell_Row_Markers,
    count: int,
}

Cell_Expectation :: struct {
    text: string,
    width: u8,
    continuation: bool,
}

// One malformed UTF-8 fixture and its maximal-subpart replacement count.
Invalid_Utf8_Fixture :: struct {
    bytes: [4]u8,
    byte_count: int,
    replacement_count: u64,
}

// Run one malformed UTF-8 fixture and verify deterministic recovery.
termgrid_test_invalid_utf8_fixture :: proc(
    t: ^testing.T, fixture: ^Invalid_Utf8_Fixture) {
    grid: Grid
    testing.expect(t, grid_init(&grid, 8, 2, allocator = context.allocator))
    testing.expect(t, grid_write(&grid,
        transmute(string)fixture.bytes[:fixture.byte_count]))
    testing.expect(t, grid_write(&grid, "A"))
    grid_finish_input(&grid)
    testing.expect_value(t, grid.invalid_utf8_count, fixture.replacement_count)
    testing.expect_value(t,
        cell_text(&grid.rows[0].cells[int(fixture.replacement_count)]), "A")
    grid_destroy(&grid)
}

// Copy one evicted row into fixed test-owned history before the callback returns.
test_scrollback_commit :: proc(
    user_data: rawptr, cells: []Cell, metadata: Scrollback_Row_Commit) {
    state := cast(^Scrollback_Test_State)user_data
    copy(state.rows[state.count][:], cells)
    state.widths[state.count] = len(cells)
    state.wrapped[state.count] = metadata.wrapped
    state.shell_markers[state.count] = metadata.shell_markers
    state.count += 1
}

// Compare one grid cell with a compact expected text and width description.
test_expect_cell :: proc(
    t: ^testing.T, grid: ^Grid, row, column: int, expected: Cell_Expectation) {

    cell := &grid.rows[row].cells[column]
    testing.expect_value(t, cell_text(cell), expected.text)
    testing.expect_value(t, cell.width, expected.width)
    testing.expect_value(t, cell.continuation, expected.continuation)
}

// Verify fixed allocation, stable row slices, style storage, and snapshot ownership.
@(test)
termgrid_test_fixed_storage_and_snapshot :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(
        &grid, 4, 2, allocator = context.allocator))
    testing.expect_value(t, len(grid.cells), 8)
    testing.expect_value(t, len(grid.rows), 2)
    testing.expect(t, raw_data(grid.rows[1].cells) == &grid.cells[4])

    style := Cell_Style{
        foreground = termpalette.terminal_color_direct(0x11223344),
        font_weight = .Bold,
        italic = true,
    }
    grid_set_style(&grid, style)
    testing.expect(t, grid_write(&grid, "A"))

    snapshot: Snapshot
    testing.expect(t, snapshot_init(
        &grid, &snapshot, context.allocator))
    testing.expect_value(t, snapshot.columns, 4)
    testing.expect_value(t, snapshot.row_count, 2)
    testing.expect_value(t, snapshot.cursor, Cursor{column = 1})
    testing.expect_value(t, snapshot.cells[0].style, style)
    testing.expect(t, snapshot.rows[0].dirty)
    testing.expect_value(t, snapshot.rows[0].dirty_start, 0)
    testing.expect_value(t, snapshot.rows[0].dirty_end, 1)

    snapshot_destroy(&snapshot)
    grid_destroy(&grid)
    testing.expect_value(t, len(grid.cells), 0)
}

// Verify printable text, delayed wrapping, CR, BS, and tab behavior.
@(test)
termgrid_test_printable_wrap_and_controls :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(
        &grid, 4, 2, allocator = context.allocator))
    defer grid_destroy(&grid)

    testing.expect(t, grid_write(&grid, "abcdE"))
    testing.expect_value(t, grid.cursor, Cursor{row = 1, column = 1})
    testing.expect(t, grid.rows[0].wrapped)
    test_expect_cell(t, &grid, 0, 3, {text = "d", width = 1})
    test_expect_cell(t, &grid, 1, 0, {text = "E", width = 1})

    testing.expect(t, grid_write(&grid, "\rZ\bY\tQ"))
    test_expect_cell(t, &grid, 1, 0, {text = "Y", width = 1})
    test_expect_cell(t, &grid, 1, 3, {text = "Q", width = 1})
}

// Verify every UTF-8 byte boundary produces the same cells as contiguous input.
@(test)
termgrid_test_chunked_utf8_matches_contiguous_input :: proc(t: ^testing.T) {
    contiguous: Grid
    chunked: Grid
    testing.expect(t, grid_init(
        &contiguous, 8, 2, allocator = context.allocator))
    testing.expect(t, grid_init(
        &chunked, 8, 2, allocator = context.allocator))
    defer grid_destroy(&contiguous)
    defer grid_destroy(&chunked)

    text := "A界e\u0301🙂Z"
    testing.expect(t, grid_write(&contiguous, text))
    for byte in transmute([]u8)text {
        part := [1]u8{byte}
        testing.expect(t, grid_write(&chunked, transmute(string)part[:]))
    }

    for cell, index in contiguous.cells {
        testing.expect_value(t, cell, chunked.cells[index])
    }
    testing.expect_value(t, contiguous.cursor, chunked.cursor)
    testing.expect_value(t, contiguous.pending_utf8_len, 0)
    testing.expect_value(t, chunked.pending_utf8_len, 0)
}

// Verify wide leaders, continuations, combining clusters, and overwrite cleanup.
@(test)
termgrid_test_wide_and_combining_cells_preserve_invariants :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(
        &grid, 6, 2, allocator = context.allocator))
    defer grid_destroy(&grid)

    testing.expect(t, grid_write(&grid, "界e\u0301"))
    test_expect_cell(t, &grid, 0, 0, {text = "界", width = 2})
    test_expect_cell(t, &grid, 0, 1, {text = "", width = 0, continuation = true})
    test_expect_cell(t, &grid, 0, 2, {text = "e\u0301", width = 1})
    testing.expect_value(t, grid.cursor.column, 3)

    testing.expect(t, grid_write(&grid, "\rX"))
    test_expect_cell(t, &grid, 0, 0, {text = "X", width = 1})
    test_expect_cell(t, &grid, 0, 1, {text = "", width = 0})
}

// Verify grid resize preserves the left and bottom intersection transactionally.
@(test)
termgrid_test_resize_grow_and_bottom_anchored_shrink :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(&grid, 4, 3, allocator = context.allocator))
    defer grid_destroy(&grid)
    testing.expect(t, grid_write(&grid, "1111\r\n2222\r\n3333"))

    grown, grow_result := grid_prepare_resize(&grid, 6, 4, context.allocator)
    testing.expect_value(t, grow_result, Grid_Resize_Result.Prepared)
    test_expect_cell(t, &grown.grid, 0, 0, {text = "1", width = 1})
    test_expect_cell(t, &grown.grid, 2, 0, {text = "3", width = 1})
    test_expect_cell(t, &grown.grid, 3, 0, {text = "", width = 0})
    grid_discard_prepared_resize(&grown)

    shrunk, shrink_result := grid_prepare_resize(&grid, 3, 2, context.allocator)
    testing.expect_value(t, shrink_result, Grid_Resize_Result.Prepared)
    testing.expect(t, grid_commit_resize(&grid, &shrunk))
    test_expect_cell(t, &grid, 0, 0, {text = "2", width = 1})
    test_expect_cell(t, &grid, 1, 0, {text = "3", width = 1})
    testing.expect_value(t, grid.cursor, Cursor{row = 1, column = 2})
    for row in grid.rows {
        testing.expect(t, row.dirty)
        testing.expect_value(t, row.dirty_end, 3)
    }
}

// Verify resize preserves both committed cell handles and active write metadata.
@(test)
termgrid_test_resize_preserves_hyperlinks :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(&grid, 3, 2, allocator = context.allocator))
    defer grid_destroy(&grid)
    handle := termmodel.Hyperlink_Handle(0x10001)
    grid.hyperlink = handle
    testing.expect(t, grid_write(&grid, "link"))

    prepared, result := grid_prepare_resize(&grid, 4, 3, context.allocator)
    testing.expect_value(t, result, Grid_Resize_Result.Prepared)
    testing.expect(t, grid_commit_resize(&grid, &prepared))
    testing.expect_value(t, grid.hyperlink, handle)
    testing.expect_value(t, grid.rows[1].cells[0].hyperlink, handle)
}

// Verify resize repairs wide fragments and failed preparation leaves state untouched.
@(test)
termgrid_test_resize_repairs_wide_boundary_and_failure_is_atomic :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(&grid, 4, 2, allocator = context.allocator))
    defer grid_destroy(&grid)
    testing.expect(t, grid_write(&grid, "AB界"))
    before: Snapshot
    testing.expect(t, snapshot_init(&grid, &before, context.allocator))
    defer snapshot_destroy(&before)

    failure_storage: [1]byte
    failure_arena: mem.Arena
    mem.arena_init(&failure_arena, failure_storage[:])
    failing_allocator := mem.arena_allocator(&failure_arena)
    failed, failed_result := grid_prepare_resize(&grid, 5, 3, failing_allocator)
    testing.expect_value(t, failed_result, Grid_Resize_Result.Allocation_Failed)
    testing.expect(t, !failed.ready)
    for cell, index in grid.cells {
        testing.expect_value(t, cell, before.cells[index])
    }
    testing.expect_value(t, grid.cursor, before.cursor)

    resized, resize_result := grid_prepare_resize(&grid, 3, 2, context.allocator)
    testing.expect_value(t, resize_result, Grid_Resize_Result.Prepared)
    testing.expect(t, grid_commit_resize(&grid, &resized))
    test_expect_cell(t, &grid, 0, 2, {text = "", width = 0})
    _, unchanged := grid_prepare_resize(&grid, 3, 2, context.allocator)
    testing.expect_value(t, unchanged, Grid_Resize_Result.Unchanged)
}

// Verify a base-plus-ZWJ-plus-base emoji cluster retains one wide cell pair.
@(test)
termgrid_test_zwj_sequence_remains_one_cluster :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(
        &grid, 6, 2, allocator = context.allocator))
    defer grid_destroy(&grid)

    testing.expect(t, grid_write(&grid, "👩‍💻"))

    test_expect_cell(t, &grid, 0, 0, {text = "👩‍💻", width = 2})
    test_expect_cell(
        t, &grid, 0, 1, {text = "", width = 0, continuation = true})
    testing.expect_value(t, grid.cursor.column, 2)
}

// Verify ambiguous width is immutable grid policy preserved by replacement grids.
@(test)
termgrid_test_ambiguous_width_modes_survive_resize :: proc(t: ^testing.T) {
    narrow: Grid
    wide: Grid
    testing.expect(t, grid_init(
        &narrow, 6, 2, allocator = context.allocator))
    testing.expect(t, grid_init(
        &wide, 6, 2, allocator = context.allocator,
        options = {ambiguous_width = .Wide}))
    defer grid_destroy(&narrow)
    defer grid_destroy(&wide)

    testing.expect(t, grid_write(&narrow, "·"))
    testing.expect(t, grid_write(&wide, "·"))
    test_expect_cell(t, &narrow, 0, 0, {text = "·", width = 1})
    test_expect_cell(t, &wide, 0, 0, {text = "·", width = 2})

    resized, result := grid_prepare_resize(&wide, 8, 3, context.allocator)
    testing.expect_value(t, result, Grid_Resize_Result.Prepared)
    testing.expect_value(t,
        resized.grid.editing.ambiguous_width, Ambiguous_Width_Mode.Wide)
    grid_discard_prepared_resize(&resized)
}

// Verify generated Unicode properties drive terminal scalar width in both modes.
@(test)
termgrid_test_unicode_17_width_properties :: proc(t: ^testing.T) {
    testing.expect_value(t, UNICODE_PROPERTY_VERSION, "17.0.0")
    testing.expect_value(t, grid_rune_width('A'), u8(1))
    testing.expect_value(t, grid_rune_width('界'), u8(2))
        testing.expect_value(t, grid_rune_width('·'), u8(1))
        testing.expect_value(t, grid_rune_width('·', .Wide), u8(2))
        testing.expect_value(t, grid_rune_width('\u0301'), u8(0))
    testing.expect_value(t, grid_rune_width('🙂'), u8(2))
}

// Verify flags, keycaps, modifiers, selectors, and ZWJ families stay one wide cluster.
@(test)
termgrid_test_emoji_sequences_preserve_terminal_geometry :: proc(t: ^testing.T) {
    fixtures := [?]string{"🇺🇸", "1️⃣", "👍🏽", "❤️", "👩‍👩‍👧‍👦"}
    for fixture in fixtures {
        grid: Grid
        testing.expect(t, grid_init(
            &grid, 8, 2, allocator = context.allocator))
        testing.expect(t, grid_write(&grid, fixture))
        test_expect_cell(t, &grid, 0, 0, {text = fixture, width = 2})
        test_expect_cell(
            t, &grid, 0, 1, {text = "", width = 0, continuation = true})
        testing.expect_value(t, grid.cursor.column, 2)
        grid_destroy(&grid)
    }
}

// Verify wide Unicode clusters wrap before the final column in either width mode.
@(test)
termgrid_test_unicode_width_modes_wrap_atomically :: proc(t: ^testing.T) {
    narrow: Grid
    wide: Grid
    testing.expect(t, grid_init(
        &narrow, 3, 2, allocator = context.allocator))
    testing.expect(t, grid_init(
        &wide, 3, 2, allocator = context.allocator,
        options = {ambiguous_width = .Wide}))
    defer grid_destroy(&narrow)
    defer grid_destroy(&wide)

    testing.expect(t, grid_write(&narrow, "AB界"))
    testing.expect(t, grid_write(&wide, "AB·"))
    test_expect_cell(t, &narrow, 1, 0, {text = "界", width = 2})
    test_expect_cell(t, &wide, 1, 0, {text = "·", width = 2})
    testing.expect(t, narrow.rows[0].wrapped)
    testing.expect(t, wide.rows[0].wrapped)
}

// Verify late emoji presentation relocates a final-column base before widening.
@(test)
termgrid_test_keycap_promotion_wraps_complete_cluster :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(
        &grid, 3, 2, allocator = context.allocator))
    defer grid_destroy(&grid)

    testing.expect(t, grid_write(&grid, "AB1️⃣"))
    test_expect_cell(t, &grid, 0, 2, {text = "", width = 0})
    test_expect_cell(t, &grid, 1, 0, {text = "1️⃣", width = 2})
    test_expect_cell(
        t, &grid, 1, 1, {text = "", width = 0, continuation = true})
    testing.expect(t, grid.rows[0].wrapped)
    testing.expect_value(t, grid.cursor, Cursor{row = 1, column = 2})
}

// Verify primary scrolling commits each exact evicted row once before mutation.
@(test)
termgrid_test_scrolling_commits_each_evicted_row_once :: proc(t: ^testing.T) {
    history: Scrollback_Test_State
    grid: Grid
    sink := Scrollback_Sink{
        user_data = &history,
        commit = test_scrollback_commit,
    }
    testing.expect(t, grid_init(
        &grid, 3, 2, context.allocator, {scrollback = sink}))
    defer grid_destroy(&grid)

    testing.expect(t, grid_write(&grid, "one\r\ntwo\r\nx"))
    testing.expect_value(t, history.count, 1)
    testing.expect_value(t, history.widths[0], 3)
    testing.expect(t, !history.wrapped[0])
    testing.expect_value(t, cell_text(&history.rows[0][0]), "o")
    testing.expect_value(t, cell_text(&history.rows[0][1]), "n")
    testing.expect_value(t, cell_text(&history.rows[0][2]), "e")
    test_expect_cell(t, &grid, 0, 0, {text = "t", width = 1})
    test_expect_cell(t, &grid, 1, 0, {text = "x", width = 1})
}

// Verify autowrap provenance survives a grid-to-scrollback boundary.
@(test)
termgrid_test_autowrap_retains_semantic_line_provenance :: proc(t: ^testing.T) {
    history: Scrollback_Test_State
    grid: Grid
    testing.expect(t, grid_init(&grid, 3, 2, context.allocator, {
        scrollback = {user_data = &history, commit = test_scrollback_commit},
    }))
    defer grid_destroy(&grid)
    line_id := grid.rows[0].logical_line_id
    testing.expect(t, grid_write(&grid, "abcdefg"))
    testing.expect_value(t, history.count, 1)
    testing.expect_value(t, grid.rows[0].logical_line_id, line_id)
    testing.expect_value(t, grid.rows[0].grapheme_offset, u32(3))
    testing.expect_value(t, grid.rows[1].logical_line_id, line_id)
    testing.expect_value(t, grid.rows[1].grapheme_offset, u32(6))
}

// Verify character edits repair wide pairs and move hyperlinks and shell markers.
@(test)
termgrid_test_character_edits_preserve_metadata_invariants :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(&grid, 8, 2, allocator = context.allocator))
    defer grid_destroy(&grid)
    grid.hyperlink = termmodel.Hyperlink_Handle(0x10001)
    testing.expect(t, grid_write(&grid, "A界BCD"))
    grid.rows[0].shell_markers.present[.Command] = true
    grid.rows[0].shell_markers.columns[.Command] = 4

    grid_insert_cells(&grid, 0, 1, 2)
    testing.expect_value(t, cell_text(&grid.rows[0].cells[3]), "界")
    testing.expect(t, grid.rows[0].cells[4].continuation)
    testing.expect_value(t, grid.rows[0].cells[3].hyperlink, grid.hyperlink)
    testing.expect_value(t, grid.rows[0].shell_markers.columns[.Command], u16(6))
    grid_delete_cells(&grid, 0, 2, 3)
    testing.expect_value(t, cell_text(&grid.rows[0].cells[2]), "B")
    testing.expect_value(t, grid.rows[0].shell_markers.columns[.Command], u16(3))
    for column in 0..<grid.columns {
        cell := &grid.rows[0].cells[column]
        testing.expect(t, !cell.continuation ||
            column > 0 && grid.rows[0].cells[column - 1].width == 2)
    }
}

// Verify explicit tabs and screen-local write modes survive resize.
@(test)
termgrid_test_screen_editing_state_controls_writes :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(&grid, 12, 2, allocator = context.allocator))
    defer grid_destroy(&grid)
    grid.editing.tab_stops = {}
    grid_set_tab_stop(&grid, 3, true)
    testing.expect(t, grid_write(&grid, "\tA"))
    testing.expect_value(t, cell_text(&grid.rows[0].cells[3]), "A")
    grid.editing.autowrap_mode = false
    grid_set_cursor(&grid, 0, 11)
    testing.expect(t, grid_write(&grid, "XY"))
    testing.expect_value(t, grid.cursor, Cursor{column = 11})
    testing.expect_value(t, cell_text(&grid.rows[0].cells[11]), "Y")
    grid.editing.insert_mode = true
    grid.editing.protected_mode = true
    grid_set_cursor(&grid, 0, 3)
    testing.expect(t, grid_write(&grid, "B"))
    testing.expect(t, grid.rows[0].cells[3].protected)
    testing.expect_value(t, cell_text(&grid.rows[0].cells[4]), "A")

    prepared, result := grid_prepare_resize(&grid, 20, 3, context.allocator)
    testing.expect_value(t, result, Grid_Resize_Result.Prepared)
    testing.expect(t, grid_commit_resize(&grid, &prepared))
    testing.expect(t, !grid.editing.autowrap_mode && grid.editing.insert_mode &&
        grid.editing.protected_mode && grid_has_tab_stop(&grid, 3))
    testing.expect_value(t, grid.editing.scroll_bottom, 2)
    testing.expect(t, grid_has_tab_stop(&grid, 16))
    grid_set_cursor(&grid, 0, 19)
    testing.expect(t, grid_write(&grid, "界"))
    testing.expect_value(t, cell_text(&grid.rows[0].cells[19]), "�")
}

// Verify region scrolling moves complete rows and only full-screen eviction commits.
@(test)
termgrid_test_region_scroll_moves_rows_without_false_scrollback :: proc(t: ^testing.T) {
    history: Scrollback_Test_State
    grid: Grid
    testing.expect(t, grid_init(&grid, 3, 4, context.allocator, {
        scrollback = {
            user_data = &history,
            commit = test_scrollback_commit,
        },
    }))
    defer grid_destroy(&grid)
    testing.expect(t, grid_write(&grid, "aaa\r\nbbb\r\nccc\r\nddd"))
    grid.rows[2].shell_markers.present[.Prompt] = true
    grid_scroll_region_up(&grid, 1, 3, 1)
    testing.expect_value(t, history.count, 0)
    testing.expect_value(t, cell_text(&grid.rows[1].cells[0]), "c")
    grid_scroll_region_down(&grid, 1, 3, 1)
    testing.expect(t, grid.rows[2].shell_markers.present[.Prompt])
    grid_scroll_region_up(&grid, 0, 3, 1)
    testing.expect_value(t, history.count, 1)
}

// Verify DEC indexing, margins, and row edits operate on explicit grid state.
@(test)
termgrid_test_dec_grid_region_operations :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(&grid, 4, 4, allocator = context.allocator))
    defer grid_destroy(&grid)
    testing.expect(t, grid_write(&grid, "aaaa\r\nbbbb\r\ncccc\r\ndddd"))
    testing.expect(t, grid_set_vertical_margins(&grid, 1, 3))
    grid_set_cursor(&grid, 3, 2)
    grid_index_forward(&grid, true)
    testing.expect_value(t, grid.cursor, Cursor{row = 3})
    testing.expect_value(t, cell_text(&grid.rows[1].cells[0]), "c")
    grid_set_cursor(&grid, 1, 2)
    grid_index_reverse(&grid)
    testing.expect_value(t, cell_text(&grid.rows[2].cells[0]), "c")
    grid_set_cursor(&grid, 2, 0)
    grid_edit_lines(&grid, 1, true)
    testing.expect_value(t, cell_text(&grid.rows[2].cells[0]), "")
    testing.expect_value(t, cell_text(&grid.rows[3].cells[0]), "c")
    testing.expect(t, !grid_set_vertical_margins(&grid, 2, 2))
}

// Verify DEC save/restore and selective erase preserve protected wide cells.
@(test)
termgrid_test_dec_grid_state_and_selective_erase :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(&grid, 8, 2, allocator = context.allocator))
    defer grid_destroy(&grid)
    grid.style.foreground = termpalette.terminal_color_indexed(2)
    grid.editing.origin_mode = true
    grid.editing.autowrap_mode = false
    grid_set_cursor(&grid, 1, 3)
    grid_dec_save_state(&grid)
    grid.style = {}
    grid.editing.origin_mode = false
    grid.editing.autowrap_mode = true
    grid_set_cursor(&grid, 0, 0)
    grid_dec_restore_state(&grid)
    testing.expect_value(t, grid.cursor, Cursor{row = 1, column = 3})
    testing.expect_value(t, grid.style.foreground,
        termpalette.terminal_color_indexed(2))
    testing.expect(t, grid.editing.origin_mode && !grid.editing.autowrap_mode)

    grid_set_cursor(&grid, 0, 0)
    grid.editing.protected_mode = true
    testing.expect(t, grid_write(&grid, "界"))
    grid.editing.protected_mode = false
    testing.expect(t, grid_write(&grid, "open"))
    grid_set_cursor(&grid, 0, 0)
    testing.expect(t, grid_selective_erase_line(&grid, 2))
    testing.expect_value(t, cell_text(&grid.rows[0].cells[0]), "界")
    testing.expect(t, grid.rows[0].cells[1].continuation)
    testing.expect_value(t, cell_text(&grid.rows[0].cells[2]), "")
}

// Verify row identities follow content and vacated rows receive fresh identities.
@(test)
termgrid_test_scroll_preserves_logical_row_identity :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(&grid, 3, 3, context.allocator))
    defer grid_destroy(&grid)
    first := grid.rows[0].logical_id
    second := grid.rows[1].logical_id
    third := grid.rows[2].logical_id

    grid_scroll_region_up(&grid, 0, 2, 1)

    testing.expect_value(t, grid.rows[0].logical_id, second)
    testing.expect_value(t, grid.rows[1].logical_id, third)
    testing.expect(t, grid.rows[2].logical_id > third)
    testing.expect(t, grid.rows[2].logical_id != first)

    prepared, result := grid_prepare_resize(&grid, 4, 4, context.allocator)
    testing.expect_value(t, result, Grid_Resize_Result.Prepared)
    testing.expect(t, grid_commit_resize(&grid, &prepared))
    testing.expect_value(t, grid.rows[0].logical_id, second)
    testing.expect_value(t, grid.rows[1].logical_id, third)
    testing.expect(t, grid.rows[3].logical_id > grid.rows[2].logical_id)
}

// Verify dirty consumption and explicit completion of a trailing UTF-8 prefix.
@(test)
termgrid_test_dirty_ranges_and_incomplete_utf8_are_explicit :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(
        &grid, 4, 2, allocator = context.allocator))
    defer grid_destroy(&grid)

    testing.expect(t, grid_write(&grid, "ab"))
    testing.expect_value(t, grid.rows[0].dirty_start, 0)
    testing.expect_value(t, grid.rows[0].dirty_end, 2)
    grid_clear_dirty(&grid)
    testing.expect(t, !grid.rows[0].dirty)

    incomplete := [2]u8{0xe2, 0x82}
    testing.expect(t, grid_write(&grid, transmute(string)incomplete[:]))
    testing.expect_value(t, grid.pending_utf8_len, 2)
    grid_finish_input(&grid)
    testing.expect_value(t, grid.pending_utf8_len, 0)
    testing.expect_value(t, grid.invalid_utf8_count, u64(1))
    test_expect_cell(t, &grid, 0, 2, {text = "�", width = 1})
}

// Verify malformed continuation recovery does not consume the following ASCII byte.
@(test)
termgrid_test_invalid_utf8_recovers_across_chunks :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(
        &grid, 4, 2, allocator = context.allocator))
    defer grid_destroy(&grid)

    lead := [1]u8{0xe2}
    testing.expect(t, grid_write(&grid, transmute(string)lead[:]))
    testing.expect(t, grid_write(&grid, "A"))

    testing.expect_value(t, grid.invalid_utf8_count, u64(1))
    testing.expect_value(t, grid.pending_utf8_len, 0)
    test_expect_cell(t, &grid, 0, 0, {text = "�", width = 1})
    test_expect_cell(t, &grid, 0, 1, {text = "A", width = 1})
}

// Verify every invalid UTF-8 prefix class recovers with deterministic replacements.
@(test)
termgrid_test_invalid_utf8_prefix_corpus :: proc(t: ^testing.T) {
    fixtures := [?]Invalid_Utf8_Fixture{
        {bytes = {0x80, 0, 0, 0}, byte_count = 1, replacement_count = 1},
        {bytes = {0xc0, 0, 0, 0}, byte_count = 1, replacement_count = 1},
        {bytes = {0xc1, 0, 0, 0}, byte_count = 1, replacement_count = 1},
        {bytes = {0xf5, 0, 0, 0}, byte_count = 1, replacement_count = 1},
        {bytes = {0xff, 0, 0, 0}, byte_count = 1, replacement_count = 1},
        {bytes = {0xe0, 0x9f, 0, 0}, byte_count = 2, replacement_count = 2},
        {bytes = {0xed, 0xa0, 0, 0}, byte_count = 2, replacement_count = 2},
        {bytes = {0xf0, 0x8f, 0, 0}, byte_count = 2, replacement_count = 2},
        {bytes = {0xf4, 0x90, 0, 0}, byte_count = 2, replacement_count = 2},
    }
    for &fixture in fixtures {
        termgrid_test_invalid_utf8_fixture(t, &fixture)
    }

    truncated: Grid
    testing.expect(t, grid_init(
        &truncated, 4, 2, allocator = context.allocator))
    incomplete := [2]u8{0xe2, 0x82}
    testing.expect(t, grid_write(
        &truncated, transmute(string)incomplete[:]))
    grid_finish_input(&truncated)
    testing.expect_value(t, truncated.invalid_utf8_count, u64(1))
    test_expect_cell(t, &truncated, 0, 0, {text = "�", width = 1})
    grid_destroy(&truncated)
}

// Verify committed scrollback retains generated Unicode cluster geometry exactly.
@(test)
termgrid_test_unicode_clusters_survive_scrollback :: proc(t: ^testing.T) {
    history: Scrollback_Test_State
    grid: Grid
    testing.expect(t, grid_init(&grid, 4, 2, context.allocator, {
        scrollback = {
            user_data = &history,
            commit = test_scrollback_commit,
        },
        ambiguous_width = .Wide,
    }))
    defer grid_destroy(&grid)

    testing.expect(t, grid_write(&grid, "🇺🇸·\r\nnext\r\nx"))
    testing.expect_value(t, history.count, 1)
    testing.expect_value(t, cell_text(&history.rows[0][0]), "🇺🇸")
    testing.expect_value(t, history.rows[0][0].width, u8(2))
    testing.expect(t, history.rows[0][1].continuation)
    testing.expect_value(t, cell_text(&history.rows[0][2]), "·")
    testing.expect_value(t, history.rows[0][2].width, u8(2))
}

// Verify bounded clusters drop whole extensions and retain valid UTF-8.
@(test)
termgrid_test_grapheme_capacity_drops_whole_extensions :: proc(t: ^testing.T) {
    grid: Grid
    testing.expect(t, grid_init(
        &grid, 4, 2, allocator = context.allocator))
    defer grid_destroy(&grid)

    testing.expect(t, grid_write(&grid, "a"))
    for _ in 0..<16 {
        testing.expect(t, grid_write(&grid, "\u0301"))
    }

    cell := &grid.rows[0].cells[0]
    testing.expect(t, cell.grapheme_truncated)
    testing.expect_value(t, cell.grapheme_len, u8(31))
    testing.expect_value(t, grid.truncated_grapheme_count, u64(1))
    testing.expect_value(t, utf8.rune_count_in_string(cell_text(cell)), 16)
}

// Verify palette mutation affects symbolic references without changing direct colors.
@(test)
termgrid_test_palette_resolves_symbolic_colors :: proc(t: ^testing.T) {
    palette: termpalette.Terminal_Palette_State
    termpalette.terminal_palette_init(&palette)
    testing.expect_value(t, palette.colors[196], u32(0xFF0000FF))
    testing.expect_value(t, palette.defaults, palette.colors)

    indexed := termpalette.terminal_color_indexed(196)
    direct := termpalette.terminal_color_direct(0x102030FF)
    palette.colors[196] = 0x112233FF
    palette.foreground = 0x445566FF
    testing.expect_value(t, termpalette.terminal_color_resolve_foreground(
        &palette, indexed), u32(0x112233FF))
    testing.expect_value(t, termpalette.terminal_color_resolve_foreground(
        &palette, direct), u32(0x102030FF))
    testing.expect_value(t, termpalette.terminal_color_resolve_foreground(
        &palette, {}), u32(0x445566FF))
    testing.expect_value(t, termpalette.terminal_color_resolve_background(
        &palette, {}), termpalette.TERMINAL_DEFAULT_BACKGROUND_RGBA)
}