package native

import "core:c"
import "core:log"
import "core:mem"
import "core:os"
import "core:testing"

import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

Sdl_Capture_Completion_Test_State :: struct {
    pixels: rawptr,
    wait_succeeds: bool,
    map_succeeds: bool,
    wait_count: int,
    map_count: int,
    unmap_count: int,
    release_count: int,
}

// Verify SDL sample-count enum ordinals are not exposed as physical counts.
@(test)
sdl_scene_sample_count_values_are_physical :: proc(t: ^testing.T) {
    testing.expect_value(t, sdl_scene_sample_count_value(._1), 1)
    testing.expect_value(t, sdl_scene_sample_count_value(._2), 2)
    testing.expect_value(t, sdl_scene_sample_count_value(._4), 4)
    testing.expect_value(t, sdl_scene_sample_count_value(._8), 8)
}

// sdl_capture_test_wait records one injected fence wait.
sdl_capture_test_wait :: proc(
    user_data: rawptr, _: ^sdl.GPUDevice, _: ^sdl.GPUFence) -> bool {
    state := cast(^Sdl_Capture_Completion_Test_State)user_data
    state^.wait_count += 1
    return state^.wait_succeeds
}

// sdl_capture_test_map records one injected transfer map.
sdl_capture_test_map :: proc(
    user_data: rawptr, _: ^sdl.GPUDevice,
    _: ^sdl.GPUTransferBuffer) -> rawptr {
    state := cast(^Sdl_Capture_Completion_Test_State)user_data
    state^.map_count += 1
    return state^.map_succeeds ? state^.pixels : nil
}

// sdl_capture_test_unmap records one injected transfer unmap.
sdl_capture_test_unmap :: proc(
    user_data: rawptr, _: ^sdl.GPUDevice, _: ^sdl.GPUTransferBuffer) {
    state := cast(^Sdl_Capture_Completion_Test_State)user_data
    state^.unmap_count += 1
}

// sdl_capture_test_release records one injected fence release.
sdl_capture_test_release :: proc(
    user_data: rawptr, _: ^sdl.GPUDevice, _: ^sdl.GPUFence) {
    state := cast(^Sdl_Capture_Completion_Test_State)user_data
    state^.release_count += 1
}

// sdl_capture_test_operations builds deterministic completion operations.
sdl_capture_test_operations :: proc(
    state: ^Sdl_Capture_Completion_Test_State) -> Sdl_Capture_Completion_Operations {
    return {
        user_data = rawptr(state),
        wait = sdl_capture_test_wait,
        map_transfer = sdl_capture_test_map,
        unmap = sdl_capture_test_unmap,
        release_fence = sdl_capture_test_release,
    }
}

// Verify capture transfer rows use the documented backend-friendly alignment.
@(test)
sdl_capture_transfer_layout_aligns_rows :: proc(t: ^testing.T) {
    layout := sdl_capture_transfer_layout(65, 3)
    testing.expect(t, layout.valid)
    testing.expect_value(t, layout.pitch_bytes, 512)
    testing.expect_value(t, layout.transfer_bytes, 1536)

    testing.expect(t, !sdl_capture_transfer_layout(0, 3).valid)
}

// Verify padded transfer rows normalize to tight top-left RGBA8 storage.
@(test)
sdl_capture_copy_rgba8_removes_row_padding :: proc(t: ^testing.T) {
    source := [24]u8{
        1, 2, 3, 4, 5, 6, 7, 8, 90, 91, 92, 93,
        9, 10, 11, 12, 13, 14, 15, 16, 94, 95, 96, 97,
    }
    destination: [16]u8
    testing.expect(t, sdl_capture_copy_rgba8(
        destination[:], raw_data(source[:]), 2, 2, 12))
    testing.expect(t, mem.compare(destination[:], []u8{
        1, 2, 3, 4, 5, 6, 7, 8,
        9, 10, 11, 12, 13, 14, 15, 16,
    }) == 0)
    testing.expect(t, !sdl_capture_copy_rgba8(
        destination[:], raw_data(source[:]), 2, 2, 7))
}

// Verify wait failure releases the fence without mapping the transfer.
@(test)
sdl_capture_completion_releases_after_wait_failure :: proc(t: ^testing.T) {
    state := Sdl_Capture_Completion_Test_State{}
    destination: [4]u8
    testing.expect(t, !sdl_capture_complete({
        fence = cast(^sdl.GPUFence)(uintptr(1)),
        destination = destination[:], width = 1, height = 1, source_pitch = 4,
    }, sdl_capture_test_operations(&state)))
    testing.expect_value(t, state.wait_count, 1)
    testing.expect_value(t, state.map_count, 0)
    testing.expect_value(t, state.unmap_count, 0)
    testing.expect_value(t, state.release_count, 1)
}

// Verify map failure releases the fence without unmapping absent storage.
@(test)
sdl_capture_completion_releases_after_map_failure :: proc(t: ^testing.T) {
    state := Sdl_Capture_Completion_Test_State{wait_succeeds = true}
    destination: [4]u8
    testing.expect(t, !sdl_capture_complete({
        fence = cast(^sdl.GPUFence)(uintptr(1)),
        destination = destination[:], width = 1, height = 1, source_pitch = 4,
    }, sdl_capture_test_operations(&state)))
    testing.expect_value(t, state.wait_count, 1)
    testing.expect_value(t, state.map_count, 1)
    testing.expect_value(t, state.unmap_count, 0)
    testing.expect_value(t, state.release_count, 1)
}

// Verify successful completion unmaps and releases exactly once.
@(test)
sdl_capture_completion_unmaps_and_releases_once :: proc(t: ^testing.T) {
    source := [4]u8{1, 2, 3, 4}
    state := Sdl_Capture_Completion_Test_State{
        pixels = rawptr(&source[0]), wait_succeeds = true, map_succeeds = true}
    destination: [4]u8
    testing.expect(t, sdl_capture_complete({
        fence = cast(^sdl.GPUFence)(uintptr(1)),
        destination = destination[:], width = 1, height = 1, source_pitch = 4,
    }, sdl_capture_test_operations(&state)))
    testing.expect_value(t, destination, source)
    testing.expect_value(t, state.unmap_count, 1)
    testing.expect_value(t, state.release_count, 1)
}

// Verify SDL core persists padded RGBA rows without changing pixel channels.
@(test)
sdl_capture_png_preserves_padded_rgba_rows :: proc(t: ^testing.T) {
    path := ".build/test-artifacts/sdl-capture-padded.png"
    os.make_directory_all(".build/test-artifacts")
    defer os.remove(path)
    pixels := [24]u8{
        255, 0, 0, 255, 0, 255, 0, 128, 90, 91, 92, 93,
        0, 0, 255, 64, 255, 255, 255, 0, 94, 95, 96, 97,
    }
    testing.expect(t, sdl_platform_save_png(
        pixels[:], 2, 2, 12, ".build/test-artifacts/sdl-capture-padded.png"))
    encoded, read_error := os.read_entire_file(path, context.allocator)
    testing.expect(t, read_error == nil)
    defer delete(encoded)
    width, height, channels: c.int
    decoded := stbi.load_from_memory(raw_data(encoded), c.int(len(encoded)),
        &width, &height, &channels, 4)
    testing.expect(t, decoded != nil)
    if decoded == nil {return}
    defer stbi.image_free(decoded)
    testing.expect_value(t, width, c.int(2))
    testing.expect_value(t, height, c.int(2))
    expected := [16]u8{
        255, 0, 0, 255, 0, 255, 0, 128,
        0, 0, 255, 64, 255, 255, 255, 0,
    }
    testing.expect(t, mem.compare(decoded[:len(expected)], expected[:]) == 0)
}

// Verify PNG persistence rejects invalid geometry and failed destinations.
@(test)
sdl_capture_png_reports_validation_and_persistence_failures :: proc(t: ^testing.T) {
    previous_logger := context.logger
    context.logger = log.nil_logger()
    defer context.logger = previous_logger
    pixels := [4]u8{1, 2, 3, 4}
    testing.expect(t, !sdl_platform_save_png(
        pixels[:], 1, 1, 3, "capture.png"))
    testing.expect(t, !sdl_platform_save_png(
        pixels[:], 1, 1, 4, ".build/missing-capture-dir/capture.png"))
}