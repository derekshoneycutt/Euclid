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

// Verify deferred replay preserves endpoint and sampled sweep responses.
@(test)
replay_dust_tool_contact_matches_immediate_reference :: proc(t: ^testing.T) {
    expected := new(particlemodel.Particle_System, context.allocator)
    actual := new(particlemodel.Particle_System, context.allocator)
    defer free(expected)
    defer free(actual)
    expected^.use_max_dust_particles = 4
    actual^.use_max_dust_particles = 4
    expected^.low_particles[0] = {pos_x = 0.2, pos_y = 0.25, alive = true}
    expected^.low_particles[1] = {pos_x = 0.25, pos_y = 0.256, alive = true}
    expected^.low_particles[2] = {pos_x = 0.2, pos_y = 0.25, alive = true}
    expected^.low_particles[3] = {pos_x = 0.8, pos_y = 0.8, alive = true}
    actual^.low_particles[0] = expected^.low_particles[0]
    actual^.low_particles[1] = expected^.low_particles[1]
    actual^.low_particles[2] = expected^.low_particles[2]
    actual^.low_particles[3] = expected^.low_particles[3]

    endpoint := Vector3{0.2, 0.25, 0}
    first := Vector3{0.2, 0.25, 0}
    second := Vector3{0.3, 0.25, 0}
    sample_count := 24
    push_dust_away_from_xy(expected, endpoint.x, endpoint.y)
    for sample_index in 0..<sample_count {
        interpolation := f32(sample_index) / f32(sample_count)
        push_dust_away_from_xy(expected,
            math.lerp(first.x, second.x, interpolation),
            math.lerp(first.y, second.y, interpolation))
    }
    testing.expect(t, queue_dust_tool_contact(
        actual, endpoint, first, second, sample_count, true))
    build_exact_dust_grid(actual)
    replay_dust_tool_contacts(actual)

    for index in 0..<expected^.use_max_dust_particles {
        expected_slot := dust_slot_snapshot(expected, index)
        actual_slot := dust_slot_snapshot(actual, index)
        test_helpers.expect_close(t, actual_slot.x, expected_slot.x, "segment x")
        test_helpers.expect_close(t, actual_slot.y, expected_slot.y, "segment y")
        test_helpers.expect_close(t, actual_slot.vx, expected_slot.vx, "segment vx")
        test_helpers.expect_close(t, actual_slot.vy, expected_slot.vy, "segment vy")
    }
    testing.expect_value(t, actual^.rng_state, expected^.rng_state)
    testing.expect_value(t, actual^.dust_tool_contact_count, 0)
}

// Verify deferred contacts retain the original pre-integration fixed-step timing.
@(test)
dust_tool_contact_replays_before_fixed_step_integration :: proc(t: ^testing.T) {
    expected := new(particlemodel.Particle_System, context.allocator)
    actual := new(particlemodel.Particle_System, context.allocator)
    defer free(expected)
    defer free(actual)
    expected^.use_max_dust_particles = 1
    actual^.use_max_dust_particles = 1
    expected^.low_particles[0] = {
        pos_x = 0.2, pos_y = 0.25, life = 100, size = 0.01, alive = true}
    actual^.low_particles[0] = expected^.low_particles[0]
    endpoint := Vector3{0.2, 0.25, 0}

    push_dust_away_from_xy(expected, endpoint.x, endpoint.y)
    update_particles(expected, f32(1.0 / 60.0))
    testing.expect(t, queue_dust_tool_contact(
        actual, endpoint, {}, {}, 0, false))
    update_particles(actual, f32(1.0 / 60.0))

    testing.expect_value(t, actual^.low_particles[0], expected^.low_particles[0])
    testing.expect_value(t, actual^.rng_state, expected^.rng_state)
}

// Verify one deferred contact excludes dust emitted by a later scene command.
@(test)
dust_tool_contact_excludes_later_spawned_slots :: proc(t: ^testing.T) {
    expected := new(particlemodel.Particle_System, context.allocator)
    actual := new(particlemodel.Particle_System, context.allocator)
    defer free(expected)
    defer free(actual)
    expected^.use_max_dust_particles = 1
    actual^.use_max_dust_particles = 1
    endpoint := Vector3{0.2, 0.25, 0}
    testing.expect(t, queue_dust_tool_contact(
        actual, endpoint, {}, {}, 0, false))

    spawn_dust_particle(expected, endpoint, rl.WHITE)
    spawn_dust_particle(actual, endpoint, rl.WHITE)
    build_exact_dust_grid(actual)
    replay_dust_tool_contacts(actual)

    testing.expect_value(t, actual^.low_particles[0], expected^.low_particles[0])
    testing.expect_value(t, actual^.rng_state, expected^.rng_state)
}

// Verify an ordered flush preserves RNG state before a later particle emission.
@(test)
dust_tool_contact_flush_precedes_later_emission_rng :: proc(t: ^testing.T) {
    expected := new(particlemodel.Particle_System, context.allocator)
    actual := new(particlemodel.Particle_System, context.allocator)
    defer free(expected)
    defer free(actual)
    expected^.use_max_dust_particles = 2
    actual^.use_max_dust_particles = 2
    expected^.low_particles[0] = {
        pos_x = 0.2, pos_y = 0.25, life = 100, alive = true}
    actual^.low_particles[0] = expected^.low_particles[0]
    endpoint := Vector3{0.2, 0.25, 0}

    push_dust_away_from_xy(expected, endpoint.x, endpoint.y)
    spawn_dust_particle(expected, endpoint, rl.WHITE)
    testing.expect(t, queue_dust_tool_contact(
        actual, endpoint, {}, {}, 0, false))
    flush_dust_tool_contacts(actual)
    spawn_dust_particle(actual, endpoint, rl.WHITE)

    testing.expect_value(t, actual^.low_particles[0], expected^.low_particles[0])
    testing.expect_value(t, actual^.low_particles[1], expected^.low_particles[1])
    testing.expect_value(t, actual^.rng_state, expected^.rng_state)
}

// Verify queue admission is bounded and records rejected contact intents.
@(test)
dust_tool_contact_queue_is_bounded :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    for _ in 0..<DUST_TOOL_CONTACT_CAP {
        testing.expect(t, queue_dust_tool_contact(ps, {}, {}, {}, 0, false))
    }

    testing.expect(t, !can_queue_dust_tool_contacts(ps, 1))
    testing.expect(t, !queue_dust_tool_contact(ps, {}, {}, {}, 0, false))
    testing.expect_value(t, ps^.dust_tool_contact_count, DUST_TOOL_CONTACT_CAP)
    testing.expect_value(t, ps^.dust_tool_contact_overflow_count, 1)
}

// Verify rebuilding exact membership observes a contact crossing a cell boundary.
@(test)
exact_dust_grid_rebuild_tracks_contact_displacement :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 1
    ps^.low_particles[0] = {pos_x = 0.0197, pos_y = 0.25, alive = true}
    endpoint := Vector3{0.011, 0.25, 0}

    build_exact_dust_grid(ps)
    old_cell := dust_grid_cell_index(0.0197, 0.25)
    testing.expect(t, queue_dust_tool_contact(
        ps, endpoint, {}, {}, 0, false))
    replay_dust_tool_contacts(ps)
    build_exact_dust_grid(ps)

    new_cell := dust_grid_cell_index(
        ps^.low_particles.pos_x[0], ps^.low_particles.pos_y[0])
    testing.expect(t, new_cell != old_cell)
    testing.expect_value(t, ps^.dust_exact_counts[old_cell], i32(0))
    testing.expect_value(t, ps^.dust_exact_counts[new_cell], i32(1))
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

    min_sep: f32 = DUST_COLLISION_RADIUS * f32(2.0)
    radius_sq: f32 = DUST_COLLISION_RADIUS *
        DUST_COLLISION_RADIUS
    resolve_dust_pair(ps, 0, 1, min_sep, radius_sq)

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

    min_sep: f32 = DUST_COLLISION_RADIUS * f32(2.0)
    radius_sq: f32 = DUST_COLLISION_RADIUS *
        DUST_COLLISION_RADIUS
    resolve_dust_pair(ps, 0, 1, min_sep, radius_sq)

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

    min_sep: f32 = DUST_COLLISION_RADIUS * f32(2.0)
    radius_sq: f32 = DUST_COLLISION_RADIUS *
        DUST_COLLISION_RADIUS
    resolve_dust_pair(ps, 0, 1, min_sep, radius_sq)

    testing.expect(t, ps^.low_particles.pos_x[0] < before_x0)
    testing.expect(t, ps^.low_particles.pos_x[1] > before_x1)
    test_helpers.expect_close(t, ps^.low_particles.vel_x[0], f32(-0.01),
        "separating vx0 should be unchanged")
    test_helpers.expect_close(t, ps^.low_particles.vel_x[1], f32(0.01),
        "separating vx1 should be unchanged")
}

//   Verify exactly coincident particles separate along a deterministic direction.
@(test)
resolve_dust_pair_exact_overlap_uses_deterministic_separation :: proc(t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)

    ps^.low_particles.pos_x[0] = 0.5
    ps^.low_particles.pos_y[0] = 0.5
    ps^.low_particles.pos_x[1] = 0.5
    ps^.low_particles.pos_y[1] = 0.5

    min_sep: f32 = DUST_COLLISION_RADIUS * f32(2.0)
    radius_sq: f32 = DUST_COLLISION_RADIUS *
        DUST_COLLISION_RADIUS
    resolve_dust_pair(ps, 0, 1, min_sep, radius_sq)

    dx := ps^.low_particles.pos_x[1] - ps^.low_particles.pos_x[0]
    dy := ps^.low_particles.pos_y[1] - ps^.low_particles.pos_y[0]
    testing.expect(t, dx * dx + dy * dy > 0)
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

//   Verify dense-bucket collision resolution rotates samples and tracks counts.
@(test)
resolve_dust_collisions_rotates_dense_bucket_samples :: proc(t: ^testing.T) {
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

// Verify the fine collision grid keeps distributed high-count candidate work linear.
@(test)
resolve_dust_collisions_bounds_distributed_14000_candidate_work :: proc(
    t: ^testing.T) {
    ps := new(particlemodel.Particle_System, context.allocator)
    defer free(ps)
    ps^.use_max_dust_particles = 14_000
    columns := 200
    for particle_index in 0..<ps^.use_max_dust_particles {
        cell_x := particle_index % columns
        cell_y := particle_index / columns
        ps^.low_particles[particle_index].alive = true
        ps^.low_particles.pos_x[particle_index] =
            (f32(cell_x) + 0.25) * DUST_COLLISION_GRID_CELL_SIZE
        ps^.low_particles.pos_y[particle_index] =
            (f32(cell_y) + 0.25) * DUST_COLLISION_GRID_CELL_SIZE
    }

    resolve_dust_collisions(ps)

    testing.expect(t, ps^.dust_collision_candidate_count <
        u64(ps^.use_max_dust_particles * 5))
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

    reset_particles(ps)

    testing.expect_value(t, ps^.next_index, 0)
    testing.expect_value(t, ps^.spawn_timer, 0.0)
    testing.expect_value(t, ps^.dust_collision_active_cell_count, 0)
    testing.expect_value(t, ps^.dust_collision_candidate_count, u64(0))
    testing.expect(t, !ps^.low_particles.alive[0])
    testing.expect_value(t, ps^.low_particles.age[0], 0.0)
    testing.expect(t, !ps^.particles.alive[0])
    testing.expect_value(t, ps^.particles.age[0], 0.0)
    testing.expect(t, !ps^.high_particles.alive[0])
    testing.expect_value(t, ps^.high_particles.age[0], 0.0)
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
