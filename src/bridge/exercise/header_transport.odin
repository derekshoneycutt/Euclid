package bridge_exercise

import bridgemodel "../model"
import transport "../transport"
import core "../../core"
import exerciseheader "../../core/exercise_header"

// Copy one validated header update into display-owned inbox storage.
send_exercise_header_update :: proc(
    state: ^core.Euclid_General_State, visible: bool,
    source: []u8) -> bridgemodel.Communication_Send_Outcome {
    if !exercise_header_update_request_valid(state, visible, source) {
        return .Allocation_Failed
    }
    service := state^.julia_runtime_service
    if service^.lifecycle == .Shutdown_Requested || service^.lifecycle == .Stopped {
        return .Runtime_Stopping
    }
    value := bridgemodel.Julia_Host_Egress(bridgemodel.Exercise_Header_Update{
        animation_generation = service^.host_exercise_header_animation_generation,
        request_id = bridgemodel.exercise_header_request_next(
            &service^.exercise_header_request_sequence),
        visible = visible,
        text = source,
    })
    return transport.consumer_mailbox_publish(&service.display_inbox, value)
}

// Validate the publisher boundary before reserving display-owned message storage.
exercise_header_update_request_valid :: proc(
    state: ^core.Euclid_General_State, visible: bool, source: []u8) -> bool {
    return state != nil && state^.julia_runtime_service != nil &&
        visible == (len(source) > 0) &&
        (!visible || exerciseheader.text_is_valid(source))
}
