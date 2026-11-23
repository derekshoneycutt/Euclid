package bridge_events

import core "../../core"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"

// Increment the cycle-boundary generation and record its Julia-owner evidence.
notify_animation_cycle_boundary_local :: proc(state: ^core.Euclid_General_State) {
    if state == nil {
        return
    }

    state^.cycle_boundary_generation += 1
    animation_generation: u64 = 0
    if state^.julia_runtime_service != nil {
        animation_generation = state^.julia_runtime_service^.animation_generation
    }
    animation_tick_sequence: u64 = 0
    if state^.julia_runtime_service != nil {
        animation_tick_sequence = state^.julia_runtime_service^.animation_tick_sequence
    }
    record_julia_evidence(state, {
        lane = .Domain,
        kind = .Animation_Cycle_Boundary,
        correlation_kind = .Animation_Tick,
        correlation = animation_tick_sequence,
        generation = animation_generation,
        flags = {.Required},
    })
}

// Record one semantic event from the Julia owner without formatting or allocation.
record_julia_evidence :: proc(
    state: ^core.Euclid_General_State, event: evidence_trace.Event) {
    if state == nil || state.julia_runtime_service == nil {
        return
    }
    service := state.julia_runtime_service
    _ = evidence_session.session_record(
        service.evidence_session, &service.evidence_ring, event)
}
