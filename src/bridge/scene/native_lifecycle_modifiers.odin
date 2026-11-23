package bridge_scene

import bridgemodel "../model"

import core "../../core"
import modifier "../../animation"
import "core:os"

// Admit setup only on the Julia owner while the existing lifecycle slot holds display.
native_lifecycle_placement_allowed :: proc(
    state: ^core.Euclid_General_State, kind: modifier.Modifier_Kind) -> bool {
    if kind != .Parabola_Place && kind != .Hyperbola_Place &&
        kind != .Cycloid_Place && kind != .Trochoid_Place {
        return false
    }
    service := state.julia_runtime_service
    if service == nil || service.animation_tick_pending ||
        service.owner_thread_id != os.get_current_thread_id() {
        return false
    }
    slot := &service.animation_lifecycle_slot
    return slot.state == .Pending && slot.host_state == rawptr(state)
}

// Preflight all native setup outputs before mutating the quiesced lifecycle world.
apply_native_lifecycle_placement :: proc(
    state: ^core.Euclid_General_State, request: modifier.Modifier_Request) -> i32 {
    if !native_lifecycle_placement_allowed(state, request.kind) {
        return bridgemodel.BRIDGE_STATUS_ILLEGAL_STATE
    }
    command: Scene_Command = {
        modifier = request,
    }
    if !validate_native_modifier_marker(state, &command) {
        return bridgemodel.BRIDGE_STATUS_INVALID_ARGUMENT
    }
    output: modifier.Modifier_Output_Buffer
    status := modifier.evaluate_modifier(request, &output)
    assert(status == .Ok)
    for index in 0..<output.count {
        value := &output.outputs[index]
        if value.kind == .Set_Conic_Sample {
            apply_native_conic_output(state, value, true)
        } else {
            apply_native_modifier_output(state, value)
        }
    }
    return bridgemodel.BRIDGE_STATUS_OK
}
