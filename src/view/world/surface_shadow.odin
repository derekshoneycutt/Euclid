package world

import native "../native"
import geometry "../../core/geometry"
import worldmodel "model"
import projection "projection"

SURFACE_SHADOW_RECEIVER_HEIGHT :: f32(-0.02)
SURFACE_SHADOW_INDEX_COUNT :: native.DRAW_SHADOW_INDEX_COUNT + 6

// Surface_Shadow_Mesh is frame-local fixed storage; no shadow heap or GPU resource is owned.
Surface_Shadow_Mesh :: struct {
    vertices: [native.DRAW_SHADOW_VERTEX_COUNT]native.Draw_Vertex,
    indices: [SURFACE_SHADOW_INDEX_COUNT]u32,
}

// build_surface_shadow_mesh projects a filled, feathered board silhouette below z = 0.
build_surface_shadow_mesh :: proc(
    surface: worldmodel.Euclid_Drawing_Surface, scale: worldmodel.Iso_Scale,
    mesh: ^Surface_Shadow_Mesh) {
    expansions: [native.DRAW_SHADOW_RING_COUNT]f32 = {0, 0.005, 0.012, 0.02, 0.03}
    alphas: [native.DRAW_SHADOW_RING_COUNT]u8 = {170, 145, 85, 25, 0}
    corners: [4]geometry.Vector3 = {
        surface.zeros, surface.right_up, surface.right_down, surface.left_down}
    directions: [4]geometry.Vector3 = {{-1, -1, 0}, {1, -1, 0}, {1, 1, 0}, {-1, 1, 0}}
    for expansion, ring in expansions {
        for corner, index in corners {
            receiver := project_to_floor_shadow(
                corner + directions[index] * expansion, scale,
                SURFACE_SHADOW_RECEIVER_HEIGHT)
            mesh^.vertices[ring * 4 + index] = {
                position = projection.iso_to_cartesian(receiver, scale),
                color = {0, 0, 0, alphas[ring]},
            }
        }
    }
    topology: native.Draw_Shadow_Mesh
    native.draw_shadow_mesh_write_indices(&topology)
    copy(mesh^.indices[:], topology.indices[:])
    center: [6]u32 = {0, 1, 2, 0, 2, 3}
    copy(mesh^.indices[native.DRAW_SHADOW_INDEX_COUNT:], center[:])
}

// draw_encoded_surface_shadow atomically admits the world-clipped shadow before the board.
draw_encoded_surface_shadow :: proc(
    encoder: ^native.Draw_Encoder, surface: worldmodel.Euclid_Drawing_Surface,
    scale: worldmodel.Iso_Scale) -> bool {
    mesh: Surface_Shadow_Mesh
    build_surface_shadow_mesh(surface, scale, &mesh)
    batch, ready := native.draw_encoder_prepare(
        encoder, len(mesh.vertices), len(mesh.indices), {pipeline = .Colored})
    if !ready {
        return false
    }
    base_vertex := u32(encoder^.vertex_count)
    copy(encoder^.vertices[encoder^.vertex_count:], mesh.vertices[:])
    for index, offset in mesh.indices {
        encoder^.indices[encoder^.index_count + offset] = base_vertex + index
    }
    encoder^.vertex_count += len(mesh.vertices)
    encoder^.index_count += len(mesh.indices)
    batch^.index_count += u32(len(mesh.indices))
    encoder^.statistics.vertices = u32(encoder^.vertex_count)
    encoder^.statistics.indices = u32(encoder^.index_count)
    return true
}
