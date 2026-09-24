#+test
package termgraphicsprepare

import "../../../taskpool"
import "core:testing"
import "core:sync"
import termattachment "../../attachment"

// One valid one-pixel PNG used for deterministic header and decode tests.
GRAPHICS_TEST_PNG :: [68]u8{
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 4, 0, 0, 0, 181, 28, 12,
    2, 0, 0, 0, 11, 73, 68, 65, 84, 120, 218, 99, 100, 248, 15, 0,
    1, 5, 1, 1, 39, 24, 227, 102, 0, 0, 0, 0, 73, 69, 78, 68,
    174, 66, 96, 130,
}

// One valid one-pixel GIF used to verify first-frame format admission.
GRAPHICS_TEST_GIF :: [34]u8{
    71, 73, 70, 56, 57, 97, 1, 0, 1, 0, 128, 0, 0, 0, 0, 0,
    255, 255, 255, 44, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 1, 76,
    0, 59,
}

// One valid one-pixel baseline JPEG used for deterministic decode tests.
GRAPHICS_TEST_JPEG :: [285]u8{
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43,
    0x00, 0x03, 0x02, 0x02, 0x03, 0x02, 0x02, 0x03, 0x03, 0x03, 0x03, 0x04,
    0x03, 0x03, 0x04, 0x05, 0x08, 0x05, 0x05, 0x04, 0x04, 0x05, 0x0a, 0x07,
    0x07, 0x06, 0x08, 0x0c, 0x0a, 0x0c, 0x0c, 0x0b, 0x0a, 0x0b, 0x0b, 0x0d,
    0x0e, 0x12, 0x10, 0x0d, 0x0e, 0x11, 0x0e, 0x0b, 0x0b, 0x10, 0x16, 0x10,
    0x11, 0x13, 0x14, 0x15, 0x15, 0x15, 0x0c, 0x0f, 0x17, 0x18, 0x16, 0x14,
    0x18, 0x12, 0x14, 0x15, 0x14, 0xff, 0xdb, 0x00, 0x43, 0x01, 0x03, 0x04,
    0x04, 0x05, 0x04, 0x05, 0x09, 0x05, 0x05, 0x09, 0x14, 0x0d, 0x0b, 0x0d,
    0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14,
    0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14,
    0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14,
    0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x14,
    0x14, 0x14, 0xff, 0xc0, 0x00, 0x11, 0x08, 0x00, 0x01, 0x00, 0x01, 0x03,
    0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xff, 0xc4, 0x00,
    0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0xff, 0xc4, 0x00, 0x14, 0x10,
    0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xc4, 0x00, 0x14, 0x01, 0x01, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x07, 0xff, 0xc4, 0x00, 0x14, 0x11, 0x01, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0xff, 0xda, 0x00, 0x0c, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11,
    0x00, 0x3f, 0x00, 0x22, 0x2d, 0x8b, 0xdf, 0xff, 0xd9,
}

// Return small positive attachment limits suitable for preparation tests.
graphics_test_limits :: proc() -> termattachment.Limits {
    return {
        attachment_capacity = 2,
        placement_capacity = 2,
        transfer_capacity = 2,
        transfer_byte_limit = 1024,
        dimension_limit = 32,
        image_pixel_limit = 1024,
        cpu_byte_limit = 4096,
        gpu_byte_limit = 4096,
        animated_attachment_limit = 2,
        animation_frame_limit = 8,
        animation_decode_byte_limit = 4096,
        animation_min_frame_duration_ns = 1_000_000,
        animation_max_frame_duration_ns = 100_000_000,
        animation_duration_ns_limit = 1_000_000_000,
    }
}

// Verify supported signatures and allocation-free dimensions obey configured limits.
@(test)
graphics_test_inspect_encoded_images :: proc(t: ^testing.T) {
    png_bytes := GRAPHICS_TEST_PNG
    jpeg_bytes := GRAPHICS_TEST_JPEG
    gif_bytes := GRAPHICS_TEST_GIF
    png := inspect_image(png_bytes[:], graphics_test_limits())
    jpeg := inspect_image(jpeg_bytes[:], graphics_test_limits())
    gif := inspect_image(gif_bytes[:], graphics_test_limits())
    testing.expect(t, png.valid)
    testing.expect_value(t, png.format, Encoded_Image_Format.Png)
    testing.expect_value(t, png.width, 1)
    testing.expect_value(t, png.height, 1)
    testing.expect(t, jpeg.valid)
    testing.expect_value(t, jpeg.format, Encoded_Image_Format.Jpeg)
    testing.expect_value(t, jpeg.width, 1)
    testing.expect_value(t, jpeg.height, 1)
    testing.expect(t, gif.valid)
    testing.expect_value(t, gif.format, Encoded_Image_Format.Gif)
    testing.expect(t, !inspect_image(png_bytes[:8], graphics_test_limits()).valid)
}

// Verify malformed and oversized static headers are rejected before native decode.
@(test)
graphics_test_rejects_invalid_encoded_headers :: proc(t: ^testing.T) {
    png_bytes := GRAPHICS_TEST_PNG
    png_bytes[11] = 12
    testing.expect(t, !inspect_image(png_bytes[:], graphics_test_limits()).valid)

    png_bytes = GRAPHICS_TEST_PNG
    png_bytes[19] = 33
    testing.expect(t, !inspect_image(png_bytes[:], graphics_test_limits()).valid)

    jpeg_bytes := GRAPHICS_TEST_JPEG
    testing.expect(t, !inspect_image(jpeg_bytes[:20], graphics_test_limits()).valid)

    gif_bytes := GRAPHICS_TEST_GIF
    gif_bytes[6] = 0
    gif_bytes[7] = 0
    testing.expect(t, !inspect_image(gif_bytes[:], graphics_test_limits()).valid)
}

// Verify JPEG preparation decodes into exact preallocated RGBA storage.
@(test)
graphics_test_prepare_jpeg :: proc(t: ^testing.T) {
    output: [4]u8
    jpeg_bytes := GRAPHICS_TEST_JPEG
    request := Prepare_Request{
        kind = .Encoded_Image, input = jpeg_bytes[:], width = 1, height = 1,
        output = output[:],
    }
    testing.expect(t, prepare(&request))
    testing.expect_value(t, output[3], u8(255))
}

// Verify SDL_image PNG decoding writes one exact preallocated RGBA result.
@(test)
graphics_test_prepare_png :: proc(t: ^testing.T) {
    output: [4]u8
    png_bytes := GRAPHICS_TEST_PNG
    request := Prepare_Request{
        kind = .Encoded_Image,
        input = png_bytes[:],
        width = 1,
        height = 1,
        output = output[:],
    }
    testing.expect(t, prepare(&request))
    testing.expect_value(t, output[3], u8(255))
}

// Verify GIF preparation decodes the first frame into exact RGBA storage.
@(test)
graphics_test_prepare_gif_first_frame :: proc(t: ^testing.T) {
    output: [4]u8
    gif_bytes := GRAPHICS_TEST_GIF
    request := Prepare_Request{
        kind = .Encoded_Image, input = gif_bytes[:], width = 1, height = 1,
        output = output[:],
    }
    testing.expect(t, prepare(&request))
    testing.expect_value(t, output[3], u8(255))
}

// Verify exact RGB and RGBA zlib streams expand in place without transient storage.
@(test)
graphics_test_prepare_zlib :: proc(t: ^testing.T) {
    rgb := [14]u8{120, 156, 99, 100, 98, 102, 97, 101, 3, 0, 0, 62, 0, 22}
    rgba := [16]u8{
        120, 156, 99, 231, 224, 228, 226, 230,
        225, 229, 3, 0, 1, 88, 0, 85,
    }
    output: [8]u8
    request := Prepare_Request{
        kind = .Zlib_Rgb, input = rgb[:], width = 2, height = 1,
        output = output[:],
    }
    testing.expect(t, prepare(&request))
    testing.expect_value(t, output, [8]u8{1, 2, 3, 255, 4, 5, 6, 255})
    request.kind = .Zlib_Rgba
    request.input = rgba[:]
    testing.expect(t, prepare(&request))
    testing.expect_value(t, output, [8]u8{7, 8, 9, 10, 11, 12, 13, 14})
}

// Verify a stream expanding beyond the declared raw extent fails without overwrite.
@(test)
graphics_test_rejects_zlib_expansion_beyond_extent :: proc(t: ^testing.T) {
    compressed := [14]u8{
        120, 156, 99, 100, 98, 102, 97, 101, 3, 0, 0, 62, 0, 22,
    }
    output := [5]u8{0, 0, 0, 0, 0xa5}
    request := Prepare_Request{
        kind = .Zlib_Rgb, input = compressed[:], width = 1, height = 1,
        output = output[:4],
    }
    testing.expect(t, !prepare(&request))
    testing.expect_value(t, output[4], u8(0xa5))
}

// Verify Sixel repeat, palette selection, bands, and transparent background expansion.
@(test)
graphics_test_prepare_sixel :: proc(t: ^testing.T) {
    output: [2 * 12 * 4]u8
    sixel := "#1;2;100;0;0#1!2~-$?"
    request := Prepare_Request{
        kind = .Sixel,
        input = transmute([]u8)sixel,
        width = 2,
        height = 12,
        output = output[:],
        transparent_background = true,
    }
    testing.expect(t, prepare(&request))
    testing.expect_value(t, output[0], u8(255))
    testing.expect_value(t, output[3], u8(255))
    testing.expect_value(t, output[(11 * 2) * 4 + 3], u8(0))
}

// Verify Sixel HLS definitions update the selected worker-side palette register.
@(test)
graphics_test_prepare_sixel_hls :: proc(t: ^testing.T) {
    output: [4]u8
    sixel := "#1;1;0;50;100#1@"
    request := Prepare_Request{
        kind = .Sixel, input = transmute([]u8)sixel,
        width = 1, height = 1, output = output[:],
    }
    testing.expect(t, prepare(&request))
    testing.expect_value(t, output, [4]u8{0, 255, 0, 255})
}

// Verify malformed or mismatched preparations cannot write outside exact output policy.
@(test)
graphics_test_rejects_invalid_preparation :: proc(t: ^testing.T) {
    output: [4]u8
    png_bytes := GRAPHICS_TEST_PNG
    request := Prepare_Request{
        kind = .Encoded_Image,
        input = png_bytes[:],
        width = 2,
        height = 1,
        output = output[:],
    }
    testing.expect(t, !prepare(&request))
    invalid_sixel := "!999~"
    request = {kind = .Sixel, input = transmute([]u8)invalid_sixel,
        width = 1, height = 1, output = output[:]}
    testing.expect(t, !prepare(&request))
}

// Verify a pre-cancelled preparation leaves its exact candidate storage untouched.
@(test)
graphics_test_pre_cancelled_preparation :: proc(t: ^testing.T) {
    output := [4]u8{0xa5, 0xa5, 0xa5, 0xa5}
    sixel := "@"
    request := Prepare_Request{
        kind = .Sixel, input = transmute([]u8)sixel,
        width = 1, height = 1, output = output[:],
    }
    requested := false
    sync.atomic_store_explicit(&requested, true, .Release)

    testing.expect(t, !prepare(&request, {requested = &requested}))
    testing.expect_value(t, output, [4]u8{0xa5, 0xa5, 0xa5, 0xa5})
    testing.expect(t, taskpool.task_cancellation_requested({
        requested = &requested,
    }))
}