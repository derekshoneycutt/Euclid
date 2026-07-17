package particles_tests

import "core:math"
import "core:testing"

import app_core "../../src/core"
import app_particles "../../src/particles"

EPS :: f32(1e-5)

expect_close :: proc(t: ^testing.T, actual, expected: f32, msg: string) {
    testing.expectf(t, math.abs(actual - expected) <= EPS,
        "%s | expected=%v got=%v", msg, expected, actual)
}

@(test)
normalize_theta_and_sweep_delta_are_stable :: proc(t: ^testing.T) {
    theta := app_particles.normalize_theta(f32(-0.5))
    expect_close(t, theta, f32(2.0 * math.PI - 0.5), "normalize_theta should wrap negatives")

    delta := app_particles.compute_sweep_delta(
        f32(1.5 * math.PI),
        f32(0.5 * math.PI))
    expect_close(t, delta, f32(math.PI), "sweep delta should wrap across zero")
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

    expect_close(t, ps^.low_particles.pos_x[0], before_ax, "no collision should keep ax")
    expect_close(t, ps^.low_particles.pos_y[0], before_ay, "no collision should keep ay")
    expect_close(t, ps^.low_particles.pos_x[1], before_bx, "no collision should keep bx")
    expect_close(t, ps^.low_particles.pos_y[1], before_by, "no collision should keep by")
    expect_close(t, ps^.low_particles.vel_x[0], before_avx, "no collision should keep avx")
    expect_close(t, ps^.low_particles.vel_y[0], before_avy, "no collision should keep avy")
    expect_close(t, ps^.low_particles.vel_x[1], before_bvx, "no collision should keep bvx")
    expect_close(t, ps^.low_particles.vel_y[1], before_bvy, "no collision should keep bvy")
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
    expect_close(t, ps^.low_particles.vel_x[0], f32(-0.01), "separating vx0 should be unchanged")
    expect_close(t, ps^.low_particles.vel_x[1], f32(0.01), "separating vx1 should be unchanged")
}
