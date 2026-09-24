package view_core

import app_core "../../core"

import "core:mem"
import "core:testing"

// Framebuffer_Capture_Test_State supplies pixels and records native operation calls.
Framebuffer_Capture_Test_State :: struct {
    source: []u8,
    width: int,
    height: int,
    pitch_bytes: int,
    allocator: mem.Allocator,
    unload_count: int,
    export_count: int,
    export_succeeds: bool,
}

// Copy the configured framebuffer pixels into storage owned by the caller.
framebuffer_test_load :: proc(
    user_data: rawptr, allocator: mem.Allocator) -> Framebuffer_Pixels {
    state := cast(^Framebuffer_Capture_Test_State)user_data
    pixels, allocation_error := make([]u8, len(state^.source), allocator)
    if allocation_error != nil {return {}}
    state^.allocator = allocator
    copy(pixels, state^.source)
    return {pixels = pixels, width = state^.width, height = state^.height,
        pitch_bytes = state^.pitch_bytes}
}

// Release one test framebuffer allocation and record the operation.
framebuffer_test_unload :: proc(
    user_data: rawptr, capture: ^Framebuffer_Pixels) {
    state := (^Framebuffer_Capture_Test_State)(user_data)
    state.unload_count += 1
    delete(capture^.pixels, state^.allocator)
}

// Return the configured export result and record the operation.
framebuffer_test_export :: proc(
    user_data: rawptr, _: ^Framebuffer_Pixels, _: cstring) -> bool {
    state := (^Framebuffer_Capture_Test_State)(user_data)
    state.export_count += 1
    return state.export_succeeds
}

// Build deterministic native operations for framebuffer capture tests.
framebuffer_test_operations :: proc(
    state: ^Framebuffer_Capture_Test_State) -> Framebuffer_Capture_Operations {
    return {
        user_data = rawptr(state),
        allocator = context.allocator,
        load = framebuffer_test_load,
        unload = framebuffer_test_unload,
        export = framebuffer_test_export,
    }
}

// Build one valid tightly packed RGBA8 source backed by caller-owned test storage.
framebuffer_test_source :: proc(
    pixels: []u8, width, height: int) -> Framebuffer_Capture_Test_State {
    return {
        source = pixels, width = width, height = height,
        pitch_bytes = width * FRAMEBUFFER_PIXEL_BYTES,
    }
}

// Verify successful admission publishes dimensions, pitch, and borrowed pixels.
@(test)
framebuffer_capture_admits_rgba8_and_releases_once :: proc(t: ^testing.T) {
    source: [12 * 7 * FRAMEBUFFER_PIXEL_BYTES]u8
    state := framebuffer_test_source(source[:], 12, 7)
    operations := framebuffer_test_operations(&state)

    capture, ok := framebuffer_acquire_with_operations(operations)
    testing.expect(t, ok)
    testing.expect_value(t, capture.width, 12)
    testing.expect_value(t, capture.height, 7)
    testing.expect_value(t, capture.pitch_bytes, 48)
    testing.expect_value(t, len(capture.pixels), len(source))

    framebuffer_release_with_operations(&capture, operations)
    framebuffer_release_with_operations(&capture, operations)
    testing.expect_value(t, state.unload_count, 1)
    testing.expect_value(t, len(capture.pixels), 0)
    testing.expect_value(t, capture.width, 0)
}

// Verify invalid image metadata is rejected and owned data is released.
@(test)
framebuffer_capture_rejects_invalid_images :: proc(t: ^testing.T) {
    source: [16]u8
    invalid_states := [3]Framebuffer_Capture_Test_State{
        framebuffer_test_source(nil, 2, 2),
        framebuffer_test_source(source[:], 0, 2),
        framebuffer_test_source(source[:], 2, 2),
    }
    invalid_states[2].pitch_bytes = 7

    for source_state in invalid_states {
        state := source_state
        capture, ok := framebuffer_acquire_with_operations(
            framebuffer_test_operations(&state))
        testing.expect(t, !ok)
        testing.expect_value(t, len(capture.pixels), 0)
        expected_unloads := len(source_state.source) == 0 ? 0 : 1
        testing.expect_value(t, state.unload_count, expected_unloads)
    }
}

// Verify crop and nearest-neighbor resize preserve exact top-left RGBA pixels.
@(test)
framebuffer_capture_mutations_refresh_metadata :: proc(t: ^testing.T) {
    source := [4 * 2 * FRAMEBUFFER_PIXEL_BYTES]u8{
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
        17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
    }
    state := framebuffer_test_source(source[:], 4, 2)
    state.export_succeeds = true
    operations := framebuffer_test_operations(&state)
    capture, ok := framebuffer_acquire_with_operations(operations)
    testing.expect(t, ok)

    testing.expect(t,
        framebuffer_crop_with_operations(&capture, 2, 2, operations))
    testing.expect_value(t, capture.width, 2)
    testing.expect_value(t, capture.height, 2)
    testing.expect_value(t, capture.pitch_bytes, 8)
    testing.expect(t, mem.compare(capture.pixels,
        []u8{1, 2, 3, 4, 5, 6, 7, 8, 17, 18, 19, 20, 21, 22, 23, 24}) == 0)
    testing.expect(t,
        framebuffer_resize_with_operations(&capture, 1, 1, operations))
    testing.expect_value(t, capture.width, 1)
    testing.expect_value(t, capture.height, 1)
    testing.expect_value(t, capture.pitch_bytes, 4)
    testing.expect(t, mem.compare(capture.pixels, []u8{1, 2, 3, 4}) == 0)
    testing.expect(t, framebuffer_export_with_operations(
        &capture, "capture.png", operations))
    testing.expect_value(t, state.export_count, 1)

    framebuffer_release_with_operations(&capture, operations)
}

// Verify failed mutation and export remain caller-releasable without duplicate unload.
@(test)
framebuffer_capture_failure_remains_releasable :: proc(t: ^testing.T) {
    source: [16]u8
    state := framebuffer_test_source(source[:], 2, 2)
    operations := framebuffer_test_operations(&state)
    capture, ok := framebuffer_acquire_with_operations(operations)
    testing.expect(t, ok)

    testing.expect(t,
        !framebuffer_crop_with_operations(&capture, 3, 2, operations))
    testing.expect(t, !framebuffer_export_with_operations(
        &capture, "capture.png", operations))
    framebuffer_release_with_operations(&capture, operations)
    framebuffer_release_with_operations(&capture, operations)
    testing.expect_value(t, state.unload_count, 1)
}

// Verify GIF normalization crops, downsamples, and retains encoder dimensions.
@(test)
gif_capture_normalization_uses_shared_framebuffer_operations :: proc(t: ^testing.T) {
    source: [12 * 8 * FRAMEBUFFER_PIXEL_BYTES]u8
    operation_state := framebuffer_test_source(source[:], 12, 8)
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
    testing.expect_value(t, frame.width, 5)
    testing.expect_value(t, frame.height, 3)
    framebuffer_release_with_operations(&frame, operations)
    testing.expect_value(t, operation_state.unload_count, 3)
}

// Verify GIF normalization releases an acquired image after resize allocation failure.
@(test)
gif_capture_normalization_releases_failed_crop :: proc(t: ^testing.T) {
    source: [16]u8
    operation_state := framebuffer_test_source(source[:], 2, 2)
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state.gif_capture.source_width = 2
    state.gif_capture.source_height = 2
    state.gif_capture.encoder.width = 1
    state.gif_capture.encoder.height = 1

    storage: [16]u8
    failure_arena: mem.Arena
    mem.arena_init(&failure_arena, storage[:])
    operations := framebuffer_test_operations(&operation_state)
    operations.allocator = mem.arena_allocator(&failure_arena)

    frame, ok := gif_capture_normalized_frame_with_operations(
        state, 1, operations)
    testing.expect(t, !ok)
    testing.expect_value(t, len(frame.pixels), 0)
    testing.expect_value(t, operation_state.unload_count, 1)
}