package ui_dust

import geometry "../../core/geometry"
import math "core:math"

// ui_dust_matching_bin clamps pane-space material into a fixed spatial cell.
ui_dust_matching_bin :: proc(
    system: ^Ui_Dust_System, point: geometry.Vector2) -> int {
    viewport := system^.viewport
    x := clamp(int((point.x - viewport.x) * UI_DUST_MATCH_GRID /
        max(viewport.width, 1)), 0, UI_DUST_MATCH_GRID - 1)
    y := clamp(int((point.y - viewport.y) * UI_DUST_MATCH_GRID /
        max(viewport.height, 1)), 0, UI_DUST_MATCH_GRID - 1)
    return y * UI_DUST_MATCH_GRID + x
}

// ui_dust_matching_build indexes only visible airborne material in emission order.
ui_dust_matching_build :: proc(system: ^Ui_Dust_System) {
    system^.match_bins = {}
    system^.match_head = 0
    cursor := system^.live_tail
    for cursor != 0 {
        index := cursor - 1
        cursor = system^.order[index].previous
        if !ui_dust_reclaim_eligible(system, {index, system^.order[index].generation}) {
            continue
        }
        bin := ui_dust_matching_bin(system,
            {system^.particles.pos_x[index], system^.particles.pos_y[index]})
        next := system^.match_bins[bin]
        newer := system^.match_head
        system^.match_links[index] = {
            next = next,
            newer = newer,
            bin = bin,
        }
        if next != 0 {
            system^.match_links[next - 1].previous = index + 1
        }
        if newer != 0 {
            system^.match_links[newer - 1].older = index + 1
        }
        system^.match_bins[bin] = index + 1
        system^.match_head = index + 1
    }
}

// ui_dust_matching_remove consumes a source from both search chains exactly once.
ui_dust_matching_remove :: proc(system: ^Ui_Dust_System, index: int) {
    link := system^.match_links[index]
    if link.previous != 0 {
        system^.match_links[link.previous - 1].next = link.next
    } else {
        system^.match_bins[link.bin] = link.next
    }
    if link.next != 0 {
        system^.match_links[link.next - 1].previous = link.previous
    }
    if link.older != 0 {
        system^.match_links[link.older - 1].newer = link.newer
    } else {
        system^.match_head = link.newer
    }
    if link.newer != 0 {
        system^.match_links[link.newer - 1].older = link.older
    }
    system^.match_links[index] = {}
}

// ui_dust_matching_cell considers a bounded prefix with stable physical-slot ties.
ui_dust_matching_cell :: proc(
    system: ^Ui_Dust_System, bin: int, target: geometry.Vector2,
    search: ^Ui_Dust_Match_Search) {
    cursor := system^.match_bins[bin]
    for cursor != 0 && search^.tested < UI_DUST_MATCH_CANDIDATES {
        index := cursor - 1
        cursor = system^.match_links[index].next
        search^.tested += 1
        dx := system^.particles.pos_x[index] - target.x
        dy := system^.particles.pos_y[index] - target.y
        squared := dx * dx + dy * dy
        if squared < search^.distance ||
            (squared == search^.distance && index < search^.best) {
            search^.best = index
            search^.distance = squared
        }
    }
}

// ui_dust_matching_find expands two local rings before an oldest-source fallback.
// At most 25 cells and 64 candidates are visited per target, even at full capacity.
ui_dust_matching_find :: proc(
    system: ^Ui_Dust_System, target: geometry.Vector2) -> int {
    cell := ui_dust_matching_bin(system, target)
    x, y := cell % UI_DUST_MATCH_GRID, cell / UI_DUST_MATCH_GRID
    search: Ui_Dust_Match_Search = {
        best = -1,
        distance = math.F32_MAX,
    }
    for radius in 0..=2 {
        for row in max(0, y-radius)..=min(UI_DUST_MATCH_GRID-1, y+radius) {
            for column in max(0, x-radius)..=min(UI_DUST_MATCH_GRID-1, x+radius) {
                if max(abs(column-x), abs(row-y)) != radius {
                    continue
                }
                ui_dust_matching_cell(system, row * UI_DUST_MATCH_GRID + column,
                    target, &search)
            }
        }
        if search.best >= 0 {
            return search.best
        }
    }
    return system^.match_head - 1
}

// ui_dust_target_include retains a destination before any fresh allocation can evict sources.
ui_dust_target_include :: proc(
    system: ^Ui_Dust_System, position: geometry.Vector2, ink: [4]u8,
    coverage: u8, style: Ui_Dust_Ink = {}) {
    assert(system^.target_count < UI_DUST_MAX_ARRIVAL_PARTICLES)
    system^.targets[system^.target_count] = {
        position = position,
        ink = ink,
        coverage = coverage,
        style = style,
    }
    system^.target_count += 1
}

// ui_dust_target_visit reverses binary digits to distribute claims across document rows.
ui_dust_target_visit :: proc(ordinal, span: int) -> int {
    result, value, bits := 0, ordinal, span
    for bits > 1 {
        result = 2 * result + value % 2
        value /= 2
        bits /= 2
    }
    return result
}

// ui_dust_form_targets completes every claim before emitting only unmet targets.
// Claims preserve slot generations and original emission order; eviction still wins.
ui_dust_form_targets :: proc(system: ^Ui_Dust_System) {
    system^.formation_reclaimed = 0
    system^.formation_fresh = 0
    ui_dust_begin_formation(system)
    if ui_dust_arrival_budget(system) == 0 {
        system^.target_count = 0
        return
    }
    reclaim := system^.transition == .Reclaim && system^.incoming_style == .Falling_Ink
    if reclaim {
        ui_dust_matching_build(system)
        span := 1
        for span < system^.target_count {
            span *= 2
        }
        for ordinal in 0..<span {
            target := ui_dust_target_visit(ordinal, span)
            if target < system^.target_count {
                ui_dust_claim_target(system, target)
            }
        }
    }
    for target in system^.targets[:system^.target_count] {
        if target.claim.generation == 0 {
            emitted := ui_dust_emit_arrival(
                system, target.position, target.ink, target.coverage)
            assert(emitted)
            system^.particles.ink_style[system^.live_tail-1] = target.style
            system^.formation_fresh += 1
        }
    }
    system^.target_count = 0
}

// ui_dust_claim_target transfers the actual visible source without emitting a duplicate.
ui_dust_claim_target :: proc(system: ^Ui_Dust_System, target_index: int) {
    target := &system^.targets[target_index]
    index := ui_dust_matching_find(system, target^.position)
    if index < 0 {
        return
    }
    reference: Ui_Dust_Slot_Ref = {index, system^.order[index].generation}
    appearance, valid := ui_dust_evaluate(system, reference)
    assert(valid)
    ui_dust_matching_remove(system, index)
    reassigned := ui_dust_slot_reassign(system, reference, .Reclaimed_Arrival)
    assert(reassigned)
    particle := system^.particles[index]
    ui_dust_capture_appearance(&particle, appearance)
    particle.target_x = target^.position.x
    particle.target_y = target^.position.y
    particle.target_color = {target^.ink[0], target^.ink[1], target^.ink[2],
        u8(u32(target^.ink[3]) * u32(target^.coverage) / 255)}
    particle.target_ink_style = target^.style
    particle.target_size = UI_DUST_SIZE_MIN +
        f32(target^.coverage) / 255 * UI_DUST_SIZE_COVERAGE_SCALE
    distance := math.sqrt(
        (appearance.position.x - target^.position.x) *
            (appearance.position.x - target^.position.x) +
        (appearance.position.y - target^.position.y) *
            (appearance.position.y - target^.position.y))
    speed := math.sqrt(appearance.velocity.x * appearance.velocity.x +
        appearance.velocity.y * appearance.velocity.y)
    particle.duration = clamp((distance + 8) / max(speed, 400),
        UI_DUST_RECLAIM_MIN_DURATION, UI_DUST_ARRIVAL_HANDOFF_START)
    particle.delay = 0
    system^.particles[index] = particle
    system^.arrival_emitted += 1
    system^.formation_reclaimed += 1
    target^.claim = reference
}

// ui_dust_capture_appearance freezes exact visible material for its next trajectory.
ui_dust_capture_appearance :: proc(
    particle: ^Ui_Dust_Particle, appearance: Ui_Dust_Appearance) {
    particle^.pos_x = appearance.position.x
    particle^.pos_y = appearance.position.y
    particle^.start_x = appearance.position.x
    particle^.start_y = appearance.position.y
    particle^.vel_x = appearance.velocity.x
    particle^.vel_y = appearance.velocity.y
    particle^.start_velocity_x = appearance.velocity.x
    particle^.start_velocity_y = appearance.velocity.y
    particle^.color = appearance.tint
    particle^.ink_style = appearance.ink_style
    particle^.captured = true
    particle^.captured_alpha = appearance.alpha
    particle^.size = appearance.size
    particle^.dust_sprite_index = appearance.sprite_index
    particle^.flight_elapsed = 0
    particle^.rest_age = 0
    particle^.sway_amplitude = 0
}

// ui_dust_release_arrivals abandons destinations, not visible motion or emission age.
ui_dust_release_arrivals :: proc(system: ^Ui_Dust_System) {
    cursor := system^.live_head
    for cursor != 0 {
        index := cursor - 1
        cursor = system^.order[index].next
        if !ui_dust_phase_is_arrival(system^.particles.phase[index]) {
            continue
        }
        reference: Ui_Dust_Slot_Ref = {index, system^.order[index].generation}
        appearance, valid := ui_dust_evaluate(system, reference)
        assert(valid)
        if appearance.alpha <= 0 {
            retired := ui_dust_slot_retire(system, reference)
            assert(retired)
            continue
        }
        reassigned := ui_dust_slot_reassign(system, reference, .Airborne_Departure)
        assert(reassigned)
        particle := system^.particles[index]
        ui_dust_capture_appearance(&particle, appearance)
        particle.life = (UI_DUST_REST_LIFE_MIN + UI_DUST_REST_LIFE_MAX) / 2
        system^.particles[index] = particle
    }
}
