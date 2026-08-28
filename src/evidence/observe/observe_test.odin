#+test
package observe

import app_core "../../core"
import evidence_trace "../trace"

import "core:testing"

// Verify display observation copies authoritative Euclid scalars without mutation.
@(test)
observe_test_display_scalars :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)
    state^.particle_system = new(app_core.Particle_System)
    defer free(state^.particle_system)
    state^.julia_runtime_service = new(app_core.Julia_Runtime_Service)
    defer free(state^.julia_runtime_service)
    state^.fixed_step = 17
    state^.simulation_time = 2.5
    state^.ui_runtime.simulation_paused = true
    state^.evidence_session.required_evidence_complete = true
    state^.point_system^.next_point_index = 4
    state^.point_system^.next_constraint_index = 3
    state^.particle_system^.next_index = 12
    state^.julia_runtime_service^.runtime_generation = 2
    state^.julia_runtime_service^.animation_tick_sequence = 9
    evidence_trace.ring_init(&state^.evidence_ring, .Display)

    result := display(state)

    testing.expect_value(t, result.fixed_step, u64(17))
    testing.expect_value(t, result.simulation_time, f32(2.5))
    testing.expect(t, result.simulation_paused)
    testing.expect_value(t, result.point_count, 4)
    testing.expect_value(t, result.constraint_count, 3)
    testing.expect_value(t, result.particle_count, 12)
    testing.expect_value(t, result.runtime_generation, u64(2))
    testing.expect_value(t, result.animation_tick_sequence, u64(9))
    testing.expect(t, result.required_evidence_complete)
    testing.expect_value(t, state^.fixed_step, u64(17))
}

// Verify Julia-host observation includes its independent producer evidence state.
@(test)
observe_test_julia_host_scalars :: proc(t: ^testing.T) {
    service := new(app_core.Julia_Runtime_Service)
    defer free(service)
    service^.runtime_generation = 5
    service^.failed_request_count = 2
    service^.animation_ticks_committed = 8
    evidence_trace.ring_init(&service^.evidence_ring, .Julia_Host)

    result := julia_host(service)

    testing.expect_value(t, result.runtime_generation, u64(5))
    testing.expect_value(t, result.failed_request_count, u64(2))
    testing.expect_value(t, result.animation_ticks_committed, u64(8))
    testing.expect_value(t, result.trace.producer, evidence_trace.Producer.Julia_Host)
    testing.expect(t, result.trace.evidence_complete)
}

// Verify simulation observations preserve each owner identity after a join.
@(test)
observe_test_simulation_owner_rings :: proc(t: ^testing.T) {
    executor: app_core.Simulation_Executor
    evidence_trace.ring_init(
        &executor.particle_task.evidence_ring, .Particle_Worker)
    evidence_trace.ring_init(
        &executor.constraint_task.evidence_ring, .Constraint_Worker)
    evidence_trace.ring_init(
        &executor.shape_cache_task.evidence_ring, .Shape_Cache_Worker)
    evidence_trace.ring_init(
        &executor.dynview_task.evidence_ring, .Dynview_Worker)

    result := simulation(&executor)

    testing.expect_value(t, result.particle.producer,
        evidence_trace.Producer.Particle_Worker)
    testing.expect_value(t, result.constraint.producer,
        evidence_trace.Producer.Constraint_Worker)
    testing.expect_value(t, result.shape_cache.producer,
        evidence_trace.Producer.Shape_Cache_Worker)
    testing.expect_value(t, result.dynview.producer,
        evidence_trace.Producer.Dynview_Worker)
}
