package ui_dust

import geometry "../../core/geometry"
import math "core:math"
import rand "core:math/rand"

// ui_dust_settle retires every visual effect and invalidates its viewport context.
ui_dust_settle :: proc(system: ^Ui_Dust_System) {
    if system == nil {
        return
    }
    system^.particle_count = 0
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
        system^.particle_count = 0
        ui_dust_cancel_arrival(system)
    }
    system^.viewport = visual.viewport
    system^.scroll_y = visual.scroll_y
    system^.visual_signature = visual.visual_signature
    system^.viewport_initialized = true
}

// ui_dust_begin_departure clears the previous batch and reseeds the private stream.
// Callers then emit one particle per selected ink sample with ui_dust_emit.
ui_dust_begin_departure :: proc(system: ^Ui_Dust_System, generation: u64) {
    if system == nil {
        return
    }
    system^.particle_count = 0
    ui_dust_cancel_arrival(system)
    system^.departure_context_pending = true
    rand.reset(UI_DUST_RANDOM_SEED ~ generation,
        rand.xoshiro256_random_generator(&system^.rng_state))
}

// ui_dust_emit appends one falling fragment at an ink sample's pane position.
ui_dust_emit :: proc(
    system: ^Ui_Dust_System, position: geometry.Vector2, ink: [4]u8,
    coverage: u8, visible_alpha: f32) -> bool {
    if system == nil || system^.particle_count >= UI_DUST_MAX_PARTICLES {
        return false
    }
    generator := rand.xoshiro256_random_generator(&system^.rng_state)
    coverage_unit := f32(coverage) / 255
    alpha := f32(ink[3]) / 255 * coverage_unit * clamp(visible_alpha, 0, 1)
    system^.particles[system^.particle_count] = {
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
    system^.particle_count += 1
    return true
}

// ui_dust_advance progresses effects independently of world pause state.
ui_dust_advance :: proc(system: ^Ui_Dust_System, delta_seconds: f32) {
    if system == nil || delta_seconds <= 0 {
        return
    }
    ui_dust_arrival_advance(system, delta_seconds)
    floor_y := system^.viewport.y + system^.viewport.height
    live_count := 0
    for index in 0..<system^.particle_count {
        particle := system^.particles[index]
        ui_dust_particle_advance(&particle, floor_y, delta_seconds)
        if particle.resting && particle.rest_age >= particle.life {
            continue
        }
        system^.particles[live_count] = particle
        live_count += 1
    }
    system^.particle_count = live_count
}

// ui_dust_particle_advance drops one fragment onto the floor, then ages its rest.
ui_dust_particle_advance :: proc(
    particle: ^Ui_Dust_Particle, floor_y, delta_seconds: f32) {
    particle^.age += delta_seconds
    if particle^.resting {
        particle^.rest_age += delta_seconds
        return
    }
    sway_velocity := particle^.sway_amplitude * particle^.sway_frequency *
        math.cos(particle^.age * particle^.sway_frequency + particle^.sway_phase)
    start_y := particle^.pos_y
    start_velocity_y := particle^.vel_y
    particle^.pos_x += (particle^.vel_x + sway_velocity) * delta_seconds
    particle^.pos_y += start_velocity_y * delta_seconds +
        0.5 * UI_DUST_DOWNWARD_ACCELERATION * delta_seconds * delta_seconds
    particle^.vel_y += UI_DUST_DOWNWARD_ACCELERATION * delta_seconds
    rest_y := floor_y - particle^.size
    if particle^.pos_y < rest_y {
        return
    }
    distance := max(0, rest_y - start_y)
    impact_time := (-start_velocity_y + math.sqrt(
        start_velocity_y * start_velocity_y +
        2 * UI_DUST_DOWNWARD_ACCELERATION * distance)) /
        UI_DUST_DOWNWARD_ACCELERATION
    particle^.pos_y = rest_y
    particle^.vel_x = 0
    particle^.vel_y = 0
    particle^.resting = true
    particle^.rest_age = max(delta_seconds - impact_time, 0)
}

// ui_dust_particle_alpha returns one live particle's opacity in [0, 1].
// Falling fragments keep their ink opacity; resting fragments fade smoothly out.
ui_dust_particle_alpha :: proc(system: ^Ui_Dust_System, index: int) -> f32 {
    if system == nil || index < 0 || index >= system^.particle_count {
        return 0
    }
    base_alpha := f32(system^.particles.color[index].a) / 255
    if !system^.particles.resting[index] {
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
