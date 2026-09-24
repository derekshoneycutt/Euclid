#+test
package native

import "core:testing"

import color "../../core/color"
import geometry "../../core/geometry"

// Verify adjacent colored rectangles share one ordered indexed batch.
@(test)
draw_encoder_test_rectangles_merge_adjacent_batch :: proc(t: ^testing.T) {
    vertices: [8]Draw_Vertex
    indices: [12]u32
    batches: [2]Draw_Batch
    commands: [2]Draw_Command
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))
    draw_color := color.Color_RGBA8{10, 20, 30, 40}
    testing.expect(t, draw_encoder_rectangle(&encoder, {1, 2, 3, 4}, draw_color))
    testing.expect(t, draw_encoder_rectangle(&encoder, {10, 20, 30, 40}, draw_color))
    testing.expect_value(t, encoder.vertex_count, 8)
    testing.expect_value(t, encoder.index_count, 12)
    testing.expect_value(t, encoder.batch_count, 1)
    testing.expect_value(t, batches[0].index_count, u32(12))
    testing.expect_value(t, indices,
        [12]u32{0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7})
    testing.expect_value(t, vertices[0].position, geometry.Vector2{1, 2})
    testing.expect_value(t, vertices[2].position, geometry.Vector2{4, 6})
    testing.expect_value(t, vertices[0].color, draw_color)
}

// Verify a changed clip starts a batch and rounds outward in physical pixels.
@(test)
draw_encoder_test_scissor_intersects_and_scales_outward :: proc(t: ^testing.T) {
    vertices: [6]Draw_Vertex
    indices: [6]u32
    batches: [2]Draw_Batch
    commands: [2]Draw_Command
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {150, 200}))
    draw_color := color.WHITE
    testing.expect(t, draw_encoder_triangle(
        &encoder, {0, 0}, {1, 0}, {0, 1}, draw_color))
    testing.expect(t, draw_encoder_push_scissor(&encoder, {10.2, 20.2, 40.1, 30.1}))
    testing.expect(t, draw_encoder_triangle(
        &encoder, {2, 2}, {3, 2}, {2, 3}, draw_color))
    testing.expect_value(t, encoder.batch_count, 2)
    testing.expect_value(t, batches[0].scissor, Draw_Scissor{0, 0, 150, 200})
    testing.expect_value(t, batches[1].scissor, Draw_Scissor{15, 40, 61, 61})
    testing.expect(t, draw_encoder_pop_scissor(&encoder))
}

// Verify rejected geometry leaves every publication count unchanged.
@(test)
draw_encoder_test_overflow_is_atomic :: proc(t: ^testing.T) {
    vertices: [3]Draw_Vertex
    indices: [5]u32
    batches: [1]Draw_Batch
    commands: [1]Draw_Command
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))
    testing.expect(t, !draw_encoder_rectangle(
        &encoder, {1, 2, 3, 4}, color.WHITE))
    testing.expect_value(t, encoder.vertex_count, 0)
    testing.expect_value(t, encoder.index_count, 0)
    testing.expect_value(t, encoder.batch_count, 0)
    testing.expect_value(t, encoder.statistics.primitive_overflows, u32(1))
}

// Verify invalid frame extents and scissor stack misuse are rejected observably.
@(test)
draw_encoder_test_rejects_invalid_frame_and_scissor_misuse :: proc(t: ^testing.T) {
    vertices: [3]Draw_Vertex
    indices: [3]u32
    batches: [1]Draw_Batch
    commands: [1]Draw_Command
    encoder: Draw_Encoder
    storage := Draw_Storage{vertices[:], indices[:], batches[:], commands[:], nil}
    testing.expect(t, !draw_encoder_begin(
        &encoder, storage, {0, 100}, {100, 100}))
    testing.expect(t, draw_encoder_begin(
        &encoder, storage, {100, 100}, {100, 100}))
    testing.expect(t, !draw_encoder_pop_scissor(&encoder))
    for _ in 1..<DRAW_SCISSOR_STACK_CAPACITY {
        testing.expect(t, draw_encoder_push_scissor(&encoder, {0, 0, 100, 100}))
    }
    testing.expect(t, !draw_encoder_push_scissor(&encoder, {0, 0, 100, 100}))
    testing.expect_value(t, encoder.statistics.scissor_overflows, u32(2))
}

// Verify thick and curved colored primitives publish their fixed topology atomically.
@(test)
draw_encoder_test_line_circle_and_ring_topology :: proc(t: ^testing.T) {
    vertices: [4 + DRAW_CIRCLE_SEGMENTS * 3 + 1]Draw_Vertex
    indices: [6 + DRAW_CIRCLE_SEGMENTS * 9]u32
    batches: [1]Draw_Batch
    commands: [1]Draw_Command
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))
    testing.expect(t, draw_encoder_line(&encoder, {10, 10}, {20, 10}, 4, color.WHITE))
    testing.expect_value(t, vertices[0].position, geometry.Vector2{8, 8})
    testing.expect_value(t, vertices[2].position, geometry.Vector2{22, 12})
    testing.expect(t, draw_encoder_circle(&encoder, {30, 30}, 5, color.WHITE))
    testing.expect(t, draw_encoder_ring(&encoder, {50, 50}, 3, 5, color.WHITE))
    testing.expect_value(t, encoder.vertex_count, len(vertices))
    testing.expect_value(t, encoder.index_count, len(indices))
    testing.expect_value(t, encoder.batch_count, 1)
}

// Verify textured quads preserve UVs and split ordered pipeline batches.
@(test)
draw_encoder_test_textured_quad_records_state_and_uvs :: proc(t: ^testing.T) {
    vertices: [8]Draw_Vertex
    indices: [12]u32
    batches: [2]Draw_Batch
    commands: [2]Draw_Command
    encoder: Draw_Encoder
    texture := rawptr(uintptr(1))
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))
    testing.expect(t, draw_encoder_rectangle(&encoder, {0, 0, 5, 5}, color.WHITE))
    testing.expect(t, draw_encoder_texture_quad(&encoder, {10, 20, 30, 40},
        {0.25, 0.5, 0.5, 0.25}, color.WHITE, texture, .Linear))
    testing.expect_value(t, encoder.batch_count, 2)
    testing.expect_value(t, batches[1].pipeline, Draw_Pipeline.Textured)
    testing.expect_value(t, batches[1].texture, texture)
    testing.expect_value(t, batches[1].sampler, Draw_Sampler.Linear)
    testing.expect_value(t, vertices[4].texcoord, geometry.Vector2{0.25, 0.5})
    testing.expect_value(t, vertices[6].texcoord, geometry.Vector2{0.75, 0.75})
}

// Verify successful frame observations accumulate totals and capacity high waters.
@(test)
sdl_draw_test_statistics_accumulate_and_track_high_water :: proc(t: ^testing.T) {
    vertices: [8]Draw_Vertex
    indices: [12]u32
    batches: [2]Draw_Batch
    commands: [2]Draw_Command
    encoder: Draw_Encoder
    runtime: Sdl_Draw_Runtime
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))
    testing.expect(t, draw_encoder_rectangle(
        &encoder, {1, 2, 3, 4}, color.WHITE))
    encoder.dust_instance_count = 3
    encoder.dust_draw_count = 1
    encoder.statistics.primitive_overflows = 2
    encoder.statistics.dust_overflows = 1
    sdl_draw_record_statistics(&runtime, &encoder, 1, 96, 24)
    testing.expect(t, draw_encoder_rectangle(
        &encoder, {5, 6, 7, 8}, color.WHITE))
    encoder.dust_instance_count = 0
    encoder.dust_draw_count = 0
    encoder.dust_expanded_vertex_count = 6
    encoder.dust_expanded_draw_count = 1
    encoder.statistics.scissor_overflows = 1
    sdl_draw_record_statistics(&runtime, &encoder, 1, 192, 48)
    testing.expect_value(t, runtime.statistics.submitted_frames, u64(2))
    testing.expect_value(t, runtime.statistics.vertices, u64(12))
    testing.expect_value(t, runtime.statistics.indices, u64(18))
    testing.expect_value(t, runtime.statistics.primitive_overflows, u64(4))
    testing.expect_value(t, runtime.statistics.scissor_overflows, u64(1))
    testing.expect_value(t, runtime.statistics.dust_instances, u64(3))
    testing.expect_value(t, runtime.statistics.dust_draws, u64(2))
    testing.expect_value(t, runtime.statistics.dust_expanded_vertices, u64(6))
    testing.expect_value(t, runtime.statistics.dust_upload_operations, u64(3))
    testing.expect_value(t, runtime.statistics.dust_upload_bytes, u64(336))
    testing.expect_value(t, runtime.statistics.dust_overflows, u64(2))
    testing.expect_value(t, runtime.statistics.max_vertices, u32(8))
    testing.expect_value(t, runtime.statistics.max_dust_instances, u32(3))
    testing.expect_value(t, runtime.statistics.max_dust_expanded_vertices, u32(6))
    testing.expect_value(t, runtime.statistics.max_dust_upload_bytes, u32(192))
    testing.expect_value(t, runtime.statistics.max_upload_bytes, u32(384))
}

// Verify custom markers split otherwise compatible 2D batches in authored order.
@(test)
draw_encoder_test_custom_commands_preserve_batch_order :: proc(t: ^testing.T) {
    vertices: [8]Draw_Vertex
    indices: [12]u32
    batches: [2]Draw_Batch
    commands: [3]Draw_Command
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))

    testing.expect(t, draw_encoder_rectangle(
        &encoder, {1, 2, 3, 4}, color.WHITE))
    testing.expect(t, draw_encoder_append_custom_command(&encoder, .Tool, 7))
    testing.expect(t, draw_encoder_rectangle(
        &encoder, {10, 20, 30, 40}, color.WHITE))

    testing.expect_value(t, encoder.batch_count, 2)
    testing.expect_value(t, encoder.command_count, 3)
    testing.expect_value(t, commands,
        [3]Draw_Command{{.Batch, 0}, {.Tool, 7}, {.Batch, 1}})
}

// Verify command-capacity rejection does not mutate prior ordered state.
@(test)
draw_encoder_test_custom_command_overflow_is_atomic :: proc(t: ^testing.T) {
    vertices: [4]Draw_Vertex
    indices: [6]u32
    batches: [1]Draw_Batch
    commands: [1]Draw_Command
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))
    testing.expect(t, draw_encoder_append_custom_command(
        &encoder, .Dust_Instanced, 3))

    testing.expect(t, !draw_encoder_rectangle(
        &encoder, {1, 2, 3, 4}, color.WHITE))
    testing.expect_value(t, encoder.vertex_count, 0)
    testing.expect_value(t, encoder.batch_count, 0)
    testing.expect_value(t, encoder.command_count, 1)
    testing.expect_value(t, commands[0], Draw_Command{.Dust_Instanced, 3})
}

// Verify custom GPU-facing records retain their reflected byte contracts.
@(test)
draw_encoder_test_custom_record_layouts_match_shaders :: proc(t: ^testing.T) {
    instance: Dust_Instance
    base := uintptr(&instance)
    testing.expect_value(t, size_of(Stroke_Vertex), 36)
    testing.expect_value(t, size_of(Stroke_Vertex_Uniforms), 64)
    testing.expect_value(t, size_of(Stroke_Fragment_Uniforms), 192)
    testing.expect_value(t, size_of(Dust_Quad_Vertex), 16)
    testing.expect_value(t, size_of(Dust_Instance), 32)
    testing.expect_value(t, uintptr(&instance.color) - base, uintptr(12))
    testing.expect_value(t, uintptr(&instance.sprite_index) - base, uintptr(28))
}

// Verify one stroke copies its complete record and orders its tool command.
@(test)
draw_encoder_test_append_stroke_is_atomic_and_ordered :: proc(t: ^testing.T) {
    vertices: [4]Draw_Vertex
    indices: [6]u32
    batches: [1]Draw_Batch
    commands: [2]Draw_Command
    stroke_vertices: [3]Stroke_Vertex
    stroke_draws: [1]Stroke_Draw
    custom := Draw_Custom_Storage{
        stroke_vertices = stroke_vertices[:], stroke_draws = stroke_draws[:]}
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], &custom},
        {100, 100}, {200, 200}))
    source := [3]Stroke_Vertex{
        {position = {1, 2, 0}},
        {position = {3, 4, 0}},
        {position = {5, 6, 0}},
    }
    vertex_uniforms: Stroke_Vertex_Uniforms
    vertex_uniforms.clip_from_model[0] = 1
    fragment_uniforms := Stroke_Fragment_Uniforms{ambient = 0.4}

    testing.expect(t, draw_encoder_append_stroke(
        &encoder, source[:], vertex_uniforms, fragment_uniforms))
    testing.expect(t, !draw_encoder_append_stroke(
        &encoder, source[:], vertex_uniforms, fragment_uniforms))
    testing.expect_value(t, encoder.stroke_vertex_count, 3)
    testing.expect_value(t, encoder.stroke_draw_count, 1)
    testing.expect_value(t, encoder.command_count, 1)
    testing.expect_value(t, commands[0], Draw_Command{.Tool, 0})
    testing.expect_value(t, stroke_vertices, source)
    testing.expect_value(t, stroke_draws[0].scissor,
        Draw_Scissor{0, 0, 200, 200})
    testing.expect_value(t, stroke_draws[0].fragment_uniforms.ambient, f32(0.4))
}

// Verify full configured dust capacity selects one instanced ordered command.
@(test)
draw_encoder_test_dust_capacity_is_one_instanced_draw :: proc(t: ^testing.T) {
    commands: [1]Draw_Command
    instances := make([]Dust_Instance, DUST_INSTANCE_CAPACITY, context.allocator)
    defer delete(instances, context.allocator)
    draws: [1]Dust_Draw
    custom := Draw_Custom_Storage{dust_instances = instances, dust_draws = draws[:]}
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {commands = commands[:], custom = &custom}, {100, 100}, {200, 200}))
    draw_encoder_enable_dust_instancing(&encoder, true)

    testing.expect(t, draw_encoder_commit_dust(
        &encoder, DUST_INSTANCE_CAPACITY, rawptr(uintptr(1))))
    testing.expect_value(t, encoder.dust_instance_count, DUST_INSTANCE_CAPACITY)
    testing.expect_value(t, commands[0], Draw_Command{.Dust_Instanced, 0})
    testing.expect_value(t, draws[0].count, u32(DUST_INSTANCE_CAPACITY))
}

// Verify expanded dust has dedicated full-prefix geometry and atlas UVs.
@(test)
draw_encoder_test_dust_expanded_fallback_is_capacity_safe :: proc(t: ^testing.T) {
    commands: [1]Draw_Command
    instances: [2]Dust_Instance
    vertices: [12]Draw_Vertex
    draws: [1]Dust_Draw
    custom := Draw_Custom_Storage{dust_instances = instances[:],
        dust_expanded_vertices = vertices[:], dust_expanded_draws = draws[:]}
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {commands = commands[:], custom = &custom}, {100, 100}, {100, 100}))
    instances[0] = {center_diameter = {10, 20, 4},
        color = {1, 0.5, 0, 1}, sprite_index = 4}
    instances[1] = {center_diameter = {30, 40, 2},
        color = {0, 1, 1, 0.5}, sprite_index = 8}

    testing.expect(t, draw_encoder_commit_dust(
        &encoder, len(instances), rawptr(uintptr(1))))
    testing.expect_value(t, commands[0], Draw_Command{.Dust_Expanded, 0})
    testing.expect_value(t, encoder.dust_expanded_vertex_count, 12)
    testing.expect_value(t, vertices[0].position, geometry.Vector2{8, 18})
    testing.expect_value(t, vertices[0].texcoord,
        geometry.Vector2{f32(1.0 / 3.0), f32(1.0 / 3.0)})
}
