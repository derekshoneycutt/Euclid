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

// Configure colocated grounded particles for deterministic density thresholds.
dust_field_test_set_colocated :: proc(ps: ^Particle_System, count: int) {
    ps^.use_max_dust_particles = 3
    for index in 0..<3 {
        ps^.low_particles.alive[index] = index < count
        ps^.low_particles.pos_x[index] = 0.5
        ps^.low_particles.pos_y[index] = 0.5
        ps^.low_particles.pos_z[index] = DUST_FLOOR_Z
        ps^.low_particles.life[index] = 1
        ps^.low_particles.color[index] = rl.WHITE
    }
}

// Build candidate density and apply membership hysteresis once.
dust_field_test_classify :: proc(ps: ^Particle_System) {
    dust_field_build_candidate_density(ps)
    dust_field_classify_particles(ps)
}

// Verify compressed grounded material enters aggregate membership.
@(test)
dust_field_membership_enters_above_threshold :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    dust_field_test_set_colocated(ps, 3)

    dust_field_test_classify(ps)

    testing.expect_value(t, ps^.dust_aggregate_count, 3)
    testing.expect(t, ps^.dust_aggregate[0])
}

// Verify aggregate membership persists between exit and entry thresholds.
@(test)
dust_field_membership_remains_through_hysteresis_band :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    dust_field_test_set_colocated(ps, 3)
    dust_field_test_classify(ps)
    dust_field_test_set_colocated(ps, 2)

    dust_field_test_classify(ps)

    testing.expect_value(t, ps^.dust_aggregate_count, 2)
    testing.expect(t, ps^.dust_aggregate[0] && ps^.dust_aggregate[1])
}

// Verify aggregate membership exits below the lower density threshold.
@(test)
dust_field_membership_exits_below_lower_threshold :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    dust_field_test_set_colocated(ps, 3)
    dust_field_test_classify(ps)
    dust_field_test_set_colocated(ps, 1)

    dust_field_test_classify(ps)

    testing.expect_value(t, ps^.dust_aggregate_count, 0)
    testing.expect(t, !ps^.dust_aggregate[0])
}

// Verify vertical motion always returns dust to individual particle authority.
@(test)
dust_field_airborne_membership_clears :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    dust_field_test_set_colocated(ps, 3)
    dust_field_test_classify(ps)
    ps^.low_particles.pos_z[0] = DUST_FLOOR_Z + 0.01

    dust_field_test_classify(ps)

    testing.expect(t, !ps^.dust_aggregate[0])
    testing.expect_value(t, ps^.dust_aggregate_count, 2)
}

// Seed a rectangular field patch with uniform density and velocity.
dust_field_test_seed_patch :: proc(ps: ^Particle_System, first, last: int,
        density: f32, velocity: rl.Vector2) {
    for y in first..=last {
        for x in first..=last {
            node := y * DUST_FIELD_DIM + x
            dust_field_mark_active(&ps^.dust_field, node)
            ps^.dust_field.density[node] = density
            ps^.dust_field.momentum_x[node] = density * velocity.x
            ps^.dust_field.momentum_y[node] = density * velocity.y
        }
    }
}

// Verify a uniform field remains spatially uniform after one solve.
@(test)
dust_field_uniform_velocity_remains_uniform :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    dust_field_test_seed_patch(ps, 122, 128, 0.9, {0.002, -0.001})

    dust_field_evolve(ps, f32(1.0 / 60.0))

    center := 125 * DUST_FIELD_DIM + 125
    neighbor := center + 1
    test_helpers.expect_close(t, ps^.dust_field.velocity_x[center],
        ps^.dust_field.velocity_x[neighbor], "uniform x should remain uniform")
    test_helpers.expect_close(t, ps^.dust_field.velocity_y[center],
        ps^.dust_field.velocity_y[neighbor], "uniform y should remain uniform")
}

// Verify one nodal impulse transfers velocity to occupied neighbors.
@(test)
dust_field_local_impulse_spreads_to_neighbors :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    center := 125 * DUST_FIELD_DIM + 125
    for node in center - 1..=center + 1 {
        dust_field_mark_active(&ps^.dust_field, node)
        ps^.dust_field.density[node] = 1
    }
    ps^.dust_field.momentum_x[center] = 0.003

    dust_field_evolve(ps, f32(1.0 / 60.0))

    testing.expect(t, ps^.dust_field.velocity_x[center + 1] > 0)
    testing.expect(t, ps^.dust_field.velocity_x[center] >
        ps^.dust_field.velocity_x[center + 1])
}

// Solve one uniform patch and return its center velocity magnitude.
dust_field_test_density_decay :: proc(density: f32) -> f32 {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    dust_field_test_seed_patch(ps, 122, 128, density, {0.003, 0})
    dust_field_evolve(ps, f32(1.0 / 60.0))
    return ps^.dust_field.velocity_x[125 * DUST_FIELD_DIM + 125]
}

// Verify denser aggregate material loses uniform bulk speed more quickly.
@(test)
dust_field_higher_density_damps_faster :: proc(t: ^testing.T) {
    lower := dust_field_test_density_decay(0.8)
    higher := dust_field_test_density_decay(2.0)

    testing.expect(t, higher < lower)
    testing.expect(t, higher > 0)
}

// Verify sub-yield density cannot generate spontaneous pressure motion.
@(test)
dust_field_below_yield_density_remains_still :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    dust_field_test_seed_patch(ps, 122, 128, 0.9, {})

    dust_field_evolve(ps, f32(1.0 / 60.0))

    center := 125 * DUST_FIELD_DIM + 125
    testing.expect_value(t, ps^.dust_field.velocity_x[center], f32(0))
    testing.expect_value(t, ps^.dust_field.velocity_y[center], f32(0))
    testing.expect_value(t, ps^.dust_field_pressure_node_count, 0)
}

// Verify an asymmetric overdensity creates finite outward correction.
@(test)
dust_field_excess_density_decompresses_boundedly :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    center := 125 * DUST_FIELD_DIM + 125
    for node in center - 1..=center + 1 {
        dust_field_mark_active(&ps^.dust_field, node)
        ps^.dust_field.density[node] = 1.2
    }
    ps^.dust_field.density[center] = 2

    dust_field_evolve(ps, f32(1.0 / 60.0))

    correction := ps^.dust_field.velocity_x[center + 1]
    testing.expect(t, correction > 0)
    testing.expect(t, correction <=
        DUST_FIELD_PRESSURE_ACCELERATION_MAX / 60)
}

// Verify exact field assignment removes same-location velocity residuals.
@(test)
dust_field_exact_assignment_removes_local_residual :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 2
    stencil := dust_field_stencil({0.5, 0.5})
    for index in 0..<2 {
        ps^.dust_aggregate[index] = true
        ps^.low_particles.pos_x[index] = 0.5
        ps^.low_particles.pos_y[index] = 0.5
        ps^.low_particles.vel_x[index] = f32(index * 2 - 1)
    }
    for stencil_index in 0..<stencil.count {
        node := int(stencil.indices[stencil_index])
        ps^.dust_field.velocity_x[node] = 0.002
        ps^.dust_field.velocity_y[node] = -0.001
    }

    dust_field_assign_particle_velocities(ps)

    test_helpers.expect_close(t, ps^.low_particles.vel_x[0], 0.002,
        "first exact x assignment")
    testing.expect_value(t, ps^.low_particles.vel_x[1], ps^.low_particles.vel_x[0])
    testing.expect_value(t, ps^.low_particles.vel_y[1], ps^.low_particles.vel_y[0])
}

// Verify field activity wakes only aggregate particles in local support.
@(test)
dust_field_dense_wake_remains_local :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 3
    ps^.dust_sleeping_count = 3
    for index in 0..<3 {
        ps^.dust_aggregate[index] = true
        ps^.dust_sleeping[index] = true
        ps^.low_particles.pos_x[index] = 0.2 + f32(index) * 0.2
        ps^.low_particles.pos_y[index] = 0.5
    }
    stencil := dust_field_stencil({0.2, 0.5})
    for stencil_index in 0..<stencil.count {
        node := int(stencil.indices[stencil_index])
        ps^.dust_field.velocity_x[node] = 0.001
    }

    dust_field_assign_particle_velocities(ps)
    dust_field_update_sleeping(ps)

    testing.expect(t, !ps^.dust_sleeping[0])
    testing.expect(t, ps^.dust_sleeping[1] && ps^.dust_sleeping[2])
    testing.expect_value(t, ps^.dust_sleeping_count, 2)
    testing.expect_value(t, ps^.dust_field_wake_transition_count, u64(1))
}