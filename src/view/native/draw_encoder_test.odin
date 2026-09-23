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
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:]}, {100, 100}, {100, 100}))
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
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:]}, {100, 100}, {150, 200}))
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
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:]}, {100, 100}, {100, 100}))
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
    encoder: Draw_Encoder
    storage := Draw_Storage{vertices[:], indices[:], batches[:]}
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
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:]}, {100, 100}, {100, 100}))
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
    encoder: Draw_Encoder
    texture := rawptr(uintptr(1))
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:]}, {100, 100}, {100, 100}))
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
    encoder: Draw_Encoder
    runtime: Sdl_Draw_Runtime
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:]}, {100, 100}, {100, 100}))
    testing.expect(t, draw_encoder_rectangle(
        &encoder, {1, 2, 3, 4}, color.WHITE))
    encoder.statistics.primitive_overflows = 2
    sdl_draw_record_statistics(&runtime, &encoder, 1, 96, 24)
    testing.expect(t, draw_encoder_rectangle(
        &encoder, {5, 6, 7, 8}, color.WHITE))
    encoder.statistics.scissor_overflows = 1
    sdl_draw_record_statistics(&runtime, &encoder, 1, 192, 48)
    testing.expect_value(t, runtime.statistics.submitted_frames, u64(2))
    testing.expect_value(t, runtime.statistics.vertices, u64(12))
    testing.expect_value(t, runtime.statistics.indices, u64(18))
    testing.expect_value(t, runtime.statistics.primitive_overflows, u64(4))
    testing.expect_value(t, runtime.statistics.scissor_overflows, u64(1))
    testing.expect_value(t, runtime.statistics.max_vertices, u32(8))
    testing.expect_value(t, runtime.statistics.max_upload_bytes, u32(240))
}
