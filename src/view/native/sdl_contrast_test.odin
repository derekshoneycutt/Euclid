#+test
package native

import "core:testing"

Sdl_Contrast_Test_Query_State :: struct {
    requested: bool,
    status: Sdl_Contrast_Status,
    query_count: int,
    pending: bool,
    completion_ready: bool,
}

// Exercise production scheduling and publication with a test-owned acquisition outcome.
sdl_contrast_test_refresh :: proc(
    platform: ^Sdl_Platform, now_seconds: f64,
    state: ^Sdl_Contrast_Test_Query_State) -> bool {
    preference := &platform^.contrast
    should_query := sdl_contrast_prepare_query(
        preference, platform^.window_focused, now_seconds)
    result := Sdl_Contrast_Query_Result{
        requested = state^.requested, status = state^.status,
    }
    if state^.completion_ready {
        state^.completion_ready = false
        result.complete = true
    } else if should_query {
        state^.query_count += 1
        result.complete = !state^.pending
    }
    if result.complete {
        sdl_contrast_commit_query(preference, now_seconds, result)
    }
    return preference^.requested
}

// Native contrast policy is cached, refreshed on focus, and refreshed every five seconds.
@(test)
sdl_contrast_refresh_is_cached_and_focus_sensitive :: proc(t: ^testing.T) {
    platform := new(Sdl_Platform, context.allocator)
    defer free(platform, context.allocator)
    state := Sdl_Contrast_Test_Query_State{requested = true, status = .Supported}
    testing.expect(t, sdl_contrast_test_refresh(platform, 0, &state))
    testing.expect(t, sdl_contrast_test_refresh(platform, 1, &state))
    testing.expect_value(t, state.query_count, 1)
    platform^.window_focused = true
    state.requested = false
    testing.expect(t, !sdl_contrast_test_refresh(platform, 2, &state))
    testing.expect_value(t, platform^.contrast.sampled_seconds, f64(2))
    testing.expect_value(t, state.query_count, 2)
    state.requested = true
    testing.expect(t, sdl_contrast_test_refresh(platform, 7, &state))
    testing.expect_value(t, state.query_count, 3)
}

// Failed and unavailable native queries preserve the last successful preference.
@(test)
sdl_contrast_query_failures_preserve_last_success :: proc(t: ^testing.T) {
    platform := new(Sdl_Platform, context.allocator)
    defer free(platform, context.allocator)
    state := Sdl_Contrast_Test_Query_State{status = .Unavailable}
    testing.expect(t, !sdl_contrast_test_refresh(platform, 0, &state))
    testing.expect_value(t, platform^.contrast.status, Sdl_Contrast_Status.Unavailable)
    state.status = .Supported
    state.requested = true
    testing.expect(t, sdl_contrast_test_refresh(platform, 5, &state))
    state.status = .Failed
    state.requested = false
    testing.expect(t, sdl_contrast_test_refresh(platform, 10, &state))
    testing.expect_value(t, platform^.contrast.status, Sdl_Contrast_Status.Failed)
    testing.expect(t, platform^.contrast.requested)
}

// Background retries retain completed status so repeated failures do not log transitions.
@(test)
sdl_contrast_async_retry_preserves_completed_logging_status :: proc(t: ^testing.T) {
    platform := new(Sdl_Platform, context.allocator)
    defer free(platform, context.allocator)
    statuses := [2]Sdl_Contrast_Status{.Unavailable, .Failed}
    for status in statuses {
        platform^.contrast = {
            status = status, requested = true, sampled_seconds = 0,
        }
        state := Sdl_Contrast_Test_Query_State{status = status, pending = true}
        testing.expect(t, sdl_contrast_test_refresh(platform, 5, &state))
        testing.expect_value(t, platform^.contrast.status, status)
        testing.expect_value(t, state.query_count, 1)
        testing.expect(t, sdl_contrast_test_refresh(platform, 5.1, &state))
        testing.expect_value(t, platform^.contrast.status, status)
        testing.expect_value(t, state.query_count, 1)
        state.completion_ready = true
        testing.expect(t, sdl_contrast_test_refresh(platform, 5.2, &state))
        testing.expect_value(t, platform^.contrast.status, status)
    }
}

// Only a first asynchronous acquisition exposes Pending before a completed result.
@(test)
sdl_contrast_initial_async_query_is_pending :: proc(t: ^testing.T) {
    platform := new(Sdl_Platform, context.allocator)
    defer free(platform, context.allocator)
    state := Sdl_Contrast_Test_Query_State{
        status = .Supported, requested = true, pending = true,
    }
    testing.expect(t, !sdl_contrast_test_refresh(platform, 0, &state))
    testing.expect_value(t, platform^.contrast.status, Sdl_Contrast_Status.Pending)
    state.completion_ready = true
    testing.expect(t, sdl_contrast_test_refresh(platform, 0.1, &state))
    testing.expect_value(t, platform^.contrast.status, Sdl_Contrast_Status.Supported)
}
