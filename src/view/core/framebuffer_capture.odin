package view_core

import "core:math"

import rl "vendor:raylib"

FRAMEBUFFER_PIXEL_BYTES :: 4

// Framebuffer_Capture_Operations supplies native calls used by synchronous capture.
Framebuffer_Capture_Operations :: struct {
    user_data: rawptr,
    load: proc(user_data: rawptr) -> rl.Image,
    unload: proc(user_data: rawptr, image: rl.Image),
    crop: proc(user_data: rawptr, image: ^rl.Image, bounds: rl.Rectangle),
    resize: proc(user_data: rawptr, image: ^rl.Image, width, height: i32),
    export: proc(user_data: rawptr, image: rl.Image, path: cstring) -> bool,
}

// Framebuffer_Pixels owns one synchronous Raylib framebuffer image on the display thread.
Framebuffer_Pixels :: struct {
    image: rl.Image,
    pixels: rawptr,
    width: int,
    height: int,
    pitch_bytes: int,
}

FRAMEBUFFER_CAPTURE_OPERATIONS := Framebuffer_Capture_Operations{
    load = framebuffer_raylib_load,
    unload = framebuffer_raylib_unload,
    crop = framebuffer_raylib_crop,
    resize = framebuffer_raylib_resize,
    export = framebuffer_raylib_export,
}

// framebuffer_set_capture_operations replaces the display-owned capture adapter.
framebuffer_set_capture_operations :: proc(operations: Framebuffer_Capture_Operations) {
    FRAMEBUFFER_CAPTURE_OPERATIONS = operations
}

// framebuffer_reset_capture_operations restores the legacy Raylib adapter.
framebuffer_reset_capture_operations :: proc() {
    FRAMEBUFFER_CAPTURE_OPERATIONS = {
        load = framebuffer_raylib_load,
        unload = framebuffer_raylib_unload,
        crop = framebuffer_raylib_crop,
        resize = framebuffer_raylib_resize,
        export = framebuffer_raylib_export,
    }
}

// Return whether one native image satisfies the tightly packed RGBA8 capture contract.
framebuffer_image_valid :: proc(image: rl.Image) -> bool {
    if image.data == nil || image.width <= 0 || image.height <= 0 ||
        image.format != rl.PixelFormat.UNCOMPRESSED_R8G8B8A8 {
        return false
    }
    width := int(image.width)
    height := int(image.height)
    return width <= math.max(int) / FRAMEBUFFER_PIXEL_BYTES &&
        width * FRAMEBUFFER_PIXEL_BYTES <= math.max(int) / height
}

// Refresh borrowed pixel metadata after a native image mutation.
framebuffer_refresh :: proc(capture: ^Framebuffer_Pixels) -> bool {
    if capture == nil || !framebuffer_image_valid(capture.image) {
        return false
    }
    capture.pixels = capture.image.data
    capture.width = int(capture.image.width)
    capture.height = int(capture.image.height)
    capture.pitch_bytes = capture.width * FRAMEBUFFER_PIXEL_BYTES
    return true
}

// Acquire and validate one synchronous framebuffer image through injected operations.
framebuffer_acquire_with_operations :: proc(
    operations: Framebuffer_Capture_Operations) -> (Framebuffer_Pixels, bool) {
    if operations.load == nil || operations.unload == nil {
        return {}, false
    }
    capture := Framebuffer_Pixels{image = operations.load(operations.user_data)}
    if framebuffer_refresh(&capture) {
        return capture, true
    }
    if capture.image.data != nil {
        operations.unload(operations.user_data, capture.image)
    }
    return {}, false
}

// Release one acquired framebuffer image and clear all borrowed metadata.
framebuffer_release_with_operations :: proc(
    capture: ^Framebuffer_Pixels, operations: Framebuffer_Capture_Operations) {
    if capture == nil {
        return
    }
    if capture.image.data != nil && operations.unload != nil {
        operations.unload(operations.user_data, capture.image)
    }
    capture^ = {}
}

// Crop one capture to a top-left rectangle and revalidate its pixel metadata.
framebuffer_crop_with_operations :: proc(
    capture: ^Framebuffer_Pixels, width, height: int,
    operations: Framebuffer_Capture_Operations) -> bool {
    if capture == nil || operations.crop == nil ||
        width <= 0 || height <= 0 || width > capture.width || height > capture.height {
        return false
    }
    operations.crop(operations.user_data, &capture.image,
        rl.Rectangle{0, 0, f32(width), f32(height)})
    return framebuffer_refresh(capture)
}

// Resize one capture with nearest-neighbor filtering and revalidate its metadata.
framebuffer_resize_with_operations :: proc(
    capture: ^Framebuffer_Pixels, width, height: int,
    operations: Framebuffer_Capture_Operations) -> bool {
    if capture == nil || operations.resize == nil || width <= 0 || height <= 0 ||
        width > int(math.max(i32)) || height > int(math.max(i32)) {
        return false
    }
    operations.resize(operations.user_data, &capture.image, i32(width), i32(height))
    return framebuffer_refresh(capture)
}

// Export one acquired framebuffer image through the current native image codec.
framebuffer_export_with_operations :: proc(
    capture: ^Framebuffer_Pixels, path: cstring,
    operations: Framebuffer_Capture_Operations) -> bool {
    return capture != nil && framebuffer_refresh(capture) && path != nil &&
        operations.export != nil &&
        operations.export(operations.user_data, capture.image, path)
}

// Load the current framebuffer through Raylib.
framebuffer_raylib_load :: proc(_: rawptr) -> rl.Image {
    return rl.LoadImageFromScreen()
}

// Release one Raylib-owned framebuffer image.
framebuffer_raylib_unload :: proc(_: rawptr, image: rl.Image) {
    rl.UnloadImage(image)
}

// Crop one Raylib-owned framebuffer image.
framebuffer_raylib_crop :: proc(
    _: rawptr, image: ^rl.Image, bounds: rl.Rectangle) {
    rl.ImageCrop(image, bounds)
}

// Resize one Raylib-owned framebuffer image with nearest-neighbor filtering.
framebuffer_raylib_resize :: proc(
    _: rawptr, image: ^rl.Image, width, height: i32) {
    rl.ImageResizeNN(image, width, height)
}

// Export one Raylib-owned framebuffer image.
framebuffer_raylib_export :: proc(
    _: rawptr, image: rl.Image, path: cstring) -> bool {
    return rl.ExportImage(image, path)
}

// Acquire one synchronous display-owned framebuffer image.
framebuffer_acquire :: proc() -> (Framebuffer_Pixels, bool) {
    return framebuffer_acquire_with_operations(FRAMEBUFFER_CAPTURE_OPERATIONS)
}

// Release one synchronous display-owned framebuffer image.
framebuffer_release :: proc(capture: ^Framebuffer_Pixels) {
    framebuffer_release_with_operations(capture, FRAMEBUFFER_CAPTURE_OPERATIONS)
}

// Crop one framebuffer image to a top-left rectangle.
framebuffer_crop :: proc(capture: ^Framebuffer_Pixels, width, height: int) -> bool {
    return framebuffer_crop_with_operations(
        capture, width, height, FRAMEBUFFER_CAPTURE_OPERATIONS)
}

// Resize one framebuffer image with nearest-neighbor filtering.
framebuffer_resize :: proc(capture: ^Framebuffer_Pixels, width, height: int) -> bool {
    return framebuffer_resize_with_operations(
        capture, width, height, FRAMEBUFFER_CAPTURE_OPERATIONS)
}

// Export one framebuffer image through Raylib's current image codec.
framebuffer_export :: proc(capture: ^Framebuffer_Pixels, path: cstring) -> bool {
    return framebuffer_export_with_operations(
        capture, path, FRAMEBUFFER_CAPTURE_OPERATIONS)
}