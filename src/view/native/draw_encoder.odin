package native

import "core:math"

import color "../../core/color"
import geometry "../../core/geometry"

DRAW_SCISSOR_STACK_CAPACITY :: 16
DRAW_CIRCLE_SEGMENTS :: 32
DRAW_POLYLINE_FAN_SEGMENTS :: 12
DRAW_POLYLINE_POINT_EPSILON :: 0.001
DRAW_POLYLINE_MITER_EPSILON :: 0.0001

// Draw_Pipeline selects one immutable native 2D graphics pipeline.
Draw_Pipeline :: enum u8 {
    Colored,
    Textured,
}

// Draw_Sampler selects texture filtering without exposing native handles.
Draw_Sampler :: enum u8 {
    Nearest,
    Linear,
}

// Draw_Texture_Binding pairs one texture handle with its sampling policy.
Draw_Texture_Binding :: struct {
    texture: rawptr,
    sampler: Draw_Sampler,
}

// Draw_Textured_Vertices holds parallel positions and texture coordinates.
Draw_Textured_Vertices :: struct {
    positions: []geometry.Vector2,
    texcoords: []geometry.Vector2,
}

// Draw_Vertex is the fixed CPU/GPU record shared by both 2D pipelines.
Draw_Vertex :: struct {
    position: geometry.Vector2,
    texcoord: geometry.Vector2,
    color: color.Color_RGBA8,
    padding: [4]u8,
}

#assert(size_of(Draw_Vertex) == 24)

// Stroke_Vertex is the fixed vertex ABI consumed by stroke3d.vert.
Stroke_Vertex :: struct {
    position: [3]f32,
    auxiliary: [2]f32,
    color: [4]f32,
}

#assert(size_of(Stroke_Vertex) == 36)

// Stroke_Vertex_Uniforms maps one logical frame into GPU clip coordinates.
Stroke_Vertex_Uniforms :: struct {
    clip_from_model: [16]f32,
}

#assert(size_of(Stroke_Vertex_Uniforms) == 64)

// Stroke_Fragment_Uniforms matches the reflected stroke3d fragment cbuffer.
Stroke_Fragment_Uniforms :: struct {
    light_direction_view: [3]f32,
    ambient: f32,
    diffuse: f32,
    material_roughness: f32,
    material_fresnel_0: f32,
    material_specular_tint: f32,
    material_shadow_limit: f32,
    radius: f32,
    stroke_mode: f32,
    strip_alpha: f32,
    segment_p0: [2]f32,
    segment_p1: [2]f32,
    strip_color: [3]f32,
    strip_side_extent: f32,
    arc_intersections_enabled: f32,
    intersection_depth_width: f32,
    attachment_extent: f32,
    occluder_count: u32,
    occluder_p0_p1: [2][4]f32,
    occluder_radius_depths: [2][4]f32,
    occluder_tangent: [2][4]f32,
}

#assert(size_of(Stroke_Fragment_Uniforms) == 192)

// Dust_Quad_Vertex is the static per-vertex ABI consumed by dust_instanced.vert.
Dust_Quad_Vertex :: struct {
    position: [2]f32,
    texcoord: [2]f32,
}

#assert(size_of(Dust_Quad_Vertex) == 16)

// Dust_Instance is the fixed per-instance ABI consumed by dust_instanced.vert.
Dust_Instance :: struct {
    center_diameter: [3]f32,
    color: [4]f32,
    sprite_index: f32,
}

#assert(size_of(Dust_Instance) == 32)
DUST_ATLAS_COLUMNS :: 3
DUST_ATLAS_ROWS :: 3
DUST_QUAD_VERTEX_COUNT :: 6
DUST_EXPANDED_VERTICES_PER_INSTANCE :: 6

// Draw_Scissor stores one physical-pixel top-left clipping rectangle.
Draw_Scissor :: struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
}

// Draw_Batch identifies one contiguous compatible indexed draw interval.
Draw_Batch :: struct {
    pipeline: Draw_Pipeline,
    texture: rawptr,
    sampler: Draw_Sampler,
    scissor: Draw_Scissor,
    first_index: u32,
    index_count: u32,
}

// Draw_Command_Kind identifies one ordered native submission operation.
Draw_Command_Kind :: enum u8 {
    Batch,
    Tool,
    Dust_Instanced,
    Dust_Expanded,
}

// Draw_Command references one fixed record in an owner-specific command array.
Draw_Command :: struct {
    kind: Draw_Command_Kind,
    index: u32,
}

// Stroke_Draw identifies one contiguous triangle-list stroke and its uniforms.
Stroke_Draw :: struct {
    first_vertex: u32,
    vertex_count: u32,
    scissor: Draw_Scissor,
    vertex_uniforms: Stroke_Vertex_Uniforms,
    fragment_uniforms: Stroke_Fragment_Uniforms,
}

// Dust_Draw identifies one instanced or expanded atlas draw interval.
Dust_Draw :: struct {
    first: u32,
    count: u32,
    texture: rawptr,
    scissor: Draw_Scissor,
    viewport_extent: [2]f32,
}

// Draw_State groups native batch compatibility without exposing SDL handles.
Draw_State :: struct {
    pipeline: Draw_Pipeline,
    texture: rawptr,
    sampler: Draw_Sampler,
}

// Draw_Polyline_Point_Kind preserves semantic cusp intent through tessellation.
Draw_Polyline_Point_Kind :: enum u8 {
    Ordinary,
    Cusp,
}

// Draw_Polyline_Topology controls endpoint and closure treatment.
Draw_Polyline_Topology :: enum u8 {
    Open,
    Closed,
}

// Draw_Polyline_Cap selects whether an open end receives a round fan.
Draw_Polyline_Cap :: enum u8 {
    Butt,
    Round,
}

// Draw_Polyline_Style groups one colored stroke's topology and geometry policy.
Draw_Polyline_Style :: struct {
    width: f32,
    miter_limit: f32,
    color: color.Color_RGBA8,
    topology: Draw_Polyline_Topology,
    start_cap: Draw_Polyline_Cap,
    finish_cap: Draw_Polyline_Cap,
}

Draw_Polyline_Group :: struct {
    point: geometry.Vector2,
    kind: Draw_Polyline_Point_Kind,
    next: int,
}

Draw_Polyline_Summary :: struct {
    group_count: int,
    raw_end: int,
    first_kind: Draw_Polyline_Point_Kind,
    vertices: int,
    indices: int,
}

Draw_Polyline_Join :: enum u8 {
    Miter,
    Bevel,
    Cusp,
}

Draw_Polyline_Pair :: struct {
    left: u32,
    right: u32,
}

Draw_Polyline_Node :: struct {
    incoming: Draw_Polyline_Pair,
    outgoing: Draw_Polyline_Pair,
}

Draw_Polyline_Builder :: struct {
    encoder: ^Draw_Encoder,
    batch: ^Draw_Batch,
    base_vertex: u32,
    vertex_count: int,
    index_count: int,
    color: color.Color_RGBA8,
}

// Draw_Encoder_Statistics records bounded work and rejected primitives.
Draw_Encoder_Statistics :: struct {
    vertices: u32,
    indices: u32,
    batches: u32,
    commands: u32,
    stroke_vertices: u32,
    stroke_draws: u32,
    curve_candidate_points: u32,
    curve_retained_points: u32,
    dust_instances: u32,
    dust_draws: u32,
    dust_expanded_vertices: u32,
    primitive_overflows: u32,
    scissor_overflows: u32,
    command_overflows: u32,
    stroke_overflows: u32,
    dust_overflows: u32,
}

// Draw_Custom_Storage groups optional fixed custom-pipeline frame records.
Draw_Custom_Storage :: struct {
    stroke_vertices: []Stroke_Vertex,
    stroke_draws: []Stroke_Draw,
    dust_instances: []Dust_Instance,
    dust_draws: []Dust_Draw,
    dust_expanded_vertices: []Draw_Vertex,
    dust_expanded_draws: []Dust_Draw,
}

// Draw_Storage borrows fixed-capacity frame buffers from the display owner.
Draw_Storage :: struct {
    vertices: []Draw_Vertex,
    indices: []u32,
    batches: []Draw_Batch,
    commands: []Draw_Command,
    custom: ^Draw_Custom_Storage,
}

// Draw_Encoder stores one frame in caller-owned fixed-capacity slices.
Draw_Encoder :: struct {
    vertices: []Draw_Vertex,
    indices: []u32,
    batches: []Draw_Batch,
    commands: []Draw_Command,
    stroke_vertices: []Stroke_Vertex,
    stroke_draws: []Stroke_Draw,
    dust_instances: []Dust_Instance,
    dust_draws: []Dust_Draw,
    dust_expanded_vertices: []Draw_Vertex,
    dust_expanded_draws: []Dust_Draw,
    vertex_count: int,
    index_count: int,
    batch_count: int,
    command_count: int,
    stroke_vertex_count: int,
    stroke_draw_count: int,
    dust_instance_count: int,
    dust_draw_count: int,
    dust_expanded_vertex_count: int,
    dust_expanded_draw_count: int,
    strokes_enabled: bool,
    dust_instancing_enabled: bool,
    logical_extent: geometry.Vector2,
    physical_extent: [2]u32,
    scissors: [DRAW_SCISSOR_STACK_CAPACITY]geometry.Rectangle,
    scissor_count: int,
    statistics: Draw_Encoder_Statistics,
}

// draw_encoder_record_curve_reduction accumulates bounded projected point counts.
draw_encoder_record_curve_reduction :: #force_inline proc(
    encoder: ^Draw_Encoder, candidate_count, retained_count: int) {
    if encoder == nil || candidate_count < 0 || retained_count < 0 {return}
    encoder^.statistics.curve_candidate_points += u32(candidate_count)
    encoder^.statistics.curve_retained_points += u32(retained_count)
}

// draw_encoder_enable_strokes records optional pipeline availability for fallbacks.
draw_encoder_enable_strokes :: proc(encoder: ^Draw_Encoder, enabled: bool) {
    if encoder != nil {encoder^.strokes_enabled = enabled}
}

// draw_encoder_begin resets one frame over caller-owned bounded storage.
draw_encoder_begin :: proc(
    encoder: ^Draw_Encoder,
    storage: Draw_Storage,
    logical_extent: geometry.Vector2,
    physical_extent: [2]u32) -> bool {
    if encoder == nil || logical_extent.x <= 0 || logical_extent.y <= 0 ||
        physical_extent.x == 0 || physical_extent.y == 0 {
        return false
    }
    encoder^ = {
        vertices = storage.vertices,
        indices = storage.indices,
        batches = storage.batches,
        commands = storage.commands,
        logical_extent = logical_extent,
        physical_extent = physical_extent,
        scissor_count = 1,
    }
    if storage.custom != nil {
        encoder^.stroke_vertices = storage.custom^.stroke_vertices
        encoder^.stroke_draws = storage.custom^.stroke_draws
        encoder^.dust_instances = storage.custom^.dust_instances
        encoder^.dust_draws = storage.custom^.dust_draws
        encoder^.dust_expanded_vertices = storage.custom^.dust_expanded_vertices
        encoder^.dust_expanded_draws = storage.custom^.dust_expanded_draws
    }
    encoder^.scissors[0] = {0, 0, logical_extent.x, logical_extent.y}
    return true
}

// draw_encoder_enable_dust_instancing records optional pipeline availability.
draw_encoder_enable_dust_instancing :: proc(
    encoder: ^Draw_Encoder, enabled: bool) {
    if encoder != nil {encoder^.dust_instancing_enabled = enabled}
}

// draw_encoder_intersect returns the visible overlap of two logical clips.
draw_encoder_intersect :: proc(
    first, second: geometry.Rectangle) -> geometry.Rectangle {
    left := max(first.x, second.x)
    top := max(first.y, second.y)
    right := min(first.x + first.width, second.x + second.width)
    bottom := min(first.y + first.height, second.y + second.height)
    return {left, top, max(f32(0), right - left), max(f32(0), bottom - top)}
}

// draw_encoder_push_scissor intersects and pushes one logical clip.
draw_encoder_push_scissor :: proc(
    encoder: ^Draw_Encoder, rectangle: geometry.Rectangle) -> bool {
    if encoder^.scissor_count >= len(encoder^.scissors) {
        encoder^.statistics.scissor_overflows += 1
        return false
    }
    parent := encoder^.scissors[encoder^.scissor_count - 1]
    encoder^.scissors[encoder^.scissor_count] =
        draw_encoder_intersect(parent, rectangle)
    encoder^.scissor_count += 1
    return true
}

// draw_encoder_pop_scissor restores the previous logical clip.
draw_encoder_pop_scissor :: proc(encoder: ^Draw_Encoder) -> bool {
    if encoder^.scissor_count <= 1 {
        encoder^.statistics.scissor_overflows += 1
        return false
    }
    encoder^.scissor_count -= 1
    return true
}

// draw_encoder_physical_scissor converts the active clip outward to physical pixels.
draw_encoder_physical_scissor :: proc(encoder: ^Draw_Encoder) -> Draw_Scissor {
    rectangle := encoder^.scissors[encoder^.scissor_count - 1]
    scale_x := f64(encoder^.physical_extent.x) / f64(encoder^.logical_extent.x)
    scale_y := f64(encoder^.physical_extent.y) / f64(encoder^.logical_extent.y)
    left := clamp(int(math.floor(f64(rectangle.x) * scale_x)),
        0, int(encoder^.physical_extent.x))
    top := clamp(int(math.floor(f64(rectangle.y) * scale_y)),
        0, int(encoder^.physical_extent.y))
    right := clamp(int(math.ceil(f64(rectangle.x + rectangle.width) * scale_x)),
        left, int(encoder^.physical_extent.x))
    bottom := clamp(int(math.ceil(f64(rectangle.y + rectangle.height) * scale_y)),
        top, int(encoder^.physical_extent.y))
    return {i32(left), i32(top), u32(right - left), u32(bottom - top)}
}

// draw_encoder_batch_compatible reports whether one state extends a batch.
draw_encoder_batch_compatible :: proc(
    batch: Draw_Batch, state: Draw_State, scissor: Draw_Scissor) -> bool {
    return batch.pipeline == state.pipeline && batch.texture == state.texture &&
        batch.sampler == state.sampler && batch.scissor == scissor
}

// draw_encoder_prepare reserves one atomic primitive and its compatible batch.
draw_encoder_prepare :: proc(
    encoder: ^Draw_Encoder, vertex_count, index_count: int,
    state: Draw_State) -> (^Draw_Batch, bool) {
    scissor := draw_encoder_physical_scissor(encoder)
    last_is_latest_batch := encoder^.command_count > 0 &&
        encoder^.commands[encoder^.command_count - 1].kind == .Batch &&
        encoder^.commands[encoder^.command_count - 1].index ==
            u32(encoder^.batch_count - 1)
    compatible := encoder^.batch_count > 0 && last_is_latest_batch &&
        draw_encoder_batch_compatible(
            encoder^.batches[encoder^.batch_count - 1], state, scissor)
    needs_batch := !compatible
    if encoder^.vertex_count + vertex_count > len(encoder^.vertices) ||
        encoder^.index_count + index_count > len(encoder^.indices) ||
        (needs_batch && (encoder^.batch_count >= len(encoder^.batches) ||
            encoder^.command_count >= len(encoder^.commands))) {
        encoder^.statistics.primitive_overflows += 1
        return nil, false
    }
    if needs_batch {
        batch := &encoder^.batches[encoder^.batch_count]
        batch^ = {pipeline = state.pipeline, texture = state.texture,
            sampler = state.sampler,
            scissor = scissor, first_index = u32(encoder^.index_count)}
        encoder^.commands[encoder^.command_count] = {
            kind = .Batch, index = u32(encoder^.batch_count)}
        encoder^.batch_count += 1
        encoder^.command_count += 1
        encoder^.statistics.batches = u32(encoder^.batch_count)
        encoder^.statistics.commands = u32(encoder^.command_count)
    }
    return &encoder^.batches[encoder^.batch_count - 1], true
}

// draw_encoder_append_custom_command appends one owner-indexed custom draw marker.
draw_encoder_append_custom_command :: proc(
    encoder: ^Draw_Encoder, kind: Draw_Command_Kind, index: u32) -> bool {
    if encoder == nil || kind == .Batch ||
        encoder^.command_count >= len(encoder^.commands) {
        if encoder != nil {
            encoder^.statistics.command_overflows += 1
        }
        return false
    }
    encoder^.commands[encoder^.command_count] = {kind = kind, index = index}
    encoder^.command_count += 1
    encoder^.statistics.commands = u32(encoder^.command_count)
    return true
}

// draw_encoder_append_stroke atomically appends one complete triangle-list draw.
draw_encoder_append_stroke :: proc(
    encoder: ^Draw_Encoder, vertices: []Stroke_Vertex,
    vertex_uniforms: Stroke_Vertex_Uniforms,
    fragment_uniforms: Stroke_Fragment_Uniforms) -> bool {
    if encoder == nil || len(vertices) == 0 || len(vertices) % 3 != 0 ||
        encoder^.stroke_vertex_count + len(vertices) > len(encoder^.stroke_vertices) ||
        encoder^.stroke_draw_count >= len(encoder^.stroke_draws) ||
        encoder^.command_count >= len(encoder^.commands) {
        if encoder != nil {encoder^.statistics.stroke_overflows += 1}
        return false
    }
    draw_index := encoder^.stroke_draw_count
    copy(encoder^.stroke_vertices[encoder^.stroke_vertex_count:], vertices)
    encoder^.stroke_draws[draw_index] = {
        first_vertex = u32(encoder^.stroke_vertex_count),
        vertex_count = u32(len(vertices)),
        scissor = draw_encoder_physical_scissor(encoder),
        vertex_uniforms = vertex_uniforms,
        fragment_uniforms = fragment_uniforms,
    }
    encoder^.commands[encoder^.command_count] = {
        kind = .Tool, index = u32(draw_index)}
    encoder^.stroke_vertex_count += len(vertices)
    encoder^.stroke_draw_count += 1
    encoder^.command_count += 1
    encoder^.statistics.stroke_vertices = u32(encoder^.stroke_vertex_count)
    encoder^.statistics.stroke_draws = u32(encoder^.stroke_draw_count)
    encoder^.statistics.commands = u32(encoder^.command_count)
    return true
}

// draw_encoder_dust_color converts one normalized instance tint to RGBA8.
draw_encoder_dust_color :: #force_inline proc(
    instance: Dust_Instance) -> color.Color_RGBA8 {
    return {
        u8(clamp(instance.color[0] * 255, 0, 255)),
        u8(clamp(instance.color[1] * 255, 0, 255)),
        u8(clamp(instance.color[2] * 255, 0, 255)),
        u8(clamp(instance.color[3] * 255, 0, 255)),
    }
}

// draw_encoder_expand_dust writes one atlas-selected textured quad.
draw_encoder_expand_dust :: proc(
    destination: []Draw_Vertex, instance: Dust_Instance) {
    center_x, center_y := instance.center_diameter[0], instance.center_diameter[1]
    radius := instance.center_diameter[2] * 0.5
    variant := clamp(int(instance.sprite_index), 0,
        DUST_ATLAS_COLUMNS * DUST_ATLAS_ROWS - 1)
    tile_x := variant % DUST_ATLAS_COLUMNS
    tile_y := variant / DUST_ATLAS_COLUMNS
    unit_u := 1 / f32(DUST_ATLAS_COLUMNS)
    unit_v := 1 / f32(DUST_ATLAS_ROWS)
    left, right := f32(tile_x) * unit_u, f32(tile_x + 1) * unit_u
    top, bottom := f32(tile_y) * unit_v, f32(tile_y + 1) * unit_v
    tint := draw_encoder_dust_color(instance)
    destination[0] = {{center_x - radius, center_y - radius}, {left, top}, tint, {}}
    destination[1] = {{center_x - radius, center_y + radius}, {left, bottom}, tint, {}}
    destination[2] = {{center_x + radius, center_y + radius}, {right, bottom}, tint, {}}
    destination[3] = destination[0]
    destination[4] = destination[2]
    destination[5] = {{center_x + radius, center_y - radius}, {right, top}, tint, {}}
}

// draw_encoder_finish_dust publishes shared command statistics after admission.
draw_encoder_finish_dust :: proc(
    encoder: ^Draw_Encoder, count: int) -> bool {
    encoder^.command_count += 1
    encoder^.statistics.commands = u32(encoder^.command_count)
    encoder^.statistics.dust_instances = u32(count)
    encoder^.statistics.dust_draws += 1
    encoder^.statistics.dust_expanded_vertices =
        u32(encoder^.dust_expanded_vertex_count)
    return true
}

// draw_encoder_commit_instanced_dust admits one instance-stream command.
draw_encoder_commit_instanced_dust :: proc(
    encoder: ^Draw_Encoder, count: int, texture: rawptr) -> bool {
    if encoder^.dust_draw_count >= len(encoder^.dust_draws) {
        return false
    }
    draw_index := encoder^.dust_draw_count
    encoder^.dust_draws[draw_index] = {first = 0, count = u32(count),
        texture = texture, scissor = draw_encoder_physical_scissor(encoder),
        viewport_extent = {encoder^.logical_extent.x,
            encoder^.logical_extent.y}}
    encoder^.commands[encoder^.command_count] = {
        kind = .Dust_Instanced, index = u32(draw_index)}
    encoder^.dust_instance_count = count
    encoder^.dust_draw_count += 1
    return true
}

// draw_encoder_commit_expanded_dust admits one CPU-expanded dust command.
draw_encoder_commit_expanded_dust :: proc(
    encoder: ^Draw_Encoder, count: int, texture: rawptr) -> bool {
    vertex_count := count * DUST_EXPANDED_VERTICES_PER_INSTANCE
    if vertex_count > len(encoder^.dust_expanded_vertices) ||
        encoder^.dust_expanded_draw_count >= len(encoder^.dust_expanded_draws) {
        encoder^.statistics.dust_overflows += 1
        return false
    }
    for index in 0..<count {
        first := index * DUST_EXPANDED_VERTICES_PER_INSTANCE
        draw_encoder_expand_dust(encoder^.dust_expanded_vertices[
            first:first + DUST_EXPANDED_VERTICES_PER_INSTANCE],
            encoder^.dust_instances[index])
    }
    draw_index := encoder^.dust_expanded_draw_count
    encoder^.dust_expanded_draws[draw_index] = {first = 0,
        count = u32(vertex_count), texture = texture,
        scissor = draw_encoder_physical_scissor(encoder)}
    encoder^.commands[encoder^.command_count] = {
        kind = .Dust_Expanded, index = u32(draw_index)}
    encoder^.dust_expanded_vertex_count = vertex_count
    encoder^.dust_expanded_draw_count += 1
    return true
}

// draw_encoder_commit_dust atomically appends one full prepared dust prefix.
draw_encoder_commit_dust :: proc(
    encoder: ^Draw_Encoder, count: int, texture: rawptr) -> bool {
    if encoder == nil || count < 0 || count > len(encoder^.dust_instances) ||
        texture == nil || encoder^.command_count >= len(encoder^.commands) {
        if encoder != nil {
            encoder^.statistics.dust_overflows += 1
        }
        return false
    }
    if count == 0 {
        return true
    }
    admitted := false
    if encoder^.dust_instancing_enabled {
        admitted = draw_encoder_commit_instanced_dust(encoder, count, texture)
    } else {
        admitted = draw_encoder_commit_expanded_dust(encoder, count, texture)
    }
    if !admitted {return false}
    return draw_encoder_finish_dust(encoder, count)
}

// draw_encoder_commit appends one complete topology or rejects it unchanged.
draw_encoder_commit :: proc(
    encoder: ^Draw_Encoder, positions: []geometry.Vector2,
    relative_indices: []u32, draw_color: color.Color_RGBA8,
    state: Draw_State) -> bool {
    batch, ready := draw_encoder_prepare(
        encoder, len(positions), len(relative_indices), state)
    if !ready {
        return false
    }
    base_vertex := u32(encoder^.vertex_count)
    for position, offset in positions {
        encoder^.vertices[encoder^.vertex_count + offset] = {
            position = position, color = draw_color}
    }
    for relative_index, offset in relative_indices {
        encoder^.indices[encoder^.index_count + offset] = base_vertex + relative_index
    }
    encoder^.vertex_count += len(positions)
    encoder^.index_count += len(relative_indices)
    batch^.index_count += u32(len(relative_indices))
    encoder^.statistics.vertices = u32(encoder^.vertex_count)
    encoder^.statistics.indices = u32(encoder^.index_count)
    return true
}

// draw_encoder_commit_textured appends one textured topology with explicit UVs.
draw_encoder_commit_textured :: proc(
    encoder: ^Draw_Encoder, vertices: Draw_Textured_Vertices,
    relative_indices: []u32, draw_color: color.Color_RGBA8,
    binding: Draw_Texture_Binding) -> bool {
    if binding.texture == nil || len(vertices.positions) != len(vertices.texcoords) {
        return false
    }
    batch, ready := draw_encoder_prepare(encoder, len(vertices.positions),
        len(relative_indices), {.Textured, binding.texture, binding.sampler})
    if !ready {
        return false
    }
    base_vertex := u32(encoder^.vertex_count)
    for position, offset in vertices.positions {
        encoder^.vertices[encoder^.vertex_count + offset] = {
            position = position, texcoord = vertices.texcoords[offset],
            color = draw_color}
    }
    for relative_index, offset in relative_indices {
        encoder^.indices[encoder^.index_count + offset] = base_vertex + relative_index
    }
    encoder^.vertex_count += len(vertices.positions)
    encoder^.index_count += len(relative_indices)
    batch^.index_count += u32(len(relative_indices))
    encoder^.statistics.vertices = u32(encoder^.vertex_count)
    encoder^.statistics.indices = u32(encoder^.index_count)
    return true
}

// draw_encoder_triangle appends one atomic colored triangle.
draw_encoder_triangle :: proc(
    encoder: ^Draw_Encoder,
    first, second, third: geometry.Vector2,
    draw_color: color.Color_RGBA8) -> bool {
    positions := [3]geometry.Vector2{first, second, third}
    relative_indices := [3]u32{0, 1, 2}
    return draw_encoder_commit(encoder, positions[:], relative_indices[:],
        draw_color, {pipeline = .Colored})
}

// draw_encoder_rectangle appends one atomic colored rectangle.
draw_encoder_rectangle :: proc(
    encoder: ^Draw_Encoder,
    rectangle: geometry.Rectangle,
    draw_color: color.Color_RGBA8) -> bool {
    if rectangle.width <= 0 || rectangle.height <= 0 {return false}
    positions := [4]geometry.Vector2{
        {rectangle.x, rectangle.y},
        {rectangle.x + rectangle.width, rectangle.y},
        {rectangle.x + rectangle.width, rectangle.y + rectangle.height},
        {rectangle.x, rectangle.y + rectangle.height},
    }
    relative_indices := [6]u32{0, 1, 2, 0, 2, 3}
    return draw_encoder_commit(encoder, positions[:], relative_indices[:],
        draw_color, {pipeline = .Colored})
}

// draw_encoder_rectangle_outline appends one atomic inset rectangle border.
draw_encoder_rectangle_outline :: proc(
    encoder: ^Draw_Encoder, rectangle: geometry.Rectangle, thickness: f32,
    draw_color: color.Color_RGBA8) -> bool {
    if rectangle.width <= 0 || rectangle.height <= 0 || thickness <= 0 {return false}
    inset := min(thickness, min(rectangle.width, rectangle.height) * 0.5)
    left, top := rectangle.x, rectangle.y
    right, bottom := left + rectangle.width, top + rectangle.height
    positions := [8]geometry.Vector2{{left, top}, {right, top}, {right, bottom},
        {left, bottom}, {left + inset, top + inset}, {right - inset, top + inset},
        {right - inset, bottom - inset}, {left + inset, bottom - inset}}
    indices := [24]u32{0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5,
        2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7}
    return draw_encoder_commit(encoder, positions[:], indices[:],
        draw_color, {pipeline = .Colored})
}

// draw_encoder_line appends one atomic thick line with square ends.
draw_encoder_line :: proc(
    encoder: ^Draw_Encoder, first, second: geometry.Vector2,
    width: f32, draw_color: color.Color_RGBA8) -> bool {
    delta := second - first
    length := f32(math.sqrt(f64(delta.x * delta.x + delta.y * delta.y)))
    if length <= 0 || width <= 0 {return false}
    half_width := width * 0.5
    along := delta / length * half_width
    normal := geometry.Vector2{-along.y, along.x}
    positions := [4]geometry.Vector2{
        first - along - normal, second + along - normal,
        second + along + normal, first - along + normal,
    }
    relative_indices := [6]u32{0, 1, 2, 0, 2, 3}
    return draw_encoder_commit(encoder, positions[:], relative_indices[:],
        draw_color, {pipeline = .Colored})
}

// draw_polyline_finite_point reports whether one projected point is usable.
draw_polyline_finite_point :: #force_inline proc(point: geometry.Vector2) -> bool {
    return !math.is_nan(point.x) && !math.is_inf(point.x) &&
        !math.is_nan(point.y) && !math.is_inf(point.y)
}

// draw_polyline_distance_squared returns squared projected separation.
draw_polyline_distance_squared :: #force_inline proc(
    first, second: geometry.Vector2) -> f32 {
    delta := second - first
    return delta.x * delta.x + delta.y * delta.y
}

// draw_polyline_unit returns the direction of one validated edge.
draw_polyline_unit :: #force_inline proc(
    first, second: geometry.Vector2) -> geometry.Vector2 {
    delta := second - first
    length := f32(math.sqrt(f64(delta.x * delta.x + delta.y * delta.y)))
    return delta / length
}

// draw_polyline_kind_at reads an optional parallel semantic-kind stream.
draw_polyline_kind_at :: #force_inline proc(
    kinds: []Draw_Polyline_Point_Kind, index: int) -> Draw_Polyline_Point_Kind {
    if len(kinds) == 0 {
        return .Ordinary
    }
    return kinds[index]
}

// draw_polyline_next_group compacts one consecutive projected-point cluster.
draw_polyline_next_group :: proc(
    points: []geometry.Vector2, kinds: []Draw_Polyline_Point_Kind,
    raw_start, raw_end: int) -> (Draw_Polyline_Group, bool) {
    if raw_start >= raw_end {
        return {}, false
    }
    group := Draw_Polyline_Group{point = points[raw_start],
        kind = draw_polyline_kind_at(kinds, raw_start), next = raw_start + 1}
    epsilon_squared := f32(DRAW_POLYLINE_POINT_EPSILON * DRAW_POLYLINE_POINT_EPSILON)
    for group.next < raw_end && draw_polyline_distance_squared(
        group.point, points[group.next]) <= epsilon_squared {
        if draw_polyline_kind_at(kinds, group.next) == .Cusp {
            group.kind = .Cusp
        }
        group.next += 1
    }
    return group, true
}

// draw_polyline_join classifies one ordinary or semantic interior point.
draw_polyline_join :: proc(
    previous, current, next: geometry.Vector2,
    kind: Draw_Polyline_Point_Kind, miter_limit: f32) -> Draw_Polyline_Join {
    if kind == .Cusp {return .Cusp}
    incoming := draw_polyline_unit(previous, current)
    outgoing := draw_polyline_unit(current, next)
    normal_sum := geometry.Vector2{-incoming.y - outgoing.y,
        incoming.x + outgoing.x}
    length_squared := draw_polyline_distance_squared({}, normal_sum)
    if length_squared <= DRAW_POLYLINE_MITER_EPSILON *
        DRAW_POLYLINE_MITER_EPSILON {return .Bevel}
    bisector := normal_sum / f32(math.sqrt(f64(length_squared)))
    outgoing_normal := geometry.Vector2{-outgoing.y, outgoing.x}
    denominator := math.abs(bisector.x * outgoing_normal.x +
        bisector.y * outgoing_normal.y)
    if denominator <= DRAW_POLYLINE_MITER_EPSILON || 1 / denominator > miter_limit {
        return .Bevel
    }
    return .Miter
}

// draw_polyline_join_cost returns exact local geometry counts.
draw_polyline_join_cost :: #force_inline proc(
    join: Draw_Polyline_Join) -> (vertices, indices: int) {
    switch join {
    case .Miter:
        return 2, 0
    case .Bevel:
        return 4, 3
    case .Cusp:
        return DRAW_POLYLINE_FAN_SEGMENTS + 6, DRAW_POLYLINE_FAN_SEGMENTS * 3
    }
    return
}

// draw_polyline_endpoint_cost returns exact pair and optional fan counts.
draw_polyline_endpoint_cost :: #force_inline proc(
    cap: Draw_Polyline_Cap) -> (vertices, indices: int) {
    if cap == .Round {
        return DRAW_POLYLINE_FAN_SEGMENTS + 4, DRAW_POLYLINE_FAN_SEGMENTS * 3
    }
    return 2, 0
}

// draw_polyline_compact_summary validates and counts retained points.
draw_polyline_compact_summary :: proc(
    points: []geometry.Vector2,
    kinds: []Draw_Polyline_Point_Kind,
    topology: Draw_Polyline_Topology) -> (Draw_Polyline_Summary, bool) {

    if len(points) < 2 || (len(kinds) != 0 && len(kinds) != len(points)) {
        return {}, false
    }
    for point in points {
        if !draw_polyline_finite_point(point) {
            return {}, false
        }
    }
    first, _ := draw_polyline_next_group(points, kinds, 0, len(points))
    summary := Draw_Polyline_Summary{raw_end = len(points), first_kind = first.kind}
    cursor, last_start := 0, 0
    last := first
    for cursor < len(points) {
        last_start = cursor
        last, _ = draw_polyline_next_group(points, kinds, cursor, len(points))
        summary.group_count += 1
        cursor = last.next
    }
    epsilon_squared := f32(DRAW_POLYLINE_POINT_EPSILON * DRAW_POLYLINE_POINT_EPSILON)
    if topology == .Closed && summary.group_count > 1 &&
        draw_polyline_distance_squared(first.point, last.point) <= epsilon_squared {
        summary.raw_end = last_start
        summary.group_count -= 1
        if last.kind == .Cusp {summary.first_kind = .Cusp}
    }
    minimum := 2
    if topology == .Closed {minimum = 3}
    return summary, summary.group_count >= minimum
}

// draw_polyline_last_group returns the final compacted point in a range.
draw_polyline_last_group :: proc(
    points: []geometry.Vector2, kinds: []Draw_Polyline_Point_Kind,
    raw_end: int) -> Draw_Polyline_Group {
    cursor := 0
    group: Draw_Polyline_Group
    for cursor < raw_end {
        group, _ = draw_polyline_next_group(points, kinds, cursor, raw_end)
        cursor = group.next
    }
    return group
}

// draw_polyline_count_join adds one classified node to an exact summary.
draw_polyline_count_join :: #force_inline proc(
    summary: ^Draw_Polyline_Summary, previous, current, next: Draw_Polyline_Group,
    miter_limit: f32) {
    join := draw_polyline_join(previous.point, current.point,
        next.point, current.kind, miter_limit)
    vertices, indices := draw_polyline_join_cost(join)
    summary^.vertices += vertices
    summary^.indices += indices
}

// draw_polyline_valid_style rejects nonfinite or geometrically invalid policy.
draw_polyline_valid_style :: #force_inline proc(style: Draw_Polyline_Style) -> bool {
    return !math.is_nan(style.width) && !math.is_inf(style.width) &&
        !math.is_nan(style.miter_limit) && !math.is_inf(style.miter_limit) &&
        style.width > 0 && style.miter_limit > 1
}

// draw_polyline_preflight computes exact topology cost before encoder mutation.
draw_polyline_preflight :: proc(
    points: []geometry.Vector2, kinds: []Draw_Polyline_Point_Kind,
    style: Draw_Polyline_Style) -> (Draw_Polyline_Summary, bool) {
    summary, valid := draw_polyline_compact_summary(points, kinds, style.topology)
    if !valid || !draw_polyline_valid_style(style) {
        return {}, false
    }
    first, _ := draw_polyline_next_group(points, kinds, 0, summary.raw_end)
    first.kind = summary.first_kind
    second, _ := draw_polyline_next_group(points, kinds, first.next, summary.raw_end)
    previous, current := first, second
    cursor := second.next
    for _ in 1..<summary.group_count - 1 {
        next, _ := draw_polyline_next_group(points, kinds, cursor, summary.raw_end)
        draw_polyline_count_join(&summary, previous, current, next, style.miter_limit)
        previous, current = current, next
        cursor = next.next
    }
    if style.topology == .Open {
        start_vertices, start_indices := draw_polyline_endpoint_cost(style.start_cap)
        finish_vertices, finish_indices := draw_polyline_endpoint_cost(style.finish_cap)
        summary.vertices += start_vertices + finish_vertices
        summary.indices += start_indices + finish_indices
        summary.indices += (summary.group_count - 1) * 6
    } else {
        draw_polyline_count_join(&summary, previous, current, first, style.miter_limit)
        draw_polyline_count_join(&summary, current, first, second, style.miter_limit)
        summary.indices += summary.group_count * 6
    }
    return summary, true
}

// draw_polyline_emit_vertex appends one preflighted relative vertex.
draw_polyline_emit_vertex :: #force_inline proc(
    builder: ^Draw_Polyline_Builder, point: geometry.Vector2) -> u32 {
    relative := u32(builder^.vertex_count)
    destination := int(builder^.base_vertex) + builder^.vertex_count
    builder^.encoder^.vertices[destination] = {position = point, color = builder^.color}
    builder^.vertex_count += 1
    return relative
}

// draw_polyline_emit_triangle appends one preflighted relative triangle.
draw_polyline_emit_triangle :: #force_inline proc(
    builder: ^Draw_Polyline_Builder, first, second, third: u32) {
    destination := builder^.encoder^.index_count + builder^.index_count
    builder^.encoder^.indices[destination] = builder^.base_vertex + first
    builder^.encoder^.indices[destination + 1] = builder^.base_vertex + second
    builder^.encoder^.indices[destination + 2] = builder^.base_vertex + third
    builder^.index_count += 3
}

// draw_polyline_emit_pair appends one left/right stroke boundary pair.
draw_polyline_emit_pair :: #force_inline proc(
    builder: ^Draw_Polyline_Builder, point, normal: geometry.Vector2,
    radius: f32) -> Draw_Polyline_Pair {
    return {draw_polyline_emit_vertex(builder, point + normal * radius),
        draw_polyline_emit_vertex(builder, point - normal * radius)}
}

// draw_polyline_emit_body joins two boundary pairs without overlap.
draw_polyline_emit_body :: #force_inline proc(
    builder: ^Draw_Polyline_Builder, first, second: Draw_Polyline_Pair) {
    draw_polyline_emit_triangle(builder, first.left, first.right, second.right)
    draw_polyline_emit_triangle(builder, first.left, second.right, second.left)
}

// draw_polyline_emit_fan appends one outward semicircle without body overlap.
draw_polyline_emit_fan :: proc(
    builder: ^Draw_Polyline_Builder, center, outward: geometry.Vector2, radius: f32) {
    center_index := draw_polyline_emit_vertex(builder, center)
    start_angle := math.atan2(f64(outward.y), f64(outward.x)) - math.PI * 0.5
    previous := draw_polyline_emit_vertex(builder, center + geometry.Vector2{
        radius * f32(math.cos(start_angle)), radius * f32(math.sin(start_angle))})
    for step in 1..=DRAW_POLYLINE_FAN_SEGMENTS {
        angle := start_angle + f64(step) * math.PI / DRAW_POLYLINE_FAN_SEGMENTS
        current := draw_polyline_emit_vertex(builder, center + geometry.Vector2{
            radius * f32(math.cos(angle)), radius * f32(math.sin(angle))})
        draw_polyline_emit_triangle(builder, center_index, previous, current)
        previous = current
    }
}

// draw_polyline_emit_endpoint appends one butt pair and optional round fan.
draw_polyline_emit_endpoint :: proc(
    builder: ^Draw_Polyline_Builder, point, tangent: geometry.Vector2,
    style: Draw_Polyline_Style, start: bool) -> Draw_Polyline_Node {
    radius := style.width * 0.5
    pair := draw_polyline_emit_pair(builder, point, {-tangent.y, tangent.x}, radius)
    cap := style.finish_cap
    if start {cap = style.start_cap}
    if cap == .Round {
        outward := tangent
        if start {outward = -tangent}
        draw_polyline_emit_fan(builder, point, outward, radius)
    }
    return {incoming = pair, outgoing = pair}
}

// draw_polyline_emit_miter appends one shared offset-line intersection pair.
draw_polyline_emit_miter :: proc(
    builder: ^Draw_Polyline_Builder, point, incoming, outgoing: geometry.Vector2,
    radius: f32) -> Draw_Polyline_Node {
    normal_sum := geometry.Vector2{-incoming.y - outgoing.y,
        incoming.x + outgoing.x}
    bisector := normal_sum /
        f32(math.sqrt(f64(draw_polyline_distance_squared({}, normal_sum))))
    outgoing_normal := geometry.Vector2{-outgoing.y, outgoing.x}
    denominator := bisector.x * outgoing_normal.x + bisector.y * outgoing_normal.y
    offset := bisector * (radius / denominator)
    pair := Draw_Polyline_Pair{
        draw_polyline_emit_vertex(builder, point + offset),
        draw_polyline_emit_vertex(builder, point - offset),
    }
    return {incoming = pair, outgoing = pair}
}

// draw_polyline_emit_bevel appends separate outside corners and one filled wedge.
draw_polyline_emit_bevel :: proc(
    builder: ^Draw_Polyline_Builder, point, incoming, outgoing: geometry.Vector2,
    radius: f32) -> Draw_Polyline_Node {
    incoming_normal := geometry.Vector2{-incoming.y, incoming.x}
    outgoing_normal := geometry.Vector2{-outgoing.y, outgoing.x}
    normal_sum := incoming_normal + outgoing_normal
    inside := point
    length_squared := draw_polyline_distance_squared({}, normal_sum)
    if length_squared > DRAW_POLYLINE_MITER_EPSILON * DRAW_POLYLINE_MITER_EPSILON {
        bisector := normal_sum / f32(math.sqrt(f64(length_squared)))
        denominator := bisector.x * outgoing_normal.x + bisector.y * outgoing_normal.y
        if math.abs(denominator) > DRAW_POLYLINE_MITER_EPSILON {
            inside = point + bisector * (radius / denominator)
        }
    }
    turn := incoming.x * outgoing.y - incoming.y * outgoing.x
    if turn >= 0 {
        inside_index := draw_polyline_emit_vertex(builder, inside)
        incoming_outer := draw_polyline_emit_vertex(
            builder, point - incoming_normal * radius)
        outgoing_inside := draw_polyline_emit_vertex(builder, inside)
        outgoing_outer := draw_polyline_emit_vertex(
            builder, point - outgoing_normal * radius)
        draw_polyline_emit_triangle(builder, incoming_outer, inside_index, outgoing_outer)
        return {{inside_index, incoming_outer}, {outgoing_inside, outgoing_outer}}
    }
    incoming_outer := draw_polyline_emit_vertex(builder, point + incoming_normal * radius)
    inside_index := draw_polyline_emit_vertex(builder, point - (inside - point))
    outgoing_outer := draw_polyline_emit_vertex(builder, point + outgoing_normal * radius)
    outgoing_inside := draw_polyline_emit_vertex(builder, point - (inside - point))
    draw_polyline_emit_triangle(builder, incoming_outer, inside_index, outgoing_outer)
    return {{incoming_outer, inside_index}, {outgoing_outer, outgoing_inside}}
}

// draw_polyline_emit_cusp terminates both branches and adds one outward fan.
draw_polyline_emit_cusp :: proc(
    builder: ^Draw_Polyline_Builder, point, incoming, outgoing: geometry.Vector2,
    radius: f32) -> Draw_Polyline_Node {
    incoming_pair := draw_polyline_emit_pair(builder, point,
        {-incoming.y, incoming.x}, radius)
    outgoing_pair := draw_polyline_emit_pair(builder, point,
        {-outgoing.y, outgoing.x}, radius)
    outward := incoming - outgoing
    length_squared := draw_polyline_distance_squared({}, outward)
    if length_squared <= DRAW_POLYLINE_MITER_EPSILON * DRAW_POLYLINE_MITER_EPSILON {
        outward = incoming
    } else {
        outward /= f32(math.sqrt(f64(length_squared)))
    }
    draw_polyline_emit_fan(builder, point, outward, radius)
    return {incoming_pair, outgoing_pair}
}

// draw_polyline_emit_join appends one classified interior topology.
draw_polyline_emit_join :: proc(
    builder: ^Draw_Polyline_Builder, previous, current, next: Draw_Polyline_Group,
    style: Draw_Polyline_Style) -> Draw_Polyline_Node {
    incoming := draw_polyline_unit(previous.point, current.point)
    outgoing := draw_polyline_unit(current.point, next.point)
    switch draw_polyline_join(previous.point, current.point,
        next.point, current.kind, style.miter_limit) {
    case .Miter:
        return draw_polyline_emit_miter(
            builder, current.point, incoming, outgoing, style.width * 0.5)
    case .Bevel:
        return draw_polyline_emit_bevel(
            builder, current.point, incoming, outgoing, style.width * 0.5)
    case .Cusp:
        return draw_polyline_emit_cusp(
            builder, current.point, incoming, outgoing, style.width * 0.5)
    }
    return {}
}

// draw_polyline_finish publishes one fully written preflighted primitive.
draw_polyline_finish :: proc(builder: ^Draw_Polyline_Builder) {
    encoder := builder^.encoder
    encoder^.vertex_count += builder^.vertex_count
    encoder^.index_count += builder^.index_count
    builder^.batch^.index_count += u32(builder^.index_count)
    encoder^.statistics.vertices = u32(encoder^.vertex_count)
    encoder^.statistics.indices = u32(encoder^.index_count)
}

// draw_polyline_emit_open writes one preflighted open stroke.
draw_polyline_emit_open :: proc(
    builder: ^Draw_Polyline_Builder, points: []geometry.Vector2,
    kinds: []Draw_Polyline_Point_Kind, summary: Draw_Polyline_Summary,
    style: Draw_Polyline_Style) {
    first, _ := draw_polyline_next_group(points, kinds, 0, summary.raw_end)
    current, _ := draw_polyline_next_group(points, kinds, first.next, summary.raw_end)
    tangent := draw_polyline_unit(first.point, current.point)
    previous_node := draw_polyline_emit_endpoint(builder, first.point,
        tangent, style, true)
    previous := first
    for _ in 1..<summary.group_count - 1 {
        next, _ := draw_polyline_next_group(points, kinds, current.next, summary.raw_end)
        node := draw_polyline_emit_join(builder, previous, current, next, style)
        draw_polyline_emit_body(builder, previous_node.outgoing, node.incoming)
        previous_node = node
        previous, current = current, next
    }
    tangent = draw_polyline_unit(previous.point, current.point)
    finish := draw_polyline_emit_endpoint(builder, current.point,
        tangent, style, false)
    draw_polyline_emit_body(builder, previous_node.outgoing, finish.incoming)
}

// draw_polyline_emit_closed writes one preflighted wrapped stroke.
draw_polyline_emit_closed :: proc(
    builder: ^Draw_Polyline_Builder, points: []geometry.Vector2,
    kinds: []Draw_Polyline_Point_Kind, summary: Draw_Polyline_Summary,
    style: Draw_Polyline_Style) {
    first, _ := draw_polyline_next_group(points, kinds, 0, summary.raw_end)
    first.kind = summary.first_kind
    second, _ := draw_polyline_next_group(points, kinds, first.next, summary.raw_end)
    last := draw_polyline_last_group(points, kinds, summary.raw_end)
    first_node := draw_polyline_emit_join(builder, last, first, second, style)
    previous, current := first, second
    previous_node := first_node
    for _ in 1..<summary.group_count - 1 {
        next, _ := draw_polyline_next_group(points, kinds, current.next, summary.raw_end)
        node := draw_polyline_emit_join(builder, previous, current, next, style)
        draw_polyline_emit_body(builder, previous_node.outgoing, node.incoming)
        previous_node = node
        previous, current = current, next
    }
    last_node := draw_polyline_emit_join(builder, previous, current, first, style)
    draw_polyline_emit_body(builder, previous_node.outgoing, last_node.incoming)
    draw_polyline_emit_body(builder, last_node.outgoing, first_node.incoming)
}

// draw_encoder_polyline appends one atomic topology-aware colored stroke.
draw_encoder_polyline :: proc(
    encoder: ^Draw_Encoder, points: []geometry.Vector2,
    kinds: []Draw_Polyline_Point_Kind, style: Draw_Polyline_Style) -> bool {
    if encoder == nil {return false}
    summary, valid := draw_polyline_preflight(points, kinds, style)
    if !valid {return false}
    batch, ready := draw_encoder_prepare(encoder, summary.vertices,
        summary.indices, {pipeline = .Colored})
    if !ready {return false}
    builder := Draw_Polyline_Builder{encoder = encoder, batch = batch,
        base_vertex = u32(encoder^.vertex_count), color = style.color}
    if style.topology == .Open {
        draw_polyline_emit_open(&builder, points, kinds, summary, style)
    } else {
        draw_polyline_emit_closed(&builder, points, kinds, summary, style)
    }
    draw_polyline_finish(&builder)
    return builder.vertex_count == summary.vertices &&
        builder.index_count == summary.indices
}

// draw_encoder_circle appends one atomic filled circle.
draw_encoder_circle :: proc(
    encoder: ^Draw_Encoder, center: geometry.Vector2, radius: f32,
    draw_color: color.Color_RGBA8) -> bool {
    if radius <= 0 {
        return false
    }
    positions: [DRAW_CIRCLE_SEGMENTS + 1]geometry.Vector2
    indices: [DRAW_CIRCLE_SEGMENTS * 3]u32
    positions[0] = center
    for index in 0..<DRAW_CIRCLE_SEGMENTS {
        angle := f64(index) * 2 * math.PI / DRAW_CIRCLE_SEGMENTS
        positions[index + 1] = center + geometry.Vector2{
            radius * f32(math.cos(angle)), radius * f32(math.sin(angle))}
        next := (index + 1) % DRAW_CIRCLE_SEGMENTS
        indices[index * 3] = 0
        indices[index * 3 + 1] = u32(index + 1)
        indices[index * 3 + 2] = u32(next + 1)
    }
    return draw_encoder_commit(encoder, positions[:], indices[:],
        draw_color, {pipeline = .Colored})
}

// draw_encoder_ring appends one atomic ring between positive ordered radii.
draw_encoder_ring :: proc(
    encoder: ^Draw_Encoder, center: geometry.Vector2,
    inner_radius, outer_radius: f32, draw_color: color.Color_RGBA8) -> bool {
    if inner_radius < 0 || outer_radius <= inner_radius {
        return false
    }
    positions: [DRAW_CIRCLE_SEGMENTS * 2]geometry.Vector2
    indices: [DRAW_CIRCLE_SEGMENTS * 6]u32
    for index in 0..<DRAW_CIRCLE_SEGMENTS {
        angle := f64(index) * 2 * math.PI / DRAW_CIRCLE_SEGMENTS
        direction := geometry.Vector2{f32(math.cos(angle)), f32(math.sin(angle))}
        positions[index * 2] = center + direction * inner_radius
        positions[index * 2 + 1] = center + direction * outer_radius
        next := (index + 1) % DRAW_CIRCLE_SEGMENTS
        base := index * 6
        indices[base] = u32(index * 2)
        indices[base + 1] = u32(index * 2 + 1)
        indices[base + 2] = u32(next * 2 + 1)
        indices[base + 3] = u32(index * 2)
        indices[base + 4] = u32(next * 2 + 1)
        indices[base + 5] = u32(next * 2)
    }
    return draw_encoder_commit(encoder, positions[:], indices[:],
        draw_color, {pipeline = .Colored})
}

// draw_encoder_texture_quad appends one atomic tinted textured rectangle.
draw_encoder_texture_quad :: proc(
    encoder: ^Draw_Encoder, rectangle: geometry.Rectangle,
    uv_rectangle: geometry.Rectangle, tint: color.Color_RGBA8,
    binding: Draw_Texture_Binding) -> bool {
    if rectangle.width <= 0 || rectangle.height <= 0 {
        return false
    }
    positions := [4]geometry.Vector2{{rectangle.x, rectangle.y},
        {rectangle.x + rectangle.width, rectangle.y},
        {rectangle.x + rectangle.width, rectangle.y + rectangle.height},
        {rectangle.x, rectangle.y + rectangle.height}}
    texcoords := [4]geometry.Vector2{{uv_rectangle.x, uv_rectangle.y},
        {uv_rectangle.x + uv_rectangle.width, uv_rectangle.y},
        {uv_rectangle.x + uv_rectangle.width, uv_rectangle.y + uv_rectangle.height},
        {uv_rectangle.x, uv_rectangle.y + uv_rectangle.height}}
    indices := [6]u32{0, 1, 2, 0, 2, 3}
    return draw_encoder_commit_textured(encoder, {positions[:], texcoords[:]},
        indices[:], tint, binding)
}
