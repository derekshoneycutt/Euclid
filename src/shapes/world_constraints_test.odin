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

// Compare one world distance correction with the matching legacy policy result.
world_constraint_test_distance_parity_case :: proc(
    t: ^testing.T,
    movement: core.Shape_Constraint_Movement_Policy,
    depend_on: i32) {
    legacy_first := make_point(-1, 0, 0)
    legacy_second := make_point(1, 0, 0)
    legacy := make_distance_constraint(depend_on, 6)
    apply_constraint_distance(&legacy, &legacy_first, &legacy_second)

    world: core.Shape_World
    first := world_constraint_test_point(&world, {-1, 0, 0})
    second := world_constraint_test_point(&world, {1, 0, 0})
    _, status := world_create_distance_constraint(&world, {
        first = first, second = second, length = 6,
        movement = movement, enabled = true})
    testing.expect_value(t, status, core.Shape_World_Status.Ok)
    world_apply_all_constraints(&world)

    test_helpers.expect_vec3_close(t, world_constraint_test_position(&world, first),
        legacy_first.position.? or_else Vector3{}, "first endpoint parity")
    test_helpers.expect_vec3_close(t, world_constraint_test_position(&world, second),
        legacy_second.position.? or_else Vector3{}, "second endpoint parity")
}

// Verify explicit movement policies preserve legacy distance correction behavior.
@(test)
world_constraints_distance_solver_matches_legacy :: proc(t: ^testing.T) {
    world_constraint_test_distance_parity_case(t, .Move_First, 1)
    world_constraint_test_distance_parity_case(t, .Move_Both, 0)
    world_constraint_test_distance_parity_case(t, .Move_Second, -1)
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