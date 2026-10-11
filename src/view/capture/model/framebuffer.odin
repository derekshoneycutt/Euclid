package capturemodel

import runtime "base:runtime"

// Framebuffer_Capture_Operations supplies native calls used by synchronous capture.
Framebuffer_Capture_Operations :: struct {
    user_data: rawptr,
    begin: proc(user_data: rawptr) -> bool,
    allocate: proc(user_data: rawptr, byte_count: int) -> ([]u8, runtime.Allocator_Error),
    load: proc(user_data: rawptr) -> Framebuffer_Pixels,
    unload: proc(user_data: rawptr, capture: ^Framebuffer_Pixels),
    reset: proc(user_data: rawptr),
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

// Gif_Capture_Extents supplies logical, screen and render dimensions for crop policy.
Gif_Capture_Extents :: struct {
    logical_width: int,
    logical_height: int,
    screen_width: int,
    screen_height: int,
    render_width: int,
    render_height: int,
}
