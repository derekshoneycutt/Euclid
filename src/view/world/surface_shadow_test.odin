package world

import testing "core:testing"
import math "core:math"
import geometry "../../core/geometry"
import native "../native"
import worldmodel "model"
import projection "projection"

// surface_shadow_test_surface supplies the full bordered board without application state.
surface_shadow_test_surface :: proc() -> worldmodel.Euclid_Drawing_Surface {
    return {
        zeros = {-0.05, -0.05, 0},
        right_up = {1.05, -0.05, 0},
        right_down = {1.05, 1.05, 0},
        left_down = {-0.05, 1.05, 0},
    }
}

// Verify the shadow follows scene light below the board without changing ordinary shadows.
@(test)
surface_shadow_follows_animation_light :: proc(t: ^testing.T) {
    scale: worldmodel.Iso_Scale = {
        use_directional_shadow = true,
        main_light_dir = {0.35, -0.45, -1},
    }
    projection.fit_iso_scale_to_viewport(
        &scale, worldmodel.VIEW_WIDTH, worldmodel.VIEW_HEIGHT)
    surface := surface_shadow_test_surface()
    mesh: Surface_Shadow_Mesh
    build_surface_shadow_mesh(surface, scale, &mesh)
    expected := projection.iso_to_cartesian(
        {surface.zeros.x + 0.35 * 0.02,
            surface.zeros.y - 0.45 * 0.02, -0.02}, scale)
    testing.expect(t, math.abs(mesh.vertices[0].position.x - expected.x) < 0.001)
    testing.expect(t, math.abs(mesh.vertices[0].position.y - expected.y) < 0.001)
    board := projection.iso_to_cartesian(surface.zeros, scale)
    testing.expect(t, mesh.vertices[0].position.x > board.x)
    testing.expect(t, mesh.vertices[0].position.y > board.y)
    testing.expect(t, mesh.vertices[0].position.x - board.x < 7)
    testing.expect(t, mesh.vertices[0].position.y - board.y < 9)
    testing.expect_value(t, project_to_floor_shadow({0, 0, 1}, scale),
        geometry.Vector3{0.35, -0.45, 0})

    scale.main_light_dir = {-0.35, 0.45, -1}
    build_surface_shadow_mesh(surface, scale, &mesh)
    testing.expect(t, mesh.vertices[0].position.x < board.x)
}

// Verify vertical fallback still separates the board and its lower receiving plane.
@(test)
surface_shadow_vertical_fallback :: proc(t: ^testing.T) {
    scale: worldmodel.Iso_Scale
    point: geometry.Vector3 = {0.2, 0.3, 0}
    expected: geometry.Vector3 = {0.2, 0.3, SURFACE_SHADOW_RECEIVER_HEIGHT}
    testing.expect_value(t, project_to_floor_shadow(
        point, scale, SURFACE_SHADOW_RECEIVER_HEIGHT), expected)
    scale.use_directional_shadow = true
    scale.main_light_dir = {1, 0, 0}
    testing.expect_value(t, project_to_floor_shadow(
        point, scale, SURFACE_SHADOW_RECEIVER_HEIGHT), expected)
}

// Verify fixed welded rings fade monotonically, fill the center, and scale with the board.
@(test)
surface_shadow_mesh_is_filled_feathered_and_fitted :: proc(t: ^testing.T) {
    scale: worldmodel.Iso_Scale
    projection.fit_iso_scale_to_viewport(
        &scale, worldmodel.VIEW_WIDTH, worldmodel.VIEW_HEIGHT)
    full, half: Surface_Shadow_Mesh
    build_surface_shadow_mesh(surface_shadow_test_surface(), scale, &full)
    projection.fit_iso_scale_to_viewport(
        &scale, worldmodel.VIEW_WIDTH * 0.5, worldmodel.VIEW_HEIGHT * 0.5)
    build_surface_shadow_mesh(surface_shadow_test_surface(), scale, &half)
    for vertex, index in full.vertices {
        testing.expect_value(t, half.vertices[index].position, vertex.position * 0.5)
        if index >= 4 {
            testing.expect(t, vertex.color[3] <= full.vertices[index - 4].color[3])
        }
        if index >= len(full.vertices) - 4 {
            testing.expect_value(t, vertex.color[3], u8(0))
        }
    }
    for index in full.indices {
        testing.expect(t, int(index) < len(full.vertices))
    }
    testing.expect_value(t, full.indices[len(full.indices) - 6], u32(0))
    testing.expect_value(t, full.indices[len(full.indices) - 1], u32(3))
}

// Verify shadow admission preserves clipping and rejects insufficient space atomically.
@(test)
surface_shadow_encoder_is_bounded_and_atomic :: proc(t: ^testing.T) {
    vertices: [native.DRAW_SHADOW_VERTEX_COUNT]native.Draw_Vertex
    indices: [SURFACE_SHADOW_INDEX_COUNT]u32
    batches: [1]native.Draw_Batch
    commands: [1]native.Draw_Command
    encoder: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:], batches[:], commands[:], nil},
        {900, 500}, {1800, 1000}))
    testing.expect(t, native.draw_encoder_push_scissor(&encoder, {10, 20, 800, 450}))
    testing.expect(t, draw_encoded_surface_shadow(
        &encoder, surface_shadow_test_surface(), {}))
    testing.expect_value(t, encoder.vertex_count, len(vertices))
    testing.expect_value(t, encoder.index_count, len(indices))
    testing.expect_value(t, batches[0].scissor, native.Draw_Scissor{20, 40, 1600, 900})
    testing.expect_value(t, encoder.scissor_count, 2)
    testing.expect(t, native.draw_encoder_begin(&encoder,
        {vertices[:], indices[:len(indices) - 1], batches[:], commands[:], nil},
        {900, 500}, {900, 500}))
    testing.expect(t, !draw_encoded_surface_shadow(
        &encoder, surface_shadow_test_surface(), {}))
    testing.expect_value(t, encoder.vertex_count, 0)
    testing.expect_value(t, encoder.index_count, 0)
    testing.expect_value(t, encoder.batch_count, 0)
}
