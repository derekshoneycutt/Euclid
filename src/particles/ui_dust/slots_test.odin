package ui_dust

import testing "core:testing"

// Verify every initialized slot belongs to exactly one live or free chain.
ui_dust_test_slot_invariants :: proc(t: ^testing.T, system: ^Ui_Dust_System) {
    seen: [UI_DUST_TOTAL_PARTICLES]bool
    previous, live, departures, arrivals := 0, 0, 0, 0
    cursor := system^.live_head
    for cursor != 0 && live < UI_DUST_TOTAL_PARTICLES {
        index := cursor - 1
        testing.expect(t, !seen[index])
        seen[index] = true
        testing.expect_value(t, system^.order[index].previous, previous)
        testing.expect(t, system^.order[index].generation != 0)
        phase := system^.particles.phase[index]
        testing.expect(t, phase != .Free)
        if ui_dust_phase_is_arrival(phase) {
            arrivals += 1
        } else {
            departures += 1
        }
        previous = cursor
        cursor = system^.order[index].next
        live += 1
    }
    testing.expect_value(t, cursor, 0)
    testing.expect_value(t, system^.live_tail, previous)
    testing.expect_value(t, system^.live_count, live)
    testing.expect_value(t, system^.particle_count, departures)
    testing.expect_value(t, system^.arrival_count, arrivals)
    free_count := ui_dust_test_free_chain(t, system, seen[:])
    testing.expect_value(t, live + free_count, system^.initialized_slots)
}

// Verify free holes do not alias live slots or retain an arrival target.
ui_dust_test_free_chain :: proc(
    t: ^testing.T, system: ^Ui_Dust_System, seen: []bool) -> int {
    free_count := 0
    cursor := system^.free_head
    for cursor != 0 && free_count < UI_DUST_TOTAL_PARTICLES {
        index := cursor - 1
        testing.expect(t, !seen[index])
        seen[index] = true
        testing.expect_value(t, system^.particles.phase[index], Ui_Dust_Phase.Free)
        testing.expect_value(t, system^.particles.target_x[index], f32(0))
        cursor = system^.order[index].next
        free_count += 1
    }
    testing.expect_value(t, cursor, 0)
    return free_count
}

// Verify repeated ring wrap evicts exactly the oldest live original emission.
@(test)
ui_dust_slots_wrap_in_emission_order :: proc(t: ^testing.T) {
    system := new(Ui_Dust_System, context.allocator)
    defer free(system, context.allocator)
    count := 3 * UI_DUST_TOTAL_PARTICLES + 17
    first: Ui_Dust_Slot_Ref
    for ordinal in 0..<count {
        reference := ui_dust_slot_emit(system, {
            phase = .Airborne_Departure,
            pos_x = f32(ordinal),
        })
        if ordinal == 0 {
            first = reference
        }
        testing.expect_value(t, reference.index, ordinal % UI_DUST_TOTAL_PARTICLES)
        testing.expect_value(t, reference.generation,
            u64(ordinal / UI_DUST_TOTAL_PARTICLES + 1))
        testing.expect_value(t, system^.live_count,
            min(ordinal + 1, UI_DUST_TOTAL_PARTICLES))
    }
    ordinal := count - UI_DUST_TOTAL_PARTICLES
    cursor := system^.live_head
    for cursor != 0 {
        testing.expect_value(t, system^.particles.pos_x[cursor - 1], f32(ordinal))
        ordinal += 1
        cursor = system^.order[cursor - 1].next
    }
    testing.expect_value(t, ordinal, count)
    testing.expect(t, !ui_dust_slot_valid(system, first))
    testing.expect(t, !ui_dust_slot_retire(system, first))
    testing.expect(t, !ui_dust_slot_reassign(system, first, .Reclaimed_Arrival))
    ui_dust_test_slot_invariants(t, system)
}

// Verify arbitrary retirement holes are reused before any occupied slot or growth.
@(test)
ui_dust_slots_reuse_holes_before_eviction :: proc(t: ^testing.T) {
    system := new(Ui_Dust_System, context.allocator)
    defer free(system, context.allocator)
    for _ in 0..<UI_DUST_TOTAL_PARTICLES {
        _ = ui_dust_slot_emit(system, {
            phase = .Airborne_Departure,
        })
    }
    oldest: Ui_Dust_Slot_Ref = {0, system^.order[0].generation}
    for index in ([3]int{7, 19, 3}) {
        reference: Ui_Dust_Slot_Ref = {index, system^.order[index].generation}
        testing.expect(t, ui_dust_slot_retire(system, reference))
        testing.expect(t, !ui_dust_slot_retire(system, reference))
        testing.expect(t, !ui_dust_slot_valid(system, reference))
    }
    ui_dust_test_slot_invariants(t, system)
    for index in ([3]int{3, 19, 7}) {
        reference := ui_dust_slot_emit(system, {
            phase = .Fresh_Arrival,
            target_x = 80,
        })
        testing.expect_value(t, reference.index, index)
        testing.expect_value(t, reference.generation, u64(2))
        testing.expect(t, ui_dust_slot_valid(system, oldest))
    }
    testing.expect_value(t, system^.initialized_slots, UI_DUST_TOTAL_PARTICLES)
    ui_dust_test_slot_invariants(t, system)
    replacement := ui_dust_slot_emit(system, {
        phase = .Resting_Departure,
    })
    testing.expect_value(t, replacement.index, oldest.index)
    testing.expect(t, !ui_dust_slot_valid(system, oldest))
}

// Verify phase transfer preserves age and eviction order while releasing targets.
@(test)
ui_dust_slots_reassignment_preserves_original_age :: proc(t: ^testing.T) {
    system := new(Ui_Dust_System, context.allocator)
    defer free(system, context.allocator)
    oldest := ui_dust_slot_emit(system, {
        phase = .Fresh_Arrival,
        target_x = 20,
        target_y = 30,
        duration = 0.4,
        age = 0.2,
        color = {1, 2, 3, 255},
    })
    for _ in 1..<UI_DUST_TOTAL_PARTICLES {
        _ = ui_dust_slot_emit(system, {
            phase = .Resting_Departure,
        })
    }
    original_order := system^.order[oldest.index]
    testing.expect(t, ui_dust_slot_reassign(system, oldest, .Airborne_Departure))
    testing.expect_value(t, system^.particles.target_x[oldest.index], f32(0))
    testing.expect_value(t, system^.particles.target_y[oldest.index], f32(0))
    testing.expect_value(t, system^.particles.duration[oldest.index], f32(0))
    testing.expect_value(t, system^.arrival_count, 0)
    testing.expect(t, ui_dust_slot_reassign(system, oldest, .Reclaimed_Arrival))
    testing.expect_value(t, system^.order[oldest.index], original_order)
    testing.expect_value(t, system^.particles.age[oldest.index], f32(0.2))
    testing.expect_value(t, system^.particles.color[oldest.index].a, u8(255))
    testing.expect_value(t, system^.arrival_count, 1)
    replacement := ui_dust_slot_emit(system, {
        phase = .Airborne_Departure,
    })
    testing.expect_value(t, replacement.index, oldest.index)
    testing.expect_value(t, system^.arrival_count, 0)
    testing.expect_value(t, system^.particles.target_x[replacement.index], f32(0))
    ui_dust_test_slot_invariants(t, system)
}

// Verify natural expiry creates stable holes and clearing never revives references.
@(test)
ui_dust_slots_expiry_and_clear_preserve_generations :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 100, 120})
    defer free(system, context.allocator)
    expired := ui_dust_slot_emit(system, {
        phase = .Resting_Departure,
        life = 0.1,
    })
    retained := ui_dust_slot_emit(system, {
        phase = .Resting_Departure,
        life = 1,
        pos_x = 50,
    })
    ui_dust_advance(system, 0.2)
    testing.expect(t, !ui_dust_slot_valid(system, expired))
    testing.expect(t, ui_dust_slot_valid(system, retained))
    reused := ui_dust_slot_emit(system, {
        phase = .Airborne_Departure,
    })
    testing.expect_value(t, reused.index, expired.index)
    testing.expect_value(t, system^.initialized_slots, 2)
    ui_dust_settle(system)
    testing.expect_value(t, system^.live_count, 0)
    ui_dust_test_slot_invariants(t, system)
    for _ in 0..<2 {
        _ = ui_dust_slot_emit(system, {
            phase = .Airborne_Departure,
        })
    }
    testing.expect(t, !ui_dust_slot_valid(system, retained))
    testing.expect(t, !ui_dust_slot_valid(system, reused))
    ui_dust_test_slot_invariants(t, system)
}

// Verify arrival eviction detaches targets but cannot extend the sampled-target cap.
@(test)
ui_dust_slots_arrival_eviction_keeps_handoff_bounded :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 5000, 100})
    defer free(system, context.allocator)
    testing.expect_value(t, ui_dust_test_emit_line(system, UI_DUST_TOTAL_PARTICLES),
        UI_DUST_TOTAL_PARTICLES)
    ui_dust_begin_arrival(system, 2, .Falling_Ink)
    ui_dust_begin_formation(system)
    for index in 0..<UI_DUST_MAX_ARRIVAL_PARTICLES {
        testing.expect(t, ui_dust_emit_arrival(
            system, {f32(index), 50}, {20, 40, 60, 255}, 255))
    }
    first: Ui_Dust_Slot_Ref = {0, system^.order[0].generation}
    testing.expect_value(t, system^.arrival_count, UI_DUST_MAX_ARRIVAL_PARTICLES)
    _ = ui_dust_test_emit_line(system, UI_DUST_MAX_ARRIVAL_PARTICLES + 1)
    testing.expect(t, !ui_dust_slot_valid(system, first))
    testing.expect_value(t, system^.particles.target_y[0], f32(0))
    testing.expect_value(t, system^.arrival_count, UI_DUST_MAX_ARRIVAL_PARTICLES - 1)
    testing.expect(t, !ui_dust_emit_arrival(system, {1, 1}, {1, 2, 3, 255}, 255))
    ui_dust_test_slot_invariants(t, system)
    ui_dust_advance(system, UI_DUST_ARRIVAL_HANDOFF_END)
    testing.expect(t, !system^.incoming_active)
    testing.expect_value(t, system^.arrival_count, 0)
    testing.expect_value(t, ui_dust_incoming_alpha(system), f32(1))
    ui_dust_test_slot_invariants(t, system)
}

// Verify arrival cancellation retires only its slots and clears every target field.
@(test)
ui_dust_slots_cancel_arrival_preserves_departure_holes :: proc(t: ^testing.T) {
    system := ui_dust_test_system({0, 0, 200, 200})
    defer free(system, context.allocator)
    departure := ui_dust_slot_emit(system, {
        phase = .Airborne_Departure,
        pos_x = 20,
        pos_y = 30,
    })
    testing.expect(t, ui_dust_test_formation(system, 7, {80, 90}))
    arrival: Ui_Dust_Slot_Ref = {1, system^.order[1].generation}
    testing.expect(t, ui_dust_slot_reassign(system, arrival, .Reclaimed_Arrival))
    ui_dust_advance(system, 0.01)
    testing.expect_value(t, system^.particles.age[arrival.index], f32(0.01))
    ui_dust_cancel_arrival(system)
    testing.expect(t, ui_dust_slot_valid(system, departure))
    testing.expect(t, !ui_dust_slot_valid(system, arrival))
    testing.expect_value(t, system^.live_count, 1)
    testing.expect_value(t, system^.arrival_count, 0)
    testing.expect_value(t, system^.particles[arrival.index], Ui_Dust_Particle{})
    replacement := ui_dust_slot_emit(system, {
        phase = .Resting_Departure,
    })
    testing.expect_value(t, replacement.index, arrival.index)
    testing.expect(t, !ui_dust_slot_retire(system, arrival))
    ui_dust_test_slot_invariants(t, system)
}
