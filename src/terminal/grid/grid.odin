package termgrid

import "core:mem"
import "core:unicode"
import "core:unicode/utf8"
import termattachment "../attachment"
import termmodel "../model"

// Cells retain one bounded grapheme cluster inline. Tabs advance to fixed
// eight-column stops under the basic control-byte policy.
CELL_GRAPHEME_CAPACITY :: 32
DEFAULT_TAB_WIDTH :: 8
TAB_STOP_CAPACITY :: 256
TAB_STOP_WORD_CAPACITY :: TAB_STOP_CAPACITY / 64

// Startup-selected policy for Unicode East Asian Ambiguous code points.
Ambiguous_Width_Mode :: enum u8 {
    Narrow,
    Wide,
}

// Complete rendition copied into a cell when its leading grapheme is written.
Cell_Style :: struct {
    foreground: termmodel.Terminal_Color_Reference,
    background: termmodel.Terminal_Color_Reference,
    font_weight: termmodel.Font_Weight,
    bold: bool,
    italic: bool,
    underline: bool,
}

// One fixed terminal column or the continuation half of a wide grapheme.
//
// Leading cells own valid UTF-8 bytes and have width one or two. A width-two
// leader is followed by a zero-width continuation cell. Cluster extensions are
// appended atomically; overflow preserves valid UTF-8 and marks truncation.
Cell :: struct {
    // Inline grapheme payload. The length delimits valid UTF-8; truncation means
    // one or more complete extensions were dropped after capacity was exhausted.
    grapheme: [CELL_GRAPHEME_CAPACITY]u8,
    grapheme_len: u8,

    // Column occupancy. Leaders use width one or two; continuations use width
    // zero, carry no grapheme/style of their own, and belong to the prior leader.
    width: u8,
    continuation: bool,

    // Cluster assembly. A trailing ZWJ arms the leader to absorb the next base
    // rune; the other flags retain bounded emoji-sequence classification.
    join_next: bool,
    regional_indicator: bool,
    emoji_candidate: bool,
    grapheme_truncated: bool,

    // Rendition captured when the leading cell was written.
    style: Cell_Style,

    // Optional terminal-owned URI identity; continuations resolve through the leader.
    hyperlink: termmodel.Hyperlink_Handle,

    // Selective erase preserves protected leading cells and their continuations.
    protected: bool,
}

// Stable view over one contiguous segment of `Grid.cells`.
// Dirty bounds are a half-open union of changed columns. `wrapped` means the row
// continued because delayed autowrap, rather than an explicit line feed, fired.
Row :: struct {
    // Borrowed stable view into the owning grid's contiguous cell allocation.
    cells: []Cell,

    // Screen-local identity copied with row content across scrolling and resize.
    logical_id: i64,

    // Geometry-independent line identity and leading-grapheme offset.
    logical_line_id: termmodel.Terminal_Logical_Line_Id,
    grapheme_offset: u32,
    head_truncated: bool,

    // Renderer damage accumulated since the last explicit dirty clear.
    dirty: bool,
    dirty_start: int,
    dirty_end: int,

    // Logical line provenance retained for scrollback and text composition.
    wrapped: bool,

    // Shell lifecycle positions emitted while this physical row was active.
    shell_markers: termmodel.Shell_Row_Markers,
}

// Logical write position within the fixed visible grid.
// `wrap_pending` delays autowrap after filling the final column until another
// printable grapheme arrives, matching terminal cursor behavior.
Cursor :: struct {
    // Clamped visible position. On delayed wrap, column remains the final column.
    row: int,
    column: int,

    // Whether the next printable base first advances to a wrapped row.
    wrap_pending: bool,
}

// Complete provenance and shell metadata for one scrollback row commit.
Scrollback_Row_Commit :: struct {
    logical_row_id: i64,
    wrapped: bool,
    shell_markers: termmodel.Shell_Row_Markers,
    logical_line_id: termmodel.Terminal_Logical_Line_Id,
    grapheme_offset: u32,
    head_truncated: bool,
}

// Optional synchronous consumer for rows evicted from the top of the grid.
// The callback borrows `cells` only for its invocation and must copy retained data
// before returning; it runs before the visible row is shifted or overwritten.
Scrollback_Sink :: struct {
    user_data: rawptr,
    commit: proc(
        user_data: rawptr, cells: []Cell, metadata: Scrollback_Row_Commit),
}

// Fixed-size visible terminal model with incremental Unicode decoding.
//
// `cells` owns one contiguous allocation and every row slice aliases its segment.
// The grid owns both allocations, active style, cursor, decoder prefix, and
// cumulative malformed/truncated-input telemetry. Scrollback storage is external.
Grid :: struct {
    // Owned storage topology. `cells` is the sole cell allocation; each `rows`
    // entry borrows one stable, non-overlapping segment. Dimensions describe both
    // arrays and remain fixed from successful initialization until destruction.
    allocator: mem.Allocator,
    cells: []Cell,
    rows: []Row,
    columns: int,
    row_count: int,

    // Live terminal state. Cursor and style govern subsequent writes, while the
    // optional sink synchronously receives top rows before scrolling overwrites them.
    cursor: Cursor,
    style: Cell_Style,
    hyperlink: termmodel.Hyperlink_Handle,
    scrollback: Scrollback_Sink,

    // Heap-owned screen-local margins, modes, tabs, and DEC saved state.
    editing_storage: []Grid_Editing_State,
    editing: ^Grid_Editing_State,

    // Incremental stream state. A valid but incomplete UTF-8 prefix survives
    // arbitrary `grid_write` chunk boundaries until completed or explicitly finished.
    pending_utf8: [utf8.UTF_MAX]u8,
    pending_utf8_len: int,

    // Lifetime diagnostics. Counts accumulate malformed sequences and grapheme
    // extensions dropped atomically because their leading cell was already full.
    invalid_utf8_count: u64,
    truncated_grapheme_count: u64,
}

// Screen-local editing and attachment context owned indirectly by one grid.
Grid_Editing_State :: struct {
    // Borrowed placement registry, screen identity, and monotonic row sequence.
    attachment_store: ^termattachment.Store,
    screen: termattachment.Screen_Identity,
    next_logical_row_id: i64,

    // DEC editing modes, margins, tabs, and saved cursor state.
    ambiguous_width: Ambiguous_Width_Mode,
    scroll_top: int,
    scroll_bottom: int,
    origin_mode: bool,
    autowrap_mode: bool,
    insert_mode: bool,
    protected_mode: bool,
    sixel_scrolling_mode: bool,
    sixel_cursor_right_mode: bool,
    tab_stops: [TAB_STOP_WORD_CAPACITY]u64,
    dec_saved: Dec_Saved_State,
}

// Optional sink and Unicode policy applied during grid initialization.
Grid_Init_Options :: struct {
    scrollback: Scrollback_Sink,
    ambiguous_width: Ambiguous_Width_Mode,
    attachment_store: ^termattachment.Store,
    screen: termattachment.Screen_Identity,
}

// Outcome of preparing one replacement visible grid.
Grid_Resize_Result :: enum {
    Prepared,
    Unchanged,
    Invalid_Dimensions,
    Allocation_Failed,
}

// Fully allocated replacement grid held outside live state until commit.
Prepared_Grid_Resize :: struct {
    grid: Grid,
    ready: bool,
}

// Renderer metadata copied for one snapshotted row.
Snapshot_Row :: struct {
    // Stable screen-local identity captured with the row's content.
    logical_id: i64,

    // Stable semantic provenance independent of physical row identity.
    logical_line_id: termmodel.Terminal_Logical_Line_Id,
    grapheme_offset: u32,
    head_truncated: bool,

    // Damage state captured from the corresponding live row.
    dirty: bool,
    dirty_start: int,
    dirty_end: int,

    // Whether this row logically continues into the next snapshotted row.
    wrapped: bool,

    // Shell lifecycle positions copied with their physical row.
    shell_markers: termmodel.Shell_Row_Markers,
}

// Allocator-owned copy of deterministic visible render state.
// It captures cells, row metadata, dimensions, and cursor, but not active style,
// scrollback wiring, decoder prefixes, or cumulative telemetry.
Snapshot :: struct {
    // Independently owned render storage copied from one grid state.
    allocator: mem.Allocator,
    cells: []Cell,
    rows: []Snapshot_Row,

    // Fixed geometry and logical cursor paired with the copied arrays.
    columns: int,
    row_count: int,
    cursor: Cursor,
}

// Report whether one bounded column has an explicit horizontal tab stop.
grid_has_tab_stop :: proc(grid: ^Grid, column: int) -> bool {
    if grid == nil || column < 0 || column >= TAB_STOP_CAPACITY {
        return false
    }
    word := column / 64
    mask := u64(1) << u64(column % 64)
    return grid.editing.tab_stops[word] & mask != 0
}

// Set or clear one bounded explicit horizontal tab stop.
grid_set_tab_stop :: proc(grid: ^Grid, column: int, enabled: bool) {
    if grid == nil || column < 0 || column >= TAB_STOP_CAPACITY {
        return
    }
    word := column / 64
    mask := u64(1) << u64(column % 64)
    if enabled {
        grid.editing.tab_stops[word] |= mask
    } else {
        grid.editing.tab_stops[word] &= ~mask
    }
}

// Issue one nonzero screen-local identity for newly materialized row content.
grid_next_logical_row_id :: proc(grid: ^Grid) -> i64 {
    grid.editing.next_logical_row_id += 1
    if grid.editing.next_logical_row_id <= 0 {
        grid.editing.next_logical_row_id = 1
    }
    return grid.editing.next_logical_row_id
}

// Assign fresh physical and hard-line semantic identity to one cleared row.
grid_reset_row_identity :: proc(grid: ^Grid, row_index: int) {
    row := &grid.rows[row_index]
    row.logical_id = grid_next_logical_row_id(grid)
    row.logical_line_id = termmodel.Terminal_Logical_Line_Id(row.logical_id)
    row.grapheme_offset = 0
    row.head_truncated = false
}

// Count occupied leading graphemes in one row without decoding retained bytes.
grid_row_grapheme_count :: proc(row: ^Row) -> u32 {
    result: u32
    for &cell in row.cells {
        if !cell.continuation && cell.grapheme_len > 0 { result += 1 }
    }
    return result
}

// Count leading graphemes before one clamped physical column boundary.
grid_row_grapheme_offset :: proc(row: ^Row, column: int) -> u32 {
    result := row.grapheme_offset
    limit := clamp(column, 0, len(row.cells))
    for cell_index in 0..<limit {
        cell := &row.cells[cell_index]
        if !cell.continuation && cell.grapheme_len > 0 { result += 1 }
    }
    return result
}

//   Remove every attachment placement belonging to one grid's screen.
//
// Parameters:
//   - grid: Screen whose placement namespace is being discarded; nil is accepted.
//
// Returns:
//   - Number of placements removed, or zero without an attachment registry.
//
// Side effects:
//   - Releases attachment placement references through the borrowed store.
grid_remove_placements :: proc(grid: ^Grid) -> int {
    if grid == nil || grid.editing.attachment_store == nil {
        return 0
    }
    return termattachment.placements_remove_screen(
        grid.editing.attachment_store, grid.editing.screen)
}

// Bind each row descriptor, assign row identities, and establish default tab stops.
grid_init_rows_and_tabs :: proc(grid: ^Grid) {
    for row_index in 0..<grid.row_count {
        start := row_index * grid.columns
        grid.rows[row_index].cells = grid.cells[start:start + grid.columns]
        grid_reset_row_identity(grid, row_index)
    }
    for column := DEFAULT_TAB_WIDTH;
        column < min(grid.columns, TAB_STOP_CAPACITY);
        column += DEFAULT_TAB_WIDTH {
        grid_set_tab_stop(grid, column, true)
    }
}

// Publish allocated grid storage and establish baseline editing state.
grid_init_state :: proc(
    grid: ^Grid, cells: []Cell, rows: []Row,
    editing: ^Grid_Editing_State, options: Grid_Init_Options) {
    grid.cells = cells
    grid.rows = rows
    grid.editing = editing
    grid.scrollback = options.scrollback
    grid.editing.attachment_store = options.attachment_store
    grid.editing.screen = options.screen
    grid.editing.ambiguous_width = options.ambiguous_width
    grid.editing.scroll_bottom = grid.row_count - 1
    grid.editing.autowrap_mode = true
    grid_init_rows_and_tabs(grid)
}

//   Allocate one fixed grid and establish stable row views over contiguous cells.
//
// Parameters:
//   - grid: Zero-valued destination storage not already owning cells.
//   - columns: Positive visible column count.
//   - rows: Positive visible row count.
//   - allocator: Allocator that owns cells and row descriptors until destruction.
//   - options: Optional scrollback sink and ambiguous-width policy.
//
// Returns:
//   - True after complete initialization; false without partial ownership on error.
//
// Side effects:
//   - Allocates cell/row storage and binds each row slice into the cell allocation.
grid_init :: proc(
    grid: ^Grid, columns, rows: int, allocator: mem.Allocator,
    options := Grid_Init_Options{}) -> bool {

    if grid == nil || columns < 1 || rows < 1 || len(grid.cells) != 0 {
        return false
    }
    cells, cells_error := make([]Cell, columns*rows, allocator)
    if cells_error != nil {
        return false
    }
    row_storage, rows_error := make([]Row, rows, allocator)
    if rows_error != nil {
        delete(cells, allocator)
        return false
    }
    editing_storage, editing_error := make(
        []Grid_Editing_State, 1, allocator)
    if editing_error != nil {
        delete(row_storage, allocator)
        delete(cells, allocator)
        return false
    }
    editing := &editing_storage[0]

    grid.allocator = allocator
    grid.columns = columns
    grid.row_count = rows
    grid.editing_storage = editing_storage
    grid_init_state(grid, cells, row_storage, editing, options)
    return true
}

//   Release all storage exclusively owned by a grid.
//
// Parameters:
//   - grid: The initialized grid to destroy; nil is a no-op.
//
// Side effects:
//   - Frees row and cell allocations and resets the complete grid to zero.
grid_destroy :: proc(grid: ^Grid) {
    if grid == nil {
        return
    }
    delete(grid.rows, grid.allocator)
    delete(grid.cells, grid.allocator)
    delete(grid.editing_storage, grid.allocator)
    grid^ = {}
}

//   Clear cells that no longer form one complete wide-cell pair.
grid_repair_wide_row :: proc(cells: []Cell) {
    for &cell, column in cells {
        if cell.continuation {
            if column == 0 || cells[column - 1].width != 2 {
                cell = {}
            }
        } else if cell.width == 2 &&
            (column + 1 >= len(cells) || !cells[column + 1].continuation) {
            cell = {}
        }
    }
}

//   Repair copied wide-cell invariants in every visible row.
grid_repair_wide_rows :: proc(grid: ^Grid) {
    for &row in grid.rows {
        grid_repair_wide_row(row.cells)
    }
}

//   Map one cursor through coordinate-preserving growth or bottom-anchored shrink.
grid_resize_cursor :: proc(
    cursor: Cursor, old_columns, old_rows, new_columns, new_rows: int) -> Cursor {
    removed_top_rows := max(old_rows - new_rows, 0)
    return {
        row = clamp(cursor.row - removed_top_rows, 0, new_rows - 1),
        column = clamp(cursor.column, 0, new_columns - 1),
        wrap_pending = cursor.wrap_pending && old_columns == new_columns,
    }
}

// Copy and resize screen-local editing modes, margins, tabs, and saved cursor.
grid_copy_resize_editing_state :: proc(source, destination: ^Grid) {
    destination.editing^ = source.editing^
    source_full_region := source.editing.scroll_top == 0 &&
        source.editing.scroll_bottom == source.row_count - 1
    destination.editing.scroll_top = clamp(
        source.editing.scroll_top, 0, destination.row_count - 1)
    destination.editing.scroll_bottom = destination.row_count - 1 if
        source_full_region else clamp(
            source.editing.scroll_bottom, destination.editing.scroll_top,
            destination.row_count - 1)
    destination.editing.dec_saved.cursor = grid_resize_cursor(
        source.editing.dec_saved.cursor, source.columns, source.row_count,
        destination.columns, destination.row_count)
    for column in source.columns..<min(destination.columns, TAB_STOP_CAPACITY) {
        if column % DEFAULT_TAB_WIDTH == 0 {
            grid_set_tab_stop(destination, column, true)
        }
    }
}

// Copy the bottom-anchored visible row intersection into a replacement grid.
grid_copy_resize_rows :: proc(source, destination: ^Grid) {
    copy_rows := min(destination.row_count, source.row_count)
    source_row := source.row_count - copy_rows
    copy_columns := min(destination.columns, source.columns)
    for offset in 0..<copy_rows {
        old_row := &source.rows[source_row + offset]
        new_row := &destination.rows[offset]
        copy(new_row.cells[:copy_columns], old_row.cells[:copy_columns])
        new_row.logical_id = old_row.logical_id
        new_row.logical_line_id = old_row.logical_line_id
        new_row.grapheme_offset = old_row.grapheme_offset
        new_row.head_truncated = old_row.head_truncated
        new_row.wrapped = old_row.wrapped
        new_row.shell_markers = old_row.shell_markers
    }
    destination.editing.next_logical_row_id = source.editing.next_logical_row_id
    for row_index in copy_rows..<destination.row_count {
        destination.rows[row_index].logical_id =
            grid_next_logical_row_id(destination)
    }
}

//   Copy non-storage state and the left/bottom visible intersection.
grid_copy_resize_state :: proc(source, destination: ^Grid) {
    destination.style = source.style
    destination.hyperlink = source.hyperlink
    destination.pending_utf8 = source.pending_utf8
    destination.pending_utf8_len = source.pending_utf8_len
    destination.invalid_utf8_count = source.invalid_utf8_count
    destination.truncated_grapheme_count = source.truncated_grapheme_count
    grid_copy_resize_editing_state(source, destination)
    grid_copy_resize_rows(source, destination)
    grid_repair_wide_rows(destination)
    destination.cursor = grid_resize_cursor(
        source.cursor, source.columns, source.row_count,
        destination.columns, destination.row_count)
}

//   Prepare a bottom-anchored replacement grid without mutating live state.
grid_prepare_resize :: proc(
    grid: ^Grid, columns, rows: int,
    allocator: mem.Allocator) -> (Prepared_Grid_Resize, Grid_Resize_Result) {
    if grid == nil || columns < 1 || rows < 1 {
        return {}, .Invalid_Dimensions
    }
    if columns == grid.columns && rows == grid.row_count {
        return {}, .Unchanged
    }
    candidate: Grid
    if !grid_init(
        &candidate, columns, rows, allocator, {
            scrollback = grid.scrollback,
            ambiguous_width = grid.editing.ambiguous_width,
            attachment_store = grid.editing.attachment_store,
            screen = grid.editing.screen,
        }) {
        return {}, .Allocation_Failed
    }
    grid_copy_resize_state(grid, &candidate)
    for &row in candidate.rows {
        row.dirty = true
        row.dirty_start = 0
        row.dirty_end = columns
    }
    return {grid = candidate, ready = true}, .Prepared
}

//   Atomically replace one live grid with a prepared candidate.
grid_commit_resize :: proc(grid: ^Grid, prepared: ^Prepared_Grid_Resize) -> bool {
    if grid == nil || prepared == nil || !prepared.ready {
        return false
    }
    removed_rows := max(grid.row_count - prepared.grid.row_count, 0)
    if grid.editing.attachment_store != nil {
        for row_index in 0..<removed_rows {
            termattachment.placements_remove_row(
                grid.editing.attachment_store, grid.editing.screen,
                grid.rows[row_index].logical_id)
        }
    }
    previous := grid^
    grid^ = prepared.grid
    prepared^ = {}
    grid_destroy(&previous)
    return true
}

//   Release an uncommitted prepared replacement.
grid_discard_prepared_resize :: proc(prepared: ^Prepared_Grid_Resize) {
    if prepared == nil || !prepared.ready {
        return
    }
    grid_destroy(&prepared.grid)
    prepared^ = {}
}

//   Select the rendition copied into subsequently written leading cells.
//
// Parameters:
//   - grid: The initialized grid.
//   - style: The new active rendition; existing cells remain unchanged.
//
// Side effects:
//   - Replaces only the grid's active style.
grid_set_style :: proc(grid: ^Grid, style: Cell_Style) {
    assert(grid != nil)
    grid.style = style
}

//   Clear all row dirty metadata after a consumer observes changes.
//
// Parameters:
//   - grid: The initialized grid whose dirty ranges were consumed.
//
// Side effects:
//   - Resets every dirty flag and half-open dirty range without changing cells.
grid_clear_dirty :: proc(grid: ^Grid) {
    assert(grid != nil)
    for &row in grid.rows {
        row.dirty = false
        row.dirty_start = 0
        row.dirty_end = 0
    }
}

//   Ingest arbitrarily chunked UTF-8 and supported basic control bytes.
//
// Notes:
//   - Incomplete UTF-8 prefixes remain buffered across calls.
//   - Printable input updates cells through width, cluster, wrap, and scroll policy.
//
// Parameters:
//   - grid: The initialized visible grid.
//   - input: Bytes to consume; caller storage is not retained.
//
// Returns:
//   - False only for nil/uninitialized grid storage; otherwise true.
//
// Side effects:
//   - Mutates decoder, cells, cursor, dirty ranges, telemetry, and possibly scrollback.
grid_write :: proc(grid: ^Grid, input: string) -> bool {
    if grid == nil || len(grid.cells) == 0 {
        return false
    }
    for byte in transmute([]u8)input {
        grid_ingest_byte(grid, byte)
    }
    return true
}

//   Finalize any incomplete UTF-8 prefix as one replacement grapheme.
//
// Parameters:
//   - grid: The grid whose current input stream has reached a semantic boundary.
//
// Side effects:
//   - Clears pending bytes, increments invalid-input telemetry, and writes `U+FFFD`.
grid_finish_input :: proc(grid: ^Grid) {
    if grid == nil || grid.pending_utf8_len == 0 {
        return
    }
    grid.pending_utf8_len = 0
    grid.invalid_utf8_count += 1
    grid_write_replacement(grid)
}

// Copy row metadata into independently owned snapshot storage.
snapshot_copy_rows :: proc(rows: []Snapshot_Row, grid_rows: []Row) {
    for row, row_index in grid_rows {
        rows[row_index] = {
            logical_id = row.logical_id,
            logical_line_id = row.logical_line_id,
            grapheme_offset = row.grapheme_offset,
            head_truncated = row.head_truncated,
            dirty = row.dirty,
            dirty_start = row.dirty_start,
            dirty_end = row.dirty_end,
            wrapped = row.wrapped,
            shell_markers = row.shell_markers,
        }
    }
}

//   Copy deterministic visible grid state into an owned snapshot.
//
// Parameters:
//   - grid: The initialized source grid borrowed for the copy.
//   - snapshot: Zero-valued destination not already owning cells.
//   - allocator: Allocator that owns snapshot storage until destruction.
//
// Returns:
//   - True after a complete copy; false without partial ownership on error.
//
// Side effects:
//   - Allocates and fills independent cell and row-metadata arrays.
snapshot_init :: proc(
    grid: ^Grid, snapshot: ^Snapshot,
    allocator: mem.Allocator) -> bool {

    if grid == nil || snapshot == nil || len(snapshot.cells) != 0 {
        return false
    }
    cells, cells_error := make([]Cell, len(grid.cells), allocator)
    if cells_error != nil {
        return false
    }
    rows, rows_error := make([]Snapshot_Row, len(grid.rows), allocator)
    if rows_error != nil {
        delete(cells, allocator)
        return false
    }
    copy(cells, grid.cells)
    snapshot_copy_rows(rows, grid.rows)
    snapshot^ = {
        allocator = allocator,
        cells = cells,
        rows = rows,
        columns = grid.columns,
        row_count = grid.row_count,
        cursor = grid.cursor,
    }
    return true
}

//   Release storage owned by a visible-state snapshot.
//
// Parameters:
//   - snapshot: The initialized snapshot to destroy; nil is a no-op.
//
// Side effects:
//   - Frees both arrays and resets the snapshot to zero.
snapshot_destroy :: proc(snapshot: ^Snapshot) {
    if snapshot == nil {
        return
    }
    delete(snapshot.rows, snapshot.allocator)
    delete(snapshot.cells, snapshot.allocator)
    snapshot^ = {}
}

//   Borrow valid UTF-8 retained by one leading cell.
//
// Parameters:
//   - cell: The cell to inspect.
//
// Returns:
//   - Its grapheme prefix, or an empty string for nil/continuation cells.
//
// Notes:
//   - The returned string aliases `cell` and must not outlive or mutate it.
cell_text :: proc(cell: ^Cell) -> string {
    if cell == nil || cell.continuation {
        return ""
    }
    return string(cell.grapheme[:cell.grapheme_len])
}

//   Merge one changed half-open column range into row dirty metadata.
//
// Parameters:
//   - row: The row whose renderer-visible change range is extended.
//   - start: Inclusive changed column.
//   - end: Exclusive changed column.
//
// Side effects:
//   - Initializes or widens the row's dirty union without touching cells.
grid_mark_dirty :: proc(row: ^Row, start, end: int) {
    if !row.dirty {
        row.dirty = true
        row.dirty_start = start
        row.dirty_end = end
        return
    }
    row.dirty_start = min(row.dirty_start, start)
    row.dirty_end = max(row.dirty_end, end)
}

//   Clear one cell while preserving wide leader/continuation invariants.
//
// Parameters:
//   - grid: The initialized grid.
//   - row_index: Valid visible row index.
//   - column: Valid visible column index.
//
// Side effects:
//   - Clears the addressed cell and its wide partner when present, marking both dirty.
grid_clear_cell :: proc(grid: ^Grid, row_index, column: int) {
    row := &grid.rows[row_index]
    cell := &row.cells[column]
    if cell.continuation && column > 0 {
        row.cells[column - 1] = {}
        grid_mark_dirty(row, column - 1, column + 1)
    } else if cell.width == 2 && column + 1 < grid.columns {
        row.cells[column + 1] = {}
        grid_mark_dirty(row, column, column + 2)
    } else {
        grid_mark_dirty(row, column, column + 1)
    }
    cell^ = {}
}

//   Reset one visible row to blank cells.
//
// Parameters:
//   - grid: The initialized grid.
//   - row_index: Valid visible row index.
//
// Side effects:
//   - Clears cells/wrap state and marks the complete row dirty.
grid_clear_row :: proc(grid: ^Grid, row_index: int) {
    row := &grid.rows[row_index]
    for &cell in row.cells {
        cell = {style = grid.style}
    }
    row.wrapped = false
    row.shell_markers = {}
    row.dirty = true
    row.dirty_start = 0
    row.dirty_end = grid.columns
}

//   Erase a clamped cell range using the active style for visible blanks.
//
// Parameters:
//   - grid: The initialized grid.
//   - row_index: Valid visible row index.
//   - start: Requested inclusive column, clamped into the row.
//   - end: Requested exclusive column, clamped after `start`.
//
// Side effects:
//   - Clears intersecting wide pairs, styles addressed blanks, and marks the range dirty.
grid_erase_range :: proc(
    grid: ^Grid, row_index, start, end: int, selective: bool = false) {
    row := &grid.rows[row_index]
    bounded_start := clamp(start, 0, grid.columns)
    bounded_end := clamp(end, bounded_start, grid.columns)
    for column in bounded_start..<bounded_end {
        protected := row.cells[column].protected
        if row.cells[column].continuation && column > 0 {
            protected = row.cells[column - 1].protected
        }
        if selective && protected {
            continue
        }
        grid_clear_cell(grid, row_index, column)
        grid.rows[row_index].cells[column].style = grid.style
    }
    grid_mark_dirty(&grid.rows[row_index], bounded_start, bounded_end)
}

//   Move the cursor within visible bounds and cancel delayed wrapping.
//
// Parameters:
//   - grid: The initialized grid.
//   - row: Requested row, clamped to the visible range.
//   - column: Requested column, clamped to the visible range.
//
// Side effects:
//   - Replaces cursor position and clears `wrap_pending` without changing cells.
grid_set_cursor :: proc(grid: ^Grid, row, column: int) {
    grid.cursor.row = clamp(row, 0, grid.row_count - 1)
    grid.cursor.column = clamp(column, 0, grid.columns - 1)
    grid.cursor.wrap_pending = false
}

//   Advance one row, scrolling at the bottom when necessary.
//
// Parameters:
//   - grid: The initialized grid.
//   - reset_column: Whether to return the cursor to column zero.
//   - wrapped: Whether the departed row ended through automatic wrapping.
//
// Side effects:
//   - Records wrap provenance, clears delayed wrap, moves the cursor, and may scroll.
grid_line_feed :: proc(grid: ^Grid, reset_column, wrapped: bool) {
    departed := &grid.rows[grid.cursor.row]
    next_line_id := departed.logical_line_id
    next_offset := departed.grapheme_offset + grid_row_grapheme_count(departed)
    departed.wrapped = wrapped
    grid.cursor.wrap_pending = false
    if reset_column {
        grid.cursor.column = 0
    }
    if grid.cursor.row == grid.editing.scroll_bottom {
        grid_scroll_region_up(
            grid, grid.editing.scroll_top, grid.editing.scroll_bottom, 1)
    } else if grid.cursor.row + 1 < grid.row_count {
        grid.cursor.row += 1
    }
    destination := &grid.rows[grid.cursor.row]
    if wrapped {
        destination.logical_line_id = next_line_id
        destination.grapheme_offset = next_offset
        destination.head_truncated = false
    } else {
        destination.logical_line_id = termmodel.Terminal_Logical_Line_Id(
            destination.logical_id)
        destination.grapheme_offset = 0
        destination.head_truncated = false
    }
}

//   Apply one supported basic control byte without interpreting escape sequences.
//
// Parameters:
//   - grid: The initialized grid.
//   - byte: Backspace, tab, line feed, carriage return, or an ignored control.
//
// Side effects:
//   - Moves the cursor and may line-feed/scroll; cells change only through scrolling.
grid_write_control :: proc(grid: ^Grid, byte: u8) {
    switch byte {
    case '\b':
        grid.cursor.wrap_pending = false
        grid.cursor.column = max(grid.cursor.column - 1, 0)
    case '\t':
        grid.cursor.wrap_pending = false
        next := grid.columns - 1
        for column in grid.cursor.column + 1..<min(grid.columns, TAB_STOP_CAPACITY) {
            if grid_has_tab_stop(grid, column) {
                next = column
                break
            }
        }
        grid.cursor.column = next
    case '\n':
        grid_line_feed(grid, false, false)
    case '\r':
        grid.cursor.column = 0
        grid.cursor.wrap_pending = false
    }
}

//   Classify one byte as a valid UTF-8 sequence lead.
//
// Parameters:
//   - byte: The candidate leading byte.
//
// Returns:
//   - Expected sequence length from one through four, or zero if invalid as a lead.
grid_utf8_expected_length :: proc(byte: u8) -> int {
    if byte < 0x80 {
        return 1
    }
    if byte >= 0xc2 && byte <= 0xdf {
        return 2
    }
    if byte >= 0xe0 && byte <= 0xef {
        return 3
    }
    if byte >= 0xf0 && byte <= 0xf4 {
        return 4
    }
    return 0
}

//   Validate one UTF-8 continuation byte including constrained second-byte ranges.
//
// Parameters:
//   - lead: The sequence's validated leading byte.
//   - index: Zero-based byte position of the candidate within the sequence.
//   - byte: The candidate continuation byte.
//
// Returns:
//   - True when continuation and scalar-range constraints permit the byte.
grid_utf8_continuation_valid :: proc(lead: u8, index: int, byte: u8) -> bool {
    if byte < 0x80 || byte > 0xbf {
        return false
    }
    if index != 1 {
        return true
    }
    switch lead {
    case 0xe0:
        return byte >= 0xa0
    case 0xed:
        return byte <= 0x9f
    case 0xf0:
        return byte >= 0x90
    case 0xf4:
        return byte <= 0x8f
    }
    return true
}

//   Decode and write the completed pending UTF-8 sequence.
grid_finish_pending_utf8 :: proc(grid: ^Grid) {
    pending := grid.pending_utf8[:grid.pending_utf8_len]
    codepoint, width := utf8.decode_rune(pending)
    grid.pending_utf8_len = 0
    if codepoint == utf8.RUNE_ERROR && width == 1 {
        grid.invalid_utf8_count += 1
        grid_write_replacement(grid)
        for remaining in pending[1:] {
            grid_ingest_byte(grid, remaining)
        }
        return
    }
    grid_write_rune(grid, codepoint, pending[:width])
}

//   Advance the incremental UTF-8 decoder by one byte.
//
// Notes:
//   - Invalid continuation emits one replacement, then retries the current byte.
//   - Completed malformed sequences preserve remaining bytes by recursive re-ingest.
//
// Parameters:
//   - grid: The initialized grid and decoder state.
//   - byte: The next input byte.
//
// Side effects:
//   - Buffers input or writes controls/graphemes and updates invalid-input telemetry.
grid_ingest_byte :: proc(grid: ^Grid, byte: u8) {
    if grid.pending_utf8_len == 0 {
        if byte < 0x80 {
            if byte < 0x20 || byte == 0x7f {
                grid_write_control(grid, byte)
            } else {
                grid_write_rune(grid, rune(byte), []u8{byte})
            }
            return
        }
        if grid_utf8_expected_length(byte) == 0 {
            grid.invalid_utf8_count += 1
            grid_write_replacement(grid)
            return
        }
    }

    if grid.pending_utf8_len > 0 && !grid_utf8_continuation_valid(
        grid.pending_utf8[0], grid.pending_utf8_len, byte) {
        grid.pending_utf8_len = 0
        grid.invalid_utf8_count += 1
        grid_write_replacement(grid)
        grid_ingest_byte(grid, byte)
        return
    }
    grid.pending_utf8[grid.pending_utf8_len] = byte
    grid.pending_utf8_len += 1
    expected := grid_utf8_expected_length(grid.pending_utf8[0])
    if grid.pending_utf8_len < expected {
        return
    }

    grid_finish_pending_utf8(grid)
}

//   Write one Unicode replacement character through the ordinary grapheme path.
//
// Parameters:
//   - grid: The initialized grid.
//
// Side effects:
//   - Applies ordinary width, wrap, dirty, and scroll behavior for `U+FFFD`.
grid_write_replacement :: proc(grid: ^Grid) {
    encoded, width := utf8.encode_rune(utf8.RUNE_ERROR)
    grid_write_rune(grid, utf8.RUNE_ERROR, encoded[:width])
}

//   Identify code points retained with the preceding grapheme leader.
//
// Parameters:
//   - codepoint: The Unicode scalar to classify.
//
// Returns:
//   - True for generated zero-width grapheme extensions and spacing marks.
grid_is_cluster_extension :: proc(codepoint: rune) -> bool {
    return unicode_is_zero_width(codepoint)
}

//   Map one Unicode scalar to zero, one, or two terminal cells.
//
// Parameters:
//   - codepoint: The Unicode scalar to classify.
//   - ambiguous_width: Startup-selected treatment of East Asian Ambiguous scalars.
//
// Returns:
//   - Zero for cluster extensions, two for wide or policy-wide scalars, otherwise one.
grid_rune_width :: proc(
    codepoint: rune, ambiguous_width: Ambiguous_Width_Mode = .Narrow) -> u8 {
    if grid_is_cluster_extension(codepoint) {
        return 0
    }
    if unicode_is_wide(codepoint) || unicode_is_emoji_presentation(codepoint) ||
        ambiguous_width == .Wide && unicode_is_ambiguous(codepoint) {
        return 2
    }
    return 1
}

//   Find the leading cell immediately before the logical cursor position.
//
// Parameters:
//   - grid: The initialized grid and current cursor state.
//
// Returns:
//   - The borrowed nonblank leader and column, or nil and -1 when unavailable.
grid_previous_leading_cell :: proc(grid: ^Grid) -> (^Cell, int) {
    column := grid.cursor.column
    if !grid.cursor.wrap_pending {
        column -= 1
    }
    if column < 0 {
        return nil, -1
    }
    cell := &grid.rows[grid.cursor.row].cells[column]
    if cell.continuation && column > 0 {
        column -= 1
        cell = &grid.rows[grid.cursor.row].cells[column]
    }
    if cell.width == 0 {
        return nil, -1
    }
    return cell, column
}

//   Append one complete encoded rune to a leading cell's grapheme.
//
// Parameters:
//   - grid: The grid owning truncation telemetry.
//   - cell: The leading cell receiving valid encoded bytes.
//   - encoded: One complete UTF-8 rune encoding.
//
// Side effects:
//   - Appends all bytes, or drops the whole rune and records grapheme truncation.
grid_append_cluster_bytes :: proc(grid: ^Grid, cell: ^Cell, encoded: []u8) {
    available := CELL_GRAPHEME_CAPACITY - int(cell.grapheme_len)
    if len(encoded) > available {
        cell.grapheme_truncated = true
        grid.truncated_grapheme_count += 1
        return
    }
    copy(cell.grapheme[int(cell.grapheme_len):], encoded)
    cell.grapheme_len += u8(len(encoded))
}

//   Relocate a final-column cluster to the next row while promoting it to width two.
//
// Parameters:
//   - grid: The initialized grid containing the source cluster.
//   - previous: The final-column cluster leader to relocate.
//   - previous_column: The leader's source column.
//
// Side effects:
//   - Clears the source, wraps or scrolls, writes the wide pair, and advances the cursor.
grid_relocate_promoted_cluster :: proc(
    grid: ^Grid, previous: ^Cell, previous_column: int) {
    leader := previous^
    grid_clear_cell(grid, grid.cursor.row, previous_column)
    grid_line_feed(grid, true, true)
    row := &grid.rows[grid.cursor.row]
    grid_clear_cell(grid, grid.cursor.row, 0)
    grid_clear_cell(grid, grid.cursor.row, 1)
    leader.width = 2
    row.cells[0] = leader
    row.cells[1] = {continuation = true}
    grid_mark_dirty(row, 0, 2)
    if grid.columns == 2 {
        grid.cursor.column = 1
        grid.cursor.wrap_pending = true
    } else {
        grid.cursor.column = 2
    }
}

//   Expand one prior single-column emoji cluster when presentation becomes emoji.
//
// Returns:
//   - True after the leader and cursor occupy two columns; false when one-column
//     geometry cannot represent the promotion.
//
// Side effects:
//   - Clears the destination column, writes a continuation, and advances the cursor.
grid_promote_previous_cluster :: proc(
    grid: ^Grid, previous: ^Cell, previous_column: int) -> bool {
    if previous.width != 1 || grid.columns < 2 {
        return previous.width == 2
    }
    if previous_column + 1 >= grid.columns {
        grid_relocate_promoted_cluster(grid, previous, previous_column)
        return true
    }
    row := &grid.rows[grid.cursor.row]
    grid_clear_cell(grid, grid.cursor.row, previous_column + 1)
    previous.width = 2
    row.cells[previous_column + 1] = {continuation = true}
    if !grid.cursor.wrap_pending && grid.cursor.column == previous_column + 1 {
        grid.cursor.column += 1
        if grid.cursor.column >= grid.columns {
            grid.cursor.column = grid.columns - 1
            grid.cursor.wrap_pending = true
        }
    }
    grid_mark_dirty(row, previous_column, previous_column + 2)
    return true
}

//   Attach one extension or ZWJ-linked base to the preceding grapheme.
//
// Notes:
//   - A leading extension with no base first creates a replacement-cell base.
//
// Parameters:
//   - grid: The initialized grid and logical cursor position.
//   - codepoint: The decoded scalar being considered for attachment.
//   - encoded: Its complete UTF-8 encoding.
//   - rune_width: Width assigned by `grid_rune_width`.
//
// Returns:
//   - True when consumed as part of the previous cluster; false for a new base.
//
// Side effects:
//   - Extends cluster bytes, updates ZWJ linkage, and marks the leader range dirty.
grid_extend_previous_cluster :: proc(
    grid: ^Grid, codepoint: rune, encoded: []u8, rune_width: u8) -> bool {

    previous, previous_column := grid_previous_leading_cell(grid)
    attaches_flag := unicode_is_regional_indicator(codepoint) && previous != nil &&
        previous.regional_indicator
    attaches_join := rune_width > 0 && previous != nil && previous.join_next
    if attaches_flag || attaches_join {
        previous.regional_indicator = false if attaches_flag else
            previous.regional_indicator
        previous.join_next = false if attaches_join else previous.join_next
        grid_append_cluster_bytes(grid, previous, encoded)
        row := &grid.rows[grid.cursor.row]
        grid_mark_dirty(
            row, previous_column, previous_column + int(previous.width))
        return true
    }
    if rune_width != 0 {
        return false
    }
    if previous == nil {
        grid_write_replacement(grid)
        previous, previous_column = grid_previous_leading_cell(grid)
    }
    grid_append_cluster_bytes(grid, previous, encoded)
    if codepoint == unicode.ZERO_WIDTH_JOINER {
        previous.join_next = true
    } else if codepoint == 0xfe0f || codepoint == 0x20e3 {
        if previous.emoji_candidate {
            grid_promote_previous_cluster(grid, previous, previous_column)
        }
    }
    row := &grid.rows[grid.cursor.row]
    grid_mark_dirty(
        row, previous_column, previous_column + int(previous.width))
    return true
}

// Prepare wrapping and insertion before placing one positive-width rune.
grid_prepare_rune_placement :: proc(grid: ^Grid, rune_width: u8) {
    if grid.editing.autowrap_mode && (grid.cursor.wrap_pending ||
        rune_width == 2 && grid.cursor.column == grid.columns - 1) {
        grid_line_feed(grid, true, true)
    }
    if grid.editing.insert_mode {
        grid_insert_cells(
            grid, grid.cursor.row, grid.cursor.column, int(rune_width))
    }
}

// Populate and mark one leading cell and optional continuation.
grid_place_rune :: proc(
    grid: ^Grid, codepoint: rune, encoded: []u8, rune_width: u8) {
    row := &grid.rows[grid.cursor.row]
    column := grid.cursor.column
    grid_clear_cell(grid, grid.cursor.row, column)
    if rune_width == 2 { grid_clear_cell(grid, grid.cursor.row, column + 1) }
    cell := &row.cells[column]
    cell.style = grid.style
    cell.hyperlink = grid.hyperlink
    cell.protected = grid.editing.protected_mode
    cell.width = rune_width
    cell.regional_indicator = unicode_is_regional_indicator(codepoint)
    cell.emoji_candidate = unicode_is_emoji(codepoint)
    grid_append_cluster_bytes(grid, cell, encoded)
    if rune_width == 2 { row.cells[column + 1] = {continuation = true} }
    grid_mark_dirty(row, column, column + int(rune_width))
}

//   Place one decoded rune while preserving cluster, width, and wrap invariants.
//
// Notes:
//   - A wide rune wraps before the final column; a one-column grid substitutes
//     `U+FFFD`. Filling the final column sets delayed wrap for the next base.
//
// Parameters:
//   - grid: The initialized grid.
//   - codepoint: The decoded Unicode scalar.
//   - encoded: Its complete valid UTF-8 encoding.
//
// Side effects:
//   - Extends a cluster or replaces cells, copies active style, advances the cursor,
//     marks dirty ranges, and may wrap or scroll.
grid_write_rune :: proc(grid: ^Grid, codepoint: rune, encoded: []u8) {
    rune_width := grid_rune_width(codepoint, grid.editing.ambiguous_width)
    if grid_extend_previous_cluster(grid, codepoint, encoded, rune_width) {
        return
    }
    if rune_width == 2 && (grid.columns == 1 ||
        grid.cursor.column == grid.columns - 1 &&
        !grid.editing.autowrap_mode) {
        grid_write_replacement(grid)
        return
    }
    grid_prepare_rune_placement(grid, rune_width)
    column := grid.cursor.column
    grid_place_rune(grid, codepoint, encoded, rune_width)

    next_column := column + int(rune_width)
    if next_column >= grid.columns {
        grid.cursor.column = grid.columns - 1
        grid.cursor.wrap_pending = grid.editing.autowrap_mode
    } else {
        grid.cursor.column = next_column
    }
}