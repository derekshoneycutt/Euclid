package ui_dust

import geometry "../../core/geometry"
import testing "core:testing"

// Count one material phase without relying on physical slot density.
ui_dust_test_phase_count :: proc(system: ^Ui_Dust_System, phase: Ui_Dust_Phase) -> int {
    count := 0
    for value in system^.particles.phase[:system^.initialized_slots] {
        if value == phase {
            count += 1
        }
    }
    return count
}

// Stage a deterministic sampled line for one reclaim-capable formation.
ui_dust_test_reclaim_targets :: proc(system: ^Ui_Dust_System, count: int) {
    ui_dust_begin_arrival(system, 22, .Falling_Ink)
    for index in 0..<count {
        ui_dust_target_include(system, {f32(index % 100) + 10, 80},
            {80, 120, 160, 255}, 192)
    }
    ui_dust_form_targets(system)
}

// Verify fewer/equal/more target populations reclaim only demand and fill shortages.
@(test)
ui_dust_reclaim_population_rules :: proc(t: ^testing.T) {
    for targets in ([4]int{0, 3, 8, 12}) {
        system := ui_dust_test_system({0, 0, 200, 200})
        for index in 0..<8 {
            testing.expect(t, ui_dust_emit(system,
                {f32(index) + 10, 40}, {20, 40, 60, 255}, 255, 1))
        }
        ui_dust_test_reclaim_targets(system, targets)
        testing.expect_value(t, ui_dust_test_phase_count(system, .Reclaimed_Arrival),
            min(8, targets))
        testing.expect_value(t, ui_dust_test_phase_count(system, .Fresh_Arrival),
            max(0, targets - 8))
        testing.expect_value(t, system^.particle_count, max(0, 8 - targets))
        testing.expect_value(t, system^.live_count, max(8, targets))
        testing.expect_value(t, system^.formation_reclaimed, min(8, targets))
        testing.expect_value(t, system^.formation_fresh, max(0, targets - 8))
        ui_dust_test_slot_invariants(t, system)
        free(system, context.allocator)
    }
}

// Verify floor, invisible, and clipped dust never supplies targets; Independent opts out.
@(test)
ui_dust_reclaim_excludes_ineligible_material :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    floor := ui_dust_slot_emit(system, {
        phase = .Resting_Departure, pos_x = 50, pos_y = 199, life = 1,
        color = {20, 40, 60, 255},
    })
    testing.expect(t, ui_dust_emit(system, {40, 40}, {20, 40, 60, 255}, 255, 0))
    testing.expect(t, ui_dust_emit(system, {-10, 40}, {20, 40, 60, 255}, 255, 1))
    ui_dust_test_reclaim_targets(system, 3)
    testing.expect_value(t, ui_dust_test_phase_count(system, .Fresh_Arrival), 3)
    testing.expect_value(t, ui_dust_test_phase_count(system, .Reclaimed_Arrival), 0)
    testing.expect(t, ui_dust_slot_valid(system, floor))
    ui_dust_settle(system)
    ui_dust_validate_context(system, {visible = true, viewport = {0, 0, 200, 200}})
    system^.transition = .Independent
    testing.expect(t, ui_dust_emit(system, {40, 40}, {20, 40, 60, 255}, 255, 1))
    ui_dust_test_reclaim_targets(system, 3)
    testing.expect_value(t, ui_dust_test_phase_count(system, .Fresh_Arrival), 3)
    testing.expect_value(t, system^.particle_count, 1)
}

// Verify comparison arrivals keep replacement clearing instead of reclaim continuity.
@(test)
ui_dust_reclaim_comparison_styles_clear_replacements :: proc(t: ^testing.T) {
    for style in ([4]Ui_Dust_Arrival_Style{.Immediate, .Fade, .Draw_In, .Falling_Ink}) {
        system := ui_dust_test_system({0, 0, 200, 200})
        testing.expect(t, ui_dust_test_formation(system, 1, {80, 100}))
        ui_dust_advance(system, 0.12)
        ui_dust_begin_departure(system, 2, style)
        testing.expect_value(t, system^.live_count, int(style == .Falling_Ink))
        ui_dust_settle(system)
        ui_dust_validate_context(system, {visible = true, viewport = {0, 0, 200, 200}})
        testing.expect(t, ui_dust_emit(system, {40, 40}, {20, 40, 60, 255}, 255, 1))
        ui_dust_begin_arrival(system, 2, style)
        ui_dust_begin_departure(system, 3, .Falling_Ink)
        testing.expect_value(t, system^.live_count,
            int(style == .Falling_Ink || style == .Immediate))
        free(system, context.allocator)
    }
}

// Verify local matching is deterministic, has stable ties, and spans target rows.
@(test)
ui_dust_reclaim_locality_and_distributed_visitation :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    for position in ([3]geometry.Vector2{{10, 10}, {10, 10}, {180, 180}}) {
        testing.expect(t, ui_dust_emit(system, position, {20, 40, 60, 255}, 255, 1))
    }
    ui_dust_begin_arrival(system, 2, .Falling_Ink)
    for position in ([4]geometry.Vector2{{10, 10}, {11, 10}, {180, 180}, {181, 180}}) {
        ui_dust_target_include(system, position, {20, 40, 60, 255}, 255)
    }
    ui_dust_form_targets(system)
    testing.expect_value(t, system^.targets[0].claim.index, 0)
    testing.expect_value(t, system^.targets[2].claim.index, 2)
    testing.expect_value(t, system^.targets[1].claim.index, 1)
    testing.expect_value(t, system^.targets[3].claim.generation, u64(0))
    ui_dust_test_slot_invariants(t, system)
}

// Verify same-slot takeover keeps visible appearance, derivative, generation and age.
@(test)
ui_dust_reclaim_continuous_takeover_and_endpoint :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 400, 1200})
    defer free(system, context.allocator)
    testing.expect(t, ui_dust_emit(system, {60, 30}, {200, 80, 40, 255}, 192, 0.7))
    ui_dust_advance(system, 0.1)
    reference := Ui_Dust_Slot_Ref{0, system^.order[0].generation}
    before, _ := ui_dust_evaluate(system, reference)
    age := system^.particles.age[0]
    order := system^.order[0]
    ui_dust_begin_arrival(system, 2, .Falling_Ink)
    ui_dust_target_include(system, {80, 100}, {40, 80, 200, 255}, 255)
    ui_dust_form_targets(system)
    after, valid := ui_dust_evaluate(system, reference)
    testing.expect(t, valid)
    ui_dust_test_appearance_near(t, before, after)
    testing.expect_value(t, system^.particles.age[0], age)
    testing.expect_value(t, system^.order[0], order)
    testing.expect_value(t, system^.live_count, 1)
    system^.incoming_elapsed = system^.particles.duration[0]
    landed, _ := ui_dust_evaluate(system, reference)
    testing.expect_value(t, landed.position, geometry.Vector2{80, 100})
    testing.expect_value(t, landed.velocity, geometry.Vector2{})
    testing.expect_value(t, landed.tint.b, u8(200))
    system^.incoming_elapsed = 0
    ui_dust_advance(system, 0.30)
    testing.expect_value(t, system^.live_count, 0)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(1))
}

// Verify replacement releases actual forming material through delay, flight and handoff.
@(test)
ui_dust_reclaim_interruption_preserves_visible_history :: proc(t: ^testing.T) {
    for elapsed in ([4]f32{0, 0.06, 0.18, 0.27}) {
        system := ui_dust_test_system({0, 0, 400, 1200})
        testing.expect(t, ui_dust_test_formation(system, 1, {80, 100}))
        ui_dust_advance(system, elapsed)
        reference := Ui_Dust_Slot_Ref{0, system^.order[0].generation}
        before, _ := ui_dust_evaluate(system, reference)
        age := system^.particles.age[0]
        ui_dust_begin_departure(system, 2)
        if before.alpha <= 0 {
            testing.expect_value(t, system^.live_count, 0)
        } else {
            after, valid := ui_dust_evaluate(system, reference)
            testing.expect(t, valid)
            ui_dust_test_appearance_near(t, before, after)
            testing.expect_value(t, system^.particles.age[0], age)
            testing.expect_value(t, system^.particles.flight_elapsed[0], f32(0))
            testing.expect_value(t, system^.particles.target_x[0], f32(0))
            ui_dust_test_reclaim_targets(system, 1)
            testing.expect_value(t,
                system^.particles.phase[0], Ui_Dust_Phase.Reclaimed_Arrival)
            ui_dust_advance(system, 0.30)
            testing.expect_value(t, ui_dust_incoming_alpha(system), f32(1))
        }
        ui_dust_test_slot_invariants(t, system)
        free(system, context.allocator)
    }
}

// Verify repeated mid-flight claims preserve order while old surplus and floor fade age.
@(test)
ui_dust_reclaim_repeated_replacement_preserves_surplus :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 400, 1200})
    defer free(system, context.allocator)
    for x in ([2]f32{20, 300}) {
        testing.expect(t, ui_dust_emit(system, {x, 20}, {20, 40, 60, 255}, 255, 1))
    }
    ui_dust_advance(system, 0.1)
    ui_dust_test_reclaim_targets(system, 1)
    surplus := system^.particles[1]
    for _ in 0..<3 {
        ui_dust_advance(system, 0.02)
        before, _ := ui_dust_evaluate(system, {0, 1})
        ui_dust_begin_departure(system, 2)
        after, _ := ui_dust_evaluate(system, {0, 1})
        ui_dust_test_appearance_near(t, before, after)
        ui_dust_test_reclaim_targets(system, 1)
        testing.expect_value(t, system^.order[0].generation, u64(1))
        testing.expect_value(t, system^.particles.start_y[1], surplus.start_y)
    }
    ui_dust_advance(system, 0.2)
    testing.expect_value(t, system^.particles.phase[1], Ui_Dust_Phase.Resting_Departure)
    rest_age := system^.particles.rest_age[1]
    ui_dust_begin_departure(system, 3)
    testing.expect_value(t, system^.particles.rest_age[1], rest_age)
    testing.expect_value(t, system^.particles.flight_elapsed[1], f32(0.36))
}

// Fill a maximum-capacity matching case and retain bounded target demand.
ui_dust_test_fill_reclaim_capacity :: proc(system: ^Ui_Dust_System) {
    for index in 0..<UI_DUST_TOTAL_PARTICLES {
        _ = ui_dust_slot_emit(system, {
            phase = .Airborne_Departure,
            pos_x = f32(index % 128) + 10,
            pos_y = f32(index / 128) + 10,
            color = {20, 40, 60, 255}, life = 1,
        })
    }
    ui_dust_begin_arrival(system, 2, .Falling_Ink)
    for index in 0..<UI_DUST_MAX_ARRIVAL_PARTICLES {
        ui_dust_target_include(system, {f32(index % 128) + 10, f32(index / 128) + 10},
            {20, 40, 60, 255}, 255)
    }
}

// Verify full matching stays bounded and deterministic.
@(test)
ui_dust_reclaim_maximum_capacity :: proc(t: ^testing.T) {
    first := ui_dust_test_system({0, 0, 400, 400})
    second := ui_dust_test_system({0, 0, 400, 400})
    defer free(first, context.allocator)
    defer free(second, context.allocator)
    ui_dust_test_fill_reclaim_capacity(first)
    ui_dust_test_fill_reclaim_capacity(second)
    ui_dust_form_targets(first)
    ui_dust_form_targets(second)
    testing.expect_value(t, first^.live_count, UI_DUST_TOTAL_PARTICLES)
    testing.expect_value(t, first^.arrival_count, UI_DUST_MAX_ARRIVAL_PARTICLES)
    testing.expect_value(t, ui_dust_test_phase_count(first, .Fresh_Arrival), 0)
    for index in 0..<UI_DUST_MAX_ARRIVAL_PARTICLES {
        testing.expect_value(t, first^.targets[index].claim, second^.targets[index].claim)
    }
    ui_dust_test_slot_invariants(t, first)
}

// Verify claims finish before shortages can evict the oldest claimed material.
@(test)
ui_dust_reclaim_shortage_eviction_keeps_deadline :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 400, 400})
    defer free(system, context.allocator)
    oldest := ui_dust_slot_emit(system, {
        phase = .Airborne_Departure, pos_x = 20, pos_y = 20, color = {20, 40, 60, 255},
    })
    for _ in 1..<UI_DUST_TOTAL_PARTICLES {
        _ = ui_dust_slot_emit(system, {
            phase = .Resting_Departure, pos_x = 20, pos_y = 399,
            life = 1, color = {20, 40, 60, 255},
        })
    }
    ui_dust_test_reclaim_targets(system, 3)
    testing.expect(t, !ui_dust_slot_valid(system, oldest))
    testing.expect_value(t, ui_dust_test_phase_count(system, .Fresh_Arrival), 2)
    testing.expect_value(t, system^.arrival_count, 2)
    testing.expect_value(t, system^.live_count, UI_DUST_TOTAL_PARTICLES)
    testing.expect_value(t, system^.eviction_count, u64(2))
    ui_dust_test_slot_invariants(t, system)
    ui_dust_advance(system, 0.30)
    testing.expect_value(t, system^.arrival_count, 0)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(1))
    testing.expect_value(t, system^.arrival_completed_count, u64(1))
    testing.expect_value(t, system^.arrival_cancelled_count, u64(0))
    testing.expect_value(t, system^.arrival_completed_duration, f32(0.30))
}
