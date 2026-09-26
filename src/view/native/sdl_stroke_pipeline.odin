package native

import "core:mem"

import sdl "vendor:sdl3"

// Sdl_Stroke_Shader_Paths names the packaged stroke pipeline artifacts.
Sdl_Stroke_Shader_Paths :: struct {
    vertex: string,
    fragment: string,
}

// Sdl_Stroke_Vertex_Input owns the fixed stroke stream description.
Sdl_Stroke_Vertex_Input :: struct {
    description: [1]sdl.GPUVertexBufferDescription,
    attributes: [3]sdl.GPUVertexAttribute,
}

// sdl_stroke_vertex_input describes the reflected stroke vertex ABI.
sdl_stroke_vertex_input :: proc() -> Sdl_Stroke_Vertex_Input {
    return {
        description = {{slot = 0, pitch = size_of(Stroke_Vertex),
            input_rate = .VERTEX}},
        attributes = {
            {location = 0, buffer_slot = 0, format = .FLOAT3, offset = 0},
            {location = 1, buffer_slot = 0, format = .FLOAT2, offset = 12},
            {location = 2, buffer_slot = 0, format = .FLOAT4, offset = 20},
        },
    }
}

// sdl_stroke_target_description returns straight-alpha scene target state.
sdl_stroke_target_description :: proc() -> sdl.GPUColorTargetDescription {
    return {
        format = SDL_SCENE_FORMAT,
        blend_state = {
            src_color_blendfactor = .SRC_ALPHA,
            dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
            color_blend_op = .ADD,
            src_alpha_blendfactor = .ONE,
            dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
            alpha_blend_op = .ADD,
            enable_blend = true,
        },
    }
}

// sdl_stroke_pipeline_create binds the reflected 36-byte stroke vertex ABI.
sdl_stroke_pipeline_create :: proc(
    device: ^sdl.GPUDevice,
    paths: Sdl_Stroke_Shader_Paths,
    sample_count: sdl.GPUSampleCount) -> ^sdl.GPUGraphicsPipeline {
    vertex_shader := sdl_draw_shader_create(device, paths.vertex, .VERTEX, 0, 1)
    if vertex_shader == nil {return nil}
    defer sdl.ReleaseGPUShader(device, vertex_shader)
    fragment_shader := sdl_draw_shader_create(
        device, paths.fragment, .FRAGMENT, 0, 1)
    if fragment_shader == nil {return nil}
    defer sdl.ReleaseGPUShader(device, fragment_shader)
    input := sdl_stroke_vertex_input()
    targets := [1]sdl.GPUColorTargetDescription{
        sdl_stroke_target_description()}
    return sdl.CreateGPUGraphicsPipeline(device, {
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        vertex_input_state = {
            vertex_buffer_descriptions = raw_data(input.description[:]),
            num_vertex_buffers = 1,
            vertex_attributes = raw_data(input.attributes[:]),
            num_vertex_attributes = len(input.attributes),
        },
        primitive_type = .TRIANGLELIST,
        rasterizer_state = {
            fill_mode = .FILL, cull_mode = .NONE,
            front_face = .COUNTER_CLOCKWISE,
        },
        multisample_state = {sample_count = sample_count},
        target_info = {
            color_target_descriptions = raw_data(targets[:]),
            num_color_targets = 1,
        },
    })
}

// sdl_stroke_runtime_admit transactionally publishes optional stroke resources.
sdl_stroke_runtime_admit :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice,
    paths: Sdl_Stroke_Shader_Paths,
    sample_count: sdl.GPUSampleCount) -> bool {
    if runtime == nil || device == nil || runtime^.stroke_ready {return false}
    pipeline := sdl_stroke_pipeline_create(device, paths, sample_count)
    if pipeline == nil {return false}
    vertex_buffer := sdl.CreateGPUBuffer(device, {
        usage = {.VERTEX},
        size = u32(size_of(Stroke_Vertex) * STROKE_VERTEX_CAPACITY),
    })
    if vertex_buffer == nil {
        sdl.ReleaseGPUGraphicsPipeline(device, pipeline)
        return false
    }
    upload_buffer := sdl.CreateGPUTransferBuffer(device, {
        usage = .UPLOAD,
        size = u32(size_of(Stroke_Vertex) * STROKE_VERTEX_CAPACITY),
    })
    if upload_buffer == nil {
        sdl.ReleaseGPUBuffer(device, vertex_buffer)
        sdl.ReleaseGPUGraphicsPipeline(device, pipeline)
        return false
    }
    runtime^.stroke_pipeline = pipeline
    runtime^.stroke_vertex_buffer = vertex_buffer
    runtime^.stroke_upload_buffer = upload_buffer
    runtime^.stroke_ready = true
    return true
}

// sdl_stroke_runtime_release releases optional stroke resources in reverse order.
sdl_stroke_runtime_release :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice) {
    if runtime^.stroke_upload_buffer != nil {
        sdl.ReleaseGPUTransferBuffer(device, runtime^.stroke_upload_buffer)
    }
    if runtime^.stroke_vertex_buffer != nil {
        sdl.ReleaseGPUBuffer(device, runtime^.stroke_vertex_buffer)
    }
    if runtime^.stroke_pipeline != nil {
        sdl.ReleaseGPUGraphicsPipeline(device, runtime^.stroke_pipeline)
    }
    runtime^.stroke_pipeline = nil
    runtime^.stroke_vertex_buffer = nil
    runtime^.stroke_upload_buffer = nil
    runtime^.stroke_ready = false
}

// sdl_stroke_upload records one cycled occupied stroke-vertex prefix upload.
sdl_stroke_upload :: proc(
    runtime: ^Sdl_Draw_Runtime, encoder: ^Draw_Encoder,
    device: ^sdl.GPUDevice, command_buffer: ^sdl.GPUCommandBuffer) -> bool {
    byte_count := u32(encoder^.stroke_vertex_count * size_of(Stroke_Vertex))
    if byte_count == 0 {return true}
    if !runtime^.stroke_ready {return false}
    mapped := sdl.MapGPUTransferBuffer(device, runtime^.stroke_upload_buffer, true)
    if mapped == nil {return false}
    mem.copy(mapped, raw_data(
        encoder^.stroke_vertices[:encoder^.stroke_vertex_count]), int(byte_count))
    sdl.UnmapGPUTransferBuffer(device, runtime^.stroke_upload_buffer)
    copy_pass := sdl.BeginGPUCopyPass(command_buffer)
    if copy_pass == nil {return false}
    sdl.UploadToGPUBuffer(copy_pass,
        {transfer_buffer = runtime^.stroke_upload_buffer},
        {buffer = runtime^.stroke_vertex_buffer, size = byte_count}, true)
    sdl.EndGPUCopyPass(copy_pass)
    return true
}

// sdl_stroke_bind selects the stroke pipeline and dedicated vertex stream.
sdl_stroke_bind :: proc(
    runtime: ^Sdl_Draw_Runtime, pass: ^sdl.GPURenderPass) {
    binding := [1]sdl.GPUBufferBinding{{buffer = runtime^.stroke_vertex_buffer}}
    sdl.BindGPUGraphicsPipeline(pass, runtime^.stroke_pipeline)
    sdl.BindGPUVertexBuffers(pass, 0, raw_data(binding[:]), 1)
}

// sdl_stroke_record_draw pushes one complete uniform pair and draws its triangles.
sdl_stroke_record_draw :: proc(
    command_buffer: ^sdl.GPUCommandBuffer, pass: ^sdl.GPURenderPass,
    draw: ^Stroke_Draw) {
    sdl.PushGPUVertexUniformData(command_buffer, 0,
        rawptr(&draw^.vertex_uniforms), size_of(draw^.vertex_uniforms))
    sdl.PushGPUFragmentUniformData(command_buffer, 0,
        rawptr(&draw^.fragment_uniforms), size_of(draw^.fragment_uniforms))
    sdl.SetGPUScissor(pass, {draw^.scissor.x, draw^.scissor.y,
        i32(draw^.scissor.width), i32(draw^.scissor.height)})
    sdl.DrawGPUPrimitives(
        pass, draw^.vertex_count, 1, draw^.first_vertex, 0)
}