package shapes

import "core:testing"

import "../core"
import test_helpers "../test_helpers"

// Create one transform-bearing world point for constraint tests.
world_constraint_test_point :: proc(
    world: ^core.Shape_World,
    position: Vector3) -> core.Shape_Entity {
    point, status := world_create_point(world, position, Shape_Style{})
    assert(status == .Ok)
    return point.entity
}

// Resolve one tested transform position after checked world construction.
world_constraint_test_position :: proc(
    world: ^core.Shape_World,
    entity: core.Shape_Entity) -> Vector3 {
    transform, found := core.shape_component_get(
        &world.transforms, &world.registry, entity)
    assert(found)
    return transform.position
}

// Verify one world distance correction against its expected endpoint positions.
world_constraint_test_distance_parity_case :: proc(
    t: ^testing.T,
    movement: core.Shape_Constraint_Movement_Policy,
    expected_first, expected_second: Vector3) {
    world: core.Shape_World
    first := world_constraint_test_point(&world, {-1, 0, 0})
    second := world_constraint_test_point(&world, {1, 0, 0})
    _, status := world_create_distance_constraint(&world, {
        first = first, second = second, length = 6,
        movement = movement, enabled = true})
    testing.expect_value(t, status, core.Shape_World_Status.Ok)
    world_apply_all_constraints(&world)

    test_helpers.expect_vec3_close(t, world_constraint_test_position(&world, first),
        expected_first, "first endpoint")
    test_helpers.expect_vec3_close(t, world_constraint_test_position(&world, second),
        expected_second, "second endpoint")
}

// Verify explicit movement policies produce deterministic distance correction.
@(test)
world_constraints_distance_solver_matches_legacy :: proc(t: ^testing.T) {
    world_constraint_test_distance_parity_case(t, .Move_First, {-5, 0, 0}, {1, 0, 0})
    world_constraint_test_distance_parity_case(t, .Move_Both, {-3, 0, 0}, {3, 0, 0})
    world_constraint_test_distance_parity_case(t, .Move_Second, {-1, 0, 0}, {5, 0, 0})
}

// Verify constraint creation rejects stale and non-transform targets transactionally.
@(test)
world_constraints_reject_invalid_targets_without_append :: proc(t: ^testing.T) {
    world: core.Shape_World
    baseline := world_constraint_test_point(&world, {})
    testing.expect_value(t, core.shape_world_freeze_baseline(
        &world), core.Shape_World_Status.Ok)
    stale := world_constraint_test_point(&world, {1, 0, 0})
    testing.expect_value(t, core.shape_world_rewind_animation(
        &world), core.Shape_World_Status.Ok)
    before := world.constraints.count

    _, stale_status := world_create_distance_constraint(&world, {
        first = baseline, second = stale, length = 1, enabled = true})
    host, host_status := world_create_line(
        &world, {}, {1, 0, 0}, Shape_Style{})
    _, host_target_status := world_create_floor_constraint(&world, {
        point = host.shape, enabled = true})

    testing.expect_value(t, stale_status, core.Shape_World_Status.Not_Found)
    testing.expect_value(t, host_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, host_target_status, core.Shape_World_Status.Not_Found)
    testing.expect_value(t, world.constraints.count, before)
}

// Verify a retained constraint value cannot mutate a reused target slot.
@(test)
world_constraints_stale_target_is_safe_at_solve_time :: proc(t: ^testing.T) {
    world: core.Shape_World
    baseline := world_constraint_test_point(&world, {})
    testing.expect_value(t, core.shape_world_freeze_baseline(
        &world), core.Shape_World_Status.Ok)
    stale := world_constraint_test_point(&world, {1, 0, 0})
    constraint := core.Shape_Constraint{kind = .Snap_Point, enabled = true}
    constraint.payload.snap_point = {point = stale, position = {9, 0, 0}}
    testing.expect_value(t, core.shape_world_rewind_animation(
        &world), core.Shape_World_Status.Ok)
    current := world_constraint_test_point(&world, {2, 0, 0})

    testing.expect_value(t, current.slot, stale.slot)
    testing.expect(t, current.generation != stale.generation)
    testing.expect_value(t, world_constraint_error(&world, &constraint), f32(0))
    world_apply_constraint(&world, &constraint)
    testing.expect_value(t, world_constraint_test_position(&world, current),
        Vector3{2, 0, 0})
    testing.expect(t, core.shape_registry_resolves(&world.registry, baseline))
}

// Verify stable insertion order is preserved in both traversal directions.
@(test)
world_constraints_preserve_forward_and_reverse_order :: proc(t: ^testing.T) {
    world: core.Shape_World
    point := world_constraint_test_point(&world, {})
    _, first_status := world_create_snap_point_constraint(&world, {
        point = point, position = {1, 0, 0}, enabled = true})
    _, second_status := world_create_snap_point_constraint(&world, {
        point = point, position = {2, 0, 0}, enabled = true})
    testing.expect_value(t, first_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, second_status, core.Shape_World_Status.Ok)

    world_apply_all_constraints(&world)
    testing.expect_value(t, world_constraint_test_position(&world, point),
        Vector3{2, 0, 0})
    world_apply_all_constraints_reverse(&world)
    testing.expect_value(t, world_constraint_test_position(&world, point),
        Vector3{1, 0, 0})
}

// Verify alternating solve passes converge a direct floor snap to zero error.
@(test)
world_constraints_solve_to_allowed_error :: proc(t: ^testing.T) {
    world: core.Shape_World
    point := world_constraint_test_point(&world, {0, 0, -2})
    _, status := world_create_snap_to_floor_constraint(&world, {
        point = point, height = 0, allowance = 0.01, enabled = true})
    testing.expect_value(t, status, core.Shape_World_Status.Ok)
    testing.expect_value(t, world_total_constraint_error(&world), f32(2))

    world_apply_all_constraints_to_error(&world, 0)

    testing.expect_value(t, world_total_constraint_error(&world), f32(0))
    testing.expect_value(t, world_constraint_test_position(&world, point), Vector3{})
}

// Verify contradictory constraints exhaust bounded work instead of blocking a frame.
@(test)
world_constraints_nonconvergent_solve_is_bounded :: proc(t: ^testing.T) {
    world: core.Shape_World
    point := world_constraint_test_point(&world, {})
    _, first_status := world_create_snap_point_constraint(&world, {
        point = point, position = {1, 0, 0}, enabled = true})
    _, second_status := world_create_snap_point_constraint(&world, {
        point = point, position = {2, 0, 0}, enabled = true})
    testing.expect_value(t, first_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, second_status, core.Shape_World_Status.Ok)

    world_apply_all_constraints_to_error(&world, 0)

    testing.expect(t, world_total_constraint_error(&world) > 0)
}

// Verify locked compass tips converge to a hinge above the drawing plane.
@(test)
world_constraints_compass_locks_keep_hinge_above_floor :: proc(t: ^testing.T) {
    world: core.Shape_World
    compass, status := world_create_compass(&world, {
        joint1 = {0, 0, 0}, pivot = {0.01, 0.01, 0.01},
        joint2 = {0.02, 0.02, 0}, limb_length = 0.35,
        style = Shape_Style{}})
    testing.expect_value(t, status, core.Shape_World_Status.Ok)
    for iteration in 0..<64 {
        if iteration & 1 == 0 {
            world_apply_all_constraints_reverse(&world)
        } else {
            world_apply_all_constraints(&world)
        }
    }
    first_lock := &world.constraints.values[compass.joint1_lock_constraint]
    first_lock^.payload.snap_point.position = {0.5, 0.5, 1.4}
    first_lock^.enabled = true
    second_lock := &world.constraints.values[compass.joint2_lock_constraint]
    second_lock^.payload.snap_point.position = {0.75, 0.5, 1.4}
    second_lock^.enabled = true

    for iteration in 0..<64 {
        if iteration & 1 == 0 {
            world_apply_all_constraints_reverse(&world)
        } else {
            world_apply_all_constraints(&world)
        }
    }
    pivot := world_constraint_test_position(&world, compass.pivot)

    testing.expect(t, pivot.z > 1.4)
    testing.expect(t, world_total_constraint_error(&world) <= 0.0001)
}

// Verify only angle kinds can consume the statically three-target angle input.
@(test)
world_constraints_reject_non_angle_kind_for_angle_payload :: proc(t: ^testing.T) {
    world: core.Shape_World
    first := world_constraint_test_point(&world, {1, 0, 0})
    pivot := world_constraint_test_point(&world, {})
    second := world_constraint_test_point(&world, {0, 1, 0})
    _, status := world_create_angle_constraint(&world, .Distance, {
        first = first, pivot = pivot, second = second,
        limit = 1, enabled = true})

    testing.expect_value(t, status, core.Shape_World_Status.Invalid_Argument)
    testing.expect_value(t, world.constraints.count, u16(0))
}

// Verify animation rewind restores the frozen ordered constraint prefix.
@(test)
world_constraints_rewind_to_baseline_frontier :: proc(t: ^testing.T) {
    world: core.Shape_World
    first := world_constraint_test_point(&world, {})
    second := world_constraint_test_point(&world, {1, 0, 0})
    _, baseline_status := world_create_distance_constraint(&world, {
        first = first, second = second, length = 1, enabled = true})
    testing.expect_value(t, baseline_status, core.Shape_World_Status.Ok)
    testing.expect_value(t, core.shape_world_freeze_baseline(
        &world), core.Shape_World_Status.Ok)
    animation := world_constraint_test_point(&world, {2, 0, 0})
    _, animation_status := world_create_distance_constraint(&world, {
        first = second, second = animation, length = 1, enabled = true})
    testing.expect_value(t, animation_status, core.Shape_World_Status.Ok)

    testing.expect_value(t, core.shape_world_rewind_animation(
        &world), core.Shape_World_Status.Ok)
    testing.expect_value(t, world.constraints.count, u16(1))
    testing.expect_value(t, world.constraints.values[0].payload.distance.first, first)
}