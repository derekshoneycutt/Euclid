package native

import "core:log"
import "core:math"

import sdl "vendor:sdl3"

when ODIN_OS == .Linux {
    SDL_GPU_DRIVER :: "vulkan"
    SDL_GPU_SHADER_FORMAT :: sdl.GPUShaderFormat{.SPIRV}
    SDL_GPU_SHADER_ENTRYPOINT :: "main"
    SDL_GPU_SHADER_SUFFIX :: ".spv"
} else when ODIN_OS == .Darwin {
    SDL_GPU_DRIVER :: "metal"
    SDL_GPU_SHADER_FORMAT :: sdl.GPUShaderFormat{.MSL}
    SDL_GPU_SHADER_ENTRYPOINT :: "main0"
    SDL_GPU_SHADER_SUFFIX :: ".msl"
} else when ODIN_OS == .Windows {
    SDL_GPU_DRIVER :: "direct3d12"
    SDL_GPU_SHADER_FORMAT :: sdl.GPUShaderFormat{.DXIL}
    SDL_GPU_SHADER_ENTRYPOINT :: "main"
    SDL_GPU_SHADER_SUFFIX :: ".dxil"
} else {
    #assert(false, "SDL GPU backend is unsupported on this platform")
}

SDL_SCENE_FORMAT :: sdl.GPUTextureFormat.R8G8B8A8_UNORM
SDL_CAPTURE_ROW_ALIGNMENT :: 256

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

// Sdl_Capture_Timing reports synchronous GPU wait and CPU copy costs.
Sdl_Capture_Timing :: struct {
    fence_wait_ns: u64,
    map_copy_ns: u64,
}

// Sdl_Capture_Transfer_Layout describes one padded GPU download allocation.
Sdl_Capture_Transfer_Layout :: struct {
    pitch_bytes: int,
    transfer_bytes: int,
    valid: bool,
}

// Sdl_Capture_Completion identifies one submitted download awaiting CPU copy.
Sdl_Capture_Completion :: struct {
    device: ^sdl.GPUDevice,
    transfer: ^sdl.GPUTransferBuffer,
    fence: ^sdl.GPUFence,
    destination: []u8,
    width: int,
    height: int,
    source_pitch: int,
    timing: ^Sdl_Capture_Timing,
}

// Sdl_Capture_Completion_Operations supplies post-submission GPU capture calls.
Sdl_Capture_Completion_Operations :: struct {
    user_data: rawptr,
    wait: proc(user_data: rawptr, device: ^sdl.GPUDevice,
        fence: ^sdl.GPUFence) -> bool,
    map_transfer: proc(user_data: rawptr, device: ^sdl.GPUDevice,
        transfer: ^sdl.GPUTransferBuffer) -> rawptr,
    unmap: proc(user_data: rawptr, device: ^sdl.GPUDevice,
        transfer: ^sdl.GPUTransferBuffer),
    release_fence: proc(user_data: rawptr, device: ^sdl.GPUDevice,
        fence: ^sdl.GPUFence),
}

SDL_CAPTURE_COMPLETION_OPERATIONS :: Sdl_Capture_Completion_Operations{
    wait = sdl_capture_wait,
    map_transfer = sdl_capture_map,
    unmap = sdl_capture_unmap,
    release_fence = sdl_capture_release_fence,
}

// Sdl_Platform owns display-thread native state for one window session.
Sdl_Platform :: struct {
    window:              ^sdl.Window,
    device:              ^sdl.GPUDevice,
    scene_target:        ^sdl.GPUTexture,
    multisample_target:  ^sdl.GPUTexture,
    default_cursor:      ^sdl.Cursor,
    resize_ew_cursor:    ^sdl.Cursor,
    resize_ns_cursor:    ^sdl.Cursor,
    active_cursor:       ^sdl.Cursor,
    metrics:             Sdl_Window_Metrics,
    scene_width:         u32,
    scene_height:        u32,
    sample_count:        sdl.GPUSampleCount,
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
    antialiasing: bool,
}

// Sdl_Swapchain_Image records one acquired presentation texture and extent.
Sdl_Swapchain_Image :: struct {
    texture: ^sdl.GPUTexture,
    width:   u32,
    height:  u32,
}

// Sdl_Scene_Targets owns one complete render and resolve target pair.
Sdl_Scene_Targets :: struct {
    scene: ^sdl.GPUTexture,
    multisample: ^sdl.GPUTexture,
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

// sdl_scene_target_create creates one physical-pixel color target.
sdl_scene_target_create :: proc(
    device: ^sdl.GPUDevice, width, height: u32,
    sample_count: sdl.GPUSampleCount) -> ^sdl.GPUTexture {
    if device == nil || width == 0 || height == 0 {
        return nil
    }
    usage: sdl.GPUTextureUsageFlags = {.COLOR_TARGET}
    if sample_count == ._1 {usage += {.SAMPLER}}
    return sdl.CreateGPUTexture(device, {
        type = .D2,
        format = SDL_SCENE_FORMAT,
        usage = usage,
        width = width,
        height = height,
        layer_count_or_depth = 1,
        num_levels = 1,
        sample_count = sample_count,
    })
}

// sdl_scene_sample_count selects the best requested scene sample count.
sdl_scene_sample_count :: proc(
    device: ^sdl.GPUDevice, antialiasing: bool) -> sdl.GPUSampleCount {
    if !antialiasing {return ._1}
    if sdl.GPUTextureSupportsSampleCount(device, SDL_SCENE_FORMAT, ._4) {
        return ._4
    }
    if sdl.GPUTextureSupportsSampleCount(device, SDL_SCENE_FORMAT, ._2) {
        return ._2
    }
    return ._1
}

// sdl_scene_sample_count_value returns the physical sample count for diagnostics.
sdl_scene_sample_count_value :: proc(sample_count: sdl.GPUSampleCount) -> int {
    switch sample_count {
    case ._1: return 1
    case ._2: return 2
    case ._4: return 4
    case ._8: return 8
    }
    return 1
}

// sdl_scene_multisample_target_create creates the optional resolve source.
sdl_scene_multisample_target_create :: proc(
    device: ^sdl.GPUDevice, width, height: u32,
    sample_count: sdl.GPUSampleCount) -> ^sdl.GPUTexture {
    if sample_count == ._1 {return nil}
    return sdl_scene_target_create(device, width, height, sample_count)
}

// sdl_scene_targets_create admits a complete render and resolve target pair.
sdl_scene_targets_create :: proc(
    device: ^sdl.GPUDevice, width, height: u32,
    sample_count: sdl.GPUSampleCount) -> Sdl_Scene_Targets {
    targets := Sdl_Scene_Targets{
        scene = sdl_scene_target_create(device, width, height, ._1),
    }
    if targets.scene == nil {return {}}
    targets.multisample = sdl_scene_multisample_target_create(
        device, width, height, sample_count)
    if sample_count != ._1 && targets.multisample == nil {
        sdl.ReleaseGPUTexture(device, targets.scene)
        return {}
    }
    return targets
}

// sdl_scene_targets_release releases a render target before its resolve target.
sdl_scene_targets_release :: proc(
    device: ^sdl.GPUDevice, scene_target,
    multisample_target: ^sdl.GPUTexture) {
    if multisample_target != nil {
        sdl.ReleaseGPUTexture(device, multisample_target)
    }
    if scene_target != nil {sdl.ReleaseGPUTexture(device, scene_target)}
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
    candidate := sdl_scene_targets_create(
        platform^.device, width, height, platform^.sample_count)
    if candidate.scene == nil {return false}
    if platform^.scene_target != nil {
        if !sdl.WaitForGPUIdle(platform^.device) {
            sdl_scene_targets_release(
                platform^.device, candidate.scene, candidate.multisample)
            return false
        }
        sdl_scene_targets_release(platform^.device, platform^.scene_target,
            platform^.multisample_target)
    }
    platform^.scene_target = candidate.scene
    platform^.multisample_target = candidate.multisample
    platform^.scene_width = width
    platform^.scene_height = height
    platform^.resize_pending = false
    return true
}

// sdl_scene_color_target_info resolves optional MSAA into the capture target.
sdl_scene_color_target_info :: proc(
    platform: ^Sdl_Platform, clear_color: sdl.FColor) -> sdl.GPUColorTargetInfo {
    if platform^.multisample_target == nil {
        return {texture = platform^.scene_target, clear_color = clear_color,
            load_op = .CLEAR, store_op = .STORE}
    }
    return {texture = platform^.multisample_target,
        clear_color = clear_color, load_op = .CLEAR, store_op = .RESOLVE,
        resolve_texture = platform^.scene_target}
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
    target := [1]sdl.GPUColorTargetInfo{
        sdl_scene_color_target_info(platform, clear_color)}
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
    if !sdl_draw_submit(platform, runtime, encoder,
        {command_buffer, image, clear_color}) {
        return .Failed
    }
    return .Presented
}

// sdl_capture_transfer_layout resolves one backend-friendly RGBA8 download layout.
sdl_capture_transfer_layout :: proc(
    width, height: u32) -> Sdl_Capture_Transfer_Layout {
    if width == 0 || height == 0 ||
        u64(width) > u64(math.max(int)) / 4 {
        return {}
    }
    row_bytes := int(width) * 4
    if row_bytes > math.max(int) - (SDL_CAPTURE_ROW_ALIGNMENT - 1) {
        return {}
    }
    pitch_bytes := (row_bytes + SDL_CAPTURE_ROW_ALIGNMENT - 1) /
        SDL_CAPTURE_ROW_ALIGNMENT * SDL_CAPTURE_ROW_ALIGNMENT
    if int(height) > math.max(int) / pitch_bytes {
        return {}
    }
    transfer_bytes := pitch_bytes * int(height)
    return {pitch_bytes, transfer_bytes, transfer_bytes <= int(math.max(u32))}
}

// sdl_capture_copy_rgba8 normalizes padded top-left rows into tight storage.
sdl_capture_copy_rgba8 :: proc(
    destination: []u8, source: rawptr,
    width, height, source_pitch: int) -> bool {
    if source == nil || width <= 0 || height <= 0 ||
        width > math.max(int) / 4 {
        return false
    }
    row_bytes := width * 4
    if source_pitch < row_bytes || height > math.max(int) / source_pitch ||
        len(destination) != row_bytes * height {
        return false
    }
    source_bytes := (cast([^]u8)source)[:source_pitch * height]
    for row in 0..<height {
        copy(destination[row * row_bytes:][:row_bytes],
            source_bytes[row * source_pitch:][:row_bytes])
    }
    return true
}

// sdl_capture_wait waits for one submitted capture fence through SDL.
sdl_capture_wait :: proc(
    _: rawptr, device: ^sdl.GPUDevice, fence: ^sdl.GPUFence) -> bool {
    fences := [1]^sdl.GPUFence{fence}
    return sdl.WaitForGPUFences(device, true, raw_data(fences[:]), len(fences))
}

// sdl_capture_map maps one completed download transfer through SDL.
sdl_capture_map :: proc(
    _: rawptr, device: ^sdl.GPUDevice,
    transfer: ^sdl.GPUTransferBuffer) -> rawptr {
    return sdl.MapGPUTransferBuffer(device, transfer, false)
}

// sdl_capture_unmap unmaps one completed download transfer through SDL.
sdl_capture_unmap :: proc(
    _: rawptr, device: ^sdl.GPUDevice, transfer: ^sdl.GPUTransferBuffer) {
    sdl.UnmapGPUTransferBuffer(device, transfer)
}

// sdl_capture_release_fence releases one submitted capture fence through SDL.
sdl_capture_release_fence :: proc(
    _: rawptr, device: ^sdl.GPUDevice, fence: ^sdl.GPUFence) {
    sdl.ReleaseGPUFence(device, fence)
}

// sdl_capture_complete normalizes one submitted download and releases completion state.
sdl_capture_complete :: proc(
    completion: Sdl_Capture_Completion,
    operations: Sdl_Capture_Completion_Operations) -> bool {
    if completion.fence == nil || operations.wait == nil ||
        operations.map_transfer == nil ||
        operations.unmap == nil || operations.release_fence == nil {
        return false
    }
    defer operations.release_fence(
        operations.user_data, completion.device, completion.fence)
    wait_started_at := sdl_time_ticks()
    if !operations.wait(
        operations.user_data, completion.device, completion.fence) {return false}
    wait_finished_at := sdl_time_ticks()
    mapped := operations.map_transfer(
        operations.user_data, completion.device, completion.transfer)
    if mapped == nil {return false}
    defer operations.unmap(
        operations.user_data, completion.device, completion.transfer)
    copied := sdl_capture_copy_rgba8(
        completion.destination, mapped, completion.width,
        completion.height, completion.source_pitch)
    if completion.timing != nil {
        completion.timing^.fence_wait_ns = wait_finished_at - wait_started_at
        completion.timing^.map_copy_ns = sdl_time_ticks() - wait_finished_at
    }
    return copied
}

// sdl_capture_submit_scene records and submits one owned-target download.
sdl_capture_submit_scene :: proc(
    platform: ^Sdl_Platform, transfer: ^sdl.GPUTransferBuffer,
    layout: Sdl_Capture_Transfer_Layout) -> ^sdl.GPUFence {
    command_buffer := sdl.AcquireGPUCommandBuffer(platform^.device)
    if command_buffer == nil {return nil}
    copy_pass := sdl.BeginGPUCopyPass(command_buffer)
    if copy_pass == nil {
        _ = sdl.CancelGPUCommandBuffer(command_buffer)
        return nil
    }
    sdl.DownloadFromGPUTexture(copy_pass, {texture = platform^.scene_target,
        w = platform^.scene_width, h = platform^.scene_height, d = 1}, {
        transfer_buffer = transfer, pixels_per_row = u32(layout.pitch_bytes / 4),
        rows_per_layer = platform^.scene_height})
    sdl.EndGPUCopyPass(copy_pass)
    return sdl.SubmitGPUCommandBufferAndAcquireFence(command_buffer)
}

// sdl_platform_read_scene_rgba8 synchronously copies the owned scene target.
sdl_platform_read_scene_rgba8 :: proc(
    platform: ^Sdl_Platform, destination: []u8,
    timing: ^Sdl_Capture_Timing = nil) -> bool {
    if platform == nil || platform^.device == nil || platform^.scene_target == nil {
        return false
    }
    layout := sdl_capture_transfer_layout(
        platform^.scene_width, platform^.scene_height)
    if !layout.valid {return false}
    row_bytes := int(platform^.scene_width) * 4
    if len(destination) != row_bytes * int(platform^.scene_height) {return false}
    transfer := sdl.CreateGPUTransferBuffer(platform^.device, {
        usage = .DOWNLOAD, size = u32(layout.transfer_bytes)})
    if transfer == nil {return false}
    defer sdl.ReleaseGPUTransferBuffer(platform^.device, transfer)
    fence := sdl_capture_submit_scene(platform, transfer, layout)
    if fence == nil {return false}
    return sdl_capture_complete({
        device = platform^.device,
        transfer = transfer,
        fence = fence,
        destination = destination,
        width = int(platform^.scene_width),
        height = int(platform^.scene_height),
        source_pitch = layout.pitch_bytes,
        timing = timing,
    }, SDL_CAPTURE_COMPLETION_OPERATIONS)
}

// sdl_platform_save_png persists borrowed top-left RGBA8 rows through SDL core.
sdl_platform_save_png :: proc(
    pixels: []u8, width, height, pitch_bytes: int, path: cstring) -> bool {
    if len(pixels) == 0 || width <= 0 || height <= 0 || path == nil ||
        width > int(math.max(i32)) || height > int(math.max(i32)) ||
        width > math.max(int) / 4 || pitch_bytes < width * 4 ||
        pitch_bytes > int(math.max(i32)) ||
        height > math.max(int) / pitch_bytes ||
        len(pixels) < pitch_bytes * height {
        return false
    }
    surface := sdl.CreateSurfaceFrom(
        i32(width), i32(height), .RGBA32, raw_data(pixels), i32(pitch_bytes))
    if surface == nil {
        log.errorf("sdl_capture_surface_failed error=%s", sdl.GetError())
        return false
    }
    defer sdl.DestroySurface(surface)
    started_at := sdl_time_ticks()
    if !sdl.SavePNG(surface, path) {
        log.errorf("sdl_capture_png_failed error=%s", sdl.GetError())
        return false
    }
    log.infof("sdl_capture_png width=%d height=%d elapsed_ns=%d",
        width, height, sdl_time_ticks() - started_at)
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
        sdl_scene_targets_release(platform^.device, platform^.scene_target,
            platform^.multisample_target)
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

// sdl_platform_admit_gpu creates, claims, and configures the native GPU device.
sdl_platform_admit_gpu :: proc(
    platform: ^Sdl_Platform, vsync: bool) -> (sdl.GPUPresentMode, bool) {
    if !sdl.GPUSupportsShaderFormats(SDL_GPU_SHADER_FORMAT, SDL_GPU_DRIVER) {
        return {}, false
    }
    platform^.device = sdl.CreateGPUDevice(
        SDL_GPU_SHADER_FORMAT, true, SDL_GPU_DRIVER)
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
        "swapchain_format=%d present_mode=%d samples=%d logical=%dx%d " +
        "pixels=%dx%d scale=%f",
        sdl.GetVersion(), sdl.GetCurrentVideoDriver(),
        sdl.GetGPUDeviceDriver(platform^.device),
        sdl.GetGPUShaderFormats(platform^.device),
        sdl.GetGPUSwapchainTextureFormat(platform^.device, platform^.window),
        present_mode, sdl_scene_sample_count_value(platform^.sample_count),
        platform^.metrics.logical_width,
        platform^.metrics.logical_height, platform^.metrics.pixel_width,
        platform^.metrics.pixel_height, platform^.metrics.display_scale)
}

// sdl_platform_create initializes one native GPU window and owned scene target.
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
    platform^.sample_count = sdl_scene_sample_count(
        platform^.device, options.antialiasing)
    platform^.resize_pending = true
    if !sdl_platform_refresh_target(platform) {
        sdl_platform_destroy(platform)
        return false
    }
    sdl_platform_log_ready(platform, present_mode)
    return true
}