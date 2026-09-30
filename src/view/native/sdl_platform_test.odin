package native

import "core:c"
import "core:log"
import "core:mem"
import "core:os"
import "core:testing"

import sdl "vendor:sdl3"
import stbi "vendor:stb/image"
import native_accessibility "accessibility"

Sdl_Capture_Completion_Test_State :: struct {
    pixels: rawptr,
    wait_succeeds: bool,
    map_succeeds: bool,
    wait_count: int,
    map_count: int,
    unmap_count: int,
    release_count: int,
}

Sdl_Windows_Admission_Test_State :: struct {
    order: [4]int,
    order_count: int,
    publish_succeeds: bool,
    hwnd_calls: int,
    publish_calls: int,
    show_calls: int,
}

// sdl_windows_admission_test_record appends one observed lifecycle step.
sdl_windows_admission_test_record :: proc(
    state: ^Sdl_Windows_Admission_Test_State, value: int) {
    state^.order[state^.order_count] = value
    state^.order_count += 1
}

// sdl_windows_admission_test_hwnd records borrowed-handle lookup.
sdl_windows_admission_test_hwnd :: proc(
    user_data: rawptr, _: ^sdl.Window) -> rawptr {
    state := cast(^Sdl_Windows_Admission_Test_State)user_data
    state^.hwnd_calls += 1
    sdl_windows_admission_test_record(state, 1)
    return user_data
}

// sdl_windows_admission_test_publish records adapter publication and admission.
sdl_windows_admission_test_publish :: proc(
    user_data: rawptr, owner: ^native_accessibility.Adapter, _: rawptr,
    _: Sdl_Accessibility_Tree_Input) -> bool {
    state := cast(^Sdl_Windows_Admission_Test_State)user_data
    state^.publish_calls += 1
    sdl_windows_admission_test_record(state, 2)
    if state^.publish_succeeds {owner^.native = user_data}
    return state^.publish_succeeds
}

// sdl_windows_admission_test_show records one native visibility request.
sdl_windows_admission_test_show :: proc(
    user_data: rawptr, _: ^sdl.Window) -> bool {
    state := cast(^Sdl_Windows_Admission_Test_State)user_data
    state^.show_calls += 1
    sdl_windows_admission_test_record(state, 3)
    return true
}

// sdl_windows_admission_test_operations binds one deterministic fixture.
sdl_windows_admission_test_operations :: proc(
    state: ^Sdl_Windows_Admission_Test_State) ->
    Sdl_Windows_Accessibility_Operations {
    return {
        user_data = state,
        hwnd = sdl_windows_admission_test_hwnd,
        publish = sdl_windows_admission_test_publish,
        show = sdl_windows_admission_test_show,
    }
}

// Verify only Windows starts SDL's application window hidden.
@(test)
sdl_windows_window_flags_start_hidden :: proc(t: ^testing.T) {
    flags := sdl_platform_window_flags({resizable = true})
    testing.expect(t, .HIGH_PIXEL_DENSITY in flags)
    testing.expect(t, .RESIZABLE in flags)
    when ODIN_OS == .Windows {
        testing.expect(t, .HIDDEN in flags)
    } else {
        testing.expect(t, .HIDDEN not_in flags)
    }
}

// Verify HWND lookup and publication precede one show attempt.
@(test)
sdl_windows_accessibility_admission_precedes_one_shot_show :: proc(t: ^testing.T) {
    state := Sdl_Windows_Admission_Test_State{publish_succeeds = true}
    platform := new(Sdl_Platform, context.allocator)
    defer free(platform, context.allocator)
    platform^.window = cast(^sdl.Window)&state
    operations := sdl_windows_admission_test_operations(&state)
    testing.expect(t, sdl_platform_windows_publish_with_operations(
        platform, {}, operations))
    testing.expect_value(t, state.order_count, 3)
    testing.expect_value(t, state.order[0], 1)
    testing.expect_value(t, state.order[1], 2)
    testing.expect_value(t, state.order[2], 3)
    testing.expect(t, platform^.accessibility_admission_attempted)
    testing.expect(t, platform^.window_show_attempted)
    testing.expect(t, platform^.window_shown)

    testing.expect(t, sdl_platform_windows_publish_with_operations(
        platform, {}, operations))
    testing.expect_value(t, state.hwnd_calls, 1)
    testing.expect_value(t, state.publish_calls, 2)
    testing.expect_value(t, state.show_calls, 1)
}

// Verify failed accessibility still shows once and cannot retry admission.
@(test)
sdl_windows_accessibility_failure_still_shows_without_retry :: proc(t: ^testing.T) {
    state: Sdl_Windows_Admission_Test_State
    platform := new(Sdl_Platform, context.allocator)
    defer free(platform, context.allocator)
    platform^.window = cast(^sdl.Window)&state
    operations := sdl_windows_admission_test_operations(&state)
    testing.expect(t, !sdl_platform_windows_publish_with_operations(
        platform, {}, operations))
    testing.expect_value(t, state.hwnd_calls, 1)
    testing.expect_value(t, state.publish_calls, 1)
    testing.expect_value(t, state.show_calls, 1)
    testing.expect(t, platform^.window_shown)

    testing.expect(t, !sdl_platform_windows_publish_with_operations(
        platform, {}, operations))
    testing.expect_value(t, state.hwnd_calls, 1)
    testing.expect_value(t, state.publish_calls, 1)
    testing.expect_value(t, state.show_calls, 1)
}

// Verify Windows content scaling preserves baseline application dimensions.
@(test)
sdl_hidpi_windows_content_coordinates_scale :: proc(t: ^testing.T) {
    content_scale := sdl_content_scale(1.5, 1)
    testing.expect_value(t, content_scale, f32(1.5))
    testing.expect_value(t, sdl_startup_extent(1280, content_scale), 1920)
    testing.expect_value(t, sdl_application_extent(1920, 1.5), 1280)
    testing.expect_value(t,
        sdl_application_coordinate(960, content_scale), f32(640))
}

// Verify Retina pixel density adds detail without changing content coordinates.
@(test)
sdl_hidpi_retina_density_preserves_content_coordinates :: proc(t: ^testing.T) {
    content_scale := sdl_content_scale(2, 2)
    testing.expect_value(t, content_scale, f32(1))
    testing.expect_value(t, sdl_startup_extent(1280, content_scale), 1280)
    testing.expect_value(t, sdl_application_extent(2560, 2), 1280)
    testing.expect_value(t,
        sdl_application_coordinate(640, content_scale), f32(640))
}

// Verify failed SDL scale queries retain usable one-to-one coordinates.
@(test)
sdl_hidpi_invalid_scales_fall_back_to_one :: proc(t: ^testing.T) {
    testing.expect_value(t, sdl_content_scale(0, 0), f32(1))
    testing.expect_value(t, sdl_content_scale(0, 2), f32(1))
    testing.expect_value(t, sdl_content_scale(2, 0), f32(1))
    testing.expect_value(t, sdl_application_extent(1280, 0), 1280)
    testing.expect_value(t, sdl_application_coordinate(640, 0), f32(640))
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