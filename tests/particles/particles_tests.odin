package particles_tests

import "core:math"
import "core:testing"

import app_core "../../src/core"
import app_particles "../../src/particles"
import app_view_core "../../src/view/core"
import test_helpers "../helpers"

EPS :: f32(1e-5)

expect_close :: proc(t: ^testing.T, actual, expected: f32, msg: string) {
    testing.expectf(t, math.abs(actual - expected) <= EPS,
        "%s | expected=%v got=%v", msg, expected, actual)
}

@(test)
normalize_theta_and_sweep_delta_are_stable :: proc(t: ^testing.T) {
    theta := app_particles.normalize_theta(f32(-0.5))
    test_helpers.expect_close(t, theta, f32(2.0 * math.PI - 0.5), "normalize_theta should wrap negatives")

    delta := app_particles.compute_sweep_delta(
        f32(1.5 * math.PI),
        f32(0.5 * math.PI))
    test_helpers.expect_close(t, delta, f32(math.PI), "sweep delta should wrap across zero")
}

@(test)
dust_grid_cell_index_clamps_bounds :: proc(t: ^testing.T) {
    testing.expect_value(t, app_particles.dust_grid_cell_index(-1, -1), 0)

    max_idx := app_particles.DUST_GRID_DIM * app_particles.DUST_GRID_DIM - 1
    testing.expect_value(t, app_particles.dust_grid_cell_index(99, 99), max_idx)
}

@(test)
reserve_dead_low_particle_slot_prefers_dead_then_wraps :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)
    ps^.use_max_dust_particles = 3
    ps^.next_index = 0

    idx0, ok0 := app_particles.reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok0)
    testing.expect_value(t, idx0, 0)
    testing.expect_value(t, ps^.next_index, 1)

    ps^.low_particles.alive[1] = true
    idx1, ok1 := app_particles.reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok1)
    testing.expect_value(t, idx1, 2)
    testing.expect_value(t, ps^.next_index, 0)

    ps^.low_particles.alive[0] = true
    ps^.low_particles.alive[1] = true
    ps^.low_particles.alive[2] = true
    idx2, ok2 := app_particles.reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok2)
    testing.expect_value(t, idx2, 0)
}

@(test)
reserve_dead_particle_slot_ring_advances :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)
    ps^.next_index = app_particles.MAX_PARTICLES - 1

    idx, ok := app_particles.reserve_dead_particle_slot(ps)
    testing.expect(t, ok)
    testing.expect_value(t, idx, app_particles.MAX_PARTICLES - 1)
    testing.expect_value(t, ps^.next_index, 0)
}

@(test)
resolve_dust_pair_no_collision_keeps_state :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)

    ps^.low_particles.pos_x[0] = 0.2
    ps^.low_particles.pos_y[0] = 0.2
    ps^.low_particles.pos_x[1] = 0.9
    ps^.low_particles.pos_y[1] = 0.9

    ps^.low_particles.vel_x[0] = 0.01
    ps^.low_particles.vel_y[0] = -0.02
    ps^.low_particles.vel_x[1] = -0.03
    ps^.low_particles.vel_y[1] = 0.04

    before_ax := ps^.low_particles.pos_x[0]
    before_ay := ps^.low_particles.pos_y[0]
    before_bx := ps^.low_particles.pos_x[1]
    before_by := ps^.low_particles.pos_y[1]
    before_avx := ps^.low_particles.vel_x[0]
    before_avy := ps^.low_particles.vel_y[0]
    before_bvx := ps^.low_particles.vel_x[1]
    before_bvy := ps^.low_particles.vel_y[1]

    min_sep: f32 = app_particles.DUST_COLLISION_RADIUS * f32(2.0)
    radius_sq: f32 = app_particles.DUST_COLLISION_RADIUS * app_particles.DUST_COLLISION_RADIUS
    app_particles.resolve_dust_pair(ps, 0, 1, min_sep, radius_sq)

    test_helpers.expect_close(t, ps^.low_particles.pos_x[0], before_ax, "no collision should keep ax")
    test_helpers.expect_close(t, ps^.low_particles.pos_y[0], before_ay, "no collision should keep ay")
    test_helpers.expect_close(t, ps^.low_particles.pos_x[1], before_bx, "no collision should keep bx")
    test_helpers.expect_close(t, ps^.low_particles.pos_y[1], before_by, "no collision should keep by")
    test_helpers.expect_close(t, ps^.low_particles.vel_x[0], before_avx, "no collision should keep avx")
    test_helpers.expect_close(t, ps^.low_particles.vel_y[0], before_avy, "no collision should keep avy")
    test_helpers.expect_close(t, ps^.low_particles.vel_x[1], before_bvx, "no collision should keep bvx")
    test_helpers.expect_close(t, ps^.low_particles.vel_y[1], before_bvy, "no collision should keep bvy")
}

@(test)
resolve_dust_pair_overlap_with_approach_applies_impulse :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
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

    min_sep: f32 = app_particles.DUST_COLLISION_RADIUS * f32(2.0)
    radius_sq: f32 = app_particles.DUST_COLLISION_RADIUS * app_particles.DUST_COLLISION_RADIUS
    app_particles.resolve_dust_pair(ps, 0, 1, min_sep, radius_sq)

    testing.expect(t, ps^.low_particles.pos_x[0] < before_x0)
    testing.expect(t, ps^.low_particles.pos_x[1] > before_x1)
    testing.expect(t, ps^.low_particles.vel_x[0] < 0)
    testing.expect(t, ps^.low_particles.vel_x[1] > 0)
}

@(test)
resolve_dust_pair_overlap_with_separating_velocity_skips_impulse :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
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

    min_sep: f32 = app_particles.DUST_COLLISION_RADIUS * f32(2.0)
    radius_sq: f32 = app_particles.DUST_COLLISION_RADIUS * app_particles.DUST_COLLISION_RADIUS
    app_particles.resolve_dust_pair(ps, 0, 1, min_sep, radius_sq)

    testing.expect(t, ps^.low_particles.pos_x[0] < before_x0)
    testing.expect(t, ps^.low_particles.pos_x[1] > before_x1)
    test_helpers.expect_close(t, ps^.low_particles.vel_x[0], f32(-0.01), "separating vx0 should be unchanged")
    test_helpers.expect_close(t, ps^.low_particles.vel_x[1], f32(0.01), "separating vx1 should be unchanged")
}

@(test)
reset_particles_clears_runtime_state_and_marks_all_slots_dead :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
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

    app_particles.reset_particles(ps)

    testing.expect_value(t, ps^.next_index, 0)
    testing.expect_value(t, ps^.spawn_timer, 0.0)
    testing.expect(t, !ps^.low_particles.alive[0])
    testing.expect_value(t, ps^.low_particles.age[0], 0.0)
    testing.expect(t, !ps^.particles.alive[0])
    testing.expect_value(t, ps^.particles.age[0], 0.0)
    testing.expect(t, !ps^.high_particles.alive[0])
    testing.expect_value(t, ps^.high_particles.age[0], 0.0)
}

@(test)
screenshake_on_dust_kick_adds_trauma :: proc(t: ^testing.T) {
    scale: app_core.Iso_Scale

    app_view_core.screenshake_on_dust_kick(&scale)

    testing.expect(t, scale.screenshake_trauma > 0)
    testing.expect_value(t, scale.screenshake_elapsed, 0.0)
}

@(test)
screenshake_on_dust_kick_batch_uses_stronger_aggregated_impulse :: proc(t: ^testing.T) {
    single: app_core.Iso_Scale
    batch: app_core.Iso_Scale

    app_view_core.screenshake_on_dust_kick(&single)
    app_view_core.screenshake_on_dust_kick_batch(&batch, 8)

    testing.expect(t, batch.screenshake_trauma > single.screenshake_trauma)
}

@(test)
screenshake_update_decays_and_clears_deterministically :: proc(t: ^testing.T) {
    scale: app_core.Iso_Scale

    app_view_core.screenshake_on_dust_kick(&scale)
    before := scale.screenshake_trauma

    app_view_core.screenshake_update(&scale, 0.01)

    testing.expect(t, scale.screenshake_trauma < before)
    testing.expect(t, scale.screenshake_offset_x != 0 || scale.screenshake_offset_y != 0)

    app_view_core.screenshake_update(&scale, app_view_core.SCREENSHAKE_MAX_TIME)

    testing.expect_value(t, scale.screenshake_trauma, 0.0)
    testing.expect_value(t, scale.screenshake_elapsed, 0.0)
    testing.expect_value(t, scale.screenshake_offset_x, 0.0)
    testing.expect_value(t, scale.screenshake_offset_y, 0.0)
}

@(test)
reserve_dead_low_particle_slot_wraps_when_all_slots_alive :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)

    ps^.use_max_dust_particles = 2
    ps^.next_index = 0
    ps^.low_particles.alive[0] = true
    ps^.low_particles.alive[1] = true

    idx, ok := app_particles.reserve_dead_low_particle_slot(ps)
    testing.expect(t, ok)
    testing.expect_value(t, idx, 0)
    testing.expect_value(t, ps^.next_index, 1)
}

@(test)
emit_shapes_hide_burst_spawns_dust_for_supported_shapes :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)
    ps^.use_max_dust_particles = 4

    ks: app_core.Shapes_Point_System
    ks.points[0].do_draw = true
    ks.points[0].kind = .Point
    ks.points[0].position = app_core.Vector3{1, 2, 0}

    app_particles.emit_shapes_hide_burst(ps, &ks, 0, false)

    testing.expect(t, ps^.low_particles.alive[0])
    testing.expect(t, ps^.low_particles.alive[1] || ps^.low_particles.alive[2] || ps^.low_particles.alive[3])
}

@(test)
clamp_xy_bounds_index_bounces_particles_back_inside_bounds :: proc(t: ^testing.T) {
    ps := new(app_core.Particle_System)
    defer free(ps)
    ps^.use_max_dust_particles = 1

    ps^.low_particles.pos_x[0] = -0.5
    ps^.low_particles.pos_y[0] = 1.2
    ps^.low_particles.vel_x[0] = -0.1
    ps^.low_particles.vel_y[0] = 0.2

    app_particles.clamp_xy_bounds_index(ps, 0)

    testing.expect_value(t, ps^.low_particles.pos_x[0], app_particles.DUST_XY_MIN)
    testing.expect_value(t, ps^.low_particles.pos_y[0], app_particles.DUST_XY_MAX)
    testing.expect(t, ps^.low_particles.vel_x[0] > 0)
    testing.expect(t, ps^.low_particles.vel_y[0] < 0)
}
