package native

import "core:math"

import color "../../core/color"
import geometry "../../core/geometry"

DRAW_SHADOW_RING_COUNT :: 5
DRAW_SHADOW_VERTEX_COUNT :: DRAW_SHADOW_RING_COUNT * 4
DRAW_SHADOW_INDICES_PER_RING :: 4 * 6
DRAW_SHADOW_INDEX_COUNT :: (DRAW_SHADOW_RING_COUNT - 1) *
    DRAW_SHADOW_INDICES_PER_RING

// Draw_Shadow_Style contains geometry and opacity only, not elevation policy.
Draw_Shadow_Style :: struct {
    contact_offset: geometry.Vector2,
    cast_offset: geometry.Vector2,
    feather: f32,
    contact_opacity: f32,
    cast_opacity: f32,
    tint: color.Color_RGBA8,
}

// Draw_Shadow_Ring describes one fixed boundary in the shadow mesh.
Draw_Shadow_Ring :: struct {
    offset: geometry.Vector2,
    expansion: f32,
    opacity: f32,
}

// Draw_Shadow_Mesh holds the complete fixed topology before encoder admission.
Draw_Shadow_Mesh :: struct {
    positions: [DRAW_SHADOW_VERTEX_COUNT]geometry.Vector2,
    opacities: [DRAW_SHADOW_VERTEX_COUNT]f32,
    indices: [DRAW_SHADOW_INDEX_COUNT]u32,
}

// draw_shadow_finite_value rejects non-finite geometry inputs.
draw_shadow_finite_value :: #force_inline proc(value: f32) -> bool {
    return !math.is_nan(value) && !math.is_inf(value)
}

// draw_shadow_finite_point rejects coordinates that cannot form GPU vertices.
draw_shadow_finite_point :: #force_inline proc(point: geometry.Vector2) -> bool {
    return draw_shadow_finite_value(point.x) &&
        draw_shadow_finite_value(point.y)
}

// draw_shadow_ring_bounds offsets support down-right with a finite feather.
draw_shadow_ring_bounds :: #force_inline proc(
    bounds: geometry.Rectangle, offset: geometry.Vector2, expansion: f32) ->
    geometry.Rectangle {
    return {
        bounds.x - expansion,
        bounds.y - expansion,
        bounds.width + offset.x + expansion * 2,
        bounds.height + offset.y + expansion * 2,
    }
}

// draw_shadow_mesh_write_ring assigns one complete rectangular boundary.
draw_shadow_mesh_write_ring :: proc(
    bounds: geometry.Rectangle, ring_style: Draw_Shadow_Ring,
    ring_index: int, mesh: ^Draw_Shadow_Mesh) -> bool {
    ring := draw_shadow_ring_bounds(
        bounds, ring_style.offset, ring_style.expansion)
    corners := [4]geometry.Vector2{}
    corners = {
        {ring.x, ring.y},
        {ring.x + ring.width, ring.y},
        {ring.x + ring.width, ring.y + ring.height},
        {ring.x, ring.y + ring.height},
    }
    for corner, corner_index in corners {
        if !draw_shadow_finite_point(corner) {
            return false
        }
        vertex_index := ring_index * 4 + corner_index
        mesh.positions[vertex_index] = corner
        mesh.opacities[vertex_index] = ring_style.opacity
    }
    return true
}

// draw_shadow_mesh_write_rings creates welded position and opacity rings.
draw_shadow_mesh_write_rings :: proc(
    bounds: geometry.Rectangle, style: Draw_Shadow_Style,
    mesh: ^Draw_Shadow_Mesh) -> bool {
    base_expansion := min(style.contact_offset.x, style.contact_offset.y) * 0.25
    rings := [DRAW_SHADOW_RING_COUNT]Draw_Shadow_Ring{
        {opacity = 0},
        {style.contact_offset, base_expansion, style.contact_opacity},
        {style.cast_offset, base_expansion * 2, style.cast_opacity},
        {style.cast_offset, base_expansion * 2 + style.feather * 0.5,
            style.cast_opacity * 0.5},
        {style.cast_offset, base_expansion * 2 + style.feather, 0},
    }
    for ring_index in 0..<DRAW_SHADOW_RING_COUNT {
        if !draw_shadow_mesh_write_ring(
            bounds, rings[ring_index], ring_index, mesh) {
            return false
        }
    }
    return true
}

// draw_shadow_mesh_write_indices welds neighboring rings without overlapping faces.
draw_shadow_mesh_write_indices :: proc(mesh: ^Draw_Shadow_Mesh) {
    for ring_index in 0..<DRAW_SHADOW_RING_COUNT - 1 {
        for corner_index in 0..<4 {
            next_corner := (corner_index + 1) % 4
            inner_a := u32(ring_index * 4 + corner_index)
            inner_b := u32(ring_index * 4 + next_corner)
            outer_a := u32((ring_index + 1) * 4 + corner_index)
            outer_b := u32((ring_index + 1) * 4 + next_corner)
            index := (ring_index * 4 + corner_index) * 6
            mesh.indices[index] = inner_a
            mesh.indices[index + 1] = inner_b
            mesh.indices[index + 2] = outer_b
            mesh.indices[index + 3] = inner_a
            mesh.indices[index + 4] = outer_b
            mesh.indices[index + 5] = outer_a
        }
    }
}

// draw_shadow_mesh_build creates valid welded rings with zero-alpha outer edges.
draw_shadow_mesh_build :: proc(
    bounds: geometry.Rectangle, style: Draw_Shadow_Style,
    mesh: ^Draw_Shadow_Mesh) -> bool {
    if mesh == nil || bounds.width <= 0 || bounds.height <= 0 ||
        !draw_shadow_finite_point({bounds.x, bounds.y}) ||
        !draw_shadow_finite_point({
            bounds.x + bounds.width, bounds.y + bounds.height}) ||
        !draw_shadow_finite_value(bounds.width) ||
        !draw_shadow_finite_value(bounds.height) ||
        !draw_shadow_finite_point(style.contact_offset) ||
        !draw_shadow_finite_point(style.cast_offset) ||
        !draw_shadow_finite_value(style.feather) || style.feather <= 0 ||
        style.contact_offset.x <= 0 || style.contact_offset.y <= 0 ||
        style.cast_offset.x <= style.contact_offset.x ||
        style.cast_offset.y <= style.contact_offset.y ||
        !draw_shadow_finite_value(style.contact_opacity) ||
        !draw_shadow_finite_value(style.cast_opacity) ||
        style.contact_opacity < 0 || style.contact_opacity > 1 ||
        style.cast_opacity < 0 || style.cast_opacity > 1 {
        return false
    }
    if !draw_shadow_mesh_write_rings(bounds, style, mesh) {
        return false
    }
    draw_shadow_mesh_write_indices(mesh)
    return true
}

// draw_encoder_shadow atomically admits the complete bounded UI shadow mesh.
draw_encoder_shadow :: proc(
    encoder: ^Draw_Encoder, bounds: geometry.Rectangle,
    style: Draw_Shadow_Style) -> bool {
    if encoder == nil {
        return false
    }
    mesh: Draw_Shadow_Mesh
    if !draw_shadow_mesh_build(bounds, style, &mesh) {
        return false
    }
    batch, ready := draw_encoder_prepare(
        encoder, DRAW_SHADOW_VERTEX_COUNT, DRAW_SHADOW_INDEX_COUNT,
        {pipeline = .Colored})
    if !ready {
        return false
    }

    base_vertex := u32(encoder^.vertex_count)
    for position, offset in mesh.positions {
        vertex_color := style.tint
        vertex_color[3] = u8(clamp(int(math.round(
            f64(style.tint[3]) * f64(mesh.opacities[offset]))), 0, 255))
        encoder^.vertices[encoder^.vertex_count + offset] = {
            position = position, color = vertex_color}
    }
    for relative_index, offset in mesh.indices {
        encoder^.indices[encoder^.index_count + offset] =
            base_vertex + relative_index
    }
    encoder^.vertex_count += DRAW_SHADOW_VERTEX_COUNT
    encoder^.index_count += DRAW_SHADOW_INDEX_COUNT
    batch^.index_count += DRAW_SHADOW_INDEX_COUNT
    encoder^.statistics.vertices = u32(encoder^.vertex_count)
    encoder^.statistics.indices = u32(encoder^.index_count)
    return true
}
