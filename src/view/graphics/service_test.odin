#+test
package viewgraphics

import "../../taskpool"
import "../../evidence/trace"
import termattachment "../../terminal/attachment"
import termgraphicsprepare "../../terminal/graphics/prepare"
import gfxprotocol "../../terminal/graphics/protocol"
import termmodel "../../terminal/model"

import "core:testing"

GRAPHICS_SERVICE_TEST_ANIMATED_GIF :: [109]u8{
    71, 73, 70, 56, 57, 97, 2, 0, 1, 0, 129, 0, 0, 255, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 33, 255, 11, 78, 69, 84, 83,
    67, 65, 80, 69, 50, 46, 48, 3, 1, 2, 0, 0, 33, 249, 4, 8,
    2, 0, 0, 0, 44, 0, 0, 0, 0, 2, 0, 1, 0, 0, 8, 5,
    0, 1, 0, 8, 8, 0, 33, 249, 4, 8, 3, 0, 0, 0, 44, 0,
    0, 0, 0, 2, 0, 1, 0, 129, 0, 255, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 8, 5, 0, 1, 0, 8, 8, 0, 59,
}

GRAPHICS_SERVICE_TEST_PNG :: [68]u8{
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 4, 0, 0, 0, 181, 28, 12,
    2, 0, 0, 0, 11, 73, 68, 65, 84, 120, 218, 99, 100, 248, 15, 0,
    1, 5, 1, 1, 39, 24, 227, 102, 0, 0, 0, 0, 73, 69, 78, 68,
    174, 66, 96, 130,
}

GRAPHICS_SERVICE_TEST_STATIC_GIF :: [34]u8{
    71, 73, 70, 56, 57, 97, 1, 0, 1, 0, 128, 0, 0, 0, 0, 0,
    255, 255, 255, 44, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 1, 76,
    0, 59,
}

// Verify two pixel buffers have identical lengths and contents.
service_test_expect_pixels_equal :: proc(
    t: ^testing.T,
    actual, expected: []u8) {
    testing.expect_value(t, len(actual), len(expected))
    for index in 0..<len(expected) {
        testing.expect_value(t, actual[index], expected[index])
    }
}

// Verify normalized timeline data and playback transitions are equivalent.
service_test_expect_animation_parity :: proc(
    t: ^testing.T,
    actual_id: termattachment.Attachment_Id,
    actual: termattachment.Animation_View,
    expected_id: termattachment.Attachment_Id,
    expected: termattachment.Animation_View) {
    testing.expect_value(t, actual.timeline, expected.timeline)
    service_test_expect_pixels_equal(t, actual.pixels, expected.pixels)
    actual_playback, actual_valid := playback_begin(actual_id, actual, 100)
    expected_playback, expected_valid := playback_begin(expected_id, expected, 100)
    testing.expect(t, actual_valid && expected_valid)
    actual_plan := playback_plan(actual_playback, actual, 20_000_100)
    expected_plan := playback_plan(expected_playback, expected, 20_000_100)
    testing.expect_value(t,
        actual_plan.candidate.frame_index, expected_plan.candidate.frame_index)
    actual_plan = playback_plan(actual_plan.candidate, actual, 50_000_100)
    expected_plan = playback_plan(expected_plan.candidate, expected, 50_000_100)
    testing.expect_value(t,
        actual_plan.candidate.frame_index, expected_plan.candidate.frame_index)
    testing.expect_value(t,
        actual_plan.candidate.completed_cycles,
        expected_plan.candidate.completed_cycles)
}

// Return small fixed limits for headless graphics-service ownership tests.
service_test_limits :: proc() -> termattachment.Limits {
    return {
        attachment_capacity = 2,
        placement_capacity = 2,
        transfer_capacity = 2,
        transfer_byte_limit = 128,
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

// Verify one stale completion released all transfer and attachment ownership.
service_test_expect_stale_release :: proc(
    t: ^testing.T, service: ^Service, store: ^termattachment.Store) {
    testing.expect_value(t, service.stale_completion_count, u64(1))
    testing.expect_value(t, store.attachment_count, 0)
    testing.expect_value(t, store.transfer_count, 0)
}

// Initialize the four owners shared by headless graphics service tests.
service_test_init :: proc(
    t: ^testing.T, store: ^termattachment.Store,
    parser: ^gfxprotocol.Graphics_Parser_State, service: ^Service,
    pool: ^taskpool.Task_Pool) {
    testing.expect(t, termattachment.store_init(
        store, service_test_limits(), context.allocator))
    testing.expect(t, gfxprotocol.graphics_parser_init(parser, store))
    testing.expect(t, service_bind_session(
        service, 1, parser, store, nil))
    testing.expect(t, taskpool.task_pool_init(pool, 1, 1))
}

// Destroy the owners shared by headless graphics service tests.
service_test_destroy :: proc(
    store: ^termattachment.Store, parser: ^gfxprotocol.Graphics_Parser_State,
    pool: ^taskpool.Task_Pool) {
    taskpool.task_pool_destroy(pool)
    gfxprotocol.graphics_parser_destroy(parser)
    termattachment.store_destroy(store)
}

// Reserve and prepare one Sixel decode operation over copied transfer input.
service_test_prepare_sixel_operation :: proc(
    t: ^testing.T, service: ^Service, store: ^termattachment.Store,
    sixel: string) -> Operation {
    transfer, outcome := termattachment.transfer_begin(store, .Sixel, len(sixel))
    testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
    testing.expect_value(t, termattachment.transfer_append(
        store, transfer, transmute([]u8)sixel),
        termattachment.Admission_Outcome.Admitted)
    attachment, attachment_outcome := termattachment.attachment_reserve(store, {
        metadata = {kind = .Raster, origin = .Sixel, metrics = {width = 1, height = 1}},
        payload_byte_count = 4, payload_format = .Rgba8, payload_stride = 4,
    })
    testing.expect_value(t,
        attachment_outcome, termattachment.Admission_Outcome.Admitted)
    operation := Operation{state = .Retry, decode = {
        kind = .Sixel, transfer_id = transfer, attachment_id = attachment,
        width = 1, height = 1,
    }}
    testing.expect(t, operation_prepare(service, &operation))
    return operation
}

// Reserve and bind one animated GIF operation over copied transfer input.
service_test_prepare_animated_operation :: proc(
    t: ^testing.T, service: ^Service, store: ^termattachment.Store) -> Operation {
    bytes := GRAPHICS_SERVICE_TEST_ANIMATED_GIF
    transfer, outcome := termattachment.transfer_begin(
        store, .Iterm2, len(bytes))
    testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
    testing.expect_value(t, termattachment.transfer_append(
        store, transfer, bytes[:]),
        termattachment.Admission_Outcome.Admitted)
    attachment, attachment_outcome := termattachment.animation_reserve(store, {
        metadata = {
            kind = .Raster,
            origin = .Iterm2,
            metrics = {width = 2, height = 1},
        },
        frame_count = 2,
        payload_byte_count = 16,
        temporary_decode_byte_count = 24,
        repeat_count = 2,
    })
    testing.expect_value(t,
        attachment_outcome, termattachment.Admission_Outcome.Admitted)
    operation := Operation{state = .Retry, decode = {
        kind = .Iterm2_Animated_Gif,
        transfer_id = transfer,
        attachment_id = attachment,
        width = 2,
        height = 1,
    }}
    operation.preflight.inspection =
        termgraphicsprepare.inspect_gif_animation(
            bytes[:], termgraphicsprepare.gif_animation_limits(store.limits))
    testing.expect(t, operation_prepare(service, &operation))
    return operation
}

// Queue one zero-attachment iTerm2 GIF preflight request.
service_test_queue_gif_preflight :: proc(
    t: ^testing.T, store: ^termattachment.Store,
    parser: ^gfxprotocol.Graphics_Parser_State, bytes: []u8,
    producer: termmodel.Terminal_Producer = {}) -> termattachment.Transfer_Id {
    transfer, outcome := termattachment.transfer_begin(
        store, .Iterm2, len(bytes))
    testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
    testing.expect_value(t, termattachment.transfer_append(store, transfer, bytes),
        termattachment.Admission_Outcome.Admitted)
    testing.expect(t, gfxprotocol.graphics_parser_queue_decode_request(parser, {
        kind = .Iterm2_Gif_Preflight,
        producer = producer,
        transfer_id = transfer,
        width = 2,
        height = 1,
    }))
    return transfer
}

// Verify joined preflight reserves an exact hidden animation then reuses the slot.
@(test)
service_test_gif_preflight_transitions_to_decode :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    bytes := GRAPHICS_SERVICE_TEST_ANIMATED_GIF
    service_test_queue_gif_preflight(t, &store, &parser, bytes[:])

    operation_intake(&service)
    operation := &service.operations[0]
    testing.expect_value(t, operation.state, Operation_State.Preflight_Retry)
    testing.expect_value(t, store.attachment_count, 0)
    testing.expect_value(t,
        gif_preflight_task_execute(&operation.preflight, {}),
        taskpool.Task_Result.Succeeded)
    operation_preflight_finish(&service, operation, .Succeeded, .Joined)

    testing.expect_value(t, operation.state, Operation_State.Retry)
    testing.expect_value(t, operation.decode.kind,
        gfxprotocol.Graphics_Decode_Kind.Iterm2_Animated_Gif)
    testing.expect_value(t, store.attachment_count, 1)
    _, visible_before_publish := termattachment.animation_view(
        &store, operation.decode.attachment_id)
    testing.expect(t, !visible_before_publish)
    testing.expect_value(t,
        prepare_task_execute(&operation.task, {}), taskpool.Task_Result.Succeeded)
    operation_discard(&service, operation)
}

// Verify single-frame GIF preflight selects the ordinary static decode path.
@(test)
service_test_gif_preflight_selects_static_target :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    bytes := GRAPHICS_SERVICE_TEST_STATIC_GIF
    service_test_queue_gif_preflight(t, &store, &parser, bytes[:])

    operation_intake(&service)
    operation := &service.operations[0]
    testing.expect_value(t,
        gif_preflight_task_execute(&operation.preflight, {}),
        taskpool.Task_Result.Succeeded)
    operation_preflight_finish(&service, operation, .Succeeded, .Joined)

    testing.expect_value(t, operation.decode.kind,
        gfxprotocol.Graphics_Decode_Kind.Iterm2_Image)
    testing.expect_value(t, store.attachment_count, 1)
    operation_discard(&service, operation)
}

// Verify malformed GIF preflight releases transfer ownership without reservation.
@(test)
service_test_gif_preflight_rejection_releases_input :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    bytes := GRAPHICS_SERVICE_TEST_ANIMATED_GIF
    service_test_queue_gif_preflight(
        t, &store, &parser, bytes[:len(bytes) - 1])

    operation_intake(&service)
    operation := &service.operations[0]
    testing.expect_value(t,
        gif_preflight_task_execute(&operation.preflight, {}),
        taskpool.Task_Result.Failed)
    operation_preflight_finish(&service, operation, .Failed, .Joined)

    testing.expect_value(t, operation.state, Operation_State.Idle)
    testing.expect_value(t, store.attachment_count, 0)
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect_value(t, parser.gif_preflight_rejection_count, u64(1))
}

// Verify producer cancellation discards retrying preflight before target reservation.
@(test)
service_test_cancel_gif_preflight_before_reservation :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    producer := termmodel.Terminal_Producer{
        kind = .Terminal_Session, id = 7, generation = 3,
    }
    bytes := GRAPHICS_SERVICE_TEST_ANIMATED_GIF
    service_test_queue_gif_preflight(
        t, &store, &parser, bytes[:], producer)
    operation_intake(&service)

    service_cancel_producer(&service, &pool, producer)

    testing.expect_value(t, service.operations[0].state, Operation_State.Idle)
    testing.expect_value(t, store.attachment_count, 0)
    testing.expect_value(t, store.transfer_count, 0)
}

// Verify publication evidence carries the exact attachment identity and dimensions.
@(test)
service_test_records_raster_publication :: proc(t: ^testing.T) {
    store: termattachment.Store
    testing.expect(t, termattachment.store_init(
        &store, service_test_limits(), context.allocator))
    defer termattachment.store_destroy(&store)
    attachment, outcome := termattachment.attachment_reserve(&store, {
        metadata = {
            kind = .Raster,
            origin = .Sixel,
            metrics = {width = 2, height = 1},
        },
        payload_byte_count = 8,
        payload_format = .Rgba8,
        payload_stride = 8,
    })
    testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
    testing.expect_value(t,
        termattachment.attachment_preparation_publish(&store, attachment),
        termattachment.Handle_Outcome.Found)
    ring: trace.Ring
    trace.ring_init(&ring, .Display)
    service := Service{store = &store, trace_ring = &ring}

    service_record_publication(&service, attachment)

    events: [1]trace.Event
    testing.expect_value(t, trace.ring_drain(&ring, events[:]), 1)
    event := events[0]
    testing.expect_value(t, event.kind, trace.Kind.Terminal_Raster_Published)
    testing.expect_value(t, event.correlation, u64(attachment.slot))
    testing.expect_value(t, event.generation, attachment.generation)
    testing.expect_value(t, event.correlation_kind, trace.Correlation_Kind.Attachment)
    testing.expect_value(t, event.payload.counts.first, u32(2))
    testing.expect_value(t, event.payload.counts.second, u32(1))
}

// Verify delete during task ownership rejects publication only after a successful join.
@(test)
service_test_stale_decode_completion :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    operation := service_test_prepare_sixel_operation(
        t, &service, &store, "@")
    handle, submit_outcome := taskpool.task_pool_submit(
        &pool, prepare_task_execute, &operation.task)
    testing.expect_value(t, submit_outcome, taskpool.Task_Submit_Outcome.Queued)
    operation.handle = handle
    operation.state = .Queued
    testing.expect_value(t,
        termattachment.attachment_remove(&store, operation.decode.attachment_id),
        termattachment.Handle_Outcome.Stale)

    result, joined := taskpool.task_pool_wait(&pool, handle)
    operation_finish(&service, &operation, result, joined)

    service_test_expect_stale_release(t, &service, &store)
}

// Verify a removed animated generation is decoded, joined, and discarded atomically.
@(test)
service_test_stale_animated_gif_completion :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    operation := service_test_prepare_animated_operation(t, &service, &store)
    handle, submit_outcome := taskpool.task_pool_submit(
        &pool, prepare_task_execute, &operation.task)
    testing.expect_value(t, submit_outcome, taskpool.Task_Submit_Outcome.Queued)
    operation.handle = handle
    operation.state = .Queued
    testing.expect_value(t,
        termattachment.attachment_remove(&store, operation.decode.attachment_id),
        termattachment.Handle_Outcome.Stale)

    result, joined := taskpool.task_pool_wait(&pool, handle)
    operation_finish(&service, &operation, result, joined)

    service_test_expect_stale_release(t, &service, &store)
    testing.expect_value(t, store.animation_decode_byte_count, 0)
}

// Publish one resident raster generation for producer-cancellation tests.
service_test_publish_resident :: proc(
    t: ^testing.T, store: ^termattachment.Store) -> termattachment.Attachment_Id {
    resident, outcome := termattachment.attachment_reserve(store, {
        metadata = {
            kind = .Raster, origin = .Sixel,
            metrics = {width = 1, height = 1},
        },
        payload_byte_count = 4, payload_format = .Rgba8, payload_stride = 4,
    })
    testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
    testing.expect_value(t,
        termattachment.attachment_preparation_publish(store, resident),
        termattachment.Handle_Outcome.Found)
    testing.expect_value(t,
        termattachment.residency_admit(store, resident, 4).outcome,
        termattachment.Admission_Outcome.Admitted)
    return resident
}

// Verify cancelling queued image work preserves the last resident generation.
@(test)
service_test_cancel_producer_preserves_resident :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    resident := service_test_publish_resident(t, &store)

    producer := termmodel.Terminal_Producer{.Terminal_Session, 7, 3}
    operation := &service.operations[0]
    operation^ = service_test_prepare_sixel_operation(
        t, &service, &store, "@")
    operation.decode.producer = producer
    operation.decode.kind = .Iterm2_Image
    handle, outcome := taskpool.task_pool_submit(
        &pool, prepare_task_execute, &operation.task)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    operation.handle = handle
    operation.state = .Queued

    service_cancel_producer(&service, &pool, producer)
    result, joined := taskpool.task_pool_wait(&pool, handle)
    testing.expect_value(t, result, taskpool.Task_Result.Cancelled)
    operation_finish(&service, operation, result, joined)

    testing.expect_value(t, service.cancellation_count, u64(1))
    testing.expect_value(t, store.attachment_count, 1)
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect(t, termattachment.residency_entry(&store, resident) != nil)
    testing.expect_value(t, store.gpu_byte_count, 4)
}

// Verify producer cancellation filters mixed-kind requests without disturbing order.
@(test)
service_test_cancel_producer_filters_parser_queue :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    cancelled := termmodel.Terminal_Producer{.Terminal_Session, 7, 3}
    retained := termmodel.Terminal_Producer{.Terminal_Session, 8, 1}
    first := service_test_prepare_animated_operation(t, &service, &store)
    second := service_test_prepare_sixel_operation(t, &service, &store, "A")
    first.decode.producer = cancelled
    second.decode.producer = retained
    testing.expect(t, gfxprotocol.graphics_parser_queue_decode_request(
        &parser, first.decode))
    testing.expect(t, gfxprotocol.graphics_parser_queue_decode_request(
        &parser, second.decode))

    service_cancel_producer(&service, &pool, cancelled)

    request, available := gfxprotocol.graphics_parser_take_decode_request(&parser)
    testing.expect(t, available)
    testing.expect_value(t, request.producer, retained)
    _, extra := gfxprotocol.graphics_parser_take_decode_request(&parser)
    testing.expect(t, !extra)
    testing.expect_value(t, store.attachment_count, 1)
    testing.expect_value(t, store.transfer_count, 1)
    operation := Operation{decode = request}
    operation_discard(&service, &operation)
}

// Verify producer cancellation discards retry work but retains unrelated operations.
@(test)
service_test_cancel_producer_filters_retry_operations :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    cancelled := termmodel.Terminal_Producer{.Terminal_Session, 7, 3}
    retained := termmodel.Terminal_Producer{.Terminal_Session, 8, 1}
    service.operations[0] = service_test_prepare_sixel_operation(
        t, &service, &store, "@")
    service.operations[1] = service_test_prepare_sixel_operation(
        t, &service, &store, "A")
    service.operations[0].decode.producer = cancelled
    service.operations[0].decode.kind = .Kitty_Zlib_Rgba
    service.operations[1].decode.producer = retained

    service_cancel_producer(&service, &pool, cancelled)

    testing.expect_value(t, service.operations[0].state, Operation_State.Idle)
    testing.expect_value(t, service.operations[1].state, Operation_State.Retry)
    testing.expect_value(t, store.attachment_count, 1)
    testing.expect_value(t, store.transfer_count, 1)
    operation_discard(&service, &service.operations[1])
    service.operations[1] = {}
}

// Verify joined animated work atomically publishes exact normalized timeline data.
@(test)
service_test_publishes_animated_gif_preparation :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    operation := service_test_prepare_animated_operation(t, &service, &store)
    handle, submit_outcome := taskpool.task_pool_submit(
        &pool, prepare_task_execute, &operation.task)
    testing.expect_value(t, submit_outcome, taskpool.Task_Submit_Outcome.Queued)
    result, joined := taskpool.task_pool_wait(&pool, handle)
    testing.expect_value(t, joined, taskpool.Task_Join_Outcome.Joined)
    testing.expect_value(t, result, taskpool.Task_Result.Succeeded)
    testing.expect_value(t,
        termattachment.transfer_remove(&store, operation.decode.transfer_id),
        termattachment.Handle_Outcome.Found)

    testing.expect_value(t,
        operation_preparation_publish(&service, operation.decode),
        termattachment.Handle_Outcome.Found)

    animation, visible := termattachment.animation_view(
        &store, operation.decode.attachment_id)
    testing.expect(t, visible)
    testing.expect_value(t, animation.timeline.frame_count, 2)
    testing.expect_value(t, animation.timeline.cycle_duration_ns, u64(50_000_000))
    testing.expect_value(t, animation.timeline.repeat_count, u32(2))
    testing.expect_value(t, animation.pixels[0], u8(255))
    testing.expect_value(t, animation.pixels[8], u8(0))
    testing.expect_value(t, animation.pixels[9], u8(255))
    testing.expect_value(t, store.animation_decode_byte_count, 0)
}

// Build the Kitty timeline equivalent of the two-frame GIF fixture.
service_test_build_kitty_parity_animation :: proc(
    t: ^testing.T,
    store: ^termattachment.Store,
    encoded: termattachment.Animation_View) -> termattachment.Attachment_Id {
    kitty_id, outcome := termattachment.attachment_admit(store, {
        metadata = {
            kind = .Raster,
            origin = .Kitty,
            metrics = {width = 2, height = 1},
        },
        payload = encoded.pixels[:8],
        payload_format = .Rgba8,
        payload_stride = 8,
        protocol_retained = true,
    })
    testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
    testing.expect_value(t, termattachment.kitty_animation_mutate_frame(
        store, kitty_id, {
            pixels = encoded.pixels[8:16],
            format = .Rgba8,
            width = 2,
            height = 1,
            gap_ms = 30,
            gap_specified = true,
            overwrite = true,
        }), termattachment.Animation_Mutation_Outcome.Found)
    testing.expect_value(t, termattachment.kitty_animation_control(
        store, kitty_id, {
            frame_number = 1, gap_ms = 20,
            gap_specified = true, loop_count = 3,
        }),
        termattachment.Animation_Mutation_Outcome.Found)
    return kitty_id
}

// Verify equivalent GIF and Kitty timelines normalize to identical playback data.
@(test)
service_test_gif_kitty_timeline_parity :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    operation := service_test_prepare_animated_operation(t, &service, &store)
    testing.expect_value(t,
        prepare_task_execute(&operation.task, {}), taskpool.Task_Result.Succeeded)
    testing.expect_value(t, termattachment.transfer_remove(
        &store, operation.decode.transfer_id), termattachment.Handle_Outcome.Found)
    testing.expect_value(t,
        operation_preparation_publish(&service, operation.decode),
        termattachment.Handle_Outcome.Found)
    encoded, encoded_found := termattachment.animation_view(
        &store, operation.decode.attachment_id)
    testing.expect(t, encoded_found)
    kitty_id := service_test_build_kitty_parity_animation(t, &store, encoded)
    kitty, kitty_found := termattachment.animation_view(&store, kitty_id)
    testing.expect(t, kitty_found)

    service_test_expect_animation_parity(t, kitty_id, kitty,
        operation.decode.attachment_id, encoded)
}

// Verify shutdown joins queued decode work and releases all nonresident ownership.
@(test)
service_test_shutdown_joins_pending_decode :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    operation := &service.operations[0]
    operation^ = service_test_prepare_sixel_operation(
        t, &service, &store, "!0~")
    handle, submit_outcome := taskpool.task_pool_submit(
        &pool, prepare_task_execute, &operation.task)
    testing.expect_value(t, submit_outcome, taskpool.Task_Submit_Outcome.Queued)
    operation.handle = handle
    operation.state = .Queued
    service.playbacks[0] = {
        attachment_id = operation.decode.attachment_id,
        active = true,
    }
    service.visibility_epoch = 7

    service_shutdown(&service, &pool)

    testing.expect_value(t, service.failure_count, u64(0))
    testing.expect_value(t, service.publication_count, u64(0))
    testing.expect_value(t, store.attachment_count, 0)
    testing.expect_value(t, store.transfer_count, 0)
    testing.expect(t, service.store == nil)
    testing.expect(t, !service.playbacks[0].active)
    testing.expect_value(t, service.visibility_epoch, u64(0))
}

// Verify an outer-session mismatch returns before touching terminal-owned bytes.
@(test)
service_test_rejects_stale_session_completion :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    operation := service_test_prepare_sixel_operation(t, &service, &store, "@")
    decode := operation.decode
    service.session_generation = 2

    operation_finish(&service, &operation, .Succeeded, .Joined)

    testing.expect_value(t, service.stale_completion_count, u64(1))
    testing.expect_value(t, store.attachment_count, 1)
    testing.expect_value(t, store.transfer_count, 1)
    testing.expect_value(t,
        termattachment.transfer_remove(&store, decode.transfer_id),
        termattachment.Handle_Outcome.Found)
    gfxprotocol.graphics_discard_pending_attachment(
        &parser, decode.attachment_id)
}

// Verify queued work is discarded before rebinding the reusable service.
@(test)
service_test_unbind_joins_and_rebinds_next_generation :: proc(t: ^testing.T) {
    first_store, second_store: termattachment.Store
    first_parser, second_parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &first_store, &first_parser, &service, &pool)
    defer taskpool.task_pool_destroy(&pool)
    operation := &service.operations[0]
    operation^ = service_test_prepare_sixel_operation(
        t, &service, &first_store, "@")
    handle, outcome := taskpool.task_pool_submit(
        &pool, prepare_task_execute, &operation.task)
    testing.expect_value(t, outcome, taskpool.Task_Submit_Outcome.Queued)
    operation.handle = handle
    operation.state = .Queued

    service_unbind_session(&service, &pool)

    testing.expect_value(t, first_store.attachment_count, 0)
    testing.expect_value(t, first_store.transfer_count, 0)
    testing.expect(t, service.parser == nil)
    testing.expect(t, service.store == nil)
    testing.expect_value(t, service.session_generation, u64(0))
    gfxprotocol.graphics_parser_destroy(&first_parser)
    termattachment.store_destroy(&first_store)

    testing.expect(t, termattachment.store_init(
        &second_store, service_test_limits(), context.allocator))
    defer termattachment.store_destroy(&second_store)
    testing.expect(t, gfxprotocol.graphics_parser_init(&second_parser, &second_store))
    defer gfxprotocol.graphics_parser_destroy(&second_parser)
    testing.expect(t, service_bind_session(
        &service, 8, &second_parser, &second_store, nil))
    testing.expect_value(t, service.session_generation, u64(8))
    service_unbind_session(&service, &pool)
}

// Verify permanent application shutdown prevents future session binding.
@(test)
service_test_shutdown_rejects_rebind :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)

    service_shutdown(&service, &pool)

    testing.expect(t, service.stopped)
    testing.expect(t, !service_bind_session(
        &service, 2, &parser, &store, nil))
}

// Admit and identify one retained Kitty root for mutation-order tests.
service_test_kitty_root :: proc(
    t: ^testing.T, store: ^termattachment.Store,
    parser: ^gfxprotocol.Graphics_Parser_State) -> termattachment.Attachment_Id {
    root := [4]u8{255, 0, 0, 255}
    id, outcome := termattachment.attachment_admit(store, {
        metadata = {
            kind = .Raster,
            origin = .Kitty,
            metrics = {width = 1, height = 1},
        },
        payload = root[:],
        payload_format = .Rgba8,
        payload_stride = 4,
        protocol_retained = true,
    })
    testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
    parser.kitty_images[0] = {
        image_id = 9,
        attachment_id = id,
        active = true,
    }
    return id
}

// Reserve one anonymous PNG output and its encoded input transfer.
service_test_kitty_png_input :: proc(
    t: ^testing.T, store: ^termattachment.Store) ->
    (termattachment.Attachment_Id, termattachment.Transfer_Id) {
    temporary, temporary_outcome := termattachment.attachment_reserve(store, {
        metadata = {
            kind = .Raster,
            origin = .Kitty,
            metrics = {width = 1, height = 1},
        },
        payload_byte_count = 4,
        payload_format = .Rgba8,
        payload_stride = 4,
    })
    testing.expect_value(t,
        temporary_outcome, termattachment.Admission_Outcome.Admitted)
    png := GRAPHICS_SERVICE_TEST_PNG
    transfer, transfer_outcome := termattachment.transfer_begin(
        store, .Kitty, len(png))
    testing.expect_value(t,
        transfer_outcome, termattachment.Admission_Outcome.Admitted)
    testing.expect_value(t, termattachment.transfer_append(
        store, transfer, png[:]), termattachment.Admission_Outcome.Admitted)
    return temporary, transfer
}

// Retain one encoded frame and following control for display ordering tests.
service_test_queue_kitty_mutations :: proc(
    t: ^testing.T, store: ^termattachment.Store,
    parser: ^gfxprotocol.Graphics_Parser_State) -> termattachment.Attachment_Id {
    id := service_test_kitty_root(t, store, parser)
    temporary, transfer := service_test_kitty_png_input(t, store)
    sequence, queued := gfxprotocol.graphics_parser_queue_mutation_request(
        parser, {
            attachment_id = id,
            temporary_attachment_id = temporary,
            controls = {image_id = 9, format = 32, width = 1, height = 1},
            kind = .Frame,
        })
    testing.expect(t, queued)
    _, queued = gfxprotocol.graphics_parser_queue_mutation_request(parser, {
        attachment_id = id,
        controls = {image_id = 9, animation_state = 3, current_frame = 2},
        kind = .Control,
        ready = true,
    })
    testing.expect(t, queued)
    testing.expect(t, gfxprotocol.graphics_parser_queue_decode_request(parser, {
        kind = .Kitty_Png,
        transfer_id = transfer,
        attachment_id = temporary,
        mutation_sequence = sequence,
        width = 1,
        height = 1,
    }))
    return id
}

// Verify encoded preparation commits its frame before a retained following control.
@(test)
service_test_kitty_encoded_mutation_order :: proc(t: ^testing.T) {
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    service_test_init(t, &store, &parser, &service, &pool)
    defer service_test_destroy(&store, &parser, &pool)
    id := service_test_queue_kitty_mutations(t, &store, &parser)

    operation_intake(&service)
    operation := &service.operations[0]
    testing.expect_value(t,
        prepare_task_execute(&operation.task, {}), taskpool.Task_Result.Succeeded)
    operation_finish(
        &service, operation, .Succeeded, .Joined)
    operation_apply_mutations(&service)

    animation, found := termattachment.animation_view(&store, id)
    testing.expect(t, found)
    testing.expect_value(t, animation.timeline.frame_count, 2)
    refresh, present := gfxprotocol.graphics_parser_take_animation_command(&parser)
    testing.expect(t, present)
    testing.expect_value(t,
        refresh.kind, gfxprotocol.Kitty_Animation_Command_Kind.Refresh)
    control: gfxprotocol.Kitty_Animation_Command
    control, present = gfxprotocol.graphics_parser_take_animation_command(&parser)
    testing.expect(t, present)
    testing.expect_value(t,
        control.kind, gfxprotocol.Kitty_Animation_Command_Kind.Control)
    testing.expect_value(t, control.current_frame, 2)
    testing.expect_value(t, store.attachment_count, 1)
    testing.expect_value(t, store.transfer_count, 0)
}

// Admit and install one replacement Kitty root generation.
service_test_replace_kitty_root :: proc(
    t: ^testing.T, store: ^termattachment.Store,
    parser: ^gfxprotocol.Graphics_Parser_State,
    old_id: termattachment.Attachment_Id) -> termattachment.Attachment_Id {
    replacement := [4]u8{1, 2, 3, 255}
    new_id, outcome := termattachment.attachment_admit(store, {
        metadata = {
            kind = .Raster, origin = .Kitty,
            metrics = {width = 1, height = 1},
        },
        payload = replacement[:], payload_format = .Rgba8,
        payload_stride = 4, protocol_retained = true,
    })
    testing.expect_value(t, outcome, termattachment.Admission_Outcome.Admitted)
    gfxprotocol.graphics_discard_attachment(parser, old_id)
    parser.kitty_images[0] = {
        image_id = 9, attachment_id = new_id, active = true,
    }
    return new_id
}

// Verify root replacement makes prepared old-generation mutations stale.
@(test)
service_test_kitty_replacement_invalidates_mutations :: proc(t: ^testing.T) {
    limits := service_test_limits()
    limits.attachment_capacity = 3
    store: termattachment.Store
    parser: gfxprotocol.Graphics_Parser_State
    service: Service
    pool: taskpool.Task_Pool
    testing.expect(t, termattachment.store_init(
        &store, limits, context.allocator))
    testing.expect(t, gfxprotocol.graphics_parser_init(&parser, &store))
    testing.expect(t, service_bind_session(&service, 1, &parser, &store, nil))
    testing.expect(t, taskpool.task_pool_init(&pool, 1, 1))
    defer service_test_destroy(&store, &parser, &pool)
    old_id := service_test_queue_kitty_mutations(t, &store, &parser)
    new_id := service_test_replace_kitty_root(t, &store, &parser, old_id)

    operation_intake(&service)
    operation := &service.operations[0]
    testing.expect_value(t,
        prepare_task_execute(&operation.task, {}), taskpool.Task_Result.Succeeded)
    operation_finish(&service, operation, .Succeeded, .Joined)
    operation_apply_mutations(&service)

    payload, found := termattachment.attachment_payload(&store, new_id)
    testing.expect(t, found)
    testing.expect_value(t, payload.bytes[0], u8(1))
    testing.expect_value(t, parser.kitty_mutation_request_count, 0)
    testing.expect_value(t, parser.kitty_animation_command_count, 0)
}