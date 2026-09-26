package native

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import sdl "vendor:sdl3"
import image "vendor:sdl3/image"

// gif_encoder_test_path creates one allocator-owned temporary GIF path.
gif_encoder_test_path :: proc(filename: string) -> (string, bool) {
    directory, directory_error := os.temp_directory(context.temp_allocator)
    if directory_error != nil {return "", false}
    path, path_error := filepath.join(
        []string{directory, filename}, context.allocator)
    return path, path_error == nil && len(path) > 0
}

// gif_encoder_test_decode verifies dimensions and delays from one encoded stream.
gif_encoder_test_decode :: proc(path: cstring) -> bool {
    stream := sdl.IOFromFile(path, "rb")
    if stream == nil {return false}
    decoder := image.CreateAnimationDecoder_IO(stream, true, "GIF")
    if decoder == nil {return false}
    defer image.CloseAnimationDecoder(decoder)
    expected_delays := [2]u64{40, 80}
    for expected_delay in expected_delays {
        frame: ^sdl.Surface
        delay: u64
        if !image.GetAnimationDecoderFrame(decoder, &frame, &delay) {
            return false
        }
        valid := frame != nil && frame.w == 2 && frame.h == 1 &&
            delay == expected_delay
        if frame != nil {sdl.DestroySurface(frame)}
        if !valid {return false}
    }
    frame: ^sdl.Surface
    delay: u64
    return !image.GetAnimationDecoderFrame(decoder, &frame, &delay) &&
        image.GetAnimationDecoderStatus(decoder) == .COMPLETE
}

// Verify the native wrapper validates input and round-trips a streaming GIF.
@(test)
sdl_gif_encoder_streams_two_frames_and_tears_down_safely :: proc(t: ^testing.T) {
    path, path_ok := gif_encoder_test_path("euclid-sdl-gif-encoder-test.gif")
    testing.expect(t, path_ok)
    defer delete(path)
    defer os.remove(path)
    _ = os.remove(path)
    testing.expect(t, os.write_entire_file(path, nil) == nil)
    c_path := strings.clone_to_cstring(path, context.allocator)
    defer delete(c_path)

    encoder: Sdl_Gif_Encoder
    testing.expect(t, !sdl_gif_encoder_begin(
        &encoder, c_path, 0, 1, context.allocator))
    testing.expect(t, sdl_gif_encoder_begin(
        &encoder, c_path, 2, 1, context.allocator))
    pixels := [12]u8{255, 0, 0, 255, 0, 255, 0, 128, 0, 0, 0, 0}
    testing.expect(t, !sdl_gif_encoder_stage_frame(&encoder, {
        pixels = pixels[:], width = 2, height = 1, pitch_bytes = 7}))
    testing.expect(t, sdl_gif_encoder_stage_frame(&encoder, {
        pixels = pixels[:], width = 2, height = 1, pitch_bytes = 12}))
    testing.expect(t, !sdl_gif_encoder_close(&encoder))
    testing.expect(t, sdl_gif_encoder_commit_frame(&encoder, 40))
    pixels = {0, 0, 255, 64, 255, 255, 255, 0, 0, 0, 0, 0}
    testing.expect(t, sdl_gif_encoder_stage_frame(&encoder, {
        pixels = pixels[:], width = 2, height = 1, pitch_bytes = 12}))
    pixels = {}
    testing.expect(t, sdl_gif_encoder_commit_frame(&encoder, 80))
    testing.expect(t, sdl_gif_encoder_close(&encoder))
    testing.expect(t, gif_encoder_test_decode(c_path))
    sdl_gif_encoder_abort(&encoder)
    sdl_gif_encoder_abort(&encoder)

    _ = os.remove(path)
    testing.expect(t, sdl_gif_encoder_begin(
        &encoder, c_path, 1, 1, context.allocator))
    testing.expect(t, !sdl_gif_encoder_close(&encoder))
    sdl_gif_encoder_abort(&encoder)
}
