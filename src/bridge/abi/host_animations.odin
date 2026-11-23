package bridge_abi

import host "../host"
import core "../../core"
import julialib "../../../libs/julia/bindings"

//   Copy one Julia-owned opaque value into canonical animation storage.
//
// Parameters:
//   - state: Live host state in a synchronous animation lifecycle callback.
//   - identity: Nonzero key and deterministic 128-bit Julia schema identity.
//   - source: Julia-owned bytes valid only for this call.
//   - byte_count: Exact positive payload size.
//
// Returns:
//   - Stable `BRIDGE_STATUS_*`; the source pointer is never retained.
@(export)
set_animation_value :: proc "c" (
    state: ^core.Euclid_General_State,
    identity_abi: host.Animation_Value_Abi_Identity,
    source: ^u8,
    byte_count: i32) -> i32 {
    return host.set_animation_value(state, identity_abi, source, byte_count)
}

//   Copy one opaque value from the active query snapshot and staged writes.
@(export)
get_animation_value :: proc "c" (
    state: ^core.Euclid_General_State,
    identity_abi: host.Animation_Value_Abi_Identity,
    destination: ^u8,
    byte_count: i32) -> i32 {
    return host.get_animation_value(state, identity_abi, destination, byte_count)
}

//   Register the Julia entry that defines null/default animation behavior.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - entry: Julia callable implementing Enter, Tick, and Exit operations.
@(export)
set_null_animations :: proc "c" (
    state: ^core.Euclid_General_State,
    entry: ^julialib.jl_value_t) {
    host.set_null_animations(state, entry)
}

// Copy a generation-local implementation path and report its required byte count.
@(export)
copy_animation_implementation_path :: proc "c" (
    state: ^core.Euclid_General_State,
    stable_id: cstring,
    destination: ^u8,
    destination_capacity: i32,
    metadata: ^host.Animation_Implementation_Path_Metadata) -> i32 {
    return host.copy_animation_implementation_path(
        state, stable_id, destination, destination_capacity, metadata)
}

//   Mark that an animation cycle boundary occurred so host-side systems can consume it once.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
notify_animation_cycle_boundary :: proc "c" (state: ^core.Euclid_General_State) {
    host.notify_animation_cycle_boundary(state)
}

// Capture native motion; curve setup alone may use the quiesced lifecycle handoff.
@(export)
apply_native_modifier :: proc "c" (
    state: ^core.Euclid_General_State,
    request_abi: host.Bridge_Native_Modifier_Request) -> i32 {
    return host.apply_native_modifier(state, request_abi)
}

//   Return the bridge ABI version expected by Julia-side integration code.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_bridge_version :: proc "c" () -> i32 {
    return host.get_bridge_version()
}

//   Return bridge feature flags that advertise optional ABI capabilities.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_bridge_feature_flags :: proc "c" () -> i32 {
    return host.get_bridge_feature_flags()
}
