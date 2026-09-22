package view_core

import app_core "../../core"

import "core:testing"

import rl "vendor:raylib"

// Framebuffer_Capture_Test_State supplies images and records native operation calls.
Framebuffer_Capture_Test_State :: struct {
    image: rl.Image,
    crop_width: i32,
    crop_height: i32,
    resize_width: i32,
    resize_height: i32,
    unload_count: int,
    crop_count: int,
    resize_count: int,
    export_count: int,
    export_succeeds: bool,
}

// Return the configured framebuffer image without entering Raylib.
framebuffer_test_load :: proc(user_data: rawptr) -> rl.Image {
    return (^Framebuffer_Capture_Test_State)(user_data)^.image
}

// Record release of one framebuffer image without entering Raylib.
framebuffer_test_unload :: proc(user_data: rawptr, _: rl.Image) {
    state := (^Framebuffer_Capture_Test_State)(user_data)
    state.unload_count += 1
}

// Apply the configured crop result and record the operation.
framebuffer_test_crop :: proc(
    user_data: rawptr, image: ^rl.Image, _: rl.Rectangle) {
    state := (^Framebuffer_Capture_Test_State)(user_data)
    state.crop_count += 1
    image.width = state.crop_width
    image.height = state.crop_height
}

// Apply the requested resize dimensions and record the operation.
framebuffer_test_resize :: proc(
    user_data: rawptr, image: ^rl.Image, width, height: i32) {
    state := (^Framebuffer_Capture_Test_State)(user_data)
    state.resize_count += 1
    state.resize_width = width
    state.resize_height = height
    image.width = width
    image.height = height
}

// Return the configured export result and record the operation.
framebuffer_test_export :: proc(
    user_data: rawptr, _: rl.Image, _: cstring) -> bool {
    state := (^Framebuffer_Capture_Test_State)(user_data)
    state.export_count += 1
    return state.export_succeeds
}

// Build deterministic native operations for framebuffer capture tests.
framebuffer_test_operations :: proc(
    state: ^Framebuffer_Capture_Test_State) -> Framebuffer_Capture_Operations {
    return {
        user_data = rawptr(state),
        load = framebuffer_test_load,
        unload = framebuffer_test_unload,
        crop = framebuffer_test_crop,
        resize = framebuffer_test_resize,
        export = framebuffer_test_export,
    }
}

// Build one valid tightly packed RGBA8 image backed by caller-owned test storage.
framebuffer_test_image :: proc(data: rawptr, width, height: i32) -> rl.Image {
    return {
        data = data,
        width = width,
        height = height,
        mipmaps = 1,
        format = .UNCOMPRESSED_R8G8B8A8,
    }
}

// Verify successful admission publishes dimensions, pitch, and borrowed pixels.
@(test)
framebuffer_capture_admits_rgba8_and_releases_once :: proc(t: ^testing.T) {
    pixel: u32
    state := Framebuffer_Capture_Test_State{
        image = framebuffer_test_image(rawptr(&pixel), 12, 7),
    }
    operations := framebuffer_test_operations(&state)

    capture, ok := framebuffer_acquire_with_operations(operations)
    testing.expect(t, ok)
    testing.expect_value(t, capture.width, 12)
    testing.expect_value(t, capture.height, 7)
    testing.expect_value(t, capture.pitch_bytes, 48)
    testing.expect_value(t, capture.pixels, rawptr(&pixel))

    framebuffer_release_with_operations(&capture, operations)
    framebuffer_release_with_operations(&capture, operations)
    testing.expect_value(t, state.unload_count, 1)
    testing.expect_value(t, capture, Framebuffer_Pixels{})
}

// Verify invalid native image metadata is rejected and owned data is released.
@(test)
framebuffer_capture_rejects_invalid_images :: proc(t: ^testing.T) {
    pixel: u32
    invalid_images := [3]rl.Image{
        framebuffer_test_image(nil, 12, 7),
        framebuffer_test_image(rawptr(&pixel), 0, 7),
        framebuffer_test_image(rawptr(&pixel), 12, 7),
    }
    invalid_images[2].format = .UNCOMPRESSED_R8G8B8

    for image in invalid_images {
        state := Framebuffer_Capture_Test_State{image = image}
        capture, ok := framebuffer_acquire_with_operations(
            framebuffer_test_operations(&state))
        testing.expect(t, !ok)
        testing.expect_value(t, capture, Framebuffer_Pixels{})
        expected_unloads := image.data == nil ? 0 : 1
        testing.expect_value(t, state.unload_count, expected_unloads)
    }
}

// Verify crop and resize refresh metadata before successful export.
@(test)
framebuffer_capture_mutations_refresh_metadata :: proc(t: ^testing.T) {
    pixel: u32
    state := Framebuffer_Capture_Test_State{
        image = framebuffer_test_image(rawptr(&pixel), 12, 8),
        crop_width = 10,
        crop_height = 6,
        export_succeeds = true,
    }
    operations := framebuffer_test_operations(&state)
    capture, ok := framebuffer_acquire_with_operations(operations)
    testing.expect(t, ok)

    testing.expect(t,
        framebuffer_crop_with_operations(&capture, 10, 6, operations))
    testing.expect_value(t, capture.width, 10)
    testing.expect_value(t, capture.height, 6)
    testing.expect_value(t, capture.pitch_bytes, 40)
    testing.expect(t,
        framebuffer_resize_with_operations(&capture, 5, 3, operations))
    testing.expect_value(t, capture.width, 5)
    testing.expect_value(t, capture.height, 3)
    testing.expect_value(t, capture.pitch_bytes, 20)
    testing.expect(t, framebuffer_export_with_operations(
        &capture, "capture.png", operations))
    testing.expect_value(t, state.crop_count, 1)
    testing.expect_value(t, state.resize_count, 1)
    testing.expect_value(t, state.export_count, 1)

    framebuffer_release_with_operations(&capture, operations)
}

// Verify failed mutation and export remain caller-releasable without duplicate unload.
@(test)
framebuffer_capture_failure_remains_releasable :: proc(t: ^testing.T) {
    pixel: u32
    state := Framebuffer_Capture_Test_State{
        image = framebuffer_test_image(rawptr(&pixel), 12, 8),
        crop_width = 0,
        crop_height = 0,
    }
    operations := framebuffer_test_operations(&state)
    capture, ok := framebuffer_acquire_with_operations(operations)
    testing.expect(t, ok)

    testing.expect(t,
        !framebuffer_crop_with_operations(&capture, 10, 6, operations))
    testing.expect(t, !framebuffer_export_with_operations(
        &capture, "capture.png", operations))
    framebuffer_release_with_operations(&capture, operations)
    framebuffer_release_with_operations(&capture, operations)
    testing.expect_value(t, state.unload_count, 1)
}

// Verify GIF normalization crops, downsamples, and retains encoder dimensions.
@(test)
gif_capture_normalization_uses_shared_framebuffer_operations :: proc(t: ^testing.T) {
    pixel: u32
    operation_state := Framebuffer_Capture_Test_State{
        image = framebuffer_test_image(rawptr(&pixel), 12, 8),
        crop_width = 10,
        crop_height = 6,
    }
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state.gif_capture.source_width = 10
    state.gif_capture.source_height = 6
    state.gif_capture.encoder.width = 5
    state.gif_capture.encoder.height = 3
    operations := framebuffer_test_operations(&operation_state)

    frame, ok := gif_capture_normalized_frame_with_operations(
        state, 2, operations)
    testing.expect(t, ok)
    testing.expect_value(t, operation_state.crop_count, 1)
    testing.expect_value(t, operation_state.resize_count, 1)
    testing.expect_value(t, operation_state.resize_width, i32(5))
    testing.expect_value(t, operation_state.resize_height, i32(3))
    testing.expect_value(t, frame.width, 5)
    testing.expect_value(t, frame.height, 3)
    framebuffer_release_with_operations(&frame, operations)
    testing.expect_value(t, operation_state.unload_count, 1)
}

// Verify GIF normalization releases an acquired image after mutation failure.
@(test)
gif_capture_normalization_releases_failed_crop :: proc(t: ^testing.T) {
    pixel: u32
    operation_state := Framebuffer_Capture_Test_State{
        image = framebuffer_test_image(rawptr(&pixel), 12, 8),
    }
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state.gif_capture.source_width = 10
    state.gif_capture.source_height = 6
    state.gif_capture.encoder.width = 10
    state.gif_capture.encoder.height = 6

    frame, ok := gif_capture_normalized_frame_with_operations(
        state, 1, framebuffer_test_operations(&operation_state))
    testing.expect(t, !ok)
    testing.expect_value(t, frame, Framebuffer_Pixels{})
    testing.expect_value(t, operation_state.crop_count, 1)
    testing.expect_value(t, operation_state.unload_count, 1)
}