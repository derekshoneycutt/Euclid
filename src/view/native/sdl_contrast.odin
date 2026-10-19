package native

import "core:log"
import "core:thread"

// Sdl_Contrast_Status distinguishes an acquired preference from missing support.
Sdl_Contrast_Status :: enum u8 {
    Not_Queried,
    Pending,
    Supported,
    Unavailable,
    Failed,
}

// Sdl_Contrast_Preference retains the last good value and owns any native query worker.
Sdl_Contrast_Preference :: struct {
    status: Sdl_Contrast_Status,
    requested: bool,
    sampled_seconds: f64,
    focused: bool,
    worker: ^thread.Thread,
    worker_requested: bool,
    worker_status: Sdl_Contrast_Status,
}

// One native acquisition outcome; incomplete work never replaces the last good request.
Sdl_Contrast_Query_Result :: struct {
    requested: bool,
    status: Sdl_Contrast_Status,
    complete: bool,
}

// sdl_platform_refresh_contrast refreshes native policy on focus or every five seconds.
sdl_platform_refresh_contrast :: proc(
    platform: ^Sdl_Platform, now_seconds: f64) -> bool {
    preference := &platform^.contrast
    should_query := sdl_contrast_prepare_query(
        preference, platform^.window_focused, now_seconds)
    result := sdl_query_system_contrast(preference, should_query)
    if result.complete {
        sdl_contrast_commit_query(preference, now_seconds, result)
    }
    return preference^.requested
}

// Reserve a due query while retaining completed status during background refreshes.
sdl_contrast_prepare_query :: proc(
    preference: ^Sdl_Contrast_Preference, focused: bool, now_seconds: f64) -> bool {
    reactivated := focused && !preference^.focused
    preference^.focused = focused
    should_query := preference^.status == .Not_Queried || reactivated ||
        now_seconds - preference^.sampled_seconds >= 5
    if should_query {
        if preference^.status == .Not_Queried {
            preference^.status = .Pending
        }
        preference^.sampled_seconds = now_seconds
    }
    return should_query
}

// sdl_contrast_commit_query retains successful policy across unavailable/failed queries.
sdl_contrast_commit_query :: proc(
    preference: ^Sdl_Contrast_Preference, now_seconds: f64,
    result: Sdl_Contrast_Query_Result) {
    status := result.status
    if status == .Failed && preference^.status != .Failed {
        log.warn("interface_contrast_platform_query_failed")
    } else if status == .Unavailable && preference^.status != .Unavailable {
        log.info("interface_contrast_platform_unavailable")
    }
    if status == .Supported {
        preference^.requested = result.requested
    }
    preference^.status = status
    preference^.sampled_seconds = now_seconds
}
