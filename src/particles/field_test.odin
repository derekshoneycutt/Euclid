package particles

import particlemodel "model"

import "core:testing"

import rl "vendor:raylib"

import test_helpers "../test_helpers"

// Sum the retained weights in one normalized field stencil.
dust_field_test_weight_sum :: proc(stencil: Dust_Field_Stencil) -> f32 {
    sum: f32
    for index in 0..<stencil.count {
        sum += stencil.weights[index]
    }
    return sum
}

// Verify interior deposition support preserves one complete contribution.
@(test)
dust_field_interior_weights_sum_to_one :: proc(t: ^testing.T) {
    position := rl.Vector2{0.347, 0.612}
    coordinates := dust_field_coordinates(position)
    stencil := dust_field_stencil(position)

    test_helpers.expect_close(t, coordinates.x, position.x * 250,
        "board x should map to field intervals")
    test_helpers.expect_close(t, coordinates.y, position.y * 250,
        "board y should map to field intervals")
    testing.expect_value(t, stencil.count, particlemodel.DUST_FIELD_STENCIL_CAP)
    test_helpers.expect_close(t, dust_field_test_weight_sum(stencil), 1,
        "interior stencil should preserve unit weight")
}

// Verify corner truncation renormalizes all retained kernel support.
@(test)
dust_field_corner_weights_sum_to_one :: proc(t: ^testing.T) {
    stencil := dust_field_stencil({0, 0})

    testing.expect_value(t, stencil.count, 4)
    test_helpers.expect_close(t, dust_field_test_weight_sum(stencil), 1,
        "corner stencil should preserve unit weight")
}

// Verify normalized sampling reconstructs a constant vector without drift.
@(test)
dust_field_constant_vector_reconstructs_exactly :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    for index in 0..<DUST_FIELD_NODE_COUNT {
        field^.velocity_x[index] = 2.5
        field^.velocity_y[index] = -1.25
    }

    sampled := dust_field_sample_vector(
        &field^.velocity_x, &field^.velocity_y, {0.347, 0.612})

    test_helpers.expect_close(t, sampled.x, 2.5, "constant x reconstruction")
    test_helpers.expect_close(t, sampled.y, -1.25, "constant y reconstruction")
}

// Verify quadratic reconstruction retains an interior linear vector field.
@(test)
dust_field_linear_vector_reconstructs_within_tolerance :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    for node_index in 0..<DUST_FIELD_NODE_COUNT {
        x := f32(node_index % DUST_FIELD_DIM) / f32(DUST_FIELD_INTERVAL_COUNT)
        y := f32(node_index / DUST_FIELD_DIM) / f32(DUST_FIELD_INTERVAL_COUNT)
        field^.velocity_x[node_index] = 2 * x - y
        field^.velocity_y[node_index] = x + 3 * y
    }
    position := rl.Vector2{0.347, 0.612}

    sampled := dust_field_sample_vector(
        &field^.velocity_x, &field^.velocity_y, position)

    test_helpers.expect_close(t, sampled.x, 2 * position.x - position.y,
        "linear x reconstruction")
    test_helpers.expect_close(t, sampled.y, position.x + 3 * position.y,
        "linear y reconstruction")
}

// Deposit a deterministic scalar fixture into one empty field.
dust_field_test_deposit_fixture :: proc(field: ^Dust_Field_State) {
    dust_field_deposit_scalar(field, &field^.density, {0.25, 0.75}, 1.5)
    dust_field_deposit_scalar(field, &field^.density, {0.251, 0.749}, 0.75)
    dust_field_deposit_scalar(field, &field^.density, {0, 1}, 2.0)
}

// Verify repeated fixed-order deposition produces identical active field state.
@(test)
dust_field_repeated_deposition_is_deterministic :: proc(t: ^testing.T) {
    first := new(Dust_Field_State, context.allocator)
    second := new(Dust_Field_State, context.allocator)
    defer free(first)
    defer free(second)
    dust_field_test_deposit_fixture(first)
    dust_field_test_deposit_fixture(second)

    testing.expect_value(t, second^.active_count, first^.active_count)
    for active_index in 0..<first^.active_count {
        node_index := int(first^.active_nodes[active_index])
        testing.expect_value(t, second^.active_nodes[active_index], i32(node_index))
        testing.expect_value(t, second^.density[node_index], first^.density[node_index])
    }
}

// Verify sparse reset clears every plane and all metadata at prior support.
@(test)
dust_field_active_reset_clears_prior_support :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)
    position := rl.Vector2{0.25, 0.75}
    stencil := dust_field_stencil(position)
    dust_field_deposit_scalar(field, &field^.density, position, 2)
    dust_field_deposit_vector(field, &field^.momentum_x,
        &field^.momentum_y, position, {3, -4})

    dust_field_reset_active(field)

    testing.expect_value(t, field^.active_count, 0)
    for stencil_index in 0..<stencil.count {
        node_index := int(stencil.indices[stencil_index])
        testing.expect_value(t, field^.density[node_index], f32(0))
        testing.expect_value(t, field^.momentum_x[node_index], f32(0))
        testing.expect_value(t, field^.momentum_y[node_index], f32(0))
        word_index := node_index / 64
        testing.expect_value(t, field^.active_bits[word_index], u64(0))
    }
}

// Verify untouched scalar and vector planes reconstruct zero.
@(test)
dust_field_empty_sample_returns_zero :: proc(t: ^testing.T) {
    field := new(Dust_Field_State, context.allocator)
    defer free(field)

    scalar := dust_field_sample_scalar(&field^.density, {0.5, 0.5})
    vector := dust_field_sample_vector(
        &field^.velocity_x, &field^.velocity_y, {0.5, 0.5})

    testing.expect_value(t, scalar, f32(0))
    testing.expect_value(t, vector, rl.Vector2{})
}