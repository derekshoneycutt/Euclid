package bridge_scene

import bridge_events "../events"
import shapemodel "../../shapes/model"
import "../../core"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"

//   Record one scene-batch outcome using the current animation tick identity.
record_scene_batch_evidence :: proc(
    state: ^core.Euclid_General_State, kind: evidence_trace.Kind,
    failed: bool) {
    service := state^.julia_runtime_service
    flags: evidence_trace.Flags = {.Required}
    if failed {
        flags += {.Failure}
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Transport,
            kind = kind,
            correlation_kind = .Scene_Batch,
            correlation = service != nil ? service^.animation_tick_sequence : 0,
            generation = service != nil ? service^.animation_generation : 0,
            tick = state^.fixed_step,
            flags = flags,
        })
}

//   Select compact typed evidence for one committed scene command.
scene_command_evidence :: proc(
    command: ^Scene_Command) -> (evidence_trace.Kind, evidence_trace.Event_Payload) {
    evidence_kinds := SCENE_COMMAND_EVIDENCE_KINDS
    kind := evidence_kinds[command^.kind]
    payload: evidence_trace.Event_Payload
    #partial switch command^.kind {
    case .Emit_Trailing_Particle:
        payload.counts.first = 1
    case .Set_Shape_Orientation, .Set_Shape_Parabola, .Set_Shape_Parabola_Frontier,
        .Set_Shape_Hyperbola, .Set_Shape_Hyperbola_Frontier,
        .Set_Parabola_Tool_Geometry, .Set_Parabola_Tool_Parameter,
        .Set_Hyperbola_Tool_Geometry, .Set_Hyperbola_Tool_Parameter:
        entity := shapemodel.shape_entity_unpack(command^.entity)
        if entity.slot > 0 {
            payload.point.point_index = entity.slot - 1
        }
        payload.point.field = u16(command^.kind)
    case:
    }
    return kind, payload
}

// Record synchronous conic construction on the Julia owner's existing lifecycle ring.
record_conic_creation_evidence :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    service := state^.julia_runtime_service
    if service == nil {
        return
    }
    kind, payload := scene_command_evidence(command)
    bridge_events.record_julia_evidence(state, {
        lane = .Domain,
        kind = kind,
        generation = service^.animation_generation,
        payload = payload,
    })
}

//   Record one committed scene command using compact kind-specific payload fields.
record_scene_command_evidence :: proc(
    state: ^core.Euclid_General_State, command: ^Scene_Command) {
    kind, payload := scene_command_evidence(command)
    if kind == .Unknown {
        return
    }
    service := state^.julia_runtime_service
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Domain,
            kind = kind,
            correlation_kind = .Scene_Batch,
            correlation = service != nil ? service^.animation_tick_sequence : 0,
            generation = service != nil ? service^.animation_generation : 0,
            tick = state^.fixed_step,
            payload = payload,
        })
}
