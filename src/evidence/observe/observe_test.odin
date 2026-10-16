#+test
package observe

import telemetrymodel "../../view/telemetry/model"
import preferencesmodel "../../view/preferences/model"

import viewmodel "../../view/ui/model"
import capturemodel "../../view/capture/model"
import bridgemodel "../../bridge/model"
import dynviewmodel "../../dynview/model"
import evidence_trace "../trace"
import particlemodel "../../particles/model"
import shapemodel "../../shapes/model"
import viewterminalmodel "../../view/terminal/model"
import testing "core:testing"

// Observe_Display_Fixture owns the borrowed state used by one display observation.
Observe_Display_Fixture :: struct {
    source: Display_Source,
}

// Allocate the independent component fixtures for a composed observation test.
observe_test_display_fixture_init :: proc(fixture: ^Observe_Display_Fixture) {
    fixture^.source.ui_layout = new(viewmodel.Ui_Layout_State, context.allocator)
    fixture^.source.ui_library = new(viewmodel.Ui_Library_State, context.allocator)
    fixture^.source.ui_presentation = new(
        viewmodel.Ui_Presentation_Interaction_State, context.allocator)
    fixture^.source.ui_preferences = new(
        viewmodel.Ui_Preference_State, context.allocator)
    fixture^.source.ui_playback = new(
        viewmodel.Ui_Playback_Control_State, context.allocator)
    fixture^.source.ui_tooltip = new(viewmodel.Ui_Tooltip_State, context.allocator)
    fixture^.source.telemetry = new(telemetrymodel.Runtime, context.allocator)
    fixture^.source.gif_capture = new(
        capturemodel.Gif_Capture_Session, context.allocator)
    fixture^.source.terminal = new(viewterminalmodel.Terminal_State, context.allocator)
    fixture^.source.dynview = new(dynviewmodel.Dynview_System, context.allocator)
    fixture^.source.shape_world = new(shapemodel.Shape_World, context.allocator)
    fixture^.source.particle_system =
        new(particlemodel.Particle_System, context.allocator)
    fixture^.source.julia_service =
        new(bridgemodel.Julia_Runtime_Service, context.allocator)
    fixture^.source.evidence_ring = new(evidence_trace.Ring, context.allocator)
}

// Release each owner allocation retained by the observation fixture.
observe_test_display_fixture_destroy :: proc(fixture: ^Observe_Display_Fixture) {
    free(fixture^.source.ui_layout, context.allocator)
    free(fixture^.source.ui_library, context.allocator)
    free(fixture^.source.ui_presentation, context.allocator)
    free(fixture^.source.ui_preferences, context.allocator)
    free(fixture^.source.ui_playback, context.allocator)
    free(fixture^.source.ui_tooltip, context.allocator)
    free(fixture^.source.telemetry, context.allocator)
    free(fixture^.source.gif_capture, context.allocator)
    free(fixture^.source.terminal, context.allocator)
    free(fixture^.source.dynview, context.allocator)
    free(fixture^.source.shape_world, context.allocator)
    free(fixture^.source.particle_system, context.allocator)
    free(fixture^.source.julia_service, context.allocator)
    free(fixture^.source.evidence_ring, context.allocator)
}

// Verify capture evidence survives an absent UI and never borrows policy storage.
@(test)
observe_test_independent_capture_owner :: proc(t: ^testing.T) {
    status := capturemodel.Gif_Capture_Status{
        gif_capture_phase = .Recording, gif_captured_frames = 7}
    source := Display_Source{gif_capture_status = &status}
    result := display(&source)
    status.gif_capture_phase = .Saved
    status.gif_captured_frames = 8
    testing.expect_value(t,
        result.gif_capture_phase, capturemodel.Gif_Capture_Phase.Recording)
    testing.expect_value(t, result.gif_captured_frames, 7)
    empty_source := Display_Source{}
    empty := display(&empty_source)
    testing.expect_value(t, empty.gif_capture_phase, capturemodel.Gif_Capture_Phase.Idle)
    testing.expect_value(t, empty.gif_captured_frames, 0)
}

// Verify persistence evidence is copied from its owner even without a UI projection.
@(test)
observe_test_independent_persistence_owner :: proc(t: ^testing.T) {
    runtime := new(preferencesmodel.Settings_Save_Runtime, context.allocator)
    defer free(runtime, context.allocator)
    runtime^ = preferencesmodel.Settings_Save_Runtime{
        settings_pending = {count = 2},
        settings_save_active = true,
        settings_save_commit_count = 3,
        settings_save_failure_count = 4,
        settings_save_owner_execution_count = 5,
    }
    source := Display_Source{preferences_runtime = runtime}
    result := display(&source)
    testing.expect(t, result.settings_save_active)
    testing.expect_value(t, result.settings_pending_count, 2)
    testing.expect_value(t, result.settings_save_commit_count, u64(3))
    testing.expect_value(t, result.settings_save_failure_count, u64(4))
    testing.expect_value(t, result.settings_save_owner_execution_count, u64(5))
    testing.expect_value(t, runtime^.settings_pending.count, 2)
}

// Verify the display copies only initialized branch motion and retained visual geometry.
@(test)
observe_tree_motion_is_pointer_free_and_bounded :: proc(t: ^testing.T) {
    library: viewmodel.Ui_Library_State
    library.motion.count = 2
    library.motion.branches[0].running = true
    library.motion.branches[2].running = true
    library.motion.visual_height = 140.25
    library.tree.scroll_y = 20.5
    result: Display
    observe_display_tree(&library, &result)
    testing.expect_value(t, result.tree_transition_count, 1)
    testing.expect_value(t, result.tree_visual_height, f32(140.25))
    testing.expect_value(t, result.tree_scroll_y, f32(20.5))
    testing.expect(t, library.motion.branches[0].running)
}

// Verify tree-settled evidence includes attached drawer and reorder transitions.
@(test)
observe_tree_motion_includes_drawer_and_swap :: proc(t: ^testing.T) {
    library: viewmodel.Ui_Library_State
    library.actions.reorder.active = true
    library.actions.drawer.running = true
    result: Display
    observe_display_tree(&library, &result)
    testing.expect_value(t, result.tree_transition_count, 2)
}

// Seed authoritative display scalars used by the observation contract test.
observe_test_seed_display_scalars :: proc(source: ^Display_Source) {
    source^.fixed_step = 17
    source^.simulation_time = 2.5
    source^.ui_playback^.simulation_paused = true
    source^.ui_presentation^.text_scroll_y = 90.5
    source^.ui_presentation^.text_scroll_max = 120
    source^.ui_layout^.vertical_split_x = 640
    source^.ui_layout^.horizontal_split_y = 360
    source^.telemetry^.colored_vertex_count = 400
    source^.telemetry^.colored_index_count = 600
    source^.telemetry^.curve_candidate_point_count = 100
    source^.telemetry^.curve_retained_point_count = 25
    source^.telemetry^.curve_retention_ratio = 0.25
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
    testing.expect_value(t, result.colored_vertex_count, u32(400))
    testing.expect_value(t, result.colored_index_count, u32(600))
    testing.expect_value(t, result.curve_candidate_point_count, u32(100))
    testing.expect_value(t, result.curve_retained_point_count, u32(25))
    testing.expect_value(t, result.curve_retention_ratio, f32(0.25))
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
    fixture: Observe_Display_Fixture
    observe_test_display_fixture_init(&fixture)
    defer observe_test_display_fixture_destroy(&fixture)
    observe_test_seed_display_scalars(&fixture.source)
    evidence_trace.ring_init(fixture.source.evidence_ring, .Display)
    result := display(&fixture.source)
    observe_test_expect_display_scalars(t, result, &fixture.source)
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
