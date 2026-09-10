package termgrid

import "core:mem"
import termattachment "../attachment"
import termmodel "../model"
import termshellintegration "../shell_integration"

// Per-slot metadata stored separately from one scrollback row's exact cells.
Scrollback_Row :: struct {
    logical_id: i64,
    logical_line_id: termmodel.Terminal_Logical_Line_Id,
    grapheme_offset: u32,
    head_truncated: bool,
    columns: int,
    wrapped: bool,
    shell_markers: termmodel.Shell_Row_Markers,
}

// Borrowed oldest-first view of one committed scrollback row.
//
// The cell slice aliases `Scrollback.cells` and remains valid only until that slot
// is overwritten or the owning scrollback is destroyed.
Scrollback_Row_View :: struct {
    logical_id: i64,
    logical_line_id: termmodel.Terminal_Logical_Line_Id,
    grapheme_offset: u32,
    head_truncated: bool,
    cells: []Cell,
    wrapped: bool,
    shell_markers: termmodel.Shell_Row_Markers,
}

// Optional terminal services borrowed by one initialized scrollback ring.
Scrollback_Init_Options :: struct {
    attachment_store: ^termattachment.Store,
    shell_integration: ^termshellintegration.Shell_Integration_State,
}

// Fixed-capacity ring of variable-width terminal rows.
//
// Storage is allocated once and commits copy complete rows without allocating.
// Logical indices are oldest-first even when physical slots wrap.
Scrollback :: struct {
    // Exclusively owned fixed storage and immutable maximum slot dimensions.
    allocator: mem.Allocator,
    cells: []Cell,
    rows: []Scrollback_Row,
    columns: int,
    capacity: int,

    // Borrowed placement registry for primary rows retained by this ring.
    attachment_store: ^termattachment.Store,
    shell_integration: ^termshellintegration.Shell_Integration_State,

    // Ring occupancy. `first` names the oldest physical slot when count is nonzero.
    count: int,
    first: int,

    // Lifetime totals; eviction counts commits that overwrite a full ring.
    committed_rows: u64,
    evicted_rows: u64,
}

// Reusable rendered-state snapshot of one compatible grid and scrollback pair.
//
// Initialization fixes all backing-slice shapes. Capture and restore allocate
// nothing and are intended for the same-sized display model throughout its lifetime.
// Parser state, pending UTF-8, grid telemetry, sink configuration, and dirty ranges
// are outside the snapshot contract.
Display_Checkpoint :: struct {
    // Exclusively owned snapshot storage allocated as one reusable shape.
    allocator: mem.Allocator,
    grid_cells: []Cell,
    grid_rows: []Snapshot_Row,
    scrollback_cells: []Cell,
    scrollback_rows: []Scrollback_Row,
    shell_command_blocks: []termmodel.Command_Block,
    placements: termattachment.Placement_Checkpoint,

    // Captured live-grid presentation state.
    grid_cursor: Cursor,
    grid_style: Cell_Style,
    grid_hyperlink: termmodel.Hyperlink_Handle,
    grid_scroll_top: int,
    grid_scroll_bottom: int,
    grid_origin_mode: bool,
    grid_autowrap_mode: bool,
    grid_insert_mode: bool,
    grid_protected_mode: bool,
    grid_tab_stops: [TAB_STOP_WORD_CAPACITY]u64,
    grid_next_logical_row_id: i64,

    // Captured scrollback topology and lifetime counters.
    scrollback_count: int,
    scrollback_first: int,
    scrollback_committed_rows: u64,
    scrollback_evicted_rows: u64,

    // Captured derived OSC 133 index topology and active candidate.
    shell_command_first: int,
    shell_command_count: int,
    shell_active_command: termmodel.Command_Block,
    shell_active_command_present: bool,

    // Set only after a complete successful capture.
    valid: bool,
}

//   Allocate one fixed-capacity row ring with a maximum cell width.
//
// Parameters:
//   - scrollback: Zero-valued destination ring.
//   - columns: Positive maximum cell count accepted for one committed row.
//   - capacity: Positive maximum number of retained rows.
//   - allocator: Allocator retained for matching destruction.
//
// Returns:
//   - True after both backing arrays are allocated; false for invalid state or
//     allocation failure.
//
// Side effects:
//   - Allocates `columns * capacity` cells and `capacity` metadata records.
scrollback_init :: proc(
    scrollback: ^Scrollback, columns, capacity: int,
    allocator: mem.Allocator,
    options := Scrollback_Init_Options{}) -> bool {

    if scrollback == nil || columns < 1 || capacity < 1 ||
        len(scrollback.cells) != 0 {
        return false
    }
    cells, cells_error := make([]Cell, columns*capacity, allocator)
    if cells_error != nil {
        return false
    }
    rows, rows_error := make([]Scrollback_Row, capacity, allocator)
    if rows_error != nil {
        delete(cells, allocator)
        return false
    }
    scrollback^ = {
        allocator = allocator,
        cells = cells,
        rows = rows,
        columns = columns,
        capacity = capacity,
        attachment_store = options.attachment_store,
        shell_integration = options.shell_integration,
    }
    return true
}

//   Release all storage exclusively owned by a scrollback ring.
//
// Parameters:
//   - scrollback: Ring to destroy; nil is a no-op.
//
// Side effects:
//   - Invalidates every borrowed row view and resets the ring to zero state.
scrollback_destroy :: proc(scrollback: ^Scrollback) {
    if scrollback == nil {
        return
    }
    delete(scrollback.rows, scrollback.allocator)
    delete(scrollback.cells, scrollback.allocator)
    scrollback^ = {}
}

// Evict the oldest full-ring row and return its reusable slot.
scrollback_evict_oldest :: proc(scrollback: ^Scrollback) -> int {
    slot := scrollback.first
    evicted_logical_row := scrollback.rows[slot].logical_id
    if scrollback.attachment_store != nil {
        termattachment.placements_remove_row(
            scrollback.attachment_store, .Primary, evicted_logical_row)
    }
    termshellintegration.shell_command_evict_through(
        scrollback.shell_integration, evicted_logical_row)
    scrollback.first = (scrollback.first + 1) % scrollback.capacity
    scrollback.evicted_rows += 1
    return slot
}

//   Copy one bounded-width row into the newest position in the ring.
//
// Parameters:
//   - scrollback: Initialized destination ring.
//   - cells: One through `scrollback.columns` cells; caller storage is not retained.
//   - wrapped: Whether this physical row continues logically onto the next row.
//
// Returns:
//   - True after commit; false for nil, uninitialized, or mismatched input.
//
// Side effects:
//   - Advances occupancy or overwrites the oldest slot when full, updates lifetime
//     counters, and may invalidate a previously borrowed view of that slot.
scrollback_commit :: proc(
    scrollback: ^Scrollback, cells: []Cell,
    metadata: Scrollback_Row_Commit) -> bool {
    if scrollback == nil || len(cells) < 1 || len(cells) > scrollback.columns ||
        scrollback.capacity == 0 {
        return false
    }
    slot := (scrollback.first + scrollback.count) % scrollback.capacity
    if scrollback.count == scrollback.capacity {
        slot = scrollback_evict_oldest(scrollback)
    } else {
        scrollback.count += 1
    }
    start := slot * scrollback.columns
    slot_cells := scrollback.cells[start:start + scrollback.columns]
    for &cell in slot_cells {
        cell = {}
    }
    copy(slot_cells, cells)
    scrollback.rows[slot].logical_id = metadata.logical_row_id
    scrollback.rows[slot].logical_line_id = metadata.logical_line_id if
        metadata.logical_line_id != 0 else
        termmodel.Terminal_Logical_Line_Id(metadata.logical_row_id)
    scrollback.rows[slot].grapheme_offset = metadata.grapheme_offset
    scrollback.rows[slot].head_truncated = metadata.head_truncated
    scrollback.rows[slot].columns = len(cells)
    scrollback.rows[slot].wrapped = metadata.wrapped
    scrollback.rows[slot].shell_markers = metadata.shell_markers
    scrollback.committed_rows += 1
    return true
}

//   Return one oldest-first borrowed row view.
//
// Parameters:
//   - scrollback: Initialized source ring.
//   - index: Logical index in `[0, scrollback.count)`, where zero is oldest.
//
// Returns:
//   - The exact-width aliased row and true, or an empty view and false.
//
// Notes:
//   - Although callers should treat the slice as immutable, Odin's slice type does
//     not enforce that constraint. The view must not outlive its owning slot.
scrollback_row :: proc(
    scrollback: ^Scrollback, index: int) -> (Scrollback_Row_View, bool) {

    if scrollback == nil || index < 0 || index >= scrollback.count {
        return {}, false
    }
    slot := (scrollback.first + index) % scrollback.capacity
    start := slot * scrollback.columns
    columns := scrollback.rows[slot].columns
    return {
        logical_id = scrollback.rows[slot].logical_id,
        logical_line_id = scrollback.rows[slot].logical_line_id,
        grapheme_offset = scrollback.rows[slot].grapheme_offset,
        head_truncated = scrollback.rows[slot].head_truncated,
        cells = scrollback.cells[start:start + columns],
        wrapped = scrollback.rows[slot].wrapped,
        shell_markers = scrollback.rows[slot].shell_markers,
    }, true
}

//   Adapt the grid scrollback callback to `scrollback_commit`.
//
// Parameters:
//   - user_data: Non-nil `^Scrollback` supplied when the grid sink was configured.
//   - cells: Synchronously borrowed exact-width evicted grid row.
//   - wrapped: Whether the evicted row logically continues onto its successor.
//
// Side effects:
//   - Copies the row into the target ring; commit failure is intentionally ignored.
scrollback_sink_commit :: proc(
    user_data: rawptr, cells: []Cell, metadata: Scrollback_Row_Commit) {
    scrollback := cast(^Scrollback)user_data
    scrollback_commit(scrollback, cells, metadata)
}

//   Allocate reusable storage for rendered grid and scrollback rollback.
//
// Parameters:
//   - checkpoint: Zero-valued destination checkpoint.
//   - grid: Initialized grid defining cell and row storage shape.
//   - scrollback: Initialized ring defining cell and metadata storage shape.
//   - allocator: Allocator retained for matching destruction.
//
// Returns:
//   - True after all backing arrays are allocated; false for invalid state or
//     allocation failure.
//
// Side effects:
//   - Allocates reusable mirrors for grid cells/wrap flags and the complete ring.
display_checkpoint_init :: proc(
    checkpoint: ^Display_Checkpoint, grid: ^Grid, scrollback: ^Scrollback,
    allocator: mem.Allocator) -> bool {

    if checkpoint == nil || grid == nil || scrollback == nil ||
        len(checkpoint.grid_cells) != 0 {
        return false
    }
    candidate := Display_Checkpoint{allocator = allocator}
    candidate.grid_cells, _ = make([]Cell, len(grid.cells), allocator)
    candidate.grid_rows, _ = make([]Snapshot_Row, len(grid.rows), allocator)
    candidate.scrollback_cells, _ = make([]Cell, len(scrollback.cells), allocator)
    candidate.scrollback_rows, _ = make([]Scrollback_Row, len(scrollback.rows), allocator)
    if scrollback.shell_integration != nil {
        candidate.shell_command_blocks, _ = make(
            []termmodel.Command_Block,
            len(scrollback.shell_integration.command_blocks), allocator)
    }
    if candidate.grid_cells == nil || candidate.grid_rows == nil ||
        candidate.scrollback_cells == nil || candidate.scrollback_rows == nil ||
        (scrollback.shell_integration != nil &&
         candidate.shell_command_blocks == nil) {
        display_checkpoint_destroy(&candidate)
        return false
    }
    if scrollback.attachment_store != nil &&
        !termattachment.placement_checkpoint_init(
            &candidate.placements, scrollback.attachment_store, allocator) {
        display_checkpoint_destroy(&candidate)
        return false
    }
    checkpoint^ = candidate
    return true
}

// Capture grid presentation fields outside its mirrored cell and row storage.
display_checkpoint_capture_grid_state :: proc(
    checkpoint: ^Display_Checkpoint, grid: ^Grid) {
    checkpoint.grid_cursor = grid.cursor
    checkpoint.grid_style = grid.style
    checkpoint.grid_hyperlink = grid.hyperlink
    checkpoint.grid_scroll_top = grid.editing.scroll_top
    checkpoint.grid_scroll_bottom = grid.editing.scroll_bottom
    checkpoint.grid_origin_mode = grid.editing.origin_mode
    checkpoint.grid_autowrap_mode = grid.editing.autowrap_mode
    checkpoint.grid_insert_mode = grid.editing.insert_mode
    checkpoint.grid_protected_mode = grid.editing.protected_mode
    checkpoint.grid_tab_stops = grid.editing.tab_stops
    checkpoint.grid_next_logical_row_id = grid.editing.next_logical_row_id
}

//   Release reusable display-checkpoint storage.
//
// Parameters:
//   - checkpoint: Checkpoint to destroy; nil is a no-op.
//
// Side effects:
//   - Releases all owned mirrors, invalidates the captured state, and resets to zero.
display_checkpoint_destroy :: proc(checkpoint: ^Display_Checkpoint) {
    if checkpoint == nil {
        return
    }
    termattachment.placement_checkpoint_destroy(&checkpoint.placements)
    delete(checkpoint.shell_command_blocks, checkpoint.allocator)
    delete(checkpoint.scrollback_rows, checkpoint.allocator)
    delete(checkpoint.scrollback_cells, checkpoint.allocator)
    delete(checkpoint.grid_rows, checkpoint.allocator)
    delete(checkpoint.grid_cells, checkpoint.allocator)
    checkpoint^ = {}
}

// Copy captured command-index topology between compatible checkpoints.
display_checkpoint_copy_shell :: proc(
    destination, source: ^Display_Checkpoint) {
    copy(destination.shell_command_blocks, source.shell_command_blocks)
    destination.shell_command_first = source.shell_command_first
    destination.shell_command_count = source.shell_command_count
    destination.shell_active_command = source.shell_active_command
    destination.shell_active_command_present = source.shell_active_command_present
}

// Capture one command index into an already compatible checkpoint mirror.
display_checkpoint_capture_shell :: proc(
    checkpoint: ^Display_Checkpoint,
    shell: ^termshellintegration.Shell_Integration_State) {
    if shell == nil { return }
    copy(checkpoint.shell_command_blocks, shell.command_blocks)
    checkpoint.shell_command_first = shell.command_first
    checkpoint.shell_command_count = shell.command_count
    checkpoint.shell_active_command = shell.active_command
    checkpoint.shell_active_command_present = shell.active_command_present
}

// Restore one command index from its reusable checkpoint mirror.
display_checkpoint_restore_shell :: proc(
    checkpoint: ^Display_Checkpoint,
    shell: ^termshellintegration.Shell_Integration_State) {
    if shell == nil { return }
    copy(shell.command_blocks, checkpoint.shell_command_blocks)
    shell.command_first = checkpoint.shell_command_first
    shell.command_count = checkpoint.shell_command_count
    shell.active_command = checkpoint.shell_active_command
    shell.active_command_present = checkpoint.shell_active_command_present
}

// Copy grid row metadata into an initialized display checkpoint.
display_checkpoint_capture_rows :: proc(
    checkpoint: ^Display_Checkpoint, rows: []Row) {
    for row, index in rows {
        checkpoint.grid_rows[index] = {
            logical_id = row.logical_id,
            logical_line_id = row.logical_line_id,
            grapheme_offset = row.grapheme_offset,
            head_truncated = row.head_truncated,
            wrapped = row.wrapped,
            shell_markers = row.shell_markers,
        }
    }
}

//   Capture rendered grid and complete scrollback-ring state without allocating.
//
// Parameters:
//   - checkpoint: Initialized reusable storage compatible with both sources.
//   - grid: Grid whose cells, wrap flags, cursor, and active style are captured.
//   - scrollback: Ring whose storage, topology, and counters are captured.
//
// Returns:
//   - True after a complete capture; false for nil or incompatible cell storage.
//
// Side effects:
//   - Replaces any prior snapshot and marks the checkpoint valid.
display_checkpoint_capture :: proc(
    checkpoint: ^Display_Checkpoint, grid: ^Grid, scrollback: ^Scrollback) -> bool {

    if checkpoint == nil || grid == nil || scrollback == nil ||
        len(checkpoint.grid_cells) != len(grid.cells) ||
        len(checkpoint.scrollback_cells) != len(scrollback.cells) ||
        (scrollback.shell_integration != nil &&
         len(checkpoint.shell_command_blocks) !=
            len(scrollback.shell_integration.command_blocks)) {
        return false
    }
    if scrollback.attachment_store != nil &&
        !termattachment.placement_checkpoint_capture(
            &checkpoint.placements, scrollback.attachment_store) {
        checkpoint.valid = false
        return false
    }
    copy(checkpoint.grid_cells, grid.cells)
    display_checkpoint_capture_rows(checkpoint, grid.rows)
    copy(checkpoint.scrollback_cells, scrollback.cells)
    copy(checkpoint.scrollback_rows, scrollback.rows)
    display_checkpoint_capture_shell(
        checkpoint, scrollback.shell_integration)
    display_checkpoint_capture_grid_state(checkpoint, grid)
    checkpoint.scrollback_count = scrollback.count
    checkpoint.scrollback_first = scrollback.first
    checkpoint.scrollback_committed_rows = scrollback.committed_rows
    checkpoint.scrollback_evicted_rows = scrollback.evicted_rows
    checkpoint.valid = true
    return true
}

// Restore captured grid presentation fields outside mirrored cell and row storage.
display_checkpoint_restore_grid_state :: proc(
    checkpoint: ^Display_Checkpoint, grid: ^Grid) {
    grid.cursor = checkpoint.grid_cursor
    grid.style = checkpoint.grid_style
    grid.hyperlink = checkpoint.grid_hyperlink
    grid.editing.scroll_top = checkpoint.grid_scroll_top
    grid.editing.scroll_bottom = checkpoint.grid_scroll_bottom
    grid.editing.origin_mode = checkpoint.grid_origin_mode
    grid.editing.autowrap_mode = checkpoint.grid_autowrap_mode
    grid.editing.insert_mode = checkpoint.grid_insert_mode
    grid.editing.protected_mode = checkpoint.grid_protected_mode
    grid.editing.tab_stops = checkpoint.grid_tab_stops
    grid.editing.next_logical_row_id = checkpoint.grid_next_logical_row_id
}

//   Restore the most recently captured rendered state without allocating.
//
// Notes:
//   - The destination pair must retain the shapes used to initialize the checkpoint.
//   - Restoration is repeatable; a successful restore does not consume the snapshot.
//
// Parameters:
//   - checkpoint: Valid checkpoint containing a prior complete capture.
//   - grid: Compatible destination grid.
//   - scrollback: Compatible destination ring.
//
// Returns:
//   - True after restoration; false for nil arguments or no valid capture.
//
// Side effects:
//   - Replaces captured cells, wraps, cursor/style, ring topology, and ring counters;
//     marks every grid row fully dirty so renderers redraw restored content.
display_checkpoint_restore :: proc(
    checkpoint: ^Display_Checkpoint, grid: ^Grid, scrollback: ^Scrollback) -> bool {

    if checkpoint == nil || !checkpoint.valid || grid == nil || scrollback == nil {
        return false
    }
    if scrollback.attachment_store != nil &&
        !termattachment.placement_checkpoint_restore(
            &checkpoint.placements, scrollback.attachment_store) {
        return false
    }
    copy(grid.cells, checkpoint.grid_cells)
    for &row, index in grid.rows {
        row.logical_id = checkpoint.grid_rows[index].logical_id
        row.logical_line_id = checkpoint.grid_rows[index].logical_line_id
        row.grapheme_offset = checkpoint.grid_rows[index].grapheme_offset
        row.head_truncated = checkpoint.grid_rows[index].head_truncated
        row.wrapped = checkpoint.grid_rows[index].wrapped
        row.shell_markers = checkpoint.grid_rows[index].shell_markers
        row.dirty = true
        row.dirty_start = 0
        row.dirty_end = grid.columns
    }
    copy(scrollback.cells, checkpoint.scrollback_cells)
    copy(scrollback.rows, checkpoint.scrollback_rows)
    display_checkpoint_restore_shell(
        checkpoint, scrollback.shell_integration)
    display_checkpoint_restore_grid_state(checkpoint, grid)
    scrollback.count = checkpoint.scrollback_count
    scrollback.first = checkpoint.scrollback_first
    scrollback.committed_rows = checkpoint.scrollback_committed_rows
    scrollback.evicted_rows = checkpoint.scrollback_evicted_rows
    return true
}

// Borrow one oldest-first scrollback row from a valid presentation checkpoint.
display_checkpoint_scrollback_row :: proc(
    checkpoint: ^Display_Checkpoint, index: int) -> (Scrollback_Row_View, bool) {
    if checkpoint == nil || !checkpoint.valid || index < 0 ||
        index >= checkpoint.scrollback_count || len(checkpoint.scrollback_rows) == 0 {
        return {}, false
    }
    slot := (checkpoint.scrollback_first + index) % len(checkpoint.scrollback_rows)
    row := checkpoint.scrollback_rows[slot]
    storage_columns := len(checkpoint.scrollback_cells) /
        len(checkpoint.scrollback_rows)
    start := slot * storage_columns
    return {
        logical_id = row.logical_id,
        logical_line_id = row.logical_line_id,
        grapheme_offset = row.grapheme_offset,
        head_truncated = row.head_truncated,
        cells = checkpoint.scrollback_cells[start:start + row.columns],
        wrapped = row.wrapped,
        shell_markers = row.shell_markers,
    }, true
}

// Borrow one grid row from a valid presentation checkpoint.
display_checkpoint_grid_row :: proc(
    checkpoint: ^Display_Checkpoint, row: int) -> ([]Cell, bool) {
    if checkpoint == nil || !checkpoint.valid || row < 0 ||
        row >= len(checkpoint.grid_rows) || len(checkpoint.grid_rows) == 0 {
        return nil, false
    }
    columns := len(checkpoint.grid_cells) / len(checkpoint.grid_rows)
    start := row * columns
    return checkpoint.grid_cells[start:start + columns], true
}

// Borrow shell metadata for one grid row in a valid presentation checkpoint.
display_checkpoint_grid_shell_markers :: proc(
    checkpoint: ^Display_Checkpoint,
    row: int) -> (termmodel.Shell_Row_Markers, bool) {
    if checkpoint == nil || !checkpoint.valid || row < 0 ||
        row >= len(checkpoint.grid_rows) {
        return {}, false
    }
    return checkpoint.grid_rows[row].shell_markers, true
}

// Return whether a valid checkpoint contains any materialized grid cell.
display_checkpoint_contains_output :: proc(
    checkpoint: ^Display_Checkpoint) -> bool {
    if checkpoint == nil || !checkpoint.valid {
        return false
    }
    for &cell in checkpoint.grid_cells {
        if cell.grapheme_len > 0 || cell.continuation {
            return true
        }
    }
    return false
}
