package view

import bridgemodel "../bridge/model"
import font "font"
import terminalview "terminal"
import core "../core"
import julia "../bridge"
import evidence_session "../evidence/session"
import runtime "base:runtime"
import fmt "core:fmt"
import time "core:time"

import viewcapture "capture"
import viewscenario "scenario"
import terminalservice "terminal/service"
import viewpreferences "preferences"

JULIA_SHUTDOWN_TIMEOUT_SECONDS :: 5.0

//   Release graphics-owned resources before destroying their backing runtime state.
shutdown_window_runtime :: proc(
    session: Euclid_Runtime_Session,
    scenario_runtime: ^viewscenario.Scenario_Runtime = nil,
    artifact_output: string = "") -> int {
    if session.state != nil {
        viewpreferences.settings_save_shutdown(
            session.state, &session.state^.simulation_executor^.pool)
        font.cache_shutdown_service(
            &session.state^.font_cache,
            &session.state^.simulation_executor^.pool)
        font.math_shaping_destroy(&session.state^.dynview.math_shaping)
        font.cache_destroy(&session.state^.font_cache)
    }
    return shutdown_runtime_session(session, scenario_runtime, artifact_output)
}

// Submit orderly host shutdown within the shared deadline; saturation terminates the process.
submit_julia_shutdown :: proc(
    service: ^bridgemodel.Julia_Runtime_Service, started_at: time.Tick) -> u64 {
    shutdown_id, sent := julia.submit_runtime_shutdown_until(
        service, started_at, JULIA_SHUTDOWN_TIMEOUT_SECONDS)
    if !sent {
        fmt.eprintln(
            "Julia shutdown request queue remained saturated; terminating process.")
        runtime.exit(1)
    }
    return shutdown_id
}

//   Wait for the matching shutdown completion within the shared timeout window.
wait_for_julia_shutdown :: proc(
    service: ^bridgemodel.Julia_Runtime_Service, shutdown_id: u64,
    started_at: time.Tick) {
    if !julia.wait_runtime_shutdown_completion(
        service, shutdown_id, started_at, JULIA_SHUTDOWN_TIMEOUT_SECONDS) {
        fmt.eprintln("Julia shutdown timed out; terminating process.")
        runtime.exit(1)
    }
}

// Join the host shutdown request before accepting the final display lifecycle evidence.
shutdown_julia_runtime :: proc(
    state: ^core.Euclid_General_State, service: ^bridgemodel.Julia_Runtime_Service) {
    started_at := time.tick_now()
    shutdown_id := submit_julia_shutdown(service, started_at)
    _ = evidence_session.session_record(
        &state^.evidence_session, &state^.evidence_ring, {
            lane = .Lifecycle,
            kind = .Runtime_Shutdown_Started,
            correlation_kind = .Runtime_Request,
            correlation = shutdown_id,
            generation = service^.runtime_generation,
            flags = {.Required},
        })
    wait_for_julia_shutdown(service, shutdown_id, started_at)
    evidence_session.session_accept_ring(
        &state^.evidence_session, &state^.evidence_ring)
}

//   Release runtime state allocations and finalize Julia/GIF runtime resources.
//
// Notes:
//   - Must be paired with initiate_animations_state to release owned allocations.
free_animations_state :: proc(state : ^core.Euclid_General_State) {
    if state == nil {
        return
    }
    viewcapture.gif_capture_destroy_session(&state^.gif_capture)
    terminalservice.terminal_graphics_runtime_destroy(state)
    terminalservice.shell_service_runtime_destroy(state)
    terminalview.terminal_destroy(&state^.terminal)
    julia.animation_storage_destroy(
        &state^.animation_memory,
        &state^.animation_values,
        &state^.dynview_documents)
    julia.destroy_julia_interface_resources(state)
    free(state^.ui_runtime.semantic_focus, context.allocator)
    free(state^.particle_system)
    free(state^.shape_world)
    free(state^.draw_surface)
    free(state^.iso_scale)
    free(state)
}
