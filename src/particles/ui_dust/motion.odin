package ui_dust

import geometry "../../core/geometry"
import color "../../core/color"
import math "core:math"

// ui_dust_departure_motion evaluates a bounded floor trajectory and its derivative.
// Vertical Hermite motion keeps the initial downward speed where monotonicity allows;
// lateral sway is integrated analytically rather than accumulated per frame.
ui_dust_departure_motion :: proc(
    particle: Ui_Dust_Particle, floor_y: f32) -> (
    position, velocity: geometry.Vector2) {
    duration := UI_DUST_DEPARTURE_DURATION
    elapsed := clamp(particle.flight_elapsed, 0, duration)
    unit := elapsed / duration
    distance := floor_y - particle.size - particle.start_y
    tangent := clamp(particle.start_velocity_y * duration, 0, max(0, 3 * distance))
    if particle.captured {
        tangent = particle.start_velocity_y * duration
    }
    wave := elapsed * particle.sway_frequency + particle.sway_phase
    position = {
        particle.start_x + particle.start_velocity_x * elapsed +
            particle.sway_amplitude * (math.sin(wave) - math.sin(particle.sway_phase)),
        particle.start_y + distance * unit * unit * (3 - 2 * unit) +
            tangent * unit * (unit - 1) * (unit - 1),
    }
    velocity = {
        particle.start_velocity_x +
            particle.sway_amplitude * particle.sway_frequency * math.cos(wave),
        (6 * distance * unit * (1 - unit) +
            tangent * (3 * unit * unit - 4 * unit + 1)) / duration,
    }
    if particle.flight_elapsed >= duration {
        position.y = floor_y - particle.size
        velocity = {}
    }
    return
}

// ui_dust_arrival_velocity differentiates the rendered cubic offset including sway.
// The delayed trajectory has no vertical motion before release and stops at target.
ui_dust_arrival_velocity :: proc(
    system: ^Ui_Dust_System, index: int) -> geometry.Vector2 {
    particle := system^.particles[index]
    if particle.phase == .Reclaimed_Arrival {
        _, velocity := ui_dust_reclaimed_motion(particle, system^.incoming_elapsed)
        return velocity
    }
    progress := ui_dust_arrival_progress(system, index)
    remaining := 1 - progress
    offset := remaining * remaining * remaining
    derivative := f32(0)
    if system^.incoming_elapsed >= particle.delay &&
        progress < 1 && particle.duration > 0 {
        derivative = -3 * remaining * remaining / particle.duration
    }
    wave := system^.incoming_elapsed * particle.sway_frequency + particle.sway_phase
    sway := particle.sway_amplitude * math.sin(wave)
    sway_velocity := particle.sway_amplitude * particle.sway_frequency * math.cos(wave)
    return {
        (particle.lateral + sway) * derivative + sway_velocity * offset,
        -particle.drop * derivative,
    }
}

// ui_dust_evaluate copies the exact rendered appearance and instantaneous velocity.
// Generation validation prevents a superseded borrower from observing reused ink.
ui_dust_evaluate :: proc(
    system: ^Ui_Dust_System, reference: Ui_Dust_Slot_Ref) -> (
    appearance: Ui_Dust_Appearance, valid: bool) {
    if !ui_dust_slot_valid(system, reference) {
        return
    }
    index := reference.index
    particle := system^.particles[index]
    appearance = {
        position = {particle.pos_x, particle.pos_y},
        velocity = {particle.vel_x, particle.vel_y},
        tint = particle.color,
        alpha = ui_dust_particle_alpha(system, index),
        size = particle.size,
        sprite_index = particle.dust_sprite_index,
        ink_style = particle.ink_style,
    }
    if ui_dust_phase_is_arrival(particle.phase) {
        appearance.position = ui_dust_arrival_position(system, index)
        appearance.velocity = ui_dust_arrival_velocity(system, index)
        appearance.alpha = ui_dust_arrival_alpha(system, index)
        if particle.phase == .Reclaimed_Arrival {
            blend := ui_dust_smoothstep(ui_dust_arrival_progress(system, index))
            appearance.tint = ui_dust_blend_tint(
                particle.color, particle.target_color, blend)
            appearance.ink_style = ui_dust_blend_ink_style(particle, blend)
            appearance.size += (particle.target_size - particle.size) * blend
        }
    } else if particle.phase == .Airborne_Departure {
        _, appearance.velocity = ui_dust_departure_motion(
            particle, system^.viewport.y + system^.viewport.height)
    }
    return appearance, true
}

// ui_dust_blend_ink_style blends display variants before policy selection, preserving ordinary ink.
ui_dust_blend_ink_style :: proc(
    particle: Ui_Dust_Particle, blend: f32) -> Ui_Dust_Ink {
    start := particle.ink_style
    target := particle.target_ink_style
    if !start.authored && !target.authored {
        return {}
    }
    if !start.authored {
        start.monochrome, start.increased = particle.color, particle.color
    }
    if !target.authored {
        target.monochrome, target.increased = particle.target_color, particle.target_color
    }
    return {
        monochrome = ui_dust_blend_tint(start.monochrome, target.monochrome, blend),
        increased = ui_dust_blend_tint(start.increased, target.increased, blend),
        authored = true,
    }
}

// ui_dust_reclaimed_motion preserves takeover position and velocity, ending at rest.
ui_dust_reclaimed_motion :: proc(
    particle: Ui_Dust_Particle, elapsed: f32) -> (
    position, velocity: geometry.Vector2) {
    target: geometry.Vector2 = {particle.target_x, particle.target_y}
    if particle.duration <= 0 || elapsed >= particle.duration {
        return target, {}
    }
    unit := clamp(elapsed / particle.duration, 0, 1)
    start: geometry.Vector2 = {particle.start_x, particle.start_y}
    initial: geometry.Vector2 = {particle.start_velocity_x, particle.start_velocity_y}
    squared, cubed := unit * unit, unit * unit * unit
    position = start * (2*cubed - 3*squared + 1) +
        initial * particle.duration * (cubed - 2*squared + unit) +
        target * (-2*cubed + 3*squared)
    velocity = (start - target) * ((6*squared - 6*unit) / particle.duration) +
        initial * (3*squared - 4*unit + 1)
    return
}

// ui_dust_blend_tint approaches destination ink without changing captured alpha.
ui_dust_blend_tint :: proc(
    start, target: color.Color_RGBA8, blend: f32) -> color.Color_RGBA8 {
    return {
        u8(f32(start.r) + (f32(target.r)-f32(start.r))*blend),
        u8(f32(start.g) + (f32(target.g)-f32(start.g))*blend),
        u8(f32(start.b) + (f32(target.b)-f32(start.b))*blend),
        start.a,
    }
}

// ui_dust_reclaim_eligible excludes assigned, settled, invisible, or stale material.
// Matching policy is separate; this predicate only defines airborne eligibility.
ui_dust_reclaim_eligible :: proc(
    system: ^Ui_Dust_System, reference: Ui_Dust_Slot_Ref) -> bool {
    if !ui_dust_slot_valid(system, reference) || !system^.viewport_initialized {
        return false
    }
    index := reference.index
    position: geometry.Vector2 = {
        system^.particles.pos_x[index], system^.particles.pos_y[index],
    }
    viewport := system^.viewport
    return system^.particles.phase[index] == .Airborne_Departure &&
        ui_dust_particle_alpha(system, index) > 0 &&
        position.x >= viewport.x && position.x < viewport.x + viewport.width &&
        position.y >= viewport.y && position.y < viewport.y + viewport.height
}
