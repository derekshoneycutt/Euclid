package particles

import colormodel "../color/model"
import particlemodel "model"
import shapemodel "../shapes/model"
import curve "../shapes/curve"
import shapes "../shapes"

import "core:math"
import "core:testing"

import test_helpers "../test_helpers"

// Verify theta normalization and sweep delta wrap correctly across zero.
@(test)
normalize_theta_and_sweep_delta_are_stable :: proc(t: ^testing.T) {
    theta := normalize_theta(f32(-0.5))
    test_helpers.expect_close(t, theta, f32(2.0 * math.PI - 0.5),
        "normalize_theta should wrap negatives")

    delta := compute_sweep_delta(
        f32(1.5 * math.PI),
        f32(0.5 * math.PI))
    test_helpers.expect_close(t, delta, f32(math.PI),
        "sweep delta should wrap across zero")
}

// Count live low-layer particles within the configured test capacity.
count_live_low_particles :: proc(ps: ^particlemodel.Particle_System) -> int {
    count: int
    for alive in ps.low_particles.alive[:ps.use_max_dust_particles] {
        if alive {
            count += 1
        }
    }
    return count
}

// Verify outlined arc emission scales with visible arc length.
@(test)
circle_dust_emission_scales_with_arc_length :: proc(t: ^testing.T) {
    quarter := new(particlemodel.Particle_System, context.allocator)
    full := new(particlemodel.Particle_System, context.allocator)
    defer free(quarter)
    defer free(full)
    quarter.use_max_dust_particles = 1000
    full.use_max_dust_particles = 1000
    color := colormodel.WHITE

    emit_circle_dust(quarter, {
        center = {}, radius = 0.2, sweep_theta = f32(math.PI/2), color = color})
    emit_circle_dust(full, {
        center = {}, radius = 0.2, sweep_theta = f32(2*math.PI), color = color})

    quarter_count := count_live_low_particles(quarter)
    full_count := count_live_low_particles(full)
    testing.expect(t, quarter_count < full_count)
    testing.expect(t, full_count >= quarter_count * 3)
}

// Verify filled arc emission occupies the sector interior instead of only its rim.
@(test)
filled_circle_dust_emission_samples_sector_interior :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps.use_max_dust_particles = 1000

    emit_filled_circle_dust(ps, {center = {}, radius = 0.2,
        sweep_theta = f32(math.PI/3), color = colormodel.WHITE})

    interior_count: int
    for index in 0..<ps.use_max_dust_particles {
        if !ps.low_particles.alive[index] {
            continue
        }
        radius_sq := ps.low_particles.pos_x[index] * ps.low_particles.pos_x[index] +
            ps.low_particles.pos_y[index] * ps.low_particles.pos_y[index]
        if radius_sq < 0.01 {
            interior_count += 1
        }
    }
    testing.expect(t, count_live_low_particles(ps) >= 200)
    testing.expect(t, interior_count >= 40)
}

// Verify longer revealed trochoid intervals produce proportionally more hide dust.
@(test)
trochoid_dust_emission_scales_with_revealed_length :: proc(t: ^testing.T) {
    partial := new(particlemodel.Particle_System, context.allocator)
    full := new(particlemodel.Particle_System, context.allocator)
    defer free(partial)
    defer free(full)
    partial.use_max_dust_particles = 1000
    full.use_max_dust_particles = 1000
    value := shapemodel.Shape_Trochoid{mode = .External, fixed_radius = 0.2,
        rolling_radius = 0.2, tracer_distance = 0.2, parameter_start = 0,
        parameter_finish = 2 * math.PI, draw_parameter = math.PI / 2}
    vertices: [curve.TROCHOID_MAX_VERTICES]Vector3
    partial_result := curve.trochoid_explicate({}, value, vertices[:])
    emit_curve_polyline_dust(partial, vertices[:partial_result.vertex_count],
        colormodel.WHITE)
    value.draw_parameter = value.parameter_finish
    full_result := curve.trochoid_explicate({}, value, vertices[:])
    emit_curve_polyline_dust(full, vertices[:full_result.vertex_count],
        colormodel.WHITE)

    partial_count := count_live_low_particles(partial)
    full_count := count_live_low_particles(full)
    testing.expect(t, partial_count < full_count)
    testing.expect(t, partial_count >= CLEAR_BURST_CURVE_MIN_SAMPLES)
}

// Verify hiding the permanent cycloid guide neither emits nor kicks dust.
@(test)
cycloid_tool_hide_is_silent :: proc(t: ^testing.T) {
    world := new(shapemodel.Shape_World, context.allocator)
    particles := new(particlemodel.Particle_System, context.allocator)
    defer free(world)
    defer free(particles)
    tool, status := shapes.world_create_cycloid_tool(world, {
        first = {0, 0, 0}, second = {1, 0, 0}, rolling_radius = 0.05,
        parameter_start = 0, parameter_finish = 2 * math.PI,
        parameter = 0, style = {color = colormodel.WHITE, brush_size = 5},
    })
    testing.expect_value(t, status, shapemodel.Shape_World_Status.Ok)
    style, found := shapemodel.shape_component_get_mut(
        &world.render_styles, &world.registry, tool.shape)
    testing.expect(t, found)
    style.visible = true
    particles.use_max_dust_particles = 1
    particles.low_particles[0].alive = true
    particles.low_particles[0].life = 10

    emitted := emit_shape_world_hide_burst(particles, world, tool.shape)

    testing.expect(t, !emitted)
    testing.expect_value(t, particles.low_particles[0].age, f32(0))
    testing.expect_value(t, particles.low_particles.vel_z[0], f32(0))
    testing.expect_value(t, count_live_low_particles(particles), 1)
}

// Verify slot reservation prefers dead slots and wraps at the particle cap.
@(test)
reserve_dead_low_particle_slot_prefers_dead_then_wraps :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 3
    ps^.next_index = 0

    idx0, ok0 := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok0)
    testing.expect_value(t, idx0, 0)
    testing.expect_value(t, ps^.next_index, 1)

    ps^.low_particles.alive[1] = true
    idx1, ok1 := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok1)
    testing.expect_value(t, idx1, 2)
    testing.expect_value(t, ps^.next_index, 0)

    ps^.low_particles.alive[0] = true
    ps^.low_particles.alive[1] = true
    ps^.low_particles.alive[2] = true
    idx2, ok2 := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok2)
    testing.expect_value(t, idx2, 0)
}

// Verify the reservation ring index wraps back to zero at the cap.
@(test)
reserve_dead_particle_slot_ring_advances :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.next_index = MAX_PARTICLES - 1

    idx, ok := reserve_dead_particle_slot(ps)
    testing.expect(t, ok)
    testing.expect_value(t, idx, MAX_PARTICLES - 1)
    testing.expect_value(t, ps^.next_index, 0)
}

// Assert two particle systems have matching low-particle slots and RNG state.
expect_dust_systems_match :: proc(
    t: ^testing.T, actual, expected: ^particlemodel.Particle_System) {
    for index in 0..<expected^.use_max_dust_particles {
        testing.expect_value(t, actual^.low_particles[index],
            expected^.low_particles[index])
    }
    testing.expect_value(t, actual^.rng_state, expected^.rng_state)
}

// Queue one point contact at every live low-particle slot.
queue_dust_slot_contacts :: proc(
    t: ^testing.T, ps: ^particlemodel.Particle_System) {
    for index in 0..<ps^.use_max_dust_particles {
        testing.expect(t, queue_dust_tool_contact(ps, {endpoint = {
            ps^.low_particles.pos_x[index], ps^.low_particles.pos_y[index], 0}}))
    }
}

// Solve queued tool contacts through the grounded vector-field path.
solve_test_dust_tool_contacts :: proc(ps: ^particlemodel.Particle_System) {
    dust_field_deposit_grounded(ps)
    apply_dust_tool_contacts_to_field(ps)
    dust_field_evolve(&ps^.dust_field, f32(1.0 / 60.0))
    dust_field_assign_grounded(ps)
}

// Verify queue admission is bounded and records rejected contact intents.
@(test)
dust_tool_contact_queue_is_bounded :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    for _ in 0..<DUST_TOOL_CONTACT_CAP {
        testing.expect(t, queue_dust_tool_contact(ps, {}))
    }

    testing.expect(t, !can_queue_dust_tool_contacts(ps, 1))
    testing.expect(t, !queue_dust_tool_contact(ps, {}))
    testing.expect_value(t, ps^.dust_tool_contact_count, DUST_TOOL_CONTACT_CAP)
    testing.expect_value(t, ps^.dust_tool_contact_overflow_count, 1)
}

// Verify only exact duplicate filled sweeps coalesce within one spawn boundary.
@(test)
dust_tool_contacts_coalesce_only_with_matching_semantics :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    first_sweep := particlemodel.Dust_Tool_Contact{
        endpoint = {0.1, 0.2, 0}, segment_first = {0.1, 0.2, 0},
        segment_second = {0.4, 0.2, 0}, has_sweep = true,
        previous_segment_first = {0.1, 0.2, 0},
        previous_segment_second = {0.4, 0.2, 0},
        source = .Compass_Filled_Sweep}
    distinct_sweep := first_sweep
    distinct_sweep.endpoint = {0.5, 0.2, 0}
    distinct_sweep.segment_second = distinct_sweep.endpoint
    duplicate := particlemodel.Dust_Tool_Contact{
        endpoint = {0.7, 0.8, 0}, source = .Point}
    testing.expect(t, queue_dust_tool_contact(ps, first_sweep))
    testing.expect(t, queue_dust_tool_contact(ps, first_sweep))
    testing.expect(t, queue_dust_tool_contact(ps, distinct_sweep))
    testing.expect(t, queue_dust_tool_contact(ps, duplicate))
    testing.expect(t, queue_dust_tool_contact(ps, duplicate))
    scenario := duplicate
    scenario.source = .Scenario
    testing.expect(t, queue_dust_tool_contact(ps, scenario))
    ps^.dust_spawn_sequence += 1
    testing.expect(t, queue_dust_tool_contact(ps, scenario))

    coalesce_dust_tool_contacts(ps)

    testing.expect_value(t, ps^.dust_tool_contact_count, 5)
    testing.expect_value(t, ps^.dust_tool_contact_coalesced_count, u64(2))
    testing.expect_value(t, ps^.dust_tool_contacts[0], first_sweep)
    testing.expect_value(t, ps^.dust_tool_contacts[1], distinct_sweep)
    testing.expect_value(t, ps^.dust_tool_contacts[2], duplicate)
}

// Verify a compound filled sweep reaches interior nodes but not distant support.
@(test)
dust_filled_compass_sweep_covers_ruled_sector :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    interior := [3][2]int{{110, 110}, {120, 120}, {130, 110}}
    outside := [2]int{175, 175}
    for point in interior {
        ps^.dust_field.density[point.y * DUST_FIELD_DIM + point.x] = 1
    }
    outside_node := outside.y * DUST_FIELD_DIM + outside.x
    ps^.dust_field.density[outside_node] = 1
    ps^.dust_field.support_bounds = {110, 110, 175, 175, true}
    testing.expect(t, queue_dust_tool_contact(ps, {
        endpoint = {0.4, 0.6, 0},
        previous_segment_first = {0.4, 0.4, 0},
        previous_segment_second = {0.6, 0.4, 0},
        segment_first = {0.4, 0.4, 0}, segment_second = {0.4, 0.6, 0},
        has_sweep = true, source = .Compass_Filled_Sweep}))

    apply_dust_tool_contacts_to_field(ps)

    for point in interior {
        node := point.y * DUST_FIELD_DIM + point.x
        testing.expect(t, ps^.dust_field.momentum_x[node] < 0)
        testing.expect(t, ps^.dust_field.momentum_y[node] > 0)
    }
    testing.expect_value(t, ps^.dust_field.momentum_x[outside_node], f32(0))
    testing.expect_value(t, ps^.dust_field.momentum_y[outside_node], f32(0))
}

// Verify floor-tool force never changes an airborne particle's ballistic state.
@(test)
dust_tool_contact_does_not_affect_airborne_particle :: proc(t: ^testing.T) {
    expected := new(particlemodel.Particle_System, context.allocator)
    actual := new(particlemodel.Particle_System, context.allocator)
    defer free(expected)
    defer free(actual)
    expected^.use_max_dust_particles = 1
    actual^.use_max_dust_particles = 1
    expected^.low_particles[0] = {pos_x = 0.505, pos_y = 0.5, pos_z = 0.1,
        vel_x = 0.001, vel_y = -0.002, life = 100, alive = true}
    actual^.low_particles[0] = expected^.low_particles[0]
    testing.expect(t, queue_dust_tool_contact(actual, {
        endpoint = {0.5, 0.5, 0}}))

    update_particles(expected, f32(1.0 / 60.0))
    update_particles(actual, f32(1.0 / 60.0))

    testing.expect_value(t, actual^.low_particles[0], expected^.low_particles[0])
}

// Verify generation boundaries discard pending field force without applying it.
@(test)
dust_tool_contact_discard_clears_pending_force :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    testing.expect(t, queue_dust_tool_contact(ps, {endpoint = {0.2, 0.25, 0}}))

    discard_dust_tool_contacts(ps)

    testing.expect_value(t, ps^.dust_tool_contact_count, 0)
}

// Verify authored vertical kick returns grounded dust to airborne authority.
@(test)
dust_kick_creates_airborne_particle :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0] = {pos_x = 0.5, pos_y = 0.5, pos_z = DUST_FLOOR_Z,
        life = 1, color = colormodel.WHITE, alive = true}

    kick_existing_dust_index(ps, 0)
    integrate_dust_positions(ps)
    update_particle_dust_index(ps, 0)

    testing.expect(t, ps^.low_particles.pos_z[0] > DUST_FLOOR_Z)
}

// Verify gravity does not create a recurring bounce for grounded dust at rest.
@(test)
update_particle_dust_index_keeps_grounded_particle_at_rest :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0].alive = true
    ps^.low_particles[0].life = 1
    ps^.low_particles.pos_z[0] = DUST_FLOOR_Z

    update_particle_dust_index(ps, 0)

    testing.expect_value(t, ps^.low_particles.pos_z[0], f32(DUST_FLOOR_Z))
    testing.expect_value(t, ps^.low_particles.vel_z[0], f32(0))
    testing.expect_value(t, ps^.dust_floor_rest_count, 1)
}

// Verify maximum authored vertical launch converges to grounded rest.
@(test)
update_particle_dust_index_settles_authored_vertical_launch :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0].alive = true
    ps^.low_particles[0].life = 1
    ps^.low_particles.vel_z[0] = DUST_VZ_MAX

    for _ in 0..<120 {
        integrate_dust_positions(ps)
        update_particle_dust_index(ps, 0)
    }

    testing.expect_value(t, ps^.low_particles.pos_z[0], f32(DUST_FLOOR_Z))
    testing.expect_value(t, ps^.low_particles.vel_z[0], f32(0))
}

// Verify two fresh particle systems produce identical seeded random ranges.
@(test)
particle_random_ranges_use_independent_seeded_generators :: proc(t: ^testing.T) {
    first := new(particlemodel.Particle_System, context.allocator)
    defer free(first)
    second := new(particlemodel.Particle_System, context.allocator)
    defer free(second)

    testing.expect_value(t,
        random_f32_range(first, -1, 1),
        random_f32_range(second, -1, 1))
    testing.expect_value(t,
        random_i32_range(first, -10, 10),
        random_i32_range(second, -10, 10))
}

// Verify scenario emission is deterministic without consuming authored RNG state.
@(test)
scenario_dust_emission_is_deterministic_and_rng_isolated :: proc(t: ^testing.T) {
    first := new(particlemodel.Particle_System, context.allocator)
    defer free(first)
    second := new(particlemodel.Particle_System, context.allocator)
    defer free(second)
    control := new(particlemodel.Particle_System, context.allocator)
    defer free(control)
    first^.use_max_dust_particles = 32
    second^.use_max_dust_particles = 32
    control^.use_max_dust_particles = 32
    request := particlemodel.Scenario_Dust_Emission_Request{
        distribution = .Disc, count = 16, x = 0.5, y = 0.5,
        radius = 0.04, seed = 17}

    testing.expect_value(t, emit_scenario_dust(first, request), 16)
    testing.expect_value(t, emit_scenario_dust(second, request), 16)
    for index in 0..<16 {
        testing.expect_value(t,
            first^.low_particles[index], second^.low_particles[index])
        testing.expect_value(t,
            first^.dust_slot_spawn_sequences[index], u64(index + 1))
    }
    testing.expect_value(t,
        random_f32_range(first, -1, 1), random_f32_range(control, -1, 1))
}

// Verify identical emission, contact, and kick streams remain deterministic.
@(test)
scenario_dust_contact_and_kick_stream_is_deterministic :: proc(t: ^testing.T) {
    first := new(particlemodel.Particle_System, context.allocator)
    defer free(first)
    second := new(particlemodel.Particle_System, context.allocator)
    defer free(second)
    first^.use_max_dust_particles = 16
    second^.use_max_dust_particles = 16
    request := particlemodel.Scenario_Dust_Emission_Request{
        distribution = .Point, count = 16, x = 0.51, y = 0.51, seed = 23}
    testing.expect_value(t, emit_scenario_dust(first, request), 16)
    testing.expect_value(t, emit_scenario_dust(second, request), 16)

    for _ in 0..<360 {
        update_particles(first, 1.0 / 60.0)
        update_particles(second, 1.0 / 60.0)
    }
    queue_dust_slot_contacts(t, first)
    queue_dust_slot_contacts(t, second)
    update_particles(first, 1.0 / 60.0)
    update_particles(second, 1.0 / 60.0)
    kick_existing_dust(first)
    kick_existing_dust(second)
    update_particles(first, 1.0 / 60.0)
    update_particles(second, 1.0 / 60.0)

    expect_dust_systems_match(t, first, second)
}

// Verify grounded particles receive field velocity while airborne particles do not.
@(test)
dust_update_affects_only_grounded_particles :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 2
    ps^.low_particles[0] = {
        pos_x = 0.25, pos_y = 0.75, pos_z = DUST_FLOOR_Z,
        vel_x = 0.003, vel_y = -0.002, alive = true}
    ps^.low_particles[1] = {
        pos_x = 0.25, pos_y = 0.75, pos_z = DUST_FLOOR_Z + 0.1,
        vel_x = -0.004, vel_y = 0.005, alive = true}
    airborne_velocity := Vector2{
        ps^.low_particles.vel_x[1], ps^.low_particles.vel_y[1]}

    dust_field_update_grounded(ps, f32(1.0 / 60.0))

    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
    testing.expect(t, ps^.low_particles.vel_x[0] < 0.003)
    testing.expect_value(t, ps^.low_particles.vel_x[1], airborne_velocity.x)
    testing.expect_value(t, ps^.low_particles.vel_y[1], airborne_velocity.y)
    test_helpers.expect_close(t,
        dust_test_plane_sum(&ps^.dust_field.density), 1,
        "only grounded density")
}

// Verify landing momentum enters the vector field before exact assignment.
@(test)
update_particles_deposits_landing_momentum :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0] = {
        pos_x = 0.5, pos_y = 0.5, pos_z = 0.001,
        vel_x = 0.003, vel_y = -0.002, vel_z = -0.01,
        life = 10, alive = true}

    update_particles(ps, f32(1.0 / 60.0))

    testing.expect_value(t, ps^.low_particles.pos_z[0], f32(DUST_FLOOR_Z))
    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
    testing.expect(t, ps^.low_particles.vel_y[0] < 0)
    test_helpers.expect_close(t,
        dust_test_plane_sum(&ps^.dust_field.density), 1,
        "landing density")
}

// Verify the production step performs no legacy grounded solver work.
@(test)
update_particles_bypasses_legacy_grounded_authorities :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 2
    for index in 0..<2 {
        ps^.low_particles[index] = {
            pos_x = 0.5, pos_y = 0.5, pos_z = DUST_FLOOR_Z,
            life = 10, alive = true}
    }

    update_particles(ps, f32(1.0 / 60.0))

    testing.expect_value(t, ps^.dust_grounded_count, 2)
    testing.expect(t, ps^.dust_peak_speed_sq >= 0)
}

// Verify P2G caches grounded particles once in stable slot order.
@(test)
dust_transfers_are_stable_and_grounded_only :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 4
    ps^.low_particles[0] = {
        pos_x = 0.2, pos_y = 0.3, pos_z = DUST_FLOOR_Z,
        vel_x = 0.001, life = 10, alive = true}
    ps^.low_particles[1] = {
        pos_x = 0.4, pos_y = 0.5, pos_z = DUST_FLOOR_Z + 0.1,
        vel_x = 0.007, life = 10, alive = true}
    ps^.low_particles[3] = {
        pos_x = 0.7, pos_y = 0.8, pos_z = DUST_FLOOR_Z,
        vel_y = -0.002, life = 10, alive = true}

    dust_field_deposit_grounded(ps)

    testing.expect_value(t, ps^.dust_transfer_count, 2)
    testing.expect_value(t, ps^.dust_transfers[0].particle_index, i32(0))
    testing.expect_value(t, ps^.dust_transfers[1].particle_index, i32(3))
    test_helpers.expect_close(t,
        dust_test_plane_sum(&ps^.dust_field.density), 2,
        "grounded transfer density")
}

// Verify the fused low-dust pass matches the former stable three-pass sequence.
expect_low_dust_deposit_state_equal :: proc(t: ^testing.T,
    actual, expected: ^particlemodel.Particle_System) {
    for index in 0..<expected^.use_max_dust_particles {
        testing.expect_value(t, actual^.low_particles[index],
            expected^.low_particles[index])
    }
    testing.expect_value(t, actual^.dust_floor_rest_count,
        expected^.dust_floor_rest_count)
    testing.expect_value(t, actual^.dust_field.support_bounds,
        expected^.dust_field.support_bounds)
    testing.expect_value(t, actual^.dust_transfer_count,
        expected^.dust_transfer_count)
}

// Verify the fused low-dust pass matches the former stable three-pass sequence.
@(test)
update_and_deposit_low_dust_matches_sequential_reference :: proc(t: ^testing.T) {
    expected := new(particlemodel.Particle_System, context.allocator)
    defer free(expected)
    actual := new(particlemodel.Particle_System, context.allocator)
    defer free(actual)
    expected^.use_max_dust_particles = 5
    actual^.use_max_dust_particles = expected^.use_max_dust_particles
    expected^.low_particles[0] = {
        pos_x = 0.3, pos_y = 0.4, pos_z = DUST_FLOOR_Z,
        vel_x = 0.001, vel_y = -0.002, life = 10, alive = true}
    expected^.low_particles[1] = {
        pos_x = 0.5, pos_y = 0.6, pos_z = 0.001,
        vel_x = 0.003, vel_y = 0.002, vel_z = -0.01, life = 10, alive = true}
    expected^.low_particles[2] = {
        pos_x = 0.7, pos_y = 0.8, pos_z = 0.2,
        vel_x = -0.004, vel_y = 0.005, vel_z = 0.003, life = 10, alive = true}
    expected^.low_particles[4] = {
        pos_x = 1, pos_y = 0, pos_z = DUST_FLOOR_Z,
        vel_x = 0.01, vel_y = -0.01, life = 10, alive = true}
    for index in 0..<5 {
        actual^.low_particles[index] = expected^.low_particles[index]
    }

    integrate_dust_positions(expected)
    for index in 0..<5 {
        update_particle_dust_index(expected, index)
    }
    dust_field_deposit_grounded(expected)
    update_and_deposit_low_dust(actual)
    expect_low_dust_deposit_state_equal(t, actual, expected)
}

// Verify reset_particles zeroes runtime state and marks every slot dead.
@(test)
reset_particles_clears_runtime_state_and_marks_all_slots_dead :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)

    ps^.use_max_dust_particles = 2
    ps^.spawn_timer = 1.0
    ps^.next_index = 3
    ps^.low_particles.alive[0] = true
    ps^.low_particles.age[0] = 0.25
    ps^.particles.alive[0] = true
    ps^.particles.age[0] = 0.5
    ps^.high_particles.alive[0] = true
    ps^.high_particles.age[0] = 0.75
    ps^.dust_transfer_count = 2

    reset_particles(ps)

    testing.expect_value(t, ps^.next_index, 0)
    testing.expect_value(t, ps^.spawn_timer, 0.0)
    testing.expect_value(t, ps^.dust_transfer_count, 0)
    testing.expect(t, !ps^.low_particles.alive[0])
    testing.expect_value(t, ps^.low_particles.age[0], 0.0)
    testing.expect(t, !ps^.particles.alive[0])
    testing.expect_value(t, ps^.particles.age[0], 0.0)
    testing.expect(t, !ps^.high_particles.alive[0])
    testing.expect_value(t, ps^.high_particles.age[0], 0.0)
}

// Verify reset_particles clears queued contact state and diagnostics.
@(test)
reset_particles_clears_dust_tool_contact_state :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.dust_tool_contact_count = 2
    ps^.dust_tool_contact_overflow_count = 3
    ps^.dust_tool_contact_coalesced_count = 4
    ps^.dust_tool_contact_sample_count = 5

    reset_particles(ps)

    testing.expect_value(t, ps^.dust_tool_contact_count, 0)
    testing.expect_value(t, ps^.dust_tool_contact_overflow_count, 0)
    testing.expect_value(t, ps^.dust_tool_contact_coalesced_count, u64(0))
    testing.expect_value(t, ps^.dust_tool_contact_sample_count, u64(0))
    testing.expect_value(t, ps^.dust_tool_contact_field_node_visit_count, u64(0))
}

// Verify slot reservation wraps to index zero when every slot is alive.
@(test)
reserve_dead_low_particle_slot_wraps_when_all_slots_alive :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)

    ps^.use_max_dust_particles = 2
    ps^.next_index = 0
    ps^.low_particles.alive[0] = true
    ps^.low_particles.alive[1] = true

    idx, ok := reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok)
    testing.expect_value(t, idx, 0)
    testing.expect_value(t, ps^.next_index, 1)
}

// Seed one world line with direct endpoint transforms and configurable visibility.
seed_shape_world_particle_line :: proc(
    world: ^shapemodel.Shape_World,
    visible: bool) {
    shape, first, second: shapemodel.Shape_Entity
    assert(shapemodel.shape_world_create_entity(world, &shape) == .Ok)
    assert(shapemodel.shape_world_create_entity(world, &first) == .Ok)
    assert(shapemodel.shape_world_create_entity(world, &second) == .Ok)
    assert(shapemodel.shape_component_insert(&world.transforms, &world.registry,
        first, shapemodel.Shape_Transform{position = {0, 0, 0}}) == .Ok)
    assert(shapemodel.shape_component_insert(&world.transforms, &world.registry,
        second, shapemodel.Shape_Transform{position = {1, 0, 0}}) == .Ok)
    assert(shapemodel.shape_component_insert(&world.render_styles, &world.registry,
        shape, shapemodel.Shape_Render_Style{visible = visible}) == .Ok)
    geometry := shapemodel.Shape_Geometry{kind = .Line}
    geometry.payload.line = {first = first, second = second}
    assert(shapemodel.shape_component_insert(&world.geometries, &world.registry,
        shape, geometry) == .Ok)
}

// Verify world clear particles resolve direct line entities without child topology.
@(test)
emit_shape_world_clear_burst_spawns_dust_for_direct_line :: proc(t: ^testing.T) {
    particles := new(particlemodel.Particle_System, context.allocator)
    defer free(particles)
    particles.use_max_dust_particles = 4
    world: shapemodel.Shape_World
    seed_shape_world_particle_line(&world, true)

    emit_shape_world_clear_burst(particles, &world)

    testing.expect(t, particles.low_particles.alive[0])
    testing.expect(t, particles.low_particles.alive[1])
}

// Verify hidden world geometry does not participate in clear particle emission.
@(test)
emit_shape_world_clear_burst_skips_hidden_geometry :: proc(t: ^testing.T) {
    particles := new(particlemodel.Particle_System, context.allocator)
    defer free(particles)
    particles.use_max_dust_particles = 4
    world: shapemodel.Shape_World
    seed_shape_world_particle_line(&world, false)

    emit_shape_world_clear_burst(particles, &world)

    for alive in particles.low_particles.alive[:particles.use_max_dust_particles] {
        testing.expect(t, !alive)
    }
}

// Verify out-of-bounds particles clamp to the bounds and bounce their velocity.
@(test)
clamp_xy_bounds_index_bounces_particles_back_inside_bounds :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1

    ps^.low_particles.pos_x[0] = -0.5
    ps^.low_particles.pos_y[0] = 1.2
    ps^.low_particles.vel_x[0] = -0.1
    ps^.low_particles.vel_y[0] = 0.2

    clamp_xy_bounds_index(ps, 0)

    testing.expect_value(t, ps^.low_particles.pos_x[0], DUST_XY_MIN)
    testing.expect_value(t, ps^.low_particles.pos_y[0], DUST_XY_MAX)
    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
    testing.expect(t, ps^.low_particles.vel_y[0] < 0)
}
