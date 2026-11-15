package world

import geometry "../../core/geometry"
import native "../native"
import worldmodel "model"
import projection "projection"

// Each clipping edge can add one vertex to a convex polygon.
SHADOW_CLIP_VERTEX_CAPACITY :: 16
// A triangle partitions into at most one board polygon and sixteen ground polygons.
SHADOW_FRAGMENT_VERTEX_CAPACITY :: 512

// Shadow_Receiver_Geometry describes the projected board and the lower-plane offset.
Shadow_Receiver_Geometry :: struct {
    board: [4]geometry.Vector2,
    winding: f32,
    ground_offset: geometry.Vector2,
}

// Shadow_Clip_Polygon contains one bounded convex coverage fragment.
Shadow_Clip_Polygon :: struct {
    points: [SHADOW_CLIP_VERTEX_CAPACITY]geometry.Vector2,
    count: int,
}

// Shadow_Clip_Edge selects the interior halfspace of one projected board edge.
Shadow_Clip_Edge :: struct {
    first, second: geometry.Vector2,
    winding: f32,
}

// Shadow_Fragment_Mesh stores independent triangles from one source triangle.
Shadow_Fragment_Mesh :: struct {
    points: [SHADOW_FRAGMENT_VERTEX_CAPACITY]geometry.Vector2,
    count: int,
}

// shadow_receiver_geometry resolves the outer board and the ground's light-ray offset.
shadow_receiver_geometry :: proc(
    surface: worldmodel.Euclid_Drawing_Surface,
    scale: worldmodel.Iso_Scale) -> Shadow_Receiver_Geometry {
    corners := [?]geometry.Vector3{
        surface.zeros, surface.right_up, surface.right_down, surface.left_down}
    result: Shadow_Receiver_Geometry
    for corner, index in corners {
        result.board[index] = projection.iso_to_cartesian(corner, scale)
    }
    edge := result.board[1] - result.board[0]
    next := result.board[2] - result.board[1]
    result.winding = 1
    if edge.x * next.y - edge.y * next.x < 0 {
        result.winding = -1
    }
    origin: geometry.Vector3
    ground := project_to_floor_shadow(origin, scale, SURFACE_SHADOW_RECEIVER_HEIGHT)
    result.ground_offset = projection.iso_to_cartesian(ground, scale) -
        projection.iso_to_cartesian(origin, scale)
    return result
}

// shadow_edge_distance classifies a screen point against one oriented board edge.
shadow_edge_distance :: #force_inline proc(
    point, first, second: geometry.Vector2, winding: f32) -> f32 {
    edge := second - first
    relative := point - first
    return winding * (edge.x * relative.y - edge.y * relative.x)
}

// shadow_clip_edge splits convex coverage into bounded interior and exterior pieces.
shadow_clip_edge :: proc(
    input: Shadow_Clip_Polygon, edge: Shadow_Clip_Edge,
    inside, outside: ^Shadow_Clip_Polygon) {
    inside.count, outside.count = 0, 0
    if input.count == 0 {
        return
    }
    previous := input.points[input.count - 1]
    previous_distance := shadow_edge_distance(
        previous, edge.first, edge.second, edge.winding)
    for index in 0..<input.count {
        current := input.points[index]
        distance := shadow_edge_distance(current, edge.first, edge.second, edge.winding)
        if (previous_distance < 0 && distance > 0) ||
            (previous_distance > 0 && distance < 0) {
            intersection := previous + (current - previous) *
                (previous_distance / (previous_distance - distance))
            inside.points[inside.count] = intersection
            outside.points[outside.count] = intersection
            inside.count += 1
            outside.count += 1
        }
        if distance >= 0 {
            inside.points[inside.count] = current
            inside.count += 1
        }
        if distance <= 0 {
            outside.points[outside.count] = current
            outside.count += 1
        }
        previous, previous_distance = current, distance
    }
}

// shadow_mesh_append triangulates one convex fragment into caller-owned storage.
shadow_mesh_append :: proc(
    mesh: ^Shadow_Fragment_Mesh, polygon: Shadow_Clip_Polygon) {
    for index in 1..<polygon.count - 1 {
        first := polygon.points[0]
        second := polygon.points[index]
        third := polygon.points[index + 1]
        edge := second - first
        other := third - first
        if edge.x * other.y - edge.y * other.x == 0 {
            continue
        }
        assert(mesh.count + 3 <= len(mesh.points))
        mesh.points[mesh.count] = first
        mesh.points[mesh.count + 1] = second
        mesh.points[mesh.count + 2] = third
        mesh.count += 3
    }
}

// shadow_ground_fragment clips a shifted ground polygon against board occlusion.
shadow_ground_fragment :: proc(
    receivers: Shadow_Receiver_Geometry, polygon: Shadow_Clip_Polygon,
    mesh: ^Shadow_Fragment_Mesh) {
    remaining := polygon
    for index in 0..<remaining.count {
        remaining.points[index] += receivers.ground_offset
    }
    for edge in 0..<4 {
        inside, outside: Shadow_Clip_Polygon
        shadow_clip_edge(remaining, {receivers.board[edge],
            receivers.board[(edge + 1) % 4], receivers.winding}, &inside, &outside)
        shadow_mesh_append(mesh, outside)
        remaining = inside
    }
}

// shadow_partition_triangle splits coverage onto the board and visible ground.
shadow_partition_triangle :: proc(
    receivers: Shadow_Receiver_Geometry, triangle: [3]geometry.Vector2,
    mesh: ^Shadow_Fragment_Mesh) {
    mesh.count = 0
    remaining: Shadow_Clip_Polygon = {
        count = 3,
    }
    for point, index in triangle {
        remaining.points[index] = point
    }
    for edge in 0..<4 {
        inside, outside: Shadow_Clip_Polygon
        shadow_clip_edge(remaining, {receivers.board[edge],
            receivers.board[(edge + 1) % 4], receivers.winding}, &inside, &outside)
        shadow_ground_fragment(receivers, outside, mesh)
        remaining = inside
    }
    shadow_mesh_append(mesh, remaining)
}

// shadow_vertex_on_board tests the complete projected board including its border.
shadow_vertex_on_board :: proc(
    receivers: Shadow_Receiver_Geometry, point: geometry.Vector2) -> bool {
    for edge in 0..<4 {
        if shadow_edge_distance(point, receivers.board[edge],
            receivers.board[(edge + 1) % 4], receivers.winding) < 0 {
            return false
        }
    }
    return true
}

// shadow_copy_board_pass preserves the existing compact topology for on-board shadows.
shadow_copy_board_pass :: proc(
    target, source: ^native.Draw_Encoder,
    receivers: Shadow_Receiver_Geometry) -> bool {
    for vertex in source.vertices[:source.vertex_count] {
        if !shadow_vertex_on_board(receivers, vertex.position) {
            return false
        }
    }
    if source.vertex_count == 0 {
        return true
    }
    if target.vertex_count + source.vertex_count > len(target.vertices) ||
        target.index_count + source.index_count > len(target.indices) {
        return false
    }
    batch, ready := native.draw_encoder_prepare(target,
        source.vertex_count, source.index_count, {
            pipeline = .Colored,
        })
    if !ready {
        return false
    }
    base := u32(target.vertex_count)
    copy(target.vertices[target.vertex_count:], source.vertices[:source.vertex_count])
    for index in 0..<source.index_count {
        target.indices[target.index_count + index] = base + source.indices[index]
    }
    target.vertex_count += source.vertex_count
    target.index_count += source.index_count
    batch.index_count += u32(source.index_count)
    target.statistics.vertices = u32(target.vertex_count)
    target.statistics.indices = u32(target.index_count)
    return true
}

// shadow_submit_fragment atomically admits one source triangle's split coverage.
shadow_submit_fragment :: proc(
    target: ^native.Draw_Encoder, mesh: ^Shadow_Fragment_Mesh,
    tint: native.Draw_Vertex) {
    if mesh.count == 0 {
        return
    }
    batch, ready := native.draw_encoder_prepare(target, mesh.count, mesh.count, {
        pipeline = .Colored,
    })
    if !ready {
        return
    }
    base := u32(target.vertex_count)
    for point, index in mesh.points[:mesh.count] {
        vertex := tint
        vertex.position = point
        target.vertices[target.vertex_count + index] = vertex
        target.indices[target.index_count + index] = base + u32(index)
    }
    target.vertex_count += mesh.count
    target.index_count += mesh.count
    batch.index_count += u32(mesh.count)
    target.statistics.vertices = u32(target.vertex_count)
    target.statistics.indices = u32(target.index_count)
}

// shadow_triangle_on_board classifies all three vertices of one encoded triangle.
shadow_triangle_on_board :: proc(
    source: ^native.Draw_Encoder, index: int,
    receivers: Shadow_Receiver_Geometry) -> bool {
    for offset in 0..<3 {
        vertex := source.vertices[source.indices[index + offset]]
        if !shadow_vertex_on_board(receivers, vertex.position) {
            return false
        }
    }
    return true
}

// shadow_share_board_vertices preserves indexed topology for a mostly on-board pass.
shadow_share_board_vertices :: proc(
    target, source: ^native.Draw_Encoder,
    receivers: Shadow_Receiver_Geometry) -> (u32, bool) {
    if target.vertex_count + source.vertex_count > len(target.vertices) {
        return 0, false
    }
    board_triangles := 0
    for index := 0; index < source.index_count; index += 3 {
        if shadow_triangle_on_board(source, index, receivers) {
            board_triangles += 1
        }
    }
    if board_triangles * 6 <= source.index_count {
        return 0, false
    }
    _, ready := native.draw_encoder_prepare(target, source.vertex_count, 0, {
        pipeline = .Colored,
    })
    if !ready {
        return 0, false
    }
    base := u32(target.vertex_count)
    copy(target.vertices[target.vertex_count:], source.vertices[:source.vertex_count])
    target.vertex_count += source.vertex_count
    target.statistics.vertices = u32(target.vertex_count)
    return base, true
}

// shadow_submit_shared_triangle appends one board triangle using copied source vertices.
shadow_submit_shared_triangle :: proc(
    target, source: ^native.Draw_Encoder, index: int, base: u32) {
    batch, ready := native.draw_encoder_prepare(target, 0, 3, {
        pipeline = .Colored,
    })
    if !ready {
        return
    }
    for offset in 0..<3 {
        target.indices[target.index_count + offset] =
            base + source.indices[index + offset]
    }
    target.index_count += 3
    batch.index_count += 3
    target.statistics.indices = u32(target.index_count)
}

// shadow_submit_receivers clips an encoded shadow pass while retaining painter order.
shadow_submit_receivers :: proc(
    target, source: ^native.Draw_Encoder, receivers: Shadow_Receiver_Geometry) {
    target.statistics.primitive_overflows += source.statistics.primitive_overflows
    target.statistics.curve_candidate_points += source.statistics.curve_candidate_points
    target.statistics.curve_retained_points += source.statistics.curve_retained_points
    if shadow_copy_board_pass(target, source, receivers) {
        return
    }
    shared_base, shared := shadow_share_board_vertices(target, source, receivers)
    for index := 0; index < source.index_count; index += 3 {
        if shared && shadow_triangle_on_board(source, index, receivers) {
            shadow_submit_shared_triangle(target, source, index, shared_base)
            continue
        }
        first := source.vertices[source.indices[index]]
        second := source.vertices[source.indices[index + 1]]
        third := source.vertices[source.indices[index + 2]]
        mesh: Shadow_Fragment_Mesh
        shadow_partition_triangle(receivers,
            {first.position, second.position, third.position}, &mesh)
        shadow_submit_fragment(target, &mesh, first)
    }
}
