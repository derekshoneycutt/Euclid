package view

import view_core "core"
import native "native"

import "core:log"
import "core:math"
import "core:mem"

// Sdl_Framebuffer_Context borrows the active display platform for CPU readback.
Sdl_Framebuffer_Context :: struct {
    platform: ^native.Sdl_Platform,
    tracker: mem.Tracking_Allocator,
    tracker_initialized: bool,
    readback_count: u64,
    fence_wait_ns: u64,
    map_copy_ns: u64,
}

// sdl_framebuffer_load downloads the owned scene target into tracked CPU storage.
sdl_framebuffer_load :: proc(
    user_data: rawptr, allocator: mem.Allocator) -> view_core.Framebuffer_Pixels {
    owner := cast(^Sdl_Framebuffer_Context)user_data
    if owner == nil || owner^.platform == nil {return {}}
    width := owner^.platform^.scene_width
    height := owner^.platform^.scene_height
    if width == 0 || height == 0 || u64(width) > u64(math.max(int)) / 4 {
        return {}
    }
    pitch_bytes := int(width) * 4
    if u64(height) > u64(math.max(int) / pitch_bytes) {return {}}
    byte_count := pitch_bytes * int(height)
    pixels, allocation_error := make([]u8, byte_count, allocator)
    if allocation_error != nil {return {}}
    timing: native.Sdl_Capture_Timing
    if !native.sdl_platform_read_scene_rgba8(owner^.platform, pixels, &timing) {
        delete(pixels, allocator)
        return {}
    }
    owner^.readback_count += 1
    owner^.fence_wait_ns += timing.fence_wait_ns
    owner^.map_copy_ns += timing.map_copy_ns
    return {pixels = pixels, width = int(width), height = int(height),
        pitch_bytes = pitch_bytes}
}

// sdl_framebuffer_unload releases all storage for the current synchronous capture.
sdl_framebuffer_unload :: proc(
    user_data: rawptr, capture: ^view_core.Framebuffer_Pixels) {
    owner := cast(^Sdl_Framebuffer_Context)user_data
    if owner != nil && owner^.tracker_initialized {
        delete(capture^.pixels, mem.tracking_allocator(&owner^.tracker))
    }
}

// sdl_framebuffer_export persists one borrowed capture through SDL core PNG support.
sdl_framebuffer_export :: proc(
    _: rawptr, capture: ^view_core.Framebuffer_Pixels, path: cstring) -> bool {
    if capture == nil {return false}
    return native.sdl_platform_save_png(capture^.pixels, capture^.width,
        capture^.height, capture^.pitch_bytes, path)
}

// sdl_framebuffer_operations exposes readback and persistence through one display owner.
sdl_framebuffer_operations :: proc(
    owner: ^Sdl_Framebuffer_Context) -> view_core.Framebuffer_Capture_Operations {
    if owner == nil || !owner^.tracker_initialized {return {}}
    return {
        user_data = rawptr(owner),
        allocator = mem.tracking_allocator(&owner^.tracker),
        load = sdl_framebuffer_load,
        unload = sdl_framebuffer_unload,
        export = sdl_framebuffer_export,
    }
}

// bind_sdl_framebuffer_capture admits display-owned capture storage.
bind_sdl_framebuffer_capture :: proc(owner: ^Sdl_Framebuffer_Context) -> bool {
    if owner == nil || owner^.platform == nil {return false}
    mem.tracking_allocator_init(
        &owner^.tracker, context.allocator, context.allocator)
    owner^.tracker_initialized = true
    return true
}

// unbind_sdl_framebuffer_capture reports telemetry and releases capture storage.
unbind_sdl_framebuffer_capture :: proc(owner: ^Sdl_Framebuffer_Context) {
    if owner != nil && owner^.tracker_initialized {
        log.infof(
            "sdl_capture_summary readbacks=%d fence_wait_ns=%d map_copy_ns=%d",
            owner^.readback_count, owner^.fence_wait_ns, owner^.map_copy_ns)
        mem.tracking_allocator_destroy(&owner^.tracker)
        owner^.tracker_initialized = false
    }
}
