package view

import view_core "core"
import native "native"

import rl "vendor:raylib"

// Sdl_Framebuffer_Context borrows the active display platform for CPU readback.
Sdl_Framebuffer_Context :: struct {
    platform: ^native.Sdl_Platform,
}

// sdl_framebuffer_load downloads the owned scene target into Raylib CPU storage.
sdl_framebuffer_load :: proc(user_data: rawptr) -> rl.Image {
    owner := cast(^Sdl_Framebuffer_Context)user_data
    if owner == nil || owner^.platform == nil {return {}}
    width := owner^.platform^.scene_width
    height := owner^.platform^.scene_height
    byte_count := int(width * height * 4)
    pixels := rl.MemAlloc(u32(byte_count))
    if pixels == nil {return {}}
    destination := (cast([^]u8)pixels)[:byte_count]
    if !native.sdl_platform_read_scene_rgba8(owner^.platform, destination) {
        rl.MemFree(pixels)
        return {}
    }
    return {data = pixels, width = i32(width), height = i32(height),
        mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
}

// bind_sdl_framebuffer_capture routes capture consumers through native readback.
bind_sdl_framebuffer_capture :: proc(owner: ^Sdl_Framebuffer_Context) {
    view_core.framebuffer_set_capture_operations({
        user_data = rawptr(owner),
        load = sdl_framebuffer_load,
        unload = view_core.framebuffer_raylib_unload,
        crop = view_core.framebuffer_raylib_crop,
        resize = view_core.framebuffer_raylib_resize,
        export = view_core.framebuffer_raylib_export,
    })
}

// unbind_sdl_framebuffer_capture restores the inactive legacy adapter.
unbind_sdl_framebuffer_capture :: proc() {
    view_core.framebuffer_reset_capture_operations()
}
