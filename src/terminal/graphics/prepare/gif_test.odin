#+test
package termgraphicsprepare

import "../../../taskpool"
import termattachment "../../attachment"
import termgraphicsnative "../native"

import "core:sync"
import "core:testing"

// Compact two-frame GIF89a with red/green canvases, 20/30 ms delays, and two repeats.
GRAPHICS_TEST_ANIMATED_GIF :: [109]u8{
    71, 73, 70, 56, 57, 97, 2, 0, 1, 0, 129, 0, 0, 255, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 33, 255, 11, 78, 69, 84, 83,
    67, 65, 80, 69, 50, 46, 48, 3, 1, 2, 0, 0, 33, 249, 4, 8,
    2, 0, 0, 0, 44, 0, 0, 0, 0, 2, 0, 1, 0, 0, 8, 5,
    0, 1, 0, 8, 8, 0, 33, 249, 4, 8, 3, 0, 0, 0, 44, 0,
    0, 0, 0, 2, 0, 1, 0, 129, 0, 255, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 8, 5, 0, 1, 0, 8, 8, 0, 59,
}

// Gif_Decode_Cancellation deterministically cancels at one native poll.
Gif_Decode_Cancellation :: struct {
    calls: int,
    cancel_at: int,
}

// Gif_Concurrent_Gate holds workers after both decoder objects are open.
Gif_Concurrent_Gate :: struct {
    mutex: sync.Mutex,
    changed: sync.Cond,
    decoder_count: int,
}

// Gif_Concurrent_Payload owns disjoint output for one worker decode.
Gif_Concurrent_Payload :: struct {
    gate: ^Gif_Concurrent_Gate,
    callback_count: int,
    pixels: [16]u8,
    valid: bool,
}

// Cancel one native decode at the configured polling boundary.
graphics_test_gif_cancel_at_poll :: proc(user_data: rawptr) -> bool {
    state := cast(^Gif_Decode_Cancellation)user_data
    state.calls += 1
    return state.calls >= state.cancel_at
}

// Hold each worker at its first frame until both decoder objects are live.
graphics_test_gif_concurrent_barrier :: proc(user_data: rawptr) -> bool {
    payload := cast(^Gif_Concurrent_Payload)user_data
    payload.callback_count += 1
    if payload.callback_count != 2 {return false}
    sync.mutex_lock(&payload.gate.mutex)
    payload.gate.decoder_count += 1
    sync.cond_broadcast(&payload.gate.changed)
    for payload.gate.decoder_count < 2 {
        sync.cond_wait(&payload.gate.changed, &payload.gate.mutex)
    }
    sync.mutex_unlock(&payload.gate.mutex)
    return false
}

// Decode one GIF through an independently owned SDL_image worker object.
graphics_test_gif_concurrent_task :: proc(
    raw_payload: rawptr, _: taskpool.Task_Cancellation_Token) -> taskpool.Task_Result {
    payload := cast(^Gif_Concurrent_Payload)raw_payload
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    result := termgraphicsnative.decode_animated_gif(&{
        bytes = bytes[:],
        frame_bytes = payload.pixels[:],
        width = 2,
        height = 1,
        frame_count = 2,
        cancellation_user_data = payload,
        cancellation_requested = graphics_test_gif_concurrent_barrier,
    })
    payload.valid = result.complete && result.frame_count == 2
    return .Succeeded if payload.valid else .Failed
}

// Set one Graphic Control Extension delay in a mutable GIF fixture.
graphics_test_set_gif_delay :: proc(bytes: []u8, occurrence, delay_cs: int) -> bool {
    found := 0
    for index in 0..<len(bytes) - 7 {
        if bytes[index] != 0x21 || bytes[index + 1] != 0xf9 ||
           bytes[index + 2] != 4 {
            continue
        }
        if found == occurrence {
            bytes[index + 4] = u8(delay_cs & 0xff)
            bytes[index + 5] = u8((delay_cs >> 8) & 0xff)
            return true
        }
        found += 1
    }
    return false
}

// Return bounded limits suitable for the animated GIF evidence fixture.
graphics_test_gif_limits :: proc() -> Gif_Animation_Limits {
    return {
        encoded_byte_limit = 1024,
        dimension_limit = 16,
        image_pixel_limit = 256,
        frame_limit = 8,
        decoded_byte_limit = 4096,
        peak_byte_limit = 4096,
        min_frame_duration_ns = 10_000_000,
        max_frame_duration_ns = 1_000_000_000,
        duration_ns_limit = 10_000_000_000,
    }
}

// Verify preflight recovers exact dimensions, frame count, delays, and loop metadata.
@(test)
graphics_test_inspect_animated_gif :: proc(t: ^testing.T) {
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    result := inspect_gif_animation(bytes[:], graphics_test_gif_limits())
    testing.expect(t, result.valid)
    testing.expect_value(t, result.width, 2)
    testing.expect_value(t, result.height, 1)
    testing.expect_value(t, result.frame_count, 2)
    testing.expect_value(t, result.decoded_byte_count, 16)
    testing.expect_value(t, result.temporary_decode_byte_count, 24)
    testing.expect_value(t, result.peak_byte_count, 149)
    testing.expect_value(t, result.total_duration_ns, u64(50_000_000))
    testing.expect_value(t, result.repeat_count, 2)
    testing.expect(t, result.has_loop_extension)
    testing.expect(t, !result.infinite)
}

// Verify SDL_image returns exact composited canvases with authoritative encoded timing.
@(test)
graphics_test_decode_animated_gif :: proc(t: ^testing.T) {
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    frames: [16]u8
    descriptors: [2]termattachment.Animation_Frame
    result, decoded := decode_gif_animation(
        bytes[:], graphics_test_gif_limits(), {
            frame_bytes = frames[:], frames = descriptors[:],
        },
        termattachment.limits_default())
    testing.expect(t, decoded)
    testing.expect(t, result.valid)
    testing.expect_value(t, descriptors[0].pixels,
        termattachment.Payload_Range{offset = 0, count = 8})
    testing.expect_value(t, descriptors[0].duration_ns, u64(20_000_000))
    testing.expect_value(t, descriptors[1].pixels,
        termattachment.Payload_Range{offset = 8, count = 8})
    testing.expect_value(t, descriptors[1].duration_ns, u64(30_000_000))
    testing.expect_value(t, frames, [16]u8{
        255, 0, 0, 255, 255, 0, 0, 255,
        0, 255, 0, 255, 0, 255, 0, 255,
    })
}

// Verify transparency and restore-background disposal produce explicit canvases.
@(test)
graphics_test_decode_animated_gif_transparency_and_disposal :: proc(t: ^testing.T) {
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    bytes[47] |= 1
    bytes[51] = 0
    pixels: [16]u8
    frames: [2]termattachment.Animation_Frame
    _, decoded := decode_gif_animation(
        bytes[:], graphics_test_gif_limits(), {
            frame_bytes = pixels[:], frames = frames[:],
        }, termattachment.limits_default())
    testing.expect(t, decoded)
    testing.expect_value(t, pixels, [16]u8{
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 255, 0, 255, 0, 255, 0, 255,
    })
}

// Verify Euclid normalizes encoded zero delays independently of decoder timing.
@(test)
graphics_test_decode_animated_gif_normalizes_zero_delays :: proc(t: ^testing.T) {
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    testing.expect(t, graphics_test_set_gif_delay(bytes[:], 0, 0))
    testing.expect(t, graphics_test_set_gif_delay(bytes[:], 1, 0))
    pixels: [16]u8
    frames: [2]termattachment.Animation_Frame
    _, decoded := decode_gif_animation(
        bytes[:], graphics_test_gif_limits(), {
            frame_bytes = pixels[:], frames = frames[:],
        }, termattachment.limits_default())
    testing.expect(t, decoded)
    testing.expect_value(t, frames[0].pixels,
        termattachment.Payload_Range{offset = 0, count = 8})
    testing.expect_value(t, frames[1].pixels,
        termattachment.Payload_Range{offset = 8, count = 8})
    testing.expect_value(t, frames[0].duration_ns, u64(10_000_000))
    testing.expect_value(t, frames[1].duration_ns, u64(10_000_000))
}

// Verify native cancellation after frame one bounds output to one copied canvas.
@(test)
graphics_test_decode_animated_gif_cancels_between_frames :: proc(t: ^testing.T) {
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    pixels: [16]u8
    cancellation := Gif_Decode_Cancellation{cancel_at = 3}
    result := termgraphicsnative.decode_animated_gif(&{
        bytes = bytes[:], frame_bytes = pixels[:],
        width = 2, height = 1, frame_count = 2,
        cancellation_user_data = &cancellation,
        cancellation_requested = graphics_test_gif_cancel_at_poll,
    })
    testing.expect(t, !result.complete)
    testing.expect_value(t, result.frame_count, 0)
    testing.expect_value(t, pixels[0], u8(255))
    testing.expect_value(t, pixels[8], u8(0))
}

// Verify finite and infinite loop metadata remains authoritative during decode.
@(test)
graphics_test_decode_animated_gif_preserves_loop_metadata :: proc(t: ^testing.T) {
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    bytes[41] = 0
    bytes[42] = 0
    inspection := inspect_gif_animation(bytes[:], graphics_test_gif_limits())
    testing.expect(t, inspection.valid && inspection.infinite)
    pixels: [16]u8
    frames: [2]termattachment.Animation_Frame
    decoded_inspection, decoded := decode_gif_animation(
        bytes[:], graphics_test_gif_limits(), {
            frame_bytes = pixels[:], frames = frames[:],
        }, termattachment.limits_default())
    testing.expect(t, decoded)
    testing.expect(t, decoded_inspection.infinite)
    testing.expect_value(t, decoded_inspection.repeat_count, 0)
}

// Verify two worker jobs hold independent SDL_image decoder objects concurrently.
@(test)
graphics_test_decode_animated_gif_supports_concurrent_workers :: proc(t: ^testing.T) {
    gate: Gif_Concurrent_Gate
    payloads := [2]Gif_Concurrent_Payload{{gate = &gate}, {gate = &gate}}
    pool: taskpool.Task_Pool
    testing.expect(t, taskpool.task_pool_init(&pool, 2, 2))
    defer taskpool.task_pool_destroy(&pool)
    first, first_outcome := taskpool.task_pool_submit(
        &pool, graphics_test_gif_concurrent_task, &payloads[0])
    second, second_outcome := taskpool.task_pool_submit(
        &pool, graphics_test_gif_concurrent_task, &payloads[1])
    testing.expect_value(t, first_outcome, taskpool.Task_Submit_Outcome.Queued)
    testing.expect_value(t, second_outcome, taskpool.Task_Submit_Outcome.Queued)
    first_result, _ := taskpool.task_pool_wait(&pool, first)
    second_result, _ := taskpool.task_pool_wait(&pool, second)
    testing.expect_value(t, first_result, taskpool.Task_Result.Succeeded)
    testing.expect_value(t, second_result, taskpool.Task_Result.Succeeded)
    testing.expect(t, payloads[0].valid && payloads[1].valid)
    testing.expect_value(t, payloads[0].pixels, payloads[1].pixels)
}

// Verify worker dispatch fills exact animation canvases and normalized descriptors.
@(test)
graphics_test_prepare_animated_gif :: proc(t: ^testing.T) {
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    pixels: [16]u8
    frames: [2]termattachment.Animation_Frame
    request := Prepare_Request{
        kind = .Animated_Gif,
        input = bytes[:],
        width = 2,
        height = 1,
        output = pixels[:],
        animation_frames = frames[:],
        attachment_limits = termattachment.limits_default(),
        gif_inspection = inspect_gif_animation(
            bytes[:], gif_animation_limits(termattachment.limits_default())),
    }

    testing.expect(t, prepare(&request))

    testing.expect_value(t, frames[0].duration_ns, u64(20_000_000))
    testing.expect_value(t, frames[1].duration_ns, u64(30_000_000))
    testing.expect_value(t, pixels[0], u8(255))
    testing.expect_value(t, pixels[8], u8(0))
    testing.expect_value(t, pixels[9], u8(255))
}

// Verify animated preparation rejects metadata that does not match immutable input.
@(test)
graphics_test_rejects_mismatched_gif_preflight :: proc(t: ^testing.T) {
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    pixels: [16]u8
    frames: [2]termattachment.Animation_Frame
    inspection := inspect_gif_animation(bytes[:], graphics_test_gif_limits())
    inspection.frame_count = 3
    _, decoded := decode_preflighted_gif_animation(
        bytes[:], {
            limits = graphics_test_gif_limits(),
            inspection = inspection,
            destination = {frame_bytes = pixels[:], frames = frames[:]},
            attachment_limits = termattachment.limits_default(),
        })
    testing.expect(t, !decoded)
}

// Verify malformed streams and every pre-decode quota reject before decoder admission.
@(test)
graphics_test_rejects_unsafe_animated_gif :: proc(t: ^testing.T) {
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    testing.expect(t, !inspect_gif_animation(
        bytes[:len(bytes) - 1], graphics_test_gif_limits()).valid)
    trailing: [111]u8
    copy(trailing[:], bytes[:])
    trailing[len(bytes)] = 0
    testing.expect(t, !inspect_gif_animation(
        trailing[:], graphics_test_gif_limits()).valid)
    malformed := bytes
    malformed[63] = 64
    testing.expect(t, !inspect_gif_animation(
        malformed[:], graphics_test_gif_limits()).valid)

    limits := graphics_test_gif_limits()
    limits.encoded_byte_limit = len(bytes) - 1
    testing.expect(t, !inspect_gif_animation(bytes[:], limits).valid)
    limits = graphics_test_gif_limits()
    limits.dimension_limit = 1
    testing.expect(t, !inspect_gif_animation(bytes[:], limits).valid)
    limits = graphics_test_gif_limits()
    limits.frame_limit = 1
    testing.expect(t, !inspect_gif_animation(bytes[:], limits).valid)
    limits = graphics_test_gif_limits()
    limits.decoded_byte_limit = 15
    testing.expect(t, !inspect_gif_animation(bytes[:], limits).valid)
    limits = graphics_test_gif_limits()
    limits.peak_byte_limit = len(bytes) - 1
    testing.expect(t, !inspect_gif_animation(bytes[:], limits).valid)
    limits = graphics_test_gif_limits()
    limits.peak_byte_limit = 148
    testing.expect(t, !inspect_gif_animation(bytes[:], limits).valid)
    limits = graphics_test_gif_limits()
    limits.duration_ns_limit = 149_000_000
    testing.expect(t, !inspect_gif_animation(bytes[:], limits).valid)
}

// Verify a zero Netscape loop value is distinguished from an absent loop extension.
@(test)
graphics_test_inspects_infinite_gif_loop :: proc(t: ^testing.T) {
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    bytes[41] = 0
    bytes[42] = 0
    result := inspect_gif_animation(bytes[:], graphics_test_gif_limits())
    testing.expect(t, result.valid)
    testing.expect(t, result.has_loop_extension)
    testing.expect(t, result.infinite)
    testing.expect_value(t, result.repeat_count, 0)
}

// Verify exact caller-owned capacities are required before SDL_image decoding starts.
@(test)
graphics_test_rejects_animated_gif_capacity_mismatch :: proc(t: ^testing.T) {
    bytes := GRAPHICS_TEST_ANIMATED_GIF
    frames: [15]u8
    descriptors: [2]termattachment.Animation_Frame
    _, decoded := decode_gif_animation(
        bytes[:], graphics_test_gif_limits(), {
            frame_bytes = frames[:], frames = descriptors[:],
        },
        termattachment.limits_default())
    testing.expect(t, !decoded)
}