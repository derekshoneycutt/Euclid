package world

import "core:math"
import "core:testing"
import geometry "../../core/geometry"
import color "../../core/color"
import core "../../core"
import native "../native"
import shapemodel "../../shapes/model"
import projection "projection"
import worldmodel "model"

// shadow_test_mesh_area sums the area of non-overlapping triangle fragments.
shadow_test_mesh_area :: proc(mesh: ^Shadow_Fragment_Mesh) -> f32 {
    result: f32
    for index := 0; index < mesh.count; index += 3 {
        first := mesh.points[index + 1] - mesh.points[index]
        second := mesh.points[index + 2] - mesh.points[index]
        result += math.abs(first.x * second.y - first.y * second.x) * 0.5
    }
    return result
}

// Verify finite-board clipping conserves coverage for triangles crossing every edge.
@(test)
shadow_receivers_partition_conserves_coverage :: proc(t: ^testing.T) {
    receivers: Shadow_Receiver_Geometry = {
        board = {{0, 0}, {1, 0}, {1, 1}, {0, 1}},
        winding = 1,
    }
    triangles := [?][3]geometry.Vector2{
        {{0.2, 0.2}, {0.8, 0.2}, {0.2, 0.8}},
        {{-2, -2}, {-1, -2}, {-2, -1}},
        {{-1, 0.5}, {0.5, -1}, {2, 2}},
        {{-2, -2}, {3, -2}, {0.5, 3}},
        {{0, 0}, {1, 0}, {1, 1}},
    }
    for triangle in triangles {
        mesh: Shadow_Fragment_Mesh
        shadow_partition_triangle(receivers, triangle, &mesh)
        first := triangle[1] - triangle[0]
        second := triangle[2] - triangle[0]
        expected := math.abs(first.x * second.y - first.y * second.x) * 0.5
        testing.expect(t, math.abs(shadow_test_mesh_area(&mesh) - expected) < 0.0001)
        testing.expect(t, mesh.count <= SHADOW_FRAGMENT_VERTEX_CAPACITY)
    }
}

// Verify ground coverage hidden by the projected board is excluded after shifting.
@(test)
shadow_receivers_ground_is_occluded :: proc(t: ^testing.T) {
    receivers: Shadow_Receiver_Geometry = {
        board = {{0, 0}, {1, 0}, {1, 1}, {0, 1}},
        winding = 1,
        ground_offset = {0.25, 0},
    }
    triangle := [?]geometry.Vector2{{-0.2, 0.2}, {-0.1, 0.2}, {-0.2, 0.3}}
    mesh: Shadow_Fragment_Mesh
    shadow_partition_triangle(receivers, triangle, &mesh)
    testing.expect_value(t, mesh.count, 0)
    receivers.ground_offset = {-0.25, 0}
    shadow_partition_triangle(receivers, triangle, &mesh)
    testing.expect(t, math.abs(shadow_test_mesh_area(&mesh) - 0.005) < 0.00001)
    for point in mesh.points[:mesh.count] {
        testing.expect(t, point.x < 0)
    }
}

// Verify the ground offset follows the same projection as the board shadow.
@(test)
shadow_receivers_offset_matches_light :: proc(t: ^testing.T) {
    scale: worldmodel.Iso_Scale = {
        use_directional_shadow = true,
        main_light_dir = {0.35, -0.45, -1},
    }
    projection.fit_iso_scale_to_viewport(&scale, 900, 500)
    receivers := shadow_receiver_geometry(surface_shadow_test_surface(), scale)
    expected := projection.iso_to_cartesian({0.007, -0.009, -0.02}, scale) -
        projection.iso_to_cartesian({}, scale)
    testing.expect(t, math.abs(receivers.ground_offset.x - expected.x) < 0.001)
    testing.expect(t, math.abs(receivers.ground_offset.y - expected.y) < 0.001)
    scale.main_light_dir = {1, 0, 0}
    receivers = shadow_receiver_geometry(surface_shadow_test_surface(), scale)
    expected = projection.iso_to_cartesian({0, 0, -0.02}, scale) -
        projection.iso_to_cartesian({}, scale)
    testing.expect_value(t, receivers.ground_offset, expected)
}

// Verify partitioning conserves area across both board windings and all edges.
@(test)
shadow_receivers_edges_and_windings :: proc(t: ^testing.T) {
    boards := [?][4]geometry.Vector2{
        {{0, 0}, {1, 0}, {1, 1}, {0, 1}},
        {{0, 1}, {1, 1}, {1, 0}, {0, 0}},
    }
    for board, board_index in boards {
        winding := f32(1)
        if board_index == 1 {
            winding = -1
        }
        receivers: Shadow_Receiver_Geometry = {
            board = board,
            winding = winding,
        }
        for edge in 0..<4 {
            first := board[edge]
            second := board[(edge + 1) % 4]
            midpoint := (first + second) * 0.5
            tangent := second - first
            inward := geometry.Vector2{-tangent.y, tangent.x} * winding
            triangle := [?]geometry.Vector2{
                midpoint - inward * 0.3,
                midpoint + tangent * 0.2 + inward * 0.3,
                midpoint - tangent * 0.2 + inward * 0.3,
            }
            mesh: Shadow_Fragment_Mesh
            shadow_partition_triangle(receivers, triangle, &mesh)
            testing.expect(t, math.abs(shadow_test_mesh_area(&mesh) - 0.12) < 0.0001)
        }
    }
}

// Check encoded coverage remains on the board or beyond the shifted ground gap.
shadow_receivers_expect_gap :: proc(
    t: ^testing.T, target: ^native.Draw_Encoder, tint: color.Color_RGBA8) {
    board_vertices, ground_vertices := 0, 0
    for index in target.indices[:target.index_count] {
        vertex := target.vertices[index]
        testing.expect_value(t, vertex.color, tint)
        testing.expect(t, vertex.position.x <= 50.0001 || vertex.position.x >= 59.9999)
        if vertex.position.x <= 50.0001 {
            board_vertices += 1
        } else {
            ground_vertices += 1
        }
    }
    testing.expect(t, board_vertices > 0 && ground_vertices > 0)
}

// Verify stroke and point coverage split without extending across the receiver gap.
@(test)
shadow_receivers_clip_encoded_coverage :: proc(t: ^testing.T) {
    source_vertices: [256]native.Draw_Vertex
    source_indices: [512]u32
    source_batches: [1]native.Draw_Batch
    source_commands: [1]native.Draw_Command
    source: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&source, {
        source_vertices[:], source_indices[:], source_batches[:], source_commands[:], nil,
    }, {100, 100}, {100, 100}))
    tint: color.Color_RGBA8 = {0, 0, 0, 90}
    testing.expect(t, native.draw_encoder_circle(&source, {50, 25}, 8, tint))
    line := [?]geometry.Vector2{{40, 35}, {60, 35}}
    testing.expect(t, native.draw_encoder_polyline(&source, line[:], nil, {
        width = 8,
        miter_limit = 4,
        color = tint,
        topology = .Open,
        start_cap = .Round,
        finish_cap = .Round,
    }))
    target_vertices: [2048]native.Draw_Vertex
    target_indices: [2048]u32
    target_batches: [1]native.Draw_Batch
    target_commands: [1]native.Draw_Command
    target: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&target, {
        target_vertices[:], target_indices[:], target_batches[:], target_commands[:], nil,
    }, {100, 100}, {100, 100}))
    receivers: Shadow_Receiver_Geometry = {
        board = {{0, 0}, {50, 0}, {50, 50}, {0, 50}},
        winding = 1,
        ground_offset = {10, 0},
    }
    shadow_submit_receivers(&target, &source, receivers)
    testing.expect(t, target.vertex_count > 0)
    testing.expect_value(t, target.statistics.primitive_overflows, u32(0))
    shadow_receivers_expect_gap(t, &target, tint)
}

// Verify all-on-board shadows retain the compact encoded topology and colors.
@(test)
shadow_receivers_preserve_compact_board_pass :: proc(t: ^testing.T) {
    source_vertices, target_vertices: [64]native.Draw_Vertex
    source_indices, target_indices: [128]u32
    source_batches, target_batches: [1]native.Draw_Batch
    source_commands, target_commands: [1]native.Draw_Command
    source, target: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&source, {
        source_vertices[:], source_indices[:], source_batches[:], source_commands[:], nil,
    }, {100, 100}, {100, 100}))
    testing.expect(t, native.draw_encoder_begin(&target, {
        target_vertices[:], target_indices[:], target_batches[:], target_commands[:], nil,
    }, {100, 100}, {100, 100}))
    testing.expect(t, native.draw_encoder_circle(&source, {25, 25}, 8, {0, 0, 0, 90}))
    receivers: Shadow_Receiver_Geometry = {
        board = {{0, 0}, {50, 0}, {50, 50}, {0, 50}},
        winding = 1,
    }
    shadow_submit_receivers(&target, &source, receivers)
    testing.expect_value(t, target.vertex_count, source.vertex_count)
    testing.expect_value(t, target.index_count, source.index_count)
    for index in 0..<source.vertex_count {
        testing.expect_value(t, target.vertices[index], source.vertices[index])
    }
    for index in 0..<source.index_count {
        testing.expect_value(t, target.indices[index], source.indices[index])
    }
}

// Verify insufficient destination storage rejects a split triangle observably.
@(test)
shadow_receivers_capacity_failure_is_atomic :: proc(t: ^testing.T) {
    source_vertices: [3]native.Draw_Vertex
    source_indices: [3]u32
    source_batches: [1]native.Draw_Batch
    source_commands: [1]native.Draw_Command
    source: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&source, {
        source_vertices[:], source_indices[:], source_batches[:], source_commands[:], nil,
    }, {100, 100}, {100, 100}))
    testing.expect(t, native.draw_encoder_triangle(
        &source, {40, 20}, {60, 20}, {40, 40}, {0, 0, 0, 90}))
    target_vertices: [2]native.Draw_Vertex
    target_indices: [2]u32
    target_batches: [1]native.Draw_Batch
    target_commands: [1]native.Draw_Command
    target: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&target, {
        target_vertices[:], target_indices[:], target_batches[:], target_commands[:], nil,
    }, {100, 100}, {100, 100}))
    receivers: Shadow_Receiver_Geometry = {
        board = {{0, 0}, {50, 0}, {50, 50}, {0, 50}},
        winding = 1,
        ground_offset = {10, 0},
    }
    shadow_submit_receivers(&target, &source, receivers)
    testing.expect_value(t, target.vertex_count, 0)
    testing.expect_value(t, target.index_count, 0)
    testing.expect_value(t, target.batch_count, 0)
    testing.expect_value(t, target.statistics.primitive_overflows, u32(1))
}

// Allocate a pen-shadow fixture; its caller frees the returned state.
shadow_receivers_pen_fixture :: proc() -> ^core.Euclid_General_State {
    state := new(core.Euclid_General_State, context.allocator)
    state.iso_scale = {
        scale = 100,
        half_scale = 50,
        quarter_scale = 25,
        x_offset = 50,
        y_offset = 50,
    }
    state.ui_runtime.preferences.values.animation.scale_percent = 100
    state.draw_surface = {
        zeros = {0, 0, 0},
        right_up = {1, 0, 0},
        right_down = {1, 1, 0},
        left_down = {0, 1, 0},
    }
    state.shape_world.draw_cache.items[0] = shapemodel.Shapes_Pen_Draw{
        base = {
            brush_size = 8,
        },
        joint1 = {0.8, 0.5, 0.1},
        joint2 = {1.3, 0.5, 0.1},
    }
    state.shape_world.draw_cache.item_count = 1
    return state
}

// Verify the actual pen shadow pass reaches both finite receivers.
@(test)
shadow_receivers_pen_pass_crosses_board :: proc(t: ^testing.T) {
    state := shadow_receivers_pen_fixture()
    defer free(state, context.allocator)
    source_vertices: [128]native.Draw_Vertex
    source_indices: [256]u32
    source_batches: [1]native.Draw_Batch
    source_commands: [1]native.Draw_Command
    source: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&source, {
        source_vertices[:], source_indices[:], source_batches[:], source_commands[:], nil,
    }, {100, 100}, {100, 100}))
    draw_encoded_cached_tool_shadow_pass(state, &source)
    testing.expect(t, source.index_count > 0)
    target_vertices: [2048]native.Draw_Vertex
    target_indices: [2048]u32
    target_batches: [1]native.Draw_Batch
    target_commands: [1]native.Draw_Command
    target: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&target, {
        target_vertices[:], target_indices[:], target_batches[:], target_commands[:], nil,
    }, {100, 100}, {100, 100}))
    receivers := shadow_receiver_geometry(state.draw_surface, state.iso_scale)
    shadow_submit_receivers(&target, &source, receivers)
    board, ground := 0, 0
    for index in target.indices[:target.index_count] {
        vertex := target.vertices[index]
        if shadow_vertex_on_board(receivers, vertex.position) {
            board += 1
        } else {
            ground += 1
        }
    }
    testing.expect(t, board > 0 && ground > 0)
    testing.expect_value(t, target.statistics.primitive_overflows, u32(0))
}

// Verify one crossing does not expand unrelated indexed circles into separate triangles.
@(test)
shadow_receivers_preserve_mostly_board_capacity :: proc(t: ^testing.T) {
    source_vertices: [1024]native.Draw_Vertex
    source_indices: [4096]u32
    source_batches: [1]native.Draw_Batch
    source_commands: [1]native.Draw_Command
    source: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&source, {
        source_vertices[:], source_indices[:], source_batches[:], source_commands[:], nil,
    }, {100, 100}, {100, 100}))
    for _ in 0..<20 {
        testing.expect(t, native.draw_encoder_circle(
            &source, {25, 25}, 5, {0, 0, 0, 90}))
    }
    testing.expect(t, native.draw_encoder_circle(&source, {50, 25}, 8, {0, 0, 0, 90}))
    target_vertices: [1200]native.Draw_Vertex
    target_indices: [4096]u32
    target_batches: [1]native.Draw_Batch
    target_commands: [1]native.Draw_Command
    target: native.Draw_Encoder
    testing.expect(t, native.draw_encoder_begin(&target, {
        target_vertices[:], target_indices[:], target_batches[:], target_commands[:], nil,
    }, {100, 100}, {100, 100}))
    receivers: Shadow_Receiver_Geometry = {
        board = {{0, 0}, {50, 0}, {50, 50}, {0, 50}},
        winding = 1,
        ground_offset = {10, 0},
    }
    shadow_submit_receivers(&target, &source, receivers)
    testing.expect_value(t, target.statistics.primitive_overflows, u32(0))
    testing.expect(t, target.vertex_count < len(target_vertices))
    testing.expect(t, target.index_count >= source.index_count)
}
