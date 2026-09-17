package capture_raylib

// Package capture_raylib owns synchronous Raylib framebuffer and image lifetimes.

import capture ".."
import rl "vendor:raylib"

// Acquire the current framebuffer into a Raylib-owned native image.
capture_native_framebuffer :: proc() -> (rl.Image, bool) {
    image := rl.LoadImageFromScreen()
    return image, image.data != nil
}

// Crop one native image to the requested bounded framebuffer region.
crop_native_frame :: proc(image: ^rl.Image, region: capture.Region) -> bool {
    if region.width == 0 && region.height == 0 {
        return true
    }
    if region.x >= int(image.width) || region.y >= int(image.height) {
        return false
    }
    width := min(region.width, int(image.width) - region.x)
    height := min(region.height, int(image.height) - region.y)
    rl.ImageCrop(image, {f32(region.x), f32(region.y), f32(width), f32(height)})
    return image.data != nil && image.width == i32(width) && image.height == i32(height)
}

// Resize one native image to an explicitly requested output extent.
resize_native_frame :: proc(image: ^rl.Image, output: capture.Extent) -> bool {
    if output.width == 0 && output.height == 0 {
        return true
    }
    if int(image.width) == output.width && int(image.height) == output.height {
        return true
    }
    rl.ImageResizeNN(image, i32(output.width), i32(output.height))
    return image.data != nil && image.width == i32(output.width) &&
        image.height == i32(output.height)
}

// Convert one native image to the portable RGBA8 capture format.
normalize_native_frame :: proc(image: ^rl.Image, format: capture.Pixel_Format) -> bool {
    if format != .Rgba8 {
        return false
    }
    rl.ImageFormat(image, rl.PixelFormat.UNCOMPRESSED_R8G8B8A8)
    return image.data != nil && image.format == rl.PixelFormat.UNCOMPRESSED_R8G8B8A8
}

// Release pixel storage originally acquired by the Raylib adapter.
release_frame :: proc(frame: ^capture.Owned_Frame) {
    if frame == nil || len(frame.pixels) == 0 {
        return
    }
    image := rl.Image{
        data = raw_data(frame.pixels),
        width = i32(frame.width),
        height = i32(frame.height),
        mipmaps = 1,
        format = rl.PixelFormat.UNCOMPRESSED_R8G8B8A8,
    }
    rl.UnloadImage(image)
}

// Apply crop, resize, and pixel-format normalization after framebuffer acquisition.
prepare_native_frame :: proc(
    image: ^rl.Image, request: capture.Request,
    completion: ^capture.Completion) -> bool {
    if !crop_native_frame(image, request.region) {
        return false
    }
    resize_required := request.output.width > 0 &&
        (int(image.width) != request.output.width ||
        int(image.height) != request.output.height)
    if !resize_native_frame(image, request.output) {
        return false
    }
    format_changed := image.format != rl.PixelFormat.UNCOMPRESSED_R8G8B8A8
    if !normalize_native_frame(image, request.format) {
        return false
    }
    if resize_required || format_changed {
        completion.normalization_bytes = u64(image.width) * u64(image.height) * 4
    }
    return true
}

// Transfer one prepared Raylib allocation into an application-owned frame contract.
own_native_frame :: proc(image: rl.Image) -> capture.Owned_Frame {
    byte_count := int(image.width) * int(image.height) * 4
    return {
        pixels = (cast([^]u8)image.data)[:byte_count],
        width = int(image.width),
        height = int(image.height),
        pitch = int(image.width) * 4,
        format = .Rgba8,
        release = release_frame,
    }
}

// Acquire and normalize one framebuffer request synchronously.
acquire :: proc(request: capture.Request) -> capture.Completion {
    completion := capture.Completion{
        status = .Failed,
        target = request.target,
        identity = request.identity,
        failure_reason = .Invalid_Request,
    }
    if !capture.request_valid(request) {
        return completion
    }
    image, acquired := capture_native_framebuffer()
    if !acquired {
        completion.failure_reason = .Readback_Failed
        return completion
    }
    completion.readback_bytes = u64(image.width) * u64(image.height) * 4
    if !prepare_native_frame(&image, request, &completion) {
        rl.UnloadImage(image)
        completion.failure_reason = .Normalization_Failed
        return completion
    }
    completion.frame = own_native_frame(image)
    completion.status = .Completed
    completion.failure_reason = .None
    return completion
}

// Materialize one acquired RGBA8 frame as a PNG through Raylib image encoding.
write_png :: proc(frame: ^capture.Owned_Frame, path: cstring) -> bool {
    if !capture.frame_valid(frame) || path == nil {
        return false
    }
    image := rl.Image{
        data = raw_data(frame.pixels),
        width = i32(frame.width),
        height = i32(frame.height),
        mipmaps = 1,
        format = rl.PixelFormat.UNCOMPRESSED_R8G8B8A8,
    }
    return rl.ExportImage(image, path)
}