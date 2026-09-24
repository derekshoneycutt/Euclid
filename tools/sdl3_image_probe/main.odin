package main

import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import image "vendor:sdl3/image"

Probe_Frame_Duration_First :: u64(40)
Probe_Frame_Duration_Second :: u64(80)

// probe_failure reports one bounded native failure and returns a process failure code.
probe_failure :: proc(stage: string) -> int {
    fmt.eprintf("probe.failed_stage=%s\n", stage)
    fmt.eprintf("probe.error=%s\n", sdl.GetError())
    fmt.eprintf("probe.result=failed\n")
    return 1
}

// probe_static_load verifies one typed decoder returns the expected one-pixel surface.
probe_static_load :: proc(path, image_type: cstring) -> bool {
    stream := sdl.IOFromFile(path, "rb")
    if stream == nil { return false }
    surface := image.LoadTyped_IO(stream, true, image_type)
    if surface == nil { return false }
    defer sdl.DestroySurface(surface)
    return surface.w == 1 && surface.h == 1
}

// probe_encode_animation writes two borrowed RGBA32 frames through the streaming API.
probe_encode_animation :: proc(path: cstring) -> bool {
    encoder := image.CreateAnimationEncoder(path)
    if encoder == nil { return false }
    pixels := [8]u8{255, 0, 0, 255, 0, 255, 0, 128}
    surface := sdl.CreateSurfaceFrom(2, 1, .RGBA32, raw_data(pixels[:]), 8)
    if surface == nil {
        image.CloseAnimationEncoder(encoder)
        return false
    }
    defer sdl.DestroySurface(surface)
    if !image.AddAnimationEncoderFrame(
        encoder, surface, Probe_Frame_Duration_First) {
        image.CloseAnimationEncoder(encoder)
        return false
    }
    pixels = {0, 0, 255, 64, 255, 255, 255, 0}
    if !image.AddAnimationEncoderFrame(
        encoder, surface, Probe_Frame_Duration_Second) {
        image.CloseAnimationEncoder(encoder)
        return false
    }
    return image.CloseAnimationEncoder(encoder)
}

// probe_decode_animation streams every encoded frame and verifies dimensions and delays.
probe_decode_animation :: proc(path: cstring) -> (frame_count: int, valid: bool) {
    stream := sdl.IOFromFile(path, "rb")
    if stream == nil { return 0, false }
    decoder := image.CreateAnimationDecoder_IO(stream, true, "GIF")
    if decoder == nil { return 0, false }
    defer image.CloseAnimationDecoder(decoder)
    expected_durations := [2]u64{
        Probe_Frame_Duration_First, Probe_Frame_Duration_Second}
    for frame_count < len(expected_durations) {
        frame: ^sdl.Surface
        duration: u64
        if !image.GetAnimationDecoderFrame(decoder, &frame, &duration) {
            return frame_count, false
        }
        if frame == nil || frame.w != 2 || frame.h != 1 ||
            duration != expected_durations[frame_count] {
            if frame != nil { sdl.DestroySurface(frame) }
            return frame_count, false
        }
        sdl.DestroySurface(frame)
        frame_count += 1
    }
    frame: ^sdl.Surface
    duration: u64
    if image.GetAnimationDecoderFrame(decoder, &frame, &duration) {
        return frame_count, false
    }
    return frame_count, image.GetAnimationDecoderStatus(decoder) == .COMPLETE
}

// main exercises required SDL_image static and streaming GIF capabilities headlessly.
main :: proc() {
    if len(os.args) != 5 {
        fmt.eprintln("usage: probe JPEG PNG GIF OUTPUT")
        os.exit(2)
    }
    fmt.printf("probe.binding_version=%d.%d.%d\n",
        image.MAJOR_VERSION, image.MINOR_VERSION, image.PATCHLEVEL)
    fmt.printf("probe.runtime_version=%d\n", image.Version())
    jpeg_path := strings.clone_to_cstring(os.args[1], context.allocator)
    png_path := strings.clone_to_cstring(os.args[2], context.allocator)
    gif_path := strings.clone_to_cstring(os.args[3], context.allocator)
    output_path := strings.clone_to_cstring(os.args[4], context.allocator)
    defer delete(jpeg_path)
    defer delete(png_path)
    defer delete(gif_path)
    defer delete(output_path)
    if !probe_static_load(jpeg_path, "JPG") {
        os.exit(probe_failure("jpeg_decode"))
    }
    fmt.println("probe.jpeg_decode=true")
    if !probe_static_load(png_path, "PNG") {
        os.exit(probe_failure("png_decode"))
    }
    fmt.println("probe.png_decode=true")
    if !probe_static_load(gif_path, "GIF") {
        os.exit(probe_failure("gif_decode"))
    }
    fmt.println("probe.gif_decode=true")
    if !probe_encode_animation(output_path) {
        os.exit(probe_failure("gif_encode"))
    }
    fmt.println("probe.gif_encode=true")
    frame_count, animation_valid := probe_decode_animation(output_path)
    fmt.printf("probe.animation_frames=%d\n", frame_count)
    fmt.printf("probe.animation_delays=%d,%d\n",
        Probe_Frame_Duration_First, Probe_Frame_Duration_Second)
    if !animation_valid {
        os.exit(probe_failure("gif_stream_decode"))
    }
    fmt.println("probe.gif_stream_decode=true")
    fmt.println("probe.cleanup_complete=true")
    fmt.println("probe.result=passed")
}
