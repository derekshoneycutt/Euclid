package native

import "core:mem"

import sdl "vendor:sdl3"

// Sdl_Dust_Shader_Paths names the packaged instanced dust artifacts.
Sdl_Dust_Shader_Paths :: struct {
    vertex:   string,
    fragment: string,
}

// Sdl_Dust_Vertex_Input owns the fixed instanced dust stream description.
Sdl_Dust_Vertex_Input :: struct {
    descriptions: [2]sdl.GPUVertexBufferDescription,
    attributes:   [5]sdl.GPUVertexAttribute,
}

// Sdl_Dust_Upload_Layout describes occupied bytes in the dust transfer buffer.
Sdl_Dust_Upload_Layout :: struct {
    quad_bytes: u32,
    instance_bytes: u32,
    expanded_bytes: u32,
}

// sdl_dust_vertex_input describes static-quad and per-instance streams.
sdl_dust_vertex_input :: proc() -> Sdl_Dust_Vertex_Input {
    return {
        descriptions = {
            {slot = 0, pitch = size_of(Dust_Quad_Vertex), input_rate = .VERTEX},
            {slot = 1, pitch = size_of(Dust_Instance), input_rate = .INSTANCE},
        },
        attributes = {
            {location = 0, buffer_slot = 0, format = .FLOAT2, offset = 0},
            {location = 1, buffer_slot = 0, format = .FLOAT2, offset = 8},
            {location = 2, buffer_slot = 1, format = .FLOAT3, offset = 0},
            {location = 3, buffer_slot = 1, format = .FLOAT4, offset = 12},
            {location = 4, buffer_slot = 1, format = .FLOAT, offset = 28},
        },
    }
}

// sdl_dust_pipeline_create binds static quad and per-instance vertex streams.
sdl_dust_pipeline_create :: proc(
    device: ^sdl.GPUDevice,
    paths: Sdl_Dust_Shader_Paths) -> ^sdl.GPUGraphicsPipeline {
    vertex_shader := sdl_draw_shader_create(device, paths.vertex, .VERTEX, 0, 1)
    if vertex_shader == nil {return nil}
    defer sdl.ReleaseGPUShader(device, vertex_shader)
    fragment_shader := sdl_draw_shader_create(
        device, paths.fragment, .FRAGMENT, 1, 0)
    if fragment_shader == nil {return nil}
    defer sdl.ReleaseGPUShader(device, fragment_shader)
    input := sdl_dust_vertex_input()
    targets := [1]sdl.GPUColorTargetDescription{sdl_stroke_target_description()}
    return sdl.CreateGPUGraphicsPipeline(device, {
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        vertex_input_state = {
            vertex_buffer_descriptions = raw_data(input.descriptions[:]),
            num_vertex_buffers = len(input.descriptions),
            vertex_attributes = raw_data(input.attributes[:]),
            num_vertex_attributes = len(input.attributes),
        },
        primitive_type = .TRIANGLELIST,
        rasterizer_state = {fill_mode = .FILL, cull_mode = .NONE,
            front_face = .COUNTER_CLOCKWISE},
        multisample_state = {sample_count = ._1},
        target_info = {color_target_descriptions = raw_data(targets[:]),
            num_color_targets = 1},
    })
}

// sdl_dust_runtime_admit publishes dedicated fallback and optional instance resources.
sdl_dust_runtime_admit :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice,
    paths: Sdl_Dust_Shader_Paths) -> bool {
    if runtime == nil || device == nil || runtime^.dust_expanded_buffer != nil {
        return false
    }
    runtime^.dust_expanded_buffer = sdl.CreateGPUBuffer(device, {
        usage = {.VERTEX},
        size = u32(size_of(Draw_Vertex) * DUST_EXPANDED_VERTEX_CAPACITY),
    })
    upload_size := size_of(Dust_Quad_Vertex) * DUST_QUAD_VERTEX_COUNT +
        size_of(Dust_Instance) * DUST_INSTANCE_CAPACITY +
        size_of(Draw_Vertex) * DUST_EXPANDED_VERTEX_CAPACITY
    runtime^.dust_upload_buffer = sdl.CreateGPUTransferBuffer(device, {
        usage = .UPLOAD, size = u32(upload_size)})
    if runtime^.dust_expanded_buffer == nil || runtime^.dust_upload_buffer == nil {
        sdl_dust_runtime_release(runtime, device)
        return false
    }
    runtime^.dust_pipeline = sdl_dust_pipeline_create(device, paths)
    if runtime^.dust_pipeline == nil {return true}
    runtime^.dust_quad_buffer = sdl.CreateGPUBuffer(device, {
        usage = {.VERTEX},
        size = u32(size_of(Dust_Quad_Vertex) * DUST_QUAD_VERTEX_COUNT),
    })
    runtime^.dust_instance_buffer = sdl.CreateGPUBuffer(device, {
        usage = {.VERTEX},
        size = u32(size_of(Dust_Instance) * DUST_INSTANCE_CAPACITY),
    })
    runtime^.dust_ready = runtime^.dust_quad_buffer != nil &&
        runtime^.dust_instance_buffer != nil
    return true
}

// sdl_dust_runtime_release releases all optional dust resources in reverse order.
sdl_dust_runtime_release :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice) {
    if runtime^.dust_upload_buffer != nil {
        sdl.ReleaseGPUTransferBuffer(device, runtime^.dust_upload_buffer)
    }
    if runtime^.dust_expanded_buffer != nil {
        sdl.ReleaseGPUBuffer(device, runtime^.dust_expanded_buffer)
    }
    if runtime^.dust_instance_buffer != nil {
        sdl.ReleaseGPUBuffer(device, runtime^.dust_instance_buffer)
    }
    if runtime^.dust_quad_buffer != nil {
        sdl.ReleaseGPUBuffer(device, runtime^.dust_quad_buffer)
    }
    if runtime^.dust_pipeline != nil {
        sdl.ReleaseGPUGraphicsPipeline(device, runtime^.dust_pipeline)
    }
    runtime^.dust_upload_buffer = nil
    runtime^.dust_expanded_buffer = nil
    runtime^.dust_instance_buffer = nil
    runtime^.dust_quad_buffer = nil
    runtime^.dust_pipeline = nil
    runtime^.dust_ready = false
}

// sdl_dust_stage_upload writes one occupied dust stream into transfer storage.
sdl_dust_stage_upload :: proc(
    runtime: ^Sdl_Draw_Runtime, encoder: ^Draw_Encoder,
    device: ^sdl.GPUDevice, layout: Sdl_Dust_Upload_Layout) -> bool {
    mapped := sdl.MapGPUTransferBuffer(device, runtime^.dust_upload_buffer, true)
    if mapped == nil {return false}
    quad := [DUST_QUAD_VERTEX_COUNT]Dust_Quad_Vertex{
        {{-0.5, -0.5}, {0, 0}}, {{-0.5, 0.5}, {0, 1}},
        {{0.5, 0.5}, {1, 1}}, {{-0.5, -0.5}, {0, 0}},
        {{0.5, 0.5}, {1, 1}}, {{0.5, -0.5}, {1, 0}},
    }
    offset: u32
    if layout.instance_bytes > 0 {
        mem.copy(mapped, raw_data(quad[:]), int(layout.quad_bytes))
        offset = layout.quad_bytes
        mem.copy(cast(rawptr)(uintptr(mapped) + uintptr(offset)), raw_data(
            encoder^.dust_instances[:encoder^.dust_instance_count]),
            int(layout.instance_bytes))
    } else {
        mem.copy(mapped, raw_data(encoder^.dust_expanded_vertices[
            :encoder^.dust_expanded_vertex_count]), int(layout.expanded_bytes))
    }
    sdl.UnmapGPUTransferBuffer(device, runtime^.dust_upload_buffer)
    return true
}

// sdl_dust_record_upload copies staged dust bytes into resident GPU buffers.
sdl_dust_record_upload :: proc(
    runtime: ^Sdl_Draw_Runtime, command_buffer: ^sdl.GPUCommandBuffer,
    layout: Sdl_Dust_Upload_Layout) -> bool {
    copy_pass := sdl.BeginGPUCopyPass(command_buffer)
    if copy_pass == nil {return false}
    if layout.instance_bytes > 0 {
        sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = runtime^.dust_upload_buffer},
            {buffer = runtime^.dust_quad_buffer, size = layout.quad_bytes}, true)
        sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = runtime^.dust_upload_buffer,
            offset = layout.quad_bytes}, {buffer = runtime^.dust_instance_buffer,
            size = layout.instance_bytes}, true)
    } else {
        sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = runtime^.dust_upload_buffer},
            {buffer = runtime^.dust_expanded_buffer,
            size = layout.expanded_bytes}, true)
    }
    sdl.EndGPUCopyPass(copy_pass)
    return true
}

// sdl_dust_upload records the occupied instanced or expanded stream upload.
sdl_dust_upload :: proc(
    runtime: ^Sdl_Draw_Runtime, encoder: ^Draw_Encoder,
    device: ^sdl.GPUDevice, command_buffer: ^sdl.GPUCommandBuffer) -> bool {
    layout := Sdl_Dust_Upload_Layout{
        quad_bytes = u32(DUST_QUAD_VERTEX_COUNT * size_of(Dust_Quad_Vertex)),
        instance_bytes = u32(
            encoder^.dust_instance_count * size_of(Dust_Instance)),
        expanded_bytes = u32(
            encoder^.dust_expanded_vertex_count * size_of(Draw_Vertex)),
    }
    if layout.instance_bytes == 0 && layout.expanded_bytes == 0 {return true}
    if runtime^.dust_upload_buffer == nil {return false}
    return sdl_dust_stage_upload(runtime, encoder, device, layout) &&
        sdl_dust_record_upload(runtime, command_buffer, layout)
}

// sdl_dust_record_instanced binds atlas state and draws one instance prefix.
sdl_dust_record_instanced :: proc(
    runtime: ^Sdl_Draw_Runtime, command_buffer: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass, draw: ^Dust_Draw) {
    bindings := [2]sdl.GPUBufferBinding{
        {buffer = runtime^.dust_quad_buffer},
        {buffer = runtime^.dust_instance_buffer},
    }
    texture_binding := [1]sdl.GPUTextureSamplerBinding{{
        texture = cast(^sdl.GPUTexture)draw^.texture,
        sampler = runtime^.linear_sampler,
    }}
    sdl.BindGPUGraphicsPipeline(pass, runtime^.dust_pipeline)
    sdl.BindGPUVertexBuffers(pass, 0, raw_data(bindings[:]), len(bindings))
    sdl.BindGPUFragmentSamplers(pass, 0, raw_data(texture_binding[:]), 1)
    sdl.PushGPUVertexUniformData(command_buffer, 0,
        rawptr(&draw^.viewport_extent), 16)
    sdl.SetGPUScissor(pass, {draw^.scissor.x, draw^.scissor.y,
        i32(draw^.scissor.width), i32(draw^.scissor.height)})
    sdl.DrawGPUPrimitives(pass, DUST_QUAD_VERTEX_COUNT, draw^.count, 0, draw^.first)
}

// sdl_dust_record_expanded binds the dedicated fallback stream and atlas.
sdl_dust_record_expanded :: proc(
    runtime: ^Sdl_Draw_Runtime, pass: ^sdl.GPURenderPass, draw: ^Dust_Draw) {
    binding := [1]sdl.GPUBufferBinding{{buffer = runtime^.dust_expanded_buffer}}
    texture_binding := [1]sdl.GPUTextureSamplerBinding{{
        texture = cast(^sdl.GPUTexture)draw^.texture,
        sampler = runtime^.linear_sampler,
    }}
    sdl.BindGPUGraphicsPipeline(pass, runtime^.textured_pipeline)
    sdl.BindGPUVertexBuffers(pass, 0, raw_data(binding[:]), 1)
    sdl.BindGPUFragmentSamplers(pass, 0, raw_data(texture_binding[:]), 1)
    sdl.SetGPUScissor(pass, {draw^.scissor.x, draw^.scissor.y,
        i32(draw^.scissor.width), i32(draw^.scissor.height)})
    sdl.DrawGPUPrimitives(pass, draw^.count, 1, draw^.first, 0)
}
