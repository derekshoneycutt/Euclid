package native

import "core:log"

// Sdl_Motion_Status distinguishes a platform preference from absent native support.
Sdl_Motion_Status :: enum u8 {
    Not_Queried,
    Supported,
    Unavailable,
    Failed,
}

// Sdl_Motion_Preference retains the last successful request through query failures.
Sdl_Motion_Preference :: struct {
    status: Sdl_Motion_Status,
    requested: bool,
    sampled_seconds: f64,
    focused: bool,
}

// sdl_platform_refresh_motion samples native policy on reactivation or every five seconds.
sdl_platform_refresh_motion :: proc(
    platform: ^Sdl_Platform, now_seconds: f64,
    query: proc() -> (bool, Sdl_Motion_Status) = sdl_query_reduced_motion) -> bool {
    preference := &platform^.motion
    reactivated := platform^.window_focused && !preference^.focused
    preference^.focused = platform^.window_focused
    if preference^.status != .Not_Queried && !reactivated &&
        now_seconds - preference^.sampled_seconds < 5 {
        return preference^.requested
    }
    requested, status := query()
    if status == .Failed && preference^.status != .Failed {
        log.warn("interface_motion_platform_query_failed")
    } else if status == .Unavailable && preference^.status != .Unavailable {
        log.info("interface_motion_platform_unavailable")
    }
    if status == .Supported {
        preference^.requested = requested
    }
    preference^.status = status
    preference^.sampled_seconds = now_seconds
    return preference^.requested
}
