package view_core

import "core:mem"
import "core:math"

FRAMEBUFFER_PIXEL_BYTES :: 4

// Framebuffer_Capture_Operations supplies native calls used by synchronous capture.
Framebuffer_Capture_Operations :: struct {
    user_data: rawptr,
    allocator: mem.Allocator,
    load: proc(user_data: rawptr, allocator: mem.Allocator) -> Framebuffer_Pixels,
    unload: proc(user_data: rawptr, capture: ^Framebuffer_Pixels),
    export: proc(
        user_data: rawptr, capture: ^Framebuffer_Pixels, path: cstring) -> bool,
}

// Framebuffer_Pixels owns one synchronous top-left RGBA8 image on the display thread.
Framebuffer_Pixels :: struct {
    pixels: []u8,
    width: int,
    height: int,
    pitch_bytes: int,
}

// Return whether one image satisfies the owned top-left RGBA8 capture contract.
framebuffer_image_valid :: proc(capture: Framebuffer_Pixels) -> bool {
    if len(capture.pixels) == 0 || capture.width <= 0 || capture.height <= 0 ||
        capture.width > math.max(int) / FRAMEBUFFER_PIXEL_BYTES {
        return false
    }
    row_bytes := capture.width * FRAMEBUFFER_PIXEL_BYTES
    if capture.pitch_bytes < row_bytes ||
        capture.height > math.max(int) / capture.pitch_bytes {
        return false
    }
    return len(capture.pixels) >= capture.pitch_bytes * capture.height
}

// Acquire and validate one synchronous framebuffer image through injected operations.
framebuffer_acquire_with_operations :: proc(
    operations: Framebuffer_Capture_Operations) -> (Framebuffer_Pixels, bool) {
    if operations.load == nil || operations.unload == nil ||
        operations.allocator.procedure == nil {
        return {}, false
    }
    capture := operations.load(operations.user_data, operations.allocator)
    if framebuffer_image_valid(capture) {
        return capture, true
    }
    if len(capture.pixels) > 0 {
        operations.unload(operations.user_data, &capture)
    }
    return {}, false
}

// Release one acquired framebuffer image and clear all borrowed metadata.
framebuffer_release_with_operations :: proc(
    capture: ^Framebuffer_Pixels, operations: Framebuffer_Capture_Operations) {
    if capture == nil {
        return
    }
    if len(capture.pixels) > 0 && operations.unload != nil {
        operations.unload(operations.user_data, capture)
    }
    capture^ = {}
}

// Replace one capture with a tightly packed top-left crop.
framebuffer_crop_with_operations :: proc(
    capture: ^Framebuffer_Pixels, width, height: int,
    operations: Framebuffer_Capture_Operations) -> bool {
    if capture == nil || !framebuffer_image_valid(capture^) ||
        operations.allocator.procedure == nil ||
        width <= 0 || height <= 0 || width > capture.width || height > capture.height {
        return false
    }
    row_bytes := width * FRAMEBUFFER_PIXEL_BYTES
    pixels, allocation_error := make(
        []u8, row_bytes * height, operations.allocator)
    if allocation_error != nil {return false}
    for row in 0..<height {
        source := capture.pixels[row * capture.pitch_bytes:][:row_bytes]
        copy(pixels[row * row_bytes:][:row_bytes], source)
    }
    operations.unload(operations.user_data, capture)
    capture^ = {pixels = pixels, width = width, height = height,
        pitch_bytes = row_bytes}
    return true
}

// Replace one capture with a tightly packed nearest-neighbor resize.
framebuffer_resize_with_operations :: proc(
    capture: ^Framebuffer_Pixels, width, height: int,
    operations: Framebuffer_Capture_Operations) -> bool {
    if capture == nil || !framebuffer_image_valid(capture^) ||
        operations.allocator.procedure == nil || width <= 0 || height <= 0 ||
        width > math.max(int) / FRAMEBUFFER_PIXEL_BYTES ||
        height > math.max(int) / (width * FRAMEBUFFER_PIXEL_BYTES) {
        return false
    }
    row_bytes := width * FRAMEBUFFER_PIXEL_BYTES
    pixels, allocation_error := make(
        []u8, row_bytes * height, operations.allocator)
    if allocation_error != nil {return false}
    for y in 0..<height {
        source_y := y * capture.height / height
        for x in 0..<width {
            source_x := x * capture.width / width
            source := source_y * capture.pitch_bytes + source_x * FRAMEBUFFER_PIXEL_BYTES
            destination := y * row_bytes + x * FRAMEBUFFER_PIXEL_BYTES
            copy(pixels[destination:][:FRAMEBUFFER_PIXEL_BYTES],
                capture.pixels[source:][:FRAMEBUFFER_PIXEL_BYTES])
        }
    }
    operations.unload(operations.user_data, capture)
    capture^ = {pixels = pixels, width = width, height = height,
        pitch_bytes = row_bytes}
    return true
}

// Export one acquired framebuffer image through the current native image codec.
framebuffer_export_with_operations :: proc(
    capture: ^Framebuffer_Pixels, path: cstring,
    operations: Framebuffer_Capture_Operations) -> bool {
    return capture != nil && framebuffer_image_valid(capture^) && path != nil &&
        operations.export != nil &&
        operations.export(operations.user_data, capture, path)
}
