package bridge

import "../julialib"
import "../core"

import "core:strings"

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
//   - Index of the inserted animation interface entry.
@(export)
add_root_animation_interface :: proc "c" (
    state : ^core.Euclid_General_State,
    getViewText, init, loop, clean : ^julialib.jl_value_t,
    name, stable_id : cstring) -> int {

    context = state^.saved_context

    parsed_stable_id, ok := parse_animation_stable_id(stable_id, name)
    if !ok {
        return -1
    }
    if reject_duplicate_stable_id(state, name, stable_id, parsed_stable_id, -1) {
        return -1
    }

    newIndex := state^.julia_interface^.next_animation_index
    state^.julia_interface^.next_animation_index += 1

    animation := &state^.julia_interface^.animations[newIndex]

    animation^.get_view_text = getViewText
    animation^.initiate = init
    animation^.loop = loop
    animation^.clean = clean
    animation^.name = strings.clone(string(name))
    animation^.stable_id = parsed_stable_id
    animation^.first_child_id = -1
    animation^.parent_id = -1
    animation^.next_sibling = -1

    return newIndex
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
//   - parentId: Parent animation index that receives the new child animation entry.
//
// Returns:
//   - Index of the inserted child animation when parentId is valid.
//   - -1 when parentId does not reference a registered animation.
@(export)
add_child_animation_interface :: proc "c" (
    state : ^core.Euclid_General_State,
    getViewText, init, loop, clean : ^julialib.jl_value_t,
    name, stable_id : cstring,
    parentId : int) -> int {

    if parentId < 0 || parentId >= state^.julia_interface^.next_animation_index {
        return -1
    }

    context = state^.saved_context

    parsed_stable_id, ok := parse_animation_stable_id(stable_id, name)
    if !ok {
        return -1
    }
    if reject_duplicate_stable_id(state, name, stable_id, parsed_stable_id, parentId) {
        return -1
    }

    newIndex := state^.julia_interface^.next_animation_index
    state^.julia_interface^.next_animation_index += 1

    parentAnimation := &state^.julia_interface^.animations[parentId]
    lastChildId := parentAnimation^.first_child_id
    if lastChildId < 0 {
        parentAnimation^.first_child_id = newIndex
    } else {
        reviewChild := &state^.julia_interface^.animations[lastChildId]
        for reviewChild^.next_sibling >= 0 {
            lastChildId = reviewChild^.next_sibling
            reviewChild = &state^.julia_interface^.animations[lastChildId]
        }
        reviewChild^.next_sibling = newIndex
    }

    animation := &state^.julia_interface^.animations[newIndex]

    animation^.get_view_text = getViewText
    animation^.initiate = init
    animation^.loop = loop
    animation^.clean = clean
    animation^.name = strings.clone(string(name))
    animation^.stable_id = parsed_stable_id
    animation^.first_child_id = -1
    animation^.parent_id = parentId
    animation^.next_sibling = -1

    return newIndex
}

//   Mark that an animation cycle boundary occurred so host-side systems can consume it once.
//
// Parameters:
//   - state: Global runtime state passed from the host application.
@(export)
notify_animation_cycle_boundary :: proc "c" (state: ^core.Euclid_General_State) {
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

