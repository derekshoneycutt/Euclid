#+test
package native

import "core:testing"

// motion_test_requested injects a successful reduced-motion query.
motion_test_requested :: proc() -> (bool, Sdl_Motion_Status) {
    return true, .Supported
}

// motion_test_allowed injects a successful full-motion query.
motion_test_allowed :: proc() -> (bool, Sdl_Motion_Status) {
    return false, .Supported
}

// motion_test_failed injects a failed native query.
motion_test_failed :: proc() -> (bool, Sdl_Motion_Status) {
    return false, .Failed
}

// motion_test_unavailable injects an unsupported desktop.
motion_test_unavailable :: proc() -> (bool, Sdl_Motion_Status) {
    return false, .Unavailable
}

// Native policy is bounded in frequency and refreshed immediately on reactivation.
@(test)
sdl_motion_refresh_is_cached_and_focus_sensitive :: proc(t: ^testing.T) {
    platform := new(Sdl_Platform, context.allocator)
    defer free(platform, context.allocator)
    testing.expect(t, sdl_platform_refresh_motion(platform, 0, motion_test_requested))
    testing.expect(t, sdl_platform_refresh_motion(platform, 1, motion_test_allowed))
    platform^.window_focused = true
    testing.expect(t, !sdl_platform_refresh_motion(platform, 2, motion_test_allowed))
    testing.expect_value(t, platform^.motion.sampled_seconds, f64(2))
    testing.expect(t, sdl_platform_refresh_motion(platform, 7, motion_test_requested))
}

// Failure and absence remain explicit and do not erase a previously admitted request.
@(test)
sdl_motion_query_failures_preserve_last_success :: proc(t: ^testing.T) {
    platform := new(Sdl_Platform, context.allocator)
    defer free(platform, context.allocator)
    testing.expect(t, !sdl_platform_refresh_motion(platform, 0, motion_test_unavailable))
    testing.expect_value(t, platform^.motion.status, Sdl_Motion_Status.Unavailable)
    testing.expect(t, sdl_platform_refresh_motion(platform, 5, motion_test_requested))
    testing.expect(t, sdl_platform_refresh_motion(platform, 10, motion_test_failed))
    testing.expect_value(t, platform^.motion.status, Sdl_Motion_Status.Failed)
    testing.expect(t, !sdl_platform_refresh_motion(platform, 15, motion_test_allowed))
}
