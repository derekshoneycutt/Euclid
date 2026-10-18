package ui_dust

import geometry "../../core/geometry"
import testing "core:testing"

// Start one falling-ink arrival with a single fixed target ready to descend.
ui_dust_test_formation :: proc(
    system: ^Ui_Dust_System, generation: u64, target: geometry.Vector2) -> bool {
    ui_dust_begin_arrival(system, generation, .Falling_Ink)
    ui_dust_begin_formation(system)
    return ui_dust_emit_arrival(system, target, {20, 40, 60, 255}, 255)
}

// Verify particles start above their targets and land exactly on them.
@(test)
ui_dust_arrival_converges_onto_targets :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    target := geometry.Vector2{50, 80}
    testing.expect(t, ui_dust_test_formation(system, 5, target))
    delay := system^.particles.delay[0]
    duration := system^.particles.duration[0]
    ui_dust_advance(system, delay + 0.01)
    start := ui_dust_arrival_position(system, 0)
    testing.expect(t, start.y < target.y - UI_DUST_ARRIVAL_DROP_MIN * 0.5)
    testing.expect(t, ui_dust_arrival_alpha(system, 0) > 0)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(0))
    ui_dust_advance(system, duration)
    landed := ui_dust_arrival_position(system, 0)
    testing.expect_value(t, landed, target)
    testing.expect(t, system^.incoming_active)
}

// Verify the handoff cross-fades particles into the exact drawing, then retires them.
@(test)
ui_dust_arrival_hands_off_to_drawing :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    testing.expect(t, ui_dust_test_formation(system, 6, {10, 10}))
    testing.expect_value(t, ui_dust_arrival_alpha(system, 0), f32(0))
    midpoint := (UI_DUST_ARRIVAL_HANDOFF_START + UI_DUST_ARRIVAL_HANDOFF_END) / 2
    ui_dust_advance(system, midpoint)
    text_alpha := ui_dust_incoming_alpha(system)
    testing.expect(t, text_alpha > 0.4 && text_alpha < 0.6)
    testing.expect_value(t, ui_dust_arrival_alpha(system, 0), 1 - text_alpha)
    ui_dust_advance(system, UI_DUST_ARRIVAL_HANDOFF_END)
    testing.expect(t, !system^.incoming_active)
    testing.expect_value(t, system^.arrival_count, 0)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(1))
}

// Verify formation is deterministic per generation and bounded by its own budget.
@(test)
ui_dust_arrival_is_deterministic_and_bounded :: proc(t: ^testing.T) {
    first := ui_dust_test_system({0, 0, 5000, 100})
    second := ui_dust_test_system({0, 0, 5000, 100})
    defer free(first, context.allocator)
    defer free(second, context.allocator)
    for system in ([2]^Ui_Dust_System{first, second}) {
        ui_dust_begin_arrival(system, 12, .Falling_Ink)
        testing.expect(t, !ui_dust_emit_arrival(system, {1, 1}, {1, 2, 3, 255}, 255))
        ui_dust_begin_formation(system)
        emitted := 0
        for index in 0..<2*UI_DUST_MAX_ARRIVAL_PARTICLES {
            if ui_dust_emit_arrival(system, {f32(index), 50}, {1, 2, 3, 255}, 200) {
                emitted += 1
            }
        }
        testing.expect_value(t, emitted, UI_DUST_MAX_ARRIVAL_PARTICLES)
    }
    last := UI_DUST_MAX_ARRIVAL_PARTICLES - 1
    testing.expect_value(t, first^.particles[0], second^.particles[0])
    testing.expect_value(t, first^.particles[last], second^.particles[last])
    testing.expect(t, first^.particles.delay[0] <= UI_DUST_ARRIVAL_DELAY_MAX)
}

// Verify content stays hidden while awaiting targets and degrades to the fade.
@(test)
ui_dust_arrival_without_targets_falls_back_to_fade :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    ui_dust_begin_arrival(system, 7, .Falling_Ink)
    testing.expect(t, ui_dust_arrival_awaiting_targets(system))
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(0))
    ui_dust_advance(system, UI_DUST_ARRIVAL_TARGET_WAIT_LIMIT)
    testing.expect(t, !ui_dust_arrival_awaiting_targets(system))
    testing.expect_value(t, system^.incoming_style, Ui_Dust_Arrival_Style.Fade)
    ui_dust_advance(system, UI_DUST_FADE_DURATION * 0.5)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(0.5))
    ui_dust_begin_arrival(system, 8, .Immediate)
    testing.expect(t, !system^.incoming_active)
}

// Verify departure, viewport invalidation, and reduced motion cancel formation.
@(test)
ui_dust_arrival_cancellation_retires_particles :: proc(t: ^testing.T) {
    viewport := geometry.Rectangle{0, 0, 200, 200}
    system := ui_dust_test_system(viewport)
    defer free(system, context.allocator)
    testing.expect(t, ui_dust_test_formation(system, 1, {10, 10}))
    ui_dust_begin_departure(system, 2)
    testing.expect_value(t, system^.arrival_count, 0)
    testing.expect(t, !system^.incoming_active)
    testing.expect(t, ui_dust_test_formation(system, 3, {10, 10}))
    ui_dust_validate_context(system, {visible = true, viewport = {0, 0, 210, 200}})
    testing.expect_value(t, system^.arrival_count, 0)
    testing.expect(t, ui_dust_test_formation(system, 4, {10, 10}))
    ui_dust_validate_context(system, {
        visible = true, reduced_motion = true, viewport = viewport,
    })
    testing.expect_value(t, system^.arrival_count, 0)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(1))
}
