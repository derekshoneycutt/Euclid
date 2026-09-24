// Package termgraphicsnative owns native codec objects used by Terminal workers.
package termgraphicsnative

import "core:c"
import sdl "vendor:sdl3"
import image "vendor:sdl3/image"

// Static_Image_Format identifies one already-admitted SDL_image decoder.
Static_Image_Format :: enum u8 {
    Png,
    Jpeg,
    Gif,
}

// Animated_Gif_Decode_Request supplies exact caller-owned streaming destinations.
Animated_Gif_Decode_Request :: struct {
    bytes: []u8,
    frame_bytes: []u8,
    width: int,
    height: int,
    frame_count: int,
    cancellation_user_data: rawptr,
    cancellation_requested: proc(user_data: rawptr) -> bool,
}

// Animated_Gif_Decode_Result reports complete production decoder output.
Animated_Gif_Decode_Result :: struct {
    frame_count: int,
    complete: bool,
}

// static_image_type returns the explicit SDL_image type for one admitted format.
static_image_type :: proc(format: Static_Image_Format) -> cstring {
    switch format {
    case .Png: return "PNG"
    case .Jpeg: return "JPG"
    case .Gif: return "GIF"
    }
    return ""
}

// Decode_Static_Image decodes one borrowed image into exact caller-owned RGBA8 storage.
Decode_Static_Image :: proc(
    bytes: []u8, output: []u8, width, height: int,
    format: Static_Image_Format) -> bool {
    if len(bytes) == 0 || width <= 0 || height <= 0 ||
        width > int(max(c.int)) || height > int(max(c.int)) ||
        width > max(int) / height || width * height > max(int) / 4 ||
        len(output) != width * height * 4 {
        return false
    }
    stream := sdl.IOFromConstMem(raw_data(bytes), uint(len(bytes)))
    if stream == nil { return false }
    surface := image.LoadTyped_IO(stream, true, static_image_type(format))
    if surface == nil { return false }
    defer sdl.DestroySurface(surface)
    if int(surface.w) != width || int(surface.h) != height ||
        surface.pixels == nil || surface.pitch <= 0 {
        return false
    }
    return sdl.ConvertPixels(
        surface.w, surface.h, surface.format, surface.pixels, surface.pitch,
        .RGBA32, raw_data(output), c.int(width * 4))
}

// animated_gif_decode_cancelled polls one optional worker cancellation source.
animated_gif_decode_cancelled :: proc(request: ^Animated_Gif_Decode_Request) -> bool {
    return request.cancellation_requested != nil &&
        request.cancellation_requested(request.cancellation_user_data)
}

// animated_gif_decode_request_valid validates exact bounded destinations.
animated_gif_decode_request_valid :: proc(
    request: ^Animated_Gif_Decode_Request) -> bool {
    if request == nil || len(request.bytes) == 0 || request.width <= 0 ||
       request.height <= 0 || request.frame_count <= 0 ||
       request.width > max(int) / request.height ||
       request.width * request.height > max(int) / 4 {
        return false
    }
    canvas_byte_count := request.width * request.height * 4
    return request.frame_count <= max(int) / canvas_byte_count &&
        len(request.frame_bytes) == request.frame_count * canvas_byte_count
}

// animated_gif_decode_frame copies and destroys one decoder-owned surface.
animated_gif_decode_frame :: proc(
    decoder: ^image.AnimationDecoder, destination: []u8,
    width, height: int) -> bool {
    surface: ^sdl.Surface
    ignored_duration_ms: u64
    if !image.GetAnimationDecoderFrame(
        decoder, &surface, &ignored_duration_ms) || surface == nil {
        return false
    }
    defer sdl.DestroySurface(surface)
    return int(surface.w) == width && int(surface.h) == height &&
        surface.pixels != nil && surface.pitch > 0 && sdl.ConvertPixels(
            surface.w, surface.h, surface.format, surface.pixels, surface.pitch,
            .RGBA32, raw_data(destination), c.int(width * 4))
}

// Decode_Animated_Gif streams composited GIF frames into caller-owned RGBA32 storage.
Decode_Animated_Gif :: proc(
    request: ^Animated_Gif_Decode_Request) -> Animated_Gif_Decode_Result {
    if !animated_gif_decode_request_valid(request) ||
       animated_gif_decode_cancelled(request) {
        return {}
    }
    stream := sdl.IOFromConstMem(raw_data(request.bytes), uint(len(request.bytes)))
    if stream == nil {return {}}
    decoder := image.CreateAnimationDecoder_IO(stream, true, "GIF")
    if decoder == nil {return {}}
    defer image.CloseAnimationDecoder(decoder)
    result: Animated_Gif_Decode_Result
    canvas_byte_count := request.width * request.height * 4
    for index in 0..<request.frame_count {
        if animated_gif_decode_cancelled(request) {return {}}
        destination := request.frame_bytes[
            index * canvas_byte_count:][:canvas_byte_count]
        if !animated_gif_decode_frame(
            decoder, destination, request.width, request.height) {return {}}
        result.frame_count += 1
    }
    if animated_gif_decode_cancelled(request) {return {}}
    extra_surface: ^sdl.Surface
    ignored_duration_ms: u64
    if image.GetAnimationDecoderFrame(
        decoder, &extra_surface, &ignored_duration_ms) {
        if extra_surface != nil {sdl.DestroySurface(extra_surface)}
        return {}
    }
    result.complete = image.GetAnimationDecoderStatus(decoder) == .COMPLETE
    return result
}

