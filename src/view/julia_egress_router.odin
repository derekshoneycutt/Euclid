package view

import bridgemodel "../bridge/model"
import bridge "../bridge"
import core "../core"
import exerciseheader "../core/exercise_header"
import viewpresentation "presentation"
import terminalservice "terminal/service"
import "core:log"

// Route one non-event Julia envelope to its display-owned subsystem.
julia_egress_router_dispatch :: proc(
    user_data: rawptr,
    message: ^bridgemodel.Julia_Host_Egress) -> bool {
    runtime := cast(^viewpresentation.Presentation_Runtime)user_data
    assert(runtime != nil && runtime^.state != nil)
    if content, is_content := message^.(bridgemodel.View_Content_Ready); is_content {
        viewpresentation.presentation_admit(runtime^.state, runtime, message, content)
        return true
    }
    if intent, is_intent := message^.(bridgemodel.Exercise_Query_Intent); is_intent {
        admit_exercise_query(runtime.state, intent)
        return false
    }
    if update, is_update := message^.(bridgemodel.Exercise_Header_Update);
        is_update {
        state := runtime^.state
        if state^.terminal.initialized &&
            state^.julia_runtime_service != nil &&
            update.request_id > state^.exercise_header.last_request_id &&
            state^.julia_runtime_service^.animation_generation ==
                update.animation_generation {
            state^.exercise_header.last_request_id = update.request_id
            if update.visible {
                if !exerciseheader.show(&state^.exercise_header, update.text) {
                    log.error("exercise_header_update_rejected_after_admission")
                }
            } else {
                exerciseheader.hide(&state^.exercise_header)
            }
        }
        return false
    }
    _ = terminalservice.terminal_service_dispatch_egress(runtime^.state, message)
    return false
}

//   Install the normal-frame Julia egress destination and admit retained startup content.
julia_egress_router_attach :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^viewpresentation.Presentation_Runtime) {
    assert(state != nil && runtime != nil && state^.julia_runtime_service != nil)
    runtime^.state = state
    bridge.configure_julia_egress_dispatch(
        state^.julia_runtime_service, julia_egress_router_dispatch, rawptr(runtime))
}

//   Stop display dispatch before destroying presentation and Terminal destinations.
julia_egress_router_detach :: proc(
    state: ^core.Euclid_General_State,
    runtime: ^viewpresentation.Presentation_Runtime) {
    if state == nil || state^.julia_runtime_service == nil || runtime == nil {
        return
    }
    bridge.clear_julia_egress_dispatch(state^.julia_runtime_service)
    runtime^.state = nil
}