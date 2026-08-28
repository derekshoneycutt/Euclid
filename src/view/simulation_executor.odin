package view

import "../core"
import "../dynview"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import "../particles"
import "../shapes"
import "../taskpool"
import "./ui"

Simulation_Task_Data :: core.Simulation_Task_Data
Frame_Preparation_Task_Data :: core.Frame_Preparation_Task_Data
Simulation_Executor :: core.Simulation_Executor

//   Create and start the persistent fixed-step worker pool.
create_simulation_executor :: proc(
    state: ^Euclid_General_State) -> ^Simulation_Executor {

    executor := new(Simulation_Executor)
    executor^.particle_task.state = state
    executor^.constraint_task.state = state
    executor^.shape_cache_task.state = state
    executor^.dynview_task.state = state
    evidence_trace.ring_init(
        &executor^.particle_task.evidence_ring, .Particle_Worker)
    evidence_trace.ring_init(
        &executor^.constraint_task.evidence_ring, .Constraint_Worker)
    evidence_trace.ring_init(
        &executor^.shape_cache_task.evidence_ring, .Shape_Cache_Worker)
    evidence_trace.ring_init(
        &executor^.dynview_task.evidence_ring, .Dynview_Worker)
    if !taskpool.task_pool_init(&executor^.pool) {
        free(executor)
        return nil
    }
    return executor
}

//   Finish queued simulation work and release persistent worker resources.
destroy_simulation_executor :: proc(executor: ^Simulation_Executor) {
    if executor == nil {
        return
    }
    taskpool.task_pool_destroy(&executor^.pool)
    free(executor)
}

//   Run one particle-system fixed step on a simulation worker.
update_particles_task :: proc(payload: rawptr) -> taskpool.Task_Result {
    data := cast(^Simulation_Task_Data)payload
    particles.update_particles(data^.state^.particle_system, data^.dt)
    _ = evidence_session.session_record(
        &data^.state^.evidence_session, &data^.evidence_ring, {
            lane = .Domain,
            kind = .Particle_Emission_Committed,
            correlation_kind = .Fixed_Step,
            correlation = data^.state^.fixed_step + 1,
            tick = data^.state^.fixed_step + 1,
            payload = {counts = {
                first = u32(max(data^.state^.particle_system^.next_index, 0)),
            }},
        })
    return .Succeeded
}

//   Solve point-system constraints on a simulation worker.
solve_constraints_task :: proc(payload: rawptr) -> taskpool.Task_Result {
    data := cast(^Simulation_Task_Data)payload
    shapes.apply_all_constraints_to_error(
        data^.state^.point_system, ALLOWED_CONSTRAINT_ERROR)
    _ = evidence_session.session_record(
        &data^.state^.evidence_session, &data^.evidence_ring, {
            lane = .Domain,
            kind = .Constraint_Solve_Completed,
            correlation_kind = .Fixed_Step,
            correlation = data^.state^.fixed_step + 1,
            tick = data^.state^.fixed_step + 1,
            flags = {.Required},
            payload = {counts = {
                first = u32(max(
                    data^.state^.point_system^.next_constraint_index, 0)),
            }},
        })
    return .Succeeded
}

//   Build interpolated shape draw data on a frame-preparation worker.
build_shape_cache_task :: proc(payload: rawptr) -> taskpool.Task_Result {
    data := cast(^Frame_Preparation_Task_Data)payload
    shapes.build_draw_cache(data^.state^.point_system, data^.interpolation_alpha)
    _ = evidence_session.session_record(
        &data^.state^.evidence_session, &data^.evidence_ring, {
            lane = .Presentation,
            kind = .Shape_Cache_Prepared,
            correlation_kind = .Fixed_Step,
            correlation = data^.state^.fixed_step,
            tick = data^.state^.fixed_step,
            payload = {counts = {
                first = u32(max(
                    data^.state^.point_system^.draw_cache.item_count, 0)),
            }},
        })
    return .Succeeded
}

//   Compile invalidated Dynview text and layout caches on a frame-preparation worker.
compile_dynview_task :: proc(payload: rawptr) -> taskpool.Task_Result {
    data := cast(^Frame_Preparation_Task_Data)payload
    dynview.compile_if_needed(&data^.state^.dynview)
    _ = evidence_session.session_record(
        &data^.state^.evidence_session, &data^.evidence_ring, {
            lane = .Presentation,
            kind = .Dynview_Compiled,
            correlation_kind = .Fixed_Step,
            correlation = data^.state^.fixed_step,
            tick = data^.state^.fixed_step,
        })
    return .Succeeded
}

//   Submit one task into a deterministic batch and require bounded admission.
submit_simulation_task :: proc(
    executor: ^Simulation_Executor, fence: ^taskpool.Task_Fence,
    procedure: taskpool.Task_Procedure, payload: rawptr) {

    outcome := taskpool.task_fence_submit(
        &executor^.pool, fence, procedure, payload)
    assert(outcome == .Queued)
}

//   Submit independent fixed-step systems and wait for the complete batch.
run_parallel_simulation_step :: proc(executor: ^Simulation_Executor, dt: f32) {
    assert(executor != nil)
    executor^.particle_task.dt = dt
    executor^.constraint_task.dt = dt
    fence, initialized := taskpool.task_fence_begin(&executor^.pool)
    assert(initialized)
    submit_simulation_task(executor, &fence, update_particles_task,
        rawptr(&executor^.particle_task))
    submit_simulation_task(executor, &fence, solve_constraints_task,
        rawptr(&executor^.constraint_task))
    assert(taskpool.task_fence_wait(&executor^.pool, &fence) == .Succeeded)
    evidence_session.session_accept_ring(
        &executor^.particle_task.state^.evidence_session,
        &executor^.particle_task.evidence_ring)
    evidence_session.session_accept_ring(
        &executor^.constraint_task.state^.evidence_session,
        &executor^.constraint_task.evidence_ring)
}

//   Prepare frame-owned shape and text caches concurrently before rendering.
run_parallel_frame_preparation :: proc(state: ^core.Euclid_General_State, alpha: f32) {
    assert(state != nil && state^.simulation_executor != nil)
    executor := state^.simulation_executor
    executor^.shape_cache_task.interpolation_alpha = alpha
    fence, initialized := taskpool.task_fence_begin(&executor^.pool)
    assert(initialized)
    submit_simulation_task(executor, &fence, build_shape_cache_task,
        rawptr(&executor^.shape_cache_task))
    if ui.prepare_ui_frame(state) {
        submit_simulation_task(executor, &fence, compile_dynview_task,
            rawptr(&executor^.dynview_task))
    }
    assert(taskpool.task_fence_wait(&executor^.pool, &fence) == .Succeeded)
    evidence_session.session_accept_ring(
        &state^.evidence_session, &executor^.shape_cache_task.evidence_ring)
    evidence_session.session_accept_ring(
        &state^.evidence_session, &executor^.dynview_task.evidence_ring)
}