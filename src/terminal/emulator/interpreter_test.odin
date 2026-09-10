#+test
package termemulator

import "core:testing"
import "core:fmt"
import "core:encoding/base64"
import termattachment "../attachment"
import termclipboard "../clipboard"
import termgrid "../grid"
import termhyperlink "../hyperlink"
import termmodel "../model"
import termpalette "../palette"
import termshellintegration "../shell_integration"

Clipboard_Action_Queue :: termclipboard.Clipboard_Action_Queue
CLIPBOARD_ACTION_CAPACITY :: termclipboard.CLIPBOARD_ACTION_CAPACITY
CLIPBOARD_TEXT_BYTE_CAPACITY :: termclipboard.CLIPBOARD_TEXT_BYTE_CAPACITY
CLIPBOARD_ACTION_QUEUE_INIT :: termclipboard.clipboard_action_queue_init
CLIPBOARD_ACTION_QUEUE_DESTROY :: termclipboard.clipboard_action_queue_destroy
CLIPBOARD_ACTION_QUEUE_ADMIT :: termclipboard.clipboard_action_queue_admit
CLIPBOARD_ACTION_QUEUE_PEEK :: termclipboard.clipboard_action_queue_peek
CLIPBOARD_ACTION_QUEUE_POP :: termclipboard.clipboard_action_queue_pop
CLIPBOARD_DECODE_PAYLOAD :: termclipboard.clipboard_decode_payload
Hyperlink_Registry :: termhyperlink.Hyperlink_Registry
HYPERLINK_REGISTRY_CAPACITY :: termhyperlink.HYPERLINK_REGISTRY_CAPACITY
HYPERLINK_REGISTRY_INIT :: termhyperlink.hyperlink_registry_init
HYPERLINK_REGISTRY_DESTROY :: termhyperlink.hyperlink_registry_destroy
HYPERLINK_REGISTRY_ADMIT :: termhyperlink.hyperlink_registry_admit
HYPERLINK_REGISTRY_URI :: termhyperlink.hyperlink_registry_uri
Shell_Integration_State :: termshellintegration.Shell_Integration_State
Shell_Marker_Admission :: termshellintegration.Shell_Marker_Admission
SHELL_INTEGRATION_INIT :: termshellintegration.shell_integration_init
SHELL_INTEGRATION_DESTROY :: termshellintegration.shell_integration_destroy
SHELL_INTEGRATION_ADMIT_CWD :: termshellintegration.shell_integration_admit_cwd
SHELL_INTEGRATION_PARSE_STATUS :: termshellintegration.shell_integration_parse_status
SHELL_INTEGRATION_PARSE_MARKER :: termshellintegration.shell_integration_parse_marker
SHELL_COMMAND_ADMIT_MARKER :: termshellintegration.shell_command_admit_marker
SHELL_COMMAND_START :: termshellintegration.shell_command_start
SHELL_COMMAND_BLOCK :: termshellintegration.shell_command_block
SHELL_COMMAND_BLOCK_COUNT :: termshellintegration.shell_command_block_count
SHELL_COMMAND_GENERATION_RETAINED ::
    termshellintegration.shell_command_generation_retained
Terminal_Palette_State :: termpalette.Terminal_Palette_State
TERMINAL_DEFAULT_FOREGROUND_RGBA :: termpalette.TERMINAL_DEFAULT_FOREGROUND_RGBA
TERMINAL_DEFAULT_BACKGROUND_RGBA :: termpalette.TERMINAL_DEFAULT_BACKGROUND_RGBA
TERMINAL_PALETTE_INIT :: termpalette.terminal_palette_init
TERMINAL_COLOR_INDEXED :: termpalette.terminal_color_indexed
TERMINAL_COLOR_DIRECT :: termpalette.terminal_color_direct
TERMINAL_COLOR_RESOLVE_FOREGROUND :: termpalette.terminal_color_resolve_foreground
TERMINAL_COLOR_RESOLVE_BACKGROUND :: termpalette.terminal_color_resolve_background

Terminal_Producer :: termmodel.Terminal_Producer
Shell_Marker_Kind :: termmodel.Shell_Marker_Kind
Shell_Row_Markers :: termmodel.Shell_Row_Markers
Terminal_Logical_Line_Id :: termmodel.Terminal_Logical_Line_Id
Terminal_Semantic_Position :: termmodel.Terminal_Semantic_Position
Command_Block :: termmodel.Command_Block
Terminal_Mouse_Tracking_Mode :: termmodel.Terminal_Mouse_Tracking_Mode
Terminal_Input_Mode :: termmodel.Terminal_Input_Mode
Terminal_Response_Kind :: termmodel.Terminal_Response_Kind
Terminal_Response :: termmodel.Terminal_Response
Terminal_Query_Geometry :: termmodel.Terminal_Query_Geometry
Cell :: termgrid.Cell

// Fixed test-owned storage for rows evicted by emulator output.
Emulator_Scrollback_Test_State :: struct {
    rows: [8][8]termgrid.Cell,
    widths: [8]int,
    wrapped: [8]bool,
    shell_markers: [8]termmodel.Shell_Row_Markers,
    count: int,
}

// One exact query request and the semantic response it must enqueue.
Terminal_Query_Fixture :: struct {
    request: string,
    response: Terminal_Response,
}

// Return the retained UTF-8 bytes for one grid cell.
cell_text :: proc(cell: ^termgrid.Cell) -> string {
    return termgrid.cell_text(cell)
}

// Copy one evicted row into fixed emulator test storage.
emulator_test_scrollback_commit :: proc(
    user_data: rawptr, cells: []termgrid.Cell,
    metadata: termgrid.Scrollback_Row_Commit) {
    state := cast(^Emulator_Scrollback_Test_State)user_data
    copy(state.rows[state.count][:], cells)
    state.widths[state.count] = len(cells)
    state.wrapped[state.count] = metadata.wrapped
    state.shell_markers[state.count] = metadata.shell_markers
    state.count += 1
}

// Initialize one small attachment store for emulator screen tests.
emulator_test_attachment_store_init :: proc(
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

// Admit one raster attachment and placement for an emulator screen test.
emulator_test_attachment_place :: proc(
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

// Admit one alternate placement, leave mode 1049, and verify screen isolation.
termgrid_test_leave_alternate_with_placement :: proc(
    t: ^testing.T, interpreter: ^Interpreter,
    store: ^termattachment.Store,
    primary_attachment, alternate_attachment: termattachment.Attachment_Id) {
    alternate_metadata := termattachment.Placement_Metadata{
        attachment_id = alternate_attachment,
        geometry = {
            screen = .Alternate,
            logical_row = interpreter.grid.rows[0].logical_id,
            column_span = 1,
            row_span = 1,
            source = {width = 2, height = 2},
            sizing = .Fit,
        },
    }
    _, placement_outcome := termattachment.placement_admit(
        store, alternate_metadata)
    testing.expect_value(t,
        placement_outcome, termattachment.Admission_Outcome.Admitted)
    testing.expect(t, interpreter_write(interpreter, "\e[?1049l"))
    testing.expect_value(t, store.placement_count, 1)
    primary_entry, _ := termattachment.attachment_entry(
        store, primary_attachment)
    alternate_entry, _ := termattachment.attachment_entry(
        store, alternate_attachment)
    testing.expect_value(t, primary_entry.placement_reference_count, 1)
    testing.expect_value(t, alternate_entry.placement_reference_count, 0)
}

// Initialize one test interpreter and its fixed grid.
test_interpreter_init :: proc(
    t: ^testing.T, grid: ^termgrid.Grid, interpreter: ^Interpreter,
    columns, rows: int) -> bool {

    if !testing.expect(t, termgrid.grid_init(
        grid, columns, rows, allocator = context.allocator)) {
        return false
    }
    if !testing.expect(t, interpreter_init(interpreter, grid)) {
        termgrid.grid_destroy(grid)
        return false
    }
    return true
}

// Drain and compare one exact sequence of semantic terminal responses.
termgrid_test_expect_responses :: proc(
    t: ^testing.T, interpreter: ^Interpreter,
    expected: []Terminal_Response) {
    for wanted in expected {
        response, present := interpreter_peek_response(interpreter)
        testing.expect(t, present)
        testing.expect_value(t, response, wanted)
        testing.expect(t, interpreter_pop_response(interpreter))
    }
}

// Write query fixtures one byte at a time under one producer identity.
termgrid_test_write_fragmented :: proc(
    t: ^testing.T, interpreter: ^Interpreter, fixtures: []string,
    producer: Terminal_Producer) {
    for fixture in fixtures {
        for byte in transmute([]u8)fixture {
            part := [1]u8{byte}
            testing.expect(t, interpreter_write(
                interpreter, transmute(string)part[:], producer))
        }
    }
}

// Write and verify one fragmented query fixture.
termgrid_test_expect_query_fixture :: proc(
    t: ^testing.T, interpreter: ^Interpreter,
    fixture: Terminal_Query_Fixture, producer: Terminal_Producer) {
    termgrid_test_write_fragmented(
        t, interpreter, []string{fixture.request}, producer)
    termgrid_test_expect_responses(
        t, interpreter, []Terminal_Response{fixture.response})
}

// Initialize one interpreter with deterministic committed query geometry.
termgrid_test_init_query_interpreter :: proc(
    t: ^testing.T, grid: ^termgrid.Grid, interpreter: ^Interpreter,
    retained: ^Terminal_Title_State) -> bool {
    retained.query_geometry = {
        window_width = 640,
        window_height = 480,
        cell_width = 8,
        cell_height = 16,
        valid = true,
    }
    if !testing.expect(t,
        termgrid.grid_init(grid, 8, 2, allocator = context.allocator)) {
        return false
    }
    if !testing.expect(t,
        interpreter_init(interpreter, grid, {title_state = retained})) {
        termgrid.grid_destroy(grid)
        return false
    }
    return true
}

// Verify fragmented DECRQSS selectors snapshot only active interpreter state.
@(test)
termgrid_test_interpreter_decrqss_queries :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    retained: Terminal_Title_State
    interpreter: Interpreter
    if !termgrid_test_init_query_interpreter(
        t, &grid, &interpreter, &retained) { return }
    defer termgrid.grid_destroy(&grid)
    producer := Terminal_Producer{.Terminal_Session, 8, 2}
    testing.expect(t, interpreter_write(&interpreter,
        "\e[1;3;4;38;5;17;48;2;1;2;3m", producer))
    style := interpreter.grid.style
    fixtures := [?]Terminal_Query_Fixture{
        {"\eP$qm\e\\", {
            kind = .Decrqss_Sgr,
            first = TERMINAL_SGR_BOLD | TERMINAL_SGR_ITALIC |
                TERMINAL_SGR_UNDERLINE,
            second = u32(style.foreground), third = u32(style.background),
            producer = producer,
        }},
        {"\eP$q q\e\\", {
            kind = .Decrqss_Cursor_Style, producer = producer,
        }},
        {"\eP$qs\e\\", {
            kind = .Decrqss_Unsupported, producer = producer,
        }},
    }
    for fixture in fixtures {
        termgrid_test_expect_query_fixture(
            t, &interpreter, fixture, producer)
    }
    testing.expect_value(t, retained.query_acceptance_count, u64(len(fixtures)))
}

// Verify DECRQSS reports the active one-based vertical margin bounds.
@(test)
termgrid_test_interpreter_decrqss_margin_query :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    retained: Terminal_Title_State
    testing.expect(t, termgrid.grid_init(&grid, 8, 8, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    interpreter: Interpreter
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &retained}))
    producer := Terminal_Producer{.Terminal_Session, 3, 4}
    testing.expect(t, interpreter_write(&interpreter, "\e[2;7r", producer))
    termgrid_test_expect_query_fixture(t, &interpreter, {
        "\eP$qr\e\\",
        {kind = .Decrqss_Margins, first = 2, second = 7, producer = producer},
    }, producer)
}

// Verify XTGETTCAP preserves request order and classifies valid unknown names.
@(test)
termgrid_test_interpreter_xtgetcap_queries :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    retained: Terminal_Title_State
    interpreter: Interpreter
    if !termgrid_test_init_query_interpreter(
        t, &grid, &interpreter, &retained) { return }
    defer termgrid.grid_destroy(&grid)
    producer := Terminal_Producer{.Julia_Evaluation, 19, 0}
    request := "\eP+q544e;436f;524742;5463;5a5a\e\\"
    termgrid_test_write_fragmented(
        t, &interpreter, []string{request}, producer)
    names := [?]string{"544e", "436f", "524742", "5463", "5a5a"}
    expected: [len(names)]Terminal_Response
    for name, index in names {
        response, valid := terminal_capability_prepare_response(
            transmute([]u8)name, producer)
        testing.expect(t, valid)
        expected[index] = response
    }
    termgrid_test_expect_responses(t, &interpreter, expected[:])
    testing.expect_value(t, retained.query_acceptance_count, u64(len(names)))
}

// Verify malformed and response-blocked DCS queries enqueue no partial replies.
@(test)
termgrid_test_interpreter_rejects_dcs_queries_transactionally :: proc(
    t: ^testing.T) {
    grid: termgrid.Grid
    retained: Terminal_Title_State
    interpreter: Interpreter
    if !termgrid_test_init_query_interpreter(
        t, &grid, &interpreter, &retained) { return }
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_write(&interpreter, "\eP+q54xz\e\\"))
    testing.expect_value(t, retained.response_count, 0)
    testing.expect_value(t, retained.query_rejection_count, u64(1))
    for _ in 0..<TERMINAL_RESPONSE_CAPACITY - 1 {
        testing.expect(t, interpreter_enqueue_response(&interpreter, {}))
    }
    testing.expect(t, interpreter_write(
        &interpreter, "\eP+q544e;436f\e\\"))
    testing.expect_value(t, retained.response_count,
        TERMINAL_RESPONSE_CAPACITY - 1)
    testing.expect_value(t, retained.query_rejection_count, u64(2))
    testing.expect_value(t, retained.response_rejection_count, u64(1))

    overflow_payload: [TERMINAL_QUERY_BYTE_CAPACITY + 1]u8
    for &byte in overflow_payload { byte = '4' }
    testing.expect(t, interpreter_write(&interpreter, "\eP+q"))
    testing.expect(t, interpreter_write(
        &interpreter, transmute(string)overflow_payload[:]))
    testing.expect(t, interpreter_write(&interpreter, "\e\\"))
    testing.expect_value(t, retained.query_rejection_count, u64(3))
    testing.expect_value(t, interpreter.overflow_sequence_count, u64(1))
}

// Verify ANSI DECRQM reports owned insert mode and unknown status.
@(test)
termgrid_test_interpreter_ansi_mode_queries :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    retained: Terminal_Title_State
    interpreter: Interpreter
    if !termgrid_test_init_query_interpreter(
        t, &grid, &interpreter, &retained) { return }
    defer termgrid.grid_destroy(&grid)
    producer := Terminal_Producer{.Terminal_Session, 4, 6}
    fixtures := [?]Terminal_Query_Fixture{
        {"\e[4$p", {kind = .Mode_Status, first = 4, second = 2,
            producer = producer}},
        {"\e[9999$p", {kind = .Mode_Status, first = 9999, second = 0,
            producer = producer}},
    }
    termgrid_test_expect_query_fixture(t, &interpreter, fixtures[0], producer)
    testing.expect(t, interpreter_write(&interpreter, "\e[4h", producer))
    fixtures[0].response.second = 1
    termgrid_test_expect_query_fixture(t, &interpreter, fixtures[0], producer)
    termgrid_test_expect_query_fixture(t, &interpreter, fixtures[1], producer)
}

// Set every row's dirty flag for a dynamic-color redraw assertion.
termgrid_test_set_rows_dirty :: proc(grid: ^termgrid.Grid, dirty: bool) {
    for &row in grid.rows { row.dirty = dirty }
}

// Verify a committed dynamic palette update dirtied both display grids.
termgrid_test_expect_dynamic_palette_commit :: proc(
    t: ^testing.T, retained: ^Terminal_Title_State,
    grid, alternate: ^termgrid.Grid) {
    testing.expect_value(t, retained.palette.colors[1], u32(0x112233ff))
    testing.expect_value(t, retained.palette.generation, u64(1))
    for row in grid.rows { testing.expect(t, row.dirty) }
    for row in alternate.rows { testing.expect(t, row.dirty) }
}

// Verify a dynamic palette query leaves generation and row dirtiness unchanged.
termgrid_test_expect_dynamic_palette_query :: proc(
    t: ^testing.T, retained: ^Terminal_Title_State, grid: ^termgrid.Grid) {
    testing.expect_value(t, retained.palette.generation, u64(1))
    for row in grid.rows { testing.expect(t, !row.dirty) }
}

// Verify fragmented dynamic-color sets, queries, resets, and redraw generation.
@(test)
termgrid_test_interpreter_dynamic_osc_colors :: proc(t: ^testing.T) {
    grid, alternate: termgrid.Grid
    retained: Terminal_Title_State
    TERMINAL_PALETTE_INIT(&retained.palette)
    testing.expect(t, termgrid.grid_init(&grid, 4, 2, allocator = context.allocator))
    testing.expect(t, termgrid.grid_init(&alternate, 4, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    defer termgrid.grid_destroy(&alternate)
    interpreter: Interpreter
    testing.expect(t, interpreter_init(&interpreter, &grid, {
        alternate_grid = &alternate, title_state = &retained,
    }))
    termgrid_test_set_rows_dirty(&grid, false)
    termgrid_test_set_rows_dirty(&alternate, false)
    producer := Terminal_Producer{.Terminal_Session, 7, 3}

    termgrid_test_write_fragmented(t, &interpreter,
        []string{"\e]4;1;rgb:1/2/3\a"}, producer)
    termgrid_test_expect_dynamic_palette_commit(
        t, &retained, &grid, &alternate)

    termgrid_test_set_rows_dirty(&grid, false)
    termgrid_test_write_fragmented(t, &interpreter,
        []string{"\e]4;1;?\e\\"}, producer)
    termgrid_test_expect_responses(t, &interpreter, []Terminal_Response{{
        kind = .Osc_Color, first = 4, second = 1, third = 0x112233ff,
        producer = producer,
    }})
    termgrid_test_expect_dynamic_palette_query(t, &retained, &grid)

    testing.expect(t, interpreter_write(&interpreter, "\e]10;#abc\a"))
    testing.expect_value(t, retained.palette.foreground, u32(0xaabbccff))
    testing.expect(t, interpreter_write(&interpreter, "\e]110\a"))
    testing.expect_value(t, retained.palette.foreground,
        TERMINAL_DEFAULT_FOREGROUND_RGBA)
    testing.expect(t, interpreter_write(&interpreter, "\e]104;1\a"))
    testing.expect_value(t, retained.palette.colors[1], retained.palette.defaults[1])
    testing.expect_value(t, retained.palette.color_acceptance_count, u64(5))
    testing.expect_value(t, retained.palette.query_acceptance_count, u64(1))
}

// Verify malformed and response-blocked color transactions preserve palette state.
@(test)
termgrid_test_interpreter_rejects_osc_color_transactions :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    retained: Terminal_Title_State
    TERMINAL_PALETTE_INIT(&retained.palette)
    testing.expect(t, termgrid.grid_init(&grid, 4, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    interpreter: Interpreter
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &retained}))
    original_one := retained.palette.colors[1]
    original_two := retained.palette.colors[2]

    testing.expect(t, interpreter_write(
        &interpreter, "\e]4;1;#fff;2;not-a-color\a"))
    testing.expect_value(t, retained.palette.colors[1], original_one)
    testing.expect_value(t, retained.palette.colors[2], original_two)
    testing.expect_value(t, retained.palette.generation, u64(0))

    for _ in 0..<TERMINAL_RESPONSE_CAPACITY {
        testing.expect(t, interpreter_enqueue_response(&interpreter, {}))
    }
    testing.expect(t, interpreter_write(&interpreter, "\e]4;1;#000;1;?\a"))
    testing.expect_value(t, retained.palette.colors[1], original_one)
    testing.expect_value(t, retained.palette.generation, u64(0))
    testing.expect_value(t, retained.palette.color_rejection_count, u64(2))
    testing.expect_value(t, retained.palette.query_rejection_count, u64(1))
    testing.expect_value(t, retained.response_rejection_count, u64(1))
}

// Compare corresponding cells and terminal-visible interpreter state.
test_expect_interpreters_equal :: proc(
    t: ^testing.T, left, right: ^Interpreter) {

    testing.expect_value(t, left.grid.cursor, right.grid.cursor)
    testing.expect_value(t, left.grid.style, right.grid.style)
    testing.expect_value(t, left.cursor_visible, right.cursor_visible)
    testing.expect_value(t, left.input_mode, right.input_mode)
    for cell, index in left.grid.cells {
        testing.expect_value(t, cell, right.grid.cells[index])
    }
}

// Verify one prefix reaches a parser state that CAN cancels without malformed input.
test_expect_interpreter_cancel :: proc(
    t: ^testing.T, interpreter: ^Interpreter, prefix: string,
    expected_state: Interpreter_State, expected_count: u64) {
    testing.expect(t, interpreter_write(interpreter, prefix))
    testing.expect_value(t, interpreter.state, expected_state)
    testing.expect(t, interpreter_write(interpreter, "\x18"))
    testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
    testing.expect_value(
        t, interpreter.cancelled_sequence_count, expected_count)
}

// Verify committed shell metadata and checkpoint restoration.
termgrid_test_expect_shell_integration :: proc(
    t: ^testing.T, shell: ^Shell_Integration_State, scrollback: ^termgrid.Scrollback,
    grid: ^termgrid.Grid, checkpoint: ^termgrid.Display_Checkpoint) {
    testing.expect_value(t,
        string(shell.observed_cwd_uri[:shell.observed_cwd_uri_byte_count]),
        "file://localhost/tmp/project")
    testing.expect_value(t, shell.cwd_acceptance_count, u64(1))
    testing.expect_value(t, shell.marker_acceptance_count, u64(4))
    history_row, history_ok := termgrid.scrollback_row(scrollback, 0)
    testing.expect(t, history_ok)
    testing.expect(t, history_row.shell_markers.present[.Prompt])
    testing.expect(t, history_row.shell_markers.present[.Command])
    testing.expect_value(t, history_row.shell_markers.columns[.Command], u16(2))
    testing.expect(t, grid.rows[0].shell_markers.present[.Execution])
    testing.expect(t, grid.rows[1].shell_markers.present[.Finished])
    testing.expect_value(t, grid.rows[1].shell_markers.finished_status, i32(17))
    testing.expect(t, termgrid.display_checkpoint_capture(checkpoint, grid, scrollback))
    grid.rows[1].shell_markers = {}
    testing.expect(t, termgrid.display_checkpoint_restore(checkpoint, grid, scrollback))
    testing.expect(t, grid.rows[1].shell_markers.present[.Finished])
}

// Verify one complete indexed command retains exact marker positions and status.
termgrid_test_expect_command_block :: proc(
    t: ^testing.T, shell: ^Shell_Integration_State) {
    testing.expect_value(t, SHELL_COMMAND_BLOCK_COUNT(shell), 1)
    block, block_ok := SHELL_COMMAND_BLOCK(shell, 0)
    testing.expect(t, block_ok)
    testing.expect(t, block.present == {
        .Prompt, .Command, .Execution, .Finished,
    })
    testing.expect_value(t, block.prompt, Terminal_Semantic_Position{1, 0})
    testing.expect_value(t, block.command, Terminal_Semantic_Position{1, 2})
    testing.expect_value(t, block.execution.logical_line_id,
        Terminal_Logical_Line_Id(2))
    testing.expect_value(t, block.finished.logical_line_id,
        Terminal_Logical_Line_Id(3))
    testing.expect_value(t, block.status, i32(17))
    testing.expect(t, block.status_present)
}

// Drive rejected OSC 8 cases and verify an accepted link remains active.
termgrid_test_expect_unsafe_hyperlinks_rejected :: proc(
    t: ^testing.T, interpreter: ^Interpreter, grid: ^termgrid.Grid,
    registry: ^Hyperlink_Registry) {
    rejected := [9]string{
        "javascript:alert(1)", "https://user@example.com/path",
        "file://remote/tmp/file", "file:///tmp/../secret",
        "file:///tmp/%2e%2e/secret", "file:///tmp%2fsecret",
        "file:///tmp/bad%2", "https://example.com/bad%2",
        "https://example.com/bad path",
    }
    for uri in rejected {
        testing.expect(t, interpreter_write(
            interpreter, fmt.tprintf("\e]8;;%s\aX", uri)))
        testing.expect_value(t, grid.hyperlink, termmodel.Hyperlink_Handle(0))
    }
    testing.expect_value(t, registry.count, 0)
    testing.expect_value(t, interpreter.hyperlink_rejection_count, u64(9))
    testing.expect(t, interpreter_write(
        interpreter, "\e]8;unknown=value;https://example.com\aY"))
    testing.expect_value(t, interpreter.hyperlink_rejection_count, u64(10))
    testing.expect(t, interpreter_write(
        interpreter, "\e]8;;https://example.com\a"))
    active_handle := grid.hyperlink
    testing.expect(t, interpreter_write(
        interpreter, "\e]8;bad;https://bad.example\aZ"))
    testing.expect_value(t, grid.hyperlink, active_handle)
    active_uri, active_ok := HYPERLINK_REGISTRY_URI(registry, active_handle)
    testing.expect(t, active_ok)
    testing.expect_value(t, active_uri, "https://example.com")
}

// Verify synchronized output captures once and publishes live state.
termgrid_test_expect_synchronized_transaction :: proc(
    t: ^testing.T, interpreter: ^Interpreter,
    synchronized: ^Synchronized_Output_State, grid: ^termgrid.Grid) {
    producer := Terminal_Producer{.Terminal_Session, 4, 7}
    testing.expect(t, interpreter_write(
        interpreter, "old\e[?2026hnew\e[?2026h", producer))
    testing.expect(t, synchronized.active)
    testing.expect_value(t, synchronized.begin_count, u64(1))
    testing.expect_value(t,
        cell_text(&synchronized.checkpoint.grid_cells[0]), "o")
    testing.expect_value(t, cell_text(&grid.cells[3]), "n")
    testing.expect(t, interpreter_write(interpreter, "\e[?2026l", producer))
    testing.expect(t, !synchronized.active)
    testing.expect_value(t, synchronized.publish_count, u64(1))
    testing.expect_value(t, cell_text(&grid.cells[3]), "n")
}

// Verify synchronized output publishes at producer and screen boundaries.
termgrid_test_expect_synchronized_boundaries :: proc(
    t: ^testing.T, interpreter: ^Interpreter,
    synchronized: ^Synchronized_Output_State) {
    first := Terminal_Producer{.Terminal_Session, 1, 1}
    second := Terminal_Producer{.Terminal_Session, 2, 1}
    testing.expect(t, interpreter_write(interpreter, "\e[?2026h\e[5n", first))
    response, present := interpreter_peek_response(interpreter)
    testing.expect(t, present)
    testing.expect_value(t, response.kind, Terminal_Response_Kind.Device_Status)
    testing.expect(t, synchronized.active)
    testing.expect(t, interpreter_write(interpreter, "x", second))
    testing.expect(t, !synchronized.active)
    testing.expect_value(t, synchronized.forced_publish_count, u64(1))
    testing.expect(t, interpreter_write(
        interpreter, "\e[?2026h\e[?1049h", second))
    testing.expect(t, !synchronized.active)
    testing.expect(t, interpreter.alternate_screen_active)
    testing.expect_value(t, synchronized.forced_publish_count, u64(2))
    testing.expect(t, interpreter_write(
        interpreter, "\e[?1049l\e[?2026h", second))
    interpreter_finish_input(interpreter)
    testing.expect(t, !synchronized.active)
    testing.expect_value(t, synchronized.forced_publish_count, u64(3))
}

// Compare every primary cell after an alternate-screen round trip.
termgrid_test_expect_cells :: proc(
    t: ^testing.T, grid: ^termgrid.Grid, expected: []Cell) {
    for cell, index in grid.cells {
        testing.expect_value(t, cell, expected[index])
    }
}

// Verify SGR parsing remains equivalent across every one-byte input boundary.
@(test)
termgrid_test_interpreter_sgr_is_chunk_independent :: proc(t: ^testing.T) {
    contiguous_grid, chunked_grid: termgrid.Grid
    contiguous, chunked: Interpreter
    if !test_interpreter_init(t, &contiguous_grid, &contiguous, 12, 2) {
        return
    }
    defer termgrid.grid_destroy(&contiguous_grid)
    if !test_interpreter_init(t, &chunked_grid, &chunked, 12, 2) {
        return
    }
    defer termgrid.grid_destroy(&chunked_grid)

    fixture := "\e[1;38;5;196mERROR\e[0m \e[3;4;38:2::10:20:30mlink\e[0m"
    testing.expect(t, interpreter_write(&contiguous, fixture))
    for byte in transmute([]u8)fixture {
        part := [1]u8{byte}
        testing.expect(t,
            interpreter_write(&chunked, transmute(string)part[:]))
    }

    test_expect_interpreters_equal(t, &contiguous, &chunked)
    testing.expect_value(t, contiguous_grid.cells[0].style.foreground,
        TERMINAL_COLOR_INDEXED(196))
    testing.expect(t, contiguous_grid.cells[0].style.bold)
    testing.expect_value(t, contiguous_grid.cells[6].style.foreground,
        TERMINAL_COLOR_DIRECT(0x0A141EFF))
    testing.expect(t, contiguous_grid.cells[6].style.italic)
    testing.expect(t, contiguous_grid.cells[6].style.underline)
}

// Verify indexed and direct colors map exactly and reject invalid groups atomically.
@(test)
termgrid_test_interpreter_extended_sgr_colors :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 8, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)

    fixture := "\e[38;5;16mA\e[38;5;231mB\e[38;5;232mC" +
        "\e[48;2;1;2;3mD\e[38:5:255mE"
    testing.expect(t, interpreter_write(&interpreter, fixture))
    testing.expect_value(t, grid.cells[0].style.foreground,
        TERMINAL_COLOR_INDEXED(16))
    testing.expect_value(t, grid.cells[1].style.foreground,
        TERMINAL_COLOR_INDEXED(231))
    testing.expect_value(t, grid.cells[2].style.foreground,
        TERMINAL_COLOR_INDEXED(232))
    testing.expect_value(t, grid.cells[3].style.background,
        TERMINAL_COLOR_DIRECT(0x010203FF))
    testing.expect_value(t, grid.cells[4].style.foreground,
        TERMINAL_COLOR_INDEXED(255))

    previous := grid.style.foreground
    testing.expect(t, interpreter_write(&interpreter, "\e[38;5;256mX"))
    testing.expect_value(t, grid.cells[5].style.foreground, previous)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(1))
}

// Verify standard/bright backgrounds, reset, erase blanks, and resize preservation.
@(test)
termgrid_test_interpreter_sgr_backgrounds_survive_boundaries :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 6, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)
    fixture := "\e[44mA界\e[104mB\e[49mC"
    for byte in transmute([]u8)fixture {
        part := [1]u8{byte}
        testing.expect(t,
            interpreter_write(&interpreter, transmute(string)part[:]))
    }
    testing.expect_value(t, grid.cells[0].style.background,
        TERMINAL_COLOR_INDEXED(4))
    testing.expect_value(t, grid.cells[1].style.background,
        TERMINAL_COLOR_INDEXED(4))
    testing.expect(t, grid.cells[2].continuation)
    testing.expect_value(t, grid.cells[3].style.background,
        TERMINAL_COLOR_INDEXED(12))
    testing.expect_value(t, grid.cells[4].style.background,
        termmodel.Terminal_Color_Reference(0))

    testing.expect(t, interpreter_write(&interpreter, "\e[42m\e[2K"))
    testing.expect_value(t,
        grid.rows[0].cells[5].style.background, TERMINAL_COLOR_INDEXED(2))
    prepared, result := termgrid.grid_prepare_resize(
        &grid, 8, 3, context.allocator)
    testing.expect_value(t, result, termgrid.Grid_Resize_Result.Prepared)
    testing.expect(t, termgrid.grid_commit_resize(&grid, &prepared))
    testing.expect_value(t, grid.style.background, TERMINAL_COLOR_INDEXED(2))
    testing.expect(t, interpreter_write(&interpreter, "\e[0mZ"))
    testing.expect_value(
        t, grid.style.background, termmodel.Terminal_Color_Reference(0))
}

// Verify validated shell titles commit across BEL and ST chunk boundaries.
@(test)
termgrid_test_interpreter_consumes_osc_title_sequences :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    title_state: Terminal_Title_State
    if !testing.expect(t, termgrid.grid_init(
        &grid, 24, 2, allocator = context.allocator)) {
        return
    }
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &title_state}))

    fixture := "\e]0;derek@BlackBoxen Euclid\a$ \e]2;working\e\\ready"
    for byte in transmute([]u8)fixture {
        part := [1]u8{byte}
        testing.expect(t,
            interpreter_write(&interpreter, transmute(string)part[:]))
    }

    testing.expect_value(t, interpreter_title(&interpreter), "working")
    testing.expect_value(t, interpreter.title_acceptance_count, u64(2))
    testing.expect_value(t, interpreter.title_rejection_count, u64(0))
    testing.expect_value(t, cell_text(&grid.cells[0]), "$")
    testing.expect_value(t, cell_text(&grid.cells[1]), " ")
    testing.expect_value(t, cell_text(&grid.cells[2]), "r")
    testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(0))
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(0))
    testing.expect_value(t, interpreter.overflow_sequence_count, u64(0))
}

// Verify fragmented OSC 8 transactions stamp stable handles on leading cells only.
@(test)
termgrid_test_interpreter_applies_osc_hyperlinks :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    registry: Hyperlink_Registry
    testing.expect(t, HYPERLINK_REGISTRY_INIT(&registry, context.allocator))
    defer HYPERLINK_REGISTRY_DESTROY(&registry)
    testing.expect(t, termgrid.grid_init(&grid, 8, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {
            title_state = &retained,
            hyperlink_registry = &registry,
        }))

    termgrid_test_write_fragmented(t, &interpreter,
        []string{"\e]8;id=first;https://example.com", "\aA界",
            "\e]8;;mailto:test@example.com\e\\B", "\e]8;;\aC"}, {})

    first := grid.cells[0].hyperlink
    second := grid.cells[3].hyperlink
    testing.expect(t, first != 0)
    testing.expect(t, second != 0 && second != first)
    testing.expect_value(t, grid.cells[1].hyperlink, first)
    testing.expect_value(t, grid.cells[2].hyperlink, termmodel.Hyperlink_Handle(0))
    testing.expect_value(t, grid.cells[4].hyperlink, termmodel.Hyperlink_Handle(0))
    first_uri, first_ok := HYPERLINK_REGISTRY_URI(&registry, first)
    second_uri, second_ok := HYPERLINK_REGISTRY_URI(&registry, second)
    testing.expect(t, first_ok && second_ok)
    testing.expect_value(t, first_uri, "https://example.com")
    testing.expect_value(t, second_uri, "mailto:test@example.com")
    testing.expect_value(t, interpreter.hyperlink_acceptance_count, u64(3))
    testing.expect_value(t, interpreter.hyperlink_rejection_count, u64(0))
}

// Verify fragmented OSC 52 writes decode canonically and retain producer identity.
@(test)
termgrid_test_interpreter_queues_osc_clipboard_writes :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    queue: Clipboard_Action_Queue
    producer := Terminal_Producer{.Terminal_Session, 17, 3}
    testing.expect(t, CLIPBOARD_ACTION_QUEUE_INIT(&queue, context.allocator))
    defer CLIPBOARD_ACTION_QUEUE_DESTROY(&queue)
    testing.expect(t, termgrid.grid_init(&grid, 8, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {
            title_state = &retained,
            clipboard_actions = &queue,
        }))

    termgrid_test_write_fragmented(t, &interpreter,
        []string{"\e]52;c;SGV", "sbG8=\a", "\e]52;;zrI=\e", "\\"}, producer)

    first, first_ok := CLIPBOARD_ACTION_QUEUE_PEEK(&queue)
    testing.expect(t, first_ok)
    testing.expect_value(t, string(first.bytes[:first.byte_count]), "Hello")
    testing.expect_value(t, first.producer, producer)
    CLIPBOARD_ACTION_QUEUE_POP(&queue)
    second, second_ok := CLIPBOARD_ACTION_QUEUE_PEEK(&queue)
    testing.expect(t, second_ok)
    testing.expect_value(t, string(second.bytes[:second.byte_count]), "β")
    testing.expect_value(t, queue.acceptance_count, u64(2))
    testing.expect_value(t, queue.rejection_count, u64(0))
}

// Verify fragmented OSC 7/133 transactions commit only local cwd and row metadata.
@(test)
termgrid_test_interpreter_commits_shell_integration :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    shell: Shell_Integration_State
    scrollback: termgrid.Scrollback
    checkpoint: termgrid.Display_Checkpoint
    testing.expect(t, SHELL_INTEGRATION_INIT(&shell, 4, context.allocator))
    defer SHELL_INTEGRATION_DESTROY(&shell)
    testing.expect(t, termgrid.scrollback_init(&scrollback, 8, 4, context.allocator))
    defer termgrid.scrollback_destroy(&scrollback)
    sink := termgrid.Scrollback_Sink{
        user_data = &scrollback,
        commit = termgrid.scrollback_sink_commit,
    }
    testing.expect(t, termgrid.grid_init(
        &grid, 8, 2, context.allocator, {scrollback = sink}))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, termgrid.display_checkpoint_init(
        &checkpoint, &grid, &scrollback, context.allocator))
    defer termgrid.display_checkpoint_destroy(&checkpoint)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {
            title_state = &retained,
            shell_integration = &shell,
        }))

    termgrid_test_write_fragmented(t, &interpreter, []string{
        "\e]7;file://local", "host/tmp/project\a",
        "\e]133;A\e", "\\ab\e]133;B\a\r\n",
        "\e]133;C\aoutput\r\n\e]133;D;", "17\e\\",
    }, {})
    termgrid_test_expect_shell_integration(
        t, &shell, &scrollback, &grid, &checkpoint)
    termgrid_test_expect_command_block(t, &shell)
}

// Verify incomplete lifecycles close chronologically and ring overwrite stays bounded.
@(test)
termgrid_test_shell_command_index_lifecycle_and_wrap :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    shell: Shell_Integration_State
    testing.expect(t, SHELL_INTEGRATION_INIT(&shell, 2, context.allocator))
    defer SHELL_INTEGRATION_DESTROY(&shell)
    testing.expect(t, termgrid.grid_init(&grid, 16, 4, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {shell_integration = &shell}))

    testing.expect(t, interpreter_write(&interpreter,
        "\e]133;A\a\e]133;B\aone\r\n" +
        "\e]133;A\a\e]133;B\atwo\e]133;C\a\e]133;D;2\a\r\n" +
        "\e]133;A\a\e]133;B\athree\e]133;C\a\e]133;D;3\a"))

    testing.expect_value(t, SHELL_COMMAND_BLOCK_COUNT(&shell), 2)
    first, first_ok := SHELL_COMMAND_BLOCK(&shell, 0)
    second, second_ok := SHELL_COMMAND_BLOCK(&shell, 1)
    testing.expect(t, first_ok && second_ok)
    shell.search_match_generation = first.generation
    testing.expect_value(t, first.status, i32(2))
    testing.expect_value(t, second.status, i32(3))
    testing.expect(t, .Finished in first.present)
    testing.expect(t, .Finished in second.present)
    testing.expect_value(t, shell.command_eviction_count, u64(1))
    testing.expect(t, SHELL_COMMAND_GENERATION_RETAINED(
        &shell, shell.search_match_generation))

    testing.expect(t, interpreter_write(&interpreter,
        "\r\n\e]133;A\a\e]133;B\afour\e]133;C\a\e]133;D;4\a"))
    testing.expect_value(t, shell.search_match_generation, u32(0))
}

// Verify soft wrapping retains ordered semantic endpoints across physical rows.
@(test)
termgrid_test_shell_command_index_tracks_wrapped_endpoints :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    shell: Shell_Integration_State
    testing.expect(t, SHELL_INTEGRATION_INIT(&shell, 4, context.allocator))
    defer SHELL_INTEGRATION_DESTROY(&shell)
    testing.expect(t, termgrid.grid_init(&grid, 4, 3, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {shell_integration = &shell}))

    testing.expect(t, interpreter_write(&interpreter,
        "\e]133;A\a\e]133;B\aabcdef\e]133;C\a\e]133;D\a"))
    block, present := SHELL_COMMAND_BLOCK(&shell, 0)
    testing.expect(t, present)
    testing.expect_value(t, block.command.logical_line_id,
        block.execution.logical_line_id)
    testing.expect(t,
        block.command.grapheme_offset < block.execution.grapheme_offset)
    testing.expect_value(t, block.execution.logical_line_id,
        block.finished.logical_line_id)
    testing.expect(t, grid.rows[0].wrapped)
}

// Verify malformed regression closes prior state without rewriting older blocks.
@(test)
termgrid_test_shell_command_index_handles_malformed_order :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    shell: Shell_Integration_State
    testing.expect(t, SHELL_INTEGRATION_INIT(&shell, 4, context.allocator))
    defer SHELL_INTEGRATION_DESTROY(&shell)
    testing.expect(t, termgrid.grid_init(&grid, 16, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {shell_integration = &shell}))

    testing.expect(t, interpreter_write(&interpreter,
        "\e]133;A\a\e]133;B\aone\e]133;B\atwo"))
    testing.expect_value(t, SHELL_COMMAND_BLOCK_COUNT(&shell), 2)
    incomplete, incomplete_ok := SHELL_COMMAND_BLOCK(&shell, 0)
    active, active_ok := SHELL_COMMAND_BLOCK(&shell, 1)
    testing.expect(t, incomplete_ok && active_ok)
    testing.expect(t, .Finished not_in incomplete.present)
    testing.expect(t, .Command in active.present)
    testing.expect_value(t, shell.lifecycle_malformed_count, u64(1))
}

// Verify alternate-screen markers never enter persistent primary command history.
@(test)
termgrid_test_shell_command_index_ignores_alternate_screen :: proc(t: ^testing.T) {
    primary: termgrid.Grid
    alternate: termgrid.Grid
    interpreter: Interpreter
    shell: Shell_Integration_State
    testing.expect(t, SHELL_INTEGRATION_INIT(&shell, 4, context.allocator))
    defer SHELL_INTEGRATION_DESTROY(&shell)
    testing.expect(t, termgrid.grid_init(&primary, 8, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&primary)
    testing.expect(t, termgrid.grid_init(&alternate, 8, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&alternate)
    testing.expect(t, interpreter_init(&interpreter, &primary, {
        alternate_grid = &alternate,
        shell_integration = &shell,
    }))

    testing.expect(t, interpreter_write(&interpreter,
        "\e[?1049h\e]133;A\a\e]133;B\aalt\e]133;C\a\e]133;D\a" +
        "\e[?1049l\e]133;A\a"))
    testing.expect_value(t, SHELL_COMMAND_BLOCK_COUNT(&shell), 1)
    block, present := SHELL_COMMAND_BLOCK(&shell, 0)
    testing.expect(t, present)
    testing.expect(t, .Prompt in block.present)
    testing.expect(t, .Command not_in block.present)
}

// Verify invalid cwd and marker transactions preserve prior committed metadata.
@(test)
termgrid_test_interpreter_rejects_invalid_shell_integration :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    shell: Shell_Integration_State
    testing.expect(t, termgrid.grid_init(&grid, 8, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {shell_integration = &shell}))
    testing.expect(t, interpreter_write(
        &interpreter, "\e]7;file:///tmp/good\a"))
    testing.expect(t, interpreter_write(
        &interpreter, "\e]7;https://example.com/unsafe\a"))
    testing.expect(t, interpreter_write(
        &interpreter, "\e]133;D;-1\a\e]133;E\a"))

    testing.expect_value(t,
        string(shell.observed_cwd_uri[:shell.observed_cwd_uri_byte_count]),
        "file:///tmp/good")
    testing.expect_value(t, shell.cwd_acceptance_count, u64(1))
    testing.expect_value(t, shell.cwd_rejection_count, u64(1))
    testing.expect_value(t, shell.marker_acceptance_count, u64(0))
    testing.expect_value(t, shell.marker_rejection_count, u64(2))
}

// Verify OSC 52 rejects reads, unsupported selections, controls, and aliases.
@(test)
termgrid_test_interpreter_rejects_unsafe_osc_clipboard_writes :: proc(
    t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    queue: Clipboard_Action_Queue
    testing.expect(t, CLIPBOARD_ACTION_QUEUE_INIT(&queue, context.allocator))
    defer CLIPBOARD_ACTION_QUEUE_DESTROY(&queue)
    testing.expect(t, termgrid.grid_init(&grid, 8, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {
            title_state = &retained,
            clipboard_actions = &queue,
        }))

    rejected := [9]string{
        "\e]52;c;?\a",
        "\e]52;p;QQ==\a",
        "\e]52;cp;QQ==\a",
        "\e]52;c;QQ\a",
        "\e]52;c;QR==\a",
        "\e]52;c;AA==\a",
        "\e]52;c;Gw==\a",
        "\e]52;c;woA=\a",
        "\e]52;c;wyg=\a",
    }
    for sequence in rejected {
        testing.expect(t, interpreter_write(&interpreter, sequence))
    }
    testing.expect_value(t, queue.count, 0)
    testing.expect_value(t, queue.acceptance_count, u64(0))
    testing.expect_value(t, queue.rejection_count, u64(len(rejected)))
}

// Verify clipboard queue pressure rejects new work and preserves FIFO content.
@(test)
termgrid_test_osc_clipboard_queue_is_bounded :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    queue: Clipboard_Action_Queue
    testing.expect(t, CLIPBOARD_ACTION_QUEUE_INIT(&queue, context.allocator))
    defer CLIPBOARD_ACTION_QUEUE_DESTROY(&queue)
    testing.expect(t, termgrid.grid_init(&grid, 8, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {
            title_state = &retained,
            clipboard_actions = &queue,
        }))

    for index in 0..<CLIPBOARD_ACTION_CAPACITY {
        testing.expect(t, interpreter_write(
            &interpreter, "\e]52;c;QQ==\a",
            Terminal_Producer{.Julia_Evaluation, u64(index + 1), 1}))
    }
    testing.expect(t, interpreter_write(&interpreter, "\e]52;c;Qg==\a"))
    testing.expect_value(t, queue.count, CLIPBOARD_ACTION_CAPACITY)
    testing.expect_value(t, queue.acceptance_count,
        u64(CLIPBOARD_ACTION_CAPACITY))
    testing.expect_value(t, queue.rejection_count, u64(1))
    first, found := CLIPBOARD_ACTION_QUEUE_PEEK(&queue)
    testing.expect(t, found)
    testing.expect_value(t, string(first.bytes[:first.byte_count]), "A")
    testing.expect_value(t, first.producer.id, u64(1))
}

// Verify the decoded clipboard policy accepts exactly 3 KiB and rejects 3 KiB plus one.
@(test)
termgrid_test_osc_clipboard_decoded_limit_is_exact :: proc(t: ^testing.T) {
    source: [CLIPBOARD_TEXT_BYTE_CAPACITY + 1]u8
    for &byte in source {
        byte = 'A'
    }
    encoded: [4100]u8
    destination: [CLIPBOARD_TEXT_BYTE_CAPACITY + 1]u8
    exact, exact_error := base64.encode_into_buf(
        encoded[:], source[:CLIPBOARD_TEXT_BYTE_CAPACITY])
    testing.expect(t, exact_error == nil)
    exact_payload: [4098]u8
    exact_payload[0] = 'c'
    exact_payload[1] = ';'
    copy(exact_payload[2:], exact)
    count, accepted := CLIPBOARD_DECODE_PAYLOAD(
        exact_payload[:], destination[:])
    testing.expect(t, accepted)
    testing.expect_value(t, count, CLIPBOARD_TEXT_BYTE_CAPACITY)

    overflow, overflow_error := base64.encode_into_buf(encoded[:], source[:])
    testing.expect(t, overflow_error == nil)
    overflow_payload: [4102]u8
    overflow_payload[0] = 'c'
    overflow_payload[1] = ';'
    copy(overflow_payload[2:], overflow)
    _, overflow_accepted := CLIPBOARD_DECODE_PAYLOAD(
        overflow_payload[:], destination[:])
    testing.expect(t, !overflow_accepted)
}

// Verify OSC 8 admission rejects unsafe schemes, credentials, and nonlocal files.
@(test)
termgrid_test_interpreter_rejects_unsafe_osc_hyperlinks :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    registry: Hyperlink_Registry
    testing.expect(t, HYPERLINK_REGISTRY_INIT(&registry, context.allocator))
    defer HYPERLINK_REGISTRY_DESTROY(&registry)
    testing.expect(t, termgrid.grid_init(&grid, 8, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {
            title_state = &retained,
            hyperlink_registry = &registry,
        }))
    termgrid_test_expect_unsafe_hyperlinks_rejected(
        t, &interpreter, &grid, &registry)
}

// Verify exact URI reuse does not consume capacity and exhaustion preserves state.
@(test)
termgrid_test_hyperlink_registry_is_bounded :: proc(t: ^testing.T) {
    registry: Hyperlink_Registry
    testing.expect(t, HYPERLINK_REGISTRY_INIT(&registry, context.allocator))
    defer HYPERLINK_REGISTRY_DESTROY(&registry)
    first, first_ok := HYPERLINK_REGISTRY_ADMIT(&registry, "https://example.com")
    duplicate, duplicate_ok := HYPERLINK_REGISTRY_ADMIT(
        &registry, "https://example.com")
    testing.expect(t, first_ok && duplicate_ok)
    testing.expect_value(t, duplicate, first)

    for index in 1..<HYPERLINK_REGISTRY_CAPACITY {
        uri := fmt.tprintf("https://example.com/%d", index)
        _, admitted := HYPERLINK_REGISTRY_ADMIT(&registry, uri)
        testing.expect(t, admitted)
    }
    _, admitted := HYPERLINK_REGISTRY_ADMIT(&registry, "https://overflow.example")
    testing.expect(t, !admitted)
    testing.expect_value(t, registry.count, HYPERLINK_REGISTRY_CAPACITY)
    testing.expect_value(t, registry.rejection_count, u64(1))
}

// Verify invalid title candidates and OSC 1 preserve the retained title.
@(test)
termgrid_test_interpreter_rejects_invalid_osc_titles :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    title_state: Terminal_Title_State
    if !testing.expect(t, termgrid.grid_init(
        &grid, 8, 2, allocator = context.allocator)) {
        return
    }
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &title_state}))

    testing.expect(t, interpreter_write(&interpreter, "\e]2;stable\a"))
    testing.expect(t, interpreter_write(&interpreter, "\e]1;icon-only\a"))
    testing.expect_value(t, interpreter_title(&interpreter), "stable")

    invalid := [2]u8{0xc3, 0x28}
    testing.expect(t, interpreter_write(&interpreter, "\e]2;"))
    testing.expect(t, interpreter_write(&interpreter, string(invalid[:])))
    testing.expect(t, interpreter_write(&interpreter, "\e\\"))
    testing.expect_value(t, interpreter_title(&interpreter), "stable")
    testing.expect_value(t, interpreter.title_acceptance_count, u64(1))
    testing.expect_value(t, interpreter.title_rejection_count, u64(1))

    testing.expect(t, interpreter_write(&interpreter, "\e]2;discarded"))
    interpreter_finish_input(&interpreter)
    testing.expect(t, interpreter_write(&interpreter, "\e]0;\a"))
    testing.expect_value(t, interpreter_title(&interpreter), "")
    testing.expect(t, interpreter_write(&interpreter, "\e]2;temporary\a"))
    interpreter_finish_input(&interpreter)
    testing.expect_value(t, interpreter_title(&interpreter), "")
}

// Verify title candidates enforce their exact fixed byte capacity.
@(test)
termgrid_test_interpreter_bounds_osc_titles :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    title_state: Terminal_Title_State
    testing.expect(t, termgrid.grid_init(
        &grid, 8, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &title_state}))

    exact: [TERMINAL_TITLE_BYTE_CAPACITY]u8
    for &byte in exact {
        byte = 'z'
    }
    testing.expect(t, interpreter_write(&interpreter, "\e]0;"))
    testing.expect(t, interpreter_write(&interpreter, string(exact[:])))
    testing.expect(t, interpreter_write(&interpreter, "\a"))
    testing.expect_value(t, len(interpreter_title(&interpreter)), len(exact))

    oversized: [TERMINAL_TITLE_BYTE_CAPACITY + 1]u8
    for &byte in oversized {
        byte = 'x'
    }
    testing.expect(t, interpreter_write(&interpreter, "\e]0;"))
    testing.expect(t, interpreter_write(&interpreter, string(oversized[:])))
    testing.expect(t, interpreter_write(&interpreter, "\a"))
    testing.expect_value(t, len(interpreter_title(&interpreter)), len(exact))
    testing.expect_value(t, interpreter.title_acceptance_count, u64(1))
    testing.expect_value(t, interpreter.title_rejection_count, u64(1))
}

// Verify an overlong OSC stays discarded until its terminator.
@(test)
termgrid_test_interpreter_discards_overlong_osc :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 8, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)

    testing.expect(t, interpreter_write(&interpreter, "\e]0;"))
    for _ in 0..=OSC_SEQUENCE_BYTE_CAPACITY {
        testing.expect(t, interpreter_write(&interpreter, "x"))
    }
    testing.expect(t, interpreter_write(&interpreter, "discarded\aOK"))

    testing.expect_value(t, cell_text(&grid.cells[0]), "O")
    testing.expect_value(t, cell_text(&grid.cells[1]), "K")
    testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
    testing.expect_value(t, interpreter.overflow_sequence_count, u64(1))
}

// Verify Julia 1.12 TerminalMenus redraw controls replace rows in place.
@(test)
termgrid_test_interpreter_replays_terminal_menu_redraw :: proc(t: ^testing.T) {
    grid, chunked_grid: termgrid.Grid
    interpreter, chunked: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 10, 3) {
        return
    }
    defer termgrid.grid_destroy(&grid)
    if !test_interpreter_init(t, &chunked_grid, &chunked, 10, 3) {
        return
    }
    defer termgrid.grid_destroy(&chunked_grid)

    initial := "\e[2K > one\r\n\e[2K   two\e[?25l"
    redraw := "\r\e[1A\e[2K   one\r\n\e[2K > two\e[?25h\n"
    testing.expect(t, interpreter_write(&interpreter, initial))
    testing.expect(t, !interpreter.cursor_visible)
    testing.expect(t, interpreter_write(&interpreter, redraw))
    fixtures := [2]string{initial, redraw}
    for fixture in fixtures {
        for byte in transmute([]u8)fixture {
            part := [1]u8{byte}
            testing.expect(t,
                interpreter_write(&chunked, transmute(string)part[:]))
        }
    }

    test_expect_interpreters_equal(t, &interpreter, &chunked)
    testing.expect(t, interpreter.cursor_visible)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(0))
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(0))
    testing.expect_value(t, interpreter.overflow_sequence_count, u64(0))
    testing.expect_value(t, grid.cursor, termgrid.Cursor{row = 2, column = 6})
    testing.expect_value(t, cell_text(&grid.rows[0].cells[1]), " ")
    testing.expect_value(t, cell_text(&grid.rows[0].cells[3]), "o")
    testing.expect_value(t, cell_text(&grid.rows[1].cells[1]), ">")
    testing.expect_value(t, cell_text(&grid.rows[1].cells[3]), "t")
}

// Verify bounded cursor movement, save/restore, and erase modes.
@(test)
termgrid_test_interpreter_cursor_and_erasure :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 6, 3) {
        return
    }
    defer termgrid.grid_destroy(&grid)

    testing.expect(t, interpreter_write(&interpreter,
        "abcdef\r\n123456\e[1;3H\e[s\e[2KX\e[uY"))

    testing.expect_value(t, grid.cursor, termgrid.Cursor{row = 0, column = 3})
    testing.expect_value(t, cell_text(&grid.rows[0].cells[0]), "")
    testing.expect_value(t, cell_text(&grid.rows[0].cells[2]), "Y")
    testing.expect_value(t, cell_text(&grid.rows[1].cells[0]), "1")
    testing.expect_value(t, cell_text(&grid.rows[1].cells[5]), "6")

    testing.expect(t,
        interpreter_write(&interpreter, "\e[2;6f\e[1A\e[2B\e[2C\e[3D"))
    testing.expect_value(t, grid.cursor, termgrid.Cursor{row = 2, column = 2})
    testing.expect(t, interpreter_write(&interpreter, "\e[2J"))
    for &cell in grid.cells {
        testing.expect_value(t, cell_text(&cell), "")
    }
}

// Verify margins, origin, indexing, and line/region edits share bounded row movement.
@(test)
termgrid_test_interpreter_applies_margin_and_region_editing :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 6, 5) {
        return
    }
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_write(&interpreter,
        "111111\r\n222222\r\n333333\r\n444444\r\n555555"))
    grid.rows[2].shell_markers.present[.Prompt] = true
    testing.expect(t, interpreter_write(
        &interpreter, "\e[2;4r\e[?6h\e[1;1H\eD"))
    testing.expect_value(t, grid.cursor.row, 2)
    testing.expect(t, interpreter_write(&interpreter, "\eM"))
    testing.expect_value(t, grid.cursor.row, 1)
    testing.expect(t, grid.rows[2].shell_markers.present[.Prompt])
    testing.expect(t, interpreter_write(&interpreter, "\e[2L\e[1M\e[1S\e[1T"))
    testing.expect_value(t, grid.editing.scroll_top, 1)
    testing.expect_value(t, grid.editing.scroll_bottom, 3)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(0))
    testing.expect(t, interpreter_write(&interpreter, "\e[0;0r"))
    testing.expect_value(t, grid.editing.scroll_top, 0)
    testing.expect_value(t, grid.editing.scroll_bottom, grid.row_count - 1)
    testing.expect_value(t, grid.cursor, termgrid.Cursor{})
}

// Verify character edits, tabs, insert mode, and autowrap dispatch exact semantics.
@(test)
termgrid_test_interpreter_applies_character_and_tab_editing :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 12, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_write(&interpreter,
        "abcdef\e[1;3H\e[2@XY\e[1P\e[2X"))
    testing.expect_value(t, cell_text(&grid.rows[0].cells[2]), "X")
    testing.expect_value(t, cell_text(&grid.rows[0].cells[3]), "Y")
    testing.expect(t, interpreter_write(&interpreter,
        "\e[3g\e[1;5H\eH\e[1;1H\e[I\e[Z"))
    testing.expect_value(t, grid.cursor.column, 0)
    testing.expect(t, interpreter_write(&interpreter,
        "\e[4h\e[1;1H12\e[4l\e[?7l\e[1;12HAB"))
    testing.expect(t, !grid.editing.insert_mode && !grid.editing.autowrap_mode)
    testing.expect_value(t, cell_text(&grid.rows[0].cells[11]), "B")
}

// Verify DECSCA selective erase and DEC save/restore preserve documented state.
@(test)
termgrid_test_interpreter_selective_erase_and_dec_restore :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 8, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_write(&interpreter,
        "\e[1\"qSAFE\e[0\"qopen\e[1;1H\e[?2K"))
    testing.expect_value(t, cell_text(&grid.rows[0].cells[0]), "S")
    testing.expect_value(t, cell_text(&grid.rows[0].cells[4]), "")
    testing.expect(t, interpreter_write(&interpreter,
        "\e[2;1H\e[1\"q界\e[0\"qopen\e[2;1H\e[?2K"))
    testing.expect_value(t, cell_text(&grid.rows[1].cells[0]), "界")
    testing.expect(t, grid.rows[1].cells[1].continuation)
    testing.expect_value(t, cell_text(&grid.rows[1].cells[2]), "")
    testing.expect(t, interpreter_write(&interpreter,
        "\e[31m\e[?6h\e[?7l\e7\e[0m\e[?6l\e[?7h\e8"))
    testing.expect_value(t, grid.style.foreground, TERMINAL_COLOR_INDEXED(1))
    testing.expect(t,
        grid.editing.origin_mode && !grid.editing.autowrap_mode)
    testing.expect(t, interpreter_write(&interpreter, "\e[?1048h\e[0m\e[?1048l"))
    testing.expect_value(t, grid.style.foreground, TERMINAL_COLOR_INDEXED(1))
}

// Verify alternate-screen output is ephemeral and restores exact primary state.
@(test)
termgrid_test_interpreter_alternate_screen_restores_primary :: proc(t: ^testing.T) {
    history: Emulator_Scrollback_Test_State
    primary, alternate: termgrid.Grid
    sink := termgrid.Scrollback_Sink{
        user_data = &history,
        commit = emulator_test_scrollback_commit,
    }
    testing.expect(t, termgrid.grid_init(
        &primary, 6, 2, context.allocator, {scrollback = sink}))
    defer termgrid.grid_destroy(&primary)
    testing.expect(t, termgrid.grid_init(
        &alternate, 6, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&alternate)
    interpreter: Interpreter
    testing.expect(t, interpreter_init(
        &interpreter, &primary, {alternate_grid = &alternate}))

    testing.expect(t, interpreter_write(
        &interpreter, "first\r\nsecond\e[1;3H\e[s\e[?25l"))
    expected_cells := make([]Cell, len(primary.cells), context.temp_allocator)
    copy(expected_cells, primary.cells)
    expected_cursor := primary.cursor
    expected_saved_cursor := interpreter.saved_cursor
    expected_history_count := history.count

    testing.expect(t, interpreter_write(
        &interpreter, "\e[?1049h\e[?1049hALT-1\r\nALT-2\r\nALT-3"))
    testing.expect(t, interpreter.alternate_screen_active)
    testing.expect_value(t, history.count, expected_history_count)
    testing.expect_value(t, cell_text(&primary.cells[0]), "A")

    testing.expect(t, interpreter_write(&interpreter, "\e[?1049l\e[?1049l"))
    testing.expect(t, !interpreter.alternate_screen_active)
    testing.expect_value(t, primary.cursor, expected_cursor)
    testing.expect_value(t, interpreter.saved_cursor, expected_saved_cursor)
    testing.expect(t, !interpreter.cursor_visible)
    testing.expect_value(t, history.count, expected_history_count)
    termgrid_test_expect_cells(t, &primary, expected_cells)
}

// Verify alternate transitions preserve primary and discard alternate placements.
@(test)
termgrid_test_interpreter_alternate_screen_isolates_placements :: proc(t: ^testing.T) {
    store: termattachment.Store
    testing.expect(t, emulator_test_attachment_store_init(&store))
    defer termattachment.store_destroy(&store)
    primary, alternate: termgrid.Grid
    testing.expect(t, termgrid.grid_init(&primary, 4, 2, context.allocator, {
        attachment_store = &store,
        screen = .Primary,
    }))
    defer termgrid.grid_destroy(&primary)
    testing.expect(t, termgrid.grid_init(&alternate, 4, 2, context.allocator, {
        attachment_store = &store,
        screen = .Alternate,
    }))
    defer termgrid.grid_destroy(&alternate)
    primary_attachment, primary_outcome := emulator_test_attachment_place(
        &store, primary.rows[0].logical_id)
    testing.expect_value(t,
        primary_outcome, termattachment.Admission_Outcome.Admitted)
    alternate_attachment, alternate_outcome := emulator_test_attachment_place(
        &store, alternate.rows[0].logical_id, .Alternate)
    testing.expect_value(t,
        alternate_outcome, termattachment.Admission_Outcome.Admitted)
    alternate_entry, _ := termattachment.attachment_entry(
        &store, alternate_attachment)
    interpreter: Interpreter
    testing.expect(t, interpreter_init(
        &interpreter, &primary, {alternate_grid = &alternate}))

    testing.expect(t, interpreter_write(&interpreter, "\e[?1049h"))

    testing.expect_value(t, store.placement_count, 1)
    primary_entry, _ := termattachment.attachment_entry(&store, primary_attachment)
    testing.expect_value(t, primary_entry.placement_reference_count, 1)
    testing.expect_value(t, alternate_entry.placement_reference_count, 0)
    termgrid_test_leave_alternate_with_placement(
        t, &interpreter, &store, primary_attachment, alternate_attachment)
}

// Verify chunked, repeated, and malformed DEC transitions remain deterministic.
@(test)
termgrid_test_interpreter_alternate_transitions_are_bounded :: proc(t: ^testing.T) {
    primary, alternate: termgrid.Grid
    testing.expect(t, termgrid.grid_init(
        &primary, 4, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&primary)
    testing.expect(t, termgrid.grid_init(
        &alternate, 4, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&alternate)
    interpreter: Interpreter
    testing.expect(t, interpreter_init(
        &interpreter, &primary, {alternate_grid = &alternate}))

    testing.expect(t, interpreter_write(&interpreter, "\e[?2004;1049;25h"))
    testing.expect(t, interpreter.alternate_screen_active)
    testing.expect(t, interpreter.cursor_visible)
    testing.expect(t, interpreter.input_mode.bracketed_paste)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(0))

    enter_sequence: string = "\e[?1049h"
    for byte in transmute([]u8)enter_sequence {
        part := [1]u8{byte}
        testing.expect(t,
            interpreter_write(&interpreter, transmute(string)part[:]))
    }
    testing.expect(t, interpreter.alternate_screen_active)
    testing.expect(t, interpreter_write(&interpreter, "\e[?1049hX"))
    testing.expect_value(t, cell_text(&primary.cells[0]), "X")
    testing.expect(t, interpreter_write(&interpreter, "\e[?1049l\e[?1049l"))
    testing.expect(t, !interpreter.alternate_screen_active)
    testing.expect(t, interpreter.input_mode.bracketed_paste)
}

// Return the complete expected terminal input mode fixture.
termgrid_test_expected_input_mode :: proc() -> Terminal_Input_Mode {
    return {
        cursor_keys_application = true,
        keypad_application = true,
        bracketed_paste = true,
        focus_reporting = true,
        mouse_tracking = .Button_Motion,
        mouse_sgr_encoding = true,
        mouse_pixel_coordinates = true,
    }
}

// Verify terminal keyboard modes are chunk-independent, repeatable, and resettable.
@(test)
termgrid_test_interpreter_tracks_input_modes :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 4, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)

    fixture := "\e[?1;1000;1002;1004;1006;1016;2004h\e="
    for byte in transmute([]u8)fixture {
        part := [1]u8{byte}
        testing.expect(t,
            interpreter_write(&interpreter, transmute(string)part[:]))
    }
    testing.expect_value(t, interpreter_input_mode(&interpreter),
        termgrid_test_expected_input_mode())

    testing.expect(t, interpreter_write(
        &interpreter, "\e[?1h\e=\e[?1l\e>\e[?1002;1004;1006;1016;2004l"))
    testing.expect_value(t, interpreter_input_mode(&interpreter), Terminal_Input_Mode{})
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(0))

    testing.expect(t, interpreter_write(&interpreter, "\e[?1;9999;2004h"))
    testing.expect(t, interpreter.input_mode.cursor_keys_application)
    testing.expect(t, interpreter.input_mode.bracketed_paste)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(1))
    testing.expect(t, interpreter_write(&interpreter, "\e[?1;2004l"))

    testing.expect(t, interpreter_write(&interpreter, "\e[?1h\e[?2004h\e"))
    interpreter_finish_input(&interpreter)
    testing.expect_value(t, interpreter.input_mode, Terminal_Input_Mode{})
    testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(1))
}

// Verify exact modifyOtherKeys mutations, query correlation, and finalization reset.
@(test)
termgrid_test_interpreter_tracks_modify_other_keys :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    testing.expect(t, termgrid.grid_init(&grid, 4, 2, allocator = context.allocator))
    if !testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &retained})) {
        termgrid.grid_destroy(&grid)
        return
    }
    defer termgrid.grid_destroy(&grid)
    producer := Terminal_Producer{.Terminal_Session, 7, 9}

    testing.expect(t, interpreter_write(&interpreter, "\e[>4;1m"))
    testing.expect_value(t, interpreter_modify_other_keys_level(&interpreter), u8(1))
    testing.expect(t, interpreter_write(&interpreter, "\e[>4;2m"))
    testing.expect_value(t, interpreter_modify_other_keys_level(&interpreter), u8(2))
    testing.expect(t, interpreter_write(&interpreter, "\e[?4m", producer))
    response, present := interpreter_peek_response(&interpreter)
    testing.expect(t, present)
    testing.expect_value(t, response, Terminal_Response{
        kind = .Modify_Other_Keys, first = 2, producer = producer,
    })
    testing.expect(t, interpreter_pop_response(&interpreter))

    testing.expect(t, interpreter_write(&interpreter, "\e[>4;0m"))
    testing.expect_value(t, interpreter_modify_other_keys_level(&interpreter), u8(0))
    testing.expect(t, interpreter_write(&interpreter, "\e[>4;2m\e[>4m"))
    testing.expect_value(t, interpreter_modify_other_keys_level(&interpreter), u8(0))
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(0))
    testing.expect(t, interpreter_write(&interpreter, "\e[>4;1m\e[?4m", producer))
    testing.expect_value(t, interpreter_modify_other_keys_level(&interpreter), u8(1))
    testing.expect_value(t, retained.response_count, 1)
    interpreter_finish_input(&interpreter)
    testing.expect_value(t, interpreter.input_mode, Terminal_Input_Mode{})
    testing.expect_value(t, interpreter_modify_other_keys_level(&interpreter), u8(0))
    testing.expect_value(t, retained.response_count, 0)
}

// Verify a different producer cannot complete an in-flight control sequence.
@(test)
termgrid_test_interpreter_rejects_cross_producer_sequences :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    testing.expect(t, termgrid.grid_init(&grid, 4, 2, allocator = context.allocator))
    if !testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &retained})) {
        termgrid.grid_destroy(&grid)
        return
    }
    defer termgrid.grid_destroy(&grid)
    first := Terminal_Producer{
        kind = .Terminal_Session, id = 1, generation = 3,
    }
    second := Terminal_Producer{
        kind = .Terminal_Session, id = 1, generation = 4,
    }

    testing.expect(t, interpreter_write(&interpreter, "\e[?", first))
    testing.expect(t, interpreter_write(&interpreter, "4m", second))
    testing.expect_value(t, retained.response_count, 0)
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(1))
}

// Verify malformed resources and levels do not mutate or enqueue replies.
@(test)
termgrid_test_interpreter_rejects_modify_other_keys_extensions :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    testing.expect(t, termgrid.grid_init(&grid, 4, 2, allocator = context.allocator))
    if !testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &retained})) {
        termgrid.grid_destroy(&grid)
        return
    }
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_write(&interpreter, "\e[>4;1m"))
    fixtures := [?]string{
        "\e[>5;2m", "\e[>4;3m", "\e[>4;m", "\e[>4;1;2m", "\e[?5m",
    }
    for fixture in fixtures {
        testing.expect(t, interpreter_write(&interpreter, fixture))
    }
    testing.expect_value(t, interpreter_modify_other_keys_level(&interpreter), u8(1))
    testing.expect_value(t, retained.response_count, 0)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(len(fixtures)))
}

// Verify Kitty flags 1-16 replace, set, clear, and query independently.
@(test)
termgrid_test_interpreter_negotiates_kitty_keyboard :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    testing.expect(t, termgrid.grid_init(&grid, 4, 2, allocator = context.allocator))
    if !testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &retained})) {
        termgrid.grid_destroy(&grid)
        return
    }
    defer termgrid.grid_destroy(&grid)
    producer := Terminal_Producer{.Terminal_Session, 3, 5}

    testing.expect(t, interpreter_write(&interpreter, "\e[=31u"))
    testing.expect_value(t, interpreter_kitty_keyboard_flags(&interpreter), u8(31))
    testing.expect(t, interpreter_write(&interpreter, "\e[=0;2u"))
    testing.expect_value(t, interpreter_kitty_keyboard_flags(&interpreter), u8(31))
    testing.expect(t, interpreter_write(&interpreter, "\e[=1;3u"))
    testing.expect_value(t, interpreter_kitty_keyboard_flags(&interpreter), u8(30))
    testing.expect(t, interpreter_write(&interpreter, "\e[?u", producer))
    response, present := interpreter_peek_response(&interpreter)
    testing.expect(t, present)
    testing.expect_value(t, response, Terminal_Response{
        kind = .Kitty_Keyboard, first = 30, producer = producer,
    })
}

// Verify the frozen push/pop fixture preserves flags 1 and 16 exactly.
@(test)
termgrid_test_interpreter_stacks_complete_kitty_flags :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    testing.expect(t, termgrid.grid_init(&grid, 4, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &retained}))

    testing.expect(t, interpreter_write(&interpreter, "\e[>17u"))
    testing.expect_value(t, interpreter_kitty_keyboard_flags(&interpreter), u8(17))
    testing.expect(t, interpreter_write(&interpreter, "\e[=31u\e[<u"))
    testing.expect_value(t, interpreter_kitty_keyboard_flags(&interpreter), u8(0))
}

// Verify Kitty status and minimal DA1 replies retain detection order and producer.
@(test)
termgrid_test_interpreter_queues_kitty_detection_responses :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    testing.expect(t, termgrid.grid_init(&grid, 4, 2, allocator = context.allocator))
    if !testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &retained})) {
        termgrid.grid_destroy(&grid)
        return
    }
    defer termgrid.grid_destroy(&grid)
    producer := Terminal_Producer{.Terminal_Session, 8, 13}

    testing.expect(t, interpreter_write(&interpreter, "\e[?u\e[c", producer))
    first, present := interpreter_peek_response(&interpreter)
    testing.expect(t, present)
    testing.expect_value(t, first, Terminal_Response{
        kind = .Kitty_Keyboard, producer = producer,
    })
    testing.expect(t, interpreter_pop_response(&interpreter))
    second: Terminal_Response
    second, present = interpreter_peek_response(&interpreter)
    testing.expect(t, present)
    testing.expect_value(t, second, Terminal_Response{
        kind = .Primary_Device_Attributes, producer = producer,
    })
}

// Verify malformed Kitty forms are unsupported and cannot mutate accepted state.
@(test)
termgrid_test_interpreter_rejects_kitty_keyboard_extensions :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    testing.expect(t, termgrid.grid_init(&grid, 4, 2, allocator = context.allocator))
    if !testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &retained})) {
        termgrid.grid_destroy(&grid)
        return
    }
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, interpreter_write(&interpreter, "\e[=1u"))
    fixtures := [?]string{
        "\e[=u", "\e[=1;0u", "\e[=1;4u", "\e[=1;2;3u",
        "\e[=1:2u", "\e[>1;2u", "\e[>1:2u", "\e[<0u",
        "\e[<1;2u", "\e[<1:2u", "\e[?1u",
    }
    for fixture in fixtures {
        testing.expect(t, interpreter_write(&interpreter, fixture))
    }
    testing.expect_value(t, interpreter_kitty_keyboard_flags(&interpreter), u8(1))
    testing.expect_value(t, retained.primary_kitty.stack_count, 0)
    testing.expect_value(t, retained.response_count, 0)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(len(fixtures)))
}

// Verify Kitty push/pop bounds and independent primary and alternate state.
@(test)
termgrid_test_interpreter_scopes_kitty_keyboard_to_screen :: proc(t: ^testing.T) {
    grid, alternate: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    testing.expect(t, termgrid.grid_init(&grid, 4, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, termgrid.grid_init(&alternate, 4, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&alternate)
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {
            alternate_grid = &alternate,
            title_state = &retained,
        }))

    testing.expect(t, interpreter_write(
        &interpreter, "\e[=0u\e[>3u\e[>u\e[<u"))
    testing.expect_value(t, interpreter_kitty_keyboard_flags(&interpreter), u8(3))
    testing.expect(t, interpreter_write(&interpreter, "\e[?1049h\e[=0u"))
    testing.expect_value(t, interpreter_kitty_keyboard_flags(&interpreter), u8(0))
    testing.expect(t, interpreter_write(&interpreter, "\e[>1u"))
    testing.expect(t, interpreter_write(&interpreter, "\e[?1049l"))
    testing.expect_value(t, interpreter_kitty_keyboard_flags(&interpreter), u8(3))

    for _ in 0..<KITTY_KEYBOARD_STACK_CAPACITY + 2 {
        testing.expect(t, interpreter_write(&interpreter, "\e[>1u"))
    }
    testing.expect_value(t, retained.primary_kitty.stack_count,
        KITTY_KEYBOARD_STACK_CAPACITY)
    testing.expect(t, interpreter_write(&interpreter, "\e[<99u"))
    testing.expect_value(t, retained.primary_kitty, Kitty_Keyboard_State{})
    interpreter_finish_input(&interpreter)
    testing.expect_value(t, retained.alternate_kitty, Kitty_Keyboard_State{})
}

// Verify combined mouse tracking modes apply left-to-right and reset selectively.
@(test)
termgrid_test_interpreter_mouse_mode_ordering :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 4, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)

    testing.expect(t, interpreter_write(&interpreter, "\e[?1002;1003;1000h"))
    testing.expect_value(t, interpreter.input_mode.mouse_tracking,
        Terminal_Mouse_Tracking_Mode.Button)
    testing.expect(t, interpreter_write(&interpreter, "\e[?1000;1002;1003h"))
    testing.expect_value(t, interpreter.input_mode.mouse_tracking,
        Terminal_Mouse_Tracking_Mode.Any_Motion)
    testing.expect(t, interpreter_write(&interpreter, "\e[?1000;1002h"))
    testing.expect_value(t, interpreter.input_mode.mouse_tracking,
        Terminal_Mouse_Tracking_Mode.Button_Motion)
    testing.expect(t, interpreter_write(&interpreter, "\e[?1000;1003l"))
    testing.expect_value(t, interpreter.input_mode.mouse_tracking,
        Terminal_Mouse_Tracking_Mode.Button_Motion)
    testing.expect(t, interpreter_write(&interpreter, "\e[?1002l"))
    testing.expect_value(t, interpreter.input_mode.mouse_tracking,
        Terminal_Mouse_Tracking_Mode.None)
    testing.expect(t, interpreter_write(&interpreter, "\e[?1003h"))
    interpreter_finish_input(&interpreter)
    testing.expect_value(t, interpreter.input_mode.mouse_tracking,
        Terminal_Mouse_Tracking_Mode.None)
}

// Verify rejected and overlong CSI input cannot leak bytes or wedge parsing.
@(test)
termgrid_test_interpreter_recovers_from_bounded_failures :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 12, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)

    testing.expect(t, interpreter_write(&interpreter, "\e[9qA"))
    testing.expect(t, interpreter_write(&interpreter, "\e[38m"))
    testing.expect(t, interpreter_write(&interpreter, "\e[12 X"))
    testing.expect(t, interpreter_write(&interpreter,
        "\e[999999999999999999999999999999AOK"))
    testing.expect(t, interpreter_write(&interpreter, "\e["))
    interpreter_finish_input(&interpreter)

    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(3))
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(1))
    testing.expect_value(t, interpreter.overflow_sequence_count, u64(1))
    testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
    testing.expect_value(t, cell_text(&grid.cells[0]), "A")
    testing.expect_value(t, cell_text(&grid.cells[1]), "O")
    testing.expect_value(t, cell_text(&grid.cells[2]), "K")
    testing.expect_value(t, cell_text(&grid.cells[3]), "")
}

// Verify valid grammar extensions remain unsupported without becoming malformed.
@(test)
termgrid_test_interpreter_classifies_valid_unsupported_grammar :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 12, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)

    testing.expect(t, interpreter_write(
        &interpreter, "AB\e[2\b\x7fCX\e(\aBA\e[1 qB\e[1:2mC"))

    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(3))
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(0))
    testing.expect_value(t, cell_text(&grid.cells[3]), "X")
    testing.expect_value(t, cell_text(&grid.cells[4]), "A")
    testing.expect_value(t, cell_text(&grid.cells[5]), "B")
    testing.expect_value(t, cell_text(&grid.cells[6]), "C")
}

// Verify every CSI private prefix is retained transactionally and dispatched by kind.
@(test)
termgrid_test_interpreter_tracks_csi_private_prefixes :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 12, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)

    fixtures := [4]string{"\e[<1m", "\e[=1m", "\e[>1m", "\e[?1003h"}
    for fixture in fixtures {
        for byte in transmute([]u8)fixture {
            part := [1]u8{byte}
            testing.expect(t,
                interpreter_write(&interpreter, transmute(string)part[:]))
        }
        testing.expect_value(t, interpreter.csi_private_marker,
            Csi_Private_Marker.None)
        testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
    }
    testing.expect_value(t, interpreter.input_mode.mouse_tracking,
        Terminal_Mouse_Tracking_Mode.Any_Motion)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(3))
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(0))
}

// Verify duplicate and misplaced private markers recover as unsupported sequences.
@(test)
termgrid_test_interpreter_rejects_misplaced_csi_private_prefixes :: proc(
    t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 12, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)

    fixtures := [5]string{
        "\e[??1h", "\e[?>1h", "\e[1?m", "\e[;>m", "\e[1 <m",
    }
    for fixture in fixtures {
        testing.expect(t, interpreter_write(&interpreter, fixture))
    }
    prefixes := [4]u8{'<', '=', '>', '?'}
    cancellations := [4]u8{0x18, 0x1a, 0x18, 0x1a}
    for prefix, index in prefixes {
        sequence := [3]u8{0x1b, '[', prefix}
        testing.expect(t,
            interpreter_write(&interpreter, transmute(string)sequence[:]))
        testing.expect(t, interpreter.csi_private_marker != .None)
        cancelled := [1]u8{cancellations[index]}
        testing.expect(t,
            interpreter_write(&interpreter, transmute(string)cancelled[:]))
        testing.expect_value(t, interpreter.csi_private_marker,
            Csi_Private_Marker.None)
    }
    testing.expect(t, interpreter_write(&interpreter, "\e[>99999"))
    testing.expect_value(t, interpreter.state, Interpreter_State.Csi_Discard)
    testing.expect(t, interpreter_write(&interpreter, "m"))
    testing.expect_value(t, interpreter.csi_private_marker,
        Csi_Private_Marker.None)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(5))
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(0))
    testing.expect_value(t, interpreter.cancelled_sequence_count, u64(4))
    testing.expect_value(t, interpreter.overflow_sequence_count, u64(1))
}

// Verify supported reports and unsupported modes stay synchronized and silent.
@(test)
termgrid_test_interpreter_consumes_unadvertised_queries_and_modes :: proc(
    t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 8, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)

    fixtures := [4]string{"\e[1c", "\e[5n", "\e[6n", "\e[?2h"}
    for fixture in fixtures {
        for byte in transmute([]u8)fixture {
            part := [1]u8{byte}
            testing.expect(t,
                interpreter_write(&interpreter, transmute(string)part[:]))
        }
    }
    testing.expect(t, interpreter_write(&interpreter, "OK"))

    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(2))
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(0))
    testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
    testing.expect_value(t, cell_text(&grid.cells[0]), "O")
    testing.expect_value(t, cell_text(&grid.cells[1]), "K")
}

// Verify identity, status, cursor, and geometry queries capture exact responses.
@(test)
termgrid_test_interpreter_captures_query_responses :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    if !termgrid_test_init_query_interpreter(
        t, &grid, &interpreter, &retained) {
        return
    }
    defer termgrid.grid_destroy(&grid)
    producer := Terminal_Producer{.Terminal_Session, 11, 17}
    fixtures := [?]Terminal_Query_Fixture{
        {"\e[c", {kind = .Primary_Device_Attributes, producer = producer}},
        {"\e[>c", {kind = .Secondary_Device_Attributes, producer = producer}},
        {"\e[5n", {kind = .Device_Status, producer = producer}},
        {"\e[2;3H\e[6n", {
            kind = .Cursor_Position, first = 2, second = 3, producer = producer,
        }},
        {"\e[14t", {
            kind = .Window_Pixels, first = 480, second = 640,
            producer = producer,
        }},
        {"\e[16t", {
            kind = .Cell_Pixels, first = 16, second = 8, producer = producer,
        }},
        {"\e[18t", {
            kind = .Text_Area_Size, first = 2, second = 8, producer = producer,
        }},
    }
    for fixture in fixtures {
        termgrid_test_expect_query_fixture(
            t, &interpreter, fixture, producer)
    }
    testing.expect(t, interpreter_write(&interpreter, "\e[H"))
    testing.expect_value(t, retained.response_count, 0)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(0))
}

// Verify mode and keyboard queries capture exact state and producer identity.
@(test)
termgrid_test_interpreter_captures_mode_query_responses :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    if !termgrid_test_init_query_interpreter(
        t, &grid, &interpreter, &retained) { return }
    defer termgrid.grid_destroy(&grid)
    producer := Terminal_Producer{.Terminal_Session, 11, 17}
    testing.expect(t, interpreter_write(&interpreter, "\e[>4;2m\e[=3u"))
    fixtures := [?]Terminal_Query_Fixture{
        {"\e[?25l\e[?25$p", {kind = .Private_Mode_Status,
            first = 25, second = 2, producer = producer}},
        {"\e[?6h\e[?6$p", {kind = .Private_Mode_Status,
            first = 6, second = 1, producer = producer}},
        {"\e[?7l\e[?7$p", {kind = .Private_Mode_Status,
            first = 7, second = 2, producer = producer}},
        {"\e[?1048h\e[?1048$p", {kind = .Private_Mode_Status,
            first = 1048, second = 1, producer = producer}},
        {"\e[?2004h\e[?2004$p", {kind = .Private_Mode_Status,
            first = 2004, second = 1, producer = producer}},
        {"\e[?1016h\e[?1016$p", {kind = .Private_Mode_Status,
            first = 1016, second = 1, producer = producer}},
        {"\e[?999$p", {kind = .Private_Mode_Status,
            first = 999, producer = producer}},
        {"\e[?4m", {kind = .Modify_Other_Keys,
            first = 2, producer = producer}},
        {"\e[?u", {kind = .Kitty_Keyboard,
            first = 3, producer = producer}},
    }
    for fixture in fixtures {
        termgrid_test_expect_query_fixture(
            t, &interpreter, fixture, producer)
    }
    testing.expect_value(t, retained.response_count, 0)
}

// Verify unsupported intermediate CSI forms cannot invoke ordinary commands.
@(test)
termgrid_test_interpreter_rejects_query_intermediate_extensions :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    retained: Terminal_Title_State
    testing.expect(t, termgrid.grid_init(&grid, 8, 2, allocator = context.allocator))
    if !testing.expect(t, interpreter_init(
        &interpreter, &grid, {title_state = &retained})) {
        termgrid.grid_destroy(&grid)
        return
    }
    defer termgrid.grid_destroy(&grid)

    fixtures := [?]string{"\e[1$m", "\e[?25 p", "\e[?25$$p", "\e[?25$z"}
    for fixture in fixtures {
        testing.expect(t, interpreter_write(&interpreter, fixture))
    }

    testing.expect_value(t, retained.response_count, 0)
    testing.expect_value(t, interpreter.unsupported_sequence_count, u64(len(fixtures)))
    testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
}

// Verify mode 2026 captures once and publishes without rolling back live state.
@(test)
termgrid_test_interpreter_synchronized_output_transaction :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    scrollback: termgrid.Scrollback
    output_started := true
    testing.expect(t, termgrid.scrollback_init(
        &scrollback, 8, 4, context.allocator))
    defer termgrid.scrollback_destroy(&scrollback)
    testing.expect(t, termgrid.grid_init(
        &grid, 8, 2, context.allocator, {scrollback = {
            user_data = &scrollback,
            commit = termgrid.scrollback_sink_commit,
        }}))
    defer termgrid.grid_destroy(&grid)
    synchronized := Synchronized_Output_State{
        scrollback = &scrollback,
        output_started = &output_started,
    }
    testing.expect(t, termgrid.display_checkpoint_init(
        &synchronized.checkpoint, &grid, &scrollback, context.allocator))
    defer termgrid.display_checkpoint_destroy(&synchronized.checkpoint)
    retained: Terminal_Title_State
    interpreter: Interpreter
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {
            title_state = &retained,
            synchronized_output = &synchronized,
        }))
    termgrid_test_expect_synchronized_transaction(
        t, &interpreter, &synchronized, &grid)
}

// Verify synchronized output keeps replies live and forces lifecycle publication.
@(test)
termgrid_test_interpreter_synchronized_output_lifecycle_boundaries :: proc(
    t: ^testing.T) {
    grid: termgrid.Grid
    alternate: termgrid.Grid
    scrollback: termgrid.Scrollback
    synchronized: Synchronized_Output_State
    output_started := true
    testing.expect(t, termgrid.scrollback_init(&scrollback, 8, 4, context.allocator))
    defer termgrid.scrollback_destroy(&scrollback)
    testing.expect(t, termgrid.grid_init(&grid, 8, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&grid)
    testing.expect(t, termgrid.grid_init(&alternate, 8, 2, allocator = context.allocator))
    defer termgrid.grid_destroy(&alternate)
    testing.expect(t, termgrid.display_checkpoint_init(
        &synchronized.checkpoint, &grid, &scrollback, context.allocator))
    defer termgrid.display_checkpoint_destroy(&synchronized.checkpoint)
    synchronized.scrollback = &scrollback
    synchronized.output_started = &output_started
    retained: Terminal_Title_State
    interpreter: Interpreter
    testing.expect(t, interpreter_init(
        &interpreter, &grid, {
            alternate_grid = &alternate,
            title_state = &retained,
            synchronized_output = &synchronized,
        }))
    termgrid_test_expect_synchronized_boundaries(
        t, &interpreter, &synchronized)
}

// Verify stream finalization classifies every incomplete parser family as malformed.
@(test)
termgrid_test_interpreter_finalizes_every_incomplete_family :: proc(t: ^testing.T) {
    prefixes := [?]string{"\e", "\e ", "\e[", "\e[1 ", "\e]x", "\e]\e"}
    states := [?]Interpreter_State{
        .Escape, .Escape_Intermediate, .Csi, .Csi_Intermediate,
        .Osc, .Osc_Escape,
    }
    for prefix, index in prefixes {
        grid: termgrid.Grid
        interpreter: Interpreter
        testing.expect(t, test_interpreter_init(
            t, &grid, &interpreter, 4, 1))
        testing.expect(t, interpreter_write(&interpreter, prefix))
        testing.expect_value(t, interpreter.state, states[index])
        interpreter_finish_input(&interpreter)
        testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
        testing.expect_value(t, interpreter.malformed_sequence_count, u64(1))
        termgrid.grid_destroy(&grid)
    }
}

// Verify CAN/SUB cancellation and ESC restart recover every parser family.
@(test)
termgrid_test_interpreter_cancels_and_restarts_sequences :: proc(t: ^testing.T) {
    grid: termgrid.Grid
    interpreter: Interpreter
    if !test_interpreter_init(t, &grid, &interpreter, 12, 2) {
        return
    }
    defer termgrid.grid_destroy(&grid)

    test_expect_interpreter_cancel(t, &interpreter, "\e", .Escape, 1)
    test_expect_interpreter_cancel(t, &interpreter, "\e ", .Escape_Intermediate, 2)
    test_expect_interpreter_cancel(t, &interpreter, "\e[", .Csi, 3)
    test_expect_interpreter_cancel(t, &interpreter, "\e[1 ", .Csi_Intermediate, 4)
    test_expect_interpreter_cancel(t, &interpreter, "\e]x", .Osc, 5)
    test_expect_interpreter_cancel(t, &interpreter, "\e]\e", .Osc_Escape, 6)
    testing.expect(t, interpreter_write(&interpreter, "\e[99999"))
    testing.expect_value(t, interpreter.state, Interpreter_State.Csi_Discard)
    testing.expect(t, interpreter_write(&interpreter, "\x1a"))
    testing.expect_value(t, interpreter.cancelled_sequence_count, u64(7))
    testing.expect(t, interpreter_write(&interpreter, "\e]"))
    for _ in 0..=OSC_SEQUENCE_BYTE_CAPACITY {
        testing.expect(t, interpreter_write(&interpreter, "x"))
    }
    testing.expect_value(t, interpreter.state, Interpreter_State.Osc_Discard)
    testing.expect(t, interpreter_write(&interpreter, "\e"))
    testing.expect_value(t, interpreter.state, Interpreter_State.Osc_Discard_Escape)
    testing.expect(t, interpreter_write(&interpreter, "\x18"))
    testing.expect_value(t, interpreter.cancelled_sequence_count, u64(8))
    testing.expect(t, interpreter_write(&interpreter, "\e[12\e[2CX"))
    testing.expect_value(t, cell_text(&grid.cells[2]), "X")
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(0))
}
