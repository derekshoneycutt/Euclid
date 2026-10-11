#+test
package termgrid

import "core:testing"
import termattachment "../attachment"
import termmodel "../model"
import termshellintegration "../shell_integration"

// Initialize one small attachment store for grid-lifecycle tests.
termgrid_test_attachment_store_init :: proc(
    store: ^termattachment.Store) -> bool {
    return termattachment.store_init(store, {
        attachment_capacity = 2,
        placement_capacity = 4,
        transfer_capacity = 2,
        transfer_byte_limit = 16,
        dimension_limit = 4,
        image_pixel_limit = 16,
        cpu_byte_limit = 16,
        gpu_byte_limit = 16,
        animated_attachment_limit = 2,
        animation_frame_limit = 4,
        animation_decode_byte_limit = 64,
        animation_min_frame_duration_ns = 1_000_000,
        animation_max_frame_duration_ns = 100_000_000,
        animation_duration_ns_limit = 1_000_000_000,
    }, context.allocator)
}

// Admit one raster payload and one primary placement anchored to `logical_row`.
termgrid_test_attachment_place :: proc(
    store: ^termattachment.Store, logical_row: i64,
    screen: termattachment.Screen_Identity = .Primary) ->
    (termattachment.Attachment_Id, termattachment.Admission_Outcome) {
    payload := [4]u8{1, 2, 3, 4}
    attachment, attachment_outcome := termattachment.attachment_admit(store, {
        metadata = {
            kind = .Raster,
            origin = .Kitty,
            metrics = {width = 2, height = 2},
        },
        payload = payload[:],
        payload_format = .Indexed8,
        payload_stride = 2,
    })
    if attachment_outcome != .Admitted {
        return {}, attachment_outcome
    }
    _, placement_outcome := termattachment.placement_admit(store, {
        attachment_id = attachment,
        geometry = {
            screen = screen,
            logical_row = logical_row,
            column_span = 1,
            row_span = 1,
            source = {width = 2, height = 2},
            sizing = .Fit,
        },
    })
    return attachment, placement_outcome
}

// Corrupt all checkpoint-owned state before testing restoration.
termgrid_test_mutate_checkpoint_state :: proc(
    grid: ^Grid, scrollback: ^Scrollback) {
    grid.cells[0].hyperlink = 0
    grid.editing.scroll_top = 1
    grid.editing.scroll_bottom = 1
    grid.editing.origin_mode = true
    grid.editing.autowrap_mode = false
    grid.editing.insert_mode = true
    grid.editing.protected_mode = true
    grid.editing.tab_stops = {}
    scrollback.cells[0].hyperlink = 0
}

// Verify fixed-capacity scrollback preserves FIFO order and exact cell state.
@(test)
termgrid_test_scrollback_ring_overwrites_oldest_row :: proc(t: ^testing.T) {
    scrollback: Scrollback
    testing.expect(t, scrollback_init(&scrollback, 2, 2, context.allocator))
    defer scrollback_destroy(&scrollback)

    rows: [3][2]Cell
    bytes := [3]u8{'a', 'b', 'c'}
    for byte, index in bytes {
        rows[index][0].grapheme[0] = byte
        rows[index][0].grapheme_len = 1
        rows[index][0].width = 1
    }
    testing.expect(t, scrollback_commit(
        &scrollback, rows[0][:], {logical_row_id = 1}))
    testing.expect(t, scrollback_commit(
        &scrollback, rows[1][:], {logical_row_id = 2, wrapped = true}))
    testing.expect(t, scrollback_commit(
        &scrollback, rows[2][:], {logical_row_id = 3}))

    testing.expect_value(t, scrollback.count, 2)
    testing.expect_value(t, scrollback.committed_rows, u64(3))
    testing.expect_value(t, scrollback.evicted_rows, u64(1))
    first, first_ok := scrollback_row(&scrollback, 0)
    second, second_ok := scrollback_row(&scrollback, 1)
    testing.expect(t, first_ok && second_ok)
    testing.expect_value(t, first.logical_id, i64(2))
    testing.expect_value(t, second.logical_id, i64(3))
    testing.expect_value(t, cell_text(&first.cells[0]), "b")
    testing.expect(t, first.wrapped)
    testing.expect_value(t, cell_text(&second.cells[0]), "c")
    testing.expect(t, !second.wrapped)
}

// Verify row eviction removes a command only after its last endpoint is gone.
@(test)
termgrid_test_scrollback_eviction_prunes_command_index :: proc(t: ^testing.T) {
    shell: termshellintegration.Shell_Integration_State
    testing.expect(t, termshellintegration.shell_integration_init(
        &shell, 2, context.allocator))
    defer termshellintegration.shell_integration_destroy(&shell)
    termshellintegration.shell_command_start(
        &shell, .Prompt, {logical_line_id = 1})
    termshellintegration.shell_command_admit_marker(&shell, {
        kind = .Finished, valid = true,
    }, {logical_line_id = 1})
    scrollback: Scrollback
    testing.expect(t, scrollback_init(
        &scrollback, 2, 1, context.allocator, {shell_integration = &shell}))
    defer scrollback_destroy(&scrollback)
    cells: [2]Cell
    testing.expect(t, scrollback_commit(
        &scrollback, cells[:], {logical_row_id = 1}))
    testing.expect_value(t,
        termshellintegration.shell_command_block_count(&shell), 1)
    block, present := termshellintegration.shell_command_block(&shell, 0)
    testing.expect(t, present)
    shell.search_match_generation = block.generation

    testing.expect(t, scrollback_commit(
        &scrollback, cells[:], {logical_row_id = 2}))
    testing.expect_value(t,
        termshellintegration.shell_command_block_count(&shell), 0)
    testing.expect_value(t, shell.command_eviction_count, u64(1))
    testing.expect_value(t, shell.search_match_generation, u32(0))
}

// Verify display rollback restores the derived command index with row metadata.
@(test)
termgrid_test_display_checkpoint_restores_command_index :: proc(t: ^testing.T) {
    shell: termshellintegration.Shell_Integration_State
    testing.expect(t, termshellintegration.shell_integration_init(
        &shell, 2, context.allocator))
    defer termshellintegration.shell_integration_destroy(&shell)
    scrollback: Scrollback
    testing.expect(t, scrollback_init(
        &scrollback, 2, 2, context.allocator, {shell_integration = &shell}))
    defer scrollback_destroy(&scrollback)
    grid: Grid
    testing.expect(t, grid_init(&grid, 2, 2, allocator = context.allocator))
    defer grid_destroy(&grid)
    checkpoint: Display_Checkpoint
    testing.expect(t, display_checkpoint_init(
        &checkpoint, &grid, &scrollback, context.allocator))
    defer display_checkpoint_destroy(&checkpoint)
    termshellintegration.shell_command_start(
        &shell, .Prompt, {logical_line_id = 1})
    testing.expect(t, display_checkpoint_capture(
        &checkpoint, &grid, &scrollback))
    termshellintegration.shell_command_admit_marker(&shell, {
        kind = .Finished, valid = true,
    }, {logical_line_id = 1})
    testing.expect(t, .Finished in shell.command_blocks[0].present)

    testing.expect(t, display_checkpoint_restore(
        &checkpoint, &grid, &scrollback))
    block, present := termshellintegration.shell_command_block(&shell, 0)
    testing.expect(t, present)
    testing.expect(t, .Prompt in block.present)
    testing.expect(t, .Finished not_in block.present)
}

// Verify overwriting a scrollback slot releases its logical row's placements.
@(test)
termgrid_test_scrollback_eviction_releases_placements :: proc(t: ^testing.T) {
    store: termattachment.Store
    testing.expect(t, termgrid_test_attachment_store_init(&store))
    defer termattachment.store_destroy(&store)
    scrollback: Scrollback
    testing.expect(t, scrollback_init(
        &scrollback, 2, 1, context.allocator, {attachment_store = &store}))
    defer scrollback_destroy(&scrollback)
    attachment, outcome := termgrid_test_attachment_place(&store, 41)
    testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
    cells: [2]Cell
    testing.expect(t, scrollback_commit(
        &scrollback, cells[:], {logical_row_id = 41}))

    testing.expect(t, scrollback_commit(
        &scrollback, cells[:], {logical_row_id = 42}))

    testing.expect_value(t, store.placement_count, 0)
    entry, found := termattachment.attachment_entry(&store, attachment)
    testing.expect_value(t, found, termattachment.Handle_Outcome.Found)
    testing.expect_value(t, entry.placement_reference_count, 0)
}

// Verify historical rows retain their committed widths without semantic reflow.
@(test)
termgrid_test_scrollback_preserves_mixed_row_widths :: proc(t: ^testing.T) {
    scrollback: Scrollback
    testing.expect(t, scrollback_init(&scrollback, 6, 3, context.allocator))
    defer scrollback_destroy(&scrollback)
    narrow: [3]Cell
    wide: [6]Cell
    narrow[0].width = 1
    wide[5].width = 1

    testing.expect(t, scrollback_commit(
        &scrollback, narrow[:], {logical_row_id = 1}))
    testing.expect(t, scrollback_commit(
        &scrollback, wide[:], {logical_row_id = 2, wrapped = true}))
    first, first_ok := scrollback_row(&scrollback, 0)
    second, second_ok := scrollback_row(&scrollback, 1)
    testing.expect(t, first_ok && second_ok)
    testing.expect_value(t, len(first.cells), 3)
    testing.expect_value(t, len(second.cells), 6)
    testing.expect(t, second.wrapped)
}

// Verify complete-cell copies preserve hyperlink identity through retained views.
@(test)
termgrid_test_scrollback_preserves_hyperlinks :: proc(t: ^testing.T) {
    scrollback: Scrollback
    testing.expect(t, scrollback_init(&scrollback, 2, 1, context.allocator))
    defer scrollback_destroy(&scrollback)
    cells := [2]Cell{
        {width = 1, hyperlink = termmodel.Hyperlink_Handle(0x10001)},
        {},
    }

    testing.expect(t, scrollback_commit(
        &scrollback, cells[:], {logical_row_id = 1}))
    row, ok := scrollback_row(&scrollback, 0)
    testing.expect(t, ok)
    testing.expect_value(t, row.cells[0].hyperlink, cells[0].hyperlink)
}

// Verify display checkpoint capture and restore preserve complete-cell hyperlink identity.
@(test)
termgrid_test_display_checkpoint_preserves_hyperlinks :: proc(t: ^testing.T) {
    grid: Grid
    scrollback: Scrollback
    checkpoint: Display_Checkpoint
    testing.expect(t, grid_init(&grid, 9, 1, allocator = context.allocator))
    defer grid_destroy(&grid)
    testing.expect(t, scrollback_init(&scrollback, 9, 1, context.allocator))
    defer scrollback_destroy(&scrollback)
    testing.expect(t, display_checkpoint_init(
        &checkpoint, &grid, &scrollback, context.allocator))
    defer display_checkpoint_destroy(&checkpoint)

    grid_handle := termmodel.Hyperlink_Handle(0x10001)
    scrollback_handle := termmodel.Hyperlink_Handle(0x10002)
    grid.cells[0] = {width = 1, hyperlink = grid_handle}
    cells: [9]Cell
    cells[0] = {width = 1, hyperlink = scrollback_handle}
    testing.expect(t, scrollback_commit(
        &scrollback, cells[:], {logical_row_id = 1}))
    testing.expect(t, display_checkpoint_capture(
        &checkpoint, &grid, &scrollback))

    termgrid_test_mutate_checkpoint_state(&grid, &scrollback)
    testing.expect(t, display_checkpoint_restore(
        &checkpoint, &grid, &scrollback))
    testing.expect_value(t, grid.cells[0].hyperlink, grid_handle)
    testing.expect_value(t, grid.editing.scroll_top, 0)
    testing.expect_value(t, grid.editing.scroll_bottom, grid.row_count - 1)
    testing.expect(t,
        !grid.editing.origin_mode && grid.editing.autowrap_mode &&
        !grid.editing.insert_mode && !grid.editing.protected_mode &&
        grid_has_tab_stop(&grid, 8))
    row, ok := scrollback_row(&scrollback, 0)
    testing.expect(t, ok)
    testing.expect_value(t, row.cells[0].hyperlink, scrollback_handle)
}

// Verify display rollback restores row identity, placement references, and pins.
@(test)
termgrid_test_display_checkpoint_restores_placements :: proc(t: ^testing.T) {
    store: termattachment.Store
    testing.expect(t, termgrid_test_attachment_store_init(&store))
    defer termattachment.store_destroy(&store)
    scrollback: Scrollback
    testing.expect(t, scrollback_init(
        &scrollback, 4, 2, context.allocator, {attachment_store = &store}))
    defer scrollback_destroy(&scrollback)
    grid: Grid
    testing.expect(t, grid_init(&grid, 4, 2, context.allocator, {
        attachment_store = &store,
        screen = .Primary,
    }))
    defer grid_destroy(&grid)
    logical_row := grid.rows[0].logical_id
    attachment, outcome := termgrid_test_attachment_place(&store, logical_row)
    testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
    checkpoint: Display_Checkpoint
    testing.expect(t, display_checkpoint_init(
        &checkpoint, &grid, &scrollback, context.allocator))
    defer display_checkpoint_destroy(&checkpoint)
    testing.expect(t, display_checkpoint_capture(
        &checkpoint, &grid, &scrollback))

    termattachment.placements_remove_row(&store, .Primary, logical_row)
    grid.rows[0].logical_id = 99
    testing.expect(t, display_checkpoint_restore(
        &checkpoint, &grid, &scrollback))

    testing.expect_value(t, grid.rows[0].logical_id, logical_row)
    testing.expect_value(t, store.placement_count, 1)
    entry, found := termattachment.attachment_entry(&store, attachment)
    testing.expect_value(t, found, termattachment.Handle_Outcome.Found)
    testing.expect_value(t, entry.placement_reference_count, 1)
    testing.expect_value(t, entry.pin_count, 1)
}
