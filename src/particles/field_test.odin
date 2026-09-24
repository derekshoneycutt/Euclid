package particles

import particlemodel "model"
import geometry "../core/geometry"

import "core:testing"

import test_helpers "../test_helpers"

// Sum all four weights in one vector-dust transfer stencil.
dust_test_weight_sum :: proc(stencil: Dust_Field_Stencil) -> f32 {
    result: f32
    for weight in stencil.weights {
        result += weight
    }
    return result
}

// Sum one complete scalar field plane.
dust_test_plane_sum :: proc(plane: ^particlemodel.Dust_Field_Scalar) -> f32 {
    result: f32
    for value in plane^ {
        result += value
    }
    return result
}

// Verify interior bilinear support preserves one complete contribution.
@(test)
dust_interior_weights_sum_to_one :: proc(t: ^testing.T) {
    stencil := dust_field_stencil({0.347, 0.612})

    test_helpers.expect_close(t, dust_test_weight_sum(stencil), 1,
        "interior stencil should preserve unit weight")
}

// Verify board corners preserve one contribution and valid node indices.
@(test)
dust_corner_weights_and_indices_are_valid :: proc(t: ^testing.T) {
    corners := [4]geometry.Vector2{{0, 0}, {1, 0}, {0, 1}, {1, 1}}
    for corner in corners {
        stencil := dust_field_stencil(corner)
        test_helpers.expect_close(t, dust_test_weight_sum(stencil), 1,
            "corner stencil should preserve unit weight")
        for node in stencil.indices {
            testing.expect(t, node >= 0 && node < i32(DUST_FIELD_NODE_COUNT))
        }
    }
}

// Verify compact transfer coordinates retain slot identity and bilinear position.
@(test)
dust_transfer_caches_compact_coordinates :: proc(t: ^testing.T) {
    transfer := dust_field_transfer({0.347, 0.612}, 37)

    testing.expect_value(t, transfer.particle_index, i32(37))
    testing.expect_value(t, transfer.base_node, i32(153 * DUST_FIELD_DIM + 86))
    test_helpers.expect_close(t, transfer.fraction_x, 0.75, "transfer fraction x")
    test_helpers.expect_close(t, transfer.fraction_y, 0, "transfer fraction y")
    stencil := dust_field_transfer_stencil(transfer)
    test_helpers.expect_close(t, dust_test_weight_sum(stencil), 1,
        "cached transfer should preserve unit weight")
}

// Verify one transfer conserves unit density and both momentum components.
@(test)
dust_deposit_conserves_density_and_momentum :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)

    dust_field_deposit(field, {0.347, 0.612}, {2.5, -1.25})

    test_helpers.expect_close(t, dust_test_plane_sum(&field^.density), 1,
        "deposited density")
    test_helpers.expect_close(t, dust_test_plane_sum(&field^.momentum_x), 2.5,
        "deposited x momentum")
    test_helpers.expect_close(t, dust_test_plane_sum(&field^.momentum_y), -1.25,
        "deposited y momentum")
}

// Verify boundary transfer does not lose density or momentum.
@(test)
dust_boundary_deposit_is_conservative :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)

    dust_field_deposit(field, {1, 1}, {0.75, -0.5})

    test_helpers.expect_close(t, dust_test_plane_sum(&field^.density), 1,
        "boundary density")
    test_helpers.expect_close(t, dust_test_plane_sum(&field^.momentum_x), 0.75,
        "boundary x momentum")
    test_helpers.expect_close(t, dust_test_plane_sum(&field^.momentum_y), -0.5,
        "boundary y momentum")
}

// Verify tool force adds density-weighted radial momentum without changing density.
@(test)
dust_tool_point_adds_density_weighted_momentum :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    center := 125 * DUST_FIELD_DIM + 125
    right := center + 1
    field^.density[center] = 3
    field^.density[right] = 2
    field^.support_bounds = {125, 125, 126, 125, true}

    visits := dust_field_apply_tool_point(field, {0.5, 0.5})

    testing.expect_value(t, visits, u64(2))
    testing.expect_value(t, field^.momentum_x[center], f32(0))
    testing.expect_value(t, field^.momentum_y[center], f32(0))
    test_helpers.expect_close(t, field^.momentum_x[right], f32(0.0042),
        "density-weighted radial x momentum")
    testing.expect_value(t, field^.momentum_y[right], f32(0))
    testing.expect_value(t, field^.density[center], f32(3))
    testing.expect_value(t, field^.density[right], f32(2))

    field^.density[right + 1] = 1
    field^.momentum_x[right + 1] = field^.momentum_x[right] / 2
    dust_field_normalize(field, {126, 125, 127, 125, true})
    test_helpers.expect_close(t, field^.momentum_x[right],
        field^.momentum_x[right + 1], "density-independent velocity increment")
}

// Verify overlapping tool samples accumulate momentum in command order.
@(test)
dust_tool_points_accumulate_overlaps :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    node := 125 * DUST_FIELD_DIM + 126
    field^.density[node] = 1
    field^.support_bounds = {126, 125, 126, 125, true}

    _ = dust_field_apply_tool_point(field, {0.5, 0.5})
    first_momentum := field^.momentum_x[node]
    _ = dust_field_apply_tool_point(field, {0.5, 0.5})

    test_helpers.expect_close(t, field^.momentum_x[node], 2 * first_momentum,
        "overlapping tool momentum")
}

// Verify authored sweep motion affects an occupied node exactly under its sample.
@(test)
dust_tool_motion_pushes_exact_center_in_authored_direction :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    center := 125 * DUST_FIELD_DIM + 125
    field^.density[center] = 2
    field^.support_bounds = {125, 125, 125, 125, true}

    visits := dust_field_apply_tool_motion(field, {0.5, 0.5}, {0, 0.1})

    testing.expect_value(t, visits, u64(1))
    testing.expect_value(t, field^.momentum_x[center], f32(0))
    testing.expect(t, field^.momentum_y[center] > 0)
}

// Verify tool force is bounded by occupied support and ignores empty nodes.
@(test)
dust_tool_point_respects_support_and_zero_density :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    field^.support_bounds = {0, 0, 2, 2, true}
    field^.density[1] = 1
    outside := 3 * DUST_FIELD_DIM + 3
    field^.density[outside] = 1

    visits := dust_field_apply_tool_point(field, {0, 0})

    testing.expect_value(t, visits, u64(9))
    testing.expect(t, field^.momentum_x[1] > 0)
    testing.expect_value(t, field^.momentum_y[1], f32(0))
    testing.expect_value(t, field^.momentum_x[outside], f32(0))
    testing.expect_value(t, field^.momentum_y[outside], f32(0))

    field^.support_bounds = {200, 200, 202, 202, true}
    testing.expect_value(t,
        dust_field_apply_tool_point(field, {0, 0}), u64(0))
}

// Verify normalization and reconstruction preserve a deposited particle velocity.
@(test)
dust_round_trip_preserves_single_velocity :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    position := geometry.Vector2{0.347, 0.612}
    expected := geometry.Vector2{0.003, -0.002}
    dust_field_deposit(field, position, expected)

    dust_field_normalize(field, field^.support_bounds)
    field^.solved_velocity_x = field^.momentum_x
    field^.solved_velocity_y = field^.momentum_y
    actual := dust_field_sample(field, position)

    test_helpers.expect_close(t, actual.x, expected.x, "round-trip x velocity")
    test_helpers.expect_close(t, actual.y, expected.y, "round-trip y velocity")
}

// Verify bilinear reconstruction preserves a linear vector field.
@(test)
dust_linear_vector_reconstructs :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    for node in 0..<DUST_FIELD_NODE_COUNT {
        x := f32(node % DUST_FIELD_DIM) / f32(DUST_FIELD_INTERVAL_COUNT)
        y := f32(node / DUST_FIELD_DIM) / f32(DUST_FIELD_INTERVAL_COUNT)
        field^.solved_velocity_x[node] = 2 * x - y
        field^.solved_velocity_y[node] = x + 3 * y
    }
    position := geometry.Vector2{0.347, 0.612}

    actual := dust_field_sample(field, position)

    test_helpers.expect_close(t, actual.x, 2 * position.x - position.y,
        "linear x reconstruction")
    test_helpers.expect_close(t, actual.y, position.x + 3 * position.y,
        "linear y reconstruction")
}

// Seed every node with one uniform deposited density and momentum.
dust_test_seed_uniform :: proc(field: ^Dust_Field_State,
    density: f32, velocity: geometry.Vector2) {
    for node in 0..<DUST_FIELD_NODE_COUNT {
        field^.density[node] = density
        field^.momentum_x[node] = density * velocity.x
        field^.momentum_y[node] = density * velocity.y
    }
    field^.support_bounds = {0, 0, DUST_FIELD_DIM - 1, DUST_FIELD_DIM - 1, true}
}

// Resolve one cardinal neighbor with the original flat-index semantics.
dust_test_reference_neighbor :: proc(node, offset_x, offset_y: int) -> int {
    x := clamp(node % DUST_FIELD_DIM + offset_x, 0, DUST_FIELD_DIM - 1)
    y := clamp(node / DUST_FIELD_DIM + offset_y, 0, DUST_FIELD_DIM - 1)
    return y * DUST_FIELD_DIM + x
}

// Evolve a field through the original flat traversal for comparison.
dust_test_reference_evolve :: proc(field: ^Dust_Field_State, dt: f32) {
    dust_field_normalize(field, field^.support_bounds)
    for node in 0..<DUST_FIELD_NODE_COUNT {
        left := dust_test_reference_neighbor(node, -1, 0)
        right := dust_test_reference_neighbor(node, 1, 0)
        down := dust_test_reference_neighbor(node, 0, -1)
        up := dust_test_reference_neighbor(node, 0, 1)
        next := dust_field_evolve_node(
            field, node, {left, right, down, up}, dt)
        field^.solved_velocity_x[node] = next.x
        field^.solved_velocity_y[node] = next.y
    }
}

// Verify bounded row traversal matches a full-grid solve for identical deposits.
@(test)
dust_bounded_solve_matches_full_reference :: proc(t: ^testing.T) {
    actual := new(Dust_Field_State, context.allocator)
    defer free(actual)
    reference := new(Dust_Field_State, context.allocator)
    defer free(reference)
    positions := [4]geometry.Vector2{{0, 0}, {0.43, 0.61}, {0.44, 0.62}, {1, 1}}
    for position, index in positions {
        velocity := geometry.Vector2{f32(index - 2) * 0.001, f32(2 - index) * 0.002}
        dust_field_deposit(actual, position, velocity)
        dust_field_deposit(reference, position, velocity)
    }
    reference^.support_bounds = {0, 0, DUST_FIELD_DIM - 1, DUST_FIELD_DIM - 1, true}

    dust_field_evolve(actual, f32(1.0 / 60.0))
    dust_test_reference_evolve(reference, f32(1.0 / 60.0))

    for node in 0..<DUST_FIELD_NODE_COUNT {
        test_helpers.expect_close(t, actual^.solved_velocity_x[node],
            reference^.solved_velocity_x[node], "bounded solve x")
        test_helpers.expect_close(t, actual^.solved_velocity_y[node],
            reference^.solved_velocity_y[node], "bounded solve y")
    }
}

// Verify one solve preserves spatially uniform velocity apart from uniform drag.
@(test)
dust_uniform_velocity_remains_uniform :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    dust_test_seed_uniform(field, 0.9, {0.003, -0.002})

    dust_field_evolve(field, f32(1.0 / 60.0))

    center := 125 * DUST_FIELD_DIM + 125
    test_helpers.expect_close(t, field^.solved_velocity_x[center],
        field^.solved_velocity_x[center + 1],
        "uniform x velocity")
    test_helpers.expect_close(t, field^.solved_velocity_y[center],
        field^.solved_velocity_y[center + 1],
        "uniform y velocity")
    testing.expect(t, field^.solved_velocity_x[center] > 0)
    testing.expect(t, field^.solved_velocity_x[center] < 0.003)
}

// Verify sub-yield density cannot create pressure motion from rest.
@(test)
dust_below_yield_density_remains_still :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    dust_test_seed_uniform(field, 0.9, {})

    dust_field_evolve(field, f32(1.0 / 60.0))

    center := 125 * DUST_FIELD_DIM + 125
    testing.expect_value(t, field^.solved_velocity_x[center], f32(0))
    testing.expect_value(t, field^.solved_velocity_y[center], f32(0))
}

// Verify one asymmetric overdensity creates finite outward correction.
@(test)
dust_pressure_decompresses_boundedly :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    center := 125 * DUST_FIELD_DIM + 125
    for node in center - 1..=center + 1 {
        field^.density[node] = 1.2
    }
    field^.density[center] = 2
    field^.support_bounds = {124, 125, 126, 125, true}

    dust_field_evolve(field, f32(1.0 / 60.0))

    correction := field^.solved_velocity_x[center + 1]
    testing.expect(t, correction > 0)
    testing.expect(t, correction <= DUST_PRESSURE_ACCELERATION_MAX / 60)
}

// Verify solving overwrites poisoned output throughout the current solve rectangle.
@(test)
dust_solve_overwrites_current_output :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    for node in 0..<DUST_FIELD_NODE_COUNT {
        field^.solved_velocity_x[node] = 17
        field^.solved_velocity_y[node] = -23
    }
    position := geometry.Vector2{0.5, 0.5}
    dust_field_deposit(field, position, {0.004, -0.003})
    bounds := dust_field_solve_bounds(field^.support_bounds)

    dust_field_evolve(field, f32(1.0 / 60.0))

    for y in int(bounds.min_y)..=int(bounds.max_y) {
        for x in int(bounds.min_x)..=int(bounds.max_x) {
            node := y * DUST_FIELD_DIM + x
            testing.expect(t, field^.solved_velocity_x[node] != 17)
            testing.expect(t, field^.solved_velocity_y[node] != -23)
        }
    }
}

// Verify preparing a disjoint step removes every prior deposition value.
@(test)
dust_prepare_clears_previous_solve_region :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    old_position := geometry.Vector2{0.1, 0.1}
    old_node := int(dust_field_stencil(old_position).indices[0])
    dust_field_deposit(field, old_position, {0.01, -0.02})
    dust_field_evolve(field, f32(1.0 / 60.0))
    testing.expect(t, field^.solved_velocity_x[old_node] != 0)

    dust_field_prepare(field)
    dust_field_deposit(field, {0.9, 0.9}, {-0.03, 0.04})

    testing.expect_value(t, field^.density[old_node], f32(0))
    testing.expect_value(t, field^.momentum_x[old_node], f32(0))
    testing.expect_value(t, field^.momentum_y[old_node], f32(0))
}

// Verify an empty following step clears prior support and publishes no region.
@(test)
dust_empty_step_clears_bounds :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    dust_field_deposit(field, {0.5, 0.5}, {0.01, 0.02})
    dust_field_evolve(field, f32(1.0 / 60.0))

    dust_field_prepare(field)
    dust_field_evolve(field, f32(1.0 / 60.0))

    testing.expect(t, !field^.support_bounds.valid)
    testing.expect(t, !field^.previous_solve_bounds.valid)
    center := 125 * DUST_FIELD_DIM + 125
    testing.expect_value(t, field^.momentum_x[center], f32(0))
    testing.expect_value(t, field^.momentum_y[center], f32(0))
}

// Verify solve halos clamp to the board at both extreme corners.
@(test)
dust_solve_bounds_clamp_to_board :: proc(t: ^testing.T) {
    lower := dust_field_stencil({0, 0})
    upper := dust_field_stencil({1, 1})
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    dust_field_include_stencil(field, lower)
    bounds := dust_field_solve_bounds(field^.support_bounds)
    testing.expect_value(t, bounds, Dust_Field_Bounds{0, 0, 2, 2, true})

    field^.support_bounds = {}
    dust_field_include_stencil(field, upper)
    bounds = dust_field_solve_bounds(field^.support_bounds)
    testing.expect_value(t, bounds, Dust_Field_Bounds{
        DUST_FIELD_DIM - 3, DUST_FIELD_DIM - 3,
        DUST_FIELD_DIM - 1, DUST_FIELD_DIM - 1, true})
}

// Verify clearing removes prior values from every fixed physics plane.
@(test)
dust_clear_resets_all_planes :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    node := DUST_FIELD_NODE_COUNT / 2
    field^.density[node] = 1
    field^.momentum_x[node] = 2
    field^.momentum_y[node] = 3
    field^.solved_velocity_x[node] = 4
    field^.solved_velocity_y[node] = 5

    dust_field_clear(field)

    testing.expect_value(t, field^, Dust_Field_State{})
}