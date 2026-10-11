package viewevidence

import shapemodel "../../shapes/model"
import core "../../core"
import evidence_checkpoint "../../evidence/checkpoint"
import evidence_session "../../evidence/session"
import evidence_trace "../../evidence/trace"

//   Record one post-join constraint summary for semantic trace consumers.
record_constraint_trace_summary :: proc(state: ^core.Euclid_General_State) {
    if state == nil || state^.shape_world == nil {
        return
    }
    active_constraints := 0
    for constraint in state^.shape_world^.constraints.values[
        :state^.shape_world^.constraints.count] {
        if constraint.enabled {
            active_constraints += 1
        }
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Domain,
            kind = .Constraint_Solve_Completed,
            correlation_kind = .Fixed_Step,
            correlation = state^.fixed_step,
            tick = state^.fixed_step,
            payload = {counts = {
                first = u32(active_constraints),
                second = u32(state^.shape_world^.constraints.count),
            }},
        })
}

//   Capture and record one bounded canonical checkpoint after worker join.
//
// Parameters:
//   - state: Display-owned state observed after synchronized simulation work.
//   - required: Whether later checkpoint eviction makes evidence incomplete.
record_evidence_checkpoint :: proc(
    state: ^core.Euclid_General_State,
    required: bool) -> evidence_checkpoint.Handle {
    if state == nil || state^.shape_world == nil ||
        state^.julia_runtime_service == nil {
        return {}
    }

    typed := capture_evidence_checkpoint(state)
    handle := evidence_checkpoint.store_put(
        &state^.evidence_checkpoints, typed, required)
    if state^.evidence_checkpoints.required_evidence_lost {
        evidence_session.session_mark_incomplete(&state^.evidence_session)
    }
    flags: evidence_trace.Flags
    if required {
        flags += {.Required}
    }
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Domain,
            kind = .Checkpoint_Stored,
            correlation_kind = .Checkpoint,
            correlation = state^.fixed_step,
            generation = u64(handle.generation),
            tick = state^.fixed_step,
            flags = flags,
            payload = {handle = {
                slot = handle.slot,
                generation = handle.generation,
            }},
        })
    return handle
}

//   Project one dense world transform and its optional rendering state.
capture_evidence_point :: proc(
    world: ^shapemodel.Shape_World,
    transform_index: int,
    captured: ^evidence_checkpoint.Point) {
    entity := world^.transforms.entities[transform_index]
    transform := &world^.transforms.values[transform_index]
    captured^.index = i32(entity.slot) - 1
    captured^.x = transform.position.x
    captured^.y = transform.position.y
    captured^.z = transform.position.z
    captured^.has_position = true
    if style, found := shapemodel.shape_component_get(
        &world^.render_styles, &world^.registry, entity); found {
        captured^.visible = style^.visible
        captured^.brush_size = style^.brush_size
    }
    if feature, found := shapemodel.shape_component_get(
        &world^.active_features, &world^.registry, entity); found {
        captured^.active_child = i32(feature^.index)
    }
}

//   Copy authoritative post-join Euclid state into one fixed checkpoint value.
capture_evidence_checkpoint :: proc(
    state: ^core.Euclid_General_State) -> evidence_checkpoint.Snapshot {
    world := state^.shape_world
    snapshot := evidence_checkpoint.Snapshot{
        fixed_step = state^.fixed_step,
        simulation_time = state^.simulation_time,
        runtime_generation = state^.julia_runtime_service^.runtime_generation,
        animation_generation = state^.julia_runtime_service^.animation_generation,
        animation_tick_sequence = state^.julia_runtime_service^.animation_tick_sequence,
        point_count = min(
            int(world^.transforms.count),
            evidence_checkpoint.CHECKPOINT_POINT_CAPACITY),
        constraint_count = int(world^.constraints.count),
    }
    for constraint in world^.constraints.values[:world^.constraints.count] {
        if constraint.enabled {
            snapshot.active_constraint_count += 1
        }
    }
    for transform_index in 0..<snapshot.point_count {
        capture_evidence_point(
            world, transform_index, &snapshot.points[transform_index])
    }
    return snapshot
}
