#+test
package termgraphicsprepare

import termattachment "../../attachment"

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

// Verify stb returns exact composited canvases and delays matching preflight metadata.
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

// Verify malformed streams and every pre-decode quota reject without stb admission.
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

// Verify exact caller-owned capacities are required before stb decoding starts.
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