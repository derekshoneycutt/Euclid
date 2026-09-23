package native

import "core:mem"
import "core:os"
import vmem "core:mem/virtual"

import sdl "vendor:sdl3"

DRAW_VERTEX_CAPACITY :: 65_536
DRAW_INDEX_CAPACITY :: 98_304
DRAW_BATCH_CAPACITY :: 4_096
DRAW_ARENA_RESERVE_SIZE :: 4 * mem.Megabyte
DRAW_ARENA_INITIAL_COMMIT_SIZE :: 4 * mem.Megabyte

// Sdl_Draw_Shader_Paths names the four packaged 2D shader artifacts.
Sdl_Draw_Shader_Paths :: struct {
    colored_vertex:   string,
    colored_fragment: string,
    textured_vertex:  string,
    textured_fragment: string,
}

// Sdl_Draw_Frame_Statistics records the last successfully submitted frame.
Sdl_Draw_Frame_Statistics :: struct {
    vertices:          u32,
    indices:           u32,
    batches:           u32,
    pipeline_bindings: u32,
    upload_operations: u32,
    upload_bytes:      u32,
    primitive_overflows: u32,
    scissor_overflows: u32,
}

// Sdl_Draw_Runtime_Statistics records cumulative work and capacity high waters.
Sdl_Draw_Runtime_Statistics :: struct {
    submitted_frames: u64,
    vertices:         u64,
    indices:          u64,
    batches:          u64,
    upload_bytes:     u64,
    primitive_overflows: u64,
    scissor_overflows: u64,
    max_vertices:     u32,
    max_indices:      u32,
    max_batches:      u32,
    max_upload_bytes: u32,
}

// Sdl_Draw_Runtime owns fixed CPU staging and display-thread SDL GPU resources.
Sdl_Draw_Runtime :: struct {
    colored_pipeline:  ^sdl.GPUGraphicsPipeline,
    textured_pipeline: ^sdl.GPUGraphicsPipeline,
    nearest_sampler:   ^sdl.GPUSampler,
    linear_sampler:    ^sdl.GPUSampler,
    vertex_buffer:     ^sdl.GPUBuffer,
    index_buffer:      ^sdl.GPUBuffer,
    upload_buffer:     ^sdl.GPUTransferBuffer,
    arena:             vmem.Arena,
    arena_initialized: bool,
    storage:           Draw_Storage,
    last_frame:        Sdl_Draw_Frame_Statistics,
    statistics:        Sdl_Draw_Runtime_Statistics,
    telemetry_reported: bool,
}

// sdl_draw_runtime_release_gpu releases admitted GPU members in reverse order.
sdl_draw_runtime_release_gpu :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice) {
    if device == nil {return}
    if runtime^.upload_buffer != nil {
        sdl.ReleaseGPUTransferBuffer(device, runtime^.upload_buffer)
    }
    if runtime^.index_buffer != nil {
        sdl.ReleaseGPUBuffer(device, runtime^.index_buffer)
    }
    if runtime^.vertex_buffer != nil {
        sdl.ReleaseGPUBuffer(device, runtime^.vertex_buffer)
    }
    if runtime^.linear_sampler != nil {
        sdl.ReleaseGPUSampler(device, runtime^.linear_sampler)
    }
    if runtime^.nearest_sampler != nil {
        sdl.ReleaseGPUSampler(device, runtime^.nearest_sampler)
    }
    if runtime^.textured_pipeline != nil {
        sdl.ReleaseGPUGraphicsPipeline(device, runtime^.textured_pipeline)
    }
    if runtime^.colored_pipeline != nil {
        sdl.ReleaseGPUGraphicsPipeline(device, runtime^.colored_pipeline)
    }
}

// sdl_draw_runtime_destroy releases all display-owned draw resources.
sdl_draw_runtime_destroy :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice) {
    if runtime == nil {return}
    sdl_draw_runtime_release_gpu(runtime, device)
    if runtime^.arena_initialized {
        vmem.arena_destroy(&runtime^.arena)
    }
    runtime^ = {}
}

// sdl_draw_shader_create loads one packaged SPIR-V shader for immediate admission.
sdl_draw_shader_create :: proc(
    device: ^sdl.GPUDevice, path: string, stage: sdl.GPUShaderStage,
    sampler_count, uniform_count: u32) -> ^sdl.GPUShader {
    source, read_error := os.read_entire_file(path, context.temp_allocator)
    if read_error != nil || len(source) == 0 {return nil}
    return sdl.CreateGPUShader(device, {
        code_size = len(source),
        code = raw_data(source),
        entrypoint = "main",
        format = {.SPIRV},
        stage = stage,
        num_samplers = sampler_count,
        num_uniform_buffers = uniform_count,
    })
}

// sdl_draw_pipeline_create creates one straight-alpha 2D graphics pipeline.
sdl_draw_pipeline_create :: proc(
    device: ^sdl.GPUDevice, vertex_path, fragment_path: string,
    textured: bool) -> ^sdl.GPUGraphicsPipeline {
    vertex_shader := sdl_draw_shader_create(device, vertex_path, .VERTEX, 0, 1)
    if vertex_shader == nil {return nil}
    defer sdl.ReleaseGPUShader(device, vertex_shader)
    sampler_count: u32 = 0
    if textured {sampler_count = 1}
    fragment_shader := sdl_draw_shader_create(
        device, fragment_path, .FRAGMENT, sampler_count, 0)
    if fragment_shader == nil {return nil}
    defer sdl.ReleaseGPUShader(device, fragment_shader)
    return sdl_draw_pipeline_create_from_shaders(
        device, vertex_shader, fragment_shader, textured)
}

// sdl_draw_pipeline_create_from_shaders binds the fixed Draw_Vertex ABI.
sdl_draw_pipeline_create_from_shaders :: proc(
    device: ^sdl.GPUDevice, vertex_shader, fragment_shader: ^sdl.GPUShader,
    textured: bool) -> ^sdl.GPUGraphicsPipeline {
    description := [1]sdl.GPUVertexBufferDescription{{
        slot = 0, pitch = size_of(Draw_Vertex), input_rate = .VERTEX}}
    attributes := [3]sdl.GPUVertexAttribute{
        {location = 0, buffer_slot = 0, format = .FLOAT2, offset = 0},
        {location = 1, buffer_slot = 0, format = .FLOAT2, offset = 8},
        {location = 2, buffer_slot = 0, format = .UBYTE4_NORM, offset = 16},
    }
    attribute_count: u32 = 2
    if textured {attribute_count = 3}
    if !textured {attributes[1] = attributes[2]}
    target := [1]sdl.GPUColorTargetDescription{{
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
    }}
    return sdl.CreateGPUGraphicsPipeline(device, {
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        vertex_input_state = {
            vertex_buffer_descriptions = raw_data(description[:]),
            num_vertex_buffers = 1,
            vertex_attributes = raw_data(attributes[:]),
            num_vertex_attributes = attribute_count,
        },
        primitive_type = .TRIANGLELIST,
        rasterizer_state = {
            fill_mode = .FILL, cull_mode = .NONE,
            front_face = .COUNTER_CLOCKWISE,
        },
        multisample_state = {sample_count = ._1},
        target_info = {
            color_target_descriptions = raw_data(target[:]),
            num_color_targets = 1,
        },
    })
}

// sdl_draw_sampler_create creates one clamped nearest or linear sampler.
sdl_draw_sampler_create :: proc(
    device: ^sdl.GPUDevice, filter: sdl.GPUFilter) -> ^sdl.GPUSampler {
    return sdl.CreateGPUSampler(device, {
        min_filter = filter,
        mag_filter = filter,
        mipmap_mode = .NEAREST,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    })
}

// sdl_draw_runtime_allocate_storage admits fixed arena-backed CPU staging.
sdl_draw_runtime_allocate_storage :: proc(runtime: ^Sdl_Draw_Runtime) -> bool {
    arena_error := vmem.arena_init_static(&runtime^.arena,
        DRAW_ARENA_RESERVE_SIZE, DRAW_ARENA_INITIAL_COMMIT_SIZE)
    if arena_error != nil {return false}
    runtime^.arena_initialized = true
    allocator := vmem.arena_allocator(&runtime^.arena)
    vertices, vertex_error := make([]Draw_Vertex, DRAW_VERTEX_CAPACITY, allocator)
    indices, index_error := make([]u32, DRAW_INDEX_CAPACITY, allocator)
    batches, batch_error := make([]Draw_Batch, DRAW_BATCH_CAPACITY, allocator)
    if vertex_error != nil || index_error != nil || batch_error != nil {return false}
    runtime^.storage = {vertices, indices, batches}
    return true
}

// sdl_draw_runtime_create admits a complete renderer candidate transactionally.
sdl_draw_runtime_create :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice,
    paths: Sdl_Draw_Shader_Paths) -> bool {
    if runtime == nil || device == nil {return false}
    candidate: Sdl_Draw_Runtime
    defer if candidate.colored_pipeline != nil || candidate.arena_initialized {
        sdl_draw_runtime_destroy(&candidate, device)
    }
    if !sdl_draw_runtime_allocate_storage(&candidate) {return false}
    candidate.colored_pipeline = sdl_draw_pipeline_create(device,
        paths.colored_vertex, paths.colored_fragment, false)
    candidate.textured_pipeline = sdl_draw_pipeline_create(device,
        paths.textured_vertex, paths.textured_fragment, true)
    candidate.nearest_sampler = sdl_draw_sampler_create(device, .NEAREST)
    candidate.linear_sampler = sdl_draw_sampler_create(device, .LINEAR)
    candidate.vertex_buffer = sdl.CreateGPUBuffer(device, {
        usage = {.VERTEX}, size = u32(size_of(Draw_Vertex) * DRAW_VERTEX_CAPACITY)})
    candidate.index_buffer = sdl.CreateGPUBuffer(device, {
        usage = {.INDEX}, size = u32(size_of(u32) * DRAW_INDEX_CAPACITY)})
    upload_size := size_of(Draw_Vertex) * DRAW_VERTEX_CAPACITY +
        size_of(u32) * DRAW_INDEX_CAPACITY
    candidate.upload_buffer = sdl.CreateGPUTransferBuffer(device, {
        usage = .UPLOAD, size = u32(upload_size)})
    if candidate.colored_pipeline == nil || candidate.textured_pipeline == nil ||
        candidate.nearest_sampler == nil || candidate.linear_sampler == nil ||
        candidate.vertex_buffer == nil || candidate.index_buffer == nil ||
        candidate.upload_buffer == nil {return false}
    runtime^ = candidate
    candidate = {}
    return true
}

// sdl_draw_encoder_batches_valid rejects incomplete textured batch state.
sdl_draw_encoder_batches_valid :: proc(encoder: ^Draw_Encoder) -> bool {
    for batch in encoder^.batches[:encoder^.batch_count] {
        if batch.pipeline == .Textured && batch.texture == nil {return false}
    }
    return true
}

// sdl_draw_record_statistics publishes one successful submission observation.
sdl_draw_record_statistics :: proc(
    runtime: ^Sdl_Draw_Runtime, encoder: ^Draw_Encoder,
    pipeline_bindings, vertex_bytes, index_bytes: u32) {
    frame := Sdl_Draw_Frame_Statistics{
        vertices = u32(encoder^.vertex_count),
        indices = u32(encoder^.index_count),
        batches = u32(encoder^.batch_count),
        pipeline_bindings = pipeline_bindings,
        upload_operations = (vertex_bytes > 0 ? 1 : 0) + (index_bytes > 0 ? 1 : 0),
        upload_bytes = vertex_bytes + index_bytes,
        primitive_overflows = encoder^.statistics.primitive_overflows,
        scissor_overflows = encoder^.statistics.scissor_overflows,
    }
    runtime^.last_frame = frame
    statistics := &runtime^.statistics
    statistics^.submitted_frames += 1
    statistics^.vertices += u64(frame.vertices)
    statistics^.indices += u64(frame.indices)
    statistics^.batches += u64(frame.batches)
    statistics^.upload_bytes += u64(frame.upload_bytes)
    statistics^.primitive_overflows += u64(frame.primitive_overflows)
    statistics^.scissor_overflows += u64(frame.scissor_overflows)
    statistics^.max_vertices = max(statistics^.max_vertices, frame.vertices)
    statistics^.max_indices = max(statistics^.max_indices, frame.indices)
    statistics^.max_batches = max(statistics^.max_batches, frame.batches)
    statistics^.max_upload_bytes = max(statistics^.max_upload_bytes, frame.upload_bytes)
}

// sdl_draw_upload records cycled vertex and index uploads for one frame.
sdl_draw_upload :: proc(
    runtime: ^Sdl_Draw_Runtime, encoder: ^Draw_Encoder,
    device: ^sdl.GPUDevice, command_buffer: ^sdl.GPUCommandBuffer) -> bool {
    vertex_bytes := u32(encoder^.vertex_count * size_of(Draw_Vertex))
    index_bytes := u32(encoder^.index_count * size_of(u32))
    if vertex_bytes == 0 && index_bytes == 0 {return true}
    mapped := sdl.MapGPUTransferBuffer(device, runtime^.upload_buffer, true)
    if mapped == nil {return false}
    mapped_bytes := (cast([^]u8)mapped)[:int(vertex_bytes + index_bytes)]
    if vertex_bytes > 0 {
        mem.copy(rawptr(&mapped_bytes[0]), raw_data(
            encoder^.vertices[:encoder^.vertex_count]), int(vertex_bytes))
    }
    if index_bytes > 0 {
        mem.copy(rawptr(&mapped_bytes[int(vertex_bytes)]), raw_data(
            encoder^.indices[:encoder^.index_count]), int(index_bytes))
    }
    sdl.UnmapGPUTransferBuffer(device, runtime^.upload_buffer)
    copy_pass := sdl.BeginGPUCopyPass(command_buffer)
    if copy_pass == nil {return false}
    if vertex_bytes > 0 {
        sdl.UploadToGPUBuffer(copy_pass,
            {transfer_buffer = runtime^.upload_buffer},
            {buffer = runtime^.vertex_buffer, size = vertex_bytes}, true)
    }
    if index_bytes > 0 {
        sdl.UploadToGPUBuffer(copy_pass,
            {transfer_buffer = runtime^.upload_buffer, offset = vertex_bytes},
            {buffer = runtime^.index_buffer, size = index_bytes}, true)
    }
    sdl.EndGPUCopyPass(copy_pass)
    return true
}

// sdl_draw_record_batch binds one compatible state interval and draws it.
sdl_draw_record_batch :: proc(
    runtime: ^Sdl_Draw_Runtime, pass: ^sdl.GPURenderPass,
    batch: Draw_Batch) {
    sdl.SetGPUScissor(pass, {
        batch.scissor.x, batch.scissor.y,
        i32(batch.scissor.width), i32(batch.scissor.height)})
    if batch.pipeline == .Textured {
        sampler := runtime^.nearest_sampler
        if batch.sampler == .Linear {sampler = runtime^.linear_sampler}
        binding := [1]sdl.GPUTextureSamplerBinding{{
            texture = cast(^sdl.GPUTexture)batch.texture,
            sampler = sampler,
        }}
        sdl.BindGPUFragmentSamplers(pass, 0, raw_data(binding[:]), 1)
    }
    sdl.DrawGPUIndexedPrimitives(
        pass, batch.index_count, 1, batch.first_index, 0, 0)
}

// sdl_draw_record_scene clears and records all ordered batches to the scene target.
sdl_draw_record_scene :: proc(
    platform: ^Sdl_Platform, runtime: ^Sdl_Draw_Runtime,
    encoder: ^Draw_Encoder, command_buffer: ^sdl.GPUCommandBuffer,
    clear_color: sdl.FColor) -> bool {
    viewport_uniform := [4]f32{
        encoder^.logical_extent.x, encoder^.logical_extent.y, 0, 0}
    sdl.PushGPUVertexUniformData(
        command_buffer, 0, raw_data(viewport_uniform[:]), size_of(viewport_uniform))
    target := [1]sdl.GPUColorTargetInfo{{
        texture = platform^.scene_target,
        clear_color = clear_color,
        load_op = .CLEAR,
        store_op = .STORE,
    }}
    pass := sdl.BeginGPURenderPass(
        command_buffer, raw_data(target[:]), len(target), nil)
    if pass == nil {return false}
    vertex_binding := [1]sdl.GPUBufferBinding{{buffer = runtime^.vertex_buffer}}
    index_binding := sdl.GPUBufferBinding{buffer = runtime^.index_buffer}
    sdl.BindGPUVertexBuffers(pass, 0, raw_data(vertex_binding[:]), 1)
    sdl.BindGPUIndexBuffer(pass, index_binding, ._32BIT)
    sdl.SetGPUViewport(pass, {
        w = f32(platform^.scene_width), h = f32(platform^.scene_height),
        min_depth = 0, max_depth = 1,
    })
    active_pipeline: Draw_Pipeline
    pipeline_bound := false
    for batch in encoder^.batches[:encoder^.batch_count] {
        if !pipeline_bound || batch.pipeline != active_pipeline {
            pipeline := runtime^.colored_pipeline
            if batch.pipeline == .Textured {pipeline = runtime^.textured_pipeline}
            sdl.BindGPUGraphicsPipeline(pass, pipeline)
            active_pipeline = batch.pipeline
            pipeline_bound = true
        }
        sdl_draw_record_batch(runtime, pass, batch)
    }
    sdl.EndGPURenderPass(pass)
    return true
}

// sdl_draw_submit uploads, renders, blits, and submits one eligible frame.
sdl_draw_submit :: proc(
    platform: ^Sdl_Platform, runtime: ^Sdl_Draw_Runtime,
    encoder: ^Draw_Encoder, command_buffer: ^sdl.GPUCommandBuffer,
    image: Sdl_Swapchain_Image, clear_color: sdl.FColor) -> bool {
    if !sdl_draw_encoder_batches_valid(encoder) ||
        !sdl_draw_upload(runtime, encoder, platform^.device, command_buffer) ||
        !sdl_draw_record_scene(
            platform, runtime, encoder, command_buffer, clear_color) {
        _ = sdl.CancelGPUCommandBuffer(command_buffer)
        return false
    }
    sdl.BlitGPUTexture(command_buffer, {
        source = {texture = platform^.scene_target,
            w = platform^.scene_width, h = platform^.scene_height},
        destination = {texture = image.texture, w = image.width, h = image.height},
        load_op = .DONT_CARE,
        filter = .NEAREST,
    })
    if !sdl.SubmitGPUCommandBuffer(command_buffer) {return false}
    pipeline_bindings: u32
    previous: Draw_Pipeline
    for batch, index in encoder^.batches[:encoder^.batch_count] {
        if index == 0 || batch.pipeline != previous {pipeline_bindings += 1}
        previous = batch.pipeline
    }
    vertex_bytes := u32(encoder^.vertex_count * size_of(Draw_Vertex))
    index_bytes := u32(encoder^.index_count * size_of(u32))
    sdl_draw_record_statistics(
        runtime, encoder, pipeline_bindings, vertex_bytes, index_bytes)
    return true
}
