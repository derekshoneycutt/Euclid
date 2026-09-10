package termgrid

import "core:mem"
import termattachment "../attachment"
import termmodel "../model"

// One borrowed chronological physical row supplied to semantic reflow.
Reflow_Source_Row :: struct {
    cells: []Cell,
    logical_row_id: i64,
    wrapped: bool,
    shell_markers: termmodel.Shell_Row_Markers,
    logical_line_id: termmodel.Terminal_Logical_Line_Id,
    grapheme_offset: u32,
    head_truncated: bool,
}

// One old physical boundary used as an input relocation key.
Reflow_Old_Position :: struct {
    logical_row_id: i64,
    column: int,
}

// One replacement row and its position within the owning logical line.
Reflow_Row :: struct {
    cells: []Cell,
    logical_line_id: termmodel.Terminal_Logical_Line_Id,
    grapheme_offset: u32,
    wrapped: bool,
    head_truncated: bool,
    shell_markers: termmodel.Shell_Row_Markers,
}

// One replacement physical boundary produced for a semantic position.
Reflow_New_Position :: struct {
    row: int,
    column: int,
}

// Mapping from an old physical boundary to geometry-independent identity.
Reflow_Old_To_Semantic :: struct {
    old: Reflow_Old_Position,
    semantic: termmodel.Terminal_Semantic_Position,
}

// Mapping from geometry-independent identity to one retained replacement boundary.
Reflow_Semantic_To_New :: struct {
    semantic: termmodel.Terminal_Semantic_Position,
    new: Reflow_New_Position,
}

// Preparation outcome for one bounded semantic reflow operation.
Reflow_Result :: enum {
    Prepared,
    Invalid_Input,
    Cell_Too_Wide,
    Relocation_Capacity_Exceeded,
    Allocation_Failed,
}

// Allocator-owned replacement rows and deterministic bidirectional relocation maps.
Prepared_Reflow :: struct {
    allocator: mem.Allocator,
    cells: []Cell,
    rows: []Reflow_Row,
    old_to_semantic: []Reflow_Old_To_Semantic,
    semantic_to_new: []Reflow_Semantic_To_New,
    evicted_rows: int,
    ready: bool,
}

// Complete unpublished primary grid and scrollback replacement.
Prepared_Primary_Reflow :: struct {
    grid: Grid,
    scrollback: Scrollback,
    reflow: Prepared_Reflow,
    grid_row_start: int,
    first_logical_row_id: i64,
    ready: bool,
}

// Captured-placement relocation context for one independently reflowed checkpoint.
Reflow_Checkpoint_Placement_Context :: struct {
    reflow: ^Prepared_Reflow,
    first_logical_row_id: i64,
}

// Dependencies and target geometry for one prepared primary reflow.
Primary_Reflow_Request :: struct {
    old_grid: ^Grid,
    old_scrollback: ^Scrollback,
    columns: int,
    rows: int,
    allocator: mem.Allocator,
}

// Shape dependencies for independently rebuilding one display checkpoint.
Display_Checkpoint_Reflow_Request :: struct {
    template_grid: ^Grid,
    scrollback: ^Scrollback,
    columns: int,
    rows: int,
    allocator: mem.Allocator,
}

// Preflight counts and outcome used to allocate exact prepared storage.
Reflow_Measure :: struct {
    row_count: int,
    grapheme_count: int,
    old_boundary_count: int,
    result: Reflow_Result,
}

// Exact storage shape for one failure-atomic reflow allocation.
Reflow_Allocation_Shape :: struct {
    rows: int,
    columns: int,
    old_boundaries: int,
    semantic_boundaries: int,
}

// Mutable cursors for one chronological replacement emission pass.
Reflow_Emit_State :: struct {
    global_row: int,
    column: int,
    retained_start: int,
    logical_line_id: termmodel.Terminal_Logical_Line_Id,
    line_offset: u32,
    old_index: int,
    semantic_index: int,
    retained_row: int,
}

// Return the occupied prefix while preserving explicit space cells as content.
reflow_occupied_columns :: proc(cells: []Cell) -> int {
    result := 0
    for cell, column in cells {
        if cell.width > 0 || cell.continuation {
            result = column + 1
        }
    }
    return result
}

// Report whether one source row contains only complete leading-cell geometry.
reflow_source_cells_valid :: proc(cells: []Cell) -> bool {
    if len(cells) == 0 { return false }
    for cell, column in cells {
        if cell.continuation {
            if column == 0 || cells[column - 1].width != 2 { return false }
            continue
        }
        if cell.width > 2 { return false }
        if cell.width == 2 &&
            (column + 1 >= len(cells) || !cells[column + 1].continuation) {
            return false
        }
    }
    return true
}

// Measure one valid source row into the aggregate target shape.
reflow_measure_cells :: proc(
    result: ^Reflow_Measure, column: ^int, cells: []Cell,
    columns: int) -> Reflow_Result {
    used := reflow_occupied_columns(cells)
    for cell in cells[:used] {
        if cell.continuation || cell.width < 1 { continue }
        width := int(cell.width)
        if width > columns { return .Cell_Too_Wide }
        if column^ + width > columns {
            result.row_count += 1
            column^ = 0
        }
        column^ += width
        result.grapheme_count += 1
    }
    return .Prepared
}

// Count leading graphemes and emitted rows without allocating replacement state.
reflow_measure :: proc(
    source: []Reflow_Source_Row, columns: int) -> Reflow_Measure {
    if len(source) == 0 || columns < 1 {
        return {result = .Invalid_Input}
    }
    result := Reflow_Measure{row_count = 1, result = .Prepared}
    column := 0
    current_line_id: termmodel.Terminal_Logical_Line_Id
    for source_row, source_index in source {
        line_id := source_row.logical_line_id if
            source_row.logical_line_id != 0 else
            termmodel.Terminal_Logical_Line_Id(source_row.logical_row_id)
        if source_index > 0 && source[source_index - 1].wrapped &&
            source_row.logical_line_id == 0 {
            line_id = current_line_id
        }
        if source_row.logical_row_id == 0 ||
            (source_index > 0 && source_row.logical_row_id <=
                source[source_index - 1].logical_row_id) ||
            (source_index > 0 && source[source_index - 1].wrapped &&
                line_id != current_line_id) ||
            !reflow_source_cells_valid(source_row.cells) {
            return {result = .Invalid_Input}
        }
        current_line_id = line_id
        result.old_boundary_count += len(source_row.cells) + 1
        measure_result := reflow_measure_cells(
            &result, &column, source_row.cells, columns)
        if measure_result != .Prepared { return {result = measure_result} }
        if !source_row.wrapped && source_index + 1 < len(source) {
            result.row_count += 1
            column = 0
        }
    }
    return result
}

// Publish one retained semantic boundary, replacing an equivalent row-end mapping.
reflow_publish_semantic :: proc(
    prepared: ^Prepared_Reflow, entry: Reflow_Semantic_To_New,
    semantic_index: ^int) {
    if semantic_index^ > 0 &&
        prepared.semantic_to_new[semantic_index^ - 1].semantic == entry.semantic {
        prepared.semantic_to_new[semantic_index^ - 1] = entry
        return
    }
    prepared.semantic_to_new[semantic_index^] = entry
    semantic_index^ += 1
}

// Release all storage owned by an uncommitted or inspected reflow result.
reflow_destroy :: proc(prepared: ^Prepared_Reflow) {
    if prepared == nil { return }
    delete(prepared.semantic_to_new, prepared.allocator)
    delete(prepared.old_to_semantic, prepared.allocator)
    delete(prepared.rows, prepared.allocator)
    delete(prepared.cells, prepared.allocator)
    prepared^ = {}
}

// Release every resource owned by an uncommitted primary reflow candidate.
primary_reflow_destroy :: proc(prepared: ^Prepared_Primary_Reflow) {
    if prepared == nil { return }
    reflow_destroy(&prepared.reflow)
    grid_destroy(&prepared.grid)
    scrollback_destroy(&prepared.scrollback)
    prepared^ = {}
}

// Allocate every prepared-reflow array as one failure-atomic candidate.
reflow_allocate :: proc(
    prepared: ^Prepared_Reflow, shape: Reflow_Allocation_Shape,
    allocator: mem.Allocator) -> bool {
    prepared.allocator = allocator
    prepared.cells, _ = make([]Cell, shape.rows*shape.columns, allocator)
    prepared.rows, _ = make([]Reflow_Row, shape.rows, allocator)
    prepared.old_to_semantic, _ = make(
        []Reflow_Old_To_Semantic, shape.old_boundaries, allocator)
    prepared.semantic_to_new, _ = make(
        []Reflow_Semantic_To_New, shape.semantic_boundaries, allocator)
    if prepared.cells == nil || prepared.rows == nil ||
        prepared.old_to_semantic == nil || prepared.semantic_to_new == nil {
        reflow_destroy(prepared)
        return false
    }
    for row_index in 0..<shape.rows {
        start := row_index * shape.columns
        prepared.rows[row_index].cells =
            prepared.cells[start:start + shape.columns]
    }
    return true
}

// Append one old-row boundary map using the current semantic grapheme offset.
reflow_map_old_row :: proc(
    prepared: ^Prepared_Reflow, source: Reflow_Source_Row,
    state: ^Reflow_Emit_State) {
    grapheme_offset := state.line_offset
    for column in 0..=len(source.cells) {
        prepared.old_to_semantic[state.old_index] = {
            old = {source.logical_row_id, column},
            semantic = {state.logical_line_id, grapheme_offset},
        }
        state.old_index += 1
        if column == len(source.cells) { continue }
        cell := &source.cells[column]
        if !cell.continuation && cell.width > 0 {
            grapheme_offset += 1
        }
    }
}

// Start one retained replacement row and publish its semantic head boundary.
reflow_start_row :: proc(
    prepared: ^Prepared_Reflow, state: ^Reflow_Emit_State) {
    state.retained_row = state.global_row - state.retained_start
    if state.retained_row < 0 { return }
    row := &prepared.rows[state.retained_row]
    row.logical_line_id = state.logical_line_id
    row.grapheme_offset = state.line_offset
    entry := Reflow_Semantic_To_New{
        semantic = {state.logical_line_id, state.line_offset},
        new = {state.retained_row, 0},
    }
    reflow_publish_semantic(prepared, entry, &state.semantic_index)
}

// Publish the boundary following one retained emitted grapheme.
reflow_publish_cell_end :: proc(
    prepared: ^Prepared_Reflow, state: ^Reflow_Emit_State) {
    if state.retained_row < 0 { return }
    reflow_publish_semantic(prepared, {
        semantic = {state.logical_line_id, state.line_offset},
        new = {state.retained_row, state.column},
    }, &state.semantic_index)
}

// Emit one source leader, wrapping atomically before a width-two boundary.
reflow_emit_cell :: proc(
    prepared: ^Prepared_Reflow, cells: []Cell, cell_index, columns: int,
    state: ^Reflow_Emit_State) {
    cell := &cells[cell_index]
    width := int(cell.width)
    if state.column + width > columns {
        if state.retained_row >= 0 {
            prepared.rows[state.retained_row].wrapped = true
        }
        state.global_row += 1
        state.column = 0
        reflow_start_row(prepared, state)
    }
    if state.retained_row >= 0 {
        copy(prepared.rows[state.retained_row].cells[
            state.column:state.column + width],
            cells[cell_index:cell_index + width])
    }
    state.column += width
    state.line_offset += 1
    reflow_publish_cell_end(prepared, state)
}

// Start the next hard-bounded logical row after one source row.
reflow_advance_source_row :: proc(
    prepared: ^Prepared_Reflow, source: []Reflow_Source_Row,
    source_index: int, state: ^Reflow_Emit_State) {
    if source[source_index].wrapped || source_index + 1 >= len(source) { return }
    state.global_row += 1
    state.column = 0
    next := source[source_index + 1]
    state.logical_line_id = next.logical_line_id if
        next.logical_line_id != 0 else
        termmodel.Terminal_Logical_Line_Id(next.logical_row_id)
    state.line_offset = next.grapheme_offset
    reflow_start_row(prepared, state)
}

// Emit retained grapheme cells and semantic boundaries at one target width.
reflow_emit :: proc(
    prepared: ^Prepared_Reflow, source: []Reflow_Source_Row,
    columns, retained_start: int) {
    first_line_id := source[0].logical_line_id if
        source[0].logical_line_id != 0 else
        termmodel.Terminal_Logical_Line_Id(source[0].logical_row_id)
    state := Reflow_Emit_State{
        retained_start = retained_start,
        logical_line_id = first_line_id,
        line_offset = source[0].grapheme_offset,
    }
    reflow_start_row(prepared, &state)
    for source_row, source_index in source {
        if source_row.logical_line_id != 0 {
            state.logical_line_id = source_row.logical_line_id
            state.line_offset = source_row.grapheme_offset
        }
        reflow_map_old_row(prepared, source_row, &state)
        used := reflow_occupied_columns(source_row.cells)
        for cell_index := 0; cell_index < used; cell_index += 1 {
            cell := &source_row.cells[cell_index]
            if cell.continuation || cell.width == 0 { continue }
            reflow_emit_cell(prepared, source_row.cells, cell_index,
                columns, &state)
        }
        reflow_advance_source_row(prepared, source, source_index, &state)
    }
    prepared.semantic_to_new =
        prepared.semantic_to_new[:state.semantic_index]
}

// Resolve one old physical boundary through a prepared semantic map.
reflow_resolve_old :: proc(
    prepared: ^Prepared_Reflow, old: Reflow_Old_Position) ->
    (termmodel.Terminal_Semantic_Position, bool) {
    if prepared == nil { return {}, false }
    for entry in prepared.old_to_semantic {
        if entry.old == old { return entry.semantic, true }
    }
    return {}, false
}

// Resolve one retained semantic boundary to replacement row and column.
reflow_resolve_semantic :: proc(
    prepared: ^Prepared_Reflow, semantic: termmodel.Terminal_Semantic_Position) ->
    (Reflow_New_Position, bool) {
    if prepared == nil { return {}, false }
    for entry in prepared.semantic_to_new {
        if entry.semantic == semantic { return entry.new, true }
    }
    return {}, false
}

// Relocate row-local shell markers through the prepared bidirectional maps.
reflow_relocate_shell_markers :: proc(
    prepared: ^Prepared_Reflow, source: []Reflow_Source_Row) {
    for source_row in source {
        for kind in termmodel.Shell_Marker_Kind {
            if !source_row.shell_markers.present[kind] { continue }
            semantic, old_found := reflow_resolve_old(prepared, {
                source_row.logical_row_id,
                int(source_row.shell_markers.columns[kind]),
            })
            position, new_found := reflow_resolve_semantic(prepared, semantic)
            if !old_found || !new_found { continue }
            markers := &prepared.rows[position.row].shell_markers
            markers.present[kind] = true
            markers.columns[kind] = u16(position.column)
            if kind == .Finished {
                markers.finished_status = source_row.shell_markers.finished_status
                markers.finished_status_present =
                    source_row.shell_markers.finished_status_present
            }
        }
    }
}

// Prepare bounded replacement rows without mutating or retaining source storage.
reflow_prepare :: proc(
    source: []Reflow_Source_Row, columns, row_capacity: int,
    allocator: mem.Allocator, relocation_capacity := int(max(int))) ->
    (Prepared_Reflow, Reflow_Result) {
    if row_capacity < 1 { return {}, .Invalid_Input }
    measure := reflow_measure(source, columns)
    if measure.result != .Prepared { return {}, measure.result }
    if measure.old_boundary_count + measure.grapheme_count +
        measure.row_count > relocation_capacity {
        return {}, .Relocation_Capacity_Exceeded
    }
    retained_rows := min(measure.row_count, row_capacity)
    prepared: Prepared_Reflow
    shape := Reflow_Allocation_Shape{
        rows = retained_rows,
        columns = columns,
        old_boundaries = measure.old_boundary_count,
        semantic_boundaries = measure.grapheme_count + measure.row_count,
    }
    if !reflow_allocate(&prepared, shape, allocator) {
        return {}, .Allocation_Failed
    }
    prepared.evicted_rows = measure.row_count - retained_rows
    reflow_emit(&prepared, source, columns, prepared.evicted_rows)
    if prepared.evicted_rows > 0 && len(prepared.rows) > 0 &&
        prepared.rows[0].grapheme_offset > 0 {
        prepared.rows[0].head_truncated = true
    }
    reflow_relocate_shell_markers(&prepared, source)
    prepared.ready = true
    return prepared, .Prepared
}

// Copy non-row grid state before semantic rows and cursor are materialized.
primary_reflow_copy_grid_state :: proc(source, destination: ^Grid) {
    destination.style = source.style
    destination.hyperlink = source.hyperlink
    destination.pending_utf8 = source.pending_utf8
    destination.pending_utf8_len = source.pending_utf8_len
    destination.invalid_utf8_count = source.invalid_utf8_count
    destination.truncated_grapheme_count = source.truncated_grapheme_count
    grid_copy_resize_editing_state(source, destination)
    destination.editing.next_logical_row_id = source.editing.next_logical_row_id
}

// Assign one fresh physical identity while copying a prepared semantic row.
primary_reflow_copy_row :: proc(
    destination: ^Row, source: ^Reflow_Row, logical_row_id: i64) {
    copy(destination.cells, source.cells)
    destination.logical_id = logical_row_id
    destination.logical_line_id = source.logical_line_id
    destination.grapheme_offset = source.grapheme_offset
    destination.head_truncated = source.head_truncated
    destination.wrapped = source.wrapped
    destination.shell_markers = source.shell_markers
    destination.dirty = true
    destination.dirty_end = len(destination.cells)
}

// Materialize prepared rows with fresh physical identities into both destinations.
primary_reflow_materialize_rows :: proc(
    prepared: ^Prepared_Primary_Reflow, old_grid: ^Grid, rows: int) -> bool {
    prepared.grid_row_start = max(len(prepared.reflow.rows) - rows, 0)
    next_id := old_grid.editing.next_logical_row_id
    for &row, row_index in prepared.reflow.rows {
        next_id += 1
        if next_id <= 0 { next_id = 1 }
        if row_index < prepared.grid_row_start {
            if !scrollback_commit(&prepared.scrollback, row.cells, {
                logical_row_id = next_id,
                wrapped = row.wrapped,
                shell_markers = row.shell_markers,
                logical_line_id = row.logical_line_id,
                grapheme_offset = row.grapheme_offset,
                head_truncated = row.head_truncated,
            }) { return false }
            continue
        }
        target_row := row_index - prepared.grid_row_start
        primary_reflow_copy_row(&prepared.grid.rows[target_row], &row, next_id)
    }
    prepared.first_logical_row_id = next_id -
        i64(len(prepared.reflow.rows)) + 1
    prepared.grid.editing.next_logical_row_id = next_id
    for row_index in len(prepared.reflow.rows) - prepared.grid_row_start..<rows {
        grid_reset_row_identity(&prepared.grid, row_index)
    }
    return true
}

// Relocate the active primary cursor, including its delayed-wrap boundary.
primary_reflow_relocate_cursor :: proc(
    prepared: ^Prepared_Primary_Reflow, old_grid: ^Grid,
    columns, rows: int) {
    semantic, old_found := reflow_resolve_old(&prepared.reflow, {
        old_grid.rows[old_grid.cursor.row].logical_id,
        old_grid.cursor.column + int(old_grid.cursor.wrap_pending),
    })
    cursor, new_found := reflow_resolve_semantic(&prepared.reflow, semantic)
    if old_found && new_found && cursor.row >= prepared.grid_row_start {
        prepared.grid.cursor = {
            row = cursor.row - prepared.grid_row_start,
            column = clamp(cursor.column, 0, columns - 1),
            wrap_pending = old_grid.cursor.wrap_pending && cursor.column >= columns,
        }
        return
    }
    prepared.grid.cursor = grid_resize_cursor(
        old_grid.cursor, old_grid.columns, old_grid.row_count, columns, rows)
}

// Initialize unpublished scrollback and grid destinations for primary reflow.
primary_reflow_initialize_destinations :: proc(
    prepared: ^Prepared_Primary_Reflow,
    request: Primary_Reflow_Request) -> bool {
    old_grid, old_scrollback := request.old_grid, request.old_scrollback
    if !scrollback_init(
        &prepared.scrollback, old_scrollback.columns, old_scrollback.capacity,
        request.allocator, {
            attachment_store = old_scrollback.attachment_store,
            shell_integration = old_scrollback.shell_integration,
        }) { return false }
    if !grid_init(&prepared.grid, request.columns, request.rows,
        request.allocator, {
        scrollback = {},
        ambiguous_width = old_grid.editing.ambiguous_width,
        attachment_store = old_grid.editing.attachment_store,
        screen = .Primary,
    }) { return false }
    return true
}

// Prepare the chronological primary stream as replacement history and viewport.
primary_reflow_prepare :: proc(
    source: []Reflow_Source_Row, request: Primary_Reflow_Request) ->
    (Prepared_Primary_Reflow, Reflow_Result) {
    old_grid, old_scrollback := request.old_grid, request.old_scrollback
    columns, rows := request.columns, request.rows
    allocator := request.allocator
    if old_grid == nil || old_scrollback == nil || columns < 1 || rows < 1 {
        return {}, .Invalid_Input
    }
    prepared: Prepared_Primary_Reflow
    reflow, result := reflow_prepare(
        source, columns, old_scrollback.capacity + rows, allocator)
    if result != .Prepared { return {}, result }
    prepared.reflow = reflow
    if !primary_reflow_initialize_destinations(&prepared, request) {
        primary_reflow_destroy(&prepared)
        return {}, .Allocation_Failed
    }
    primary_reflow_copy_grid_state(old_grid, &prepared.grid)
    if !primary_reflow_materialize_rows(&prepared, old_grid, rows) {
        primary_reflow_destroy(&prepared)
        return {}, .Invalid_Input
    }
    primary_reflow_relocate_cursor(&prepared, old_grid, columns, rows)
    prepared.scrollback.committed_rows = old_scrollback.committed_rows
    prepared.scrollback.evicted_rows = old_scrollback.evicted_rows +
        u64(prepared.reflow.evicted_rows)
    prepared.ready = true
    return prepared, .Prepared
}

// Return the fresh physical row identity for one retained reflow row.
primary_reflow_logical_row :: proc(
    prepared: ^Prepared_Primary_Reflow, row: int) -> (i64, bool) {
    if prepared == nil || !prepared.ready || row < 0 ||
        row >= len(prepared.reflow.rows) {
        return 0, false
    }
    return prepared.first_logical_row_id + i64(row), true
}

// Convert one scrollback row view into a borrowed reflow descriptor.
primary_reflow_scrollback_source :: proc(row: Scrollback_Row_View) ->
    Reflow_Source_Row {
    return {
        cells = row.cells,
        logical_row_id = row.logical_id,
        wrapped = row.wrapped,
        shell_markers = row.shell_markers,
        logical_line_id = row.logical_line_id,
        grapheme_offset = row.grapheme_offset,
        head_truncated = row.head_truncated,
    }
}

// Convert one grid row into a borrowed reflow descriptor.
primary_reflow_grid_source :: proc(row: ^Row) -> Reflow_Source_Row {
    return {
        cells = row.cells,
        logical_row_id = row.logical_id,
        wrapped = row.wrapped,
        shell_markers = row.shell_markers,
        logical_line_id = row.logical_line_id,
        grapheme_offset = row.grapheme_offset,
        head_truncated = row.head_truncated,
    }
}

// Allocate borrowed chronological source descriptors for primary history and grid.
primary_reflow_source :: proc(
    grid: ^Grid, scrollback: ^Scrollback, allocator: mem.Allocator) ->
    ([]Reflow_Source_Row, bool) {
    if grid == nil || scrollback == nil { return nil, false }
    grid_count := clamp(grid.cursor.row + 1, 1, len(grid.rows))
    for row_index := len(grid.rows) - 1; row_index >= grid_count; row_index -= 1 {
        if reflow_occupied_columns(grid.rows[row_index].cells) > 0 {
            grid_count = row_index + 1
            break
        }
    }
    source, allocation_error := make(
        []Reflow_Source_Row, scrollback.count + grid_count, allocator)
    if allocation_error != nil { return nil, false }
    for index in 0..<scrollback.count {
        row, found := scrollback_row(scrollback, index)
        if !found { delete(source, allocator); return nil, false }
        source[index] = primary_reflow_scrollback_source(row)
    }
    for row_index in 0..<grid_count {
        row := &grid.rows[row_index]
        source[scrollback.count + row_index] = primary_reflow_grid_source(row)
    }
    return source, true
}

// Allocate chronological source descriptors borrowed from one valid checkpoint.
reflow_checkpoint_source :: proc(
    checkpoint: ^Display_Checkpoint, allocator: mem.Allocator) ->
    ([]Reflow_Source_Row, bool) {
    if checkpoint == nil || !checkpoint.valid { return nil, false }
    grid_count := clamp(
        checkpoint.grid_cursor.row + 1, 1, len(checkpoint.grid_rows))
    for row_index := len(checkpoint.grid_rows) - 1;
        row_index >= grid_count; row_index -= 1 {
        cells, found := display_checkpoint_grid_row(checkpoint, row_index)
        if found && reflow_occupied_columns(cells) > 0 {
            grid_count = row_index + 1
            break
        }
    }
    source, allocation_error := make([]Reflow_Source_Row,
        checkpoint.scrollback_count + grid_count, allocator)
    if allocation_error != nil { return nil, false }
    for index in 0..<checkpoint.scrollback_count {
        row, found := display_checkpoint_scrollback_row(checkpoint, index)
        if !found { delete(source, allocator); return nil, false }
        source[index] = {row.cells, row.logical_id, row.wrapped,
            row.shell_markers, row.logical_line_id, row.grapheme_offset,
            row.head_truncated}
    }
    for row_index in 0..<grid_count {
        cells, found := display_checkpoint_grid_row(checkpoint, row_index)
        if !found { delete(source, allocator); return nil, false }
        row := checkpoint.grid_rows[row_index]
        source[checkpoint.scrollback_count + row_index] = {
            cells, row.logical_id, row.wrapped, row.shell_markers,
            row.logical_line_id, row.grapheme_offset, row.head_truncated,
        }
    }
    return source, true
}

// Relocate one placement captured by an independently reflowed checkpoint.
reflow_checkpoint_placement :: proc(
    user_data: rawptr, geometry: termattachment.Placement_Geometry) ->
    (termattachment.Placement_Geometry, bool) {
    ctx := cast(^Reflow_Checkpoint_Placement_Context)user_data
    semantic, old_found := reflow_resolve_old(
        ctx.reflow, {geometry.logical_row, geometry.column})
    relocated, new_found := reflow_resolve_semantic(ctx.reflow, semantic)
    if !old_found || !new_found { return {}, false }
    result := geometry
    result.logical_row = ctx.first_logical_row_id + i64(relocated.row)
    result.column = relocated.column
    return result, true
}

// Materialize retained history rows into an initialized checkpoint.
reflow_checkpoint_scrollback_rows :: proc(
    destination: ^Display_Checkpoint, reflow: ^Prepared_Reflow,
    columns, grid_start: int, first_logical_row_id: i64) {
    storage_columns := len(destination.scrollback_cells) /
        len(destination.scrollback_rows)
    destination.scrollback_count = grid_start
    destination.scrollback_first = 0
    for row_index in 0..<grid_start {
        row := &reflow.rows[row_index]
        start := row_index * storage_columns
        copy(destination.scrollback_cells[start:start + columns], row.cells)
        destination.scrollback_rows[row_index] = {
            logical_id = first_logical_row_id + i64(row_index),
            logical_line_id = row.logical_line_id,
            grapheme_offset = row.grapheme_offset,
            head_truncated = row.head_truncated,
            columns = columns,
            wrapped = row.wrapped,
            shell_markers = row.shell_markers,
        }
    }
}

// Materialize retained viewport rows into an initialized checkpoint.
reflow_checkpoint_grid_rows :: proc(
    destination: ^Display_Checkpoint, reflow: ^Prepared_Reflow,
    columns, grid_start: int, first_logical_row_id: i64) {
    for row_index in grid_start..<len(reflow.rows) {
        target := row_index - grid_start
        start := target * columns
        copy(destination.grid_cells[start:start + columns],
            reflow.rows[row_index].cells)
        row := &reflow.rows[row_index]
        destination.grid_rows[target] = {
            logical_id = first_logical_row_id + i64(row_index),
            logical_line_id = row.logical_line_id,
            grapheme_offset = row.grapheme_offset,
            head_truncated = row.head_truncated,
            dirty = true,
            dirty_end = columns,
            wrapped = row.wrapped,
            shell_markers = row.shell_markers,
        }
    }
}

// Materialize semantic rows into an initialized fixed-shape checkpoint.
reflow_checkpoint_rows :: proc(
    destination: ^Display_Checkpoint, reflow: ^Prepared_Reflow,
    columns, rows: int, first_logical_row_id: i64) {
    grid_start := max(len(reflow.rows) - rows, 0)
    reflow_checkpoint_scrollback_rows(
        destination, reflow, columns, grid_start, first_logical_row_id)
    reflow_checkpoint_grid_rows(
        destination, reflow, columns, grid_start, first_logical_row_id)
}

// Copy non-cursor checkpoint state that is independent of physical row topology.
reflow_checkpoint_copy_state :: proc(
    destination, source: ^Display_Checkpoint, rows: int,
    next_logical_row_id: i64, evicted_rows: int) {
    display_checkpoint_copy_shell(destination, source)
    destination.grid_style = source.grid_style
    destination.grid_hyperlink = source.grid_hyperlink
    destination.grid_scroll_top = clamp(source.grid_scroll_top, 0, rows - 1)
    destination.grid_scroll_bottom = rows - 1
    destination.grid_origin_mode = source.grid_origin_mode
    destination.grid_autowrap_mode = source.grid_autowrap_mode
    destination.grid_insert_mode = source.grid_insert_mode
    destination.grid_protected_mode = source.grid_protected_mode
    destination.grid_tab_stops = source.grid_tab_stops
    destination.grid_next_logical_row_id = next_logical_row_id
    destination.scrollback_committed_rows = source.scrollback_committed_rows
    destination.scrollback_evicted_rows = source.scrollback_evicted_rows +
        u64(evicted_rows)
}

// Relocate one checkpoint cursor through its independently prepared reflow.
reflow_checkpoint_cursor :: proc(
    destination, source: ^Display_Checkpoint, reflow: ^Prepared_Reflow,
    columns, rows: int) {
    semantic, old_found := reflow_resolve_old(reflow, {
        source.grid_rows[source.grid_cursor.row].logical_id,
        source.grid_cursor.column + int(source.grid_cursor.wrap_pending),
    })
    cursor, new_found := reflow_resolve_semantic(reflow, semantic)
    grid_start := max(len(reflow.rows) - rows, 0)
    if old_found && new_found && cursor.row >= grid_start {
        destination.grid_cursor = {
            row = cursor.row - grid_start,
            column = clamp(cursor.column, 0, columns - 1),
            wrap_pending = source.grid_cursor.wrap_pending &&
                cursor.column >= columns,
        }
        return
    }
    destination.grid_cursor = grid_resize_cursor(source.grid_cursor,
        len(source.grid_cells) / len(source.grid_rows),
        len(source.grid_rows), columns, rows)
}

// Copy and relocate one checkpoint's captured placement table.
reflow_checkpoint_placements :: proc(
    destination, source: ^Display_Checkpoint, reflow: ^Prepared_Reflow,
    first_logical_row_id: i64) -> bool {
    if !source.placements.valid { return true }
    if !termattachment.placement_checkpoint_copy(
        &destination.placements, &source.placements) { return false }
    ctx := Reflow_Checkpoint_Placement_Context{reflow, first_logical_row_id}
    return termattachment.placement_checkpoint_relocate(
        &destination.placements, .Primary, &ctx,
        reflow_checkpoint_placement)
}

// Initialize a resized checkpoint by semantically reflowing its captured content.
display_checkpoint_reflow_init :: proc(
    destination, source: ^Display_Checkpoint,
    request: Display_Checkpoint_Reflow_Request) -> bool {
    columns, rows := request.columns, request.rows
    allocator := request.allocator
    if !display_checkpoint_init(
        destination, request.template_grid, request.scrollback, allocator) {
        return false
    }
    if source == nil || !source.valid { return true }
    descriptors, source_ok := reflow_checkpoint_source(source, allocator)
    if !source_ok { display_checkpoint_destroy(destination); return false }
    reflow, result := reflow_prepare(
        descriptors, columns, len(request.scrollback.rows) + rows, allocator)
    delete(descriptors, allocator)
    if result != .Prepared {
        display_checkpoint_destroy(destination); return false
    }
    defer reflow_destroy(&reflow)
    first_id := source.grid_next_logical_row_id + 1
    reflow_checkpoint_rows(destination, &reflow, columns, rows, first_id)
    reflow_checkpoint_copy_state(destination, source, rows,
        first_id + i64(len(reflow.rows)) - 1, reflow.evicted_rows)
    reflow_checkpoint_cursor(destination, source, &reflow, columns, rows)
    if !reflow_checkpoint_placements(destination, source, &reflow, first_id) {
        display_checkpoint_destroy(destination); return false
    }
    destination.valid = true
    return true
}