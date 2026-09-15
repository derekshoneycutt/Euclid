package particles

import particlemodel "model"
import shapemodel "../shapes/model"

import "core:math"
import "core:testing"

import rl "vendor:raylib"

import test_helpers "../test_helpers"

EPS :: f32(1e-5)

//   Snapshot one low-particle slot's position and velocity.
Dust_Slot_Snapshot :: struct {
    x:  f32,
    y:  f32,
    vx: f32,
    vy: f32,
}

//   Verify theta normalization and sweep delta wrap correctly across zero.
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

//   Count live low-layer particles within the configured test capacity.
count_live_low_particles :: proc(ps: ^particlemodel.Particle_System) -> int {
    count: int
    for alive in ps.low_particles.alive[:ps.use_max_dust_particles] {
        if alive {
            count += 1
        }
    }
    return count
}

//   Verify outlined arc emission scales with visible arc length.
@(test)
circle_dust_emission_scales_with_arc_length :: proc(t: ^testing.T) {
    quarter := new(particlemodel.Particle_System, context.allocator)
    full := new(particlemodel.Particle_System, context.allocator)
    defer free(quarter)
    defer free(full)
    quarter.use_max_dust_particles = 1000
    full.use_max_dust_particles = 1000
    color := rl.Color{255, 255, 255, 255}

    emit_circle_dust(quarter, {{0, 0, 0}, {0.2, 0, 0}, {0, 0.2, 0}, 0, color})
    emit_circle_dust(full, {
        {0, 0, 0}, {0.2, 0, 0}, {0.2, 0, 0}, f32(2 * math.PI), color})

    quarter_count := count_live_low_particles(quarter)
    full_count := count_live_low_particles(full)
    testing.expect(t, quarter_count < full_count)
    testing.expect(t, full_count >= quarter_count * 3)
}

//   Verify filled arc emission occupies the sector interior instead of only its rim.
@(test)
filled_circle_dust_emission_samples_sector_interior :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps.use_max_dust_particles = 1000

    emit_filled_circle_dust(ps, {
        {0, 0, 0}, {0.2, 0, 0},
        {0.1, math.sqrt(f32(3)) * 0.1, 0}, 0,
        rl.Color{255, 255, 255, 255}})

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

//   Verify dust_grid_cell_index clamps out-of-range coordinates to the grid.
@(test)
dust_grid_cell_index_clamps_bounds :: proc(t: ^testing.T) {
    testing.expect_value(t, dust_grid_cell_index(-1, -1), 0)

    max_idx := DUST_GRID_DIM * DUST_GRID_DIM - 1
    testing.expect_value(t, dust_grid_cell_index(99, 99), max_idx)
}

// Verify exact grid membership retains every particle above the collision sample cap.
@(test)
exact_dust_grid_retains_dense_cell_membership :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = particlemodel.DUST_COLLISION_CELL_SAMPLE_CAP + 8
    for index in 0..<ps^.use_max_dust_particles {
        ps^.low_particles[index].alive = true
        ps^.low_particles.pos_x[index] = 0.5
        ps^.low_particles.pos_y[index] = 0.5
    }

    build_exact_dust_grid(ps)

    cell := dust_grid_cell_index(0.5, 0.5)
    testing.expect_value(t, ps^.dust_active_cell_count, 1)
    testing.expect_value(t, ps^.dust_exact_counts[cell],
        i32(ps^.use_max_dust_particles))
    first := int(ps^.dust_exact_offsets[cell])
    last := int(ps^.dust_exact_offsets[cell + 1])
    testing.expect_value(t, last - first, ps^.use_max_dust_particles)
    for index in 0..<ps^.use_max_dust_particles {
        testing.expect_value(t, ps^.dust_exact_indices[first + index], i32(index))
    }
}

//   Verify slot reservation prefers dead slots and wraps at the particle cap.
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

// Verify exact-grid active-cell storage accepts every possible cell once.
@(test)
exact_dust_grid_tracks_all_cells_at_capacity :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = DUST_GRID_DIM_SQUARED
    for index in 0..<DUST_GRID_DIM_SQUARED {
        cell_x := index % DUST_GRID_DIM
        cell_y := index / DUST_GRID_DIM
        ps^.low_particles[index].alive = true
        ps^.low_particles.pos_x[index] =
            (f32(cell_x) + 0.5) * DUST_GRID_CELL_SIZE
        ps^.low_particles.pos_y[index] =
            (f32(cell_y) + 0.5) * DUST_GRID_CELL_SIZE
    }

    build_exact_dust_grid(ps)

    testing.expect_value(t, ps^.dust_active_cell_count, DUST_GRID_DIM_SQUARED)
    for index in 0..<DUST_GRID_DIM_SQUARED {
        testing.expect_value(t, ps^.dust_active_cells[index], i32(index))
        testing.expect_value(t, ps^.dust_exact_counts[index], i32(1))
    }
}

//   Verify the reservation ring index wraps back to zero at the cap.
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

//   Capture one low-particle slot's current position and velocity.
dust_slot_snapshot :: #force_inline proc(
    ps: ^particlemodel.Particle_System, index: int) -> Dust_Slot_Snapshot {

    return Dust_Slot_Snapshot{
        ps^.low_particles.pos_x[index],
        ps^.low_particles.pos_y[index],
        ps^.low_particles.vel_x[index],
        ps^.low_particles.vel_y[index],
    }
}

//   Assert one low-particle slot still matches a prior snapshot.
expect_dust_slot_unchanged :: proc(
    t: ^testing.T,
    ps: ^particlemodel.Particle_System,
    index: int,
    before: Dust_Slot_Snapshot) {

    test_helpers.expect_close(t, ps^.low_particles.pos_x[index], before.x,
        "no collision should keep x")
    test_helpers.expect_close(t, ps^.low_particles.pos_y[index], before.y,
        "no collision should keep y")
    test_helpers.expect_close(t, ps^.low_particles.vel_x[index], before.vx,
        "no collision should keep vx")
    test_helpers.expect_close(t, ps^.low_particles.vel_y[index], before.vy,
        "no collision should keep vy")
}

//   Assert two particle systems have matching low-particle slots and RNG state.
expect_dust_systems_match :: proc(
    t: ^testing.T, actual, expected: ^particlemodel.Particle_System) {
    for index in 0..<expected^.use_max_dust_particles {
        actual_slot := dust_slot_snapshot(actual, index)
        expected_slot := dust_slot_snapshot(expected, index)
        test_helpers.expect_close(t, actual_slot.x, expected_slot.x, "slot x")
        test_helpers.expect_close(t, actual_slot.y, expected_slot.y, "slot y")
        test_helpers.expect_close(t, actual_slot.vx, expected_slot.vx, "slot vx")
        test_helpers.expect_close(t, actual_slot.vy, expected_slot.vy, "slot vy")
    }
    testing.expect_value(t, actual^.rng_state, expected^.rng_state)
}

//   Queue one point contact at every live low-particle slot.
queue_dust_slot_contacts :: proc(
    t: ^testing.T, ps: ^particlemodel.Particle_System) {
    for index in 0..<ps^.use_max_dust_particles {
        testing.expect(t, queue_dust_tool_contact(ps, {endpoint = {
            ps^.low_particles.pos_x[index], ps^.low_particles.pos_y[index], 0}}))
    }
}

// Solve queued tool contacts through the grounded vector-field path.
solve_test_dust_tool_contacts :: proc(ps: ^particlemodel.Particle_System) {
    vector_dust_field_deposit_grounded(ps)
    apply_dust_tool_contacts_to_field(ps)
    vector_dust_field_evolve(&ps^.vector_dust_field, f32(1.0 / 60.0))
    vector_dust_field_assign_grounded(ps)
}

// Verify queued contact changes field momentum without correcting position directly.
@(test)
dust_tool_contact_applies_through_field_without_position_correction :: proc(
        t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0] = {
        pos_x = 0.505, pos_y = 0.5, life = 100, alive = true}
    before := dust_slot_snapshot(ps, 0)
    testing.expect(t, queue_dust_tool_contact(ps, {endpoint = {0.5, 0.5, 0}}))

    vector_dust_field_deposit_grounded(ps)
    apply_dust_tool_contacts_to_field(ps)

    testing.expect_value(t, ps^.low_particles.pos_x[0], before.x)
    testing.expect_value(t, ps^.low_particles.pos_y[0], before.y)
    testing.expect(t, vector_dust_test_plane_sum(
        &ps^.vector_dust_field.momentum_x) > 0)
    vector_dust_field_evolve(&ps^.vector_dust_field, f32(1.0 / 60.0))
    vector_dust_field_assign_grounded(ps)
    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
    testing.expect_value(t, ps^.dust_tool_contact_count, 0)
}

// Verify sweep intervals follow contact radius and remain statically bounded.
@(test)
dust_tool_sweep_intervals_follow_radius :: proc(t: ^testing.T) {
    origin := Vector3{}
    radius := f32(DUST_CONTACT_PUSH_RADIUS)
    testing.expect_value(t, dust_tool_sweep_interval_count(origin, origin), 1)
    testing.expect_value(t, dust_tool_sweep_interval_count(
        origin, {radius * 0.5, 0, 0}), 1)
    testing.expect_value(t, dust_tool_sweep_interval_count(
        origin, {radius, 0, 0}), 1)
    testing.expect_value(t, dust_tool_sweep_interval_count(
        origin, {0.08, 0.06, 0}), 10)
    testing.expect_value(t, dust_tool_sweep_interval_count(
        origin, {1, 1, 0}), 142)
    testing.expect_value(t, dust_tool_sweep_interval_count(
        origin, {2, 2, 0}), DUST_TOOL_SWEEP_MAX_INTERVALS)
}

// Verify generated samples include both endpoints with radius-bounded gaps.
@(test)
dust_tool_sweep_sampling_is_inclusive_and_radius_bounded :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    first := Vector3{0.1, 0.2, 0}
    second := Vector3{0.125, 0.2, 0}
    interval_count := dust_tool_sweep_interval_count(first, second)
    spacing := (second.x - first.x) / f32(interval_count)
    testing.expect(t, spacing <= f32(DUST_CONTACT_PUSH_RADIUS))
    testing.expect(t, queue_dust_tool_contact(ps, {
        endpoint = second, segment_first = first, segment_second = second,
        has_sweep = true, source = .Compass_Span}))

    apply_dust_tool_contacts_to_field(ps)

    testing.expect_value(t, interval_count, 3)
    testing.expect_value(t, ps^.dust_tool_contact_sample_count, u64(4))

    testing.expect(t, queue_dust_tool_contact(ps, {endpoint = first}))
    apply_dust_tool_contacts_to_field(ps)
    testing.expect_value(t, ps^.dust_tool_contact_sample_count, u64(1))

    testing.expect(t, queue_dust_tool_contact(ps, {
        endpoint = first, segment_first = first, segment_second = first,
        has_sweep = true, source = .Compass_Span}))
    apply_dust_tool_contacts_to_field(ps)
    testing.expect_value(t, ps^.dust_tool_contact_sample_count, u64(2))
}

// Verify reversing a span preserves its response away from exact-center RNG cases.
@(test)
dust_tool_sweep_response_is_orientation_symmetric :: proc(t: ^testing.T) {
    forward := new(particlemodel.Particle_System, context.allocator)
    reverse := new(particlemodel.Particle_System, context.allocator)
    defer free(forward)
    defer free(reverse)
    forward^.use_max_dust_particles = 2
    reverse^.use_max_dust_particles = 2
    forward^.low_particles[0] = {
        pos_x = 0.095, pos_y = 0.5, life = 100, alive = true}
    forward^.low_particles[1] = {
        pos_x = 0.905, pos_y = 0.5, life = 100, alive = true}
    reverse^.low_particles[0] = forward^.low_particles[0]
    reverse^.low_particles[1] = forward^.low_particles[1]
    first := Vector3{0.1, 0.5, 0}
    second := Vector3{0.9, 0.5, 0}
    testing.expect(t, queue_dust_tool_contact(forward, {
        segment_first = first, segment_second = second, has_sweep = true}))
    testing.expect(t, queue_dust_tool_contact(reverse, {
        segment_first = second, segment_second = first, has_sweep = true}))
    solve_test_dust_tool_contacts(forward)
    solve_test_dust_tool_contacts(reverse)

    expect_dust_systems_match(t, forward, reverse)
    testing.expect_value(t, forward^.dust_tool_contact_sample_count, u64(81))
    testing.expect_value(t, reverse^.dust_tool_contact_sample_count, u64(81))
}

// Verify sweep force scales with touched field nodes rather than particle count.
@(test)
dust_tool_sweep_visits_bounded_field_nodes :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 2
    ps^.low_particles[0] = {
        pos_x = 0.095, pos_y = 0.5, life = 100, alive = true}
    ps^.low_particles[1] = {
        pos_x = 0.905, pos_y = 0.5, life = 100, alive = true}
    testing.expect(t, queue_dust_tool_contact(ps, {
        endpoint = {0.9, 0.5, 0},
        segment_first = {0.1, 0.5, 0},
        segment_second = {0.9, 0.5, 0},
        has_sweep = true,
    }))
    solve_test_dust_tool_contacts(ps)

    testing.expect_value(t, ps^.dust_tool_contact_sample_count, u64(81))
    testing.expect(t, ps^.dust_tool_contact_field_node_visit_count < 2500)
    testing.expect(t, ps^.low_particles.vel_x[0] < 0)
    testing.expect(t, ps^.low_particles.vel_x[1] > 0)
}

// Verify field force changes velocity only after fixed-step position integration.
@(test)
dust_tool_contact_applies_after_fixed_step_position_integration :: proc(t: ^testing.T) {
    expected := new(particlemodel.Particle_System, context.allocator)
    actual := new(particlemodel.Particle_System, context.allocator)
    defer free(expected)
    defer free(actual)
    expected^.use_max_dust_particles = 1
    actual^.use_max_dust_particles = 1
    expected^.low_particles[0] = {
        pos_x = 0.2, pos_y = 0.25, life = 100, size = 0.01, alive = true}
    actual^.low_particles[0] = expected^.low_particles[0]
    endpoint := Vector3{0.195, 0.25, 0}
    update_particles(expected, f32(1.0 / 60.0))
    testing.expect(t, queue_dust_tool_contact(actual, {endpoint = endpoint}))
    update_particles(actual, f32(1.0 / 60.0))

    testing.expect_value(t, actual^.low_particles.pos_x[0],
        expected^.low_particles.pos_x[0])
    testing.expect_value(t, actual^.low_particles.pos_y[0],
        expected^.low_particles.pos_y[0])
    testing.expect(t, actual^.low_particles.vel_x[0] >
        expected^.low_particles.vel_x[0])
}

// Verify grounded field velocity continues after the contact queue is consumed.
@(test)
dust_tool_contact_velocity_persists_after_contact :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0] = {
        pos_x = 0.505, pos_y = 0.5, life = 100, alive = true}
    testing.expect(t, queue_dust_tool_contact(ps, {endpoint = {0.5, 0.5, 0}}))

    update_particles(ps, f32(1.0 / 60.0))
    first_velocity := ps^.low_particles.vel_x[0]
    update_particles(ps, f32(1.0 / 60.0))

    testing.expect(t, first_velocity > 0)
    testing.expect_value(t, ps^.dust_tool_contact_count, 0)
    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
}

// Verify shared field force includes a grounded particle spawned later in the step.
@(test)
dust_tool_contact_includes_later_grounded_spawn_sequence :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    testing.expect(t, queue_dust_tool_contact(ps, {endpoint = {0.5, 0.5, 0}}))
    ps^.dust_spawn_sequence = 1
    ps^.dust_slot_spawn_sequences[0] = 1
    ps^.low_particles[0] = {
        pos_x = 0.505, pos_y = 0.5, life = 100, alive = true}

    solve_test_dust_tool_contacts(ps)

    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
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

// Verify adjacent redundant contacts coalesce without crossing source or spawn bounds.
@(test)
dust_tool_contacts_coalesce_only_with_matching_semantics :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    first_span := particlemodel.Dust_Tool_Contact{
        endpoint = {0.1, 0.2, 0}, segment_first = {0.1, 0.2, 0},
        segment_second = {0.4, 0.2, 0}, has_sweep = true,
        source = .Compass_Span}
    final_span := first_span
    final_span.endpoint = {0.5, 0.2, 0}
    final_span.segment_second = final_span.endpoint
    duplicate := particlemodel.Dust_Tool_Contact{
        endpoint = {0.7, 0.8, 0}, source = .Point}
    testing.expect(t, queue_dust_tool_contact(ps, first_span))
    testing.expect(t, queue_dust_tool_contact(ps, final_span))
    testing.expect(t, queue_dust_tool_contact(ps, duplicate))
    testing.expect(t, queue_dust_tool_contact(ps, duplicate))
    scenario := duplicate
    scenario.source = .Scenario
    testing.expect(t, queue_dust_tool_contact(ps, scenario))
    ps^.dust_spawn_sequence += 1
    testing.expect(t, queue_dust_tool_contact(ps, scenario))

    coalesce_dust_tool_contacts(ps)

    testing.expect_value(t, ps^.dust_tool_contact_count, 4)
    testing.expect_value(t, ps^.dust_tool_contact_coalesced_count, u64(2))
    testing.expect_value(t, ps^.dust_tool_contacts[0], final_span)
    testing.expect_value(t, ps^.dust_tool_contacts[1], duplicate)
    testing.expect_value(t, ps^.dust_tool_contacts[2].source,
        particlemodel.Dust_Tool_Contact_Source.Scenario)
    testing.expect_value(t, ps^.dust_tool_contacts[2].max_spawn_sequence, u64(0))
    testing.expect_value(t, ps^.dust_tool_contacts[3].max_spawn_sequence, u64(1))
}

//   Verify a non-overlapping dust pair keeps positions and velocities unchanged.
@(test)
resolve_dust_pair_no_collision_keeps_state :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)

    ps^.low_particles.pos_x[0] = 0.2
    ps^.low_particles.pos_y[0] = 0.2
    ps^.low_particles.pos_x[1] = 0.9
    ps^.low_particles.pos_y[1] = 0.9

    ps^.low_particles.vel_x[0] = 0.01
    ps^.low_particles.vel_y[0] = -0.02
    ps^.low_particles.vel_x[1] = -0.03
    ps^.low_particles.vel_y[1] = 0.04

    before_a := dust_slot_snapshot(ps, 0)
    before_b := dust_slot_snapshot(ps, 1)

    resolve_dust_pair(ps, 0, 1)

    expect_dust_slot_unchanged(t, ps, 0, before_a)
    expect_dust_slot_unchanged(t, ps, 1, before_b)
}

//   Verify an approaching overlapping pair receives a separating impulse.
@(test)
resolve_dust_pair_overlap_with_approach_applies_impulse :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)

    ps^.low_particles.pos_x[0] = 0.4
    ps^.low_particles.pos_y[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.403
    ps^.low_particles.pos_y[1] = 0.5

    ps^.low_particles.vel_x[0] = 0.01
    ps^.low_particles.vel_y[0] = 0.0
    ps^.low_particles.vel_x[1] = -0.01
    ps^.low_particles.vel_y[1] = 0.0

    before_x0 := ps^.low_particles.pos_x[0]
    before_x1 := ps^.low_particles.pos_x[1]

    resolve_dust_pair(ps, 0, 1)

    testing.expect(t, ps^.low_particles.pos_x[0] < before_x0)
    testing.expect(t, ps^.low_particles.pos_x[1] > before_x1)
    testing.expect(t, ps^.low_particles.vel_x[0] < 0)
    testing.expect(t, ps^.low_particles.vel_x[1] > 0)
}

//   Verify a separating overlapping pair repositions but skips the impulse.
@(test)
resolve_dust_pair_overlap_with_separating_velocity_skips_impulse :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)

    ps^.low_particles.pos_x[0] = 0.4
    ps^.low_particles.pos_y[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.403
    ps^.low_particles.pos_y[1] = 0.5

    ps^.low_particles.vel_x[0] = -0.01
    ps^.low_particles.vel_y[0] = 0.0
    ps^.low_particles.vel_x[1] = 0.01
    ps^.low_particles.vel_y[1] = 0.0

    before_x0 := ps^.low_particles.pos_x[0]
    before_x1 := ps^.low_particles.pos_x[1]

    resolve_dust_pair(ps, 0, 1)

    testing.expect(t, ps^.low_particles.pos_x[0] < before_x0)
    testing.expect(t, ps^.low_particles.pos_x[1] > before_x1)
    test_helpers.expect_close(t, ps^.low_particles.vel_x[0], f32(-0.01),
        "separating vx0 should be unchanged")
    test_helpers.expect_close(t, ps^.low_particles.vel_x[1], f32(0.01),
        "separating vx1 should be unchanged")
}

//   Verify exactly coincident particles use a stable separation direction.
@(test)
resolve_dust_pair_exact_overlap_uses_deterministic_separation :: proc(t: ^testing.T) {
    first := new(particlemodel.Particle_System, context.allocator)
    defer free(first)
    second := new(particlemodel.Particle_System, context.allocator)
    defer free(second)

    first^.low_particles.pos_x[0] = 0.5
    first^.low_particles.pos_y[0] = 0.5
    first^.low_particles.pos_x[1] = 0.5
    first^.low_particles.pos_y[1] = 0.5
    second^.low_particles.pos_x[0] = 0.5
    second^.low_particles.pos_y[0] = 0.5
    second^.low_particles.pos_x[1] = 0.5
    second^.low_particles.pos_y[1] = 0.5
    first^.dust_collision_frame = 1
    second^.dust_collision_frame = 200

    resolve_dust_pair(first, 0, 1)
    resolve_dust_pair(second, 0, 1)

    dx := first^.low_particles.pos_x[1] - first^.low_particles.pos_x[0]
    dy := first^.low_particles.pos_y[1] - first^.low_particles.pos_y[0]
    testing.expect(t, dx * dx + dy * dy > 0)
    testing.expect_value(t,
        first^.low_particles.pos_x[0], second^.low_particles.pos_x[0])
    testing.expect_value(t,
        first^.low_particles.pos_y[0], second^.low_particles.pos_y[0])
}

//   Verify quiet approaching particles lose relative normal motion without rebounding.
@(test)
resolve_dust_pair_low_speed_contact_is_inelastic :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.low_particles.pos_x[0] = 0.5
    ps^.low_particles.pos_y[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.503
    ps^.low_particles.pos_y[1] = 0.5
    ps^.low_particles.vel_x[0] = 0.0001
    ps^.low_particles.vel_x[1] = -0.0001

    resolve_dust_pair(ps, 0, 1)

    test_helpers.expect_close(t, ps^.low_particles.vel_x[0], f32(0),
        "quiet first particle should not rebound")
    test_helpers.expect_close(t, ps^.low_particles.vel_x[1], f32(0),
        "quiet second particle should not rebound")
    testing.expect_value(t, ps^.dust_collision_rest_contact_count, 1)
}

//   Verify the half-neighborhood discovers one contact across a grid boundary.
@(test)
resolve_dust_collisions_finds_cross_cell_contact_once :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 2
    ps^.low_particles[0].alive = true
    ps^.low_particles[1].alive = true
    ps^.low_particles.pos_x[0] = 0.4999
    ps^.low_particles.pos_y[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.5001
    ps^.low_particles.pos_y[1] = 0.5

    resolve_dust_collisions(ps)

    testing.expect_value(t, ps^.dust_pair_count, 1)
    testing.expect_value(t, ps^.dust_collision_correction_count, 1)
}

// Configure one live grounded collision particle at a deterministic position.
dust_collision_test_particle :: proc(ps: ^Particle_System, index: int,
        position: Vector2) {
    ps^.low_particles[index] = {
        pos_x = position.x,
        pos_y = position.y,
        pos_z = DUST_FLOOR_Z,
        life = 1,
        color = rl.WHITE,
        alive = true,
    }
}

// Verify aggregate-interior contacts are rejected before pair-cache insertion.
@(test)
dust_collision_aggregate_interior_produces_no_cached_pair :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 3
    for index in 0..<3 {
        dust_collision_test_particle(ps, index, {0.5, 0.5})
        ps^.dust_aggregate[index] = true
    }

    resolve_dust_collisions(ps)

    testing.expect_value(t, ps^.dust_pair_count, 0)
    testing.expect_value(t, ps^.dust_field_suppressed_pair_count, u64(3))
    testing.expect_value(t, ps^.dust_collision_correction_count, 0)
}

// Verify mixed aggregate-boundary contacts retain ordinary pair response.
@(test)
dust_collision_mixed_pair_retains_impulse :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 2
    dust_collision_test_particle(ps, 0, {0.5, 0.5})
    dust_collision_test_particle(ps, 1, {0.503, 0.5})
    ps^.dust_aggregate[0] = true
    ps^.low_particles.vel_x[0] = 0.01
    ps^.low_particles.vel_x[1] = -0.01

    resolve_dust_collisions(ps)

    testing.expect_value(t, ps^.dust_pair_count, 1)
    testing.expect_value(t, ps^.dust_field_suppressed_pair_count, u64(0))
    testing.expect(t, ps^.low_particles.vel_x[0] < 0)
    testing.expect(t, ps^.low_particles.vel_x[1] > 0)
}

// Verify sparse nonaggregate contacts retain positional correction.
@(test)
dust_collision_sparse_pair_retains_correction :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 2
    dust_collision_test_particle(ps, 0, {0.5, 0.5})
    dust_collision_test_particle(ps, 1, {0.503, 0.5})

    resolve_dust_collisions(ps)

    testing.expect_value(t, ps^.dust_pair_count, 1)
    testing.expect_value(t, ps^.dust_collision_correction_count, 1)
    testing.expect_value(t, ps^.dust_field_suppressed_pair_count, u64(0))
}

// Verify mixed-pair impulse is retained by aggregate field authority.
@(test)
dust_collision_boundary_impulse_enters_field :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 2
    dust_collision_test_particle(ps, 0, {0.5, 0.5})
    dust_collision_test_particle(ps, 1, {0.503, 0.5})
    ps^.dust_aggregate[0] = true
    ps^.low_particles.vel_x[0] = 0.01
    ps^.low_particles.vel_x[1] = -0.01
    resolve_dust_collisions(ps)
    collision_velocity := ps^.low_particles.vel_x[0]

    dust_field_update_aggregate(ps, f32(1.0 / 60.0))

    testing.expect(t, collision_velocity < 0)
    testing.expect(t, ps^.low_particles.vel_x[0] < 0)
    testing.expect(t, ps^.dust_field_peak_speed > 0)
}

// Verify authored vertical kick returns aggregate dust to airborne particle authority.
@(test)
dust_kick_creates_airborne_nonaggregate_particle :: proc(t: ^testing.T) {
    ps := new(Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    dust_collision_test_particle(ps, 0, {0.5, 0.5})
    ps^.dust_aggregate[0] = true

    kick_existing_dust_index(ps, 0)
    integrate_dust_positions(ps)
    update_particle_dust_index(ps, 0)
    dust_field_prepare_membership(ps)

    testing.expect(t, ps^.low_particles.pos_z[0] > DUST_FLOOR_Z)
    testing.expect(t, !ps^.dust_aggregate[0])
}

//   Verify gravity does not create a recurring bounce for grounded dust at rest.
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

    update_particles(ps, 1.0 / 60.0)
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

//   Verify two fresh particle systems produce identical seeded random ranges.
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

// Verify identical emission, settle, contact, and kick streams remain deterministic.
@(test)
scenario_dust_settle_and_wake_stream_is_deterministic :: proc(t: ^testing.T) {
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
    testing.expect_value(t, first^.dust_sleeping_count, 0)
    testing.expect_value(t, second^.dust_sleeping_count, 0)
    queue_dust_slot_contacts(t, first)
    queue_dust_slot_contacts(t, second)
    update_particles(first, 1.0 / 60.0)
    update_particles(second, 1.0 / 60.0)
    kick_existing_dust(first)
    kick_existing_dust(second)
    update_particles(first, 1.0 / 60.0)
    update_particles(second, 1.0 / 60.0)

    expect_dust_systems_match(t, first, second)
    testing.expect_value(t, first^.dust_sleeping, second^.dust_sleeping)
    testing.expect_value(t, first^.dust_activity_frames, second^.dust_activity_frames)
    testing.expect_value(t,
        first^.dust_sleep_transition_count, second^.dust_sleep_transition_count)
    testing.expect_value(t,
        first^.dust_wake_transition_count, second^.dust_wake_transition_count)
    testing.expect_value(t, first^.dust_aggregate_count, second^.dust_aggregate_count)
    testing.expect_value(t, first^.dust_field_suppressed_pair_count,
        second^.dust_field_suppressed_pair_count)
}

//   Verify dense-bucket collision resolution bounds samples and tracks counts.
@(test)
resolve_dust_collisions_bounds_dense_bucket_samples :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)

    ps^.use_max_dust_particles = particlemodel.DUST_COLLISION_CELL_SAMPLE_CAP + 8
    for i in 0..<ps^.use_max_dust_particles {
        ps^.low_particles[i].alive = true
        ps^.low_particles.pos_x[i] = 0.5
        ps^.low_particles.pos_y[i] = 0.5
    }

    resolve_dust_collisions(ps)

    testing.expect_value(t, ps^.dust_collision_frame, u64(1))
    testing.expect_value(t,
        ps^.dust_counts[dust_collision_grid_cell_index(0.5, 0.5)],
        i32(particlemodel.DUST_COLLISION_CELL_SAMPLE_CAP))
    testing.expect_value(t,
        ps^.dust_seen_counts[dust_collision_grid_cell_index(0.5, 0.5)],
        i32(ps^.use_max_dust_particles))
}

//   Verify a quiet over-capacity cell retains stable sampled membership.
@(test)
resolve_dust_collisions_keeps_sleeping_bucket_samples_stable :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = particlemodel.DUST_COLLISION_CELL_SAMPLE_CAP + 8
    for i in 0..<ps^.use_max_dust_particles {
        ps^.low_particles[i].alive = true
        ps^.low_particles.pos_x[i] = 0.5
        ps^.low_particles.pos_y[i] = 0.5
        ps^.dust_sleeping[i] = true
    }
    resolve_dust_collisions(ps)
    cell := dust_collision_grid_cell_index(0.5, 0.5)
    first := int(ps^.dust_collision_offsets[cell])
    expected: [DUST_COLLISION_CELL_SAMPLE_CAP]i32
    for i in 0..<DUST_COLLISION_CELL_SAMPLE_CAP {
        expected[i] = ps^.dust_buckets[first + i]
    }

    resolve_dust_collisions(ps)

    for i in 0..<DUST_COLLISION_CELL_SAMPLE_CAP {
        testing.expect_value(t, ps^.dust_buckets[first + i], expected[i])
    }
}

//   Verify awake members displace sleeping work in a bounded dense cell.
@(test)
populate_dust_collision_grid_prioritizes_awake_members :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = particlemodel.DUST_COLLISION_CELL_SAMPLE_CAP + 1
    for i in 0..<ps^.use_max_dust_particles {
        ps^.low_particles[i].alive = true
        ps^.low_particles.pos_x[i] = 0.5
        ps^.low_particles.pos_y[i] = 0.5
        ps^.dust_sleeping[i] = i < ps^.use_max_dust_particles - 1
    }
    prepare_dust_collision_grid(ps)

    populate_dust_collision_grid(ps)

    cell := dust_collision_grid_cell_index(0.5, 0.5)
    first := int(ps^.dust_collision_offsets[cell])
    testing.expect_value(t, ps^.dust_buckets[first],
        i32(ps^.use_max_dust_particles - 1))
}

//   Verify overloaded fine-cell refinement retains spatially sparse children.
@(test)
refine_dust_collision_bucket_balances_spatial_children :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = DUST_COLLISION_CELL_SAMPLE_CAP + 8
    for i in 0..<ps^.use_max_dust_particles {
        ps^.low_particles[i].alive = true
        ps^.low_particles.pos_x[i] = 0.5005
        ps^.low_particles.pos_y[i] = 0.5005
        if i >= DUST_COLLISION_CELL_SAMPLE_CAP {
            ps^.low_particles.pos_x[i] = 0.5025
            ps^.low_particles.pos_y[i] = 0.5025
        }
    }
    build_exact_dust_grid(ps)
    cell := dust_collision_grid_cell_index(0.501, 0.501)
    prepare_dust_collision_grid(ps)
    populate_dust_collision_grid(ps)
    refine_dust_collision_bucket(ps, cell)

    first := int(ps^.dust_collision_offsets[cell])
    sparse_child_count: int
    for index in 0..<int(ps^.dust_counts[cell]) {
        particle_index := int(ps^.dust_buckets[first + index])
        if dust_collision_refined_child(ps, particle_index) == 3 {
            sparse_child_count += 1
        }
    }
    testing.expect_value(t, sparse_child_count, 8)
    testing.expect_value(t, ps^.dust_collision_refined_cell_count, 1)
}

// Seed live dust across every fine cell with deterministic wrapped layers.
seed_distributed_collision_capacity :: proc(
    ps: ^particlemodel.Particle_System, count: int) {
    ps^.use_max_dust_particles = count
    for particle_index in 0..<ps^.use_max_dust_particles {
        cell := particle_index % DUST_COLLISION_GRID_CELL_COUNT
        layer := particle_index / DUST_COLLISION_GRID_CELL_COUNT
        cell_x := cell % DUST_COLLISION_GRID_DIM
        cell_y := cell / DUST_COLLISION_GRID_DIM
        offset := f32(0.25 + 0.5 * f32(layer))
        ps^.low_particles[particle_index].alive = true
        ps^.low_particles.pos_x[particle_index] =
            (f32(cell_x) + offset) * DUST_COLLISION_GRID_CELL_SIZE
        ps^.low_particles.pos_y[particle_index] =
            (f32(cell_y) + offset) * DUST_COLLISION_GRID_CELL_SIZE
    }
}

// Verify one distributed capacity case retains bounded collision work.
expect_distributed_collision_capacity :: proc(t: ^testing.T, count: int) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    seed_distributed_collision_capacity(ps, count)

    resolve_dust_collisions(ps)

    testing.expect(t, ps^.dust_collision_candidate_count <
        u64(ps^.use_max_dust_particles * 12))
    testing.expect(t, ps^.dust_pair_count <= DUST_COLLISION_PAIR_CAP)
    testing.expect_value(t, ps^.dust_pair_dropped_count, 0)
    testing.expect(t, ps^.dust_field_suppressed_pair_count <=
        ps^.dust_collision_candidate_count)
}

// Verify the fine collision grid keeps 14,000-particle candidate work bounded.
@(test)
resolve_dust_collisions_bounds_distributed_14000_candidate_work :: proc(
    t: ^testing.T) {
    expect_distributed_collision_capacity(t, 14_000)
}

// Verify the fine collision grid keeps 40,000-particle candidate work bounded.
@(test)
resolve_dust_collisions_bounds_distributed_40000_candidate_work :: proc(
    t: ^testing.T) {
    expect_distributed_collision_capacity(t, 40_000)
}

// Verify maximum-capacity collision work remains bounded without pair overflow.
@(test)
resolve_dust_collisions_bounds_maximum_capacity_work :: proc(t: ^testing.T) {
    expect_distributed_collision_capacity(t, particlemodel.MAX_LOW_PARTICLES)
}

//   Verify dense residual damping preserves momentum while reducing variance.
@(test)
relax_dense_grounded_dust_preserves_momentum_and_reduces_variance :: proc(
    t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 4
    for i in 0..<ps^.use_max_dust_particles {
        ps^.low_particles[i].alive = true
        ps^.low_particles.pos_x[i] = 0.505
        ps^.low_particles.pos_y[i] = 0.505
        ps^.low_particles.vel_x[i] = f32(i) - 1.5
    }
    before_momentum := f32(0)
    before_energy := f32(0)
    for i in 0..<ps^.use_max_dust_particles {
        before_momentum += ps^.low_particles.vel_x[i]
        before_energy += ps^.low_particles.vel_x[i] * ps^.low_particles.vel_x[i]
    }

    relax_dense_grounded_dust(ps)

    after_momentum := f32(0)
    after_energy := f32(0)
    for i in 0..<ps^.use_max_dust_particles {
        after_momentum += ps^.low_particles.vel_x[i]
        after_energy += ps^.low_particles.vel_x[i] * ps^.low_particles.vel_x[i]
    }
    test_helpers.expect_close(t, after_momentum, before_momentum,
        "relaxation should preserve leaf momentum")
    testing.expect(t, after_energy < before_energy)
    testing.expect(t, ps^.dust_relaxation_energy_removed > 0)
}

//   Verify adaptive leaves preserve separate coherent streams within one parent.
@(test)
relax_dense_grounded_dust_keeps_refined_streams_separate :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = DUST_RELAXATION_SPLIT_2_ENTER
    for i in 0..<ps^.use_max_dust_particles {
        left := i < ps^.use_max_dust_particles / 2
        ps^.low_particles[i].alive = true
        ps^.low_particles.pos_x[i] = 0.404 if left else 0.416
        ps^.low_particles.pos_y[i] = 0.405
        ps^.low_particles.vel_x[i] = 0.01 if left else -0.01
    }

    relax_dense_grounded_dust(ps)

    parent := dust_grid_cell_index(0.405, 0.405)
    testing.expect_value(t, ps^.dust_relaxation_parent_levels[parent], u8(1))
    for i in 0..<ps^.use_max_dust_particles {
        expected := f32(0.01) if i < ps^.use_max_dust_particles / 2 else -0.01
        test_helpers.expect_close(t, ps^.low_particles.vel_x[i], expected,
            "refined coherent stream should remain unchanged")
    }
}

//   Verify recently disturbed particles bypass dense residual damping.
@(test)
relax_dense_grounded_dust_respects_activity_grace :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 4
    for i in 0..<ps^.use_max_dust_particles {
        ps^.low_particles[i].alive = true
        ps^.low_particles.pos_x[i] = 0.5
        ps^.low_particles.pos_y[i] = 0.5
        ps^.low_particles.vel_x[i] = f32(i)
        ps^.dust_activity_frames[i] = 1
    }

    relax_dense_grounded_dust(ps)

    for i in 0..<ps^.use_max_dust_particles {
        testing.expect_value(t, ps^.low_particles.vel_x[i], f32(i))
    }
    testing.expect_value(t, ps^.dust_relaxation_dense_leaf_count, 0)
}

// Verify legacy sleep state cannot gate field-authority position integration.
@(test)
vector_dust_ignores_legacy_sleep_during_integration :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0].alive = true
    ps^.low_particles.pos_x[0] = 0.5
    ps^.low_particles.vel_x[0] = 1
    ps^.dust_sleeping[0] = true
    ps^.dust_sleeping_count = 1

    integrate_dust_positions(ps)

    testing.expect_value(t, ps^.low_particles.pos_x[0], f32(1.5))
}

// Verify a quiet sparse particle sleeps while crossing relaxation-cell boundaries.
@(test)
relax_dense_grounded_dust_sleeps_sparse_leaf :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0].alive = true
    ps^.low_particles.pos_x[0] = 0.5
    ps^.low_particles.pos_y[0] = 0.5

    for frame in 0..<int(DUST_SLEEP_QUIET_FRAMES) {
        ps^.low_particles.pos_x[0] = 0.499 if frame % 2 == 0 else 0.501
        relax_dense_grounded_dust(ps)
    }

    testing.expect(t, ps^.dust_sleeping[0])
    testing.expect_value(t, ps^.dust_sleep_transition_count, u64(1))
}

// Verify contact work resets an otherwise quiet leaf's sleep accumulation.
@(test)
relax_dense_grounded_dust_rejects_active_contact_work :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 4
    for i in 0..<ps^.use_max_dust_particles {
        ps^.low_particles[i].alive = true
        ps^.low_particles.pos_x[i] = 0.51 + f32(i) * 0.0001
        ps^.low_particles.pos_y[i] = 0.51
    }
    relax_dense_grounded_dust(ps)
    leaf := int(ps^.dust_relaxation_leaf_indices[0])
    testing.expect_value(t, ps^.dust_relaxation_leaf_quiet_frames[leaf], u16(1))
    ps^.dust_contact_impulse[0] = DUST_SLEEP_MAX_COLLISION_IMPULSE * 2
    ps^.dust_contact_correction[1] = DUST_SLEEP_MAX_POSITION_CORRECTION * 2

    relax_dense_grounded_dust(ps)

    testing.expect_value(t, ps^.dust_relaxation_leaf_quiet_frames[leaf], u16(0))
}

//   Verify a clear kick wakes sleeping dust before applying authored velocity.
@(test)
kick_existing_dust_index_wakes_sleeping_particle :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0].alive = true
    ps^.low_particles[0].life = 1
    ps^.dust_sleeping[0] = true
    ps^.dust_sleeping_count = 1

    kick_existing_dust_index(ps, 0)

    testing.expect(t, !ps^.dust_sleeping[0])
    testing.expect_value(t, ps^.dust_sleeping_count, 0)
    testing.expect_value(t, ps^.dust_wake_transition_count, u64(1))
    testing.expect(t, ps^.low_particles.vel_z[0] > 0)
}

//   Verify active contact wakes a sleeping particle before pair response.
@(test)
resolve_dust_pair_active_contact_wakes_sleeping_particle :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.low_particles.pos_x[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.503
    ps^.low_particles.vel_x[0] = 0.01
    ps^.dust_sleeping[1] = true
    ps^.dust_sleeping_count = 1

    resolve_dust_pair(ps, 0, 1)

    testing.expect(t, !ps^.dust_sleeping[1])
    testing.expect_value(t, ps^.dust_wake_transition_count, u64(1))
}

// Verify negligible mixed contact does not restart a settled particle.
@(test)
resolve_dust_pair_quiet_contact_keeps_sleeping_particle :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.low_particles.pos_x[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.00385 + ps^.low_particles.pos_x[0]
    ps^.low_particles.vel_x[0] = DUST_WAKE_NEIGHBOR_SPEED * 0.5
    ps^.dust_sleeping[1] = true
    ps^.dust_sleeping_count = 1

    resolve_dust_pair(ps, 0, 1)

    testing.expect(t, ps^.dust_sleeping[1])
    testing.expect_value(t, ps^.dust_wake_transition_count, u64(0))
    testing.expect_value(t, ps^.dust_sleeping_pair_skip_count, u64(1))
}

// Verify substantial overlap wakes and separates a sleeper despite low impact speed.
@(test)
resolve_dust_pair_penetration_wakes_sleeping_particle :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.low_particles.pos_x[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.503
    ps^.low_particles.vel_x[0] = DUST_WAKE_NEIGHBOR_SPEED * 0.5
    ps^.dust_sleeping[1] = true
    ps^.dust_sleeping_count = 1

    resolve_dust_pair(ps, 0, 1)

    testing.expect(t, !ps^.dust_sleeping[1])
    testing.expect_value(t, ps^.dust_wake_transition_count, u64(1))
    separation := ps^.low_particles.pos_x[1] - ps^.low_particles.pos_x[0]
    testing.expect(t, separation > f32(0.003))
}

//   Verify energetic contact wakes sleeping dust in the neighboring parent halo.
@(test)
resolve_dust_pair_energetic_contact_wakes_sleeping_halo :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 3
    ps^.low_particles[0].alive = true
    ps^.low_particles[1].alive = true
    ps^.low_particles[2].alive = true
    ps^.low_particles.pos_x[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.503
    ps^.low_particles.pos_x[2] = 0.521
    ps^.low_particles.pos_y[0] = 0.5
    ps^.low_particles.pos_y[1] = 0.5
    ps^.low_particles.pos_y[2] = 0.5
    ps^.low_particles.vel_x[0] = 0.01
    ps^.dust_sleeping[1] = true
    ps^.dust_sleeping[2] = true
    ps^.dust_sleeping_count = 2
    build_exact_dust_grid(ps)

    resolve_dust_pair(ps, 0, 1)

    testing.expect(t, !ps^.dust_sleeping[1])
    testing.expect(t, !ps^.dust_sleeping[2])
    testing.expect_value(t, ps^.dust_wake_transition_count, u64(2))
}

//   Verify two sleeping particles skip internal collision response.
@(test)
resolve_dust_pair_sleeping_pair_skips_response :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.low_particles.pos_x[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.5001
    ps^.dust_sleeping[0] = true
    ps^.dust_sleeping[1] = true
    before_x := ps^.low_particles.pos_x[0]

    resolve_dust_pair(ps, 0, 1)

    testing.expect_value(t, ps^.low_particles.pos_x[0], before_x)
    testing.expect_value(t, ps^.dust_sleeping_pair_skip_count, u64(1))
}

//   Verify airborne dust cannot enter the grounded relaxation sleep path.
@(test)
relax_dense_grounded_dust_never_sleeps_airborne_particles :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 4
    for i in 0..<ps^.use_max_dust_particles {
        ps^.low_particles[i].alive = true
        ps^.low_particles.pos_x[i] = 0.5
        ps^.low_particles.pos_y[i] = 0.5
        ps^.low_particles.pos_z[i] = 0.1
    }
    for _ in 0..<int(DUST_SLEEP_QUIET_FRAMES) {
        relax_dense_grounded_dust(ps)
    }

    testing.expect_value(t, ps^.dust_sleeping_count, 0)
}

// Verify the complete fixed-step path damps a dense grounded cluster without sleeping.
@(test)
update_particles_settles_dense_grounded_cluster :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 8
    for i in 0..<ps^.use_max_dust_particles {
        ps^.low_particles[i].alive = true
        ps^.low_particles[i].life = 1
        ps^.low_particles.pos_x[i] = 0.51 + f32(i % 4) * 0.0002
        ps^.low_particles.pos_y[i] = 0.51 + f32(i / 4) * 0.0002
    }
    for _ in 0..<180 {
        update_particles(ps, 1.0 / 60.0)
    }

    testing.expect_value(t, ps^.dust_sleeping_count, 0)
    speed_before := math.abs(ps^.low_particles.vel_x[0]) +
        math.abs(ps^.low_particles.vel_y[0])
    before_x := ps^.low_particles.pos_x[0]
    before_y := ps^.low_particles.pos_y[0]
    for _ in 0..<30 {
        update_particles(ps, 1.0 / 60.0)
    }
    displacement := math.abs(ps^.low_particles.pos_x[0] - before_x) +
        math.abs(ps^.low_particles.pos_y[0] - before_y)
    speed_after := math.abs(ps^.low_particles.vel_x[0]) +
        math.abs(ps^.low_particles.vel_y[0])
    testing.expect(t, displacement < 0.0001)
    testing.expect(t, speed_after <= speed_before)
}

// Verify grounded particles receive field velocity while airborne particles do not.
@(test)
vector_dust_update_affects_only_grounded_particles :: proc(t: ^testing.T) {
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

    vector_dust_field_update_grounded(ps, f32(1.0 / 60.0))

    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
    testing.expect(t, ps^.low_particles.vel_x[0] < 0.003)
    testing.expect_value(t, ps^.low_particles.vel_x[1], airborne_velocity.x)
    testing.expect_value(t, ps^.low_particles.vel_y[1], airborne_velocity.y)
    test_helpers.expect_close(t,
        vector_dust_test_plane_sum(&ps^.vector_dust_field.density), 1,
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
        vector_dust_test_plane_sum(&ps^.vector_dust_field.density), 1,
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

    testing.expect_value(t, ps^.dust_collision_candidate_count, u64(0))
    testing.expect_value(t, ps^.dust_pair_count, 0)
    testing.expect_value(t, ps^.dust_aggregate_count, 0)
    testing.expect_value(t, ps^.dust_relaxation_active_leaf_count, 0)
    testing.expect_value(t, ps^.dust_sleeping_count, 0)
}

// Verify P2G caches grounded particles once in stable slot order.
@(test)
vector_dust_transfers_are_stable_and_grounded_only :: proc(t: ^testing.T) {
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

    vector_dust_field_deposit_grounded(ps)

    testing.expect_value(t, ps^.vector_dust_transfer_count, 2)
    testing.expect_value(t, ps^.vector_dust_transfers[0].particle_index, i32(0))
    testing.expect_value(t, ps^.vector_dust_transfers[1].particle_index, i32(3))
    test_helpers.expect_close(t,
        vector_dust_test_plane_sum(&ps^.vector_dust_field.density), 2,
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
    testing.expect_value(t, actual^.vector_dust_field.support_bounds,
        expected^.vector_dust_field.support_bounds)
    testing.expect_value(t, actual^.vector_dust_transfer_count,
        expected^.vector_dust_transfer_count)
    for index in 0..<expected^.vector_dust_transfer_count {
        testing.expect_value(t, actual^.vector_dust_transfers[index],
            expected^.vector_dust_transfers[index])
    }
    for node in 0..<DUST_FIELD_NODE_COUNT {
        testing.expect_value(t, actual^.vector_dust_field.density[node],
            expected^.vector_dust_field.density[node])
        testing.expect_value(t, actual^.vector_dust_field.momentum_x[node],
            expected^.vector_dust_field.momentum_x[node])
        testing.expect_value(t, actual^.vector_dust_field.momentum_y[node],
            expected^.vector_dust_field.momentum_y[node])
    }
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
    vector_dust_field_deposit_grounded(expected)
    update_and_deposit_low_dust(actual)
    expect_low_dust_deposit_state_equal(t, actual, expected)
}

//   Verify reset_particles zeroes runtime state and marks every slot dead.
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
    ps^.dust_collision_active_cell_count = 2
    ps^.dust_collision_candidate_count = 17
    ps^.vector_dust_transfer_count = 2
    ps^.dust_field_suppressed_pair_count = 11
    ps^.dust_relaxation_parent_levels[0] = 2
    ps^.dust_relaxation_leaf_quiet_frames[0] = DUST_SLEEP_QUIET_FRAMES
    ps^.dust_relaxation_leaf_last_seen[0] = 4

    reset_particles(ps)

    testing.expect_value(t, ps^.next_index, 0)
    testing.expect_value(t, ps^.spawn_timer, 0.0)
    testing.expect_value(t, ps^.dust_collision_active_cell_count, 0)
    testing.expect_value(t, ps^.dust_collision_candidate_count, u64(0))
    testing.expect_value(t, ps^.vector_dust_transfer_count, 0)
    testing.expect_value(t, ps^.dust_field_suppressed_pair_count, u64(0))
    testing.expect_value(t, ps^.dust_relaxation_parent_levels[0], u8(0))
    testing.expect_value(t, ps^.dust_relaxation_leaf_quiet_frames[0], u16(0))
    testing.expect_value(t, ps^.dust_relaxation_leaf_last_seen[0], u64(0))
    testing.expect(t, !ps^.low_particles.alive[0])
    testing.expect_value(t, ps^.low_particles.age[0], 0.0)
    testing.expect(t, !ps^.particles.alive[0])
    testing.expect_value(t, ps^.particles.age[0], 0.0)
    testing.expect(t, !ps^.high_particles.alive[0])
    testing.expect_value(t, ps^.high_particles.age[0], 0.0)
}

//   Verify reset_particles clears queued contact state and diagnostics.
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

//   Verify slot reservation wraps to index zero when every slot is alive.
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

//   Seed one world line with direct endpoint transforms and configurable visibility.
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

//   Verify world clear particles resolve direct line entities without child topology.
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

//   Verify hidden world geometry does not participate in clear particle emission.
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

//   Verify out-of-bounds particles clamp to the bounds and bounce their velocity.
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
