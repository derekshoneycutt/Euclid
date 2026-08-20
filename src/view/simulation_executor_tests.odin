package view

import app_core "../core"
import app_files "../files"
import app_trace "../trace"

import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:thread"

//   Build the run settings for one headless trace-enabled session.
make_headless_trace_settings :: proc() -> app_core.Euclid_Run_Settings {
    return app_core.Euclid_Run_Settings{
        do_run = true,
        do_antialiasing = false,
        do_vsync = false,
        dust_particle_max = app_core.MAX_LOW_PARTICLES,
        limit_fps = true,
        use_simd_batch_projection = false,
        use_gpu_dust_instancing = false,
        semantic_trace_enabled = true,
        semantic_trace_strict = true,
        semantic_trace_output = "",
        semantic_trace_events = "",
        // Exercise the trace pipeline without printing records to stdout.
        semantic_trace_sink = true,
    }
}

//   Assert the headless session started with a ready service and live state.
expect_headless_session_ready :: proc(
    t: ^testing.T, session: Euclid_Runtime_Session) {

    state := session.state
    service := session.julia_service
    testing.expect(t, state != nil)
    testing.expect(t, service != nil)
    testing.expect_value(t, service^.lifecycle, app_core.Julia_Lifecycle_State.Ready)
    testing.expect(t, state^.julia_interface != nil)
    testing.expect(t, state^.julia_interface^.current_animation != nil)
    testing.expect(t, state^.simulation_executor != nil)
    testing.expect_value(t, state^.fixed_step, u64(0))
    testing.expect_value(t, state^.simulation_time, f32(0))
}

//   Verify a headless runtime session starts, steps, and shuts down without a window.
@(test)
headless_runtime_session_starts_steps_and_shuts_down_without_window :: proc(
    t: ^testing.T) {
    cwd, cwd_err := os.get_working_directory(context.temp_allocator)
    testing.expect(t, cwd_err == nil)
    testing.expect(t, len(cwd) > 0)
    bin_dir, bin_join_err := filepath.join([]string{cwd, "bin"}, context.allocator)
    testing.expect(t, bin_join_err == nil)
    defer delete(bin_dir)
    asset_root_config := app_files.make_asset_root_config(bin_dir)
    defer app_files.destroy_asset_root_config(&asset_root_config)
    testing.expect(t, app_files.reload_packaged_assets_root_with_config(
        &asset_root_config))

    settings := make_headless_trace_settings()
    session, ok := create_runtime_session(&settings)
    testing.expect(t, ok)
    if !ok {
        return
    }
    defer shutdown_runtime_session(session)

    expect_headless_session_ready(t, session)

    state := session.state
    testing.expect(t, run_deterministic_fixed_step(state, 0.025))
    testing.expect(t, run_deterministic_fixed_step(state, 0.025))
    testing.expect_value(t, state^.fixed_step, u64(2))
    testing.expectf(t, math.abs(state^.simulation_time - 0.05) <= 0.0001,
        "expected simulation_time near 0.05, got %v", state^.simulation_time)
    testing.expect(t, app_trace.state_is_valid(&state^.trace_state))
}

//   Verify a deterministic fixed step advances identity after the worker joins.
@(test)
deterministic_fixed_step_advances_identity_after_worker_join :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.particle_system = new(app_core.Particle_System)
    defer free(state^.particle_system)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)
    state^.trace_state.enabled = true
    state^.trace_state.output_mode = .Sink
    state^.trace_state.categories = app_core.Trace_Category_Set{.Geometry}

    executor := create_simulation_executor(state)
    state^.simulation_executor = executor
    defer destroy_simulation_executor(executor)

    testing.expect(t, run_deterministic_fixed_step(state, 0.025))
    testing.expect_value(t, state^.fixed_step, u64(1))
    testing.expectf(t, math.abs(state^.simulation_time - 0.025) <= 0.0001,
        "expected simulation_time near 0.025, got %v", state^.simulation_time)
    testing.expect_value(t, state^.trace_state.records_count, 1)

    first_record := &state^.trace_state.records[0]
    first_event := string(first_record^.event[:first_record^.event_len])
    first_payload := string(first_record^.payload[:first_record^.payload_len])
    testing.expect_value(t, first_event, "constraint.solve_summary")
    testing.expect(t, strings.contains(first_payload, "\"fixed_step\":1"))
    testing.expect(t, strings.contains(first_payload, "\"simulation_time\":0.025"))

    testing.expect(t, run_deterministic_fixed_step(state, 0.025))
    testing.expect_value(t, state^.fixed_step, u64(2))
    testing.expectf(t, math.abs(state^.simulation_time - 0.05) <= 0.0001,
        "expected simulation_time near 0.05, got %v", state^.simulation_time)
    testing.expect_value(t, state^.trace_state.records_count, 2)

    second_record := &state^.trace_state.records[1]
    second_payload := string(second_record^.payload[:second_record^.payload_len])
    testing.expect(t, strings.contains(second_payload, "\"fixed_step\":2"))
    testing.expect(t, strings.contains(second_payload, "\"simulation_time\":0.05"))
}

//   Verify a deterministic fixed step emits a post-join checkpoint snapshot.
@(test)
deterministic_fixed_step_emits_post_join_checkpoint_snapshot :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.julia_interface^.current_animation = &state^.julia_interface^.null_animation
    state^.julia_interface^.null_animation.name = "null"
    state^.julia_runtime_service = new(app_core.Julia_Runtime_Service)
    defer free(state^.julia_runtime_service)
    state^.particle_system = new(app_core.Particle_System)
    defer free(state^.particle_system)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)
    state^.point_system^.next_point_index = 1
    state^.point_system^.points[0].kind = .Point
    state^.point_system^.points[0].position = app_core.Vector3{1, 2, 3}
    state^.trace_state.enabled = true
    state^.trace_state.output_mode = .Sink
    state^.trace_state.categories = app_core.Trace_Category_Set{.Trace, .Geometry}

    executor := create_simulation_executor(state)
    state^.simulation_executor = executor
    defer destroy_simulation_executor(executor)

    testing.expect(t, run_deterministic_fixed_step(state, 0.025))
    testing.expect_value(t, state^.trace_state.records_count, 2)

    checkpoint := &state^.trace_state.records[1]
    event_name := string(checkpoint^.event[:checkpoint^.event_len])
    payload := string(checkpoint^.payload[:checkpoint^.payload_len])
    testing.expect_value(t, event_name, "trace.checkpoint")
    testing.expect(t, strings.contains(payload, "\"checkpoint_id\":1"))
    testing.expect(t, strings.contains(payload, "\"fixed_step\":1"))
    testing.expect(t, strings.contains(payload, "\"simulation_time\":0.025"))
    testing.expect(t, strings.contains(payload, "\"animation_id\":\"null\""))
    testing.expect(t, strings.contains(payload, "\"next_point_index\":1"))
    testing.expect(t, strings.contains(payload, "\"points\":["))
}

//   Verify a parallel step joins the particle and constraint updates.
@(test)
parallel_simulation_step_joins_particle_and_constraint_updates :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.particle_system = new(app_core.Particle_System)
    defer free(state^.particle_system)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)

    particles := state^.particle_system
    particles^.use_max_dust_particles = 1
    particles^.low_particles.alive[0] = true
    particles^.low_particles.life[0] = 10
    particles^.low_particles.vel_x[0] = 0.25

    points := state^.point_system
    points^.points[0].position = app_core.Vector3{0, 0, -1}
    points^.constraints[0] = app_core.Shapes_Constraint{
        kind = .Floor,
        on_point = 0,
        restriction = app_core.Vector3{0, 0, 0},
        do_apply = true,
    }

    executor := create_simulation_executor(state)
    defer destroy_simulation_executor(executor)
    run_parallel_simulation_step(executor, 0.01)
    first_batch_x := particles^.low_particles.pos_x[0]
    run_parallel_simulation_step(executor, 0.01)

    testing.expect_value(t, first_batch_x, f32(0.25))
    testing.expect(t, particles^.low_particles.pos_x[0] > first_batch_x)
    position := points^.points[0].position.? or_else app_core.Vector3{}
    testing.expect_value(t, position.z, f32(0))
}

//   Verify frame preparation joins the shape and dynview cache updates.
@(test)
parallel_frame_preparation_joins_shape_and_dynview_cache_updates :: proc(t: ^testing.T) {
    state := new(app_core.Euclid_General_State)
    defer free(state)
    state^.point_system = new(app_core.Shapes_Point_System)
    defer free(state^.point_system)
    state^.point_system^.next_point_index = 1
    state^.point_system^.points[0].kind = .Point
    state^.point_system^.points[0].do_draw = true
    state^.point_system^.points[0].position = app_core.Vector3{1, 2, 3}
    state^.dynview.enabled = true

    executor := create_simulation_executor(state)
    state^.simulation_executor = executor
    defer destroy_simulation_executor(executor)

    run_parallel_frame_preparation(state, 0.25)
    testing.expect_value(t, state^.point_system^.draw_cache.item_count, 1)
    testing.expect(t, state^.dynview.compile_cache.is_valid)
    testing.expect(t, state^.dynview.compile_cache.layout_is_valid)
    testing.expect(t, thread.pool_is_empty(&executor^.pool))

    run_parallel_frame_preparation(state, 0.75)
    testing.expect_value(t, state^.point_system^.draw_cache.item_count, 1)
    testing.expect(t, thread.pool_is_empty(&executor^.pool))
}