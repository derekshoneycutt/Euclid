#+test
package terminalview

import "../../core"
import "../../core/protocol"
import termattachment "../../terminal/attachment"
import termclipboard "../../terminal/clipboard"
import termgrid "../../terminal/grid"
import termemulator "../../terminal/emulator"
import termhist "../../terminal/history"
import termmodel "../../terminal/model"
import termpalette "../../terminal/palette"
import termshellintegration "../../terminal/shell_integration"
import "../font"
import "../input"

import "core:mem"
import "core:testing"

import rl "vendor:raylib"

// Fake display adapter facts captured by hyperlink activation tests.
Terminal_Test_Hyperlink_Activation :: struct {
    uri: string,
    count: int,
}

Terminal_Test_Clipboard_Text ::
    [termclipboard.CLIPBOARD_TEXT_BYTE_CAPACITY]u8

// Fake display adapter facts captured by clipboard publication tests.
Terminal_Test_Clipboard_Writes :: struct {
    values: [termclipboard.CLIPBOARD_ACTION_CAPACITY]Terminal_Test_Clipboard_Text,
    lengths: [termclipboard.CLIPBOARD_ACTION_CAPACITY]int,
    count: int,
}

// Verify container theme replaces only semantic default foreground references.
@(test)
terminal_test_theme_preserves_explicit_ansi_foreground :: proc(t: ^testing.T) {
    palette: termpalette.Terminal_Palette_State
    termpalette.terminal_palette_init(&palette)
    themed_default := rl.Color{12, 34, 56, 255}

    testing.expect_value(t,
        terminal_resolve_foreground(&palette, {}, themed_default),
        themed_default)
    indexed := termpalette.terminal_color_indexed(1)
    testing.expect_value(t,
        terminal_resolve_foreground(&palette, indexed, themed_default),
        terminal_packed_color(
            termpalette.terminal_color_resolve_foreground(&palette, indexed)))
    direct := termpalette.terminal_color_direct(0xAABBCCFF)
    testing.expect_value(t,
        terminal_resolve_foreground(&palette, direct, themed_default),
        rl.Color{0xAA, 0xBB, 0xCC, 0xFF})
}

// Verify initialization never discards an already published terminal owner.
@(test)
terminal_test_reinitialization_is_rejected :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    allocator := term.allocator

    testing.expect(t, !terminal_init(&term))
    testing.expect_value(t, term.allocator, allocator)
    testing.expect(t, term.history != nil)
}

// Verify a retired terminal generation tolerates final application teardown.
@(test)
terminal_test_destroy_is_idempotent :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))

    terminal_destroy(&term)
    testing.expect(t, !term.initialized)
    terminal_destroy(&term)
    testing.expect(t, !term.initialized)
    testing.expect(t, term.history == nil)
    testing.expect(t, term.output_interpreter.title_state == nil)
}

// Verify fit sizing centers content and explicit-cell sizing applies offsets.
@(test)
terminal_test_raster_fit_and_explicit_geometry :: proc(t: ^testing.T) {
    placement := termattachment.Placement_Metadata{
        geometry = {
            column_span = 4, row_span = 2, sizing = .Fit,
            content_offset_x = 3, content_offset_y = 5,
        },
    }
    fit := terminal_raster_geometry(
        placement, {width = 100, height = 50}, rl.Vector2{10, 20}, 20, 20)
    testing.expect(t, fit.valid)
    testing.expect_value(t, fit.destination.x, f32(13))
    testing.expect_value(t, fit.destination.y, f32(25))
    testing.expect_value(t, fit.destination.width, f32(80))
    testing.expect_value(t, fit.destination.height, f32(40))

    placement.geometry.sizing = .Explicit_Cells
    explicit := terminal_raster_geometry(
        placement, {width = 100, height = 50}, rl.Vector2{10, 20}, 20, 20)
    testing.expect_value(t, explicit.destination.width, f32(80))
    testing.expect_value(t, explicit.destination.height, f32(40))
}

// Verify fill sizing crops centrally and rejects source rectangles outside the raster.
@(test)
terminal_test_raster_fill_and_source_validation :: proc(t: ^testing.T) {
    placement := termattachment.Placement_Metadata{
        geometry = {
            pixel_width = 50, pixel_height = 50, sizing = .Fill,
        },
    }
    fill := terminal_raster_geometry(
        placement, {width = 100, height = 50}, {}, 10, 20)
    testing.expect(t, fill.valid)
    testing.expect_value(t, fill.source.x, 25)
    testing.expect_value(t, fill.source.width, 50)
    testing.expect_value(t, fill.destination.width, f32(50))
    placement.geometry.source = {x = 90, width = 20, height = 10}
    testing.expect(t, !terminal_raster_geometry(
        placement, {width = 100, height = 50}, {}, 10, 20).valid)
}

// Verify negative placements sit behind text while zero and positive z sit above it.
@(test)
terminal_test_raster_layer_partition :: proc(t: ^testing.T) {
    testing.expect(t, terminal_raster_in_layer(-1, .Behind_Text))
    testing.expect(t, !terminal_raster_in_layer(0, .Behind_Text))
    testing.expect(t, !terminal_raster_in_layer(-1, .In_Front_Of_Text))
    testing.expect(t, terminal_raster_in_layer(0, .In_Front_Of_Text))
    testing.expect(t, terminal_raster_in_layer(1, .In_Front_Of_Text))
}

// Record one borrowed URI without invoking the operating system.
terminal_test_activate_hyperlink :: proc(user_data: rawptr, uri: cstring) -> bool {
    activation := (^Terminal_Test_Hyperlink_Activation)(user_data)
    activation.uri = string(uri)
    activation.count += 1
    return true
}

// Copy one borrowed clipboard value without invoking the operating system.
terminal_test_write_clipboard :: proc(user_data: rawptr, text: string) -> bool {
    writes := (^Terminal_Test_Clipboard_Writes)(user_data)
    if writes.count >= len(writes.values) {
        return false
    }
    writes.lengths[writes.count] = copy(writes.values[writes.count][:], text)
    writes.count += 1
    return true
}

// Verify OSC 7 observation and reserved OSC 133 prompt navigation use presented rows.
@(test)
terminal_test_shell_integration_navigation :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    term.geometry.line_height = 20
    terminal_append_ansi_output(&term,
        "\e]7;file:///tmp/project\a\e]133;A\aone\r\n" +
        "middle\r\n\e]133;A\atwo")
    testing.expect_value(t, terminal_observed_cwd_uri(&term),
        "file:///tmp/project")
    term.scroll_offset_y = 0
    events := [2]input.Input_Event{
        {kind = .Press, key = .A},
        {kind = .Press, key = .Page_Down,
            modifiers = {.Control, .Shift}},
    }
    event_index, handled := terminal_update_shell_navigation(
        &term, {events = events[:]})
    testing.expect(t, handled)
    testing.expect_value(t, event_index, 1)
    testing.expect_value(t, term.scroll_offset_y, f32(40))
    filtered := input.input_frame_remove_event({events = events[:]}, event_index)
    testing.expect_value(t, len(filtered.events), 1)
    testing.expect_value(t, filtered.events[0].key, input.Input_Key.A)
}

// Verify indexed command navigation and semantic selection use exact marker columns.
@(test)
terminal_test_shell_command_navigation_and_selection :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    term.geometry.line_height = 20
    terminal_append_ansi_output(&term,
        "\e]133;A\ap$ \e]133;B\aecho one\e]133;C\a\r\none\r\n" +
        "\e]133;D;0\a\e]133;A\ap$ \e]133;B\afalse\e]133;C\a\r\n" +
        "bad\e]133;D;1\a")
    term.scroll_offset_y = 0
    command_down := [1]input.Input_Event{{
        kind = .Press, key = .Page_Down, modifiers = {.Control, .Alt},
    }}
    _, handled := terminal_update_shell_navigation(
        &term, {events = command_down[:]})
    testing.expect(t, handled)
    testing.expect_value(t, term.scroll_offset_y, f32(40))

    select_command := [1]input.Input_Event{{
        kind = .Press, key = .C, modifiers = {.Control, .Alt},
    }}
    _, handled = terminal_update_shell_navigation(
        &term, {events = select_command[:]})
    testing.expect(t, handled && term.view_selection_active)
    testing.expect_value(t, term.view_selection_anchor, core.Terminal_View_Position{2, 3})
    testing.expect_value(t, term.view_selection_head, core.Terminal_View_Position{2, 8})
    testing.expect_value(t, terminal_view_selection_text(&term), "false")

    select_output := [1]input.Input_Event{{
        kind = .Press, key = .O, modifiers = {.Control, .Alt},
    }}
    _, handled = terminal_update_shell_navigation(
        &term, {events = select_output[:]})
    testing.expect(t, handled)
    testing.expect_value(t, term.view_selection_anchor, core.Terminal_View_Position{2, 8})
    testing.expect_value(t, term.view_selection_head, core.Terminal_View_Position{3, 3})
    testing.expect_value(t, terminal_view_selection_text(&term), "bad")
}

// Verify literal command search wraps and joins soft rows at cell boundaries.
@(test)
terminal_test_shell_command_search_wrap_and_graphemes :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 20, rows = 4}, term.output_grid.allocator))
    terminal_append_ansi_output(&term,
        "\e]133;A\a\e]133;B\aabcdefghijklmnopqrstuv\e]133;C\a" +
        "\e]133;D;0\a\r\n\e]133;A\a\e]133;B\aéx\e]133;C\a\e]133;D;0\a")

    testing.expect(t, terminal_command_search_set_query(&term, "stuv"))
    testing.expect(t, terminal_command_search(&term, 1))
    testing.expect_value(t, term.view_selection_anchor,
        core.Terminal_View_Position{0, 18})
    testing.expect_value(t, term.view_selection_head, core.Terminal_View_Position{1, 2})
    first_generation := term.shell_integration.search_match_generation
    testing.expect(t, terminal_command_search(&term, 1))
    testing.expect_value(t,
        term.shell_integration.search_match_generation, first_generation)

    testing.expect(t, terminal_command_search_set_query(&term, "́"))
    testing.expect(t, !terminal_command_search(&term, 1))
    testing.expect(t, terminal_command_search_set_query(&term, "é"))
    testing.expect(t, terminal_command_search(&term, -1))
    testing.expect_value(t, term.view_selection_anchor, core.Terminal_View_Position{2, 0})
    testing.expect_value(t, term.view_selection_head, core.Terminal_View_Position{2, 3})
    query: [termshellintegration.SHELL_COMMAND_SEARCH_QUERY_BYTE_CAPACITY]u8
    testing.expect(t, terminal_command_search_set_query(&term, string(query[:])))
}

// Verify the local search editor retains UTF-8 and navigates in both directions.
@(test)
terminal_test_shell_command_search_input :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    terminal_append_ansi_output(&term,
        "\e]133;A\a\e]133;B\aecho β\e]133;C\a\e]133;D;0\a")
    testing.expect(t, terminal_command_search_begin(&term))
    events := [3]input.Input_Event{
        {kind = .Text, codepoint = 'β'},
        {kind = .Press, key = .Enter},
        {kind = .Press, key = .Enter, modifiers = {.Shift}},
    }
    for event in events {
        testing.expect(t, terminal_update_command_search(&term, event))
    }
    shell := term.shell_integration
    testing.expect_value(t,
        string(shell.search_query[:shell.search_query_byte_count]), "β")
    testing.expect(t, shell.search_match_generation != 0)
    testing.expect_value(t, term.view_selection_anchor.byte_offset, 5)
    testing.expect_value(t, term.view_selection_head.byte_offset, 7)
    testing.expect(t, terminal_update_command_search(
        &term, {kind = .Press, key = .Backspace}))
    testing.expect_value(t, shell.search_query_byte_count, 0)
    testing.expect(t, terminal_update_command_search(
        &term, {kind = .Press, key = .Escape}))
    testing.expect(t, !shell.search_editing)
    testing.expect_value(t, terminal_command_status_color(0),
        rl.Color{0x38, 0x98, 0x26, 0xFF})
    testing.expect_value(t, terminal_command_status_color(1),
        rl.Color{0xCB, 0x3C, 0x33, 0xFF})
}

// Build one single-width test cell with inline UTF-8 storage.
terminal_test_cell :: proc(
    text: string, style := termgrid.Cell_Style{}) -> termgrid.Cell {

    result := termgrid.Cell{width = 1, style = style}
    result.grapheme_len = u8(copy(result.grapheme[:], text))
    return result
}

// Verify one retained query snapshot matches accepted cells and pixel pitches.
terminal_test_expect_query_geometry :: proc(
    t: ^testing.T, actual: termmodel.Terminal_Query_Geometry,
    dimensions: protocol.Terminal_Dimensions, cell_width, cell_height: u32) {
    testing.expect_value(t, actual, termmodel.Terminal_Query_Geometry{
        window_width = u32(dimensions.columns) * cell_width,
        window_height = u32(dimensions.rows) * cell_height,
        cell_width = cell_width,
        cell_height = cell_height,
        valid = true,
    })
}

// Verify pixel geometry derives bounded cells without accepting tiny viewports.
@(test)
terminal_test_dimensions_from_viewport :: proc(t: ^testing.T) {
    limits := TERMINAL_DIMENSION_LIMITS
    exact := terminal_dimensions_from_viewport(1280, 612, 10, 18, limits)
    testing.expect(t, exact.valid)
    testing.expect_value(t, exact.dimensions,
        protocol.Terminal_Dimensions{columns = 128, rows = 34})
    fractional := terminal_dimensions_from_viewport(1289.9, 629.9, 10, 18, limits)
    testing.expect_value(t, fractional.dimensions, exact.dimensions)
    clamped := terminal_dimensions_from_viewport(9999, 9999, 10, 18, limits)
    testing.expect_value(t, clamped.dimensions, limits.maximum)
    testing.expect(t,
        !terminal_dimensions_from_viewport(199, 72, 10, 18, limits).valid)
    testing.expect(t,
        !terminal_dimensions_from_viewport(0, 612, 10, 18, limits).valid)
}

// Verify only changed valid dimensions advance accepted geometry generation.
@(test)
terminal_test_accept_geometry_generation :: proc(t: ^testing.T) {
    retained: termemulator.Terminal_Title_State
    term := core.Terminal_State{
        geometry = {dimensions = {columns = 128, rows = 34}, generation = 1},
        output_interpreter = {title_state = &retained},
    }
    unchanged := terminal_accept_geometry(&term,
        {dimensions = term.geometry.dimensions, valid = true}, 10, 18)
    testing.expect(t, !unchanged.changed)
    testing.expect_value(t, term.geometry.generation, u64(1))
    testing.expect_value(t, term.geometry.column_width, f32(10))
    testing.expect_value(t, term.geometry.line_height, f32(18))
    terminal_test_expect_query_geometry(
        t, retained.query_geometry, {columns = 128, rows = 34}, 10, 18)
    changed := terminal_accept_geometry(&term,
        {dimensions = {columns = 100, rows = 30}, valid = true}, 10, 18)
    testing.expect(t, changed.changed)
    testing.expect_value(t, changed.previous,
        protocol.Terminal_Dimensions{columns = 128, rows = 34})
    testing.expect_value(t, changed.generation, u64(2))
    terminal_accept_geometry(&term, {}, 10, 18)
    testing.expect_value(t, term.geometry.generation, u64(2))
    testing.expect_value(t, term.geometry.dimensions,
        protocol.Terminal_Dimensions{columns = 100, rows = 30})
    testing.expect_value(t, term.rejected_geometry_count, u64(1))
    latest := terminal_accept_geometry(&term,
        {dimensions = {columns = 90, rows = 20}, valid = true}, 12, 21)
    testing.expect_value(t, latest.generation, u64(3))
    testing.expect_value(t, term.geometry.column_width, f32(12))
    testing.expect_value(t, term.geometry.line_height, f32(21))
    terminal_test_expect_query_geometry(
        t, retained.query_geometry, {columns = 90, rows = 20}, 12, 21)
}

// Verify semantic drawing and hit-test bounds use accepted cell dimensions.
@(test)
terminal_test_accepted_bounds_follow_dynamic_geometry :: proc(t: ^testing.T) {
    term := core.Terminal_State{geometry = {
        dimensions = {columns = 20, rows = 4},
        column_width = 8,
        line_height = 18,
    }}
    bounds := terminal_accepted_padded_bounds(
        &term, {x = 5, y = 7, width = 1000, height = 800})
    testing.expect_value(t, bounds.width, f32(160))
    testing.expect_value(t, bounds.height, f32(72))
}

// Verify wide continuations resolve to leaders while later columns retain byte offsets.
@(test)
terminal_test_output_row_byte_offsets_follow_cell_geometry :: proc(t: ^testing.T) {
    cells := [5]termgrid.Cell{
        terminal_test_cell("界"), {}, terminal_test_cell("e\u0301"), {},
        terminal_test_cell("x"),
    }
    cells[0].width = 2
    cells[1] = {continuation = true}

    testing.expect_value(t, terminal_output_row_byte_offset(cells[:], 0), 0)
    testing.expect_value(t, terminal_output_row_byte_offset(cells[:], 1), 0)
    testing.expect_value(t,
        terminal_output_row_byte_offset(cells[:], 2), len("界"))
    testing.expect_value(t,
        terminal_output_row_byte_offset(cells[:], 3), len("界e\u0301"))
    testing.expect_value(t,
        terminal_output_row_byte_offset(cells[:], 5), len("界e\u0301 x"))
}

// Verify live-grid mouse coordinates are one-based, bounded, and Shift-arbitrated.
@(test)
terminal_test_resolve_mouse_frame_uses_live_grid :: proc(t: ^testing.T) {
    term := core.Terminal_State{geometry = {
        dimensions = {columns = 20, rows = 4},
        column_width = 8,
        line_height = 18,
    }}
    bounds := rl.Rectangle{x = 5, y = 7, width = 1000, height = 800}
    inside := terminal_resolve_mouse_frame(&term, {
        mouse_position = {x = 5 + TERMINAL_PADDING + 17,
            y = 7 + TERMINAL_PADDING + 37},
    }, bounds)
    testing.expect(t, inside.terminal_mouse_inside)
    testing.expect(t, inside.terminal_mouse_owned)
    testing.expect_value(t, inside.terminal_mouse_position,
        input.Input_Terminal_Position{column = 3, row = 3})
    testing.expect_value(t, inside.terminal_mouse_pixel_position,
        input.Input_Terminal_Position{column = 18, row = 38})

    outside := terminal_resolve_mouse_frame(&term, {
        mouse_position = {x = 9999, y = 9999},
        mouse_modifiers = {.Shift},
    }, bounds)
    testing.expect(t, !outside.terminal_mouse_inside)
    testing.expect(t, !outside.terminal_mouse_owned)
    testing.expect_value(t, outside.terminal_mouse_position,
        input.Input_Terminal_Position{column = 20, row = 4})
    testing.expect_value(t, outside.terminal_mouse_pixel_position,
        input.Input_Terminal_Position{column = 160, row = 72})
}

// Verify resize preserves a valid fixed-shape checkpoint without changing scrollback.
@(test)
terminal_test_primary_grid_resize_rebuilds_checkpoint :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    testing.expect(t, termemulator.interpreter_write(
        &term.output_interpreter, "\e[34;1HCAPTURED"))
    testing.expect(t, termgrid.display_checkpoint_capture(
        term.output_checkpoint, &term.output_grid, &term.output_scrollback))
    testing.expect(t, termemulator.interpreter_write(
        &term.output_interpreter, "\rLIVE"))
    committed_rows := term.output_scrollback.committed_rows

    dimensions := protocol.Terminal_Dimensions{columns = 100, rows = 30}
    testing.expect(t, terminal_resize_display_grids(
        &term, dimensions, term.output_grid.allocator))
    testing.expect_value(t, term.output_grid.columns, 100)
    testing.expect_value(t, term.output_grid.row_count, 30)
    testing.expect_value(t, term.output_alternate_grid.columns, 100)
    testing.expect_value(t, term.output_alternate_grid.row_count, 30)
    testing.expect_value(t, len(term.output_checkpoint.grid_cells), 3000)
    testing.expect(t, term.output_checkpoint.valid)
    testing.expect_value(t,
        term.output_scrollback.committed_rows, committed_rows)
    testing.expect(t, termgrid.display_checkpoint_restore(
        term.output_checkpoint, &term.output_grid, &term.output_scrollback))
    testing.expect_value(t,
        termgrid.cell_text(&term.output_grid.rows[29].cells[0]), "C")
}

// Verify failed primary preparation does not alter grid or accepted geometry.
@(test)
terminal_test_primary_grid_resize_failure_is_uncommitted :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    dimensions := term.geometry.dimensions
    columns := term.output_grid.columns
    rows := term.output_grid.row_count
    failure_storage: [1]byte
    failure_arena: mem.Arena
    mem.arena_init(&failure_arena, failure_storage[:])
    failing_allocator := mem.arena_allocator(&failure_arena)

    testing.expect(t, !terminal_resize_display_grids(
        &term, {columns = 100, rows = 30}, failing_allocator))
    testing.expect_value(t, term.output_grid.columns, columns)
    testing.expect_value(t, term.output_grid.row_count, rows)
    testing.expect_value(t, term.geometry.dimensions, dimensions)
    testing.expect_value(t, term.geometry.generation, u64(1))
}

// Verify failure after preparing the active grid commits neither display grid.
@(test)
terminal_test_second_grid_resize_failure_is_uncommitted :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    active_cells := raw_data(term.output_grid.cells)
    inactive_cells := raw_data(term.output_alternate_grid.cells)
    failure_storage: [size_of(termgrid.Cell)*100*30 +
        size_of(termgrid.Row)*30 + 256]byte
    failure_arena: mem.Arena
    mem.arena_init(&failure_arena, failure_storage[:])

    testing.expect(t, !terminal_resize_display_grids(
        &term, {columns = 100, rows = 30},
        mem.arena_allocator(&failure_arena)))
    testing.expect_value(t, raw_data(term.output_grid.cells), active_cells)
    testing.expect_value(t,
        raw_data(term.output_alternate_grid.cells), inactive_cells)
    testing.expect_value(t, term.output_grid.columns, TERMINAL_GRID_COLUMNS)
    testing.expect_value(t,
        term.output_alternate_grid.columns, TERMINAL_GRID_COLUMNS)
}

// Verify rows evicted after resize enter history at their new exact width.
@(test)
terminal_test_resized_grid_commits_new_width_scrollback :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 6, rows = 2}, term.output_grid.allocator))
    testing.expect(t, termemulator.interpreter_write(
        &term.output_interpreter, "first\r\nsecond\r\nthird"))

    row, ok := termgrid.scrollback_row(&term.output_scrollback, 0)
    testing.expect(t, ok)
    testing.expect_value(t, len(row.cells), 6)
    testing.expect_value(t, termgrid.cell_text(&row.cells[0]), "f")
}

// Verify one narrow reflow's history identity and reverse selection mapping.
terminal_test_expect_narrow_reflow :: proc(
    t: ^testing.T, term: ^core.Terminal_State,
    line_id: termmodel.Terminal_Logical_Line_Id) {
    testing.expect_value(t, term.output_scrollback.count, 1)
    testing.expect(t, term.view_selection_active)
    testing.expect_value(t, term.view_selection_anchor,
        core.Terminal_View_Position{line = 2, byte_offset = 2})
    testing.expect_value(t, term.view_selection_head,
        core.Terminal_View_Position{line = 0, byte_offset = 1})
    history, history_found := termgrid.scrollback_row(&term.output_scrollback, 0)
    testing.expect(t, history_found)
    testing.expect_value(t, history.logical_line_id, line_id)
}

// Verify repeated semantic reflow crosses history while preserving reverse selection.
@(test)
terminal_test_primary_reflow_round_trip_preserves_selection :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 6, rows = 2}, term.output_grid.allocator))
    term.output_started = true
    testing.expect(t, termemulator.interpreter_write(
        &term.output_interpreter, "abcdefghi"))
    line_id := term.output_grid.rows[0].logical_line_id
    term.view_selection_active = true
    term.view_selection_anchor = {line = 1, byte_offset = 2}
    term.view_selection_head = {line = 0, byte_offset = 1}

    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 3, rows = 2}, term.output_grid.allocator))
    terminal_test_expect_narrow_reflow(t, &term, line_id)
    term.view_selection_anchor = {line = 0, byte_offset = 1}
    term.view_selection_head = {line = 2, byte_offset = 2}

    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 9, rows = 2}, term.output_grid.allocator))
    testing.expect_value(t, term.output_scrollback.count, 0)
    testing.expect_value(t,
        terminal_output_row_text(term.output_grid.rows[0].cells), "abcdefghi")
    testing.expect_value(t, term.output_grid.rows[0].logical_line_id, line_id)
    testing.expect_value(t, term.view_selection_anchor,
        core.Terminal_View_Position{line = 0, byte_offset = 1})
    testing.expect_value(t, term.view_selection_head,
        core.Terminal_View_Position{line = 0, byte_offset = 8})
}

// Admit one tiny raster attachment for terminal placement resize fixtures.
terminal_test_admit_reflow_attachment :: proc(
    store: ^termattachment.Store) ->
    (termattachment.Attachment_Id, termattachment.Admission_Outcome) {
    payload := [4]u8{1, 2, 3, 4}
    return termattachment.attachment_admit(store, {
        metadata = {
            kind = .Raster,
            origin = .Kitty,
            metrics = {width = 2, height = 2},
        },
        payload = payload[:],
        payload_format = .Indexed8,
        payload_stride = 2,
    })
}

// Admit one one-cell placement at a specified screen-local anchor.
terminal_test_admit_reflow_placement :: proc(
    store: ^termattachment.Store, attachment: termattachment.Attachment_Id,
    screen: termattachment.Screen_Identity, logical_row: i64, column: int) ->
    (termattachment.Placement_Id, termattachment.Admission_Outcome) {
    return termattachment.placement_admit(store, {
        attachment_id = attachment,
        geometry = {
            screen = screen,
            logical_row = logical_row,
            column = column,
            column_span = 1,
            row_span = 1,
            source = {width = 2, height = 2},
            sizing = .Fit,
        },
    })
}

// Verify a raster anchor resolves on the trailing blank cursor row.
@(test)
terminal_test_raster_resolves_blank_grid_row :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 6, rows = 2}, term.output_grid.allocator))
    term.output_started = true
    termgrid.grid_set_cursor(&term.output_grid, 1, 0)

    logical_row := term.output_grid.rows[1].logical_id
    line, found := terminal_raster_line(&term, logical_row)
    testing.expect(t, found)
    testing.expect_value(t, line, 1)
}

// Verify a trailing blank-row raster contributes its full extent to scrolling.
@(test)
terminal_test_raster_extends_content_height :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 6, rows = 2}, term.output_grid.allocator))
    term.output_started = true
    termgrid.grid_set_cursor(&term.output_grid, 1, 0)
    attachment, attachment_outcome := terminal_test_admit_reflow_attachment(
        term.synchronized_output.attachments)
    testing.expect_value(t, attachment_outcome,
        termattachment.Admission_Outcome.Admitted)
    _, placement_outcome := terminal_test_admit_reflow_placement(
        term.synchronized_output.attachments, attachment, .Primary,
        term.output_grid.rows[1].logical_id, 0)
    testing.expect_value(t, placement_outcome,
        termattachment.Admission_Outcome.Admitted)

    content_height := terminal_raster_content_height(&term, 8, 20)
    testing.expect(t, content_height > f32(terminal_line_count(&term)) * 20)
}

// Verify a scrolled top-row anchor follows its semantic content through widening.
@(test)
terminal_test_primary_reflow_relocates_viewport_anchor :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 3, rows = 2}, term.output_grid.allocator))
    term.output_started = true
    testing.expect(t, termemulator.interpreter_write(
        &term.output_interpreter, "abcdefghi"))
    term.scroll_offset_y = TERMINAL_FONT_SIZE + TERMINAL_LINE_SPACING

    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 6, rows = 2}, term.output_grid.allocator))
    testing.expect_value(t, term.scroll_offset_y, f32(0))
    testing.expect_value(t,
        terminal_output_row_text(term.output_grid.rows[0].cells), "abcdef")
}

// Verify primary raster anchors relocate while alternate anchors retain coordinates.
@(test)
terminal_test_primary_reflow_relocates_placements :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 6, rows = 2}, term.output_grid.allocator))
    testing.expect(t, termemulator.interpreter_write(
        &term.output_interpreter, "abcdefghi"))
    store := term.synchronized_output.attachments
    attachment, attachment_outcome :=
        terminal_test_admit_reflow_attachment(store)
    testing.expect_value(t, attachment_outcome,
        termattachment.Admission_Outcome.Admitted)
    primary, primary_outcome := terminal_test_admit_reflow_placement(
        store, attachment, .Primary, term.output_grid.rows[0].logical_id, 4)
    testing.expect_value(t, primary_outcome,
        termattachment.Admission_Outcome.Admitted)
    alternate_row := term.output_alternate_grid.rows[0].logical_id
    alternate, alternate_outcome := terminal_test_admit_reflow_placement(
        store, attachment, .Alternate, alternate_row, 2)
    testing.expect_value(t, alternate_outcome,
        termattachment.Admission_Outcome.Admitted)

    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 3, rows = 2}, term.output_grid.allocator))
    primary_metadata, primary_found := termattachment.placement_metadata(
        store, primary)
    alternate_metadata, alternate_found := termattachment.placement_metadata(
        store, alternate)
    testing.expect(t, primary_found && alternate_found)
    testing.expect_value(t, primary_metadata.geometry.logical_row,
        term.output_grid.rows[0].logical_id)
    testing.expect_value(t, primary_metadata.geometry.column, 1)
    testing.expect_value(t, alternate_metadata.geometry.logical_row, alternate_row)
    testing.expect_value(t, alternate_metadata.geometry.column, 2)
}

// Verify delayed wrap remains armed at the reflowed end of a full logical line.
@(test)
terminal_test_primary_reflow_preserves_delayed_wrap :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 6, rows = 2}, term.output_grid.allocator))
    testing.expect(t, termemulator.interpreter_write(
        &term.output_interpreter, "abcdef"))
    testing.expect(t, term.output_grid.cursor.wrap_pending)

    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 3, rows = 2}, term.output_grid.allocator))
    testing.expect_value(t, term.output_grid.cursor,
        termgrid.Cursor{row = 1, column = 2, wrap_pending = true})
    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 6, rows = 2}, term.output_grid.allocator))
    testing.expect_value(t, term.output_grid.cursor,
        termgrid.Cursor{row = 0, column = 5, wrap_pending = true})
}

// Verify rollback checkpoint content reflows independently from later live output.
@(test)
terminal_test_primary_reflow_rebuilds_semantic_checkpoint :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 9, rows = 2}, term.output_grid.allocator))
    testing.expect(t, termemulator.interpreter_write(
        &term.output_interpreter, "abcdefghi"))
    testing.expect(t, termgrid.display_checkpoint_capture(
        term.output_checkpoint, &term.output_grid, &term.output_scrollback))
    testing.expect(t, termemulator.interpreter_write(
        &term.output_interpreter, "\rLIVE"))

    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 3, rows = 2}, term.output_grid.allocator))
    testing.expect(t, termgrid.display_checkpoint_restore(
        term.output_checkpoint, &term.output_grid, &term.output_scrollback))
    history, history_found := termgrid.scrollback_row(
        &term.output_scrollback, 0)
    testing.expect(t, history_found)
    testing.expect_value(t, terminal_output_row_text(history.cells), "abc")
    testing.expect_value(t,
        terminal_output_row_text(term.output_grid.rows[0].cells), "def")
    testing.expect_value(t,
        terminal_output_row_text(term.output_grid.rows[1].cells), "ghi")
}

// Verify shrink clears only selections with endpoints outside the new rectangle.
@(test)
terminal_test_resize_reconciles_view_selection :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    term.banner_ready = true
    term.view_selection_active = true
    term.view_selection_anchor = {line = 0, byte_offset = 2}
    term.view_selection_head = {line = 1, byte_offset = 30}

    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 20, rows = 4}, term.output_grid.allocator))
    testing.expect(t, !term.view_selection_active)
    testing.expect(t, !term.view_selection_dragging)
}

// Verify resize preserves a selection whose endpoints remain representable.
@(test)
terminal_test_resize_preserves_valid_view_selection :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    term.banner_ready = true
    term.view_selection_active = true
    term.view_selection_anchor = {line = 0, byte_offset = 2}
    term.view_selection_head = {line = 1, byte_offset = 10}

    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 20, rows = 4}, term.output_grid.allocator))
    testing.expect(t, term.view_selection_active)
}

// Verify resize during DEC 1049 preserves both screens and their saved cursors.
@(test)
terminal_test_alternate_screen_resize_restores_resized_primary :: proc(
    t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    interpreter := &term.output_interpreter
    testing.expect(t, termemulator.interpreter_write(
        interpreter, "\e[34;1HPRIMARY\e[s\e[?1049h\e[34;1HALT\e[s"))
    committed_rows := term.output_scrollback.committed_rows

    dimensions := protocol.Terminal_Dimensions{columns = 10, rows = 4}
    testing.expect(t, terminal_resize_display_grids(
        &term, dimensions, term.output_grid.allocator))
    testing.expect(t, interpreter.alternate_screen_active)
    testing.expect_value(t, term.output_grid.columns, 10)
    testing.expect_value(t, term.output_alternate_grid.columns, 10)
    testing.expect_value(t,
        termgrid.cell_text(&term.output_grid.rows[3].cells[0]), "A")
    testing.expect_value(t,
        interpreter.saved_cursor, termgrid.Cursor{row = 3, column = 3})

    testing.expect(t, termemulator.interpreter_write(interpreter, "\e[?1049l"))
    testing.expect_value(t,
        termgrid.cell_text(&term.output_grid.rows[3].cells[0]), "P")
    testing.expect_value(t, term.output_grid.cursor, termgrid.Cursor{row = 3, column = 7})
    testing.expect_value(t,
        interpreter.saved_cursor, termgrid.Cursor{row = 3, column = 7})
    testing.expect_value(t,
        term.output_scrollback.committed_rows, committed_rows)
}

// Exercise display replacement, attachment reuse, and retained history growth.
terminal_test_churn_recyclable_storage :: proc(
    t: ^testing.T, term: ^core.Terminal_State) {
    dimensions := [2]protocol.Terminal_Dimensions{
        {columns = 140, rows = 40},
        {columns = TERMINAL_GRID_COLUMNS, rows = TERMINAL_GRID_ROWS},
    }

    for iteration in 0..<32 {
        target := dimensions[iteration % len(dimensions)]
        testing.expect(t, terminal_resize_display_grids(
            term, target, term.output_grid.allocator))
    }

    payload := [1024]u8{}
    attachments := term.synchronized_output.attachments
    for _ in 0..<64 {
        id, outcome := termattachment.attachment_admit(attachments, {
            metadata = {
                kind = .Raster,
                origin = .Kitty,
                metrics = {width = 32, height = 32},
            },
            payload = payload[:],
            payload_format = .Indexed8,
            payload_stride = 32,
        })
        testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
        testing.expect_value(t,
            termattachment.attachment_remove(attachments, id),
            termattachment.Handle_Outcome.Found)
        testing.expect(t, termhist.termhist_insert_text(term.history, "history-growth"))
        testing.expect(t, termhist.termhist_accept_current(term.history))
    }
}

// Verify terminal model storage follows ordinary animation generation replacement.
@(test)
terminal_test_animation_generation_replacement :: proc(t: ^testing.T) {
    memory: core.Animation_Memory
    testing.expect(t, core.animation_memory_init(&memory))
    defer core.animation_memory_destroy(&memory)
    testing.expect_value(t, core.animation_memory_begin_generation(
        &memory, 7), core.Animation_Memory_Status.Ok)

    term: core.Terminal_State
    testing.expect(t, terminal_init_for_animation(&term, &memory, 7))
    testing.expect_value(t, term.animation_generation, u64(7))
    testing.expect(t, term.allocator == core.animation_memory_allocator(&memory))
    initial := core.animation_memory_diagnostics(&memory)
    testing.expect(t, initial.current_used > 0)

    terminal_test_churn_recyclable_storage(t, &term)
    churned := core.animation_memory_diagnostics(&memory)
    testing.expect(t, churned.current_used >= initial.current_used)

    terminal_destroy(&term)
    testing.expect_value(t, core.animation_memory_begin_generation(
        &memory, 8), core.Animation_Memory_Status.Ok)
    reset := core.animation_memory_diagnostics(&memory)
    testing.expect_value(t, reset.current_used, uint(0))
    testing.expect_value(t, reset.reset_count, churned.reset_count + 1)
    testing.expect(t, terminal_init_for_animation(&term, &memory, 8))
    testing.expect_value(t, term.animation_generation, u64(8))
    terminal_destroy(&term)
}

// Verify terminal initialization and replacement grids retain wide ambiguous policy.
@(test)
terminal_test_ambiguous_width_policy_is_terminal_lifetime_state :: proc(
    t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term, .Wide))
    defer terminal_destroy(&term)
    palette := &term.output_interpreter.title_state.palette
    testing.expect_value(t, palette.colors[196], u32(0xFF0000FF))
    testing.expect_value(t, palette.defaults, palette.colors)
    testing.expect_value(t,
        term.output_grid.editing.ambiguous_width,
        termgrid.Ambiguous_Width_Mode.Wide)
    testing.expect_value(t, term.output_alternate_grid.editing.ambiguous_width,
        termgrid.Ambiguous_Width_Mode.Wide)
    testing.expect(t, terminal_resize_display_grids(
        &term, {columns = 100, rows = 20}, term.output_grid.allocator))
    testing.expect_value(t,
        term.output_grid.editing.ambiguous_width,
        termgrid.Ambiguous_Width_Mode.Wide)
    testing.expect_value(t, term.output_alternate_grid.editing.ambiguous_width,
        termgrid.Ambiguous_Width_Mode.Wide)
}

// Verify shaped runs stop at style, blank, and non-single-width boundaries.
@(test)
terminal_test_shape_run_boundaries :: proc(t: ^testing.T) {
    regular := termgrid.Cell_Style{
        foreground = termpalette.terminal_color_direct(0xffffffff)}
    bold := regular
    bold.bold = true
    cells := [5]termgrid.Cell{
        terminal_test_cell("-", regular),
        terminal_test_cell(">", regular),
        terminal_test_cell("=", bold),
        terminal_test_cell("", regular),
        terminal_test_cell("x", regular),
    }
    testing.expect_value(t, terminal_shape_run_end(cells[:], 0), 2)
    testing.expect_value(t, terminal_shape_run_end(cells[:], 2), 3)
    testing.expect(t, !terminal_cell_shape_eligible(&cells[3]))
}

// Verify UTF-8 flattening preserves source bytes and maps clusters to source cells.
@(test)
terminal_test_shape_run_utf8_mapping :: proc(t: ^testing.T) {
    cells := [2]termgrid.Cell{
        terminal_test_cell("λ"), terminal_test_cell("→")}
    storage: [16]u8
    offsets: [3]int
    text, built := terminal_shape_run_text(cells[:], storage[:], offsets[:])

    testing.expect(t, built)
    testing.expect_value(t, text, "λ→")
    testing.expect_value(t, offsets, [3]int{0, len("λ"), len("λ→")})
    first, first_ok := terminal_shape_cluster_column(0, offsets[:])
    second, second_ok := terminal_shape_cluster_column(u32(len("λ")), offsets[:])
    testing.expect(t, first_ok && second_ok)
    testing.expect_value(t, first, 0)
    testing.expect_value(t, second, 1)
}

// Verify composed narrow clusters shape as one cell while wide emoji use fallback.
@(test)
terminal_test_unicode_cluster_shaping_boundaries :: proc(t: ^testing.T) {
    combining := terminal_test_cell("e\u0301")
    emoji := terminal_test_cell("🇺🇸")
    emoji.width = 2
    continuation := termgrid.Cell{continuation = true}
    cells := [3]termgrid.Cell{combining, emoji, continuation}

    testing.expect(t, terminal_cell_shape_eligible(&cells[0]))
    testing.expect(t, !terminal_cell_shape_eligible(&cells[1]))
    testing.expect(t, !terminal_cell_shape_eligible(&cells[2]))
    storage: [16]u8
    offsets: [2]int
    text, built := terminal_shape_run_text(
        cells[:1], storage[:], offsets[:])
    testing.expect(t, built)
    testing.expect_value(t, text, "e\u0301")
    testing.expect_value(t, offsets, [2]int{0, len("e\u0301")})
}

// Verify maximum-width rows partition completely into bounded shaping chunks.
@(test)
terminal_test_shape_workspace_accepts_maximum_width :: proc(t: ^testing.T) {
    start := 0
    chunks := 0
    for start < TERMINAL_MAX_COLUMNS {
        chunk_end := terminal_shape_chunk_end(start, TERMINAL_MAX_COLUMNS)
        testing.expect(t, chunk_end > start)
        testing.expect(t, chunk_end - start <= TERMINAL_SHAPING_RUN_COLUMNS)
        start = chunk_end
        chunks += 1
    }
    testing.expect_value(t, start, TERMINAL_MAX_COLUMNS)
    testing.expect_value(t, chunks, 2)
}

// Verify shaped output must preserve one equal horizontal advance per source cell.
@(test)
terminal_test_shaped_run_advance_validation :: proc(t: ^testing.T) {
    atlas := font_test_atlas(8)
    glyphs := [2]font.Shaped_Glyph{
        {glyph_id = 2, x_advance = 10},
        {glyph_id = 3, cluster = 1, x_advance = 10},
    }
    testing.expect(t, terminal_shaped_run_is_valid(glyphs[:], 2, 2, atlas))
    glyphs[1].x_advance = 9
    testing.expect(t, !terminal_shaped_run_is_valid(glyphs[:], 2, 2, atlas))
    glyphs[1].x_advance = 10
    glyphs[1].glyph_id = 8
    testing.expect(t, !terminal_shaped_run_is_valid(glyphs[:], 2, 2, atlas))
}

// Verify shaped whitespace has no drawable atlas area.
@(test)
terminal_test_shaped_whitespace_has_no_ink :: proc(t: ^testing.T) {
    testing.expect(t, !terminal_shaped_source_has_ink({}))
    testing.expect(t, !terminal_shaped_source_has_ink({width = 8}))
    testing.expect(t, terminal_shaped_source_has_ink({width = 8, height = 12}))
    testing.expect(t, !terminal_text_has_visible_bytes(TERMINAL_CONTINUATION_PROMPT))
    testing.expect(t, terminal_text_has_visible_bytes("julia> "))
    space := termgrid.Cell{grapheme_len = 1, width = 1}
    visible := termgrid.Cell{grapheme_len = 1, width = 1}
    space.grapheme[0] = ' '
    visible.grapheme[0] = '#'
    testing.expect(t, terminal_cell_is_ascii_space(&space))
    testing.expect(t, !terminal_cell_is_ascii_space(&visible))
}

// Build metadata-only font state for shaped-run validation tests.
font_test_atlas :: proc(glyph_count: i32) -> rl.Font {
    return {glyphCount = glyph_count}
}

// Verify the prompt line composes the Julia prompt with the given text.
@(test)
terminal_test_prompt_line :: proc(t: ^testing.T) {
    testing.expect_value(t, terminal_prompt_line("something"), "julia> something")
    testing.expect_value(t, terminal_prompt_line(""), "julia> ")
    testing.expect_value(t, terminal_prompt_draw_color(.Shell),
        TERMINAL_SHELL_PROMPT_COLOR)
}

// Verify copy requires Shift so plain Ctrl+C remains a foreground interrupt.
@(test)
terminal_test_clipboard_copy_shortcut :: proc(t: ^testing.T) {
    ctrl_c := input.Input_Frame{events = []input.Input_Event{{
        kind = .Press,
        key = .C,
        modifiers = {.Control},
    }}}
    testing.expect(t, !terminal_clipboard_copy_requested(ctrl_c))

    copy := input.Input_Frame{
        events = []input.Input_Event{{
            kind = .Press,
            key = .C,
            modifiers = {.Control, .Shift},
        }},
    }
    testing.expect(t, terminal_clipboard_copy_requested(copy))
}

// Verify paste requires both modifiers and inserts clipboard text at the cursor.
@(test)
terminal_test_clipboard_paste_shortcut :: proc(t: ^testing.T) {
    ctrl_v := input.Input_Frame{events = []input.Input_Event{{
        kind = .Press,
        key = .V,
        modifiers = {.Control},
    }}}
    testing.expect(t, !terminal_clipboard_paste_requested(ctrl_v))

    paste := input.Input_Frame{
        events = []input.Input_Event{{
            kind = .Press,
            key = .V,
            modifiers = {.Control, .Shift},
        }},
    }
    testing.expect(t, terminal_clipboard_paste_requested(paste))

    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    testing.expect(t, termhist.termhist_insert_text(term.history, "ac"))
    testing.expect(t, termhist.termhist_move_left(term.history))
    testing.expect(t, terminal_insert_clipboard_text(&term, "β"))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "aβc")
    testing.expect_value(t, termhist.termhist_cursor(term.history), len("aβ"))
}

// Verify the prompt and keyboard input stay blocked until Julia's real
// startup banner arrives, then unblock once it's displayed.
@(test)
terminal_test_banner_gates_prompt_and_input :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, !terminal_prompt_visible(&term))
    update := terminal_update_keyboard(&term, input.Input_Frame{})
    testing.expect(t, !update.cursor_moved)

    terminal_display_banner(&term, "Version test banner\n")
    testing.expect(t, terminal_prompt_visible(&term))
    testing.expect_value(t, terminal_line_count(&term), 1)
    testing.expect_value(t, terminal_line_text(&term, 0), "Version test banner")
}

// Verify a submitted evaluation hides the live prompt until completion.
@(test)
terminal_test_prompt_waits_for_eval_completion :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    term.banner_ready = true
    testing.expect(t, terminal_prompt_visible(&term))

    testing.expect(t, terminal_begin_eval(&term, "begin\n    1"))
    testing.expect(t, !terminal_prompt_visible(&term))

    terminal_continue_eval(&term)
    testing.expect(t, terminal_prompt_visible(&term))
    testing.expect_value(t, terminal_prompt_prefix(&term), TERMINAL_CONTINUATION_PROMPT)
    testing.expect_value(t, terminal_prompt_prefix(&term), "       ")
    testing.expect_value(
        t, termhist.termhist_current_text(term.history), "begin\n    1\n    ")
    testing.expect_value(t, terminal_eval_source(&term, "end"), "end")

    terminal_complete_eval(&term)
    testing.expect(t, terminal_prompt_visible(&term))
    testing.expect_value(t, terminal_prompt_prefix(&term), TERMINAL_PROMPT)
}

// Verify continuation input is auto-indented and editable across lines.
@(test)
terminal_test_continuation_is_multiline_editable :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    termhist.termhist_insert_text(term.history, "begin\n    value")
    submitted := terminal_submit(&term)
    testing.expect_value(t, submitted, "begin\n    value")
    first_row := term.output_grid.rows[0].cells
    testing.expect(t, first_row[0].style.foreground != {})
    testing.expect_value(t, first_row[len(TERMINAL_PROMPT)].style.foreground,
        termmodel.Terminal_Color_Reference(0))
    testing.expect(t, terminal_begin_eval(&term, submitted))
    terminal_continue_eval(&term)

    testing.expect_value(
        t, termhist.termhist_current_text(term.history), "begin\n    value\n    ")
    testing.expect(t, termhist.termhist_backspace(term.history))
    testing.expect(t, termhist.termhist_backspace(term.history))
    testing.expect(t, termhist.termhist_backspace(term.history))
    testing.expect(t, termhist.termhist_backspace(term.history))
    testing.expect_value(
        t, termhist.termhist_current_text(term.history), "begin\n    value\n")
    testing.expect(t, termhist.termhist_backspace(term.history))
    testing.expect_value(
        t, termhist.termhist_current_text(term.history), "begin\n    value")
    testing.expect(t, termhist.termhist_backspace(term.history))
    testing.expect_value(
        t, termhist.termhist_current_text(term.history), "begin\n    valu")
}

// Verify incomplete input removes its committed prompt from authoritative output.
@(test)
terminal_test_continuation_restores_display_checkpoint :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    terminal_append_output_line(&term, "before")
    testing.expect(t, termhist.termhist_insert_text(term.history, "begin"))
    submitted := terminal_submit(&term)
    testing.expect_value(t, terminal_line_count(&term), 2)
    testing.expect_value(t, terminal_line_text(&term, 1), "julia> begin")

    testing.expect(t, terminal_begin_eval(&term, submitted))
    terminal_continue_eval(&term)

    testing.expect_value(t, terminal_line_count(&term), 1)
    testing.expect_value(t, terminal_line_text(&term, 0), "before")
    testing.expect_value(t, termhist.termhist_current_text(term.history), "begin\n")
}

// Verify repeated incomplete submissions redraw accumulated source only once.
@(test)
terminal_test_repeated_continuation_does_not_duplicate_prompt_rows :: proc(
    t: ^testing.T) {

    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, termhist.termhist_insert_text(term.history, "for i in 1:2"))
    first := terminal_submit(&term)
    testing.expect(t, terminal_begin_eval(&term, first))
    terminal_continue_eval(&term)

    testing.expect(t, termhist.termhist_insert_text(term.history, "println(i)"))
    second := terminal_submit(&term)
    testing.expect_value(t, terminal_line_count(&term), 2)
    testing.expect_value(t, terminal_line_text(&term, 0), "julia> for i in 1:2")
    testing.expect_value(t, terminal_line_text(&term, 1), "       println(i)")
    testing.expect(t, terminal_begin_eval(&term, second))
    terminal_continue_eval(&term)
    testing.expect_value(t, terminal_line_count(&term), 0)

    testing.expect(t, termhist.termhist_insert_text(term.history, "end"))
    third := terminal_submit(&term)
    testing.expect_value(t, terminal_line_count(&term), 3)
    testing.expect_value(t, terminal_line_text(&term, 0), "julia> for i in 1:2")
    testing.expect_value(t, terminal_line_text(&term, 1), "       println(i)")
    testing.expect_value(t, terminal_line_text(&term, 2), "       end")
    testing.expect(t, terminal_begin_eval(&term, third))
    terminal_complete_eval(&term)

    testing.expect_value(t, term.history.history_len, 1)
    testing.expect(t, terminal_history_prev_test_helper(&term))
    testing.expect_value(t, termhist.termhist_current_text(term.history),
        "for i in 1:2\nprintln(i)\nend")
}

// Verify `?` at the start of the line enters help mode and keeps trailing text.
@(test)
terminal_test_help_mode_keeps_text_after_leading_question_mark :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    termhist.termhist_insert_text(term.history, "sort")
    termhist.termhist_move_home(term.history)

    testing.expect(t, terminal_enter_help_mode_on_question_mark(&term, '?'))
    testing.expect(t, terminal_is_help_mode(&term))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "sort")
    testing.expect_value(t, terminal_prompt_prefix(&term), TERMINAL_HELP_PROMPT)
}

// Verify `?` typed after the start of the line is left as ordinary input.
@(test)
terminal_test_question_mark_mid_line_does_not_enter_help_mode :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    termhist.termhist_insert_text(term.history, "sort")

    testing.expect(t, !terminal_enter_help_mode_on_question_mark(&term, '?'))
    testing.expect(t, !terminal_is_help_mode(&term))
}

// Verify help mode is single-shot: it exits as soon as it's left, mirroring
// how Julia's REPL returns to `julia>` immediately after a help submission.
@(test)
terminal_test_exit_help_mode_restores_standard_prompt :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, terminal_enter_help_mode_on_question_mark(&term, '?'))
    testing.expect(t, terminal_is_help_mode(&term))

    terminal_exit_help_mode(&term)
    testing.expect(t, !terminal_is_help_mode(&term))
    testing.expect_value(t, terminal_prompt_prefix(&term), TERMINAL_PROMPT)
}

// Verify `]` at the start of the line enters pkg mode and keeps trailing text.
@(test)
terminal_test_pkg_mode_keeps_text_after_leading_bracket :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    termhist.termhist_insert_text(term.history, "status")
    termhist.termhist_move_home(term.history)

    testing.expect(t, terminal_enter_pkg_mode_on_bracket(&term, ']'))
    testing.expect(t, terminal_is_pkg_mode(&term))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "status")
    testing.expect_value(t, terminal_prompt_prefix(&term), TERMINAL_PKG_PROMPT)
}

// Verify `]` typed after the start of the line is left as ordinary input.
@(test)
terminal_test_bracket_mid_line_does_not_enter_pkg_mode :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    termhist.termhist_insert_text(term.history, "status")

    testing.expect(t, !terminal_enter_pkg_mode_on_bracket(&term, ']'))
    testing.expect(t, !terminal_is_pkg_mode(&term))
}

// Verify pkg mode is sticky: submitting a command does not exit it, unlike
// help mode's single-shot behavior.
@(test)
terminal_test_pkg_mode_stays_active_across_submit :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, terminal_enter_pkg_mode_on_bracket(&term, ']'))
    termhist.termhist_insert_text(term.history, "status")
    terminal_submit(&term)

    testing.expect(t, terminal_is_pkg_mode(&term))
    testing.expect_value(t, terminal_prompt_prefix(&term), TERMINAL_PKG_PROMPT)

    terminal_exit_help_mode(&term)
    testing.expect(t, terminal_is_pkg_mode(&term))
}

// Verify backspace on an empty pkg-mode line exits back to the standard prompt.
@(test)
terminal_test_backspace_on_empty_exits_pkg_mode :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, terminal_enter_pkg_mode_on_bracket(&term, ']'))
    testing.expect(t, terminal_try_exit_mode_on_empty_backspace(&term))
    testing.expect(t, !terminal_is_pkg_mode(&term))
    testing.expect_value(t, terminal_prompt_prefix(&term), TERMINAL_PROMPT)
}

// Verify Ctrl+C cancels Pkg input and restores the standard Julia prompt.
@(test)
terminal_test_cancel_pkg_mode :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, terminal_enter_pkg_mode_on_bracket(&term, ']'))
    termhist.termhist_insert_text(term.history, "status")
    testing.expect(t, terminal_cancel_pkg_mode(&term))
    testing.expect(t, !terminal_is_pkg_mode(&term))
    testing.expect_value(t, terminal_prompt_prefix(&term), TERMINAL_PROMPT)
    testing.expect_value(t, termhist.termhist_current_text(term.history), "")
    testing.expect(t, !terminal_cancel_pkg_mode(&term))
}

// Verify history browsing restores each entry's own recorded prompt mode.
@(test)
terminal_test_history_browse_restores_recorded_mode :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, terminal_enter_pkg_mode_on_bracket(&term, ']'))
    termhist.termhist_insert_text(term.history, "status")
    terminal_submit(&term)

    testing.expect(t, terminal_try_exit_mode_on_empty_backspace(&term))
    termhist.termhist_insert_text(term.history, "1 + 1")
    terminal_submit(&term)

    testing.expect(t, terminal_history_prev_test_helper(&term))
    testing.expect(t, !terminal_is_pkg_mode(&term))
    testing.expect(t, !terminal_is_help_mode(&term))

    testing.expect(t, terminal_history_prev_test_helper(&term))
    testing.expect(t, terminal_is_pkg_mode(&term))

    terminal_history_browse_next(&term)
    testing.expect(t, !terminal_is_pkg_mode(&term))
}

//   Step to the previous history entry via the same path terminal keys use.
terminal_history_prev_test_helper :: proc(term: ^core.Terminal_State) -> bool {
    before := term.history.history_index
    terminal_history_browse_prev(term)
    return term.history.history_index != before
}

// Verify selection and negotiated mouse tracking suppress hyperlink clicks.
terminal_test_expect_hyperlink_precedence :: proc(
    t: ^testing.T, term: ^core.Terminal_State,
    point: input.Input_Position, bounds: rl.Rectangle) {
    shifted := input.Input_Frame{
        mouse_position = point,
        mouse_pressed = {.Left},
        mouse_modifiers = {.Shift},
    }
    testing.expect(t, !terminal_update_hyperlink_click(
        term, shifted, bounds).requested)
    term.output_interpreter.input_mode = {
        mouse_tracking = .Button,
        mouse_sgr_encoding = true,
    }
    testing.expect(t, !terminal_update_hyperlink_click(term, {
        mouse_position = point,
        mouse_pressed = {.Left},
    }, bounds).requested)
}

// Verify Ctrl+D is only treated as an exit request on an empty, non-help,
// non-continuation line, matching a shell's EOF-on-empty-line convention.
@(test)
terminal_test_can_exit_on_ctrl_d :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, terminal_can_exit_on_ctrl_d(&term))

    termhist.termhist_insert_text(term.history, "1")
    testing.expect(t, !terminal_can_exit_on_ctrl_d(&term))
    termhist.termhist_backspace(term.history)

    term.input_mode = .Help
    testing.expect(t, !terminal_can_exit_on_ctrl_d(&term))
    term.input_mode = .Normal

    term.collecting_continuation = true
    testing.expect(t, !terminal_can_exit_on_ctrl_d(&term))
    term.collecting_continuation = false

    testing.expect(t, terminal_can_exit_on_ctrl_d(&term))
}

// Verify completed evaluation leaves one blank line before the next prompt.
@(test)
terminal_test_completion_adds_prompt_spacing :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, terminal_begin_eval(&term, "1 + 1"))
    terminal_append_output_line(&term, "2")
    terminal_complete_eval(&term)

    testing.expect_value(t, terminal_line_count(&term), 2)
    testing.expect_value(t, terminal_line_text(&term, 0), "2")
    testing.expect_value(t, terminal_line_text(&term, 1), "")
}

// Verify same-link release activates through a fake adapter and respects precedence.
@(test)
terminal_test_hyperlink_click_activation :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    terminal_append_ansi_output(
        &term, "\e]8;;https://example.com/path\a界\e]8;;\a")
    term.geometry.column_width = 10
    term.geometry.line_height = 20
    bounds := rl.Rectangle{0, 0, 100, 60}
    point := input.Input_Position{25, 15}

    terminal_update_hyperlink_click(&term, {
        mouse_position = point,
        mouse_pressed = {.Left},
    }, bounds)
    request := terminal_update_hyperlink_click(&term, {
        mouse_position = point,
        mouse_released = {.Left},
    }, bounds)
    fake: Terminal_Test_Hyperlink_Activation
    testing.expect(t, terminal_activate_hyperlink(&term, request, {
        user_data = &fake,
        activate = terminal_test_activate_hyperlink,
    }))
    testing.expect_value(t, fake.uri, "https://example.com/path")
    testing.expect_value(t, fake.count, 1)
    terminal_test_expect_hyperlink_precedence(t, &term, point, bounds)
}

// Verify conservative row-local detection trims prose without weakening URI policy.
@(test)
terminal_test_detects_plain_text_links :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    terminal_append_output_line(&term,
        "See https://example.com/a(b). mailto:user@example.com! www.example.com")
    cells, present := terminal_output_row(&term, 0)
    testing.expect(t, present)

    web := terminal_detect_link_at(cells, 0, 8)
    testing.expect_value(t, web.kind, Terminal_Link_Kind.Detected)
    testing.expect_value(t, string(web.uri[:web.uri_byte_count]),
        "https://example.com/a(b)")
    testing.expect_value(t, web.column_start, 4)
    testing.expect_value(t, web.column_end, 28)

    mail := terminal_detect_link_at(cells, 0, 36)
    testing.expect_value(t, mail.kind, Terminal_Link_Kind.Detected)
    testing.expect_value(t, string(mail.uri[:mail.uri_byte_count]),
        "mailto:user@example.com")
    testing.expect_value(t, terminal_detect_link_at(cells, 0, 58).kind,
        Terminal_Link_Kind.None)
    testing.expect_value(t, term.hyperlink_registry.count, 0)

    terminal_append_output_line(&term,
        "file:///home/user/value custom://example.test")
    blocked, _ := terminal_output_row(&term, 1)
    testing.expect_value(t, terminal_detect_link_at(blocked, 1, 2).kind,
        Terminal_Link_Kind.None)
    testing.expect_value(t, terminal_detect_link_at(blocked, 1, 28).kind,
        Terminal_Link_Kind.None)
}

// Verify unmatched closers trim and explicit OSC 8 metadata wins over detection.
@(test)
terminal_test_detected_link_boundaries_and_explicit_precedence :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    terminal_append_output_line(&term, "https://example.com/path) tail")
    cells, _ := terminal_output_row(&term, 0)
    detected := terminal_detect_link_at(cells, 0, 5)
    testing.expect_value(t, string(detected.uri[:detected.uri_byte_count]),
        "https://example.com/path")
    testing.expect_value(t, detected.kind, Terminal_Link_Kind.Detected)

    terminal_append_ansi_output(
        &term, "\e]8;;https://explicit.example\ahttps://plain.example\e]8;;\a")
    term.geometry.column_width = 10
    term.geometry.line_height = 20
    hit := terminal_hit_test_link(
        &term, rl.Rectangle{0, 0, 400, 80}, rl.Vector2{25, 35})
    testing.expect_value(t, hit.kind, Terminal_Link_Kind.Osc8)
    testing.expect(t, hit.handle != 0)
}

// Verify detected links activate only after an unchanged same-target release.
@(test)
terminal_test_detected_link_click_activation :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    terminal_append_output_line(&term, "https://example.com/path")
    term.geometry.column_width = 10
    term.geometry.line_height = 20
    bounds := rl.Rectangle{0, 0, 400, 60}
    point := input.Input_Position{25, 15}

    terminal_update_hyperlink_click(&term, {
        mouse_position = point, mouse_pressed = {.Left},
    }, bounds)
    request := terminal_update_hyperlink_click(&term, {
        mouse_position = point, mouse_released = {.Left},
    }, bounds)
    testing.expect_value(t, request.kind, Terminal_Link_Kind.Detected)
    fake: Terminal_Test_Hyperlink_Activation
    testing.expect(t, terminal_activate_hyperlink(&term, request, {
        user_data = &fake, activate = terminal_test_activate_hyperlink,
    }))
    testing.expect_value(t, fake.uri, "https://example.com/path")
    testing.expect_value(t, term.hyperlink_registry.count, 0)

    cells, _ := terminal_output_row(&term, 0)
    style_before := cells[0].style
    hover := terminal_hyperlink_hover_hit(&term, {
        mouse_position = point,
    }, bounds)
    testing.expect_value(t, hover.kind, Terminal_Link_Kind.Detected)
    testing.expect_value(t, cells[0].style, style_before)

    terminal_test_expect_hyperlink_precedence(t, &term, point, bounds)
}

// Verify release over another valid detected target cannot activate the pressed URI.
@(test)
terminal_test_detected_link_changed_target_rejected :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    terminal_append_output_line(
        &term, "https://one.example https://two.example")
    cells, _ := terminal_output_row(&term, 0)
    first := terminal_detect_link_at(cells, 0, 2)
    second := terminal_detect_link_at(cells, 0, 24)
    terminal_store_hyperlink_press(&term, first)
    testing.expect(t, !terminal_hyperlink_release_matches(&term, second))
    terminal_clear_hyperlink_press(&term)
}

// Verify matching OSC 52 actions publish in order through a fake display sink.
@(test)
terminal_test_publishes_osc_clipboard_writes :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    producer := termmodel.Terminal_Producer{.Julia_Evaluation, 19, 0}
    terminal_append_ansi_output(
        &term, "\e]52;c;b25l\a\e]52;;zrI=\e\\", producer)

    writes: Terminal_Test_Clipboard_Writes
    published := terminal_publish_clipboard_actions(
        &term, term.output_producer, {
            user_data = &writes,
            write = terminal_test_write_clipboard,
        })

    testing.expect_value(t, published, 2)
    testing.expect_value(t,
        string(writes.values[0][:writes.lengths[0]]), "one")
    testing.expect_value(t,
        string(writes.values[1][:writes.lengths[1]]), "β")
    testing.expect_value(t, term.clipboard_actions.count, 0)
    testing.expect_value(t, term.clipboard_actions.publication_count, u64(2))
    testing.expect_value(t,
        term.clipboard_actions.stale_discard_count, u64(0))
}

// Verify producer rollover discards older clipboard content before publication.
@(test)
terminal_test_discards_stale_osc_clipboard_writes :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    first := termmodel.Terminal_Producer{.Terminal_Session, 3, 1}
    second := termmodel.Terminal_Producer{.Terminal_Session, 3, 2}
    terminal_append_ansi_output(&term, "\e]52;c;b2xk\a", first)
    terminal_append_ansi_output(&term, "\e]52;c;bmV3\a", second)

    writes: Terminal_Test_Clipboard_Writes
    published := terminal_publish_clipboard_actions(
        &term, term.output_producer, {
            user_data = &writes,
            write = terminal_test_write_clipboard,
        })

    testing.expect_value(t, published, 1)
    testing.expect_value(t, writes.count, 1)
    testing.expect_value(t,
        string(writes.values[0][:writes.lengths[0]]), "new")
    testing.expect_value(t, term.clipboard_actions.count, 0)
    testing.expect_value(t,
        term.clipboard_actions.stale_discard_count, u64(1))
    testing.expect_value(t, term.clipboard_actions.publication_count, u64(1))
}

// Verify retained terminal text rejects overflow without allocating or publishing state.
@(test)
terminal_test_rejects_retained_text_overflow :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    oversized: [protocol.TERMINAL_RETAINED_TEXT_MAX_BYTES + 1]u8
    source := string(oversized[:])
    testing.expect(t, !terminal_begin_eval(&term, source))
    testing.expect_value(t, term.pending_eval_source, "")

    testing.expect(t, termhist.termhist_insert_text(term.history, source))
    request := terminal_request_completion(&term)
    testing.expect(t, !request.requested)
    testing.expect_value(t, term.pending_completion_source, "")

    termhist.termhist_clear(term.history)
    testing.expect(t, termhist.termhist_insert_text(term.history, "x"))
    request = terminal_request_completion(&term)
    testing.expect(t, request.requested)
    testing.expect(t, !terminal_set_completion_preview(
        &term, Terminal_Completion_Preview{
            request_id = request.request_id,
            found = true,
            replacement_end = 1,
            insertion = source,
        }))
    testing.expect_value(t, term.completion_preview_insertion, "")
}

// Verify a Unicode completion previews before explicitly replacing source text.
@(test)
terminal_test_accepts_unicode_completion_preview :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, termhist.termhist_insert_text(term.history, "x=\\alpha"))
    request := terminal_request_completion(&term)
    testing.expect(t, terminal_set_completion_preview(&term, Terminal_Completion_Preview{
        request_id = request.request_id,
        found = true,
        replacement_start = len("x="),
        replacement_end = len("x=\\alpha"),
        insertion = "α",
    }))
    testing.expect_value(t, termhist.termhist_current_text(term.history), "x=\\alpha")
    testing.expect(t, terminal_accept_completion_preview(&term))

    testing.expect_value(t, termhist.termhist_current_text(term.history), "x=α")
    testing.expect_value(t, termhist.termhist_cursor(term.history), len("x=α"))
}

// Verify a completion response cannot overwrite edits made after Tab.
@(test)
terminal_test_discards_stale_completion :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, termhist.termhist_insert_text(term.history, "\\alpha"))
    request := terminal_request_completion(&term)
    testing.expect(t, termhist.termhist_insert_text(term.history, "x"))
    testing.expect(t, !terminal_set_completion_preview(&term, Terminal_Completion_Preview{
        request_id = request.request_id,
        found = true,
        replacement_end = len("\\alpha"),
        insertion = "α",
    }))

    testing.expect_value(t, termhist.termhist_current_text(term.history), "\\alphax")
    testing.expect(t, !terminal_accept_completion_preview(&term))
}

// Verify automatic completion waits for its debounce deadline.
@(test)
terminal_test_completion_debounce :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, termhist.termhist_insert_text(term.history, "\\alpha"))
    terminal_schedule_completion(&term, 1)
    testing.expect(t, !terminal_take_scheduled_completion(&term, 1).requested)

    request := terminal_take_scheduled_completion(
        &term, 1 + TERMINAL_COMPLETION_DEBOUNCE_SECONDS)
    testing.expect(t, request.requested)
    testing.expect_value(t, request.code, "\\alpha")

    testing.expect(t, terminal_set_completion_preview(&term, Terminal_Completion_Preview{
        request_id = request.request_id,
    }))
    testing.expect_value(
        t, term.pending_completion_request_id, protocol.Request_Id(0))
    testing.expect_value(t, len(term.completion_preview_insertion), 0)
}

// Verify duplicate completion results cannot replace an accepted preview.
@(test)
terminal_test_discards_duplicate_completion_result :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, termhist.termhist_insert_text(term.history, "\\alpha"))
    request := terminal_request_completion(&term)
    testing.expect(t, terminal_set_completion_preview(&term,
        Terminal_Completion_Preview{
            request_id = request.request_id,
            found = true,
            replacement_end = len("\\alpha"),
            insertion = "α",
        }))
    testing.expect(t, !terminal_set_completion_preview(&term,
        Terminal_Completion_Preview{
            request_id = request.request_id,
            found = true,
            replacement_end = len("\\alpha"),
            insertion = "wrong",
        }))
    testing.expect_value(t, term.completion_preview_insertion, "α")
}

// Verify request identity and cursor position independently guard completion results.
@(test)
terminal_test_completion_requires_current_identity_and_cursor :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, termhist.termhist_insert_text(term.history, "print"))
    request := terminal_request_completion(&term)
    testing.expect(t, !terminal_set_completion_preview(&term,
        Terminal_Completion_Preview{
            request_id = request.request_id + 1,
            found = true,
            insertion = "println",
        }))

    termhist.termhist_move_left(term.history)
    testing.expect(t, !terminal_set_completion_preview(&term,
        Terminal_Completion_Preview{
            request_id = request.request_id,
            found = true,
            insertion = "println",
        }))
}

// Verify a current failure terminates its request and a stale failure does not.
@(test)
terminal_test_completion_failure_respects_snapshot :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    testing.expect(t, termhist.termhist_insert_text(term.history, "print"))
    request := terminal_request_completion(&term)
    testing.expect(t, !terminal_fail_completion(&term, request.request_id + 1))
    testing.expect_value(t, term.pending_completion_request_id, request.request_id)
    testing.expect(t, terminal_fail_completion(&term, request.request_id))
    testing.expect_value(
        t, term.pending_completion_request_id, protocol.Request_Id(0))
}

// Verify font selection maps terminal styling to semantic variant identity.
@(test)
terminal_test_font_weight_selection :: proc(t: ^testing.T) {
    styles := []termhist.Termhist_Text_Style{
        {font_weight = .Light},
        {font_weight = .Medium, is_italic = true},
        {font_weight = .Semi_Bold},
        {font_weight = .Extra_Bold, is_italic = true},
        {font_weight = .Black},
    }

    testing.expect_value(
        t, terminal_font_key_for_style(styles[0]), font.Font_Key.Light)
    testing.expect_value(
        t, terminal_font_key_for_style(styles[1]), font.Font_Key.Medium_Italic)
    testing.expect_value(
        t, terminal_font_key_for_style(styles[2]), font.Font_Key.Semi_Bold)
    testing.expect_value(
        t, terminal_font_key_for_style(styles[3]), font.Font_Key.Extra_Bold_Italic)
    testing.expect_value(
        t, terminal_font_key_for_style(styles[4]), font.Font_Key.Black)
}

// Verify ANSI SGR output becomes styled terminal cells without escape bytes.
@(test)
terminal_test_ansi_output_styles :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    terminal_append_ansi_output(
        &term, "\e[1;31mERROR\e[0m plain \e[4;96mlink\e[0m\n")

    testing.expect_value(t, terminal_line_text(&term, 0), "ERROR plain link")
    row := term.output_grid.rows[0].cells
    testing.expect(t, row[0].style.bold)
    testing.expect_value(t, row[0].style.foreground,
        termpalette.terminal_color_indexed(int(Terminal_Color.Red)))
    testing.expect_value(t, row[5].style.foreground,
        termmodel.Terminal_Color_Reference(0))
    testing.expect(t, row[12].style.underline)
    testing.expect_value(
        t, row[12].style.foreground,
        termpalette.terminal_color_indexed(int(Terminal_Color.Bright_Cyan)))
}

// Verify a bare `\r` overwrite replaces cells written earlier on the line.
@(test)
terminal_test_ansi_output_carriage_return_overwrite :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    terminal_append_ansi_output(&term, "10%\r50%\r100%\n")

    testing.expect_value(t, terminal_line_count(&term), 1)
    testing.expect_value(t, terminal_line_text(&term, 0), "100%")
}

// Verify synchronized output hides live mutations until normal publication.
@(test)
terminal_test_synchronized_output_defers_presentation :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    terminal_append_ansi_output(&term, "old")
    terminal_append_ansi_output(&term, "\e[?2026h\e[31mnew")
    testing.expect(t, term.synchronized_output.active)
    testing.expect_value(t, terminal_line_text(&term, 0), "old")
    testing.expect_value(t,
        termgrid.cell_text(&term.output_grid.rows[0].cells[3]), "n")
    testing.expect_value(t,
        term.output_grid.rows[0].cells[3].style.foreground,
        termpalette.terminal_color_indexed(1))
    testing.expect_value(t,
        terminal_output_cursor_presentation(&term).column, 3)

    terminal_append_ansi_output(&term, "\e[?2026l")
    testing.expect(t, !term.synchronized_output.active)
    testing.expect_value(t, terminal_line_text(&term, 0), "oldnew")
    row, present := terminal_output_row(&term, 0)
    testing.expect(t, present)
    testing.expect_value(t, row[3].style.foreground,
        termpalette.terminal_color_indexed(1))
    testing.expect_value(t, term.synchronized_output.publish_count, u64(1))
}

// Verify synchronized presentation retains old hyperlink metadata until publication.
@(test)
terminal_test_synchronized_output_defers_hyperlinks :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    terminal_append_ansi_output(
        &term, "\e]8;;https://old.example\aA\e]8;;\a")
    old_handle := terminal_output_hyperlink_at(&term, 0, 0)
    terminal_append_ansi_output(&term,
        "\e[?2026h\r\e]8;;https://new.example\aB\e]8;;\a")
    new_handle := term.output_grid.rows[0].cells[0].hyperlink
    testing.expect(t, old_handle != 0 && new_handle != old_handle)
    testing.expect_value(t,
        terminal_output_hyperlink_at(&term, 0, 0), old_handle)

    terminal_append_ansi_output(&term, "\e[?2026l")
    testing.expect_value(t,
        terminal_output_hyperlink_at(&term, 0, 0), new_handle)
}

// Verify an unterminated synchronized transaction publishes after 250 ms.
@(test)
terminal_test_synchronized_output_deadline_forces_publication :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    terminal_append_ansi_output(&term, "old\e[?2026hnew")
    terminal_update_synchronized_output(&term, 10)
    terminal_update_synchronized_output(&term, 10.249)
    testing.expect(t, term.synchronized_output.active)
    testing.expect_value(t, terminal_line_text(&term, 0), "old")
    terminal_update_synchronized_output(&term, 10.250)
    testing.expect(t, !term.synchronized_output.active)
    testing.expect_value(t, terminal_line_text(&term, 0), "oldnew")
    testing.expect_value(t,
        term.synchronized_output.forced_publish_count, u64(1))
}

// Verify style set before a `\r` overwrite still applies to text typed after it.
@(test)
terminal_test_ansi_output_carriage_return_keeps_style :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    terminal_append_ansi_output(&term, "\e[31mfoo\rbar\e[0m\n")

    testing.expect_value(t, terminal_line_text(&term, 0), "bar")
    testing.expect_value(
        t, term.output_grid.rows[0].cells[0].style.foreground,
        termpalette.terminal_color_indexed(int(Terminal_Color.Red)))
}

// Verify `\r\n` is normalized to a single line ending like a lone `\n`.
@(test)
terminal_test_ansi_output_crlf_normalized :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    terminal_append_ansi_output(&term, "a\r\nb\n")

    testing.expect_value(t, terminal_line_count(&term), 2)
    testing.expect_value(t, terminal_line_text(&term, 0), "a")
    testing.expect_value(t, terminal_line_text(&term, 1), "b")
}

// Verify output split before a newline does not create a blank row.
@(test)
terminal_test_ansi_output_chunk_boundary_preserves_lines :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    terminal_append_ansi_output(&term, "poop 1")
    terminal_append_ansi_output(&term, "\npoop 2\n")

    testing.expect_value(t, terminal_line_count(&term), 2)
    testing.expect_value(t, terminal_line_text(&term, 0), "poop 1")
    testing.expect_value(t, terminal_line_text(&term, 1), "poop 2")
}

// Verify abnormal evaluation completion restores primary history and prompt ownership.
@(test)
terminal_test_completion_restores_stranded_alternate_screen :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)
    term.banner_ready = true

    terminal_append_ansi_output(&term, "primary\n")
    testing.expect(t, terminal_begin_eval(&term, "broken_tui()"))
    terminal_append_ansi_output(
        &term, "\e[?1h\e=\e[?2004h\e[?1049h\e[31mALT\r\nSCREEN\e[")
    testing.expect(t, term.output_interpreter.alternate_screen_active)
    testing.expect_value(t, terminal_line_count(&term), 2)
    row, ok := terminal_output_row(&term, 0)
    testing.expect(t, ok)
    testing.expect_value(t, terminal_output_row_text(row), "ALT")

    terminal_complete_eval(&term)

    testing.expect(t, !term.output_interpreter.alternate_screen_active)
    testing.expect(t, term.output_interpreter.cursor_visible)
    testing.expect_value(t, term.output_interpreter.input_mode,
        termmodel.Terminal_Input_Mode{})
    testing.expect_value(
        t, term.output_interpreter.state, termemulator.Interpreter_State.Ground)
    testing.expect_value(t, term.output_grid.style, termgrid.Cell_Style{})
    testing.expect(t, terminal_prompt_visible(&term))
    testing.expect_value(t, terminal_line_text(&term, 0), "primary")
}

// Verify the ANSI cursor follows active-grid visibility and scrollback coordinates.
@(test)
terminal_test_output_cursor_presentation :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    terminal_append_ansi_output(&term, "abc\e[2;3H")
    cursor := terminal_output_cursor_presentation(&term, true)
    testing.expect(t, cursor.visible)
    testing.expect_value(t, cursor.style, Terminal_Output_Cursor_Style.Filled)
    testing.expect_value(t, cursor.line, 1)
    testing.expect_value(t, cursor.column, 2)
    testing.expect_value(t, cursor.width, 1)

    terminal_append_ansi_output(&term, "\e[?25l")
    testing.expect(t, !terminal_output_cursor_presentation(&term).visible)
    terminal_append_ansi_output(&term, "\e[?25h\e[?1049h界")
    term.output_grid.cursor.column = 0
    cursor = terminal_output_cursor_presentation(&term, false)
    testing.expect(t, cursor.visible)
    testing.expect_value(t, cursor.style, Terminal_Output_Cursor_Style.Outline)
    testing.expect_value(t, cursor.line, 0)
    testing.expect_value(t, cursor.width, 2)

    term.banner_ready = true
    term.awaiting_eval = false
    testing.expect(t, !terminal_output_cursor_presentation(&term).visible)
}

// Verify a `\r` overwrite on one line never touches an earlier closed line.
@(test)
terminal_test_ansi_output_carriage_return_keeps_prior_line :: proc(t: ^testing.T) {
    term: core.Terminal_State
    testing.expect(t, terminal_init(&term))
    defer terminal_destroy(&term)

    terminal_append_ansi_output(&term, "first\n")
    terminal_append_ansi_output(&term, "10%\r100%\n")

    testing.expect_value(t, terminal_line_count(&term), 2)
    testing.expect_value(t, terminal_line_text(&term, 0), "first")
    testing.expect_value(t, terminal_line_text(&term, 1), "100%")
}
