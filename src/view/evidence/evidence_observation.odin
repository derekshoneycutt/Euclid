package viewevidence

import observe "../../evidence/observe"
import viewgraphics "../terminal/graphics"
import core "../../core"

// Copy display-owned composition into the evidence model at an owner boundary.
observe_display_state :: proc(state: ^core.Euclid_General_State) -> observe.Display {
    if state == nil {
        return {}
    }
    source := observe.Display_Source{
        fixed_step = state.fixed_step,
        simulation_time = state.simulation_time,
        ui_layout = &state.ui_runtime.layout,
        ui_library = &state.ui_runtime.library,
        ui_presentation = &state.ui_runtime.presentation,
        ui_preferences = &state.ui_runtime.preferences,
        ui_playback = &state.ui_runtime.playback,
        ui_tooltip = &state.ui_runtime.tooltip,
        ui_platform_reduce_motion = state.ui_runtime.platform_reduce_motion,
        preferences_runtime = &state.preferences_runtime,
        telemetry = &state.telemetry,
        gif_capture = &state.gif_capture,
        gif_capture_status = &state.gif_capture_status,
        terminal = &state.terminal,
        dynview = &state.dynview,
        shape_world = state.shape_world,
        particle_system = state.particle_system,
        julia_service = state.julia_runtime_service,
        required_evidence_complete =
            state.evidence_session.required_evidence_complete,
        evidence_ring = &state.evidence_ring,
    }
    result := observe.display(&source)
    viewgraphics.service_observe(
        cast(^viewgraphics.Service)state.terminal_graphics_user_data, &result)
    return result
}

// Copy joined simulation producer rings into the evidence model.
observe_simulation_executor :: proc(
    executor: ^core.Simulation_Executor) -> observe.Simulation {
    if executor == nil {
        return {}
    }
    source := observe.Simulation_Source{
        particle = &executor.particle_task.evidence_ring,
        constraint = &executor.constraint_task.evidence_ring,
        shape_cache = &executor.shape_cache_task.evidence_ring,
        dynview = &executor.dynview_task.evidence_ring,
    }
    return observe.simulation(&source)
}