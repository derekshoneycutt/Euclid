#+test
package native

import "core:math"
import "core:testing"

import color "../../core/color"
import geometry "../../core/geometry"

// Draw_Shadow_Test_Topology accumulates mesh edge and vertex incidence.
Draw_Shadow_Test_Topology :: struct {
    edges: [DRAW_SHADOW_VERTEX_COUNT][DRAW_SHADOW_VERTEX_COUNT]u8,
    vertex_references: [DRAW_SHADOW_VERTEX_COUNT]u8,
}

// draw_shadow_test_style provides one valid test elevation in logical pixels.
draw_shadow_test_style :: #force_inline proc() -> Draw_Shadow_Style {
    return {
        contact_offset = {0.75, 0.75},
        cast_offset = {2.5, 4.5},
        feather = 5.5,
        contact_opacity = 0.26,
        cast_opacity = 0.20,
        tint = color.Color_RGBA8{22, 14, 16, 255},
    }
}

// draw_shadow_test_record_triangle validates and records one mesh face.
draw_shadow_test_record_triangle :: proc(
    t: ^testing.T, vertices: []Draw_Vertex, indices: []u32,
    triangle: int, topology: ^Draw_Shadow_Test_Topology) {
    a, b, c := indices[triangle * 3], indices[triangle * 3 + 1],
        indices[triangle * 3 + 2]
    testing.expect(t, a < DRAW_SHADOW_VERTEX_COUNT)
    testing.expect(t, b < DRAW_SHADOW_VERTEX_COUNT)
    testing.expect(t, c < DRAW_SHADOW_VERTEX_COUNT)
    pa, pb, pc := vertices[a].position, vertices[b].position,
        vertices[c].position
    area := (pb.x - pa.x) * (pc.y - pa.y) -
        (pb.y - pa.y) * (pc.x - pa.x)
    testing.expect(t, !math.is_nan(area) && !math.is_inf(area) && area < 0)
    topology^.vertex_references[a] += 1
    topology^.vertex_references[b] += 1
    topology^.vertex_references[c] += 1
    topology^.edges[a][b] += 1
    topology^.edges[b][a] += 1
    topology^.edges[b][c] += 1
    topology^.edges[c][b] += 1
    topology^.edges[c][a] += 1
    topology^.edges[a][c] += 1
}

// draw_shadow_test_mesh_topology checks indices form one closed mesh boundary.
draw_shadow_test_mesh_topology :: proc(
    t: ^testing.T, vertices: []Draw_Vertex, indices: []u32) {
    topology: Draw_Shadow_Test_Topology
    for triangle in 0..<len(indices) / 3 {
        draw_shadow_test_record_triangle(
            t, vertices, indices, triangle, &topology)
    }
    boundary_edges := 0
    for first in 0..<DRAW_SHADOW_VERTEX_COUNT {
        testing.expect(t, topology.vertex_references[first] > 0)
        for second in first + 1..<DRAW_SHADOW_VERTEX_COUNT {
            count := topology.edges[first][second]
            testing.expect(t, count == 0 || count == 1 || count == 2)
            if count == 1 {
                testing.expect(t,
                    first / 4 == second / 4 &&
                    (first / 4 == 0 || first / 4 == DRAW_SHADOW_RING_COUNT - 1))
                boundary_edges += 1
            }
        }
    }
    testing.expect_value(t, boundary_edges, 8)
}

// draw_shadow_test_mesh_bounds checks surface and finite outer-ring extents.
draw_shadow_test_mesh_bounds :: proc(
    t: ^testing.T, bounds: geometry.Rectangle, vertices: []Draw_Vertex) {
    testing.expect_value(t, vertices[0].position,
        geometry.Vector2{bounds.x, bounds.y})
    testing.expect_value(t, vertices[16].color[3], u8(0))
    testing.expect_value(t, vertices[17].color[3], u8(0))
    testing.expect_value(t, vertices[18].color[3], u8(0))
    testing.expect_value(t, vertices[19].color[3], u8(0))
    testing.expect_value(t, vertices[16].position,
        geometry.Vector2{4.125, 6.125})
    testing.expect_value(t, vertices[18].position,
        geometry.Vector2{48.375, 42.375})
}

// Verify bounded shadow topology, stable counts, and a welded seam-free mesh.
@(test)
draw_shadow_test_mesh_is_bounded_deterministic_and_welded :: proc(t: ^testing.T) {
    vertices_a: [DRAW_SHADOW_VERTEX_COUNT]Draw_Vertex
    indices_a: [DRAW_SHADOW_INDEX_COUNT]u32
    batches_a: [1]Draw_Batch
    commands_a: [1]Draw_Command
    vertices_b: [DRAW_SHADOW_VERTEX_COUNT]Draw_Vertex
    indices_b: [DRAW_SHADOW_INDEX_COUNT]u32
    batches_b: [1]Draw_Batch
    commands_b: [1]Draw_Command
    encoder_a: Draw_Encoder
    encoder_b: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder_a,
        {vertices_a[:], indices_a[:], batches_a[:], commands_a[:], nil},
        {100, 100}, {200, 200}))
    testing.expect(t, draw_encoder_begin(&encoder_b,
        {vertices_b[:], indices_b[:], batches_b[:], commands_b[:], nil},
        {100, 100}, {200, 200}))
    bounds: geometry.Rectangle = {10, 12, 30, 20}
    testing.expect(t, draw_encoder_shadow(
        &encoder_a, bounds, draw_shadow_test_style()))
    testing.expect(t, draw_encoder_shadow(
        &encoder_b, bounds, draw_shadow_test_style()))
    testing.expect_value(t, encoder_a.vertex_count, DRAW_SHADOW_VERTEX_COUNT)
    testing.expect_value(t, encoder_a.index_count, DRAW_SHADOW_INDEX_COUNT)
    testing.expect_value(t, encoder_a.batch_count, 1)
    testing.expect_value(t, encoder_a.command_count, 1)
    testing.expect_value(t, vertices_b, vertices_a)
    testing.expect_value(t, indices_b, indices_a)
    draw_shadow_test_mesh_bounds(t, bounds, vertices_a[:])
    draw_shadow_test_mesh_topology(t, vertices_a[:], indices_a[:])
}

// Verify shadows respect but never modify the encoder's active scissor stack.
@(test)
draw_shadow_test_scissor_is_balanced_and_scaled :: proc(t: ^testing.T) {
    vertices: [DRAW_SHADOW_VERTEX_COUNT]Draw_Vertex
    indices: [DRAW_SHADOW_INDEX_COUNT]u32
    batches: [1]Draw_Batch
    commands: [1]Draw_Command
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {200, 200}))
    testing.expect(t, draw_encoder_push_scissor(
        &encoder, {10, 20, 40, 30}))
    testing.expect(t, draw_encoder_shadow(
        &encoder, {12, 22, 20, 10}, draw_shadow_test_style()))
    testing.expect_value(t, encoder.scissor_count, 2)
    testing.expect_value(t, batches[0].scissor, Draw_Scissor{20, 40, 80, 60})
    testing.expect(t, draw_encoder_pop_scissor(&encoder))
    testing.expect_value(t, encoder.scissor_count, 1)
    testing.expect_value(t, encoder.statistics.scissor_overflows, u32(0))
}

// draw_shadow_test_capacity_failure checks rejected geometry has no publication.
draw_shadow_test_capacity_failure :: proc(
    t: ^testing.T, vertex_capacity, index_capacity,
    batch_capacity, command_capacity: int) {
    vertices: [DRAW_SHADOW_VERTEX_COUNT]Draw_Vertex
    indices: [DRAW_SHADOW_INDEX_COUNT]u32
    batches: [1]Draw_Batch
    commands: [1]Draw_Command
    encoder: Draw_Encoder
    storage: Draw_Storage = {
        vertices = vertices[:vertex_capacity],
        indices = indices[:index_capacity],
        batches = batches[:batch_capacity],
        commands = commands[:command_capacity],
    }
    testing.expect(t, draw_encoder_begin(
        &encoder, storage, {100, 100}, {100, 100}))
    testing.expect(t, !draw_encoder_shadow(
        &encoder, {10, 10, 20, 20}, draw_shadow_test_style()))
    testing.expect_value(t, encoder.vertex_count, 0)
    testing.expect_value(t, encoder.index_count, 0)
    testing.expect_value(t, encoder.batch_count, 0)
    testing.expect_value(t, encoder.command_count, 0)
    testing.expect_value(t, encoder.statistics.primitive_overflows, u32(1))
}

// Verify all encoder capacities reject the whole shadow instead of a partial mesh.
@(test)
draw_shadow_test_capacity_failures_are_atomic :: proc(t: ^testing.T) {
    draw_shadow_test_capacity_failure(
        t, DRAW_SHADOW_VERTEX_COUNT - 1, DRAW_SHADOW_INDEX_COUNT, 1, 1)
    draw_shadow_test_capacity_failure(
        t, DRAW_SHADOW_VERTEX_COUNT, DRAW_SHADOW_INDEX_COUNT - 1, 1, 1)
    draw_shadow_test_capacity_failure(
        t, DRAW_SHADOW_VERTEX_COUNT, DRAW_SHADOW_INDEX_COUNT, 0, 1)
    draw_shadow_test_capacity_failure(
        t, DRAW_SHADOW_VERTEX_COUNT, DRAW_SHADOW_INDEX_COUNT, 1, 0)
}

// Verify malformed geometry is rejected before changing encoder publication.
@(test)
draw_shadow_test_invalid_geometry_is_rejected :: proc(t: ^testing.T) {
    vertices: [DRAW_SHADOW_VERTEX_COUNT]Draw_Vertex
    indices: [DRAW_SHADOW_INDEX_COUNT]u32
    batches: [1]Draw_Batch
    commands: [1]Draw_Command
    encoder: Draw_Encoder
    testing.expect(t, draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {100, 100}, {100, 100}))
    testing.expect(t, !draw_encoder_shadow(
        &encoder, {10, 10, 0, 20}, draw_shadow_test_style()))
    testing.expect_value(t, encoder.vertex_count, 0)
    testing.expect_value(t, encoder.index_count, 0)
    testing.expect_value(t, encoder.batch_count, 0)
    testing.expect_value(t, encoder.command_count, 0)
    testing.expect_value(t, encoder.statistics.primitive_overflows, u32(0))
}
