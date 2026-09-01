package bridge

import "../julialib"
import "../core"

// Carry one animation key and deterministic schema identity across the C ABI.
Animation_Value_Abi_Identity :: struct {
    key : u64,
    schema_low : u64,
    schema_high : u64,
}

//   Convert a canonical animation-value result to its stable bridge status.
animation_value_bridge_status :: proc "contextless" (
    status: core.Animation_Value_Status) -> i32 {
    switch status {
    case .Ok:
        return BRIDGE_STATUS_OK
    case .Invalid_Argument:
        return BRIDGE_STATUS_INVALID_ARGUMENT
    case .Illegal_State:
        return BRIDGE_STATUS_ILLEGAL_STATE
    case .Not_Found:
        return BRIDGE_STATUS_NOT_FOUND
    case .Schema_Mismatch:
        return BRIDGE_STATUS_SCHEMA_MISMATCH
    case .Out_Of_Capacity, .Allocation_Failed:
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    return BRIDGE_STATUS_ILLEGAL_STATE
}

//   Build the canonical identity for the host's active animation generation.
animation_value_identity :: proc "contextless" (
    state: ^core.Euclid_General_State,
    identity_abi: Animation_Value_Abi_Identity) -> core.Animation_Value_Identity {
    return {
        generation = state^.animation_values.generation,
        key = identity_abi.key,
        schema_low = identity_abi.schema_low,
        schema_high = identity_abi.schema_high,
    }
}

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
    identity_abi: Animation_Value_Abi_Identity,
    source: rawptr,
    byte_count: i32) -> i32 {
    if state == nil {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    if source == nil || byte_count <= 0 ||
        byte_count > i32(core.ANIMATION_VALUE_MAX_PAYLOAD_BYTES) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state^.saved_context
    identity := animation_value_identity(state, identity_abi)
    source_bytes := cast([^]u8)source
    payload := source_bytes[:int(byte_count)]
    if state^.scene_command_batch_target != nil {
        if state^.animation_query_snapshot_target == nil {
            return BRIDGE_STATUS_ILLEGAL_STATE
        }
        return animation_value_bridge_status(core.animation_value_pending_append(
            &state^.scene_command_batch_target^.animation_value_writes,
            identity,
            payload))
    }
    if state^.animation_query_snapshot_target != nil {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    return animation_value_bridge_status(core.animation_value_store_set(
        &state^.animation_values, identity, payload))
}

//   Copy one canonical opaque value into Julia-owned destination storage.
//
// Parameters:
//   - state: Live host state in a synchronous animation lifecycle callback.
//   - identity: Existing key and exact bound 128-bit schema identity.
//   - destination: Julia-owned bytes valid only for this call.
//   - byte_count: Exact positive destination size.
//
// Returns:
//   - Stable `BRIDGE_STATUS_*`; destination changes only on success.
get_animation_query_value :: proc(
    state: ^core.Euclid_General_State,
    identity: core.Animation_Value_Identity,
    payload: []u8) -> i32 {
    if state^.scene_command_batch_target == nil ||
        !state^.animation_query_snapshot_target^.animation_values_valid {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    status := core.animation_value_pending_copy(
        &state^.scene_command_batch_target^.animation_value_writes,
        identity,
        payload)
    if status != .Not_Found {
        return animation_value_bridge_status(status)
    }
    return animation_value_bridge_status(core.animation_value_snapshot_copy(
        &state^.animation_query_snapshot_target^.animation_values,
        identity,
        payload))
}

//   Copy one opaque value from the active query snapshot and staged writes.
@(export)
get_animation_value :: proc "c" (
    state: ^core.Euclid_General_State,
    identity_abi: Animation_Value_Abi_Identity,
    destination: rawptr,
    byte_count: i32) -> i32 {
    if state == nil {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    if destination == nil || byte_count <= 0 ||
        byte_count > i32(core.ANIMATION_VALUE_MAX_PAYLOAD_BYTES) {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    context = state^.saved_context
    identity := animation_value_identity(state, identity_abi)
    destination_bytes := cast([^]u8)destination
    payload := destination_bytes[:int(byte_count)]
    if state^.animation_query_snapshot_target != nil {
        return get_animation_query_value(state, identity, payload)
    }
    if state^.scene_command_batch_target != nil {
        return BRIDGE_STATUS_ILLEGAL_STATE
    }
    return animation_value_bridge_status(core.animation_value_store_copy(
        &state^.animation_values, identity, payload))
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
    
    state^.julia_interface^.null_animation.entry = entry
}

//   Register a top-level animation interface entry in the Julia animation registry.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - entry: Julia callable implementing Enter, Tick, and Exit operations.
//   - name: Null-terminated animation label string from Julia.
//   - stable_id: Null-terminated UUID identity string for restore/persistence.
//
// Returns:
//   - 1 when inserted successfully.
//   - -1 when validation or insertion fails.
@(export)
add_root_animation_interface :: proc "c" (
    state : ^core.Euclid_General_State,
    entry: ^julialib.jl_value_t,
    name, stable_id : cstring) -> int {

    context = state^.saved_context

    if entry == nil {
        return -1
    }

    parsed_stable_id, parsed_ok := parse_animation_stable_id(stable_id, name)
    if !parsed_ok {
        return -1
    }
    if reject_duplicate_stable_id(state, name, stable_id, parsed_stable_id, "") {
        return -1
    }

    _, inserted := add_animation_to_registry(
        state,
        entry,
        name,
        parsed_stable_id,
        nil)
    if !inserted {
        return -1
    }

    return 1
}

//   Register a child animation interface and link it under an existing parent animation.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - entry: Julia callable implementing Enter, Tick, and Exit operations.
//   - name: Null-terminated animation label string from Julia.
//   - stable_id: Null-terminated UUID identity string for restore/persistence.
//   - parent_stable_id: Parent animation UUID string that receives the new child entry.
//
// Returns:
//   - 1 when inserted successfully.
//   - -1 when parent_stable_id does not reference a registered animation.
@(export)
add_child_animation_interface :: proc "c" (
    state : ^core.Euclid_General_State,
    entry: ^julialib.jl_value_t,
    name, stable_id : cstring,
    parent_stable_id: cstring) -> int {

    context = state^.saved_context

    if entry == nil {
        return -1
    }

    parent, ok := resolve_parent_animation_by_stable_id(state, parent_stable_id)
    if !ok {
        return -1
    }

    parsed_stable_id, parsed_ok := parse_animation_stable_id(stable_id, name)
    if !parsed_ok {
        return -1
    }
    if reject_duplicate_stable_id(state, name, stable_id, parsed_stable_id,
        parent_stable_id) {
        return -1
    }

    _, inserted := add_animation_to_registry(
        state,
        entry,
        name,
        parsed_stable_id,
        parent)
    if !inserted {
        return -1
    }

    return 1
}

//   Mark that an animation cycle boundary occurred so host-side systems can consume it once.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
notify_animation_cycle_boundary :: proc "c" (state: ^core.Euclid_General_State) {
    _, captured := append_scene_command(state, .Notify_Animation_Cycle_Boundary)
    if captured {
        return
    }
    context = state^.saved_context
    notify_animation_cycle_boundary_local(state)
}

//   Return the bridge ABI version expected by Julia-side integration code.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_bridge_version :: proc "c" () -> i32 {
    return BRIDGE_VERSION
}

//   Return bridge feature flags that advertise optional ABI capabilities.
//
// Returns:
//   - Bridge integer value for the requested capability, index, or status code.
@(export)
get_bridge_feature_flags :: proc "c" () -> i32 {
    return BRIDGE_FEATURE_FLAGS
}

