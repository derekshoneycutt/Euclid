#+test
package termemulator

import "core:testing"
import termattachment "../attachment"
import gfxprotocol "../graphics/protocol"
import gfxsemantics "../graphics/semantics"
import termgrid "../grid"

// Pointers comprising one retained graphics interpreter fixture.
Graphics_Test_Targets :: struct {
    store: ^termattachment.Store,
    graphics: ^gfxprotocol.Graphics_Parser_State,
    title: ^Terminal_Title_State,
    grid: ^termgrid.Grid,
    interpreter: ^Interpreter,
}

// Owners needed to write a graphics command and inspect resulting store counts.
Graphics_Test_Write_Targets :: struct {
    interpreter: ^Interpreter,
    store: ^termattachment.Store,
}

// Bounded resource and grid dimensions for one Sixel animation fixture.
Graphics_Test_Sixel_Config :: struct {
    attachment_capacity: int,
    dimension_limit: int,
    image_pixel_limit: int,
    byte_limit: int,
    row_count: int,
}

// Initialize one small attachment store for emulator graphics integration tests.
graphics_test_attachment_store_init :: proc(
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

// Initialize one interpreter with retained graphics framing and bounded transfers.
graphics_test_init :: proc(
    store: ^termattachment.Store, graphics: ^gfxprotocol.Graphics_Parser_State,
    title: ^Terminal_Title_State, grid: ^termgrid.Grid,
    interpreter: ^Interpreter) -> bool {
    if !graphics_test_attachment_store_init(store) ||
        !gfxprotocol.graphics_parser_init(graphics, store) {
        return false
    }
    title.graphics = graphics
    if !termgrid.grid_init(grid, 8, 2, allocator = context.allocator) {
        gfxprotocol.graphics_parser_destroy(graphics)
        termattachment.store_destroy(store)
        return false
    }
    return interpreter_init(interpreter, grid, {title_state = title})
}

// Initialize one graphics fixture with caller-selected attachment limits.
graphics_test_init_with_limits :: proc(
    targets: Graphics_Test_Targets, limits: termattachment.Limits,
    row_count := 2) -> bool {
    if !termattachment.store_init(targets.store, limits, context.allocator) ||
        !gfxprotocol.graphics_parser_init(targets.graphics, targets.store) {
        return false
    }
    targets.title.graphics = targets.graphics
    if !termgrid.grid_init(
        targets.grid, 8, row_count, allocator = context.allocator) {
        gfxprotocol.graphics_parser_destroy(targets.graphics)
        termattachment.store_destroy(targets.store)
        return false
    }
    return interpreter_init(
        targets.interpreter, targets.grid, {title_state = targets.title})
}

// Release one graphics framing fixture in transfer-before-store order.
graphics_test_destroy :: proc(
    store: ^termattachment.Store, graphics: ^gfxprotocol.Graphics_Parser_State,
    grid: ^termgrid.Grid) {
    termgrid.grid_destroy(grid)
    gfxprotocol.graphics_parser_destroy(graphics)
    termattachment.store_destroy(store)
}

// Take and verify one retained Kitty response status.
graphics_test_expect_kitty_status :: proc(
    t: ^testing.T, graphics: ^gfxprotocol.Graphics_Parser_State,
    expected: gfxprotocol.Kitty_Graphics_Response_Status) {
    response, present := gfxprotocol.graphics_parser_take_kitty_response(graphics)
    testing.expect(t, present)
    testing.expect_value(t, response.status, expected)
}

// Write one graphics command and assert resulting attachment and placement counts.
graphics_test_expect_write_counts :: proc(
    t: ^testing.T, targets: Graphics_Test_Write_Targets,
    sequence: string, attachment_count, placement_count: int) {
    testing.expect(t, interpreter_write(targets.interpreter, sequence))
    testing.expect_value(t, targets.store.attachment_count, attachment_count)
    testing.expect_value(t, targets.store.placement_count, placement_count)
}

// Return the bounded resource policy shared by small Kitty animation tests.
graphics_test_kitty_animation_limits :: proc() -> termattachment.Limits {
    limits := termattachment.limits_default()
    limits.attachment_capacity = 2
    limits.placement_capacity = 4
    limits.transfer_capacity = 2
    limits.transfer_byte_limit = 16
    limits.dimension_limit = 4
    limits.image_pixel_limit = 16
    limits.cpu_byte_limit = 128
    limits.gpu_byte_limit = 16
    limits.animated_attachment_limit = 2
    limits.animation_frame_limit = 4
    limits.animation_decode_byte_limit = 64
    return limits
}

// Write one Kitty command and verify its synchronous response status.
graphics_test_write_kitty_status :: proc(
    t: ^testing.T, targets: Graphics_Test_Targets, command: string,
    producer: Terminal_Producer,
    expected: gfxprotocol.Kitty_Graphics_Response_Status) {
    testing.expect(t, interpreter_write(targets.interpreter, command, producer))
    graphics_test_expect_kitty_status(t, targets.graphics, expected)
}

// Return the larger bounded policy needed by the iTerm2 animation sequence.
graphics_test_iterm2_animation_limits :: proc() -> termattachment.Limits {
    return {
        attachment_capacity = 5, placement_capacity = 5, transfer_capacity = 5,
        transfer_byte_limit = 512, dimension_limit = 64,
        image_pixel_limit = 4096, cpu_byte_limit = 4096,
        gpu_byte_limit = 4096, animated_attachment_limit = 2,
        animation_frame_limit = 4, animation_decode_byte_limit = 4096,
        animation_min_frame_duration_ns = 1_000_000,
        animation_max_frame_duration_ns = 100_000_000,
        animation_duration_ns_limit = 1_000_000_000,
    }
}

// Verify and release the original iTerm2 decode request.
graphics_test_expect_iterm2_original :: proc(
    t: ^testing.T, interpreter: ^Interpreter,
    graphics: ^gfxprotocol.Graphics_Parser_State,
    store: ^termattachment.Store, producer: Terminal_Producer) {
    testing.expect(t, interpreter_write(interpreter,
        "\e]1337;File=name=x;inline=1;size=68;width=2;height=3px;preserveAspectRatio=0:iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=\a",
        producer))
    request, available := gfxprotocol.graphics_parser_take_decode_request(graphics)
    testing.expect(t, available)
    testing.expect_value(t, request.kind, gfxprotocol.Graphics_Decode_Kind.Iterm2_Image)
    testing.expect_value(t, request.declared_byte_count, 68)
    testing.expect_value(t, request.geometry.column_span, 2)
    testing.expect_value(t, request.geometry.pixel_height, 3)
    testing.expect(t, !request.preserve_aspect_ratio)
    termattachment.transfer_remove(store, request.transfer_id)
    gfxprotocol.graphics_discard_pending_attachment(graphics, request.attachment_id)
}

// Verify pixel-sized iTerm2 placement leaves the cursor on its final occupied row.
@(test)
graphics_test_iterm2_pixel_height_advances_cursor :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    limits := termattachment.Limits{
        attachment_capacity = 2,
        placement_capacity = 4,
        transfer_capacity = 2,
        transfer_byte_limit = 512,
        dimension_limit = 64,
        image_pixel_limit = 4096,
        cpu_byte_limit = 4096,
        gpu_byte_limit = 4096,
        animated_attachment_limit = 2,
        animation_frame_limit = 4,
        animation_decode_byte_limit = 4096,
        animation_min_frame_duration_ns = 1_000_000,
        animation_max_frame_duration_ns = 100_000_000,
        animation_duration_ns_limit = 1_000_000_000,
    }
    testing.expect(t, graphics_test_init_with_limits({
        store = &store, graphics = &graphics, title = &title,
        grid = &grid, interpreter = &interpreter,
    }, limits, 8))
    defer graphics_test_destroy(&store, &graphics, &grid)
    title.query_geometry = {cell_width = 8, cell_height = 16, valid = true}
    gfxsemantics.graphics_semantics_enable(&graphics)

    testing.expect(t, interpreter_write(&interpreter,
        "\e]1337;File=name=x;inline=1;size=68;width=2;height=32px;preserveAspectRatio=0:iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=\a"))

    testing.expect_value(t, store.placement_count, 1)
    _, available := gfxprotocol.graphics_parser_take_decode_request(&graphics)
    testing.expect(t, available)
    testing.expect_value(t, grid.cursor.row, 1)
    testing.expect_value(t, grid.cursor.column, 0)
}

// Verify timg's line-feed and cursor-up animation sequence retains one logical row.
@(test)
graphics_test_iterm2_timg_animation_retains_anchor :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init_with_limits({
        store = &store, graphics = &graphics, title = &title,
        grid = &grid, interpreter = &interpreter,
    }, graphics_test_iterm2_animation_limits(), 8))
    defer graphics_test_destroy(&store, &graphics, &grid)
    title.query_geometry = {cell_width = 8, cell_height = 16, valid = true}
    gfxsemantics.graphics_semantics_enable(&graphics)
    termgrid.grid_set_cursor(&grid, 3, 0)

    IMAGE :: "\e]1337;File=size=68;width=1px;height=32px;inline=1:iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=\a"
    testing.expect(t, interpreter_write(
        &interpreter, IMAGE + "\n\e[2A" + IMAGE + "\n\e[2A" + IMAGE +
            "\n\e[2A" + IMAGE + "\n\e[2A" + IMAGE + "\n"))

    testing.expect_value(t, graphics.decode_request_count, 4)
    testing.expect_value(t, store.placement_count, 4)
    first, first_available := gfxprotocol.graphics_parser_take_decode_request(&graphics)
    second, second_available := gfxprotocol.graphics_parser_take_decode_request(&graphics)
    testing.expect(t, first_available)
    testing.expect(t, second_available)
    testing.expect_value(t, first.geometry.logical_row, second.geometry.logical_row)
    testing.expect_value(t, grid.cursor.row, 5)
    testing.expect_value(t, grid.cursor.column, 0)
}

// Verify and release the completed multipart iTerm2 decode request.
graphics_test_expect_iterm2_multipart :: proc(
    t: ^testing.T, interpreter: ^Interpreter,
    graphics: ^gfxprotocol.Graphics_Parser_State,
    store: ^termattachment.Store, producer: Terminal_Producer) {
    testing.expect(t, interpreter_write(interpreter,
        "\e]1337;MultipartFile=name=x;inline=1;size=68;width=50%\a\e]1337;FilePart=iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=\a\e]1337;FileEnd\a",
        producer))
    request, available := gfxprotocol.graphics_parser_take_decode_request(graphics)
    testing.expect(t, available)
    testing.expect_value(t, request.width_percent, 50)
    bytes, found := termattachment.transfer_bytes(store, request.transfer_id)
    testing.expect(t, found)
    testing.expect_value(t, len(bytes), 68)
    termattachment.transfer_remove(store, request.transfer_id)
    gfxprotocol.graphics_discard_pending_attachment(graphics, request.attachment_id)
}

// Verify one valid Sixel request and release its retained resources.
graphics_test_expect_sixel_request :: proc(
    t: ^testing.T, interpreter: ^Interpreter,
    graphics: ^gfxprotocol.Graphics_Parser_State,
    store: ^termattachment.Store, grid: ^termgrid.Grid) {
    testing.expect(t, interpreter_write(interpreter,
        "\e[?80h\eP1;2q\"1;1;4;12#1;2;100;0;0!4~-$#2;1;120;50;100??\e\\"))
    request, available := gfxprotocol.graphics_parser_take_decode_request(graphics)
    testing.expect(t, available)
    testing.expect_value(t, request.kind, gfxprotocol.Graphics_Decode_Kind.Sixel)
    testing.expect_value(t, request.width, 4)
    testing.expect_value(t, request.height, 12)
    testing.expect_value(t, request.palette_count, 3)
    testing.expect(t, request.palette[1] != 0)
    testing.expect(t, request.palette[2] != 0)
    testing.expect(t, request.transparent_background)
    testing.expect_value(t, grid.cursor.row, 1)
    testing.expect_value(t, grid.cursor.column, 0)
    termattachment.transfer_remove(store, request.transfer_id)
    gfxprotocol.graphics_discard_pending_attachment(graphics, request.attachment_id)
}

// Verify every split of one graphics sequence yields one expected frame.
graphics_test_expect_every_split :: proc(
    t: ^testing.T, sequence: string, expected_kind: gfxprotocol.Graphics_Frame_Kind,
    expected_header, expected_payload: string) {
    producer := Terminal_Producer{.Terminal_Session, 9, 4}
    for split in 0..=len(sequence) {
        store: termattachment.Store
        graphics: gfxprotocol.Graphics_Parser_State
        title: Terminal_Title_State
        grid: termgrid.Grid
        interpreter: Interpreter
        testing.expect(t, graphics_test_init(
            &store, &graphics, &title, &grid, &interpreter))
        testing.expect(t, interpreter_write(
            &interpreter, sequence[:split], producer))
        testing.expect(t, interpreter_write(
            &interpreter, sequence[split:], producer))
        frame, available := gfxprotocol.graphics_parser_take_frame(&graphics)
        testing.expect(t, available)
        testing.expect_value(t, frame.kind, expected_kind)
        testing.expect_value(t, frame.producer, producer)
        testing.expect_value(t,
            string(frame.header[:frame.header_byte_count]), expected_header)
        if frame.transfer_id.generation != 0 {
            bytes, found := termattachment.transfer_bytes(
                &store, frame.transfer_id)
            testing.expect(t, found)
            testing.expect_value(t, string(bytes), expected_payload)
            termattachment.transfer_remove(&store, frame.transfer_id)
        } else {
            testing.expect_value(t, expected_payload, "")
        }
        testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
        graphics_test_destroy(&store, &graphics, &grid)
    }
}

// Verify every split of one Kitty APC frame produces the same decoded result.
@(test)
graphics_test_kitty_apc_every_split :: proc(t: ^testing.T) {
    sequence := "\e_Ga=t;SGVsbG8=\e\\"
    producer := Terminal_Producer{.Terminal_Session, 7, 3}
    for split in 0..=len(sequence) {
        store: termattachment.Store
        graphics: gfxprotocol.Graphics_Parser_State
        title: Terminal_Title_State
        grid: termgrid.Grid
        interpreter: Interpreter
        testing.expect(t, graphics_test_init(
            &store, &graphics, &title, &grid, &interpreter))

        testing.expect(t, interpreter_write(
            &interpreter, sequence[:split], producer))
        testing.expect(t, interpreter_write(
            &interpreter, sequence[split:], producer))
        frame, available := gfxprotocol.graphics_parser_take_frame(&graphics)
        testing.expect(t, available)
        testing.expect_value(t, frame.kind, gfxprotocol.Graphics_Frame_Kind.Kitty)
        testing.expect_value(t, frame.producer, producer)
        testing.expect_value(t,
            string(frame.header[:frame.header_byte_count]), "a=t")
        bytes, found := termattachment.transfer_bytes(
            &store, frame.transfer_id)
        testing.expect(t, found)
        testing.expect_value(t, string(bytes), "Hello")
        testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
        termattachment.transfer_remove(&store, frame.transfer_id)
        graphics_test_destroy(&store, &graphics, &grid)
    }
}

// Verify malformed and cancelled Kitty frames release partial transfer ownership.
@(test)
graphics_test_kitty_apc_recovery_releases_transfer :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init(
        &store, &graphics, &title, &grid, &interpreter))
    defer graphics_test_destroy(&store, &graphics, &grid)

    testing.expect(t, interpreter_write(
        &interpreter, "\e_Ga=t;SGV!ignored\e\\X"))
    testing.expect_value(t, graphics.frame_count, 0)
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect_value(t, cell_text(&grid.cells[0]), "X")
    testing.expect(t, interpreter_write(&interpreter, "\e_Ga=t;SGV"))
    testing.expect_value(t, store.transfer_count, 1)
    testing.expect(t, interpreter_write(&interpreter, "\x18"))
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
}

// Verify Sixel and every selected iTerm2 framing form survive all split points.
@(test)
graphics_test_sixel_and_iterm2_every_split :: proc(t: ^testing.T) {
    graphics_test_expect_every_split(
        t, "\eP1;2qABC\e\\", .Sixel, "1;2", "ABC")
    graphics_test_expect_every_split(
        t, "\e]1337;File=name=x;inline=1:SGk=\a",
        .Iterm2_File, "File=name=x;inline=1", "Hi")
    graphics_test_expect_every_split(
        t, "\e]1337;File=name=x:SGk=\e\\",
        .Iterm2_File, "File=name=x", "Hi")
    graphics_test_expect_every_split(
        t, "\e]1337;MultipartFile=name=x;size=2\a",
        .Iterm2_Multipart_File, "MultipartFile=name=x;size=2", "")
    graphics_test_expect_every_split(
        t, "\e]1337;FilePart=SGk=\e\\",
        .Iterm2_File_Part, "FilePart=", "Hi")
    graphics_test_expect_every_split(
        t, "\e]1337;FileEnd\a", .Iterm2_File_End, "FileEnd", "")
}

// Verify quota failure and producer changes discard partial graphics transfers.
@(test)
graphics_test_transfer_pressure_and_producer_recovery :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init(
        &store, &graphics, &title, &grid, &interpreter))
    defer graphics_test_destroy(&store, &graphics, &grid)
    first := Terminal_Producer{.Terminal_Session, 1, 1}
    second := Terminal_Producer{.Julia_Evaluation, 2, 1}

    testing.expect(t, interpreter_write(
        &interpreter,
        "\e]1337;File=x:QUJDREVGR0hJSktMTU5PUFFSU1Q=\aX", first))
    testing.expect_value(t, graphics.frame_count, 0)
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect_value(t, cell_text(&grid.cells[0]), "X")
    testing.expect(t, interpreter_write(&interpreter, "\ePqABC", first))
    testing.expect_value(t, store.transfer_count, 1)
    testing.expect(t, interpreter_write(&interpreter, "Y", second))
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
    testing.expect_value(t, cell_text(&grid.cells[1]), "Y")
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(2))
}

// Verify bounded header pressure discards without leaking bytes into grid text.
@(test)
graphics_test_header_pressure_recovers :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init(
        &store, &graphics, &title, &grid, &interpreter))
    defer graphics_test_destroy(&store, &graphics, &grid)

    sequence: [gfxprotocol.GRAPHICS_HEADER_BYTE_CAPACITY + 7]u8
    sequence[0] = '\e'
    sequence[1] = '_'
    sequence[2] = 'G'
    for index in 0..=gfxprotocol.GRAPHICS_HEADER_BYTE_CAPACITY {
        sequence[index + 3] = 'x'
    }
    sequence[len(sequence) - 3] = '\e'
    sequence[len(sequence) - 2] = '\\'
    sequence[len(sequence) - 1] = 'X'
    testing.expect(t, interpreter_write(&interpreter, string(sequence[:])))
    testing.expect_value(t, interpreter.overflow_sequence_count, u64(1))
    testing.expect_value(t, graphics.frame_count, 0)
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect_value(t, cell_text(&grid.cells[0]), "X")
}

// Verify completed-frame queue pressure rejects one frame and resumes after drain.
@(test)
graphics_test_frame_pressure_recovers :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init(
        &store, &graphics, &title, &grid, &interpreter))
    defer graphics_test_destroy(&store, &graphics, &grid)

    for _ in 0..<gfxprotocol.GRAPHICS_FRAME_CAPACITY {
        testing.expect(t, interpreter_write(
            &interpreter, "\e]1337;FileEnd\a"))
    }
    testing.expect(t, interpreter_write(&interpreter, "\e]1337;FileEnd\a"))
    testing.expect_value(t, graphics.frame_count, gfxprotocol.GRAPHICS_FRAME_CAPACITY)
    testing.expect_value(t, graphics.frame_rejection_count, u64(1))
    for _ in 0..<gfxprotocol.GRAPHICS_FRAME_CAPACITY {
        _, available := gfxprotocol.graphics_parser_take_frame(&graphics)
        testing.expect(t, available)
    }
    testing.expect(t, interpreter_write(&interpreter, "\e]1337;FileEnd\a"))
    testing.expect_value(t, graphics.frame_count, 1)
}

// Verify stream finalization aborts every graphics state and preserves its service.
@(test)
graphics_test_finalizes_every_incomplete_state :: proc(t: ^testing.T) {
    prefixes := [?]string{
        "\e_Gx;QQ", "\e_Gx;QQ\e", "\e_Gx;!", "\e_Gx;!\e",
        "\eP", "\ePqA", "\ePqA\e", "\ePx", "\ePx\e",
        "\e]1337;File=x", "\e]1337;File=x:QQ\e",
        "\e]1337;File=x:!", "\e]1337;File=x:!\e",
    }
    states := [?]Interpreter_State{
        .Apc, .Apc_Escape, .Apc_Discard, .Apc_Discard_Escape,
        .Dcs, .Dcs_Data, .Dcs_Escape, .Dcs_Discard, .Dcs_Discard_Escape,
        .Iterm2, .Iterm2_Escape, .Iterm2_Discard,
        .Iterm2_Discard_Escape,
    }
    for prefix, index in prefixes {
        store: termattachment.Store
        graphics: gfxprotocol.Graphics_Parser_State
        title: Terminal_Title_State
        grid: termgrid.Grid
        interpreter: Interpreter
        testing.expect(t, graphics_test_init(
            &store, &graphics, &title, &grid, &interpreter))
        testing.expect(t, interpreter_write(&interpreter, prefix))
        testing.expect_value(t, interpreter.state, states[index])
        malformed_before := interpreter.malformed_sequence_count

        interpreter_finish_input(&interpreter)

        testing.expect_value(t, interpreter.state, Interpreter_State.Ground)
        testing.expect_value(t, store.transfer_count, 0)
        testing.expect_value(t,
            interpreter.malformed_sequence_count, malformed_before + 1)
        testing.expect(t, title.graphics == &graphics)
        graphics_test_destroy(&store, &graphics, &grid)
    }
}

// Verify terminated partial Base64 is rejected without leaking payload or text.
@(test)
graphics_test_rejects_truncated_base64 :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init(
        &store, &graphics, &title, &grid, &interpreter))
    defer graphics_test_destroy(&store, &graphics, &grid)

    testing.expect(t, interpreter_write(&interpreter, "\e_Ga=t;QQ\e\\"))
    testing.expect(t, interpreter_write(
        &interpreter, "\e]1337;File=x:QQ\a"))

    testing.expect_value(t, graphics.frame_count, 0)
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect_value(t, interpreter.malformed_sequence_count, u64(2))
}

// Verify bounded Kitty response values retain order and producer correlation.
@(test)
graphics_test_kitty_response_queue_is_bounded :: proc(t: ^testing.T) {
    state: gfxprotocol.Graphics_Parser_State
    for index in 0..<gfxprotocol.KITTY_GRAPHICS_RESPONSE_CAPACITY {
        testing.expect(t, gfxprotocol.graphics_parser_queue_kitty_response(&state, {
            producer = {.Terminal_Session, u64(index + 1), 3},
            image_id = u32(index + 10),
            placement_id = u32(index + 20),
            status = .Ok,
        }))
    }
    testing.expect(t, !gfxprotocol.graphics_parser_queue_kitty_response(&state, {}))
    testing.expect_value(t, state.kitty_response_rejection_count, u64(1))
    for index in 0..<gfxprotocol.KITTY_GRAPHICS_RESPONSE_CAPACITY {
        response, available := gfxprotocol.graphics_parser_take_kitty_response(&state)
        testing.expect(t, available)
        testing.expect_value(t, response.producer.id, u64(index + 1))
        testing.expect_value(t, response.producer.generation, u64(3))
        testing.expect_value(t, response.image_id, u32(index + 10))
        testing.expect_value(t, response.placement_id, u32(index + 20))
    }
    _, available := gfxprotocol.graphics_parser_take_kitty_response(&state)
    testing.expect(t, !available)
}

// Verify Kitty raw RGBA transmission commits placement before following text.
@(test)
graphics_test_kitty_raw_transmit_and_place :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init(
        &store, &graphics, &title, &grid, &interpreter))
    defer graphics_test_destroy(&store, &graphics, &grid)
    producer := Terminal_Producer{.Terminal_Session, 17, 2}
    gfxsemantics.graphics_semantics_enable(&graphics)

    testing.expect(t, interpreter_write(
        &interpreter, "\e_Ga=T,f=32,s=1,v=1,c=1,r=1,C=1;AQIDBA==\e\\X",
        producer))

    testing.expect_value(t, store.attachment_count, 1)
    testing.expect_value(t, store.placement_count, 1)
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect_value(t, grid.cursor.row, 0)
    testing.expect_value(t, grid.cursor.column, 1)
    testing.expect_value(t, cell_text(&grid.cells[0]), "X")
    response, available := gfxprotocol.graphics_parser_take_kitty_response(&graphics)
    testing.expect(t, available)
    testing.expect_value(t, response.producer, producer)
    testing.expect_value(t,
        response.status, gfxprotocol.Kitty_Graphics_Response_Status.Ok)
}

// Verify timg's line-feed and cursor-up Kitty sequence retains one logical row.
@(test)
graphics_test_kitty_timg_animation_retains_anchor :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    limits := termattachment.limits_default()
    limits.attachment_capacity = 4
    limits.placement_capacity = 4
    limits.transfer_capacity = 2
    limits.transfer_byte_limit = 256
    limits.dimension_limit = 4
    limits.image_pixel_limit = 16
    limits.cpu_byte_limit = 256
    limits.gpu_byte_limit = 256
    testing.expect(t, graphics_test_init_with_limits({
        store = &store, graphics = &graphics, title = &title,
        grid = &grid, interpreter = &interpreter,
    }, limits, row_count = 8))
    defer graphics_test_destroy(&store, &graphics, &grid)
    gfxsemantics.graphics_semantics_enable(&graphics)
    termgrid.grid_set_cursor(&grid, 3, 0)

    IMAGE :: "\e_Ga=T,f=100,i=7,r=2,q=2;iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=\e\\"
    expected_row: i64
    for frame_index in 0..<4 {
        testing.expect(t, interpreter_write(&interpreter, IMAGE + "\n\e[2A"))
        request, available :=
            gfxprotocol.graphics_parser_take_decode_request(&graphics)
        testing.expect(t, available)
        if frame_index == 0 { expected_row = request.geometry.logical_row }
        testing.expect_value(t, request.geometry.logical_row, expected_row)
        termattachment.transfer_remove(&store, request.transfer_id)
    }
    testing.expect_value(t, store.placement_count, 1)
    testing.expect_value(t, grid.cursor.row, 3)
}

// Initialize one Kitty animation fixture and append its second frame.
graphics_test_kitty_animation_setup :: proc(
    t: ^testing.T, targets: Graphics_Test_Targets) ->
    (Terminal_Producer, termattachment.Attachment_Id) {
    testing.expect(t, graphics_test_init_with_limits(
        targets, graphics_test_kitty_animation_limits()))
    gfxsemantics.graphics_semantics_enable(targets.graphics)
    producer := Terminal_Producer{.Terminal_Session, 18, 2}
    testing.expect(t, interpreter_write(targets.interpreter,
        "\e_Ga=t,f=32,s=2,v=1,i=7;/wAA/wAA//8=\e\\", producer))
    _, response_present := gfxprotocol.graphics_parser_take_kitty_response(
        targets.graphics)
    testing.expect(t, response_present)
    testing.expect(t, interpreter_write(targets.interpreter,
        "\e_Ga=f,f=32,s=1,v=1,x=1,c=1,z=25,X=1,i=7;AP8A/w==\e\\",
        producer))
    frame_response, frame_response_present :=
        gfxprotocol.graphics_parser_take_kitty_response(targets.graphics)
    testing.expect(t, frame_response_present)
    testing.expect_value(t,
        frame_response.status, gfxprotocol.Kitty_Graphics_Response_Status.Ok)
    identity_index := gfxsemantics.graphics_kitty_find_image(
        targets.graphics, {image_id = 7})
    testing.expect(t, identity_index >= 0)
    id := targets.graphics.kitty_images[identity_index].attachment_id
    _, refresh_present := gfxprotocol.graphics_parser_take_animation_command(
        targets.graphics)
    testing.expect(t, refresh_present)
    return producer, id
}

// Verify Kitty frame upload and composition retain exact pixels and refresh effects.
@(test)
graphics_test_kitty_animation_mutations :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    producer, id := graphics_test_kitty_animation_setup(
        t, {&store, &graphics, &title, &grid, &interpreter})
    defer graphics_test_destroy(&store, &graphics, &grid)
    animation, found := termattachment.animation_view(&store, id)
    testing.expect(t, found)
    if found {
        testing.expect_value(t, animation.timeline.frame_count, 2)
        testing.expect_value(t, animation.pixels[12], u8(0))
        testing.expect_value(t, animation.pixels[13], u8(255))
    }
    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=c,i=7,r=1,c=2,X=0,Y=0,x=1,y=0,w=1,h=1,C=1;\e\\",
        producer))
    composition_response, composition_response_present :=
        gfxprotocol.graphics_parser_take_kitty_response(&graphics)
    testing.expect(t, composition_response_present)
    testing.expect_value(t,
        composition_response.status, gfxprotocol.Kitty_Graphics_Response_Status.Ok)
    composed, composed_found := termattachment.animation_view(&store, id)
    testing.expect(t, composed_found)
    testing.expect_value(t, composed.pixels[12], u8(255))
    testing.expect_value(t, composed.pixels[13], u8(0))
    _, composition_refresh_present :=
        gfxprotocol.graphics_parser_take_animation_command(&graphics)
    testing.expect(t, composition_refresh_present)
}

// Verify Kitty controls, deletion, and continuation chunks retain ordered effects.
@(test)
graphics_test_kitty_animation_control_delete_chunk :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    producer, id := graphics_test_kitty_animation_setup(
        t, {&store, &graphics, &title, &grid, &interpreter})
    defer graphics_test_destroy(&store, &graphics, &grid)
    targets := Graphics_Test_Targets{&store, &graphics, &title, &grid, &interpreter}
    graphics_test_write_kitty_status(t, targets,
        "\e_Ga=a,i=7,s=3,c=2,v=2;\e\\", producer, .Ok)
    control, control_present := gfxprotocol.graphics_parser_take_animation_command(
        &graphics)
    testing.expect(t, control_present)
    testing.expect_value(t,
        control.kind, gfxprotocol.Kitty_Animation_Command_Kind.Control)
    testing.expect_value(t, control.current_frame, 2)
    testing.expect_value(t, control.animation_state, 3)
    graphics_test_write_kitty_status(t, targets,
        "\e_Ga=d,d=f,i=7,r=2;\e\\", producer, .Ok)
    reduced, reduced_found := termattachment.animation_view(&store, id)
    testing.expect(t, reduced_found)
    testing.expect_value(t, reduced.timeline.frame_count, 1)

    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=f,f=32,s=1,v=1,i=7,m=1;AP8A\e\\", producer))
    _, partial_response_present :=
        gfxprotocol.graphics_parser_take_kitty_response(&graphics)
    testing.expect(t, !partial_response_present)
    testing.expect(t, interpreter_write(&interpreter,
        "\e_Gm=0;/w==\e\\", producer))
    graphics_test_expect_kitty_status(
        t, &graphics, gfxprotocol.Kitty_Graphics_Response_Status.Ok)
    chunked, chunked_found := termattachment.animation_view(&store, id)
    testing.expect(t, chunked_found)
    testing.expect_value(t, chunked.timeline.frame_count, 2)
}

// Verify animation replies preserve exact status classes and Kitty quiet modes.
@(test)
graphics_test_kitty_animation_response_matrix :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    limits := graphics_test_kitty_animation_limits()
    limits.placement_capacity = 2
    testing.expect(t, graphics_test_init_with_limits(
        {&store, &graphics, &title, &grid, &interpreter}, limits))
    defer graphics_test_destroy(&store, &graphics, &grid)
    gfxsemantics.graphics_semantics_enable(&graphics)
    producer := Terminal_Producer{.Terminal_Session, 20, 2}

    targets := Graphics_Test_Targets{&store, &graphics, &title, &grid, &interpreter}
    graphics_test_write_kitty_status(t, targets,
        "\e_Ga=a,i=99,s=3;\e\\", producer, .Not_Found)
    graphics_test_write_kitty_status(t, targets,
        "\e_Ga=a,i=99,s=3,q=1;\e\\", producer, .Not_Found)
    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=a,i=99,s=3,q=2;\e\\", producer))
    _, present := gfxprotocol.graphics_parser_take_kitty_response(&graphics)
    testing.expect(t, !present)
    graphics_test_write_kitty_status(t, targets,
        "\e_Ga=a,i=99,s=4;\e\\", producer, .Invalid)
}

// Verify committed mutation command pressure returns exact Kitty capacity status.
@(test)
graphics_test_kitty_animation_response_pressure :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    producer, _ := graphics_test_kitty_animation_setup(
        t, {&store, &graphics, &title, &grid, &interpreter})
    defer graphics_test_destroy(&store, &graphics, &grid)
    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=t,f=32,s=1,v=1,i=8;/wAA/w==\e\\", producer))
    graphics_test_expect_kitty_status(
        t, &graphics, gfxprotocol.Kitty_Graphics_Response_Status.Ok)
    identity_index := gfxsemantics.graphics_kitty_find_image(
        &graphics, {image_id = 8})
    testing.expect(t, identity_index >= 0)
    id := graphics.kitty_images[identity_index].attachment_id
    for _ in 0..<gfxprotocol.KITTY_ANIMATION_COMMAND_CAPACITY {
        testing.expect(t, gfxprotocol.graphics_parser_queue_animation_command(
            &graphics, {attachment_id = id, kind = .Refresh}))
    }
    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=f,f=32,s=1,v=1,i=8;AP8A/w==\e\\", producer))
    graphics_test_expect_kitty_status(
        t, &graphics, gfxprotocol.Kitty_Graphics_Response_Status.Capacity_Exceeded)
}

// Verify an encoded frame blocks a later same-image control until worker preparation.
@(test)
graphics_test_kitty_encoded_frame_orders_control :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    limits := graphics_test_kitty_animation_limits()
    limits.attachment_capacity = 3
    limits.placement_capacity = 2
    limits.transfer_byte_limit = 128
    testing.expect(t, graphics_test_init_with_limits(
        {&store, &graphics, &title, &grid, &interpreter}, limits))
    defer graphics_test_destroy(&store, &graphics, &grid)
    gfxsemantics.graphics_semantics_enable(&graphics)
    producer := Terminal_Producer{.Terminal_Session, 19, 2}

    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=t,f=32,s=1,v=1,i=9;/wAA/w==\e\\", producer))
    _, response_present := gfxprotocol.graphics_parser_take_kitty_response(&graphics)
    testing.expect(t, response_present)
    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=f,f=100,i=9;iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=\e\\",
        producer))
    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=a,i=9,s=3,c=2;\e\\", producer))

    testing.expect_value(t, graphics.kitty_mutation_request_count, 2)
    testing.expect(t, !graphics.kitty_mutation_requests[0].ready)
    testing.expect(t, graphics.kitty_mutation_requests[1].ready)
    _, mutation_present := gfxprotocol.graphics_parser_take_mutation_request(&graphics)
    testing.expect(t, !mutation_present)
    decode, decode_present := gfxprotocol.graphics_parser_take_decode_request(&graphics)
    testing.expect(t, decode_present)
    testing.expect_value(t,
        decode.mutation_sequence, graphics.kitty_mutation_requests[0].sequence)
}

// Verify Kitty image identity supports RGB placement, replacement, quiet, and delete.
@(test)
graphics_test_kitty_identity_replacement_and_delete :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init(
        &store, &graphics, &title, &grid, &interpreter))
    defer graphics_test_destroy(&store, &graphics, &grid)
    gfxsemantics.graphics_semantics_enable(&graphics)
    targets := Graphics_Test_Write_Targets{&interpreter, &store}

    graphics_test_expect_write_counts(t, targets,
        "\e_Ga=t,f=24,s=1,v=1,i=7;AQID\e\\", 1, 0)
    _, available := gfxprotocol.graphics_parser_take_kitty_response(&graphics)
    testing.expect(t, available)

    graphics_test_expect_write_counts(t, targets,
        "\e_Ga=p,i=7,p=9,C=1\e\\", 1, 1)
    _, available = gfxprotocol.graphics_parser_take_kitty_response(&graphics)
    testing.expect(t, available)

    graphics_test_expect_write_counts(t, targets,
        "\e_Ga=t,f=32,s=1,v=1,i=7,q=1;BQYHCA==\e\\", 1, 0)
    _, available = gfxprotocol.graphics_parser_take_kitty_response(&graphics)
    testing.expect(t, !available)

    graphics_test_expect_write_counts(t, targets,
        "\e_Ga=p,i=7,p=9,C=1\e\\", 1, 1)
    graphics_test_expect_write_counts(t, targets,
        "\e_Ga=d,d=p,p=9\e\\", 1, 0)
    graphics_test_expect_write_counts(t, targets,
        "\e_Ga=d,d=I,i=7\e\\", 0, 0)
}

// Verify one retained Kitty PNG decode request and its bounded transfer payload.
graphics_test_expect_kitty_png_decode :: proc(
    t: ^testing.T, targets: Graphics_Test_Targets,
    request: gfxprotocol.Graphics_Decode_Request) {
    testing.expect_value(t, request.kind, gfxprotocol.Graphics_Decode_Kind.Kitty_Png)
    testing.expect_value(t, request.image_id, u32(3))
    testing.expect_value(t, request.placement_id, u32(4))
    testing.expect_value(t, request.geometry.column_span, 2)
    testing.expect(t, request.place)
    testing.expect(t, request.attachment_id.generation != 0)
    testing.expect_value(t, targets.store.attachment_count, 1)
    testing.expect_value(t, targets.store.placement_count, 1)
    bytes, found := termattachment.transfer_bytes(
        targets.store, request.transfer_id)
    testing.expect(t, found)
    testing.expect_value(t, len(bytes), 68)
}

// Verify encoded Kitty payloads retain bounded decode ownership and placement intent.
@(test)
graphics_test_kitty_png_decode_request :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init_with_limits({
        store = &store, graphics = &graphics, title = &title,
        grid = &grid, interpreter = &interpreter,
    }, {
        attachment_capacity = 2, placement_capacity = 4, transfer_capacity = 2,
        transfer_byte_limit = 256, dimension_limit = 4, image_pixel_limit = 16,
        cpu_byte_limit = 256, gpu_byte_limit = 256,
        animated_attachment_limit = 2, animation_frame_limit = 4,
        animation_decode_byte_limit = 256,
        animation_min_frame_duration_ns = 1_000_000,
        animation_max_frame_duration_ns = 100_000_000,
        animation_duration_ns_limit = 1_000_000_000,
    }))
    defer graphics_test_destroy(&store, &graphics, &grid)
    gfxsemantics.graphics_semantics_enable(&graphics)

    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=T,f=100,i=3,p=4,c=2,r=1,C=1;iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=\e\\"))
    request, available := gfxprotocol.graphics_parser_take_decode_request(&graphics)
    testing.expect(t, available)
    graphics_test_expect_kitty_png_decode(t,
        {&store, &graphics, &title, &grid, &interpreter}, request)
    termattachment.transfer_remove(&store, request.transfer_id)
    gfxprotocol.graphics_discard_pending_attachment(&graphics, request.attachment_id)
}

// Verify iTerm2 original and multipart images produce exact bounded decode requests.
@(test)
graphics_test_iterm2_original_and_multipart :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init_with_limits({
        store = &store, graphics = &graphics, title = &title,
        grid = &grid, interpreter = &interpreter,
    }, {
        attachment_capacity = 2, placement_capacity = 4, transfer_capacity = 2,
        transfer_byte_limit = 256, dimension_limit = 4, image_pixel_limit = 16,
        cpu_byte_limit = 256, gpu_byte_limit = 256,
        animated_attachment_limit = 2, animation_frame_limit = 4,
        animation_decode_byte_limit = 256,
        animation_min_frame_duration_ns = 1_000_000,
        animation_max_frame_duration_ns = 100_000_000,
        animation_duration_ns_limit = 1_000_000_000,
    }))
    defer graphics_test_destroy(&store, &graphics, &grid)
    gfxsemantics.graphics_semantics_enable(&graphics)
    producer := Terminal_Producer{.Terminal_Session, 2, 5}

    graphics_test_expect_iterm2_original(
        t, &interpreter, &graphics, &store, producer)
    graphics_test_expect_iterm2_multipart(
        t, &interpreter, &graphics, &store, producer)

    testing.expect(t, interpreter_write(&interpreter,
        "\e]1337;MultipartFile=x;inline=1;size=3\a\e]1337;FilePart=iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=\a\e]1337;FileEnd\a",
        producer))
    _, available := gfxprotocol.graphics_parser_take_decode_request(&graphics)
    testing.expect(t, !available)
    testing.expect_value(t, store.transfer_count, 0)
}

// Verify Sixel semantics retain palette, extent, transparency, and DECSDM effects.
@(test)
graphics_test_sixel_semantics_and_recovery :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init_with_limits({
        store = &store,
        graphics = &graphics,
        title = &title,
        grid = &grid,
        interpreter = &interpreter,
    }, {
            attachment_capacity = 2,
            placement_capacity = 4,
            transfer_capacity = 2,
            transfer_byte_limit = 512,
            dimension_limit = 32,
            image_pixel_limit = 256,
            cpu_byte_limit = 256,
            gpu_byte_limit = 256,
            animated_attachment_limit = 2,
            animation_frame_limit = 4,
            animation_decode_byte_limit = 256,
            animation_min_frame_duration_ns = 1_000_000,
            animation_max_frame_duration_ns = 100_000_000,
            animation_duration_ns_limit = 1_000_000_000,
        }))
    defer graphics_test_destroy(&store, &graphics, &grid)
    gfxsemantics.graphics_semantics_enable(&graphics)

    graphics_test_expect_sixel_request(
        t, &interpreter, &graphics, &store, &grid)

    testing.expect(t, interpreter_write(&interpreter, "\ePq!0~\e\\"))
    _, available := gfxprotocol.graphics_parser_take_decode_request(&graphics)
    testing.expect(t, !available)
    testing.expect_value(t, store.transfer_count, 0)
}

// Initialize one bounded Sixel animation fixture with explicit raster limits.
graphics_test_init_sixel_animation :: proc(
    targets: Graphics_Test_Targets, config: Graphics_Test_Sixel_Config) -> bool {
    return graphics_test_init_with_limits(targets, {
        attachment_capacity = config.attachment_capacity,
        placement_capacity = 4,
        transfer_capacity = 2,
        transfer_byte_limit = 64,
        dimension_limit = config.dimension_limit,
        image_pixel_limit = config.image_pixel_limit,
        cpu_byte_limit = config.byte_limit,
        gpu_byte_limit = config.byte_limit,
        animated_attachment_limit = 2,
        animation_frame_limit = 4,
        animation_decode_byte_limit = config.byte_limit,
        animation_min_frame_duration_ns = 1_000_000,
        animation_max_frame_duration_ns = 100_000_000,
        animation_duration_ns_limit = 1_000_000_000,
    }, row_count = config.row_count)
}

// Write one Sixel frame, verify cursor and placement effects, and release its transfer.
graphics_test_expect_sixel_frame :: proc(
    t: ^testing.T, targets: Graphics_Test_Targets, command: string,
    expected_row, expected_placements: int) -> gfxprotocol.Graphics_Decode_Request {
    testing.expect(t, interpreter_write(targets.interpreter, command))
    request, available := gfxprotocol.graphics_parser_take_decode_request(
        targets.graphics)
    testing.expect(t, available)
    testing.expect_value(t, targets.grid.cursor.row, expected_row)
    testing.expect_value(t, targets.store.placement_count, expected_placements)
    termattachment.transfer_remove(targets.store, request.transfer_id)
    return request
}

// Drive four timg-style Sixel frames while preserving one logical anchor.
graphics_test_expect_sixel_timg_frames :: proc(
    t: ^testing.T, targets: Graphics_Test_Targets,
    attachment_ids: ^[4]termattachment.Attachment_Id) {
    FRAME :: "\e[80l\e[?7730l\e[?8452h\ePq\"1;1;16;144!16~\e\\"
    expected_row: i64
    for frame_index in 0..<4 {
        if frame_index > 0 {
            testing.expect(t, interpreter_write(targets.interpreter, "\e[9A"))
        }
        testing.expect(t, interpreter_write(targets.interpreter, FRAME))
        request, available := gfxprotocol.graphics_parser_take_decode_request(
            targets.graphics)
        testing.expect(t, available)
        if frame_index == 0 { expected_row = request.geometry.logical_row }
        testing.expect_value(t, request.geometry.logical_row, expected_row)
        testing.expect_value(t, targets.grid.cursor.row, 9)
        testing.expect_value(t, targets.grid.cursor.column, 2)
        testing.expect(t, interpreter_write(targets.interpreter, "\r\n"))
        testing.expect_value(t, targets.grid.cursor.row, 10)
        testing.expect_value(t, targets.grid.cursor.column, 0)
        attachment_ids[frame_index] = request.attachment_id
        termattachment.transfer_remove(targets.store, request.transfer_id)
    }
}

// Verify reset DECSDM cursor effects and exact-anchor Sixel redraw replacement.
@(test)
graphics_test_sixel_reset_decsdm_redraw :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init_sixel_animation({
        store = &store,
        graphics = &graphics,
        title = &title,
        grid = &grid,
        interpreter = &interpreter,
    }, {2, 32, 128, 1024, 4}))
    defer graphics_test_destroy(&store, &graphics, &grid)
    gfxsemantics.graphics_semantics_enable(&graphics)
    title.query_geometry = {cell_width = 8, cell_height = 16, valid = true}
    targets := Graphics_Test_Targets{&store, &graphics, &title, &grid, &interpreter}

    first := graphics_test_expect_sixel_frame(
        t, targets, "\e[?80l\ePq\"1;1;4;32!4~\e\\\n", 2, 1)

    second := graphics_test_expect_sixel_frame(
        t, targets, "\e[2A\e[?80l\ePq\"1;1;4;32!4~\e\\\n", 2, 2)

    gfxprotocol.graphics_discard_pending_attachment(&graphics, first.attachment_id)
    testing.expect(t, interpreter_write(
        &interpreter, "\e[2A\e[C\ePq\"1;1;4;32!4~\e\\"))
    third, third_available := gfxprotocol.graphics_parser_take_decode_request(&graphics)
    testing.expect(t, third_available)
    testing.expect_value(t, store.placement_count, 2)
    termattachment.transfer_remove(&store, third.transfer_id)
    gfxprotocol.graphics_discard_pending_attachment(&graphics, second.attachment_id)
    gfxprotocol.graphics_discard_pending_attachment(&graphics, third.attachment_id)
}

// Verify timg's unprefixed DECSDM and cursor-up Sixel sequence retains one anchor.
@(test)
graphics_test_sixel_timg_animation_retains_anchor :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init_sixel_animation({
        store = &store, graphics = &graphics, title = &title,
        grid = &grid, interpreter = &interpreter,
    }, {4, 160, 4096, 65_536, 16}))
    defer graphics_test_destroy(&store, &graphics, &grid)
    gfxsemantics.graphics_semantics_enable(&graphics)
    title.query_geometry = {cell_width = 8, cell_height = 16, valid = true}
    termgrid.grid_set_cursor(&grid, 1, 0)

    attachment_ids: [4]termattachment.Attachment_Id
    graphics_test_expect_sixel_timg_frames(t,
        {&store, &graphics, &title, &grid, &interpreter}, &attachment_ids)
    testing.expect(t, !grid.editing.sixel_scrolling_mode)
    testing.expect_value(t, store.placement_count, 4)
    testing.expect_value(t, grid.cursor.row, 10)
    for attachment_id in attachment_ids {
        gfxprotocol.graphics_discard_pending_attachment(&graphics, attachment_id)
    }
}

// Verify Kitty direct chunks assemble once and abort when producer identity changes.
@(test)
graphics_test_kitty_chunk_assembly_and_boundary :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init(
        &store, &graphics, &title, &grid, &interpreter))
    defer graphics_test_destroy(&store, &graphics, &grid)
    gfxsemantics.graphics_semantics_enable(&graphics)
    first := Terminal_Producer{.Terminal_Session, 4, 1}
    second := Terminal_Producer{.Julia_Evaluation, 8, 1}

    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=t,f=32,s=1,v=1,i=5,m=1;AQI=\e\\", first))
    testing.expect_value(t, store.transfer_count, 1)
    testing.expect(t, interpreter_write(
        &interpreter, "\e_Gm=0;AwQ=\e\\", first))
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect_value(t, store.attachment_count, 1)
    testing.expect(t, interpreter_write(
        &interpreter, "\e_Ga=p,i=5,C=1\e\\", first))
    testing.expect_value(t, store.placement_count, 1)

    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=t,f=32,s=1,v=1,i=6,m=1;AQI=\e\\", first))
    testing.expect_value(t, store.transfer_count, 1)
    testing.expect(t, interpreter_write(&interpreter, "X", second))
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect_value(t, cell_text(&grid.cells[0]), "X")
}

// Verify Kitty crop, offsets, and z-index map into neutral placement metadata.
@(test)
graphics_test_kitty_geometry_and_z_delete :: proc(t: ^testing.T) {
    store: termattachment.Store
    graphics: gfxprotocol.Graphics_Parser_State
    title: Terminal_Title_State
    grid: termgrid.Grid
    interpreter: Interpreter
    testing.expect(t, graphics_test_init(
        &store, &graphics, &title, &grid, &interpreter))
    defer graphics_test_destroy(&store, &graphics, &grid)
    gfxsemantics.graphics_semantics_enable(&graphics)

    testing.expect(t, interpreter_write(&interpreter,
        "\e_Ga=T,f=32,s=1,v=1,i=12,p=13,c=2,r=3,x=0,y=0,w=1,h=1,X=2,Y=3,z=-4,C=1;AQIDBA==\e\\"))
    testing.expect_value(t, store.placement_count, 1)
    identity := graphics.kitty_placements[0]
    metadata, found := termattachment.placement_metadata(
        &store, identity.internal_id)
    testing.expect(t, found)
    testing.expect_value(t, metadata.geometry.column_span, 2)
    testing.expect_value(t, metadata.geometry.row_span, 3)
    testing.expect_value(t, metadata.geometry.content_offset_x, 2)
    testing.expect_value(t, metadata.geometry.content_offset_y, 3)
    testing.expect_value(t, metadata.geometry.source,
        termattachment.Pixel_Rectangle{0, 0, 1, 1})
    testing.expect_value(t, metadata.geometry.z_index, i32(-4))

    testing.expect(t, interpreter_write(
        &interpreter, "\e_Ga=d,d=z,z=-4\e\\"))
    testing.expect_value(t, store.placement_count, 0)
    testing.expect_value(t, store.attachment_count, 1)
}