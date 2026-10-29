package native

import testing "core:testing"
import sdl "vendor:sdl3"

// Sdl_Target_Test owns fake handles and records exactly which transaction was retired.
Sdl_Target_Test :: struct {
    metrics: Sdl_Window_Metrics,
    create_ok: bool,
    wait_ok: bool,
    creates: int,
    releases: int,
    released: ^sdl.GPUTexture,
}

SDL_TARGET_TEST_OPERATIONS :: Sdl_Scene_Target_Operations{
    metrics = sdl_target_test_metrics,
    create = sdl_target_test_create,
    wait = sdl_target_test_wait,
    release = sdl_target_test_release,
}

// sdl_target_test_metrics reads deterministic observations from the borrowed window handle.
sdl_target_test_metrics :: proc(window: ^sdl.Window) -> (Sdl_Window_Metrics, bool) {
    fixture := cast(^Sdl_Target_Test)window
    return fixture^.metrics, true
}

// sdl_target_test_create returns a distinct candidate only when allocation succeeds.
sdl_target_test_create :: proc(
    device: ^sdl.GPUDevice, _: u32, _: u32, _: sdl.GPUSampleCount) -> Sdl_Scene_Targets {
    fixture := cast(^Sdl_Target_Test)device
    fixture^.creates += 1
    if !fixture^.create_ok {
        return {}
    }
    return {
        scene = cast(^sdl.GPUTexture)&fixture^.creates,
    }
}

// sdl_target_test_wait controls whether the outstanding target is safe to retire.
sdl_target_test_wait :: proc(device: ^sdl.GPUDevice) -> bool {
    return (cast(^Sdl_Target_Test)device)^.wait_ok
}

// sdl_target_test_release records retirement without touching a GPU.
sdl_target_test_release :: proc(
    device: ^sdl.GPUDevice, scene: ^sdl.GPUTexture, _: ^sdl.GPUTexture) {
    fixture := cast(^Sdl_Target_Test)device
    fixture^.releases += 1
    fixture^.released = scene
}

// Verify failed allocation/fencing preserves last-good extents; success publishes before encoding.
@(test)
sdl_target_admission_is_transactional :: proc(t: ^testing.T) {
    fixture: Sdl_Target_Test = {
        metrics = {
            logical_width = 400,
            logical_height = 800,
            pixel_width = 800,
            pixel_height = 1600,
        },
    }
    platform := new(Sdl_Platform, context.allocator)
    defer free(platform, context.allocator)
    platform^.window = cast(^sdl.Window)&fixture
    platform^.device = cast(^sdl.GPUDevice)&fixture
    platform^.scene_target = cast(^sdl.GPUTexture)&fixture.metrics
    platform^.scene_width, platform^.scene_height = 1280, 720
    platform^.resize_pending = true
    original := platform^.scene_target
    testing.expect(t, !sdl_platform_refresh_target(platform, SDL_TARGET_TEST_OPERATIONS))
    testing.expect_value(t, platform^.scene_width, u32(1280))
    testing.expect_value(t, platform^.scene_target, original)
    fixture.create_ok = true
    testing.expect(t, !sdl_platform_refresh_target(platform, SDL_TARGET_TEST_OPERATIONS))
    testing.expect_value(t, fixture.releases, 1)
    testing.expect_value(t, fixture.released, cast(^sdl.GPUTexture)&fixture.creates)
    testing.expect_value(t, platform^.scene_target, original)
    fixture.wait_ok = true
    testing.expect(t, sdl_platform_refresh_target(platform, SDL_TARGET_TEST_OPERATIONS))
    testing.expect_value(t, fixture.released, original)
    testing.expect_value(t, platform^.metrics, fixture.metrics)
    testing.expect_value(t, platform^.scene_width, u32(800))
    testing.expect_value(t, platform^.scene_height, u32(1600))
    testing.expect(t, !platform^.resize_pending)
    fixture.metrics.logical_width = 800
    testing.expect(t, sdl_platform_refresh_target(platform, SDL_TARGET_TEST_OPERATIONS))
    testing.expect_value(t, platform^.metrics.logical_width, 800)
    testing.expect_value(t, fixture.creates, 3)
}
