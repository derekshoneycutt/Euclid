package main

import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import sdl "vendor:sdl3"

PROBE_WIDTH :: 640
PROBE_HEIGHT :: 480
RESIZE_WIDTH :: 800
RESIZE_HEIGHT :: 560
FRAME_LIMIT :: 90

when ODIN_OS == .Linux {
    PROBE_GPU_DRIVER :: "vulkan"
    PROBE_SHADER_FORMAT :: sdl.GPUShaderFormat{.SPIRV}
    PROBE_SHADER_ENTRYPOINT :: "main"
} else when ODIN_OS == .Darwin {
    PROBE_GPU_DRIVER :: "metal"
    PROBE_SHADER_FORMAT :: sdl.GPUShaderFormat{.MSL}
    PROBE_SHADER_ENTRYPOINT :: "main0"
} else when ODIN_OS == .Windows {
    PROBE_GPU_DRIVER :: "direct3d12"
    PROBE_SHADER_FORMAT :: sdl.GPUShaderFormat{.DXIL}
    PROBE_SHADER_ENTRYPOINT :: "main"
} else {
    #assert(false, "SDL3 probe is unsupported on this platform")
}

Probe_Vertex :: struct {
    position: [2]f32,
    color: [3]f32,
}

Probe_State :: struct {
    window:          ^sdl.Window,
    device:          ^sdl.GPUDevice,
    vertex_shader:   ^sdl.GPUShader,
    fragment_shader: ^sdl.GPUShader,
    pipeline:        ^sdl.GPUGraphicsPipeline,
    vertex_buffer:   ^sdl.GPUBuffer,
    transfer_buffer: ^sdl.GPUTransferBuffer,
    window_claimed:  bool,
}

Frame_Summary :: struct {
    frames_presented:  int,
    unavailable_frames: int,
    resize_event:       bool,
    resize_requested:   bool,
}

#assert(size_of(Probe_Vertex) == 20)
#assert(offset_of(Probe_Vertex, position) == 0)
#assert(offset_of(Probe_Vertex, color) == 8)

// report_error records one failed SDL operation with its current diagnostic.
report_error :: proc(stage: string) {
    fmt.eprintf("probe.stage=%s\nprobe.result=failed\nprobe.error=%s\n", stage, sdl.GetError())
}

// release_probe releases every admitted native resource in reverse owner order.
release_probe :: proc(state: ^Probe_State) -> bool {
    idle := true
    if state.device != nil {
        idle = sdl.WaitForGPUIdle(state.device)
        if state.transfer_buffer != nil {
            sdl.ReleaseGPUTransferBuffer(state.device, state.transfer_buffer)
        }
        if state.vertex_buffer != nil {
            sdl.ReleaseGPUBuffer(state.device, state.vertex_buffer)
        }
        if state.pipeline != nil {
            sdl.ReleaseGPUGraphicsPipeline(state.device, state.pipeline)
        }
        if state.fragment_shader != nil {
            sdl.ReleaseGPUShader(state.device, state.fragment_shader)
        }
        if state.vertex_shader != nil {
            sdl.ReleaseGPUShader(state.device, state.vertex_shader)
        }
        if state.window_claimed {
            sdl.ReleaseWindowFromGPUDevice(state.device, state.window)
        }
        sdl.DestroyGPUDevice(state.device)
    }
    if state.window != nil {
        sdl.DestroyWindow(state.window)
    }
    sdl.Quit()
    return idle
}

// load_shader creates one native shader from an owned file buffer.
load_shader :: proc(
    device: ^sdl.GPUDevice,
    path: string,
    stage: sdl.GPUShaderStage) -> ^sdl.GPUShader {
    source, read_error := os.read_entire_file(path, context.allocator)
    if read_error != nil {
        fmt.eprintf("probe.shader_read_error=%v\n", read_error)
        return nil
    }
    defer delete(source)
    create_info := sdl.GPUShaderCreateInfo{
        code_size = len(source),
        code = raw_data(source),
        entrypoint = PROBE_SHADER_ENTRYPOINT,
        format = PROBE_SHADER_FORMAT,
        stage = stage,
    }
    return sdl.CreateGPUShader(device, create_info)
}

// create_pipeline creates the probe's immutable triangle graphics pipeline.
create_pipeline :: proc(
    state: ^Probe_State,
    target_format: sdl.GPUTextureFormat) -> bool {
    descriptions := [1]sdl.GPUVertexBufferDescription{{
        slot = 0,
        pitch = size_of(Probe_Vertex),
        input_rate = .VERTEX,
    }}
    attributes := [2]sdl.GPUVertexAttribute{
        {location = 0, buffer_slot = 0, format = .FLOAT2, offset = 0},
        {location = 1, buffer_slot = 0, format = .FLOAT3, offset = 8},
    }
    targets := [1]sdl.GPUColorTargetDescription{{format = target_format}}
    create_info := sdl.GPUGraphicsPipelineCreateInfo{
        vertex_shader = state.vertex_shader,
        fragment_shader = state.fragment_shader,
        vertex_input_state = {
            vertex_buffer_descriptions = raw_data(descriptions[:]),
            num_vertex_buffers = len(descriptions),
            vertex_attributes = raw_data(attributes[:]),
            num_vertex_attributes = len(attributes),
        },
        primitive_type = .TRIANGLELIST,
        multisample_state = {sample_count = ._1},
        target_info = {
            color_target_descriptions = raw_data(targets[:]),
            num_color_targets = len(targets),
        },
    }
    state.pipeline = sdl.CreateGPUGraphicsPipeline(state.device, create_info)
    return state.pipeline != nil
}

// upload_vertices creates and fills the immutable probe vertex buffer.
upload_vertices :: proc(state: ^Probe_State) -> bool {
    vertices := [3]Probe_Vertex{
        {{0.0, -0.62}, {0.95, 0.25, 0.20}},
        {{0.62, 0.55}, {0.20, 0.85, 0.35}},
        {{-0.62, 0.55}, {0.20, 0.45, 0.95}},
    }
    byte_count := u32(size_of(vertices))
    state.vertex_buffer = sdl.CreateGPUBuffer(state.device, {
        usage = {.VERTEX}, size = byte_count,
    })
    state.transfer_buffer = sdl.CreateGPUTransferBuffer(state.device, {
        usage = .UPLOAD, size = byte_count,
    })
    if state.vertex_buffer == nil || state.transfer_buffer == nil {
        return false
    }
    mapped := sdl.MapGPUTransferBuffer(state.device, state.transfer_buffer, false)
    if mapped == nil {
        return false
    }
    mem.copy(mapped, raw_data(vertices[:]), int(byte_count))
    sdl.UnmapGPUTransferBuffer(state.device, state.transfer_buffer)
    command_buffer := sdl.AcquireGPUCommandBuffer(state.device)
    if command_buffer == nil {
        return false
    }
    copy_pass := sdl.BeginGPUCopyPass(command_buffer)
    if copy_pass == nil {
        _ = sdl.CancelGPUCommandBuffer(command_buffer)
        return false
    }
    source := sdl.GPUTransferBufferLocation{transfer_buffer = state.transfer_buffer}
    destination := sdl.GPUBufferRegion{buffer = state.vertex_buffer, size = byte_count}
    sdl.UploadToGPUBuffer(copy_pass, source, destination, false)
    sdl.EndGPUCopyPass(copy_pass)
    return sdl.SubmitGPUCommandBuffer(command_buffer)
}

// render_frame records and submits one clear-and-triangle presentation.
render_frame :: proc(state: ^Probe_State) -> (presented: bool, available: bool) {
    command_buffer := sdl.AcquireGPUCommandBuffer(state.device)
    if command_buffer == nil {
        return false, false
    }
    texture: ^sdl.GPUTexture
    width, height: u32
    if !sdl.AcquireGPUSwapchainTexture(
        command_buffer, state.window, &texture, &width, &height) {
        _ = sdl.CancelGPUCommandBuffer(command_buffer)
        return false, false
    }
    if texture == nil {
        return sdl.SubmitGPUCommandBuffer(command_buffer), false
    }
    target := [1]sdl.GPUColorTargetInfo{{
        texture = texture,
        clear_color = sdl.FColor{0.055, 0.075, 0.095, 1.0},
        load_op = .CLEAR,
        store_op = .STORE,
    }}
    render_pass := sdl.BeginGPURenderPass(
        command_buffer, raw_data(target[:]), len(target), nil)
    if render_pass == nil {
        _ = sdl.CancelGPUCommandBuffer(command_buffer)
        return false, true
    }
    sdl.BindGPUGraphicsPipeline(render_pass, state.pipeline)
    binding := [1]sdl.GPUBufferBinding{{buffer = state.vertex_buffer}}
    sdl.BindGPUVertexBuffers(render_pass, 0, raw_data(binding[:]), len(binding))
    sdl.SetGPUViewport(render_pass, sdl.GPUViewport{
        w = f32(width), h = f32(height), min_depth = 0, max_depth = 1,
    })
    sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
    sdl.EndGPURenderPass(render_pass)
    return sdl.SubmitGPUCommandBuffer(command_buffer), true
}

// poll_events drains close and resize events for one probe frame.
poll_events :: proc() -> (close_requested: bool, resize_event: bool) {
    event: sdl.Event
    for sdl.PollEvent(&event) {
        if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED {
            close_requested = true
        }
        if event.type == .WINDOW_RESIZED || event.type == .WINDOW_PIXEL_SIZE_CHANGED {
            resize_event = true
        }
    }
    return
}

// report_device records the selected GPU and its driver identity.
report_device :: proc(device: ^sdl.GPUDevice) {
    fmt.printf("probe.selected_gpu_driver=%s\n", sdl.GetGPUDeviceDriver(device))
    fmt.printf("probe.shader_formats=%v\n", sdl.GetGPUShaderFormats(device))
    properties := sdl.GetGPUDeviceProperties(device)
    fmt.printf("probe.gpu_device_name=%s\n", sdl.GetStringProperty(
        properties, sdl.PROP_GPU_DEVICE_NAME_STRING, "unknown"))
    fmt.printf("probe.gpu_driver_name=%s\n", sdl.GetStringProperty(
        properties, sdl.PROP_GPU_DEVICE_DRIVER_NAME_STRING, "unknown"))
    fmt.printf("probe.gpu_driver_version=%s\n", sdl.GetStringProperty(
        properties, sdl.PROP_GPU_DEVICE_DRIVER_VERSION_STRING, "unknown"))
}

// configure_swapchain claims the window and selects an explicit present contract.
configure_swapchain :: proc(state: ^Probe_State) -> (sdl.GPUTextureFormat, bool) {
    if !sdl.ClaimWindowForGPUDevice(state.device, state.window) {
        report_error("window_claim")
        return .INVALID, false
    }
    state.window_claimed = true
    if !sdl.WindowSupportsGPUSwapchainComposition(state.device, state.window, .SDR) ||
       !sdl.WindowSupportsGPUPresentMode(state.device, state.window, .VSYNC) ||
       !sdl.SetGPUSwapchainParameters(state.device, state.window, .SDR, .VSYNC) {
        report_error("swapchain_parameters")
        return .INVALID, false
    }
    fmt.println("probe.swapchain_composition=sdr")
    fmt.println("probe.present_mode=vsync")
    format := sdl.GetGPUSwapchainTextureFormat(state.device, state.window)
    fmt.printf("probe.swapchain_format=%d\n", format)
    return format, true
}

// initialize_platform admits SDL, a window, and an explicit native GPU device.
initialize_platform :: proc(state: ^Probe_State) -> (sdl.GPUTextureFormat, bool) {
    if !sdl.Init({.VIDEO, .EVENTS}) {
        report_error("sdl_init")
        return .INVALID, false
    }
    state.window = sdl.CreateWindow("Euclid SDL3 Probe", PROBE_WIDTH, PROBE_HEIGHT,
        {.RESIZABLE, .HIGH_PIXEL_DENSITY})
    if state.window == nil {
        report_error("window_create")
        return .INVALID, false
    }
    fmt.printf("probe.video_driver=%s\n", sdl.GetCurrentVideoDriver())
    for index in 0..<sdl.GetNumGPUDrivers() {
        fmt.printf("probe.gpu_driver[%d]=%s\n", index, sdl.GetGPUDriver(index))
    }
    if !sdl.GPUSupportsShaderFormats(PROBE_SHADER_FORMAT, PROBE_GPU_DRIVER) {
        report_error("gpu_shader_support")
        return .INVALID, false
    }
    state.device = sdl.CreateGPUDevice(
        PROBE_SHADER_FORMAT, true, PROBE_GPU_DRIVER)
    if state.device == nil {
        report_error("gpu_device_create")
        return .INVALID, false
    }
    report_device(state.device)
    return configure_swapchain(state)
}

// failure_injected reports whether a named local teardown probe was requested.
failure_injected :: proc(name: string) -> bool {
    buffer: [64]u8
    value := os.get_env(buffer[:], "EUCLID_SDL3_PROBE_INJECT_FAILURE")
    return value == name
}

// initialize_resources creates shaders, pipeline, and uploaded vertex storage.
initialize_resources :: proc(
    state: ^Probe_State,
    arguments: []string,
    target_format: sdl.GPUTextureFormat) -> bool {
    state.vertex_shader = load_shader(state.device, arguments[0], .VERTEX)
    state.fragment_shader = load_shader(state.device, arguments[1], .FRAGMENT)
    if state.vertex_shader == nil || state.fragment_shader == nil {
        report_error("shader_create")
        return false
    }
    if failure_injected("after_shader_create") {
        report_error("injected_after_shader_create")
        return false
    }
    if !create_pipeline(state, target_format) {
        report_error("pipeline_create")
        return false
    }
    if !upload_vertices(state) {
        report_error("vertex_upload")
        return false
    }
    return true
}

// present_frames executes the bounded event, resize, and presentation loop.
present_frames :: proc(state: ^Probe_State) -> (Frame_Summary, bool) {
    summary: Frame_Summary
    for frame in 0..<FRAME_LIMIT {
        close_requested, observed_resize := poll_events()
        summary.resize_event = summary.resize_event || observed_resize
        if close_requested {
            break
        }
        if frame == 8 {
            summary.resize_requested = sdl.SetWindowSize(
                state.window, RESIZE_WIDTH, RESIZE_HEIGHT)
        }
        presented, available := render_frame(state)
        if available && !presented {
            report_error("frame_submit")
            return summary, false
        }
        if presented && available {
            summary.frames_presented += 1
        } else if !available {
            summary.unavailable_frames += 1
        }
        sdl.Delay(16)
    }
    return summary, true
}

// run_frames presents the triangle and records compositor resize behavior.
run_frames :: proc(state: ^Probe_State) -> bool {
    initial_w, initial_h, pixel_w, pixel_h: c.int
    _ = sdl.GetWindowSize(state.window, &initial_w, &initial_h)
    _ = sdl.GetWindowSizeInPixels(state.window, &pixel_w, &pixel_h)
    fmt.printf("probe.initial_size=%dx%d\n", initial_w, initial_h)
    fmt.printf("probe.initial_pixels=%dx%d\n", pixel_w, pixel_h)
    fmt.printf("probe.display_scale=%.3f\n", sdl.GetWindowDisplayScale(state.window))
    summary, presented := present_frames(state)
    if !presented {
        return false
    }
    final_w, final_h, final_pixel_w, final_pixel_h: c.int
    _ = sdl.GetWindowSize(state.window, &final_w, &final_h)
    _ = sdl.GetWindowSizeInPixels(state.window, &final_pixel_w, &final_pixel_h)
    resize_observed := final_w != initial_w || final_h != initial_h ||
        summary.resize_event
    resize_status := "indeterminate"
    if resize_observed {
        resize_status = "observed"
    } else if summary.resize_requested {
        resize_status = "indeterminate"
    }
    fmt.printf("probe.final_size=%dx%d\n", final_w, final_h)
    fmt.printf("probe.final_pixels=%dx%d\n", final_pixel_w, final_pixel_h)
    fmt.printf("probe.resize_status=%s\n", resize_status)
    fmt.printf("probe.frames_presented=%d\n", summary.frames_presented)
    fmt.printf("probe.unavailable_frames=%d\n", summary.unavailable_frames)
    if summary.frames_presented == 0 {
        report_error("no_presented_frames")
        return false
    }
    return true
}

// main exercises the minimum complete SDL_GPU presentation path.
main :: proc() {
    if len(os.args) != 3 {
        fmt.eprintln("usage: sdl3_probe VERTEX_SPV FRAGMENT_SPV")
        os.exit(2)
    }
    state: Probe_State
    fmt.printf("probe.binding_version=%d.%d.%d\n", sdl.MAJOR_VERSION,
        sdl.MINOR_VERSION, sdl.MICRO_VERSION)
    fmt.printf("probe.runtime_version=%d\n", sdl.GetVersion())
    target_format, initialized := initialize_platform(&state)
    passed := initialized && initialize_resources(
        &state, os.args[1:], target_format) && run_frames(&state)
    cleanup_complete := release_probe(&state)
    fmt.printf("probe.cleanup_complete=%t\n", cleanup_complete)
    if passed && cleanup_complete {
        fmt.println("probe.result=passed")
        return
    }
    if passed {
        report_error("gpu_idle_cleanup")
    }
    os.exit(1)
}
