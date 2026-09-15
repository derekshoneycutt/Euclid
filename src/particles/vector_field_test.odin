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
    test_helpers.expect_close(t, vector_dust_test_plane_sum(&field^.velocity_x), 2.5,
        "deposited x momentum")
    test_helpers.expect_close(t, vector_dust_test_plane_sum(&field^.velocity_y), -1.25,
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
    test_helpers.expect_close(t, vector_dust_test_plane_sum(&field^.velocity_x), 0.75,
        "boundary x momentum")
    test_helpers.expect_close(t, vector_dust_test_plane_sum(&field^.velocity_y), -0.5,
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

    vector_dust_field_normalize(field)
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
        field^.velocity_x[node] = 2 * x - y
        field^.velocity_y[node] = x + 3 * y
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
        field^.velocity_x[node] = density * velocity.x
        field^.velocity_y[node] = density * velocity.y
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
    test_helpers.expect_close(t, field^.velocity_x[center], field^.velocity_x[center + 1],
        "uniform x velocity")
    test_helpers.expect_close(t, field^.velocity_y[center], field^.velocity_y[center + 1],
        "uniform y velocity")
    testing.expect(t, field^.velocity_x[center] > 0)
    testing.expect(t, field^.velocity_x[center] < 0.003)
}

// Verify sub-yield density cannot create pressure motion from rest.
@(test)
vector_dust_below_yield_density_remains_still :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    vector_dust_test_seed_uniform(field, 0.9, {})

    vector_dust_field_evolve(field, f32(1.0 / 60.0))

    center := 125 * DUST_FIELD_DIM + 125
    testing.expect_value(t, field^.velocity_x[center], f32(0))
    testing.expect_value(t, field^.velocity_y[center], f32(0))
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

    vector_dust_field_evolve(field, f32(1.0 / 60.0))

    correction := field^.velocity_x[center + 1]
    testing.expect(t, correction > 0)
    testing.expect(t, correction <= VECTOR_DUST_PRESSURE_ACCELERATION_MAX / 60)
}

// Verify clearing removes prior values from every fixed physics plane.
@(test)
vector_dust_clear_resets_all_planes :: proc(t: ^testing.T) {
    field := new(Vector_Dust_Field_State, context.allocator)
    defer free(field)
    node := DUST_FIELD_NODE_COUNT / 2
    field^.density[node] = 1
    field^.velocity_x[node] = 2
    field^.velocity_y[node] = 3
    field^.next_velocity_x[node] = 4
    field^.next_velocity_y[node] = 5

    vector_dust_field_clear(field)

    testing.expect_value(t, field^, Vector_Dust_Field_State{})
}