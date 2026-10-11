#+test
package termgrid

import "core:mem"
import "core:testing"
import termmodel "../model"
import termpalette "../palette"

// Owned cell and marker storage for the mixed semantic-reflow fixture.
Reflow_Mixed_Fixture :: struct {
    first: [4]Cell,
    second: [4]Cell,
    third: [2]Cell,
    first_markers: termmodel.Shell_Row_Markers,
    second_markers: termmodel.Shell_Row_Markers,
}

// Build one occupied single-width reflow fixture cell.
reflow_test_cell :: proc(
    text: string, style := Cell_Style{},
    hyperlink := termmodel.Hyperlink_Handle(0),
    protected := false) -> Cell {
    result := Cell{
        width = 1,
        style = style,
        hyperlink = hyperlink,
        protected = protected,
    }
    result.grapheme_len = u8(copy(result.grapheme[:], text))
    return result
}

// Build mixed widths, styling, links, protection, and all shell marker classes.
reflow_test_mixed_fixture :: proc(
    style: Cell_Style,
    handle: termmodel.Hyperlink_Handle) -> Reflow_Mixed_Fixture {
    result := Reflow_Mixed_Fixture{
        first = {
            reflow_test_cell("A"), reflow_test_cell(" "),
            reflow_test_cell("界", style, handle, true),
            {continuation = true},
        },
        second = {
            reflow_test_cell("é", style), reflow_test_cell("B"), {}, {}},
        third = {reflow_test_cell("Z"), {}},
    }
    result.first[2].width = 2
    result.first_markers.present[.Prompt] = true
    result.first_markers.present[.Command] = true
    result.first_markers.columns[.Command] = 1
    result.second_markers.present[.Execution] = true
    result.second_markers.present[.Finished] = true
    result.second_markers.columns[.Execution] = 2
    result.second_markers.columns[.Finished] = 2
    result.second_markers.finished_status = 17
    result.second_markers.finished_status_present = true
    return result
}

// Verify the retained mixed-cell payload after semantic row emission.
reflow_test_expect_mixed_cells :: proc(
    t: ^testing.T, prepared: ^Prepared_Reflow,
    style: Cell_Style, handle: termmodel.Hyperlink_Handle) {
    testing.expect_value(t, cell_text(&prepared.rows[0].cells[0]), "A")
    testing.expect_value(t, cell_text(&prepared.rows[0].cells[1]), " ")
    testing.expect_value(t, cell_text(&prepared.rows[1].cells[0]), "界")
    testing.expect(t, prepared.rows[1].cells[1].continuation)
    testing.expect_value(t, prepared.rows[1].cells[0].style, style)
    testing.expect_value(t, prepared.rows[1].cells[0].hyperlink, handle)
    testing.expect(t, prepared.rows[1].cells[0].protected)
    testing.expect_value(t, cell_text(&prepared.rows[1].cells[2]), "é")
    testing.expect_value(t, cell_text(&prepared.rows[2].cells[0]), "B")
    testing.expect_value(t, cell_text(&prepared.rows[3].cells[0]), "Z")
}

// Verify every shell marker class survives with its status metadata.
reflow_test_expect_mixed_markers :: proc(
    t: ^testing.T, prepared: ^Prepared_Reflow) {
    testing.expect(t, prepared.rows[0].shell_markers.present[.Command])
    testing.expect(t, prepared.rows[0].shell_markers.present[.Prompt])
    testing.expect_value(t,
        prepared.rows[0].shell_markers.columns[.Command], u16(1))
    testing.expect(t, prepared.rows[2].shell_markers.present[.Execution])
    testing.expect_value(t,
        prepared.rows[2].shell_markers.columns[.Execution], u16(1))
    testing.expect(t, prepared.rows[2].shell_markers.present[.Finished])
    testing.expect_value(t,
        prepared.rows[2].shell_markers.finished_status, i32(17))
    testing.expect(t,
        prepared.rows[2].shell_markers.finished_status_present)
}

// Verify semantic composition preserves cell identity, hard lines, and markers.
@(test)
termgrid_test_reflow_mixed_cells_and_hard_boundaries :: proc(t: ^testing.T) {
    style := Cell_Style{
        foreground = termpalette.terminal_color_direct(0x123456FF), italic = true}
    handle := termmodel.Hyperlink_Handle(0x10001)
    fixture := reflow_test_mixed_fixture(style, handle)
    source := [3]Reflow_Source_Row{
        {cells = fixture.first[:], logical_row_id = 10, wrapped = true,
            shell_markers = fixture.first_markers},
        {cells = fixture.second[:], logical_row_id = 11,
            shell_markers = fixture.second_markers},
        {cells = fixture.third[:], logical_row_id = 12},
    }

    prepared, result := reflow_prepare(source[:], 3, 8, context.allocator)
    testing.expect_value(t, result, Reflow_Result.Prepared)
    defer reflow_destroy(&prepared)
    testing.expect_value(t, len(prepared.rows), 4)
    testing.expect(t, prepared.rows[0].wrapped && prepared.rows[1].wrapped)
    testing.expect(t, !prepared.rows[2].wrapped && !prepared.rows[3].wrapped)
    reflow_test_expect_mixed_cells(t, &prepared, style, handle)
    semantic, found := reflow_resolve_old(&prepared, {11, 0})
    testing.expect(t, found)
    testing.expect_value(t, semantic,
        termmodel.Terminal_Semantic_Position{10, 3})
    relocated, retained := reflow_resolve_semantic(&prepared, semantic)
    testing.expect(t, retained)
    testing.expect_value(t, relocated, Reflow_New_Position{1, 2})
    reflow_test_expect_mixed_markers(t, &prepared)
}

// Verify bounded output retains the newest rows and canonicalizes wrap boundaries.
@(test)
termgrid_test_reflow_capacity_retains_newest_line_tail :: proc(t: ^testing.T) {
    cells := [6]Cell{
        reflow_test_cell("a"), reflow_test_cell("b"), reflow_test_cell("c"),
        reflow_test_cell("d"), reflow_test_cell("e"), reflow_test_cell("f"),
    }
    source := [1]Reflow_Source_Row{{cells = cells[:], logical_row_id = 40}}
    prepared, result := reflow_prepare(
        source[:], 2, 2, context.allocator)
    testing.expect_value(t, result, Reflow_Result.Prepared)
    defer reflow_destroy(&prepared)
    testing.expect_value(t, prepared.evicted_rows, 1)
    testing.expect(t, prepared.rows[0].head_truncated)
    testing.expect_value(t, cell_text(&prepared.rows[0].cells[0]), "c")
    testing.expect_value(t, cell_text(&prepared.rows[1].cells[1]), "f")
    _, evicted := reflow_resolve_semantic(&prepared, {40, 1})
    testing.expect(t, !evicted)
    boundary, retained := reflow_resolve_semantic(&prepared, {40, 2})
    testing.expect(t, retained)
    testing.expect_value(t, boundary, Reflow_New_Position{0, 0})
    semantic, old_found := reflow_resolve_old(&prepared, {40, 2})
    testing.expect(t, old_found)
    testing.expect_value(t, semantic,
        termmodel.Terminal_Semantic_Position{40, 2})
}

// Verify one-column ASCII output and impossible wide-cell geometry are explicit.
@(test)
termgrid_test_reflow_one_column_width_policy :: proc(t: ^testing.T) {
    ascii := [2]Cell{reflow_test_cell("a"), reflow_test_cell("b")}
    source := [1]Reflow_Source_Row{{cells = ascii[:], logical_row_id = 50}}
    prepared, result := reflow_prepare(
        source[:], 1, 2, context.allocator)
    testing.expect_value(t, result, Reflow_Result.Prepared)
    testing.expect_value(t, len(prepared.rows), 2)
    reflow_destroy(&prepared)

    wide := [2]Cell{reflow_test_cell("界"), {continuation = true}}
    wide[0].width = 2
    source[0].cells = wide[:]
    _, wide_result := reflow_prepare(source[:], 1, 2, context.allocator)
    testing.expect_value(t, wide_result, Reflow_Result.Cell_Too_Wide)
}

// Verify repeated narrow-wide-narrow layout preserves grapheme order exactly.
@(test)
termgrid_test_reflow_repetition_preserves_semantic_content :: proc(t: ^testing.T) {
    cells := [6]Cell{
        reflow_test_cell("a"), reflow_test_cell("b"), reflow_test_cell("c"),
        reflow_test_cell("d"), reflow_test_cell("e"), reflow_test_cell("f"),
    }
    original := [1]Reflow_Source_Row{{cells = cells[:], logical_row_id = 70}}
    wide, wide_result := reflow_prepare(
        original[:], 6, 3, context.allocator)
    testing.expect_value(t, wide_result, Reflow_Result.Prepared)
    defer reflow_destroy(&wide)
    wide_source := [1]Reflow_Source_Row{{
        cells = wide.rows[0].cells,
        logical_row_id = 70,
        wrapped = wide.rows[0].wrapped,
        shell_markers = wide.rows[0].shell_markers,
        logical_line_id = wide.rows[0].logical_line_id,
        grapheme_offset = wide.rows[0].grapheme_offset,
        head_truncated = wide.rows[0].head_truncated,
    }}
    narrow, narrow_result := reflow_prepare(
        wide_source[:], 2, 3, context.allocator)
    testing.expect_value(t, narrow_result, Reflow_Result.Prepared)
    defer reflow_destroy(&narrow)
    testing.expect_value(t, len(narrow.rows), 3)
    for index in 0..<len(cells) {
        row, column := index / 2, index % 2
        testing.expect_value(t,
            narrow.rows[row].cells[column], cells[index])
    }
}

// Verify preflight relocation pressure and allocation failure publish no candidate.
@(test)
termgrid_test_reflow_preparation_failures_are_atomic :: proc(t: ^testing.T) {
    cells := [2]Cell{reflow_test_cell("a"), reflow_test_cell("b")}
    source := [1]Reflow_Source_Row{{cells = cells[:], logical_row_id = 60}}
    limited, limited_result := reflow_prepare(
        source[:], 2, 1, context.allocator, 2)
    testing.expect_value(t, limited_result,
        Reflow_Result.Relocation_Capacity_Exceeded)
    testing.expect(t, !limited.ready && limited.cells == nil)

    storage: [1]byte
    arena: mem.Arena
    mem.arena_init(&arena, storage[:])
    failed, failure_result := reflow_prepare(
        source[:], 2, 1, mem.arena_allocator(&arena))
    testing.expect_value(t, failure_result, Reflow_Result.Allocation_Failed)
    testing.expect(t, !failed.ready && failed.cells == nil)

    malformed := [1]Cell{{continuation = true}}
    source[0].cells = malformed[:]
    invalid, invalid_result := reflow_prepare(
        source[:], 2, 1, context.allocator)
    testing.expect_value(t, invalid_result, Reflow_Result.Invalid_Input)
    testing.expect(t, !invalid.ready && invalid.cells == nil)

    duplicate := [2]Reflow_Source_Row{
        {cells = cells[:], logical_row_id = 80},
        {cells = cells[:], logical_row_id = 80},
    }
    _, duplicate_result := reflow_prepare(
        duplicate[:], 2, 2, context.allocator)
    testing.expect_value(t, duplicate_result, Reflow_Result.Invalid_Input)
}