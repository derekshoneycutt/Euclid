package ui_dust

import geometry "../../core/geometry"
import math "core:math"
import testing "core:testing"

// Verify every source height reaches the exact floor at the fixed deadline.
@(test)
ui_dust_departure_deadline_is_height_independent :: proc(t: ^testing.T) {
    for height in ([3]f32{120, 1200, 12000}) {
        system := ui_dust_test_system({0, 0, 200, height})
        ui_dust_begin_departure(system, 1)
        testing.expect(t, ui_dust_emit(
            system, {50, 10}, {20, 40, 60, 255}, 255, 1))
        reference: Ui_Dust_Slot_Ref = {0, system^.order[0].generation}
        testing.expect(t, ui_dust_reclaim_eligible(system, reference))
        ui_dust_advance(system, UI_DUST_DEPARTURE_DURATION)
        particle := system^.particles[0]
        testing.expect_value(t, particle.phase, Ui_Dust_Phase.Resting_Departure)
        testing.expect_value(t, particle.pos_y, height - particle.size)
        testing.expect_value(t, particle.rest_age, f32(0))
        testing.expect_value(t, particle.vel_x, f32(0))
        testing.expect_value(t, particle.vel_y, f32(0))
        testing.expect(t, !ui_dust_reclaim_eligible(system, reference))
        appearance, valid := ui_dust_evaluate(system, reference)
        testing.expect(t, valid)
        testing.expect_value(t, appearance.velocity, geometry.Vector2{})
        ui_dust_advance(system, particle.life)
        testing.expect_value(t, system^.live_count, 0)
        free(system, context.allocator)
    }
}

// Verify a coarse flight frame spends its full remainder fading at the floor.
@(test)
ui_dust_departure_coarse_frame_consumes_rest_remainder :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 1200})
    defer free(system, context.allocator)
    testing.expect(t, ui_dust_emit(system, {50, 20}, {20, 40, 60, 255}, 255, 1))
    system^.particles.life[0] = 1
    ui_dust_advance(system, UI_DUST_DEPARTURE_DURATION + 0.5)
    testing.expect_value(t, system^.particles.rest_age[0], f32(0.5))
    testing.expect_value(t, ui_dust_particle_alpha(system, 0), f32(0.5))
    x := system^.particles.pos_x[0]
    ui_dust_advance(system, 0.25)
    testing.expect_value(t, system^.particles.pos_x[0], x)
    ui_dust_advance(system, 0.25)
    testing.expect_value(t, system^.live_count, 0)
    testing.expect(t, ui_dust_emit(system, {50, 20}, {20, 40, 60, 255}, 255, 1))
    ui_dust_advance(system, UI_DUST_DEPARTURE_DURATION + UI_DUST_REST_LIFE_MAX)
    testing.expect_value(t, system^.live_count, 0)
}

// Compare copied appearance with tolerances for accumulated floating-point clocks.
ui_dust_test_appearance_near :: proc(
    t: ^testing.T, first, second: Ui_Dust_Appearance) {
    testing.expect(t, math.abs(first.position.x - second.position.x) < 0.002)
    testing.expect(t, math.abs(first.position.y - second.position.y) < 0.002)
    testing.expect(t, math.abs(first.velocity.x - second.velocity.x) < 0.01)
    testing.expect(t, math.abs(first.velocity.y - second.velocity.y) < 0.01)
    testing.expect(t, math.abs(first.alpha - second.alpha) < 0.0001)
    testing.expect_value(t, first.tint, second.tint)
    testing.expect_value(t, first.size, second.size)
    testing.expect_value(t, first.sprite_index, second.sprite_index)
}

// Verify analytic departure position, velocity and fade do not depend on frame size.
@(test)
ui_dust_departure_partition_invariance :: proc(t: ^testing.T) {
    first := ui_dust_test_system({0, 0, 200, 1200})
    second := ui_dust_test_system({0, 0, 200, 1200})
    defer free(first, context.allocator)
    defer free(second, context.allocator)
    for system in ([2]^Ui_Dust_System{first, second}) {
        ui_dust_begin_departure(system, 2)
        testing.expect(t, ui_dust_emit(system, {50, 20}, {20, 40, 60, 200}, 192, 0.7))
    }
    for elapsed in ([3]f32{0.125, 0.25, 0.5}) {
        ui_dust_advance(first, elapsed)
        for _ in 0..<8 {
            ui_dust_advance(second, elapsed / 8)
        }
        first_appearance, first_valid := ui_dust_evaluate(first, {0, 1})
        second_appearance, second_valid := ui_dust_evaluate(second, {0, 1})
        testing.expect(t, first_valid && second_valid)
        ui_dust_test_appearance_near(t, first_appearance, second_appearance)
        testing.expect_value(t, first^.particles.phase[0], second^.particles.phase[0])
    }
}

// Verify full text opacity and arrival retirement at exactly 0.30 seconds.
@(test)
ui_dust_arrival_deadline_and_partition_invariance :: proc(t: ^testing.T) {
    first := ui_dust_test_system({0, 0, 200, 200})
    second := ui_dust_test_system({0, 0, 200, 200})
    defer free(first, context.allocator)
    defer free(second, context.allocator)
    for system in ([2]^Ui_Dust_System{first, second}) {
        testing.expect(t, ui_dust_test_formation(system, 8, {80, 90}))
        system^.particles.delay[0] = UI_DUST_ARRIVAL_DELAY_MAX
        system^.particles.duration[0] = UI_DUST_ARRIVAL_FALL_MAX
    }
    for elapsed in ([2]f32{0.125, 0.14}) {
        ui_dust_advance(first, elapsed)
        for _ in 0..<8 {
            ui_dust_advance(second, elapsed / 8)
        }
        first_appearance, _ := ui_dust_evaluate(first, {0, 1})
        second_appearance, _ := ui_dust_evaluate(second, {0, 1})
        ui_dust_test_appearance_near(t, first_appearance, second_appearance)
    }
    for system in ([2]^Ui_Dust_System{first, second}) {
        ui_dust_advance(system, f32(0.30) - system^.incoming_elapsed)
        testing.expect_value(t, ui_dust_incoming_alpha(system), f32(1))
        testing.expect(t, !system^.incoming_active)
        testing.expect_value(t, system^.arrival_count, 0)
        testing.expect_value(t, system^.live_count, 0)
    }
}

// Verify bounded target waiting does not spend the post-target formation budget.
@(test)
ui_dust_arrival_target_wait_and_coarse_retirement :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    ui_dust_begin_arrival(system, 8, .Falling_Ink)
    ui_dust_advance(system, UI_DUST_ARRIVAL_TARGET_WAIT_LIMIT * 0.75)
    testing.expect(t, ui_dust_arrival_awaiting_targets(system))
    ui_dust_begin_formation(system)
    testing.expect(t, ui_dust_emit_arrival(system, {80, 90}, {20, 40, 60, 255}, 255))
    testing.expect_value(t, system^.incoming_elapsed, f32(0))
    ui_dust_advance(system, 0.5)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(1))
    testing.expect_value(t, system^.live_count, 0)
    ui_dust_begin_arrival(system, 9, .Falling_Ink)
    ui_dust_advance(system, UI_DUST_ARRIVAL_TARGET_WAIT_LIMIT + UI_DUST_FADE_DURATION)
    testing.expect(t, !system^.incoming_active)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(1))
}

// Verify derivatives include sway by comparing against central position differences.
ui_dust_test_velocity_derivative :: proc(
    t: ^testing.T, system: ^Ui_Dust_System, arrival: bool) {
    epsilon := f32(0.0001)
    reference: Ui_Dust_Slot_Ref = {0, system^.order[0].generation}
    center, valid := ui_dust_evaluate(system, reference)
    testing.expect(t, valid)
    before, after := geometry.Vector2{}, geometry.Vector2{}
    if arrival {
        system^.incoming_elapsed -= epsilon
        before = ui_dust_arrival_position(system, 0)
        system^.incoming_elapsed += 2 * epsilon
        after = ui_dust_arrival_position(system, 0)
        system^.incoming_elapsed -= epsilon
    } else {
        particle := system^.particles[0]
        particle.flight_elapsed -= epsilon
        before, _ = ui_dust_departure_motion(particle, system^.viewport.height)
        particle.flight_elapsed += 2 * epsilon
        after, _ = ui_dust_departure_motion(particle, system^.viewport.height)
    }
    derivative := (after - before) / (2 * epsilon)
    testing.expect(t, math.abs(derivative.x - center.velocity.x) < 0.1)
    testing.expect(t, math.abs(derivative.y - center.velocity.y) < 0.2)
}

// Verify reusable evaluation matches motion and appearance for both fragment paths.
@(test)
ui_dust_evaluation_matches_rendered_motion :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    testing.expect(t, ui_dust_emit(system, {50, 20}, {20, 40, 60, 255}, 255, 1))
    ui_dust_advance(system, 0.125)
    ui_dust_test_velocity_derivative(t, system, false)
    ui_dust_settle(system)
    testing.expect(t, ui_dust_test_formation(system, 8, {80, 90}))
    ui_dust_advance(system, 0.125)
    ui_dust_test_velocity_derivative(t, system, true)
    appearance, valid := ui_dust_evaluate(system, {0, system^.order[0].generation})
    testing.expect(t, valid)
    testing.expect_value(t, appearance.position, ui_dust_arrival_position(system, 0))
    testing.expect_value(t, appearance.alpha, ui_dust_arrival_alpha(system, 0))
    system^.incoming_elapsed = UI_DUST_ARRIVAL_DELAY_MAX + UI_DUST_ARRIVAL_FALL_MAX
    testing.expect_value(t, ui_dust_arrival_velocity(system, 0), geometry.Vector2{})
    testing.expect_value(t, ui_dust_arrival_position(system, 0), geometry.Vector2{80, 90})
    testing.expect(t, !ui_dust_reclaim_eligible(system,
        {0, system^.order[0].generation}))
    _, stale_valid := ui_dust_evaluate(system, {0, 1})
    testing.expect(t, !stale_valid)
}
