package native

import "core:log"
import "core:mem"

import sdl "vendor:sdl3"

SDL_SCENE_FORMAT :: sdl.GPUTextureFormat.R8G8B8A8_UNORM

// Sdl_Frame_Result distinguishes presentation from temporary unavailability and failure.
Sdl_Frame_Result :: enum u8 {
    Presented,
    Unavailable,
    Failed,
}

// Sdl_Window_Metrics records one stable logical and physical window observation.
Sdl_Window_Metrics :: struct {
    logical_width:  int,
    logical_height: int,
    pixel_width:    int,
    pixel_height:   int,
    display_scale:  f32,
}

// Sdl_Input_Diagnostics records content-free lifetime input outcomes.
Sdl_Input_Diagnostics :: struct {
    key_events: u64,
    unmapped_key_events: u64,
    text_runes: u64,
    invalid_text_events: u64,
    button_events: u64,
    wheel_events: u64,
    focus_events: u64,
    event_overflows: u64,
}

// Sdl_Platform owns display-thread native state for one window session.
Sdl_Platform :: struct {
    window:              ^sdl.Window,
    device:              ^sdl.GPUDevice,
    scene_target:        ^sdl.GPUTexture,
    default_cursor:      ^sdl.Cursor,
    resize_ew_cursor:    ^sdl.Cursor,
    resize_ns_cursor:    ^sdl.Cursor,
    active_cursor:       ^sdl.Cursor,
    metrics:             Sdl_Window_Metrics,
    scene_width:         u32,
    scene_height:        u32,
    window_claimed:      bool,
    close_requested:     bool,
    resize_pending:      bool,
    text_input_active:   bool,
    unavailable_frames: u64,
    input_diagnostics:   Sdl_Input_Diagnostics,
}

// Sdl_Platform_Options defines immutable creation policy for one window session.
Sdl_Platform_Options :: struct {
    title:     cstring,
    width:     int,
    height:    int,
    resizable: bool,
    vsync:     bool,
}

// Sdl_Swapchain_Image records one acquired presentation texture and extent.
Sdl_Swapchain_Image :: struct {
    texture: ^sdl.GPUTexture,
    width:   u32,
    height:  u32,
}

// sdl_platform_metrics reads positive logical and physical extents from one window.
sdl_platform_metrics :: proc(window: ^sdl.Window) -> (Sdl_Window_Metrics, bool) {
    logical_width, logical_height: i32
    pixel_width, pixel_height: i32
    if window == nil || !sdl.GetWindowSize(window, &logical_width, &logical_height) ||
       !sdl.GetWindowSizeInPixels(window, &pixel_width, &pixel_height) {
        return {}, false
    }
    return {
        logical_width = max(1, int(logical_width)),
        logical_height = max(1, int(logical_height)),
        pixel_width = max(1, int(pixel_width)),
        pixel_height = max(1, int(pixel_height)),
        display_scale = sdl.GetWindowDisplayScale(window),
    }, true
}

// sdl_scene_target_create creates one single-sample physical-pixel color target.
sdl_scene_target_create :: proc(
    device: ^sdl.GPUDevice, width, height: u32) -> ^sdl.GPUTexture {
    if device == nil || width == 0 || height == 0 {
        return nil
    }
    return sdl.CreateGPUTexture(device, {
        type = .D2,
        format = SDL_SCENE_FORMAT,
        usage = {.COLOR_TARGET, .SAMPLER},
        width = width,
        height = height,
        layer_count_or_depth = 1,
        num_levels = 1,
        sample_count = ._1,
    })
}

// sdl_platform_refresh_target atomically replaces a mismatched scene target.
sdl_platform_refresh_target :: proc(platform: ^Sdl_Platform) -> bool {
    metrics, ok := sdl_platform_metrics(platform^.window)
    if !ok {
        return false
    }
    platform^.metrics = metrics
    width := u32(metrics.pixel_width)
    height := u32(metrics.pixel_height)
    if platform^.scene_target != nil && platform^.scene_width == width &&
       platform^.scene_height == height {
        platform^.resize_pending = false
        return true
    }
    candidate := sdl_scene_target_create(platform^.device, width, height)
    if candidate == nil {
        return false
    }
    if platform^.scene_target != nil {
        if !sdl.WaitForGPUIdle(platform^.device) {
            sdl.ReleaseGPUTexture(platform^.device, candidate)
            return false
        }
        sdl.ReleaseGPUTexture(platform^.device, platform^.scene_target)
    }
    platform^.scene_target = candidate
    platform^.scene_width = width
    platform^.scene_height = height
    platform^.resize_pending = false
    return true
}

// sdl_swapchain_acquire acquires one command buffer and its presentation image.
sdl_swapchain_acquire :: proc(
    platform: ^Sdl_Platform,
    command_buffer: ^^sdl.GPUCommandBuffer) -> (Sdl_Swapchain_Image, bool) {
    command_buffer^ = sdl.AcquireGPUCommandBuffer(platform^.device)
    if command_buffer^ == nil {
        return {}, false
    }
    image: Sdl_Swapchain_Image
    if !sdl.AcquireGPUSwapchainTexture(command_buffer^, platform^.window,
        &image.texture, &image.width, &image.height) {
        _ = sdl.CancelGPUCommandBuffer(command_buffer^)
        return {}, false
    }
    return image, true
}

// sdl_submit_clear_blit records and submits one owned-target presentation.
sdl_submit_clear_blit :: proc(
    platform: ^Sdl_Platform, command_buffer: ^sdl.GPUCommandBuffer,
    image: Sdl_Swapchain_Image, clear_color: sdl.FColor) -> bool {
    target := [1]sdl.GPUColorTargetInfo{{
        texture = platform^.scene_target,
        clear_color = clear_color,
        load_op = .CLEAR,
        store_op = .STORE,
    }}
    render_pass := sdl.BeginGPURenderPass(
        command_buffer, raw_data(target[:]), len(target), nil)
    if render_pass == nil {
        _ = sdl.CancelGPUCommandBuffer(command_buffer)
        return false
    }
    sdl.EndGPURenderPass(render_pass)
    sdl.BlitGPUTexture(command_buffer, {
        source = {texture = platform^.scene_target,
            w = platform^.scene_width, h = platform^.scene_height},
        destination = {texture = image.texture, w = image.width, h = image.height},
        load_op = .DONT_CARE,
        filter = .NEAREST,
    })
    return sdl.SubmitGPUCommandBuffer(command_buffer)
}

// sdl_platform_present_clear submits one owned-target clear and swapchain blit.
sdl_platform_present_clear :: proc(
    platform: ^Sdl_Platform, clear_color: sdl.FColor) -> Sdl_Frame_Result {
    if platform^.resize_pending && !sdl_platform_refresh_target(platform) {
        platform^.unavailable_frames += 1
        return .Unavailable
    }
    command_buffer: ^sdl.GPUCommandBuffer
    image, acquired := sdl_swapchain_acquire(platform, &command_buffer)
    if !acquired {
        return .Failed
    }
    if image.texture == nil {
        platform^.unavailable_frames += 1
        if !sdl.SubmitGPUCommandBuffer(command_buffer) {
            return .Failed
        }
        return .Unavailable
    }
    if !sdl_submit_clear_blit(platform, command_buffer, image, clear_color) {
        return .Failed
    }
    return .Presented
}

// sdl_platform_present_draw submits one bounded encoded scene and swapchain blit.
sdl_platform_present_draw :: proc(
    platform: ^Sdl_Platform, runtime: ^Sdl_Draw_Runtime,
    encoder: ^Draw_Encoder, clear_color: sdl.FColor) -> Sdl_Frame_Result {
    if platform^.resize_pending && !sdl_platform_refresh_target(platform) {
        platform^.unavailable_frames += 1
        return .Unavailable
    }
    command_buffer: ^sdl.GPUCommandBuffer
    image, acquired := sdl_swapchain_acquire(platform, &command_buffer)
    if !acquired {return .Failed}
    if image.texture == nil {
        platform^.unavailable_frames += 1
        if !sdl.SubmitGPUCommandBuffer(command_buffer) {return .Failed}
        return .Unavailable
    }
    if !sdl_draw_submit(
        platform, runtime, encoder, command_buffer, image, clear_color) {
        return .Failed
    }
    return .Presented
}

// sdl_platform_read_scene_rgba8 synchronously copies the owned scene target.
sdl_platform_read_scene_rgba8 :: proc(
    platform: ^Sdl_Platform, destination: []u8) -> bool {
    if platform == nil || platform^.device == nil || platform^.scene_target == nil ||
        len(destination) != int(platform^.scene_width * platform^.scene_height * 4) {
        return false
    }
    transfer := sdl.CreateGPUTransferBuffer(platform^.device, {
        usage = .DOWNLOAD, size = u32(len(destination))})
    if transfer == nil {return false}
    defer sdl.ReleaseGPUTransferBuffer(platform^.device, transfer)
    command_buffer := sdl.AcquireGPUCommandBuffer(platform^.device)
    if command_buffer == nil {return false}
    copy_pass := sdl.BeginGPUCopyPass(command_buffer)
    if copy_pass == nil {
        _ = sdl.CancelGPUCommandBuffer(command_buffer)
        return false
    }
    sdl.DownloadFromGPUTexture(copy_pass, {texture = platform^.scene_target,
        w = platform^.scene_width, h = platform^.scene_height, d = 1}, {
        transfer_buffer = transfer, pixels_per_row = platform^.scene_width,
        rows_per_layer = platform^.scene_height})
    sdl.EndGPUCopyPass(copy_pass)
    if !sdl.SubmitGPUCommandBuffer(command_buffer) ||
        !sdl.WaitForGPUIdle(platform^.device) {return false}
    mapped := sdl.MapGPUTransferBuffer(platform^.device, transfer, false)
    if mapped == nil {return false}
    mem.copy(raw_data(destination), mapped, len(destination))
    sdl.UnmapGPUTransferBuffer(platform^.device, transfer)
    return true
}

// sdl_platform_destroy releases all admitted native resources in reverse order.
sdl_platform_destroy :: proc(platform: ^Sdl_Platform) {
    if platform == nil {
        return
    }
    diagnostics := platform^.input_diagnostics
    log.infof(
        "sdl_input_summary keys=%d unmapped=%d text=%d invalid_text=%d " +
        "buttons=%d wheels=%d focus=%d overflows=%d",
        diagnostics.key_events, diagnostics.unmapped_key_events,
        diagnostics.text_runes, diagnostics.invalid_text_events,
        diagnostics.button_events, diagnostics.wheel_events,
        diagnostics.focus_events, diagnostics.event_overflows)
    if platform^.text_input_active && platform^.window != nil {
        _ = sdl.StopTextInput(platform^.window)
    }
    if platform^.device != nil {
        if !sdl.WaitForGPUIdle(platform^.device) {
            log.errorf("sdl_gpu_idle_failed error=%s", sdl.GetError())
        }
        if platform^.scene_target != nil {
            sdl.ReleaseGPUTexture(platform^.device, platform^.scene_target)
        }
        if platform^.window_claimed {
            sdl.ReleaseWindowFromGPUDevice(platform^.device, platform^.window)
        }
        sdl.DestroyGPUDevice(platform^.device)
    }
    if platform^.window != nil {
        sdl_platform_destroy_cursors(platform)
        sdl.DestroyWindow(platform^.window)
    }
    sdl.Quit()
    platform^ = {}
}

// sdl_platform_admit_gpu creates, claims, and configures one Vulkan GPU device.
sdl_platform_admit_gpu :: proc(
    platform: ^Sdl_Platform, vsync: bool) -> (sdl.GPUPresentMode, bool) {
    if !sdl.GPUSupportsShaderFormats({.SPIRV}, "vulkan") {
        return {}, false
    }
    platform^.device = sdl.CreateGPUDevice({.SPIRV}, true, "vulkan")
    if platform^.device == nil ||
       !sdl.ClaimWindowForGPUDevice(platform^.device, platform^.window) {
        return {}, false
    }
    platform^.window_claimed = true
    present_mode := sdl.GPUPresentMode.VSYNC
    if !vsync && sdl.WindowSupportsGPUPresentMode(
        platform^.device, platform^.window, .IMMEDIATE) {
        present_mode = .IMMEDIATE
    }
    configured := sdl.SetGPUSwapchainParameters(
        platform^.device, platform^.window, .SDR, present_mode)
    return present_mode, configured
}

// sdl_platform_log_ready records the admitted runtime and presentation contract.
sdl_platform_log_ready :: proc(
    platform: ^Sdl_Platform, present_mode: sdl.GPUPresentMode) {
    log.infof(
        "sdl_platform_ready version=%d video=%s gpu_driver=%s shader_formats=%v " +
        "swapchain_format=%d present_mode=%d logical=%dx%d pixels=%dx%d scale=%f",
        sdl.GetVersion(), sdl.GetCurrentVideoDriver(),
        sdl.GetGPUDeviceDriver(platform^.device),
        sdl.GetGPUShaderFormats(platform^.device),
        sdl.GetGPUSwapchainTextureFormat(platform^.device, platform^.window),
        present_mode, platform^.metrics.logical_width,
        platform^.metrics.logical_height, platform^.metrics.pixel_width,
        platform^.metrics.pixel_height, platform^.metrics.display_scale)
}

// sdl_platform_create initializes one Linux Vulkan window and owned scene target.
sdl_platform_create :: proc(
    platform: ^Sdl_Platform, options: Sdl_Platform_Options) -> bool {
    if platform == nil || options.width <= 0 || options.height <= 0 ||
       !sdl.Init({.VIDEO, .EVENTS}) {
        return false
    }
    flags: sdl.WindowFlags = {.HIGH_PIXEL_DENSITY}
    if options.resizable {
        flags += {.RESIZABLE}
    }
    platform^.window = sdl.CreateWindow(
        options.title, i32(options.width), i32(options.height), flags)
    if platform^.window == nil {
        sdl_platform_destroy(platform)
        return false
    }
    if !sdl_platform_admit_cursors(platform) {
        sdl_platform_destroy(platform)
        return false
    }
    present_mode, gpu_ready := sdl_platform_admit_gpu(platform, options.vsync)
    if !gpu_ready {
        sdl_platform_destroy(platform)
        return false
    }
    platform^.resize_pending = true
    if !sdl_platform_refresh_target(platform) {
        sdl_platform_destroy(platform)
        return false
    }
    sdl_platform_log_ready(platform, present_mode)
    return true
}