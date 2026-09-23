package native

import "core:math"

import color "../../core/color"
import geometry "../../core/geometry"

DRAW_SCISSOR_STACK_CAPACITY :: 16
DRAW_CIRCLE_SEGMENTS :: 32

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

// Draw_Vertex is the fixed CPU/GPU record shared by both 2D pipelines.
Draw_Vertex :: struct {
    position: geometry.Vector2,
    texcoord: geometry.Vector2,
    color:    color.Color_RGBA8,
    padding:  [4]u8,
}

#assert(size_of(Draw_Vertex) == 24)

// Draw_Scissor stores one physical-pixel top-left clipping rectangle.
Draw_Scissor :: struct {
    x:      i32,
    y:      i32,
    width:  u32,
    height: u32,
}

// Draw_Batch identifies one contiguous compatible indexed draw interval.
Draw_Batch :: struct {
    pipeline:    Draw_Pipeline,
    texture:     rawptr,
    sampler:     Draw_Sampler,
    scissor:     Draw_Scissor,
    first_index: u32,
    index_count: u32,
}

// Draw_State groups native batch compatibility without exposing SDL handles.
Draw_State :: struct {
    pipeline: Draw_Pipeline,
    texture:  rawptr,
    sampler:  Draw_Sampler,
}

// Draw_Encoder_Statistics records bounded work and rejected primitives.
Draw_Encoder_Statistics :: struct {
    vertices:          u32,
    indices:           u32,
    batches:           u32,
    primitive_overflows: u32,
    scissor_overflows: u32,
}

// Draw_Storage borrows fixed-capacity frame buffers from the display owner.
Draw_Storage :: struct {
    vertices: []Draw_Vertex,
    indices:  []u32,
    batches:  []Draw_Batch,
}

// Draw_Encoder stores one frame in caller-owned fixed-capacity slices.
Draw_Encoder :: struct {
    vertices:        []Draw_Vertex,
    indices:         []u32,
    batches:         []Draw_Batch,
    vertex_count:    int,
    index_count:     int,
    batch_count:     int,
    logical_extent:  geometry.Vector2,
    physical_extent: [2]u32,
    scissors:        [DRAW_SCISSOR_STACK_CAPACITY]geometry.Rectangle,
    scissor_count:   int,
    statistics:      Draw_Encoder_Statistics,
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
        logical_extent = logical_extent,
        physical_extent = physical_extent,
        scissor_count = 1,
    }
    encoder^.scissors[0] = {0, 0, logical_extent.x, logical_extent.y}
    return true
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
    compatible := encoder^.batch_count > 0 && draw_encoder_batch_compatible(
        encoder^.batches[encoder^.batch_count - 1], state, scissor)
    needs_batch := !compatible
    if encoder^.vertex_count + vertex_count > len(encoder^.vertices) ||
        encoder^.index_count + index_count > len(encoder^.indices) ||
        (needs_batch && encoder^.batch_count >= len(encoder^.batches)) {
        encoder^.statistics.primitive_overflows += 1
        return nil, false
    }
    if needs_batch {
        batch := &encoder^.batches[encoder^.batch_count]
        batch^ = {pipeline = state.pipeline, texture = state.texture,
            sampler = state.sampler,
            scissor = scissor, first_index = u32(encoder^.index_count)}
        encoder^.batch_count += 1
        encoder^.statistics.batches = u32(encoder^.batch_count)
    }
    return &encoder^.batches[encoder^.batch_count - 1], true
}

// draw_encoder_commit appends one complete topology or rejects it unchanged.
draw_encoder_commit :: proc(
    encoder: ^Draw_Encoder, positions: []geometry.Vector2,
    relative_indices: []u32, draw_color: color.Color_RGBA8,
    state: Draw_State) -> bool {
    batch, ready := draw_encoder_prepare(
        encoder, len(positions), len(relative_indices), state)
    if !ready {return false}
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
    encoder: ^Draw_Encoder, positions, texcoords: []geometry.Vector2,
    relative_indices: []u32, draw_color: color.Color_RGBA8,
    texture: rawptr, sampler: Draw_Sampler) -> bool {
    if texture == nil || len(positions) != len(texcoords) {return false}
    batch, ready := draw_encoder_prepare(encoder, len(positions),
        len(relative_indices), {.Textured, texture, sampler})
    if !ready {return false}
    base_vertex := u32(encoder^.vertex_count)
    for position, offset in positions {
        encoder^.vertices[encoder^.vertex_count + offset] = {
            position = position, texcoord = texcoords[offset], color = draw_color}
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

// draw_encoder_circle appends one atomic filled circle.
draw_encoder_circle :: proc(
    encoder: ^Draw_Encoder, center: geometry.Vector2, radius: f32,
    draw_color: color.Color_RGBA8) -> bool {
    if radius <= 0 {return false}
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
    if inner_radius < 0 || outer_radius <= inner_radius {return false}
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
    texture: rawptr, sampler: Draw_Sampler = .Nearest) -> bool {
    if rectangle.width <= 0 || rectangle.height <= 0 {return false}
    positions := [4]geometry.Vector2{{rectangle.x, rectangle.y},
        {rectangle.x + rectangle.width, rectangle.y},
        {rectangle.x + rectangle.width, rectangle.y + rectangle.height},
        {rectangle.x, rectangle.y + rectangle.height}}
    texcoords := [4]geometry.Vector2{{uv_rectangle.x, uv_rectangle.y},
        {uv_rectangle.x + uv_rectangle.width, uv_rectangle.y},
        {uv_rectangle.x + uv_rectangle.width, uv_rectangle.y + uv_rectangle.height},
        {uv_rectangle.x, uv_rectangle.y + uv_rectangle.height}}
    indices := [6]u32{0, 1, 2, 0, 2, 3}
    return draw_encoder_commit_textured(encoder, positions[:], texcoords[:],
        indices[:], tint, texture, sampler)
}
