package terminalview

import "../../core"
import "../../core/protocol"
import termgrid "../../terminal/grid"
import termemulator "../../terminal/emulator"
import termattachment "../../terminal/attachment"
import termhist "../../terminal/history"
import "../font"

import "core:log"
import "core:mem"
import "core:unicode/utf8"

import rl "vendor:raylib"

//   Derive bounded terminal dimensions from usable pixels and cell metrics.
//
// Parameters:
//   - usable_width: Horizontal content extent available for complete cells.
//   - usable_height: Vertical content extent available for complete rows.
//   - column_width: Measured monospace cell pitch in pixels.
//   - line_height: Configured terminal row pitch in pixels.
//   - limits: Inclusive minimum and maximum protocol dimensions.
//
// Returns:
//   - A valid clamped dimension candidate, or an empty candidate for unusable metrics
//     or a viewport smaller than the configured minimum.
terminal_dimensions_from_viewport :: proc(
    usable_width, usable_height, column_width, line_height: f32,
    limits: protocol.Terminal_Dimension_Limits) -> Terminal_Dimension_Candidate {
    if usable_width <= 0 || usable_height <= 0 ||
        column_width <= 0 || line_height <= 0 {
        return {}
    }
    columns := int(usable_width / column_width)
    rows := int(usable_height / line_height)
    if columns < int(limits.minimum.columns) ||
        rows < int(limits.minimum.rows) {
        return {}
    }
    return {
        dimensions = {
            columns = u16(clamp(columns, int(limits.minimum.columns),
                int(limits.maximum.columns))),
            rows = u16(clamp(rows, int(limits.minimum.rows),
                int(limits.maximum.rows))),
        },
        valid = true,
    }
}

//   Commit one valid changed dimension candidate and refresh accepted metrics.
//
// Parameters:
//   - term: Terminal state receiving accepted dimensions and measured cell metrics.
//   - candidate: Validated viewport-derived dimensions to consider.
//   - column_width: Measured monospace cell pitch in pixels.
//   - line_height: Configured terminal row pitch in pixels.
//
// Returns:
//   - A populated geometry change when dimensions changed; otherwise an empty value.
//
// Side effects:
//   - Records rejected candidates, always refreshes metrics for valid candidates, and
//     advances geometry generation exactly once for changed dimensions.
terminal_accept_geometry :: proc(
    term: ^core.Terminal_State, candidate: Terminal_Dimension_Candidate,
    column_width, line_height: f32) -> Terminal_Geometry_Change {
    if !candidate.valid {
        term.rejected_geometry_count += 1
        return {}
    }
    previous := term.geometry.dimensions
    term.geometry.column_width = column_width
    term.geometry.line_height = line_height
    terminal_publish_query_geometry(
        term, candidate.dimensions, column_width, line_height)
    if candidate.dimensions == previous {
        return {}
    }
    term.geometry.dimensions = candidate.dimensions
    term.geometry.generation += 1
    return {
        changed = true,
        previous = previous,
        current = candidate.dimensions,
        generation = term.geometry.generation,
    }
}

// Publish display-committed cell and text-area pixels for terminal query snapshots.
//
// Parameters:
//   - term: Display-owned terminal carrying retained interpreter state.
//   - dimensions: Accepted text-area size in character cells.
//   - column_width: Accepted horizontal cell pitch in pixels.
//   - line_height: Accepted vertical cell pitch in pixels.
//
// Side effects:
//   - Replaces retained query geometry with rounded positive integer dimensions.
terminal_publish_query_geometry :: proc(
    term: ^core.Terminal_State, dimensions: protocol.Terminal_Dimensions,
    column_width, line_height: f32) {
    title_state := term.output_interpreter.title_state
    if title_state == nil {
        return
    }
    cell_width := max(1, int(column_width + 0.5))
    cell_height := max(1, int(line_height + 0.5))
    title_state.query_geometry = {
        window_width = u32(dimensions.columns) * u32(cell_width),
        window_height = u32(dimensions.rows) * u32(cell_height),
        cell_width = u32(cell_width),
        cell_height = u32(cell_height),
        valid = true,
    }
}

// Convert a composed UTF-8 byte boundary into its physical cell column.
terminal_output_row_column_offset :: proc(
    cells: []termgrid.Cell, byte_offset: int) -> int {
    target := max(byte_offset, 0)
    for column in 0..=len(cells) {
        if terminal_output_row_byte_offset(cells, column) >= target {
            return column
        }
    }
    return len(cells)
}

// Relocate one primary view endpoint through an unpublished semantic reflow.
terminal_reflow_view_position :: proc(
    term: ^core.Terminal_State, prepared: ^termgrid.Prepared_Primary_Reflow,
    position: core.Terminal_View_Position) ->
    (core.Terminal_View_Position, bool) {
    cells, found := terminal_output_row(term, position.line)
    logical_row, logical_found := terminal_output_logical_row(term, position.line)
    if !found || !logical_found { return {}, false }
    column := terminal_output_row_column_offset(cells, position.byte_offset)
    semantic, semantic_found := termgrid.reflow_resolve_old(
        &prepared.reflow, {logical_row, column})
    relocated, relocated_found := termgrid.reflow_resolve_semantic(
        &prepared.reflow, semantic)
    if !semantic_found || !relocated_found { return {}, false }
    row := &prepared.reflow.rows[relocated.row]
    return {
        line = relocated.row,
        byte_offset = terminal_output_row_byte_offset(
            row.cells, relocated.column),
    }, true
}

// Relocate or evict one captured primary raster placement through reflow maps.
terminal_reflow_placement :: proc(
    user_data: rawptr, geometry: termattachment.Placement_Geometry) ->
    (termattachment.Placement_Geometry, bool) {
    ctx := cast(^Terminal_Placement_Reflow_Context)user_data
    semantic, old_found := termgrid.reflow_resolve_old(
        &ctx.primary.reflow, {geometry.logical_row, geometry.column})
    relocated, new_found := termgrid.reflow_resolve_semantic(
        &ctx.primary.reflow, semantic)
    logical_row, row_found := termgrid.primary_reflow_logical_row(
        ctx.primary, relocated.row)
    if !old_found || !new_found || !row_found { return {}, false }
    result := geometry
    result.logical_row = logical_row
    result.column = relocated.column
    return result, true
}

// Release every unpublished resize resource after failed preparation.
terminal_discard_prepared_resize :: proc(prepared: ^Prepared_Terminal_Resize) {
    if prepared == nil { return }
    termattachment.placement_checkpoint_destroy(&prepared.placements)
    termgrid.display_checkpoint_destroy(&prepared.synchronized_checkpoint)
    termgrid.display_checkpoint_destroy(&prepared.checkpoint)
    termgrid.grid_discard_prepared_resize(&prepared.alternate)
    termgrid.primary_reflow_destroy(&prepared.primary)
    prepared^ = {}
}

// Prepare a relocated live placement checkpoint without mutating the store.
terminal_prepare_resize_placements :: proc(
    term: ^core.Terminal_State, prepared: ^Prepared_Terminal_Resize,
    allocator: mem.Allocator) -> bool {
    attachments := term.synchronized_output.attachments
    if !termattachment.placement_checkpoint_init(
        &prepared.placements, attachments, allocator) ||
        !termattachment.placement_checkpoint_capture(
            &prepared.placements, attachments) { return false }
    ctx := Terminal_Placement_Reflow_Context{&prepared.primary}
    return termattachment.placement_checkpoint_relocate(
        &prepared.placements, .Primary, &ctx, terminal_reflow_placement)
}

// Prepare primary selection and viewport anchors in replacement coordinates.
terminal_prepare_resize_view_state :: proc(
    term: ^core.Terminal_State, prepared: ^Prepared_Terminal_Resize) {
    if !term.output_interpreter.alternate_screen_active &&
        (term.view_selection_active || term.view_selection_dragging) {
        prepared.selection_anchor = term.view_selection_anchor
        prepared.selection_head = term.view_selection_head
        anchor, anchor_ok := terminal_reflow_view_position(
            term, &prepared.primary, term.view_selection_anchor)
        head, head_ok := terminal_reflow_view_position(
            term, &prepared.primary, term.view_selection_head)
        prepared.selection_anchor = anchor
        prepared.selection_head = head
        prepared.selection_retained = anchor_ok && head_ok
    }
    prepared.scroll_offset_y = term.scroll_offset_y
    if term.output_interpreter.alternate_screen_active ||
        term.scroll_offset_y <= 0 { return }
    pitch := TERMINAL_FONT_SIZE + TERMINAL_LINE_SPACING
    anchor := core.Terminal_View_Position{
        line = int(term.scroll_offset_y / pitch),
    }
    relocated, retained := terminal_reflow_view_position(
        term, &prepared.primary, anchor)
    if retained { prepared.scroll_offset_y = f32(relocated.line) * pitch }
}

// Prepare semantic primary and coordinate-preserving alternate grid replacements.
terminal_prepare_resize_grids :: proc(
    term: ^core.Terminal_State, prepared: ^Prepared_Terminal_Resize,
    dimensions: protocol.Terminal_Dimensions, allocator: mem.Allocator) -> bool {
    primary_grid := &term.output_grid
    alternate_grid := &term.output_alternate_grid
    if term.output_interpreter.alternate_screen_active {
        primary_grid, alternate_grid = alternate_grid, primary_grid
    }
    source, source_ok := termgrid.primary_reflow_source(
        primary_grid, &term.output_scrollback, allocator)
    if !source_ok { return false }
    primary, primary_result := termgrid.primary_reflow_prepare(source, {
        old_grid = primary_grid,
        old_scrollback = &term.output_scrollback,
        columns = int(dimensions.columns),
        rows = int(dimensions.rows),
        allocator = allocator,
    })
    delete(source, allocator)
    if primary_result != .Prepared { return false }
    prepared.primary = primary
    alternate, result := termgrid.grid_prepare_resize(alternate_grid,
        int(dimensions.columns), int(dimensions.rows), allocator)
    if result != .Prepared { return false }
    prepared.alternate = alternate
    return true
}

//   Allocate both replacement grids and checkpoint before any visible mutation.
//
// Parameters:
//   - term: Terminal state supplying current grids, scrollback, and checkpoint contents.
//   - dimensions: Target protocol dimensions for both display grids.
//   - allocator: Resizable allocator owning replacement grid and checkpoint storage.
//
// Returns:
//   - Complete unpublished replacement resources and true, or empty and false after
//     discarding every resource acquired by a failed preparation.
//
// Side effects:
//   - Allocates prepared grid and checkpoint storage without changing visible state.
terminal_prepare_display_resize :: proc(
    term: ^core.Terminal_State, dimensions: protocol.Terminal_Dimensions,
    allocator: mem.Allocator) -> (Prepared_Terminal_Resize, bool) {
    prepared: Prepared_Terminal_Resize
    if !terminal_prepare_resize_grids(
        term, &prepared, dimensions, allocator) {
        terminal_discard_prepared_resize(&prepared); return {}, false
    }
    if !termgrid.display_checkpoint_reflow_init(
        &prepared.checkpoint, term.output_checkpoint, {
            template_grid = &prepared.primary.grid,
            scrollback = &prepared.primary.scrollback,
            columns = int(dimensions.columns),
            rows = int(dimensions.rows),
            allocator = allocator,
        }) {
        terminal_discard_prepared_resize(&prepared); return {}, false
    }
    if !termgrid.display_checkpoint_init(
        &prepared.synchronized_checkpoint, &prepared.primary.grid,
        &prepared.primary.scrollback, allocator) {
        terminal_discard_prepared_resize(&prepared); return {}, false
    }
    if !terminal_prepare_resize_placements(term, &prepared, allocator) {
        terminal_discard_prepared_resize(&prepared); return {}, false
    }
    terminal_prepare_resize_view_state(term, &prepared)
    return prepared, true
}

//   Return whether one stored selection endpoint remains representable after resize.
//
// Parameters:
//   - term: Terminal state supplying content, prompt, and scroll position.
//   - position: Combined-content selection endpoint, including virtual columns.
//   - dimensions: Candidate viewport dimensions after resize.
//
// Returns:
//   - True when both the endpoint line and its real or virtual column remain visible.
terminal_resize_selection_position_valid :: proc(
    term: ^core.Terminal_State, position: core.Terminal_View_Position,
    dimensions: protocol.Terminal_Dimensions) -> bool {
    real_lines := terminal_line_count(term)
    if terminal_prompt_visible(term) {
        real_lines += terminal_live_input_line_count(term)
    }
    viewport_end := int(term.scroll_offset_y /
        (TERMINAL_FONT_SIZE + TERMINAL_LINE_SPACING)) + int(dimensions.rows)
    if position.line < 0 || position.line >= max(real_lines, viewport_end) {
        return false
    }
    text := terminal_line_text(term, position.line)
    byte_offset := min(position.byte_offset, len(text))
    column := utf8.rune_count_in_string(text[:byte_offset]) +
        max(position.byte_offset - len(text), 0)
    return column <= int(dimensions.columns)
}

//   Clear a mouse selection when either endpoint falls outside resized geometry.
//
// Parameters:
//   - term: Terminal state owning view-selection endpoints and activity flags.
//   - dimensions: Newly accepted dimensions used to validate both endpoints.
//
// Side effects:
//   - Clears active and dragging flags when either endpoint is no longer representable.
terminal_reconcile_selection_after_resize :: proc(
    term: ^core.Terminal_State, dimensions: protocol.Terminal_Dimensions) {
    if !term.view_selection_active && !term.view_selection_dragging {
        return
    }
    if terminal_resize_selection_position_valid(
        term, term.view_selection_anchor, dimensions) &&
        terminal_resize_selection_position_valid(
            term, term.view_selection_head, dimensions) {
        return
    }
    term.view_selection_active = false
    term.view_selection_dragging = false
}

// Publish prepared grid and history storage and return superseded grid owners.
terminal_publish_resize_resources :: proc(
    term: ^core.Terminal_State, prepared: ^Prepared_Terminal_Resize,
    alternate_active: bool) -> Terminal_Superseded_Display {
    primary_grid := &term.output_grid
    alternate_grid := &term.output_alternate_grid
    if alternate_active { primary_grid, alternate_grid = alternate_grid, primary_grid }
    superseded := Terminal_Superseded_Display{primary_grid^, alternate_grid^}
    primary_grid^ = prepared.primary.grid
    prepared.primary.grid = {}
    alternate_grid^ = prepared.alternate.grid
    prepared.alternate = {}
    replacement := &prepared.primary.scrollback
    copy(term.output_scrollback.cells, replacement.cells)
    copy(term.output_scrollback.rows, replacement.rows)
    term.output_scrollback.count = replacement.count
    term.output_scrollback.first = replacement.first
    term.output_scrollback.committed_rows = replacement.committed_rows
    term.output_scrollback.evicted_rows = replacement.evicted_rows
    primary_grid.scrollback = {
        user_data = &term.output_scrollback,
        commit = termgrid.scrollback_sink_commit,
    }
    return superseded
}

// Publish resized ordinary and synchronized checkpoint storage.
terminal_publish_resize_checkpoints :: proc(
    term: ^core.Terminal_State, prepared: ^Prepared_Terminal_Resize) {
    termgrid.display_checkpoint_destroy(term.output_checkpoint)
    term.output_checkpoint^ = prepared.checkpoint
    prepared.checkpoint = {}
    termgrid.display_checkpoint_destroy(&term.synchronized_output.checkpoint)
    term.synchronized_output.checkpoint = prepared.synchronized_checkpoint
    prepared.synchronized_checkpoint = {}
    term.synchronized_output.scrollback = &term.output_scrollback
}

// Publish relocated selection and viewport state after replacement content exists.
terminal_publish_resize_view_state :: proc(
    term: ^core.Terminal_State, prepared: ^Prepared_Terminal_Resize,
    dimensions: protocol.Terminal_Dimensions, alternate_active: bool) {
    if !alternate_active &&
        (term.view_selection_active || term.view_selection_dragging) &&
        prepared.selection_retained {
        term.view_selection_anchor = prepared.selection_anchor
        term.view_selection_head = prepared.selection_head
    } else {
        terminal_reconcile_selection_after_resize(term, dimensions)
    }
    term.scroll_offset_y = prepared.scroll_offset_y
}

// Release all superseded and preparation-only resize resources.
terminal_finish_display_resize :: proc(
    prepared: ^Prepared_Terminal_Resize,
    superseded: ^Terminal_Superseded_Display) {
    termgrid.reflow_destroy(&prepared.primary.reflow)
    termattachment.placement_checkpoint_destroy(&prepared.placements)
    termgrid.grid_destroy(&superseded.alternate)
    termgrid.grid_destroy(&superseded.primary)
    termgrid.scrollback_destroy(&prepared.primary.scrollback)
}

// Publish prepared grids and reconcile interpreter geometry after resize.
terminal_publish_display_resize :: proc(
    term: ^core.Terminal_State, prepared: ^Prepared_Terminal_Resize,
    dimensions, old_dimensions: protocol.Terminal_Dimensions,
    alternate_active: bool) -> Terminal_Superseded_Display {
    superseded := terminal_publish_resize_resources(
        term, prepared, alternate_active)
    termemulator.interpreter_resize_state(
        &term.output_interpreter,
        int(old_dimensions.columns), int(old_dimensions.rows),
        int(dimensions.columns), int(dimensions.rows))
    if alternate_active {
        term.output_interpreter.primary_cursor = term.output_alternate_grid.cursor
    }
    return superseded
}

//   Replace both display grids and fixed-shape checkpoint as one transaction.
//
// Parameters:
//   - term: Terminal state owning primary, alternate, interpreter, and checkpoint state.
//   - dimensions: Target protocol dimensions for both display grids.
//   - allocator: Resizable allocator owning replacement resources.
//
// Returns:
//   - True after a no-op or complete transactional resize; false before visible mutation
//     when replacement preparation fails.
//
// Side effects:
//   - Replaces both grids and checkpoint, reconciles interpreter state and selection,
//     and releases superseded checkpoint storage after all preparation succeeds.
terminal_resize_display_grids :: proc(
    term: ^core.Terminal_State, dimensions: protocol.Terminal_Dimensions,
    allocator: mem.Allocator) -> bool {
    if term == nil {
        return false
    }
    columns, rows := int(dimensions.columns), int(dimensions.rows)
    if term.output_grid.columns == columns && term.output_grid.row_count == rows &&
        term.output_alternate_grid.columns == columns &&
        term.output_alternate_grid.row_count == rows {
        return true
    }
    termemulator.interpreter_publish_synchronized_output(
        &term.output_interpreter, true)
    prepared, prepared_ok := terminal_prepare_display_resize(
        term, dimensions, allocator)
    if !prepared_ok {
        return false
    }
    alternate_active := term.output_interpreter.alternate_screen_active
    old_dimensions := protocol.Terminal_Dimensions{
        u16(term.output_grid.columns), u16(term.output_grid.row_count)}
    if !termattachment.placement_checkpoint_restore(
        &prepared.placements, term.synchronized_output.attachments) {
        terminal_discard_prepared_resize(&prepared)
        return false
    }
    superseded := terminal_publish_display_resize(
        term, &prepared, dimensions, old_dimensions, alternate_active)
    terminal_publish_resize_checkpoints(term, &prepared)
    terminal_publish_resize_view_state(
        term, &prepared, dimensions, alternate_active)
    terminal_finish_display_resize(&prepared, &superseded)
    return true
}

//   Accept a changed viewport-derived geometry and advance its generation once.
//
// Parameters:
//   - term: Terminal state whose dimensions and display resources may change.
//   - font: Monospace font used to measure terminal column pitch.
//   - bounds: Full viewport bounds before terminal padding.
//
// Returns:
//   - A populated geometry change when new dimensions are committed; otherwise empty.
//
// Side effects:
//   - May transactionally resize display resources, update accepted metrics, advance
//     generation, increment rejection diagnostics, and log failed resize attempts.
terminal_update_geometry :: proc(
    term: ^core.Terminal_State, font: rl.Font,
    bounds: rl.Rectangle) -> Terminal_Geometry_Change {
    padded := terminal_padded_bounds(bounds)
    column_width := terminal_column_width(font)
    line_height := TERMINAL_FONT_SIZE + TERMINAL_LINE_SPACING
    candidate := terminal_dimensions_from_viewport(
        padded.width, padded.height, column_width, line_height,
        term.dimension_limits)
    if candidate.valid && candidate.dimensions != term.geometry.dimensions &&
        !terminal_resize_display_grids(
            term, candidate.dimensions, term.output_grid.allocator) {
        term.rejected_geometry_count += 1
        log.warnf(
            "terminal geometry rejected columns=%d rows=%d generation=%d",
            candidate.dimensions.columns, candidate.dimensions.rows,
            term.geometry.generation)
        return {}
    }
    return terminal_accept_geometry(term, candidate, column_width, line_height)
}

//   Borrow one font for the current draw operation.
//
// Parameters:
//   - resolver: Borrowing callback and owner context for the active font cache.
//   - key: Semantic font variant requested by terminal content.
//
// Returns:
//   - The resolved Raylib font borrowed for the current draw operation.
terminal_font_resolve :: proc(
    resolver: font.Font_Resolver, key: font.Font_Key) -> rl.Font {

    assert(resolver.resolve != nil)
    return resolver.resolve(resolver.user_data, key)
}

//   Select semantic font identity from a terminal text style.
//
// Parameters:
//   - style: Terminal-history style carrying weight, bold, and italic attributes.
//
// Returns:
//   - The semantic font key matching the effective weight and italic state.
terminal_font_key_for_style :: proc(
    style: termhist.Termhist_Text_Style) -> font.Font_Key {

    weight := style.font_weight
    if style.is_bold && weight == .Regular {
        weight = .Bold
    }

    switch weight {
    case .Light:
        return .Light_Italic if style.is_italic else .Light
    case .Medium:
        return .Medium_Italic if style.is_italic else .Medium
    case .Semi_Bold:
        return .Semi_Bold_Italic if style.is_italic else .Semi_Bold
    case .Bold:
        return .Bold_Italic if style.is_italic else .Bold
    case .Extra_Bold:
        return .Extra_Bold_Italic if style.is_italic else .Extra_Bold
    case .Black:
        return .Black_Italic if style.is_italic else .Black
    case .Regular:
        return .Regular_Italic if style.is_italic else .Regular
    }
    return .Regular_Italic if style.is_italic else .Regular
}
