package files_tests

import "core:testing"

import app_core "../../src/core"
import app_files "../../src/files"

@(test)
gif_encode_begin_rejects_invalid_dimensions :: proc(t: ^testing.T) {
    state := app_core.Gif_Encode_State{}

    testing.expect(t, !app_files.gif_encode_begin(&state, 0, 10))
    testing.expect(t, !app_files.gif_encode_begin(&state, 10, 0))
    testing.expect(t, !app_files.gif_encode_begin(&state, 70000, 10))
}

@(test)
gif_encode_begin_and_end_produces_trailer_without_frames :: proc(t: ^testing.T) {
    state := app_core.Gif_Encode_State{}

    testing.expect(t, app_files.gif_encode_begin(&state, 2, 2))

    result := app_files.gif_encode_end(&state)
    defer app_files.gif_encode_free(&result)

    testing.expect(t, result.data_size > 0)
    testing.expect_value(t, result.data[result.data_size - 1], u8(app_files.GIF_TRAILER))
}

@(test)
gif_encode_frame_round_trip_with_small_rgba_input :: proc(t: ^testing.T) {
    state := app_core.Gif_Encode_State{}

    testing.expect(t, app_files.gif_encode_begin(&state, 2, 2))

    pixels := []u8{
        255, 0, 0, 255,
        0, 255, 0, 255,
        0, 0, 255, 255,
        255, 255, 255, 255,
    }

    ok := app_files.gif_encode_frame(&state, &pixels[0], 2, 10, 0)
    testing.expect(t, ok)

    result := app_files.gif_encode_end(&state)
    defer app_files.gif_encode_free(&result)

    testing.expect(t, result.data_size > 0)
    testing.expect_value(t, result.data[result.data_size - 1], u8(app_files.GIF_TRAILER))
}
