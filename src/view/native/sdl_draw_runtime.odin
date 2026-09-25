package native

import "core:mem"
import "core:os"
import vmem "core:mem/virtual"

import sdl "vendor:sdl3"

DRAW_VERTEX_CAPACITY :: 65_536
DRAW_INDEX_CAPACITY :: 98_304
DRAW_BATCH_CAPACITY :: 4_096
DRAW_COMMAND_CAPACITY :: 8_192
STROKE_VERTEX_CAPACITY :: 32_768
STROKE_DRAW_CAPACITY :: 1_024
DUST_INSTANCE_CAPACITY :: 65_536
DUST_DRAW_CAPACITY :: 4
DUST_EXPANDED_VERTEX_CAPACITY ::
    DUST_INSTANCE_CAPACITY * DUST_EXPANDED_VERTICES_PER_INSTANCE
DRAW_ARENA_RESERVE_SIZE :: 32 * mem.Megabyte
DRAW_ARENA_INITIAL_COMMIT_SIZE :: 8 * mem.Megabyte

// Sdl_Draw_Shader_Paths names the four packaged 2D shader artifacts.
Sdl_Draw_Shader_Paths :: struct {
    colored_vertex:   string,
    colored_fragment: string,
    textured_vertex:  string,
    textured_fragment: string,
}

// Sdl_Draw_Vertex_Input owns one complete fixed 2D vertex-input description.
Sdl_Draw_Vertex_Input :: struct {
    descriptions: [1]sdl.GPUVertexBufferDescription,
    attributes:   [3]sdl.GPUVertexAttribute,
    attribute_count: u32,
}

// Sdl_Draw_Upload_Statistics describes custom stream upload work for one frame.
Sdl_Draw_Upload_Statistics :: struct {
    stroke_bytes: u32,
    dust_operations: u32,
    dust_bytes: u32,
}

// Sdl_Draw_Record_Context groups the immutable state for one render pass.
Sdl_Draw_Record_Context :: struct {
    runtime: ^Sdl_Draw_Runtime,
    encoder: ^Draw_Encoder,
    command_buffer: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
}

// Sdl_Draw_Command_State tracks bindings across the ordered command stream.
Sdl_Draw_Command_State :: struct {
    active_pipeline: Draw_Pipeline,
    active_kind: Draw_Command_Kind,
    pipeline_bound: bool,
}

// Sdl_Draw_Submission groups frame-specific GPU submission inputs.
Sdl_Draw_Submission :: struct {
    command_buffer: ^sdl.GPUCommandBuffer,
    image: Sdl_Swapchain_Image,
    clear_color: sdl.FColor,
}

// Sdl_Draw_Frame_Statistics records the last successfully submitted frame.
Sdl_Draw_Frame_Statistics :: struct {
    vertices:          u32,
    indices:           u32,
    batches:           u32,
    commands:          u32,
    stroke_vertices:   u32,
    stroke_draws:      u32,
    dust_instances:    u32,
    dust_draws:        u32,
    dust_expanded_vertices: u32,
    pipeline_bindings: u32,
    upload_operations: u32,
    upload_bytes:      u32,
    dust_upload_operations: u32,
    dust_upload_bytes: u32,
    primitive_overflows: u32,
    scissor_overflows: u32,
    command_overflows: u32,
    stroke_overflows:  u32,
    dust_overflows:    u32,
}

// Sdl_Draw_Runtime_Statistics records cumulative work and capacity high waters.
Sdl_Draw_Runtime_Statistics :: struct {
    submitted_frames: u64,
    vertices:         u64,
    indices:          u64,
    batches:          u64,
    commands:         u64,
    stroke_vertices:  u64,
    stroke_draws:     u64,
    dust_instances:   u64,
    dust_draws:       u64,
    dust_expanded_vertices: u64,
    upload_bytes:     u64,
    dust_upload_operations: u64,
    dust_upload_bytes: u64,
    primitive_overflows: u64,
    scissor_overflows: u64,
    command_overflows: u64,
    stroke_overflows:  u64,
    dust_overflows:    u64,
    max_vertices:     u32,
    max_indices:      u32,
    max_batches:      u32,
    max_commands:     u32,
    max_stroke_vertices: u32,
    max_stroke_draws: u32,
    max_dust_instances: u32,
    max_dust_draws: u32,
    max_dust_expanded_vertices: u32,
    max_dust_upload_bytes: u32,
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
    texture_upload_buffer: ^sdl.GPUTransferBuffer,
    stroke_pipeline:       ^sdl.GPUGraphicsPipeline,
    stroke_vertex_buffer:  ^sdl.GPUBuffer,
    stroke_upload_buffer:  ^sdl.GPUTransferBuffer,
    stroke_ready:          bool,
    dust_pipeline:         ^sdl.GPUGraphicsPipeline,
    dust_quad_buffer:      ^sdl.GPUBuffer,
    dust_instance_buffer:  ^sdl.GPUBuffer,
    dust_expanded_buffer:  ^sdl.GPUBuffer,
    dust_upload_buffer:    ^sdl.GPUTransferBuffer,
    dust_ready:            bool,
    dust_atlas:            Sampled_Texture,
    texture_operations: Texture_Operation_Queue,
    arena:             vmem.Arena,
    arena_initialized: bool,
    storage:           Draw_Storage,
    custom_storage:    Draw_Custom_Storage,
    last_frame:        Sdl_Draw_Frame_Statistics,
    statistics:        Sdl_Draw_Runtime_Statistics,
    telemetry_reported: bool,
}

// sdl_draw_runtime_release_buffers releases core transfer and data buffers.
sdl_draw_runtime_release_buffers :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice) {
    if runtime^.texture_upload_buffer != nil {
        sdl.ReleaseGPUTransferBuffer(device, runtime^.texture_upload_buffer)
    }
    if runtime^.upload_buffer != nil {
        sdl.ReleaseGPUTransferBuffer(device, runtime^.upload_buffer)
    }
    if runtime^.index_buffer != nil {
        sdl.ReleaseGPUBuffer(device, runtime^.index_buffer)
    }
    if runtime^.vertex_buffer != nil {
        sdl.ReleaseGPUBuffer(device, runtime^.vertex_buffer)
    }
}

// sdl_draw_runtime_release_core_state releases samplers and 2D pipelines.
sdl_draw_runtime_release_core_state :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice) {
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

// sdl_draw_runtime_release_gpu releases admitted GPU members in reverse order.
sdl_draw_runtime_release_gpu :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice) {
    if device == nil {return}
    if runtime^.dust_atlas.handle != nil {
        sdl.ReleaseGPUTexture(
            device, cast(^sdl.GPUTexture)runtime^.dust_atlas.handle)
        runtime^.dust_atlas = {}
    }
    sdl_dust_runtime_release(runtime, device)
    sdl_stroke_runtime_release(runtime, device)
    sdl_draw_runtime_release_buffers(runtime, device)
    sdl_draw_runtime_release_core_state(runtime, device)
}

// sdl_draw_runtime_destroy releases all display-owned draw resources.
sdl_draw_runtime_destroy :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice) {
    if runtime == nil {return}
    sdl_draw_discard_texture_operations(runtime, device)
    sdl_draw_runtime_release_gpu(runtime, device)
    if runtime^.arena_initialized {
        vmem.arena_destroy(&runtime^.arena)
    }
    runtime^ = {}
}

// sdl_draw_shader_create loads one packaged native shader for immediate admission.
sdl_draw_shader_create :: proc(
    device: ^sdl.GPUDevice, path: string, stage: sdl.GPUShaderStage,
    sampler_count, uniform_count: u32) -> ^sdl.GPUShader {
    source, read_error := os.read_entire_file(path, context.temp_allocator)
    if read_error != nil || len(source) == 0 {return nil}
    return sdl.CreateGPUShader(device, {
        code_size = len(source),
        code = raw_data(source),
        entrypoint = SDL_GPU_SHADER_ENTRYPOINT,
        format = SDL_GPU_SHADER_FORMAT,
        stage = stage,
        num_samplers = sampler_count,
        num_uniform_buffers = uniform_count,
    })
}

// sdl_draw_pipeline_create creates one straight-alpha 2D graphics pipeline.
sdl_draw_pipeline_create :: proc(
    device: ^sdl.GPUDevice, vertex_path, fragment_path: string,
    textured: bool,
    sample_count: sdl.GPUSampleCount) -> ^sdl.GPUGraphicsPipeline {
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
        device, vertex_shader, fragment_shader, textured, sample_count)
}

// sdl_draw_vertex_input describes the fixed Draw_Vertex ABI.
sdl_draw_vertex_input :: proc(textured: bool) -> Sdl_Draw_Vertex_Input {
    input := Sdl_Draw_Vertex_Input{}
    input.descriptions = {{
        slot = 0, pitch = size_of(Draw_Vertex), input_rate = .VERTEX}}
    input.attributes = {
        {location = 0, buffer_slot = 0, format = .FLOAT2, offset = 0},
        {location = 1, buffer_slot = 0, format = .FLOAT2, offset = 8},
        {location = 2, buffer_slot = 0, format = .UBYTE4_NORM, offset = 16},
    }
    input.attribute_count = 2
    if textured {input.attribute_count = 3}
    if !textured {input.attributes[1] = input.attributes[2]}
    return input
}

// sdl_draw_pipeline_create_from_shaders binds the fixed Draw_Vertex ABI.
sdl_draw_pipeline_create_from_shaders :: proc(
    device: ^sdl.GPUDevice, vertex_shader, fragment_shader: ^sdl.GPUShader,
    textured: bool,
    sample_count: sdl.GPUSampleCount) -> ^sdl.GPUGraphicsPipeline {
    input := sdl_draw_vertex_input(textured)
    targets := [1]sdl.GPUColorTargetDescription{
        sdl_stroke_target_description()}
    return sdl.CreateGPUGraphicsPipeline(device, {
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        vertex_input_state = {
            vertex_buffer_descriptions = raw_data(input.descriptions[:]),
            num_vertex_buffers = 1,
            vertex_attributes = raw_data(input.attributes[:]),
            num_vertex_attributes = input.attribute_count,
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

// sdl_draw_runtime_allocate_core_storage admits the ordinary command streams.
sdl_draw_runtime_allocate_core_storage :: proc(
    runtime: ^Sdl_Draw_Runtime, allocator: mem.Allocator) -> bool {
    vertices, vertex_error := make([]Draw_Vertex, DRAW_VERTEX_CAPACITY, allocator)
    indices, index_error := make([]u32, DRAW_INDEX_CAPACITY, allocator)
    batches, batch_error := make([]Draw_Batch, DRAW_BATCH_CAPACITY, allocator)
    commands, command_error := make(
        []Draw_Command, DRAW_COMMAND_CAPACITY, allocator)
    if vertex_error != nil || index_error != nil || batch_error != nil ||
        command_error != nil {return false}
    runtime^.storage = {vertices, indices, batches, commands, nil}
    return true
}

// sdl_draw_runtime_allocate_custom_storage admits optional draw streams.
sdl_draw_runtime_allocate_custom_storage :: proc(
    runtime: ^Sdl_Draw_Runtime, allocator: mem.Allocator) -> bool {
    stroke_vertices, stroke_vertex_error := make(
        []Stroke_Vertex, STROKE_VERTEX_CAPACITY, allocator)
    stroke_draws, stroke_draw_error := make(
        []Stroke_Draw, STROKE_DRAW_CAPACITY, allocator)
    dust_instances, dust_instance_error := make(
        []Dust_Instance, DUST_INSTANCE_CAPACITY, allocator)
    dust_draws, dust_draw_error := make(
        []Dust_Draw, DUST_DRAW_CAPACITY, allocator)
    dust_expanded_vertices, dust_expanded_vertex_error := make(
        []Draw_Vertex, DUST_EXPANDED_VERTEX_CAPACITY, allocator)
    dust_expanded_draws, dust_expanded_draw_error := make(
        []Dust_Draw, DUST_DRAW_CAPACITY, allocator)
    if stroke_vertex_error != nil || stroke_draw_error != nil ||
        dust_instance_error != nil ||
        dust_draw_error != nil || dust_expanded_vertex_error != nil ||
        dust_expanded_draw_error != nil {return false}
    runtime^.custom_storage = {
        stroke_vertices = stroke_vertices,
        stroke_draws = stroke_draws,
        dust_instances = dust_instances,
        dust_draws = dust_draws,
        dust_expanded_vertices = dust_expanded_vertices,
        dust_expanded_draws = dust_expanded_draws,
    }
    runtime^.storage.custom = &runtime^.custom_storage
    return true
}

// sdl_draw_runtime_allocate_storage admits fixed arena-backed CPU staging.
sdl_draw_runtime_allocate_storage :: proc(runtime: ^Sdl_Draw_Runtime) -> bool {
    arena_error := vmem.arena_init_static(&runtime^.arena,
        DRAW_ARENA_RESERVE_SIZE, DRAW_ARENA_INITIAL_COMMIT_SIZE)
    if arena_error != nil {return false}
    runtime^.arena_initialized = true
    allocator := vmem.arena_allocator(&runtime^.arena)
    if !sdl_draw_runtime_allocate_core_storage(runtime, allocator) ||
        !sdl_draw_runtime_allocate_custom_storage(runtime, allocator) {return false}
    return true
}

// sdl_draw_runtime_create admits a complete renderer candidate transactionally.
sdl_draw_runtime_create :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice,
    paths: Sdl_Draw_Shader_Paths,
    sample_count: sdl.GPUSampleCount) -> bool {
    if runtime == nil || device == nil {return false}
    candidate: Sdl_Draw_Runtime
    defer if candidate.colored_pipeline != nil || candidate.arena_initialized {
        sdl_draw_runtime_destroy(&candidate, device)
    }
    if !sdl_draw_runtime_allocate_storage(&candidate) {return false}
    candidate.colored_pipeline = sdl_draw_pipeline_create(device,
        paths.colored_vertex, paths.colored_fragment, false, sample_count)
    candidate.textured_pipeline = sdl_draw_pipeline_create(device,
        paths.textured_vertex, paths.textured_fragment, true, sample_count)
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
    candidate.texture_upload_buffer = sdl.CreateGPUTransferBuffer(device, {
        usage = .UPLOAD, size = TEXTURE_UPLOAD_BYTE_CAPACITY})
    if candidate.colored_pipeline == nil || candidate.textured_pipeline == nil ||
        candidate.nearest_sampler == nil || candidate.linear_sampler == nil ||
        candidate.vertex_buffer == nil || candidate.index_buffer == nil ||
        candidate.upload_buffer == nil || candidate.texture_upload_buffer == nil {
        return false
    }
    runtime^ = candidate
    runtime^.storage.custom = &runtime^.custom_storage
    candidate = {}
    return true
}

// sdl_sampled_texture_create creates one immutable-size RGBA8 sampled texture.
sdl_sampled_texture_create :: proc(
    platform: ^Sdl_Platform, width, height: u32) -> Sampled_Texture {
    if platform == nil || platform^.device == nil || width == 0 || height == 0 {
        return {}
    }
    handle := sdl.CreateGPUTexture(platform^.device, {
        type = .D2,
        format = .R8G8B8A8_UNORM,
        usage = {.SAMPLER},
        width = width,
        height = height,
        layer_count_or_depth = 1,
        num_levels = 1,
        sample_count = ._1,
    })
    return {handle = handle, width = width, height = height}
}

// sdl_sampled_texture_release immediately releases one owner-held texture.
sdl_sampled_texture_release :: proc(
    platform: ^Sdl_Platform, texture: ^Sampled_Texture) {
    if platform == nil || platform^.device == nil || texture == nil {return}
    if texture^.handle != nil {
        sdl.ReleaseGPUTexture(
            platform^.device, cast(^sdl.GPUTexture)texture^.handle)
    }
    texture^ = {}
}

// sdl_draw_batch_command_valid checks one ordinary indexed draw reference.
sdl_draw_batch_command_valid :: proc(
    encoder: ^Draw_Encoder, command: Draw_Command) -> bool {
    if command.index >= u32(encoder^.batch_count) {return false}
    batch := encoder^.batches[command.index]
    return batch.pipeline != .Textured || batch.texture != nil
}

// sdl_draw_tool_command_valid checks one stroke-stream draw reference.
sdl_draw_tool_command_valid :: proc(
    encoder: ^Draw_Encoder, command: Draw_Command) -> bool {
    if command.index >= u32(encoder^.stroke_draw_count) {return false}
    draw := encoder^.stroke_draws[command.index]
    return draw.vertex_count > 0 && draw.first_vertex + draw.vertex_count <=
        u32(encoder^.stroke_vertex_count)
}

// sdl_draw_instanced_dust_command_valid checks one instance prefix.
sdl_draw_instanced_dust_command_valid :: proc(
    encoder: ^Draw_Encoder, command: Draw_Command) -> bool {
    if !encoder^.dust_instancing_enabled ||
        command.index >= u32(encoder^.dust_draw_count) {return false}
    draw := encoder^.dust_draws[command.index]
    return draw.texture != nil && draw.count > 0 &&
        draw.first + draw.count <= u32(encoder^.dust_instance_count)
}

// sdl_draw_expanded_dust_command_valid checks one expanded vertex prefix.
sdl_draw_expanded_dust_command_valid :: proc(
    encoder: ^Draw_Encoder, command: Draw_Command) -> bool {
    if command.index >= u32(encoder^.dust_expanded_draw_count) {return false}
    draw := encoder^.dust_expanded_draws[command.index]
    return draw.texture != nil && draw.count > 0 &&
        draw.first + draw.count <= u32(encoder^.dust_expanded_vertex_count)
}

// sdl_draw_command_valid dispatches validation by encoded command family.
sdl_draw_command_valid :: proc(
    encoder: ^Draw_Encoder, command: Draw_Command) -> bool {
    switch command.kind {
    case .Batch:          return sdl_draw_batch_command_valid(encoder, command)
    case .Tool:           return sdl_draw_tool_command_valid(encoder, command)
    case .Dust_Instanced: return sdl_draw_instanced_dust_command_valid(encoder, command)
    case .Dust_Expanded:  return sdl_draw_expanded_dust_command_valid(encoder, command)
    }
    return false
}

// sdl_draw_encoder_commands_valid rejects incomplete or unsupported command state.
sdl_draw_encoder_commands_valid :: proc(encoder: ^Draw_Encoder) -> bool {
    for command in encoder^.commands[:encoder^.command_count] {
        if !sdl_draw_command_valid(encoder, command) {return false}
    }
    return true
}

// sdl_draw_accumulate_totals adds one submitted frame to lifetime totals.
sdl_draw_accumulate_totals :: proc(
    statistics: ^Sdl_Draw_Runtime_Statistics,
    frame: Sdl_Draw_Frame_Statistics) {
    statistics^.submitted_frames += 1
    statistics^.vertices += u64(frame.vertices)
    statistics^.indices += u64(frame.indices)
    statistics^.batches += u64(frame.batches)
    statistics^.commands += u64(frame.commands)
    statistics^.stroke_vertices += u64(frame.stroke_vertices)
    statistics^.stroke_draws += u64(frame.stroke_draws)
    statistics^.dust_instances += u64(frame.dust_instances)
    statistics^.dust_draws += u64(frame.dust_draws)
    statistics^.dust_expanded_vertices += u64(frame.dust_expanded_vertices)
    statistics^.upload_bytes += u64(frame.upload_bytes)
    statistics^.dust_upload_operations += u64(frame.dust_upload_operations)
    statistics^.dust_upload_bytes += u64(frame.dust_upload_bytes)
    statistics^.primitive_overflows += u64(frame.primitive_overflows)
    statistics^.scissor_overflows += u64(frame.scissor_overflows)
    statistics^.command_overflows += u64(frame.command_overflows)
    statistics^.stroke_overflows += u64(frame.stroke_overflows)
    statistics^.dust_overflows += u64(frame.dust_overflows)
}

// sdl_draw_accumulate_high_waters updates observed bounded-storage peaks.
sdl_draw_accumulate_high_waters :: proc(
    statistics: ^Sdl_Draw_Runtime_Statistics,
    frame: Sdl_Draw_Frame_Statistics) {
    statistics^.max_vertices = max(statistics^.max_vertices, frame.vertices)
    statistics^.max_indices = max(statistics^.max_indices, frame.indices)
    statistics^.max_batches = max(statistics^.max_batches, frame.batches)
    statistics^.max_commands = max(statistics^.max_commands, frame.commands)
    statistics^.max_stroke_vertices = max(
        statistics^.max_stroke_vertices, frame.stroke_vertices)
    statistics^.max_stroke_draws = max(
        statistics^.max_stroke_draws, frame.stroke_draws)
    statistics^.max_dust_instances = max(
        statistics^.max_dust_instances, frame.dust_instances)
    statistics^.max_dust_draws = max(
        statistics^.max_dust_draws, frame.dust_draws)
    statistics^.max_dust_expanded_vertices = max(
        statistics^.max_dust_expanded_vertices, frame.dust_expanded_vertices)
    statistics^.max_dust_upload_bytes = max(
        statistics^.max_dust_upload_bytes, frame.dust_upload_bytes)
    statistics^.max_upload_bytes = max(statistics^.max_upload_bytes, frame.upload_bytes)
}

// sdl_draw_accumulate_statistics adds one frame and updates capacity high waters.
sdl_draw_accumulate_statistics :: proc(
    statistics: ^Sdl_Draw_Runtime_Statistics,
    frame: Sdl_Draw_Frame_Statistics) {
    sdl_draw_accumulate_totals(statistics, frame)
    sdl_draw_accumulate_high_waters(statistics, frame)
}

// sdl_draw_upload_statistics calculates custom-stream upload counts and bytes.
sdl_draw_upload_statistics :: proc(
    encoder: ^Draw_Encoder) -> Sdl_Draw_Upload_Statistics {
    result := Sdl_Draw_Upload_Statistics{
        stroke_bytes = u32(
            encoder^.stroke_vertex_count * size_of(Stroke_Vertex)),
        dust_bytes = u32(
            encoder^.dust_expanded_vertex_count * size_of(Draw_Vertex)),
    }
    instance_bytes := u32(
        encoder^.dust_instance_count * size_of(Dust_Instance))
    if instance_bytes > 0 {
        result.dust_operations = 2
        result.dust_bytes += u32(
            DUST_QUAD_VERTEX_COUNT * size_of(Dust_Quad_Vertex)) + instance_bytes
    } else if result.dust_bytes > 0 {
        result.dust_operations = 1
    }
    return result
}

// sdl_draw_record_statistics publishes one successful submission observation.
sdl_draw_record_statistics :: proc(
    runtime: ^Sdl_Draw_Runtime, encoder: ^Draw_Encoder,
    pipeline_bindings, vertex_bytes, index_bytes: u32) {
    upload := sdl_draw_upload_statistics(encoder)
    frame := Sdl_Draw_Frame_Statistics{
        vertices = u32(encoder^.vertex_count),
        indices = u32(encoder^.index_count),
        batches = u32(encoder^.batch_count),
        commands = u32(encoder^.command_count),
        stroke_vertices = u32(encoder^.stroke_vertex_count),
        stroke_draws = u32(encoder^.stroke_draw_count),
        dust_instances = u32(encoder^.dust_instance_count),
        dust_draws = u32(
            encoder^.dust_draw_count + encoder^.dust_expanded_draw_count),
        dust_expanded_vertices = u32(encoder^.dust_expanded_vertex_count),
        pipeline_bindings = pipeline_bindings,
        upload_operations = (vertex_bytes > 0 ? 1 : 0) +
            (index_bytes > 0 ? 1 : 0) +
            (upload.stroke_bytes > 0 ? 1 : 0) +
            upload.dust_operations,
        upload_bytes = vertex_bytes + index_bytes + upload.stroke_bytes +
            upload.dust_bytes,
        dust_upload_operations = upload.dust_operations,
        dust_upload_bytes = upload.dust_bytes,
        primitive_overflows = encoder^.statistics.primitive_overflows,
        scissor_overflows = encoder^.statistics.scissor_overflows,
        command_overflows = encoder^.statistics.command_overflows,
        stroke_overflows = encoder^.statistics.stroke_overflows,
        dust_overflows = encoder^.statistics.dust_overflows,
    }
    runtime^.last_frame = frame
    sdl_draw_accumulate_statistics(&runtime^.statistics, frame)
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

// sdl_draw_normalize_textures writes queued source pixels into upload storage.
sdl_draw_normalize_textures :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice) -> bool {
    queue := &runtime^.texture_operations
    if queue^.byte_count == 0 {return true}
    mapped := sdl.MapGPUTransferBuffer(device, runtime^.texture_upload_buffer, true)
    if mapped == nil {return false}
    mapped_bytes := (cast([^]u8)mapped)[:int(queue^.byte_count)]
    normalized := true
    for operation in queue^.operations[:queue^.count] {
        if operation.kind == .Retire {continue}
        first := int(operation.byte_offset)
        last := first + int(operation.byte_count)
        if last > len(mapped_bytes) || !texture_normalize_rgba8(
            mapped_bytes[first:last], operation.source, operation.format) {
            normalized = false
            break
        }
    }
    sdl.UnmapGPUTransferBuffer(device, runtime^.texture_upload_buffer)
    return normalized
}

// sdl_draw_record_texture_uploads records normalized texture copies in order.
sdl_draw_record_texture_uploads :: proc(
    runtime: ^Sdl_Draw_Runtime,
    command_buffer: ^sdl.GPUCommandBuffer) -> bool {
    queue := &runtime^.texture_operations
    if queue^.byte_count == 0 {return true}
    copy_pass := sdl.BeginGPUCopyPass(command_buffer)
    if copy_pass == nil {return false}
    for operation in queue^.operations[:queue^.count] {
        if operation.kind == .Retire {continue}
        sdl.UploadToGPUTexture(copy_pass, {
            transfer_buffer = runtime^.texture_upload_buffer,
            offset = operation.byte_offset,
            pixels_per_row = operation.width,
            rows_per_layer = operation.height,
        }, {
            texture = cast(^sdl.GPUTexture)operation.texture,
            w = operation.width,
            h = operation.height,
            d = 1,
        }, operation.kind == .Update)
    }
    sdl.EndGPUCopyPass(copy_pass)
    return true
}

// sdl_draw_upload_textures normalizes and records queued texture copies.
sdl_draw_upload_textures :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice,
    command_buffer: ^sdl.GPUCommandBuffer) -> bool {
    return sdl_draw_normalize_textures(runtime, device) &&
        sdl_draw_record_texture_uploads(runtime, command_buffer)
}

// sdl_draw_finish_texture_operations reports outcomes and releases owned resources.
sdl_draw_finish_texture_operations :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice, succeeded: bool) {
    for operation in runtime^.texture_operations.operations[
        :runtime^.texture_operations.count] {
        if succeeded && operation.kind == .Retire ||
            !succeeded && operation.kind == .Create {
            sdl.ReleaseGPUTexture(device, cast(^sdl.GPUTexture)operation.texture)
        }
        if operation.completion != nil {
            operation.completion(operation.user_data,
                operation.identity, operation.generation, succeeded)
        }
    }
    runtime^.texture_operations = {}
}

// sdl_draw_discard_texture_operations rolls back queued candidate ownership.
sdl_draw_discard_texture_operations :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice) {
    if runtime == nil || device == nil || runtime^.texture_operations.count == 0 {
        return
    }
    sdl_draw_finish_texture_operations(runtime, device, false)
}

// sdl_draw_commit_texture_operations retires queued resources after submission.
sdl_draw_commit_texture_operations :: proc(
    runtime: ^Sdl_Draw_Runtime, device: ^sdl.GPUDevice) {
    sdl_draw_finish_texture_operations(runtime, device, true)
}

// sdl_draw_submit_texture_operations completes startup-only uploads synchronously.
sdl_draw_submit_texture_operations :: proc(
    platform: ^Sdl_Platform, runtime: ^Sdl_Draw_Runtime) -> bool {
    if platform == nil || runtime == nil || runtime^.texture_operations.count == 0 {
        return false
    }
    command_buffer := sdl.AcquireGPUCommandBuffer(platform^.device)
    if command_buffer == nil {return false}
    if !sdl_draw_upload_textures(runtime, platform^.device, command_buffer) {
        _ = sdl.CancelGPUCommandBuffer(command_buffer)
        sdl_draw_discard_texture_operations(runtime, platform^.device)
        return false
    }
    if !sdl.SubmitGPUCommandBuffer(command_buffer) ||
        !sdl.WaitForGPUIdle(platform^.device) {
        sdl_draw_discard_texture_operations(runtime, platform^.device)
        return false
    }
    sdl_draw_commit_texture_operations(runtime, platform^.device)
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

// sdl_draw_push_2d_uniform restores the viewport cbuffer after a custom draw.
sdl_draw_push_2d_uniform :: proc(
    command_buffer: ^sdl.GPUCommandBuffer, encoder: ^Draw_Encoder) {
    viewport_uniform := [4]f32{
        encoder^.logical_extent.x, encoder^.logical_extent.y, 0, 0}
    sdl.PushGPUVertexUniformData(
        command_buffer, 0, raw_data(viewport_uniform[:]), size_of(viewport_uniform))
}

// sdl_draw_bind_2d_buffers restores the core vertex and index bindings.
sdl_draw_bind_2d_buffers :: proc(
    runtime: ^Sdl_Draw_Runtime, pass: ^sdl.GPURenderPass) {
    vertex_binding := [1]sdl.GPUBufferBinding{{buffer = runtime^.vertex_buffer}}
    index_binding := sdl.GPUBufferBinding{buffer = runtime^.index_buffer}
    sdl.BindGPUVertexBuffers(pass, 0, raw_data(vertex_binding[:]), 1)
    sdl.BindGPUIndexBuffer(pass, index_binding, ._32BIT)
}

// sdl_draw_record_batch_command restores core state and records one batch.
sdl_draw_record_batch_command :: proc(
    ctx: Sdl_Draw_Record_Context, state: ^Sdl_Draw_Command_State,
    command: Draw_Command) {
    batch := ctx.encoder^.batches[command.index]
    if !state^.pipeline_bound || state^.active_kind != .Batch {
        sdl_draw_push_2d_uniform(ctx.command_buffer, ctx.encoder)
        sdl_draw_bind_2d_buffers(ctx.runtime, ctx.pass)
    }
    if !state^.pipeline_bound || state^.active_kind != .Batch ||
        batch.pipeline != state^.active_pipeline {
        pipeline := ctx.runtime^.colored_pipeline
        if batch.pipeline == .Textured {pipeline = ctx.runtime^.textured_pipeline}
        sdl.BindGPUGraphicsPipeline(ctx.pass, pipeline)
        state^.active_pipeline = batch.pipeline
    }
    sdl_draw_record_batch(ctx.runtime, ctx.pass, batch)
}

// sdl_draw_record_tool_command records one custom stroke draw.
sdl_draw_record_tool_command :: proc(
    ctx: Sdl_Draw_Record_Context, state: ^Sdl_Draw_Command_State,
    command: Draw_Command) {
    if !state^.pipeline_bound || state^.active_kind != .Tool {
        sdl_stroke_bind(ctx.runtime, ctx.pass)
    }
    sdl_stroke_record_draw(ctx.command_buffer, ctx.pass,
        &ctx.encoder^.stroke_draws[command.index])
}

// sdl_draw_record_expanded_dust_command records one fallback dust draw.
sdl_draw_record_expanded_dust_command :: proc(
    ctx: Sdl_Draw_Record_Context, state: ^Sdl_Draw_Command_State,
    command: Draw_Command) {
    if !state^.pipeline_bound || state^.active_kind != .Dust_Expanded {
        sdl_draw_push_2d_uniform(ctx.command_buffer, ctx.encoder)
    }
    sdl_dust_record_expanded(ctx.runtime, ctx.pass,
        &ctx.encoder^.dust_expanded_draws[command.index])
}

// sdl_draw_record_commands records every ordered operation inside one pass.
sdl_draw_record_commands :: proc(
    runtime: ^Sdl_Draw_Runtime, encoder: ^Draw_Encoder,
    command_buffer: ^sdl.GPUCommandBuffer, pass: ^sdl.GPURenderPass) {
    ctx := Sdl_Draw_Record_Context{runtime, encoder, command_buffer, pass}
    state := Sdl_Draw_Command_State{active_kind = .Batch}
    for command in encoder^.commands[:encoder^.command_count] {
        switch command.kind {
        case .Batch: sdl_draw_record_batch_command(ctx, &state, command)
        case .Tool: sdl_draw_record_tool_command(ctx, &state, command)
        case .Dust_Instanced:
            sdl_dust_record_instanced(runtime, command_buffer, pass,
                &encoder^.dust_draws[command.index])
        case .Dust_Expanded:
            sdl_draw_record_expanded_dust_command(ctx, &state, command)
        }
        state.active_kind = command.kind
        state.pipeline_bound = true
    }
}

// sdl_draw_record_scene clears and records the ordered native command stream.
sdl_draw_record_scene :: proc(
    platform: ^Sdl_Platform, runtime: ^Sdl_Draw_Runtime,
    encoder: ^Draw_Encoder, command_buffer: ^sdl.GPUCommandBuffer,
    clear_color: sdl.FColor) -> bool {
    sdl_draw_push_2d_uniform(command_buffer, encoder)
    target := [1]sdl.GPUColorTargetInfo{
        sdl_scene_color_target_info(platform, clear_color)}
    pass := sdl.BeginGPURenderPass(
        command_buffer, raw_data(target[:]), len(target), nil)
    if pass == nil {return false}
    sdl_draw_bind_2d_buffers(runtime, pass)
    sdl.SetGPUViewport(pass, {
        w = f32(platform^.scene_width), h = f32(platform^.scene_height),
        min_depth = 0, max_depth = 1})
    sdl_draw_record_commands(runtime, encoder, command_buffer, pass)
    sdl.EndGPURenderPass(pass)
    return true
}

// sdl_draw_prepare_submission uploads and records one scene command stream.
sdl_draw_prepare_submission :: proc(
    platform: ^Sdl_Platform, runtime: ^Sdl_Draw_Runtime,
    encoder: ^Draw_Encoder, submission: Sdl_Draw_Submission) -> bool {
    if !sdl_draw_encoder_commands_valid(encoder) ||
        !sdl_draw_upload_textures(runtime, platform^.device,
            submission.command_buffer) ||
        !sdl_draw_upload(runtime, encoder, platform^.device,
            submission.command_buffer) ||
        !sdl_stroke_upload(runtime, encoder, platform^.device,
            submission.command_buffer) ||
        !sdl_dust_upload(runtime, encoder, platform^.device,
            submission.command_buffer) {return false}
    return sdl_draw_record_scene(platform, runtime, encoder,
        submission.command_buffer, submission.clear_color)
}

// sdl_draw_pipeline_binding_count counts ordered native state transitions.
sdl_draw_pipeline_binding_count :: proc(encoder: ^Draw_Encoder) -> u32 {
    count: u32
    previous_kind: Draw_Command_Kind
    previous_pipeline: Draw_Pipeline
    for command, index in encoder^.commands[:encoder^.command_count] {
        changed := index == 0 || command.kind != previous_kind
        if command.kind == .Batch {
            batch := encoder^.batches[command.index]
            changed = changed || batch.pipeline != previous_pipeline
            previous_pipeline = batch.pipeline
        }
        if changed {count += 1}
        previous_kind = command.kind
    }
    return count
}

// sdl_draw_submit uploads, renders, blits, and submits one eligible frame.
sdl_draw_submit :: proc(
    platform: ^Sdl_Platform, runtime: ^Sdl_Draw_Runtime,
    encoder: ^Draw_Encoder, submission: Sdl_Draw_Submission) -> bool {
    if !sdl_draw_prepare_submission(platform, runtime, encoder, submission) {
        _ = sdl.CancelGPUCommandBuffer(submission.command_buffer)
        sdl_draw_discard_texture_operations(runtime, platform^.device)
        return false
    }
    sdl.BlitGPUTexture(submission.command_buffer, {
        source = {texture = platform^.scene_target,
            w = platform^.scene_width, h = platform^.scene_height},
        destination = {texture = submission.image.texture,
            w = submission.image.width, h = submission.image.height},
        load_op = .DONT_CARE,
        filter = .NEAREST,
    })
    if !sdl.SubmitGPUCommandBuffer(submission.command_buffer) {
        sdl_draw_discard_texture_operations(runtime, platform^.device)
        return false
    }
    sdl_draw_commit_texture_operations(runtime, platform^.device)
    vertex_bytes := u32(encoder^.vertex_count * size_of(Draw_Vertex))
    index_bytes := u32(encoder^.index_count * size_of(u32))
    sdl_draw_record_statistics(
        runtime, encoder, sdl_draw_pipeline_binding_count(encoder),
        vertex_bytes, index_bytes)
    return true
}
