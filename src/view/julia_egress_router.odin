package view

import bridgemodel "../bridge/model"
import bridge "../bridge"
import core "../core"
import viewpresentation "presentation"
import terminalservice "terminal/service"

//   Route one non-event Julia envelope to its display-owned subsystem.
// Presentation admission retains the envelope; Terminal dispatch consumes it immediately.
julia_egress_router_dispatch :: proc(
    user_data: rawptr,
    message: ^bridgemodel.Julia_Host_Egress) -> bool {
    runtime := cast(^viewpresentation.Presentation_Runtime)user_data
    assert(runtime != nil && runtime^.state != nil)
    if content, is_content := message^.(bridgemodel.View_Content_Ready); is_content {
        viewpresentation.presentation_admit(runtime^.state, runtime, message, content)
        return true
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