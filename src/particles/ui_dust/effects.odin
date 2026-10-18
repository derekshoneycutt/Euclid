package ui_dust

import geometry "../../core/geometry"
import math "core:math"
import rand "core:math/rand"

// ui_dust_settle retires every visual effect and invalidates its viewport context.
ui_dust_settle :: proc(system: ^Ui_Dust_System) {
    if system == nil {
        return
    }
    ui_dust_slots_clear(system)
    ui_dust_cancel_arrival(system)
    system^.viewport_initialized = false
    system^.departure_context_pending = false
}

// ui_dust_validate_context cancels effects made stale by display changes.
ui_dust_validate_context :: proc(
    system: ^Ui_Dust_System, visual: Ui_Dust_Visual_Context) {
    if system == nil {
        return
    }
    if !visual.visible || visual.reduced_motion ||
        visual.viewport.width <= 0 || visual.viewport.height <= 0 {
        ui_dust_settle(system)
        return
    }
    new_arrival := system^.incoming_active && system^.incoming_elapsed == 0
    ignore_departure_scroll := system^.departure_context_pending
    system^.departure_context_pending = false
    scroll_changed := system^.scroll_y != visual.scroll_y &&
        !new_arrival && !ignore_departure_scroll
    if system^.viewport_initialized &&
        (system^.viewport != visual.viewport || scroll_changed ||
         system^.visual_signature != visual.visual_signature) {
        ui_dust_slots_clear(system)
        ui_dust_cancel_arrival(system)
    }
    system^.viewport = visual.viewport
    system^.scroll_y = visual.scroll_y
    system^.visual_signature = visual.visual_signature
    system^.viewport_initialized = true
}

// ui_dust_begin_departure releases forming material in Reclaim mode; Independent
// and comparison arrivals keep replacement semantics. Surplus retains its clocks.
ui_dust_begin_departure :: proc(
    system: ^Ui_Dust_System, generation: u64,
    next_style: Ui_Dust_Arrival_Style = UI_DUST_ARRIVAL_STYLE) {
    if system == nil {
        return
    }
    if system^.transition == .Reclaim && next_style == .Falling_Ink &&
        (system^.incoming_style == .Falling_Ink || !system^.incoming_active) {
        ui_dust_release_arrivals(system)
    } else {
        ui_dust_slots_clear(system)
    }
    ui_dust_cancel_arrival(system)
    system^.departure_context_pending = true
    rand.reset(UI_DUST_RANDOM_SEED ~ generation,
        rand.xoshiro256_random_generator(&system^.rng_state))
}

// ui_dust_emit appends one falling fragment at an ink sample's pane position.
ui_dust_emit :: proc(
    system: ^Ui_Dust_System, position: geometry.Vector2, ink: [4]u8,
    coverage: u8, visible_alpha: f32) -> bool {
    if system == nil {
        return false
    }
    generator := rand.xoshiro256_random_generator(&system^.rng_state)
    coverage_unit := f32(coverage) / 255
    alpha := f32(ink[3]) / 255 * coverage_unit * clamp(visible_alpha, 0, 1)
    particle := Ui_Dust_Particle{
        phase = .Airborne_Departure,
        pos_x = position.x,
        pos_y = position.y,
        vel_x = rand.float32_range(UI_DUST_VX_MIN, UI_DUST_VX_MAX, generator),
        vel_y = rand.float32_range(UI_DUST_VY_MIN, UI_DUST_VY_MAX, generator),
        life = rand.float32_range(
            UI_DUST_REST_LIFE_MIN, UI_DUST_REST_LIFE_MAX, generator),
        size = UI_DUST_SIZE_MIN + coverage_unit * UI_DUST_SIZE_COVERAGE_SCALE,
        sway_amplitude = rand.float32_range(
            UI_DUST_SWAY_AMPLITUDE_MIN, UI_DUST_SWAY_AMPLITUDE_MAX, generator),
        sway_frequency = rand.float32_range(
            UI_DUST_SWAY_FREQUENCY_MIN, UI_DUST_SWAY_FREQUENCY_MAX, generator),
        sway_phase = rand.float32_range(0, 2 * math.PI, generator),
        color = {ink[0], ink[1], ink[2], u8(clamp(alpha * 255, 0, 255))},
        dust_sprite_index = u8(rand.int32_range(
            0, UI_DUST_SPRITE_VARIANT_COUNT, generator)),
    }
    particle.start_x = position.x
    particle.start_y = position.y
    particle.start_velocity_x = particle.vel_x
    particle.start_velocity_y = particle.vel_y
    _ = ui_dust_slot_emit(system, particle)
    return true
}

// ui_dust_advance progresses effects independently of world pause state.
ui_dust_advance :: proc(system: ^Ui_Dust_System, delta_seconds: f32) {
    if system == nil || delta_seconds <= 0 {
        return
    }
    ui_dust_arrival_advance(system, delta_seconds)
    floor_y := system^.viewport.y + system^.viewport.height
    cursor := system^.live_head
    for cursor != 0 {
        index := cursor - 1
        cursor = system^.order[index].next
        particle := system^.particles[index]
        if ui_dust_phase_is_arrival(particle.phase) {
            system^.particles.age[index] += delta_seconds
            continue
        }
        ui_dust_particle_advance(&particle, floor_y, delta_seconds)
        if particle.phase == .Resting_Departure && particle.rest_age >= particle.life {
            retired := ui_dust_slot_retire(
                system, {index, system^.order[index].generation})
            assert(retired)
            continue
        }
        system^.particles[index] = particle
    }
}

// ui_dust_particle_advance reaches the floor at the fixed deadline and consumes
// the same frame's remainder into stationary fade, independently of frame partition.
ui_dust_particle_advance :: proc(
    particle: ^Ui_Dust_Particle, floor_y, delta_seconds: f32) {
    particle^.age += delta_seconds
    if particle^.phase == .Resting_Departure {
        particle^.rest_age += delta_seconds
        return
    }
    particle^.flight_elapsed += delta_seconds
    position, velocity := ui_dust_departure_motion(particle^, floor_y)
    particle^.pos_x = position.x
    particle^.pos_y = position.y
    particle^.vel_x = velocity.x
    particle^.vel_y = velocity.y
    if particle^.flight_elapsed >= UI_DUST_DEPARTURE_DURATION {
        particle^.phase = .Resting_Departure
        particle^.rest_age = particle^.flight_elapsed - UI_DUST_DEPARTURE_DURATION
    }
}

// ui_dust_particle_alpha returns one live particle's opacity in [0, 1].
// Falling fragments keep their ink opacity; resting fragments fade smoothly out.
ui_dust_particle_alpha :: proc(system: ^Ui_Dust_System, index: int) -> f32 {
    if system == nil || index < 0 || index >= system^.initialized_slots ||
        (system^.particles.phase[index] != .Airborne_Departure &&
         system^.particles.phase[index] != .Resting_Departure) {
        return 0
    }
    base_alpha := f32(system^.particles.color[index].a) / 255
    if system^.particles.captured[index] {
        base_alpha = system^.particles.captured_alpha[index]
    }
    if system^.particles.phase[index] != .Resting_Departure {
        return base_alpha
    }
    life := system^.particles.life[index]
    if life <= 0 {
        return 0
    }
    progress := clamp(system^.particles.rest_age[index] / life, 0, 1)
    remaining := 1 - progress
    return base_alpha * remaining * remaining * (1 + 2 * progress)
}
