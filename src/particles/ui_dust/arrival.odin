package ui_dust

import geometry "../../core/geometry"
import math "core:math"
import rand "core:math/rand"

// ui_dust_begin_arrival starts one generation's arrival in the selected style.
// Falling ink and draw-in wait for targets from the first presented frame of the
// new content; the content stays masked until formation starts or the wait limit
// falls back to the fade. Immediate arrival only cancels any earlier arrival.
ui_dust_begin_arrival :: proc(
    system: ^Ui_Dust_System, generation: u64, style: Ui_Dust_Arrival_Style) {
    if system == nil {
        return
    }
    ui_dust_cancel_arrival(system)
    if style == .Immediate {
        return
    }
    system^.incoming_active = true
    system^.incoming_style = style
    system^.incoming_generation = generation
    system^.incoming_awaiting_targets = style == .Falling_Ink || style == .Draw_In
    if style == .Draw_In {
        ui_dust_reveal_reset(system)
    }
}

// ui_dust_cancel_arrival shows incoming content fully and keeps outgoing dust.
ui_dust_cancel_arrival :: proc(system: ^Ui_Dust_System) {
    if system == nil {
        return
    }
    if system^.incoming_active {
        system^.arrival_cancelled_count += 1
    }
    ui_dust_arrival_retire_slots(system)
    system^.incoming_active = false
    system^.incoming_style = .Immediate
    system^.incoming_awaiting_targets = false
    system^.incoming_wait = 0
    system^.incoming_elapsed = 0
    system^.incoming_generation = 0
    system^.arrival_emitted = 0
    system^.target_count = 0
    system^.reveal_row_count = 0
}

// ui_dust_arrival_awaiting_targets reports whether falling ink or draw-in still
// needs targets from the new content's first presented frame.
ui_dust_arrival_awaiting_targets :: proc(system: ^Ui_Dust_System) -> bool {
    return system != nil && system^.incoming_active &&
        system^.incoming_awaiting_targets
}

// ui_dust_arrival_use_fade degrades a waiting falling-ink or draw-in arrival to
// the fade. Used when the new content supplies no visible ink or targets never arrive.
ui_dust_arrival_use_fade :: proc(system: ^Ui_Dust_System) {
    if !ui_dust_arrival_awaiting_targets(system) {
        return
    }
    system^.incoming_style = .Fade
    system^.incoming_awaiting_targets = false
    system^.incoming_wait = 0
    system^.incoming_elapsed = 0
    ui_dust_arrival_retire_slots(system)
    system^.arrival_emitted = 0
    system^.reveal_row_count = 0
}

// ui_dust_begin_formation starts falling ink or draw-in once targets are available
// and reseeds the private arrival stream. Draw-in first builds its bands from the
// included samples and degrades to the fade without them. Callers then emit up to
// ui_dust_arrival_budget particles with ui_dust_emit_arrival.
ui_dust_begin_formation :: proc(system: ^Ui_Dust_System) {
    if !ui_dust_arrival_awaiting_targets(system) {
        return
    }
    if system^.incoming_style == .Draw_In && !ui_dust_reveal_build_rows(system) {
        ui_dust_arrival_use_fade(system)
        return
    }
    system^.incoming_awaiting_targets = false
    system^.incoming_wait = 0
    system^.incoming_elapsed = 0
    ui_dust_arrival_retire_slots(system)
    system^.arrival_emitted = 0
    rand.reset(UI_DUST_ARRIVAL_RANDOM_SEED ~ system^.incoming_generation,
        rand.xoshiro256_random_generator(&system^.arrival_rng_state))
}

// ui_dust_arrival_budget returns how many arrival particles the formed style uses.
// Draw-in keeps its ink-contact accents sparse.
ui_dust_arrival_budget :: proc(system: ^Ui_Dust_System) -> int {
    if system == nil || !system^.incoming_active || system^.incoming_awaiting_targets {
        return 0
    }
    #partial switch system^.incoming_style {
    case .Falling_Ink:
        return UI_DUST_MAX_ARRIVAL_PARTICLES
    case .Draw_In:
        return UI_DUST_DRAW_IN_ACCENT_MAX
    }
    return 0
}

// ui_dust_emit_arrival appends one particle for a fixed ink target: a falling
// particle for falling ink, or a deposition accent at the draw-in front's contact.
ui_dust_emit_arrival :: proc(
    system: ^Ui_Dust_System, target: geometry.Vector2, ink: [4]u8,
    coverage: u8) -> bool {
    if system == nil || system^.arrival_emitted >= ui_dust_arrival_budget(system) {
        return false
    }
    generator := rand.xoshiro256_random_generator(&system^.arrival_rng_state)
    coverage_unit := f32(coverage) / 255
    alpha := f32(ink[3]) / 255 * coverage_unit
    particle := ui_dust_arrival_motion(system, target, generator)
    particle.phase = .Fresh_Arrival
    particle.size = UI_DUST_SIZE_MIN + coverage_unit * UI_DUST_SIZE_COVERAGE_SCALE
    particle.sway_amplitude = rand.float32_range(
        UI_DUST_SWAY_AMPLITUDE_MIN, UI_DUST_SWAY_AMPLITUDE_MAX, generator)
    particle.sway_frequency = rand.float32_range(
        UI_DUST_SWAY_FREQUENCY_MIN, UI_DUST_SWAY_FREQUENCY_MAX, generator)
    particle.sway_phase = rand.float32_range(0, 2 * math.PI, generator)
    particle.color = {ink[0], ink[1], ink[2], u8(clamp(alpha * 255, 0, 255))}
    particle.dust_sprite_index = u8(rand.int32_range(
        0, UI_DUST_SPRITE_VARIANT_COUNT, generator))
    _ = ui_dust_slot_emit(system, particle)
    system^.arrival_emitted += 1
    return true
}

// ui_dust_arrival_motion draws one particle's style-specific approach. Draw-in
// accents settle briefly onto ink exactly when the reveal front reaches it.
ui_dust_arrival_motion :: proc(
    system: ^Ui_Dust_System, target: geometry.Vector2,
    generator: rand.Generator) -> Ui_Dust_Particle {
    if system^.incoming_style == .Draw_In {
        return {
            target_x = target.x,
            target_y = target.y,
            drop = rand.float32_range(UI_DUST_DRAW_IN_ACCENT_DROP_MIN,
                UI_DUST_DRAW_IN_ACCENT_DROP_MAX, generator),
            lateral = rand.float32_range(-UI_DUST_DRAW_IN_ACCENT_LATERAL_MAX,
                UI_DUST_DRAW_IN_ACCENT_LATERAL_MAX, generator),
            delay = ui_dust_reveal_contact_time(system, target),
            duration = UI_DUST_DRAW_IN_ACCENT_SETTLE,
        }
    }
    return {
        target_x = target.x,
        target_y = target.y,
        drop = rand.float32_range(
            UI_DUST_ARRIVAL_DROP_MIN, UI_DUST_ARRIVAL_DROP_MAX, generator),
        lateral = rand.float32_range(
            -UI_DUST_ARRIVAL_LATERAL_MAX, UI_DUST_ARRIVAL_LATERAL_MAX, generator),
        delay = rand.float32_range(0, UI_DUST_ARRIVAL_DELAY_MAX, generator),
        duration = rand.float32_range(
            UI_DUST_ARRIVAL_FALL_MIN, UI_DUST_ARRIVAL_FALL_MAX, generator),
    }
}

// ui_dust_arrival_duration returns the full length of one arrival style.
ui_dust_arrival_duration :: proc(style: Ui_Dust_Arrival_Style) -> f32 {
    switch style {
    case .Immediate:
        return 0
    case .Fade:
        return UI_DUST_FADE_DURATION
    case .Falling_Ink:
        return UI_DUST_ARRIVAL_HANDOFF_END
    case .Draw_In:
        return UI_DUST_DRAW_IN_DURATION + UI_DUST_DRAW_IN_ACCENT_LIFE
    }
    return 0
}

// ui_dust_arrival_advance ages the arrival, bounding the wait for falling targets.
ui_dust_arrival_advance :: proc(system: ^Ui_Dust_System, delta_seconds: f32) {
    if !system^.incoming_active {
        return
    }
    remaining := delta_seconds
    if system^.incoming_awaiting_targets {
        system^.incoming_wait += delta_seconds
        if system^.incoming_wait >=
            UI_DUST_ARRIVAL_TARGET_WAIT_LIMIT + UI_DUST_FADE_DURATION {
            ui_dust_arrival_finish(system, UI_DUST_FADE_DURATION)
            return
        }
        if system^.incoming_wait < UI_DUST_ARRIVAL_TARGET_WAIT_LIMIT {
            return
        }
        remaining = system^.incoming_wait - UI_DUST_ARRIVAL_TARGET_WAIT_LIMIT
        ui_dust_arrival_use_fade(system)
    }
    system^.incoming_elapsed += remaining
    if system^.incoming_elapsed >= ui_dust_arrival_duration(system^.incoming_style) {
        ui_dust_arrival_finish(system, ui_dust_arrival_duration(system^.incoming_style))
    }
}

// ui_dust_arrival_finish records the logical endpoint, excluding coarse-frame remainder.
ui_dust_arrival_finish :: proc(system: ^Ui_Dust_System, duration: f32) {
    system^.arrival_completed_count += 1
    system^.arrival_completed_duration = duration
    system^.incoming_active = false
    ui_dust_cancel_arrival(system)
}

// ui_dust_incoming_alpha returns the current opacity of newly published content.
// Falling ink keeps content hidden while particles descend, then cross-fades the
// exact drawing in as the landed particles fade out. Draw-in reveals content
// through its own row bands, so its global opacity is full once formed.
ui_dust_incoming_alpha :: proc(system: ^Ui_Dust_System) -> f32 {
    if system == nil || !system^.incoming_active {
        return 1
    }
    if system^.incoming_awaiting_targets {
        return 0
    }
    progress := system^.incoming_elapsed / UI_DUST_FADE_DURATION
    #partial switch system^.incoming_style {
    case .Falling_Ink:
        progress = (system^.incoming_elapsed - UI_DUST_ARRIVAL_HANDOFF_START) /
            (UI_DUST_ARRIVAL_HANDOFF_END - UI_DUST_ARRIVAL_HANDOFF_START)
    case .Draw_In:
        return 1
    }
    return ui_dust_smoothstep(progress)
}

// ui_dust_arrival_progress returns one arrival particle's descent progress in [0, 1].
ui_dust_arrival_progress :: proc(system: ^Ui_Dust_System, index: int) -> f32 {
    duration := system^.particles.duration[index]
    if duration <= 0 {
        return 1
    }
    return clamp(
        (system^.incoming_elapsed - system^.particles.delay[index]) / duration, 0, 1)
}

// ui_dust_arrival_position returns one arrival particle's pane-space center.
// The remaining offset eases out cubically, so the particle lands on its target.
ui_dust_arrival_position :: proc(
    system: ^Ui_Dust_System, index: int) -> geometry.Vector2 {
    if system == nil || index < 0 || index >= system^.initialized_slots ||
        !ui_dust_phase_is_arrival(system^.particles.phase[index]) {
        return {}
    }
    if system^.particles.phase[index] == .Reclaimed_Arrival {
        position, _ := ui_dust_reclaimed_motion(
            system^.particles[index], system^.incoming_elapsed)
        return position
    }
    remaining := 1 - ui_dust_arrival_progress(system, index)
    offset := remaining * remaining * remaining
    sway := system^.particles.sway_amplitude[index] * math.sin(
        system^.incoming_elapsed * system^.particles.sway_frequency[index] +
        system^.particles.sway_phase[index])
    return {
        system^.particles.target_x[index] +
            (system^.particles.lateral[index] + sway) * offset,
        system^.particles.target_y[index] - system^.particles.drop[index] * offset,
    }
}

// ui_dust_arrival_alpha returns one arrival particle's opacity in [0, 1].
// Falling particles appear after their delay and yield to the exact drawing during
// handoff; draw-in accents appear at contact and fade over their short life.
ui_dust_arrival_alpha :: proc(system: ^Ui_Dust_System, index: int) -> f32 {
    if system == nil || index < 0 || index >= system^.initialized_slots ||
        !ui_dust_phase_is_arrival(system^.particles.phase[index]) ||
        system^.incoming_elapsed < system^.particles.delay[index] {
        return 0
    }
    appear := ui_dust_smoothstep(
        ui_dust_arrival_progress(system, index) / UI_DUST_ARRIVAL_APPEAR_FRACTION)
    base_alpha := f32(system^.particles.color[index].a) / 255
    if system^.particles.phase[index] == .Reclaimed_Arrival {
        particle := system^.particles[index]
        blend := ui_dust_smoothstep(ui_dust_arrival_progress(system, index))
        alpha := particle.captured_alpha +
            (f32(particle.target_color.a)/255 - particle.captured_alpha) * blend
        return alpha * (1 - ui_dust_incoming_alpha(system))
    }
    if system^.incoming_style == .Draw_In {
        age := system^.incoming_elapsed - system^.particles.delay[index]
        return base_alpha * appear *
            (1 - ui_dust_smoothstep(age / UI_DUST_DRAW_IN_ACCENT_LIFE))
    }
    return base_alpha * appear * (1 - ui_dust_incoming_alpha(system))
}

// ui_dust_arrival_retire_slots releases targets without touching departure slots.
ui_dust_arrival_retire_slots :: proc(system: ^Ui_Dust_System) {
    cursor := system^.live_head
    for cursor != 0 {
        index := cursor - 1
        cursor = system^.order[index].next
        if ui_dust_phase_is_arrival(system^.particles.phase[index]) {
            retired := ui_dust_slot_retire(
                system, {index, system^.order[index].generation})
            assert(retired)
        }
    }
}

// ui_dust_smoothstep eases a clamped unit progress value.
ui_dust_smoothstep :: #force_inline proc(progress: f32) -> f32 {
    unit := clamp(progress, 0, 1)
    return unit * unit * (3 - 2 * unit)
}
