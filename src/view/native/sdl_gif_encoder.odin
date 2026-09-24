package native

import "core:log"
import "core:math"

import sdl "vendor:sdl3"
import image "vendor:sdl3/image"

// Sdl_Gif_Encoder owns one display-thread SDL_image streaming encoder.
Sdl_Gif_Encoder :: struct {
    handle: ^image.AnimationEncoder,
    width: int,
    height: int,
    frame_count: u64,
}

// Sdl_Gif_Frame describes one borrowed RGBA32 frame submitted synchronously.
Sdl_Gif_Frame :: struct {
    pixels: []u8,
    width: int,
    height: int,
    pitch_bytes: int,
    duration_ms: u64,
}

// sdl_gif_encoder_begin opens one GIF stream at an exact temporary path.
sdl_gif_encoder_begin :: proc(
    encoder: ^Sdl_Gif_Encoder, path: cstring, width, height: int) -> bool {
    if encoder == nil || encoder.handle != nil || path == nil ||
    width <= 0 || height <= 0 || width > int(math.max(i32)) ||
    height > int(math.max(i32)) {
        return false
    }
    stream := sdl.IOFromFile(path, "wb")
    if stream == nil {
        log.errorf("sdl_gif_encoder_stream_failed error=%s", sdl.GetError())
        return false
    }
    handle := image.CreateAnimationEncoder_IO(stream, true, "GIF")
    if handle == nil {
        log.errorf("sdl_gif_encoder_begin_failed error=%s", sdl.GetError())
        return false
    }
    encoder^ = {handle = handle, width = width, height = height}
    return true
}

// sdl_gif_encoder_add_frame synchronously submits one borrowed RGBA32 frame.
sdl_gif_encoder_add_frame :: proc(
    encoder: ^Sdl_Gif_Encoder, frame: Sdl_Gif_Frame) -> bool {
    if encoder == nil || encoder.handle == nil || frame.width != encoder.width ||
       frame.height != encoder.height || frame.width <= 0 || frame.height <= 0 ||
       frame.width > int(math.max(i32)) / 4 ||
       frame.pitch_bytes < frame.width * 4 ||
       frame.height > math.max(int) / frame.pitch_bytes ||
       len(frame.pixels) < frame.pitch_bytes * frame.height ||
       frame.pitch_bytes > int(math.max(i32)) || frame.duration_ms == 0 {
        return false
    }
    surface := sdl.CreateSurfaceFrom(
        i32(frame.width), i32(frame.height), .RGBA32,
        raw_data(frame.pixels), i32(frame.pitch_bytes))
    if surface == nil {return false}
    defer sdl.DestroySurface(surface)
    if !image.AddAnimationEncoderFrame(
        encoder.handle, surface, frame.duration_ms) {
        log.errorf("sdl_gif_encoder_frame_failed error=%s", sdl.GetError())
        return false
    }
    encoder.frame_count += 1
    return true
}

// sdl_gif_encoder_close closes one nonempty stream exactly once.
sdl_gif_encoder_close :: proc(encoder: ^Sdl_Gif_Encoder) -> bool {
    if encoder == nil || encoder.handle == nil {return false}
    handle := encoder.handle
    has_frames := encoder.frame_count > 0
    encoder^ = {}
    closed := image.CloseAnimationEncoder(handle)
    if !closed {
        log.errorf("sdl_gif_encoder_close_failed error=%s", sdl.GetError())
    }
    return has_frames && closed
}

// sdl_gif_encoder_abort closes and clears one stream without publishing it.
sdl_gif_encoder_abort :: proc(encoder: ^Sdl_Gif_Encoder) {
    if encoder == nil {return}
    if encoder.handle != nil {
        _ = image.CloseAnimationEncoder(encoder.handle)
    }
    encoder^ = {}
}