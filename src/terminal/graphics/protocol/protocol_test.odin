#+test
package termgraphicsprotocol

import "core:testing"
import termattachment "../../attachment"
import termmodel "../../model"

// Return compact attachment limits sufficient for graphics protocol unit tests.
graphics_protocol_test_limits :: proc() -> termattachment.Limits {
    return {
        attachment_capacity = 2,
        placement_capacity = 2,
        transfer_capacity = 2,
        transfer_byte_limit = 64,
        dimension_limit = 8,
        image_pixel_limit = 64,
        cpu_byte_limit = 256,
        gpu_byte_limit = 256,
        animated_attachment_limit = 2,
        animation_frame_limit = 4,
        animation_decode_byte_limit = 256,
        animation_min_frame_duration_ns = 1_000_000,
        animation_max_frame_duration_ns = 100_000_000,
        animation_duration_ns_limit = 1_000_000_000,
    }
}

// Initialize one attachment store and its borrowed graphics protocol state.
graphics_protocol_test_init :: proc(
    store: ^termattachment.Store, state: ^Graphics_Parser_State) -> bool {
    return termattachment.store_init(
        store, graphics_protocol_test_limits(), context.allocator) &&
        graphics_parser_init(state, store)
}

// Verify canonical Base64 framing retains exact header, payload, and producer identity.
@(test)
graphics_protocol_test_base64_frame :: proc(t: ^testing.T) {
    store: termattachment.Store
    state: Graphics_Parser_State
    testing.expect(t, graphics_protocol_test_init(&store, &state))
    defer termattachment.store_destroy(&store)
    defer graphics_parser_destroy(&state)

    testing.expect(t, graphics_parser_begin_transfer(&state, .Kitty))
    header := "a=t"
    for byte in transmute([]u8)header {
        testing.expect(t, graphics_parser_append_header(&state, byte))
    }
    payload := "SGVsbG8="
    for byte in transmute([]u8)payload {
        testing.expect(t, graphics_parser_ingest_base64(&state, byte))
    }
    producer := termmodel.Terminal_Producer{.Terminal_Session, 7, 3}
    testing.expect(t, graphics_parser_finish_frame(
        &state, .Kitty, producer, true))

    frame, present := graphics_parser_take_frame(&state)
    testing.expect(t, present)
    testing.expect_value(t, frame.kind, Graphics_Frame_Kind.Kitty)
    testing.expect_value(t, frame.producer, producer)
    testing.expect_value(t,
        string(frame.header[:frame.header_byte_count]), "a=t")
    bytes, found := termattachment.transfer_bytes(&store, frame.transfer_id)
    testing.expect(t, found)
    testing.expect_value(t, string(bytes), "Hello")
    termattachment.transfer_remove(&store, frame.transfer_id)
}

// Verify invalid Base64 aborts without publishing a frame or retaining a transfer.
@(test)
graphics_protocol_test_invalid_base64_releases_transfer :: proc(t: ^testing.T) {
    store: termattachment.Store
    state: Graphics_Parser_State
    testing.expect(t, graphics_protocol_test_init(&store, &state))
    defer termattachment.store_destroy(&store)
    defer graphics_parser_destroy(&state)

    testing.expect(t, graphics_parser_begin_transfer(&state, .Kitty))
    testing.expect(t, !graphics_parser_ingest_base64(&state, '!'))
    testing.expect(t, !graphics_parser_finish_frame(
        &state, .Kitty, {}, true))
    testing.expect_value(t, state.frame_count, 0)
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect_value(t, state.frame_rejection_count, u64(1))
}

// Verify the Kitty response queue preserves order and rejects excess values.
@(test)
graphics_protocol_test_response_queue_is_bounded :: proc(t: ^testing.T) {
    state: Graphics_Parser_State
    for index in 0..<KITTY_GRAPHICS_RESPONSE_CAPACITY {
        testing.expect(t, graphics_parser_queue_kitty_response(&state, {
            producer = {.Terminal_Session, u64(index + 1), 4},
            image_id = u32(index + 10),
            status = .Ok,
        }))
    }
    testing.expect(t, !graphics_parser_queue_kitty_response(&state, {}))
    testing.expect_value(t, state.kitty_response_rejection_count, u64(1))

    for index in 0..<KITTY_GRAPHICS_RESPONSE_CAPACITY {
        response, present := graphics_parser_take_kitty_response(&state)
        testing.expect(t, present)
        testing.expect_value(t, response.producer.id, u64(index + 1))
        testing.expect_value(t, response.image_id, u32(index + 10))
    }
    _, present := graphics_parser_take_kitty_response(&state)
    testing.expect(t, !present)
}

// Verify only GIF preflight may transfer payload ownership without an attachment.
@(test)
graphics_protocol_test_preflight_attachment_invariant :: proc(t: ^testing.T) {
    state: Graphics_Parser_State
    transfer := termattachment.Transfer_Id{slot = 0, generation = 1}
    attachment := termattachment.Attachment_Id{slot = 0, generation = 1}

    testing.expect(t, !graphics_parser_queue_decode_request(&state, {
        kind = .Iterm2_Image, transfer_id = transfer,
    }))
    testing.expect(t, !graphics_parser_queue_decode_request(&state, {
        kind = .Iterm2_Gif_Preflight,
        transfer_id = transfer,
        attachment_id = attachment,
    }))
    testing.expect(t, graphics_parser_queue_decode_request(&state, {
        kind = .Iterm2_Gif_Preflight, transfer_id = transfer,
    }))
    testing.expect(t, graphics_parser_queue_decode_request(&state, {
        kind = .Iterm2_Image,
        transfer_id = transfer,
        attachment_id = attachment,
    }))
}

// Verify Kitty animation commands retain exact generations in FIFO order.
@(test)
graphics_protocol_test_animation_command_queue :: proc(t: ^testing.T) {
    state: Graphics_Parser_State
    for index in 0..<KITTY_ANIMATION_COMMAND_CAPACITY {
        testing.expect(t, graphics_parser_queue_animation_command(&state, {
            attachment_id = {slot = index, generation = u64(index + 1)},
            kind = .Control,
            current_frame = index + 1,
        }))
    }
    testing.expect(t, !graphics_parser_queue_animation_command(&state, {
        attachment_id = {slot = 1, generation = 1},
    }))
    for index in 0..<KITTY_ANIMATION_COMMAND_CAPACITY {
        command, present := graphics_parser_take_animation_command(&state)
        testing.expect(t, present)
        testing.expect_value(t, command.attachment_id.generation, u64(index + 1))
        testing.expect_value(t, command.current_frame, index + 1)
    }
    _, present := graphics_parser_take_animation_command(&state)
    testing.expect(t, !present)
}

// Verify encoded readiness blocks later mutations and requires exact correlation.
@(test)
graphics_protocol_test_mutation_readiness_preserves_order :: proc(t: ^testing.T) {
    state: Graphics_Parser_State
    target := termattachment.Attachment_Id{slot = 1, generation = 2}
    temporary := termattachment.Attachment_Id{slot = 0, generation = 3}
    first_sequence, queued := graphics_parser_queue_mutation_request(&state, {
        attachment_id = target,
        temporary_attachment_id = temporary,
        kind = .Frame,
    })
    testing.expect(t, queued)
    _, queued = graphics_parser_queue_mutation_request(&state, {
        attachment_id = target,
        kind = .Control,
        ready = true,
    })
    testing.expect(t, queued)
    _, present := graphics_parser_take_mutation_request(&state)
    testing.expect(t, !present)
    testing.expect(t, !graphics_parser_mark_mutation_ready(
        &state, first_sequence, {slot = 0, generation = 4}))
    testing.expect(t, graphics_parser_mark_mutation_ready(
        &state, first_sequence, temporary))
    first, second: Kitty_Mutation_Request
    first, present = graphics_parser_take_mutation_request(&state)
    testing.expect(t, present)
    testing.expect_value(t, first.kind, Kitty_Mutation_Kind.Frame)
    second, present = graphics_parser_take_mutation_request(&state)
    testing.expect(t, present)
    testing.expect_value(t, second.kind, Kitty_Mutation_Kind.Control)
}

// Verify destruction releases an active transfer before clearing borrowed state.
@(test)
graphics_protocol_test_destroy_releases_active_transfer :: proc(t: ^testing.T) {
    store: termattachment.Store
    state: Graphics_Parser_State
    testing.expect(t, graphics_protocol_test_init(&store, &state))
    defer termattachment.store_destroy(&store)

    testing.expect(t, graphics_parser_begin_transfer(&state, .Sixel))
    testing.expect_value(t, store.transfer_count, 1)
    graphics_parser_destroy(&state)
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect(t, state.store == nil)
}
