package shapes

import shapemodel "model"
import "core:math/linalg"
import "core:log"

// Hold an orthonormal endpoint frame without duplicating canonical point authority.
World_Endpoint_Plane_Basis :: struct {
    tangent, transverse: Vector3,
    valid: bool,
}

// Resolve a host's plane rotation; tool-only or manually assembled packets remain XY.
world_lerped_orientation :: proc(
    world: ^shapemodel.Shape_World, entity: shapemodel.Shape_Entity,
    alpha: f32) -> quaternion128 {
    value, found := shapemodel.shape_component_get(
        &world.orientations, &world.registry, entity)
    if !found {
        return 1
    }
    return linalg.normalize(linalg.quaternion_slerp(
        value.previous_orientation, value.orientation, alpha))
}

// Map already sampled intrinsic geometry around its authoritative world anchor.
world_pose_curve_vertices :: proc(
    world: ^shapemodel.Shape_World, entity: shapemodel.Shape_Entity,
    alpha: f32, anchor: Vector3, vertices: []Vector3) {
    q := world_lerped_orientation(world, entity, alpha)
    for &point in vertices {
        point = anchor + linalg.mul(q, point - anchor)
    }
}

// Resolve an endpoint-driven display frame without replacing its defining positions.
world_endpoint_plane_basis :: proc(
    world: ^shapemodel.Shape_World, entity: shapemodel.Shape_Entity,
    alpha: f32, first, second: Vector3) -> World_Endpoint_Plane_Basis {
    delta := second - first
    if linalg.dot(delta, delta) <= 0.0000000001 {
        return {}
    }
    tangent := linalg.normalize(delta)
    q := world_lerped_orientation(world, entity, alpha)
    normal := linalg.mul(q, Vector3{0, 0, 1})
    transverse := linalg.cross(normal, tangent)
    if linalg.dot(transverse, transverse) < 0.0000000001 {
        transverse = linalg.mul(q, Vector3{0, 1, 0})
        transverse -= tangent * linalg.dot(transverse, tangent)
    }
    if linalg.dot(transverse, transverse) < 0.0000000001 {
        transverse = linalg.mul(q, Vector3{1, 0, 0})
        transverse -= tangent * linalg.dot(transverse, tangent)
    }
    return {tangent, linalg.normalize(transverse), true}
}

// Map local endpoint-defined geometry into its interpolated plane.
world_pose_endpoint_vertices :: proc(
    world: ^shapemodel.Shape_World, entity: shapemodel.Shape_Entity,
    alpha: f32, endpoints: [2]Vector3, vertices: []Vector3) -> bool {
    basis := world_endpoint_plane_basis(
        world, entity, alpha, endpoints[0], endpoints[1])
    if !basis.valid {
        log.errorf("shape_endpoint_plane_degenerate slot=%d generation=%d",
            entity.slot, entity.generation)
        return false
    }
    for &point in vertices {
        point = endpoints[0] + basis.tangent * point.x + basis.transverse * point.y
    }
    return true
}
