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
    allocation_count: int,
    fail_allocation_at: int,
    capture_active: bool,
    unload_count: int,
    reset_count: int,
    export_count: int,
    export_succeeds: bool,
}

// Gif_Capture_Test_Encoder records staged and committed frames without native IO.
Gif_Capture_Test_Encoder :: struct {
    staged: bool,
    stage_count: int,
    commit_count: int,
    close_count: int,
    durations: [4]u64,
}

// Admit one non-overlapping test capture transaction.
framebuffer_test_begin :: proc(user_data: rawptr) -> bool {
    state := cast(^Framebuffer_Capture_Test_State)user_data
    if state.capture_active {return false}
    state.capture_active = true
    return true
}

// Allocate framebuffer pixels through the test operation owner.
framebuffer_test_allocate :: proc(
    user_data: rawptr, byte_count: int) -> ([]u8, mem.Allocator_Error) {
    state := cast(^Framebuffer_Capture_Test_State)user_data
    if !state.capture_active {return nil, .Invalid_Argument}
    state.allocation_count += 1
    if state.fail_allocation_at == state.allocation_count {
        return nil, .Out_Of_Memory
    }
    return make([]u8, byte_count, state.allocator)
}

// Copy the configured framebuffer pixels into owner-controlled test storage.
framebuffer_test_load :: proc(user_data: rawptr) -> Framebuffer_Pixels {
    state := cast(^Framebuffer_Capture_Test_State)user_data
    pixels, allocation_error := framebuffer_test_allocate(
        user_data, len(state^.source))
    if allocation_error != nil {return {}}
    copy(pixels, state^.source)
    return {pixels = pixels, width = state^.width, height = state^.height,
        pitch_bytes = state^.pitch_bytes}
}

// Complete one test capture domain; individual allocations are already released.
framebuffer_test_reset :: proc(user_data: rawptr) {
    state := cast(^Framebuffer_Capture_Test_State)user_data
    state.capture_active = false
    state.reset_count += 1
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
        begin = framebuffer_test_begin,
        allocate = framebuffer_test_allocate,
        load = framebuffer_test_load,
        unload = framebuffer_test_unload,
        reset = framebuffer_test_reset,
        export = framebuffer_test_export,
    }
}

// Build one valid tightly packed RGBA8 source backed by caller-owned test storage.
framebuffer_test_source :: proc(
    pixels: []u8, width, height: int) -> Framebuffer_Capture_Test_State {
    return {
        source = pixels, width = width, height = height,
        pitch_bytes = width * FRAMEBUFFER_PIXEL_BYTES,
        allocator = context.allocator,
    }
}

// Copy-free test staging records one accepted frame and rejects overlap.
gif_capture_test_stage_frame :: proc(
    user_data: rawptr, _: Gif_Capture_Frame) -> bool {
    encoder := cast(^Gif_Capture_Test_Encoder)user_data
    if encoder == nil || encoder.staged {return false}
    encoder.staged = true
    encoder.stage_count += 1
    return true
}

// Record one duration for the currently staged test frame.
gif_capture_test_commit_frame :: proc(user_data: rawptr, duration_ms: u64) -> bool {
    encoder := cast(^Gif_Capture_Test_Encoder)user_data
    if encoder == nil || !encoder.staged ||
       encoder.commit_count >= len(encoder.durations) {
        return false
    }
    encoder.durations[encoder.commit_count] = duration_ms
    encoder.commit_count += 1
    encoder.staged = false
    return true
}

// Close one test stream only after its staged frame is committed.
gif_capture_test_close :: proc(user_data: rawptr) -> bool {
    encoder := cast(^Gif_Capture_Test_Encoder)user_data
    if encoder == nil || encoder.staged {return false}
    encoder.close_count += 1
    return true
}

// Clear any staged test frame during capture abort.
gif_capture_test_abort :: proc(user_data: rawptr) {
    encoder := cast(^Gif_Capture_Test_Encoder)user_data
    if encoder != nil {encoder.staged = false}
}

// Return a stable synthetic output path after test finalization.
gif_capture_test_published_path :: proc(_: rawptr) -> string {
    return "test.gif"
}

// Build staged encoder operations for portable GIF policy tests.
gif_capture_test_encoder_operations :: proc(
    encoder: ^Gif_Capture_Test_Encoder) -> Gif_Capture_Operations {
    return {
        user_data = rawptr(encoder),
        stage_frame = gif_capture_test_stage_frame,
        commit_frame = gif_capture_test_commit_frame,
        close = gif_capture_test_close,
        abort = gif_capture_test_abort,
        published_path = gif_capture_test_published_path,
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
    testing.expect_value(t, state.reset_count, 1)
    testing.expect_value(t, len(capture.pixels), 0)
    testing.expect_value(t, capture.width, 0)
}

// Verify overlapping acquisition cannot reset or invalidate a live capture domain.
@(test)
framebuffer_capture_rejects_overlapping_acquisition :: proc(t: ^testing.T) {
    source: [FRAMEBUFFER_PIXEL_BYTES]u8
    state := framebuffer_test_source(source[:], 1, 1)
    operations := framebuffer_test_operations(&state)
    first, first_ok := framebuffer_acquire_with_operations(operations)

    second, second_ok := framebuffer_acquire_with_operations(operations)
    testing.expect(t, first_ok)
    testing.expect(t, !second_ok)
    testing.expect_value(t, len(first.pixels), FRAMEBUFFER_PIXEL_BYTES)
    testing.expect_value(t, len(second.pixels), 0)
    testing.expect_value(t, state.reset_count, 0)

    framebuffer_release_with_operations(&first, operations)
    testing.expect_value(t, state.reset_count, 1)
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
    state.gif_capture.output_width = 5
    state.gif_capture.output_height = 3
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
    state.gif_capture.output_width = 1
    state.gif_capture.output_height = 1

    operations := framebuffer_test_operations(&operation_state)
    operation_state.fail_allocation_at = 2

    frame, ok := gif_capture_normalized_frame_with_operations(
        state, 1, operations)
    testing.expect(t, !ok)
    testing.expect_value(t, len(frame.pixels), 0)
    testing.expect_value(t, operation_state.unload_count, 1)
}

// Verify capture stages first, honors cadence, and commits forward durations.
@(test)
gif_capture_stages_and_commits_fixed_step_intervals :: proc(t: ^testing.T) {
    source: [8]u8
    framebuffer := framebuffer_test_source(source[:], 2, 1)
    encoder: Gif_Capture_Test_Encoder
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state, context.allocator)
    state^.gif_capture = {
        operations = gif_capture_test_encoder_operations(&encoder),
        active = true, source_width = 2, source_height = 1,
        output_width = 2, output_height = 1, active_downsample_factor = 1,
        active_frame_step = 2, active_timing_mode = .Animation,
    }
    operations := framebuffer_test_operations(&framebuffer)

    state^.fixed_step = 10
    testing.expect(t, gif_capture_submit_frame(state, operations))
    testing.expect_value(t, encoder.stage_count, 1)
    testing.expect_value(t, encoder.commit_count, 0)

    state^.fixed_step = 13
    testing.expect(t, gif_capture_submit_frame(state, operations))
    testing.expect_value(t, encoder.stage_count, 1)
    state^.fixed_step = 15
    testing.expect(t, gif_capture_submit_frame(state, operations))
    testing.expect_value(t, encoder.commit_count, 1)
    testing.expect_value(t, encoder.durations[0], u64(83))
    testing.expect_value(t, encoder.stage_count, 2)

    state^.fixed_step = 18
    testing.expect(t, gif_capture_finalize_session(state))
    testing.expect_value(t, encoder.commit_count, 2)
    testing.expect_value(t, encoder.durations[1], u64(50))
    testing.expect_value(t, encoder.close_count, 1)
    testing.expect_value(t, state^.ui_runtime.gif_captured_frames, 2)
}