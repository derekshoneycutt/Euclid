package particles

import particlemodel "model"

import "core:testing"

import rl "vendor:raylib"

import test_helpers "../test_helpers"

// Sum all four weights in one vector-dust transfer stencil.
vector_dust_test_weight_sum :: proc(stencil: Vector_Dust_Field_Stencil) -> f32 {
    result: f32
    for weight in stencil.weights {
        result += weight
    }
    return result
}

// Sum one complete scalar field plane.
vector_dust_test_plane_sum :: proc(plane: ^particlemodel.Dust_Field_Scalar) -> f32 {
    result: f32
    for value in plane^ {
        result += value
    }
    return result
}

// Verify interior bilinear support preserves one complete contribution.
@(test)
vector_dust_interior_weights_sum_to_one :: proc(t: ^testing.T) {
    stencil := vector_dust_field_stencil({0.347, 0.612})

    test_helpers.expect_close(t, vector_dust_test_weight_sum(stencil), 1,
        "interior stencil should preserve unit weight")
}

// Verify board corners preserve one contribution and valid node indices.
@(test)
vector_dust_corner_weights_and_indices_are_valid :: proc(t: ^testing.T) {
    corners := [4]rl.Vector2{{0, 0}, {1, 0}, {0, 1}, {1, 1}}
    for corner in corners {
        stencil := vector_dust_field_stencil(corner)
        test_helpers.expect_close(t, vector_dust_test_weight_sum(stencil), 1,
            "corner stencil should preserve unit weight")
        for node in stencil.indices {
            testing.expect(t, node >= 0 && node < i32(DUST_FIELD_NODE_COUNT))
        }
    }
}

// Verify one transfer conserves unit density and both momentum components.
@(test)
vector_dust_deposit_conserves_density_and_momentum :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)

    vector_dust_field_deposit(field, {0.347, 0.612}, {2.5, -1.25})

    test_helpers.expect_close(t, vector_dust_test_plane_sum(&field^.density), 1,
        "deposited density")
    test_helpers.expect_close(t, vector_dust_test_plane_sum(&field^.momentum_x), 2.5,
        "deposited x momentum")
    test_helpers.expect_close(t, vector_dust_test_plane_sum(&field^.momentum_y), -1.25,
        "deposited y momentum")
}

// Verify boundary transfer does not lose density or momentum.
@(test)
vector_dust_boundary_deposit_is_conservative :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)

    vector_dust_field_deposit(field, {1, 1}, {0.75, -0.5})

    test_helpers.expect_close(t, vector_dust_test_plane_sum(&field^.density), 1,
        "boundary density")
    test_helpers.expect_close(t, vector_dust_test_plane_sum(&field^.momentum_x), 0.75,
        "boundary x momentum")
    test_helpers.expect_close(t, vector_dust_test_plane_sum(&field^.momentum_y), -0.5,
        "boundary y momentum")
}

// Verify normalization and reconstruction preserve a deposited particle velocity.
@(test)
vector_dust_round_trip_preserves_single_velocity :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    position := rl.Vector2{0.347, 0.612}
    expected := rl.Vector2{0.003, -0.002}
    vector_dust_field_deposit(field, position, expected)

    vector_dust_field_normalize(field, field^.support_bounds)
    field^.solved_velocity_x = field^.momentum_x
    field^.solved_velocity_y = field^.momentum_y
    actual := vector_dust_field_sample(field, position)

    test_helpers.expect_close(t, actual.x, expected.x, "round-trip x velocity")
    test_helpers.expect_close(t, actual.y, expected.y, "round-trip y velocity")
}

// Verify bilinear reconstruction preserves a linear vector field.
@(test)
vector_dust_linear_vector_reconstructs :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    for node in 0..<DUST_FIELD_NODE_COUNT {
        x := f32(node % DUST_FIELD_DIM) / f32(DUST_FIELD_INTERVAL_COUNT)
        y := f32(node / DUST_FIELD_DIM) / f32(DUST_FIELD_INTERVAL_COUNT)
        field^.solved_velocity_x[node] = 2 * x - y
        field^.solved_velocity_y[node] = x + 3 * y
    }
    position := rl.Vector2{0.347, 0.612}

    actual := vector_dust_field_sample(field, position)

    test_helpers.expect_close(t, actual.x, 2 * position.x - position.y,
        "linear x reconstruction")
    test_helpers.expect_close(t, actual.y, position.x + 3 * position.y,
        "linear y reconstruction")
}

// Seed every node with one uniform deposited density and momentum.
vector_dust_test_seed_uniform :: proc(field: ^Vector_Dust_Field_State,
    density: f32, velocity: rl.Vector2) {
    for node in 0..<DUST_FIELD_NODE_COUNT {
        field^.density[node] = density
        field^.momentum_x[node] = density * velocity.x
        field^.momentum_y[node] = density * velocity.y
    }
    field^.support_bounds = {0, 0, DUST_FIELD_DIM - 1, DUST_FIELD_DIM - 1, true}
}

// Resolve one cardinal neighbor with the original flat-index semantics.
vector_dust_test_reference_neighbor :: proc(node, offset_x, offset_y: int) -> int {
    x := clamp(node % DUST_FIELD_DIM + offset_x, 0, DUST_FIELD_DIM - 1)
    y := clamp(node / DUST_FIELD_DIM + offset_y, 0, DUST_FIELD_DIM - 1)
    return y * DUST_FIELD_DIM + x
}

// Evolve a field through the original flat traversal for comparison.
vector_dust_test_reference_evolve :: proc(field: ^Vector_Dust_Field_State, dt: f32) {
    vector_dust_field_normalize(field, field^.support_bounds)
    for node in 0..<DUST_FIELD_NODE_COUNT {
        left := vector_dust_test_reference_neighbor(node, -1, 0)
        right := vector_dust_test_reference_neighbor(node, 1, 0)
        down := vector_dust_test_reference_neighbor(node, 0, -1)
        up := vector_dust_test_reference_neighbor(node, 0, 1)
        next := vector_dust_field_evolve_node(
            field, node, {left, right, down, up}, dt)
        field^.solved_velocity_x[node] = next.x
        field^.solved_velocity_y[node] = next.y
    }
}

// Verify bounded row traversal matches a full-grid solve for identical deposits.
@(test)
vector_dust_bounded_solve_matches_full_reference :: proc(t: ^testing.T) {
    actual := new(Vector_Dust_Field_State, context.allocator)
    defer free(actual)
    reference := new(Vector_Dust_Field_State, context.allocator)
    defer free(reference)
    positions := [4]rl.Vector2{{0, 0}, {0.43, 0.61}, {0.44, 0.62}, {1, 1}}
    for position, index in positions {
        velocity := rl.Vector2{f32(index - 2) * 0.001, f32(2 - index) * 0.002}
        vector_dust_field_deposit(actual, position, velocity)
        vector_dust_field_deposit(reference, position, velocity)
    }
    reference^.support_bounds = {0, 0, DUST_FIELD_DIM - 1, DUST_FIELD_DIM - 1, true}

    vector_dust_field_evolve(actual, f32(1.0 / 60.0))
    vector_dust_test_reference_evolve(reference, f32(1.0 / 60.0))

    for node in 0..<DUST_FIELD_NODE_COUNT {
        test_helpers.expect_close(t, actual^.solved_velocity_x[node],
            reference^.solved_velocity_x[node], "bounded solve x")
        test_helpers.expect_close(t, actual^.solved_velocity_y[node],
            reference^.solved_velocity_y[node], "bounded solve y")
    }
}

// Verify one solve preserves spatially uniform velocity apart from uniform drag.
@(test)
vector_dust_uniform_velocity_remains_uniform :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    vector_dust_test_seed_uniform(field, 0.9, {0.003, -0.002})

    vector_dust_field_evolve(field, f32(1.0 / 60.0))

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
vector_dust_below_yield_density_remains_still :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    vector_dust_test_seed_uniform(field, 0.9, {})

    vector_dust_field_evolve(field, f32(1.0 / 60.0))

    center := 125 * DUST_FIELD_DIM + 125
    testing.expect_value(t, field^.solved_velocity_x[center], f32(0))
    testing.expect_value(t, field^.solved_velocity_y[center], f32(0))
}

// Verify one asymmetric overdensity creates finite outward correction.
@(test)
vector_dust_pressure_decompresses_boundedly :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    center := 125 * DUST_FIELD_DIM + 125
    for node in center - 1..=center + 1 {
        field^.density[node] = 1.2
    }
    field^.density[center] = 2
    field^.support_bounds = {124, 125, 126, 125, true}

    vector_dust_field_evolve(field, f32(1.0 / 60.0))

    correction := field^.solved_velocity_x[center + 1]
    testing.expect(t, correction > 0)
    testing.expect(t, correction <= VECTOR_DUST_PRESSURE_ACCELERATION_MAX / 60)
}

// Verify solving overwrites poisoned output throughout the current solve rectangle.
@(test)
vector_dust_solve_overwrites_current_output :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    for node in 0..<DUST_FIELD_NODE_COUNT {
        field^.solved_velocity_x[node] = 17
        field^.solved_velocity_y[node] = -23
    }
    position := rl.Vector2{0.5, 0.5}
    vector_dust_field_deposit(field, position, {0.004, -0.003})
    bounds := vector_dust_field_solve_bounds(field^.support_bounds)

    vector_dust_field_evolve(field, f32(1.0 / 60.0))

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
vector_dust_prepare_clears_previous_solve_region :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    old_position := rl.Vector2{0.1, 0.1}
    old_node := int(vector_dust_field_stencil(old_position).indices[0])
    vector_dust_field_deposit(field, old_position, {0.01, -0.02})
    vector_dust_field_evolve(field, f32(1.0 / 60.0))
    testing.expect(t, field^.solved_velocity_x[old_node] != 0)

    vector_dust_field_prepare(field)
    vector_dust_field_deposit(field, {0.9, 0.9}, {-0.03, 0.04})

    testing.expect_value(t, field^.density[old_node], f32(0))
    testing.expect_value(t, field^.momentum_x[old_node], f32(0))
    testing.expect_value(t, field^.momentum_y[old_node], f32(0))
}

// Verify an empty following step clears prior support and publishes no region.
@(test)
vector_dust_empty_step_clears_bounds :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    vector_dust_field_deposit(field, {0.5, 0.5}, {0.01, 0.02})
    vector_dust_field_evolve(field, f32(1.0 / 60.0))

    vector_dust_field_prepare(field)
    vector_dust_field_evolve(field, f32(1.0 / 60.0))

    testing.expect(t, !field^.support_bounds.valid)
    testing.expect(t, !field^.previous_solve_bounds.valid)
    center := 125 * DUST_FIELD_DIM + 125
    testing.expect_value(t, field^.momentum_x[center], f32(0))
    testing.expect_value(t, field^.momentum_y[center], f32(0))
}

// Verify solve halos clamp to the board at both extreme corners.
@(test)
vector_dust_solve_bounds_clamp_to_board :: proc(t: ^testing.T) {
    lower := vector_dust_field_stencil({0, 0})
    upper := vector_dust_field_stencil({1, 1})
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    vector_dust_field_include_stencil(field, lower)
    bounds := vector_dust_field_solve_bounds(field^.support_bounds)
    testing.expect_value(t, bounds, Vector_Dust_Field_Bounds{0, 0, 2, 2, true})

    field^.support_bounds = {}
    vector_dust_field_include_stencil(field, upper)
    bounds = vector_dust_field_solve_bounds(field^.support_bounds)
    testing.expect_value(t, bounds, Vector_Dust_Field_Bounds{
        DUST_FIELD_DIM - 3, DUST_FIELD_DIM - 3,
        DUST_FIELD_DIM - 1, DUST_FIELD_DIM - 1, true})
}

// Verify clearing removes prior values from every fixed physics plane.
@(test)
vector_dust_clear_resets_all_planes :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    node := DUST_FIELD_NODE_COUNT / 2
    field^.density[node] = 1
    field^.momentum_x[node] = 2
    field^.momentum_y[node] = 3
    field^.solved_velocity_x[node] = 4
    field^.solved_velocity_y[node] = 5

    vector_dust_field_clear(field)

    testing.expect_value(t, field^, Vector_Dust_Field_State{})
}