package ui_dust

import geometry "../../core/geometry"
import testing "core:testing"

// Create one heap-backed test system so fixed SoA storage stays off the test stack.
ui_dust_test_system :: proc(viewport: geometry.Rectangle) -> ^Ui_Dust_System {
    system := new(Ui_Dust_System, context.allocator)
    ui_dust_validate_context(system, {visible = true, viewport = viewport})
    return system
}

// Emit `count` deterministic ink samples spread across a wide source line.
ui_dust_test_emit_line :: proc(system: ^Ui_Dust_System, count: int) -> int {
    emitted := 0
    for index in 0..<count {
        if ui_dust_emit(system, {f32(index), f32(index % 29)},
            {20, 40, 60, 255}, u8(index % 255 + 1), 1) {
            emitted += 1
        }
    }
    return emitted
}

// Verify emission is deterministic, bounded by fixed capacity, and moves downward.
@(test)
ui_dust_departure_is_deterministic_and_bounded :: proc(t: ^testing.T) {
    viewport := geometry.Rectangle{0, 0, 5000, 100}
    first := ui_dust_test_system(viewport)
    second := ui_dust_test_system(viewport)
    defer free(first, context.allocator)
    defer free(second, context.allocator)
    ui_dust_begin_departure(first, 71)
    ui_dust_begin_departure(second, 71)
    testing.expect_value(t, ui_dust_test_emit_line(first, 4096),
        UI_DUST_TOTAL_PARTICLES)
    testing.expect_value(t, ui_dust_test_emit_line(second, 4096),
        UI_DUST_TOTAL_PARTICLES)
    testing.expect_value(t, first^.particle_count, UI_DUST_TOTAL_PARTICLES)
    testing.expect_value(t, first^.particles[0], second^.particles[0])
    last := UI_DUST_TOTAL_PARTICLES - 1
    testing.expect_value(t, first^.particles[last], second^.particles[last])
    testing.expect(t, first^.particles.vel_y[0] >= UI_DUST_VY_MIN)
    testing.expect(t, first^.particles.dust_sprite_index[0] <
        UI_DUST_SPRITE_VARIANT_COUNT)
    initial_alpha := ui_dust_particle_alpha(first, 0)
    initial_y := first^.particles.pos_y[0]
    ui_dust_advance(first, 0.05)
    testing.expect(t, first^.particles.pos_y[0] > initial_y + 1.2)
    testing.expect_value(t, ui_dust_particle_alpha(first, 0), initial_alpha)
    ui_dust_advance(first, 4)
    testing.expect_value(t, first^.particle_count, 0)
}

// Verify fragments come to rest on the viewport floor and fade after landing.
@(test)
ui_dust_departure_rests_at_floor_before_fading :: proc(t: ^testing.T) {
    viewport := geometry.Rectangle{0, 0, 100, 120}
    system := ui_dust_test_system(viewport)
    defer free(system, context.allocator)
    ui_dust_begin_departure(system, 71)
    testing.expect(t, ui_dust_emit(system, {50, 10}, {20, 40, 60, 255}, 255, 1))
    initial_alpha := ui_dust_particle_alpha(system, 0)
    ui_dust_advance(system, UI_DUST_DEPARTURE_DURATION + 0.2)
    testing.expect_value(t, system^.particle_count, 1)
    particle := system^.particles[0]
    testing.expect_value(t, particle.phase, Ui_Dust_Phase.Resting_Departure)
    testing.expect_value(t, particle.pos_y,
        viewport.y + viewport.height - particle.size)
    testing.expect(t, particle.rest_age > 0)
    testing.expect(t, ui_dust_particle_alpha(system, 0) < initial_alpha)
    ui_dust_advance(system, 2)
    testing.expect_value(t, system^.particle_count, 0)
}

// Verify smooth arrival opacity progresses without animation or simulation policy.
@(test)
ui_dust_arrival_fades_and_settles :: proc(t: ^testing.T) {
    system := new(Ui_Dust_System, context.allocator)
    defer free(system, context.allocator)
    ui_dust_begin_arrival(system, 8, .Fade)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(0))
    ui_dust_advance(system, UI_DUST_FADE_DURATION * 0.5)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(0.5))
    ui_dust_advance(system, UI_DUST_FADE_DURATION)
    testing.expect(t, !system^.incoming_active)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(1))
}

// Verify reduced motion and viewport invalidation retire every active effect.
@(test)
ui_dust_context_invalidation_retires_effects :: proc(t: ^testing.T) {
    system := new(Ui_Dust_System, context.allocator)
    defer free(system, context.allocator)
    viewport := geometry.Rectangle{10, 20, 200, 120}
    ui_dust_validate_context(system, {
        visible = true, viewport = viewport, scroll_y = 5, visual_signature = 1,
    })
    ui_dust_begin_arrival(system, 9, .Fade)
    ui_dust_advance(system, 0.01)
    ui_dust_validate_context(system, {
        visible = true, viewport = viewport, scroll_y = 6, visual_signature = 1,
    })
    testing.expect(t, !system^.incoming_active)
    ui_dust_begin_departure(system, 10)
    testing.expect(t, ui_dust_emit(system, {20, 30}, {1, 2, 3, 255}, 255, 1))
    ui_dust_validate_context(system, {
        visible = true, reduced_motion = true, viewport = viewport,
        scroll_y = 6, visual_signature = 1,
    })
    testing.expect_value(t, system^.particle_count, 0)
    testing.expect(t, !system^.viewport_initialized)
}
