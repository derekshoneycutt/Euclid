package julia_host

import bridgemodel "../model"
import julialib "../../../libs/julia/bindings"
import core "../../core"
import uuid "core:encoding/uuid"
import log "core:log"

TERMINAL_ANIMATION_NAME :: "Terminal"
ANIMATION_LIFECYCLE_ACTIVATE :: i32(1)
ANIMATION_LIFECYCLE_RESET :: i32(2)
ANIMATION_LIFECYCLE_RELOAD :: i32(4)
ANIMATION_LIFECYCLE_NATIVE_RESET :: i32(1)
ANIMATION_LIFECYCLE_COMPLETED :: i32(2)

Julia_Interface_Reload_Transaction :: struct {
    state: ^core.Euclid_General_State,
    host: ^Julia_Runtime_Host,
    request: bridgemodel.Animation_Lifecycle_Requested,
    package_identity: [32]byte,
    stable_id: uuid.Identifier,
    candidate: ^julialib.jl_value_t,
    service: ^Julia_Runtime_Service,
    previous_interface: ^bridgemodel.Euclid_Julia_Interface,
    staged_interface: ^bridgemodel.Euclid_Julia_Interface,
    staged_slot: int,
    target: ^bridgemodel.Euclid_Julia_Animation_Interface,
}

//   Invoke one Julia callback through the stack-preserving diagnostic boundary.
call_julia_callback1 :: proc(
    state: ^core.Euclid_General_State, callback, argument: ^julialib.jl_value_t) {

    julialib.jl_call2(
        state^.julia_interface^.invoke_with_exception_diagnostics,
        callback, argument)
}

//   Invoke one two-argument Julia callback through the diagnostic boundary.
call_julia_callback2 :: proc(
    state: ^core.Euclid_General_State, callback, first,
    second: ^julialib.jl_value_t) {

    julialib.jl_call3(
        state^.julia_interface^.invoke_with_exception_diagnostics,
        callback, first, second)
}

//   Invoke Julia-side script initialization after native catalogue materialization.
//
// Parameters:
//   - state: Global runtime state passed through to Julia callback entry points.
//
// Notes:
//   - Julia exceptions are reported and the call returns early without panicking.
init_euclid_scripts :: proc(state: ^core.Euclid_General_State) -> bool {
    service := state^.julia_runtime_service
    if service == nil || service^.runtime_host == nil {
        log.error("julia_content_runtime_host_missing")
        return false
    }
    state_value := julialib.jl_box_voidpointer(state)

    call_julia_callback2(
        state, state^.julia_interface^.init_scripts,
        service^.runtime_host, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("init_euclid_scripts")
        return false
    }
    if !finish_euclid_generation(state) {
        log.error("julia_content_finish_generation_failed")
        return false
    }
    return true
}

//   Complete native initialization after one generation registers its callbacks.
finish_euclid_generation :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if state^.julia_interface^.selected_animation == nil {
        select_default_animation(state)
    }
    return true
}

//   Initialize one explicitly rooted candidate without executing animation policy.
init_euclid_generation :: proc(
    state: ^core.Euclid_General_State,
    generation: ^julialib.jl_value_t) -> bool {

    main_module := resolve_main_module()
    if main_module == nil || generation == nil {
        return false
    }
    callback := julialib.jl_get_function(
        main_module, "initialize_euclid_generation")
    if callback == nil {
        return false
    }
    args: [3]^julialib.jl_value_t = {
        state^.julia_runtime_service^.runtime_host,
        generation,
        julialib.jl_box_voidpointer(state),
    }
    _ = julialib.jl_call(callback, &args[0], 3)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("initialize_euclid_generation")
        return false
    }
    return true
}
