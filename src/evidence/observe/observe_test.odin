#+test
package observe

import app_core "../../core"
import evidence_trace "../trace"

import "core:testing"

// Seed authoritative display scalars used by the observation contract test.
observe_test_seed_display_scalars :: proc(state: ^app_core.Euclid_General_State) {
    state^.fixed_step = 17
    state^.simulation_time = 2.5
    state^.ui_runtime.simulation_paused = true
    state^.ui_runtime.view_text_scroll_y = 90.5
    state^.ui_runtime.view_text_scroll_max = 120
    state^.ui_runtime.vertical_split_x = 640
    state^.ui_runtime.horizontal_split_y = 360
    state^.evidence_session.required_evidence_complete = true
    state^.shape_world^.transforms.count = 4
    state^.shape_world^.constraints.count = 3
    state^.particle_system^.next_index = 12
    state^.julia_runtime_service^.runtime_generation = 2
    state^.julia_runtime_service^.animation_tick_sequence = 9
}

// Assert one observation contains every seeded display scalar.
observe_test_expect_display_scalars :: proc(
    t: ^testing.T, result: Display, state: ^app_core.Euclid_General_State) {
    testing.expect_value(t, result.fixed_step, u64(17))
    testing.expect_value(t, result.simulation_time, f32(2.5))
    testing.expect(t, result.simulation_paused)
    testing.expect_value(t, result.view_text_scroll_y, f32(90.5))
    testing.expect_value(t, result.view_text_scroll_max, f32(120))
    testing.expect_value(t, result.vertical_split_x, f32(640))
    testing.expect_value(t, result.horizontal_split_y, f32(360))
    testing.expect_value(t, result.point_count, 4)
    testing.expect_value(t, result.constraint_count, 3)
    testing.expect_value(t, result.particle_count, 12)
    testing.expect_value(t, result.runtime_generation, u64(2))
    testing.expect_value(t, result.animation_tick_sequence, u64(9))
    testing.expect(t, result.required_evidence_complete)
    testing.expect_value(t, state^.fixed_step, u64(17))
}

// Verify display observation copies authoritative Euclid scalars without mutation.
@(test)
observe_test_display_scalars :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State, context.allocator)
    defer free(state)
    state^.shape_world = new(app_core.Shape_World, context.allocator)
    defer free(state^.shape_world)
    state^.particle_system = new(app_core.Particle_System, context.allocator)
    defer free(state^.particle_system)
    state^.julia_runtime_service = new(app_core.Julia_Runtime_Service, context.allocator)
    defer free(state^.julia_runtime_service)
    observe_test_seed_display_scalars(state)
    evidence_trace.ring_init(&state^.evidence_ring, .Display)

    result := display(state)
    observe_test_expect_display_scalars(t, result, state)
}

// Verify Julia-host observation includes its independent producer evidence state.
@(test)
observe_test_julia_host_scalars :: proc(t: ^testing.T) {
    service := new(app_core.Julia_Runtime_Service, context.allocator)
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
