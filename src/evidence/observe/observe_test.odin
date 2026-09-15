#+test
package observe

import bridgemodel "../../bridge/model"

import dynviewmodel "../../dynview/model"
import evidence_trace "../trace"
import particlemodel "../../particles/model"
import shapemodel "../../shapes/model"
import viewmodel "../../view/model"
import viewterminalmodel "../../view/terminal/model"

import "core:testing"

// Seed authoritative display scalars used by the observation contract test.
observe_test_seed_display_scalars :: proc(source: ^Display_Source) {
    source^.fixed_step = 17
    source^.simulation_time = 2.5
    source^.ui_runtime^.simulation_paused = true
    source^.ui_runtime^.view_text_scroll_y = 90.5
    source^.ui_runtime^.view_text_scroll_max = 120
    source^.ui_runtime^.vertical_split_x = 640
    source^.ui_runtime^.horizontal_split_y = 360
    source^.required_evidence_complete = true
    source^.shape_world^.transforms.count = 4
    source^.shape_world^.constraints.count = 3
    source^.particle_system^.next_index = 12
    source^.particle_system^.use_max_dust_particles = 3
    source^.particle_system^.low_particles[0].alive = true
    source^.particle_system^.low_particles[1].alive = true
    source^.particle_system^.low_particles[2].alive = true
    source^.particle_system^.low_particles.pos_z[2] = 0.25
    source^.particle_system^.dust_grounded_count = 2
    source^.particle_system^.dust_peak_speed_sq = 0.03125
    source^.particle_system^.dust_kinetic_measure = 0.0625
    source^.particle_system^.dust_field.previous_solve_bounds = {
        min_x = 2, min_y = 3, max_x = 5, max_y = 7, valid = true}
    source^.particle_system^.dust_tool_contact_overflow_count = 1
    source^.particle_system^.dust_tool_contact_coalesced_count = 4
    source^.particle_system^.dust_tool_contact_sample_count = 5
    source^.particle_system^.dust_tool_contact_field_node_visit_count = 6
    source^.particle_system^.last_render_low = 3
    source^.julia_service^.runtime_generation = 2
    source^.julia_service^.animation_tick_sequence = 9
}

// Assert one observation contains every seeded display scalar.
observe_test_expect_display_scalars :: proc(
    t: ^testing.T, result: Display, source: ^Display_Source) {
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
    testing.expect_value(t, result.dust_live_count, 3)
    testing.expect_value(t, result.dust_airborne_count, 1)
    testing.expect_value(t, result.dust_grounded_count, 2)
    testing.expect_value(t, result.dust_peak_speed_sq, f32(0.03125))
    testing.expect_value(t, result.dust_kinetic_measure, f32(0.0625))
    testing.expect_value(t, result.dust_field_solve_node_count, 20)
    testing.expect_value(t, result.dust_tool_contact_overflow_count, 1)
    testing.expect_value(t, result.dust_tool_contact_coalesced_count, u64(4))
    testing.expect_value(t, result.dust_tool_contact_sample_count, u64(5))
    testing.expect_value(t, result.dust_tool_contact_field_node_visit_count, u64(6))
    testing.expect_value(t, result.dust_rendered_count, 3)
    testing.expect_value(t, result.runtime_generation, u64(2))
    testing.expect_value(t, result.animation_tick_sequence, u64(9))
    testing.expect(t, result.required_evidence_complete)
    testing.expect_value(t, source^.fixed_step, u64(17))
}

// Verify display observation copies authoritative Euclid scalars without mutation.
@(test)
observe_test_display_scalars :: proc(t: ^testing.T) {
    ui_runtime := new(viewmodel.Euclid_Ui_Runtime_State, context.allocator)
    defer free(ui_runtime)
    gif_capture := new(viewmodel.Gif_Capture_Session, context.allocator)
    defer free(gif_capture)
    terminal := new(viewterminalmodel.Terminal_State, context.allocator)
    defer free(terminal)
    dynview := new(dynviewmodel.Dynview_System, context.allocator)
    defer free(dynview)
    shape_world := new(shapemodel.Shape_World, context.allocator)
    defer free(shape_world)
    particle_system := new(particlemodel.Particle_System, context.allocator)
    defer free(particle_system)
    julia_service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
    defer free(julia_service)
    evidence_ring := new(evidence_trace.Ring, context.allocator)
    defer free(evidence_ring)
    source := Display_Source{
        ui_runtime = ui_runtime,
        gif_capture = gif_capture,
        terminal = terminal,
        dynview = dynview,
        shape_world = shape_world,
        particle_system = particle_system,
        julia_service = julia_service,
        evidence_ring = evidence_ring,
    }
    observe_test_seed_display_scalars(&source)
    evidence_trace.ring_init(source.evidence_ring, .Display)

    result := display(&source)
    observe_test_expect_display_scalars(t, result, &source)
}

// Verify Julia-host observation includes its independent producer evidence state.
@(test)
observe_test_julia_host_scalars :: proc(t: ^testing.T) {
    service := new(bridgemodel.Julia_Runtime_Service, context.allocator)
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
    rings: [4]evidence_trace.Ring
    evidence_trace.ring_init(&rings[0], .Particle_Worker)
    evidence_trace.ring_init(&rings[1], .Constraint_Worker)
    evidence_trace.ring_init(&rings[2], .Shape_Cache_Worker)
    evidence_trace.ring_init(&rings[3], .Dynview_Worker)
    source := Simulation_Source{
        particle = &rings[0],
        constraint = &rings[1],
        shape_cache = &rings[2],
        dynview = &rings[3],
    }

    result := simulation(&source)

    testing.expect_value(t, result.particle.producer,
        evidence_trace.Producer.Particle_Worker)
    testing.expect_value(t, result.constraint.producer,
        evidence_trace.Producer.Constraint_Worker)
    testing.expect_value(t, result.shape_cache.producer,
        evidence_trace.Producer.Shape_Cache_Worker)
    testing.expect_value(t, result.dynview.producer,
        evidence_trace.Producer.Dynview_Worker)
}
