package ui_dust

// ui_dust_phase_is_arrival identifies slots owning a formation target.
ui_dust_phase_is_arrival :: #force_inline proc(phase: Ui_Dust_Phase) -> bool {
    return phase == .Fresh_Arrival || phase == .Reclaimed_Arrival
}

// ui_dust_slot_valid checks a borrowed slot without admitting retired generations.
ui_dust_slot_valid :: proc(
    system: ^Ui_Dust_System, reference: Ui_Dust_Slot_Ref) -> bool {
    return system != nil && reference.index >= 0 &&
        reference.index < system^.initialized_slots && reference.generation != 0 &&
        system^.order[reference.index].generation == reference.generation &&
        system^.particles.phase[reference.index] != .Free
}

// ui_dust_slot_count adjusts phase totals without changing emission order.
ui_dust_slot_count :: proc(
    system: ^Ui_Dust_System, phase: Ui_Dust_Phase, delta: int) {
    if ui_dust_phase_is_arrival(phase) {
        system^.arrival_count += delta
    } else if phase != .Free {
        system^.particle_count += delta
    }
}

// ui_dust_slot_retire detaches one live emission, clears its target, and frees it.
// Stale references cannot retire a later occupant of the same physical slot.
ui_dust_slot_retire :: proc(
    system: ^Ui_Dust_System, reference: Ui_Dust_Slot_Ref) -> bool {
    if !ui_dust_slot_valid(system, reference) {
        return false
    }
    index := reference.index
    order := &system^.order[index]
    if order^.previous != 0 {
        system^.order[order^.previous - 1].next = order^.next
    } else {
        system^.live_head = order^.next
    }
    if order^.next != 0 {
        system^.order[order^.next - 1].previous = order^.previous
    } else {
        system^.live_tail = order^.previous
    }
    ui_dust_slot_count(system, system^.particles.phase[index], -1)
    system^.particles[index] = {}
    order^.previous = 0
    order^.next = system^.free_head
    system^.free_head = index + 1
    system^.live_count -= 1
    return true
}

// ui_dust_slot_emit reuses a free slot or evicts the oldest original emission.
// A zeroed system is ready to use; no heap storage or population compaction occurs.
ui_dust_slot_emit :: proc(
    system: ^Ui_Dust_System, particle: Ui_Dust_Particle) -> Ui_Dust_Slot_Ref {
    assert(system != nil && particle.phase != .Free)
    if system^.free_head == 0 &&
        system^.initialized_slots == UI_DUST_TOTAL_PARTICLES {
        index := system^.live_head - 1
        retired := ui_dust_slot_retire(
            system, {index, system^.order[index].generation})
        assert(retired)
        system^.eviction_count += 1
    }
    index := system^.initialized_slots
    if system^.free_head != 0 {
        index = system^.free_head - 1
        system^.free_head = system^.order[index].next
    } else {
        system^.initialized_slots += 1
    }
    order := &system^.order[index]
    order^.generation += 1
    assert(order^.generation != 0)
    order^.previous = system^.live_tail
    order^.next = 0
    if system^.live_tail != 0 {
        system^.order[system^.live_tail - 1].next = index + 1
    } else {
        system^.live_head = index + 1
    }
    system^.live_tail = index + 1
    system^.particles[index] = particle
    system^.live_count += 1
    ui_dust_slot_count(system, particle.phase, 1)
    return {index, order^.generation}
}

// ui_dust_slot_reassign changes ownership without rejuvenating the emission.
// Leaving formation detaches its target; physical motion is the caller's policy.
ui_dust_slot_reassign :: proc(
    system: ^Ui_Dust_System, reference: Ui_Dust_Slot_Ref,
    phase: Ui_Dust_Phase) -> bool {
    assert(phase != .Free)
    if !ui_dust_slot_valid(system, reference) {
        return false
    }
    index := reference.index
    previous := system^.particles.phase[index]
    if ui_dust_phase_is_arrival(previous) && !ui_dust_phase_is_arrival(phase) {
        system^.particles.target_x[index] = 0
        system^.particles.target_y[index] = 0
        system^.particles.drop[index] = 0
        system^.particles.lateral[index] = 0
        system^.particles.delay[index] = 0
        system^.particles.duration[index] = 0
        system^.particles.target_color[index] = {}
        system^.particles.target_size[index] = 0
    }
    ui_dust_slot_count(system, previous, -1)
    system^.particles.phase[index] = phase
    ui_dust_slot_count(system, phase, 1)
    return true
}

// ui_dust_slots_clear retires all material without resetting slot generations.
ui_dust_slots_clear :: proc(system: ^Ui_Dust_System) {
    for system^.live_head != 0 {
        index := system^.live_head - 1
        retired := ui_dust_slot_retire(
            system, {index, system^.order[index].generation})
        assert(retired)
    }
}
