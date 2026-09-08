package bridge

import "../core"

//   Decode the stable ABI MIME value into its native representation.
presentation_mime_from_abi :: proc(value: i32) -> (core.Presentation_Mime, bool) {
    switch value {
    case 0:
        return .Text_Plain, true
    case 1:
        return .Text_Latex, true
    }
    return {}, false
}

//   Map presentation transport outcomes onto the stable bridge status contract.
presentation_bridge_status :: proc(outcome: core.Communication_Send_Outcome) -> i32 {
    switch outcome {
    case .Sent, .Queue_Full:
        return BRIDGE_STATUS_OK
    case .Allocation_Failed:
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    case .Runtime_Stopping, .Channel_Closed:
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    return BRIDGE_STATUS_ILLEGAL_STATE
}

//   Publish exact MIME-bearing bytes through the Julia-owned egress link.
@(export)
publish_presented_text :: proc "c" (
    state: ^core.Euclid_General_State, mime_value: i32,
    source: rawptr, byte_count: i32) -> i32 {
    if state == nil || state^.julia_runtime_service == nil ||
        state^.julia_interface == nil {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    if byte_count < 0 || byte_count > i32(core.PRESENTATION_MAX_SOURCE_BYTES) ||
        (source == nil && byte_count > 0) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state^.saved_context
    mime, valid_mime := presentation_mime_from_abi(mime_value)
    if !valid_mime {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    payload: []u8
    if byte_count > 0 {
        source_bytes := cast([^]u8)source
        payload = source_bytes[:int(byte_count)]
    }
    return presentation_bridge_status(send_presented_text(state, mime, payload))
}
