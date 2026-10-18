package native

import "core:log"
import "core:math"
import "core:mem"

import sdl "vendor:sdl3"
import image "vendor:sdl3/image"

// Sdl_Gif_Encoder owns one display-thread SDL_image streaming encoder.
Sdl_Gif_Encoder :: struct {
    handle: ^image.AnimationEncoder,
    width: int,
    height: int,
    frame_count: u64,
    staged_pixels: []u8,
    staged: bool,
}

// Sdl_Gif_Frame describes one borrowed RGBA32 frame copied into native staging.
Sdl_Gif_Frame :: struct {
    pixels: []u8,
    width: int,
    height: int,
    pitch_bytes: int,
}

// Open a GIF stream and allocate staged pixels from the caller's capture domain.
// The allocator is not retained; the caller supplies the same live domain at teardown.
sdl_gif_encoder_begin :: proc(
    encoder: ^Sdl_Gif_Encoder, path: cstring, width, height: int,
    allocator: mem.Allocator) -> bool {
    if encoder == nil || encoder.handle != nil || path == nil ||
    width <= 0 || height <= 0 || width > int(math.max(i32)) ||
    height > int(math.max(i32)) || width > math.max(int) / 4 ||
    height > math.max(int) / (width * 4) || allocator.procedure == nil {
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
    staged_pixels, allocation_error := make([]u8, width * height * 4, allocator)
    if allocation_error != nil {
        _ = image.CloseAnimationEncoder(handle)
        return false
    }
    encoder^ = {handle = handle, width = width, height = height,
        staged_pixels = staged_pixels}
    return true
}

// sdl_gif_encoder_stage_frame copies one borrowed RGBA32 frame into bounded storage.
sdl_gif_encoder_stage_frame :: proc(
    encoder: ^Sdl_Gif_Encoder, frame: Sdl_Gif_Frame) -> bool {
    if encoder == nil || encoder.handle == nil || encoder.staged ||
       frame.width != encoder.width ||
       frame.height != encoder.height || frame.width <= 0 || frame.height <= 0 ||
       frame.width > int(math.max(i32)) / 4 ||
       frame.pitch_bytes < frame.width * 4 ||
       frame.height > math.max(int) / frame.pitch_bytes ||
       len(frame.pixels) < frame.pitch_bytes * frame.height ||
       frame.pitch_bytes > int(math.max(i32)) {
        return false
    }
    row_bytes := frame.width * 4
    for row in 0..<frame.height {
        source := frame.pixels[row * frame.pitch_bytes:][:row_bytes]
        destination := encoder.staged_pixels[row * row_bytes:][:row_bytes]
        copy(destination, source)
    }
    encoder.staged = true
    return true
}

// sdl_gif_encoder_commit_frame submits and clears the staged frame.
sdl_gif_encoder_commit_frame :: proc(
    encoder: ^Sdl_Gif_Encoder, duration_ms: u64) -> bool {
    if encoder == nil || encoder.handle == nil || !encoder.staged ||
       duration_ms == 0 {
        return false
    }
    pitch_bytes := encoder.width * 4
    surface := sdl.CreateSurfaceFrom(
        i32(encoder.width), i32(encoder.height), .RGBA32,
        raw_data(encoder.staged_pixels), i32(pitch_bytes))
    if surface == nil {
       return false
    }
    defer sdl.DestroySurface(surface)
    if !image.AddAnimationEncoderFrame(
        encoder.handle, surface, duration_ms) {
        log.errorf("sdl_gif_encoder_frame_failed error=%s", sdl.GetError())
        return false
    }
    encoder.frame_count += 1
    encoder.staged = false
    return true
}

// Close one nonempty stream and release staging through its original owner allocator.
sdl_gif_encoder_close :: proc(
    encoder: ^Sdl_Gif_Encoder, allocator: mem.Allocator) -> bool {
    if encoder == nil || encoder.handle == nil || encoder.staged {
       return false
    }
    handle := encoder.handle
    has_frames := encoder.frame_count > 0
    staged_pixels := encoder.staged_pixels
    encoder^ = {}
    closed := image.CloseAnimationEncoder(handle)
    delete(staged_pixels, allocator)
    if !closed {
        log.errorf("sdl_gif_encoder_close_failed error=%s", sdl.GetError())
    }
    return has_frames && closed
}

// Close and clear one stream without publication, releasing staging through its owner.
sdl_gif_encoder_abort :: proc(
    encoder: ^Sdl_Gif_Encoder, allocator: mem.Allocator) {
    if encoder == nil {
       return
    }
    if encoder.handle != nil {
        _ = image.CloseAnimationEncoder(encoder.handle)
    }
    if len(encoder.staged_pixels) > 0 && allocator.procedure != nil {
        delete(encoder.staged_pixels, allocator)
    }
    encoder^ = {}
}