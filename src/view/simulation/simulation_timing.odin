package viewsimulation

import audio "../../audio"
import core "../../core"
import shapes "../../shapes"
import julia "../../bridge"
import simulationmodel "model"
import viewcapture "../capture"
import projection "../world/projection"
import viewtelemetry "../telemetry"
import terminalservice "../terminal/service"
import viewevidence "../evidence"
import capturemodel "../capture/model"

//   Run fixed-step simulation updates and return interpolation alpha for rendering.
accumulate_and_update_systems :: proc(
    state: ^core.Euclid_General_State, frame_dt: f32,
    gif_extents: capturemodel.Gif_Capture_Extents) -> f32 {
    projection.recompute_iso_scale_precompute(state^.iso_scale)

    clamped_dt := frame_dt
    if clamped_dt > simulationmodel.MAX_FRAME_DT {
        clamped_dt = simulationmodel.MAX_FRAME_DT
    }
    viewtelemetry.update_average_fps(state, clamped_dt)
    projection.screenshake_update(state^.iso_scale, clamped_dt)

    if state^.ui_runtime.simulation_paused {
        julia.publish_available_animation_tick(state)
        audio.set_drawing_activity(&state^.chalk_audio, false)
        state^.accumulator = 0
        return 0
    }

    state^.accumulator += clamped_dt

    step_count := 0
    for state^.accumulator >= simulationmodel.FIXED_DT {
        // Never expose worker-commanded tool dimensions before constraints normalize them.
        shapes.shape_world_update_previous_values(state^.shape_world)
        run_windowed_fixed_step(state, simulationmodel.FIXED_DT, gif_extents)

        state^.accumulator -= simulationmodel.FIXED_DT
        step_count += 1
        if step_count >= simulationmodel.MAX_STEPS_PER_FRAME {
            state^.accumulator = 0
            break
        }
    }

    alpha := state^.accumulator / simulationmodel.FIXED_DT
    return alpha
}

//   Run one deterministic fixed step through animation publication and worker join.
//
// Parameters:
//   - state: Runtime state advanced by one fixed step.
//   - dt: Deterministic fixed-step duration.
//
// Returns:
//   - ok: true when the step completed and post-join identity advanced.
run_deterministic_fixed_step :: proc(
    state: ^core.Euclid_General_State, dt: f32) -> bool {
    if state == nil || state^.simulation_executor == nil || dt <= 0 {
        return false
    }

    state^.current_delta_time = dt
    julia.publish_available_animation_tick(state)
    if state^.ui_runtime.animation_policy_paused {
        audio.set_drawing_activity(&state^.chalk_audio, false)
    }
    if !state^.ui_runtime.animation_policy_paused {
        julia.schedule_animation_tick(state, dt)
    }
    run_parallel_simulation_step(state^.simulation_executor, dt)
    state^.fixed_step += 1
    terminalservice.terminal_tick_record_step(
        &state^.terminal_tick_publisher, state^.fixed_step)
    state^.simulation_time += dt
    viewevidence.record_constraint_trace_summary(state)
    _ = viewevidence.record_evidence_checkpoint(state, false)
    return true
}

//   Run one fixed step and apply windowed presentation side effects after the worker join.
//
// Parameters:
//   - state: Runtime state advanced by one fixed step.
//   - dt: Fixed-step duration from the windowed runtime.
//
// Returns:
//   - ok: true when the deterministic step completed.
run_windowed_fixed_step :: proc(
    state: ^core.Euclid_General_State, dt: f32,
    gif_extents: capturemodel.Gif_Capture_Extents) -> bool {
    if !run_deterministic_fixed_step(state, dt) {
        return false
    }

    previous_phase := state^.gif_capture_status.gif_capture_phase
    viewcapture.gif_capture_update_fixed_step(state, gif_extents)
    viewcapture.record_gif_capture_transition(
        state, previous_phase, state^.gif_capture_status.gif_capture_phase)
    return true
}
