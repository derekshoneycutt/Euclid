package julia_host

import julialib "../../../libs/julia/bindings"
import "core:fmt"

//   Bind Julia functions that accept native Terminal requests.
bind_julia_terminal_ingress_callbacks :: proc(
    host: ^Julia_Runtime_Host, main_module: ^julialib.jl_module_t) {

    host^.terminal_startup_banner = julialib.jl_get_function(
        main_module, "terminal_host_startup_banner")
    host^.terminal_start_session = julialib.jl_get_function(
        main_module, "terminal_host_start_session")
    host^.terminal_close_session = julialib.jl_get_function(
        main_module, "terminal_host_close_session")
    host^.terminal_ingest_evaluation = julialib.jl_get_function(
        main_module, "terminal_host_ingest_evaluation")
    bind_julia_active_operation_outcome_callback(host, main_module)
    bind_julia_terminal_interactive_callbacks(host, main_module)
    host^.terminal_ingest_completion_preview = julialib.jl_get_function(
        main_module, "terminal_host_ingest_completion_preview")
    host^.terminal_ingest_completion_candidates = julialib.jl_get_function(
        main_module, "terminal_host_ingest_completion_candidates")
    host^.terminal_ingest_highlight = julialib.jl_get_function(
        main_module, "terminal_host_ingest_highlight")
    host^.terminal_highlight_identity_type = julialib.jl_get_global(
        main_module, julialib.jl_symbol("NativeHighlightIdentity"))
    host^.terminal_shutdown = julialib.jl_get_function(
        main_module, "terminal_host_shutdown")
    host^.terminal_ingest_tick_configuration = julialib.jl_get_function(
        main_module, "terminal_host_ingest_tick_stream_configuration")
    host^.terminal_ingest_tick_pulse = julialib.jl_get_function(
        main_module, "terminal_host_ingest_tick_pulse")
    bind_julia_animation_lifecycle_callbacks(host, main_module)
}

// Bind the outcome callback and its payload type from their owning Julia module.
bind_julia_active_operation_outcome_callback :: proc(
    host: ^Julia_Runtime_Host, main_module: ^julialib.jl_module_t) {
    host^.active_operation_outcome_ingest = julialib.jl_get_function(
        main_module, "terminal_host_ingest_active_operation_outcome")
    host^.active_operation_progress_ingest = julialib.jl_get_function(
        main_module, "terminal_host_ingest_active_operation_progress")
    bridge_module := julialib.jl_get_global(
        main_module, julialib.jl_symbol("OdinJuliaBridge"))
    if bridge_module == nil {
        host^.active_operation_outcome_type = nil
        host^.active_operation_progress_type = nil
    } else {
        bridge := cast(^julialib.jl_module_t)bridge_module
        host^.active_operation_outcome_type = julialib.jl_get_global(
            bridge, julialib.jl_symbol("NativeActiveOperationOutcome"))
        host^.active_operation_progress_type = julialib.jl_get_global(
            bridge, julialib.jl_symbol("NativeActiveOperationProgress"))
    }
}

// Bind Julia lifecycle callbacks for native animation-owner requests.
bind_julia_animation_lifecycle_callbacks :: proc(
    host: ^Julia_Runtime_Host, main_module: ^julialib.jl_module_t) {
    host^.animation_tick = julialib.jl_get_function(
        main_module, "animation_host_tick")
    host^.animation_tick_payload_type = julialib.jl_get_global(
        main_module, julialib.jl_symbol("NativeAnimationTickPayload"))
    host^.animation_lifecycle = julialib.jl_get_function(
        main_module, "animation_host_lifecycle")
    host^.animation_lifecycle_acknowledge_reset = julialib.jl_get_function(
        main_module, "animation_host_acknowledge_reset")
    host^.animation_lifecycle_payload_type = julialib.jl_get_global(
        main_module, julialib.jl_symbol("NativeAnimationLifecyclePayload"))
}

//   Bind Terminal result callbacks and the primitive Julia pump scheduling query.
bind_julia_terminal_egress_callbacks :: proc(
    host: ^Julia_Runtime_Host, main_module: ^julialib.jl_module_t) {

    host^.terminal_take_evaluation = julialib.jl_get_function(
        main_module, "terminal_host_take_evaluation")
    host^.terminal_take_completion = julialib.jl_get_function(
        main_module, "terminal_host_take_completion")
    host^.terminal_take_highlight = julialib.jl_get_function(
        main_module, "terminal_host_take_highlight")
    host^.terminal_take_session_lifecycle = julialib.jl_get_function(
        main_module, "terminal_host_take_session_lifecycle")
    host^.terminal_take_tick_stream = julialib.jl_get_function(
        main_module, "terminal_host_take_tick_stream")
    host^.terminal_pump = julialib.jl_get_function(
        main_module, "terminal_host_pump_wait_ns")
}

//   Report whether every required Terminal callback was bound.
julia_terminal_callbacks_complete :: proc(host: ^Julia_Runtime_Host) -> bool {
    return host^.terminal_startup_banner != nil &&
        host^.terminal_start_session != nil &&
        host^.terminal_close_session != nil &&
        host^.terminal_ingest_evaluation != nil &&
        host^.active_operation_outcome_ingest != nil &&
        host^.active_operation_outcome_type != nil &&
        host^.active_operation_progress_ingest != nil &&
        host^.active_operation_progress_type != nil &&
        host^.terminal_ingest_interactive_input != nil &&
        host^.terminal_ingest_geometry != nil &&
        host^.terminal_ingest_capabilities != nil &&
        host^.terminal_ingest_completion_preview != nil &&
        host^.terminal_ingest_completion_candidates != nil &&
        host^.terminal_pump != nil &&
        host^.terminal_shutdown != nil && host^.terminal_take_evaluation != nil &&
        host^.terminal_take_completion != nil &&
        host^.terminal_ingest_highlight != nil &&
        host^.terminal_take_highlight != nil &&
        host^.terminal_highlight_identity_type != nil &&
        host^.terminal_take_session_lifecycle != nil &&
        host^.terminal_ingest_tick_configuration != nil &&
        host^.terminal_ingest_tick_pulse != nil &&
        host^.terminal_take_tick_stream != nil && host^.animation_tick != nil &&
        host^.animation_tick_payload_type != nil &&
        host^.animation_lifecycle != nil &&
        host^.animation_lifecycle_acknowledge_reset != nil &&
        host^.animation_lifecycle_payload_type != nil
}

//   Construct and validate the rooted runtime host after native state exists.
bind_julia_terminal_callbacks :: proc(host: ^Julia_Runtime_Host) -> bool {
    main_module := julialib.julia_main_module()
    bind_julia_terminal_ingress_callbacks(host, main_module)
    bind_julia_terminal_egress_callbacks(host, main_module)
    return julia_terminal_callbacks_complete(host)
}

//   Report which required Terminal callbacks were absent during host construction.
report_missing_julia_terminal_callbacks :: proc(host: ^Julia_Runtime_Host) {
    fmt.eprintln(
        "Julia startup: missing Terminal callback(s): banner=",
        host^.terminal_startup_banner != nil,
        " start=", host^.terminal_start_session != nil,
        " close=", host^.terminal_close_session != nil,
        " ingest=", host^.terminal_ingest_evaluation != nil,
        " active_operation_outcome=",
        host^.active_operation_outcome_type != nil,
        " active_operation_progress=",
        host^.active_operation_progress_type != nil,
        " completion_preview=", host^.terminal_ingest_completion_preview != nil,
        " completion_candidates=", host^.terminal_ingest_completion_candidates != nil,
        " pump=", host^.terminal_pump != nil,
        " shutdown=", host^.terminal_shutdown != nil,
        " evaluation=", host^.terminal_take_evaluation != nil,
        " completion=", host^.terminal_take_completion != nil,
        " highlight_ingest=", host^.terminal_ingest_highlight != nil,
        " highlight_take=", host^.terminal_take_highlight != nil,
        " highlight_identity=", host^.terminal_highlight_identity_type != nil,
        " lifecycle=", host^.terminal_take_session_lifecycle != nil,
        " animation_tick=", host^.animation_tick != nil,
        " animation_tick_payload=", host^.animation_tick_payload_type != nil,
        " animation_lifecycle=", host^.animation_lifecycle != nil,
        " animation_lifecycle_ack=",
        host^.animation_lifecycle_acknowledge_reset != nil,
        " animation_lifecycle_payload=",
        host^.animation_lifecycle_payload_type != nil)
}
