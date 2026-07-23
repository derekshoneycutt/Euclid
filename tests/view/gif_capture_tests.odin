package view_tests

import "core:strings"
import "core:testing"

import app_core "../../src/core"
import app_view "../../src/view/core"

@(test)
clear_and_set_gif_status_note_handles_truncation :: proc(t: ^testing.T) {
    ui_runtime := new(app_core.Euclid_UI_Runtime_State)
    defer free(ui_runtime)

    app_view.clear_gif_status_note(ui_runtime)
    testing.expect_value(t, ui_runtime^.gif_status_note_len, 0)
    testing.expect_value(t, ui_runtime^.gif_status_note[0], u8(0))

    long_note := strings.repeat("x", len(ui_runtime^.gif_status_note) + 20, context.temp_allocator)
    app_view.set_gif_status_note(ui_runtime, long_note)

    expected_len := len(ui_runtime^.gif_status_note) - 1
    testing.expect_value(t, ui_runtime^.gif_status_note_len, expected_len)
    testing.expect_value(t, ui_runtime^.gif_status_note[expected_len], u8(0))
}

@(test)
clear_and_set_last_gif_path_handles_truncation :: proc(t: ^testing.T) {
    ui_runtime := new(app_core.Euclid_UI_Runtime_State)
    defer free(ui_runtime)

    app_view.clear_last_gif_path(ui_runtime)
    testing.expect_value(t, ui_runtime^.last_gif_path_len, 0)
    testing.expect_value(t, ui_runtime^.last_gif_path[0], u8(0))

    long_path := strings.repeat("a", len(ui_runtime^.last_gif_path) + 32, context.temp_allocator)
    app_view.set_last_gif_path(ui_runtime, long_path)

    expected_len := len(ui_runtime^.last_gif_path) - 1
    testing.expect_value(t, ui_runtime^.last_gif_path_len, expected_len)
    testing.expect_value(t, ui_runtime^.last_gif_path[expected_len], u8(0))
}

@(test)
gif_capture_delay_centiseconds_matches_expected_steps :: proc(t: ^testing.T) {
    testing.expect_value(t, app_view.gif_capture_delay_centiseconds(1), 2)
    testing.expect_value(t, app_view.gif_capture_delay_centiseconds(4), 7)
    testing.expect_value(t, app_view.gif_capture_delay_centiseconds(0), 1)
}

@(test)
gif_capture_consume_cycle_boundary_consumes_once_per_generation :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)

    testing.expect(t, !app_view.gif_capture_consume_cycle_boundary(state))

    state^.cycle_boundary_generation = 1
    testing.expect(t, app_view.gif_capture_consume_cycle_boundary(state))
    testing.expect(t, !app_view.gif_capture_consume_cycle_boundary(state))

    state^.cycle_boundary_generation = 2
    testing.expect(t, app_view.gif_capture_consume_cycle_boundary(state))
}

@(test)
gif_capture_abort_session_is_safe_when_inactive :: proc(t: ^testing.T) {
    session := app_core.Gif_Capture_Session{}
    app_view.gif_capture_abort_session(&session)
    testing.expect(t, !session.active)
}

@(test)
gif_output_filename_has_expected_shape :: proc(t: ^testing.T) {
    name := app_view.gif_output_filename()

    testing.expect(t, strings.has_prefix(name, "Euclid_"))
    testing.expect(t, strings.has_suffix(name, ".gif"))
}
