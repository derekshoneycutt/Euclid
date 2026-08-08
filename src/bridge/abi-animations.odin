package bridge

import "../julialib"
import "../core"

//   Register Julia callbacks that define the null/default animation behavior.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - getViewText: Julia function pointer used to bind animation callback behavior.
//   - init: Julia function pointer used to bind animation callback behavior.
//   - loop: Julia function pointer used to bind animation callback behavior.
//   - clean: Julia function pointer used to bind animation callback behavior.
@(export)
set_null_animations :: proc "c" (
    state: ^core.Euclid_General_State,
    getViewText, init, loop, clean: ^julialib.jl_value_t) {
    
    state^.julia_interface^.null_animation.get_view_text = getViewText
    state^.julia_interface^.null_animation.initiate = init
    state^.julia_interface^.null_animation.loop = loop
    state^.julia_interface^.null_animation.clean = clean
}

//   Register a top-level animation interface entry in the Julia animation registry.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
//   - getViewText: Julia function pointer used to bind animation callback behavior.
//   - init: Julia function pointer used to bind animation callback behavior.
//   - loop: Julia function pointer used to bind animation callback behavior.
//   - clean: Julia function pointer used to bind animation callback behavior.
//   - name: Null-terminated animation label string from Julia.
//   - stable_id: Null-terminated UUID identity string for restore/persistence.
//
// Returns:
//   - 1 when inserted successfully.
//   - -1 when validation or insertion fails.
@(export)
add_root_animation_interface :: proc "c" (
    state : ^core.Euclid_General_State,
    getViewText, init, loop, clean : ^julialib.jl_value_t,
    name, stable_id : cstring) -> int {

    context = state^.saved_context

    parsed_stable_id, parsed_ok := parse_animation_stable_id(stable_id, name)
    if !parsed_ok {
        return -1
    }
    if reject_duplicate_stable_id(state, name, stable_id, parsed_stable_id, "") {
        return -1
    }

    _, inserted := add_animation_to_registry(
        state,
        getViewText,
        init,
        loop,
        clean,
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
//   - getViewText: Julia function pointer used to bind animation callback behavior.
//   - init: Julia function pointer used to bind animation callback behavior.
//   - loop: Julia function pointer used to bind animation callback behavior.
//   - clean: Julia function pointer used to bind animation callback behavior.
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
    getViewText, init, loop, clean : ^julialib.jl_value_t,
    name, stable_id : cstring,
    parent_stable_id: cstring) -> int {

    context = state^.saved_context

    parent, ok := resolve_parent_animation_by_stable_id(state, parent_stable_id)
    if !ok {
        return -1
    }

    parsed_stable_id, parsed_ok := parse_animation_stable_id(stable_id, name)
    if !parsed_ok {
        return -1
    }
    if reject_duplicate_stable_id(state, name, stable_id, parsed_stable_id, parent_stable_id) {
        return -1
    }

    _, inserted := add_animation_to_registry(
        state,
        getViewText,
        init,
        loop,
        clean,
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

