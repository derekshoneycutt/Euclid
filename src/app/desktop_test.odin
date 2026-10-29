package app

import testing "core:testing"
import sdl "vendor:sdl3"

// Verify close/scenario success and startup/runtime failure map to distinct SDL outcomes.
@(test)
desktop_callback_result_mapping :: proc(t: ^testing.T) {
    testing.expect_value(t, desktop_result(true, true), sdl.AppResult.CONTINUE)
    testing.expect_value(t, desktop_result(false, true), sdl.AppResult.SUCCESS)
    testing.expect_value(t, desktop_result(false, false), sdl.AppResult.FAILURE)
    testing.expect_value(t, desktop_result(true, false), sdl.AppResult.FAILURE)
}
