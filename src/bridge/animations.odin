package bridge

import "../julialib"
import "../core"
import "../files"
import "../kine"

import "core:encoding/uuid"
import "core:fmt"
import "core:strings"

SCRATCHPAD_ANIMATION_NAME :: "Scratchpad"

//   Invoke Julia-side script initialization and optional null-animation init hook.
//
// Parameters:
//   - state: Global runtime state passed through to Julia callback entry points.
//
// Notes:
//   - Julia exceptions are reported and the call returns early without panicking.
init_euclid_scripts :: proc(
    state: ^core.Euclid_General_State) {

    state_value := julialib.jl_box_voidpointer(state)

    julialib.jl_call1(state^.julia_interface^.init_scripts, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("init_euclid_scripts")
        return
    }

    if state^.julia_interface^.null_animation.initiate != nil {
        julialib.jl_call1(state^.julia_interface^.null_animation.initiate, state_value)
        if julialib.jl_exception_occurred() != nil {
            print_julia_exception("init_euclid_scripts")
            return
        }
    }

    if state^.julia_interface^.selected_animation_index < 0 {
        select_default_animation(state)
    }
}

//  Perform a single animation frame update for the julia system, including
//  updating the state, hot-reloading julia code and assets, etc. as required.
//
// Parameters:
//   - state: Global runtime state containing Julia interface selection and cooldown state.
//   - dt: Fixed-step delta used for reset cooldown countdown.
//
// Notes:
//   - Julia exceptions are logged and ignored for this step.
perform_animation_frame :: proc(
    state: ^core.Euclid_General_State, dt: f32) {

    update_running_animations(state, dt)
    call_global_euclid_loop(state, dt)
    call_current_animation_loop(state, dt)
}

//   Fetch UI view text from the active Julia animation callback.
//
// Parameters:
//   - state: Global runtime state forwarded to the animation text callback.
//
// Returns:
//   - Cloned text for immediate UI consumption.
//   - Empty string when callback is unavailable, returns nil, or throws an exception.
call_current_animation_get_view_text :: proc(
    state: ^core.Euclid_General_State) -> string {

    if state^.julia_interface^.current_animation == nil ||
        state^.julia_interface^.current_animation^.get_view_text == nil {
        return ""
    }

    state_value := julialib.jl_box_voidpointer(state)

    result := julialib.jl_call1(
        state^.julia_interface^.current_animation^.get_view_text, state_value)

    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Current animation get view text")
        return ""
    }
    if result == nil {
        return ""
    }

    return strings.clone(string(julialib.jl_string_ptr(result)), context.temp_allocator)
}

//   Update animation lifecycle state, hot-reload assets if changed, and process animation switches/resets.
//
// Parameters:
//   - state: Global runtime state containing Julia interface selection and cooldown state.
//   - dt: Fixed-step delta used for reset cooldown countdown.
//
// Notes:
//   - Applies animation reset cooldown gating to prevent immediate repeated resets.
update_running_animations :: proc(
    state: ^core.Euclid_General_State, dt: f32) {

    reload_packaged_assets_if_updated(state)

    if state^.julia_interface^.animation_reset_cooldown_remaining > 0 {
        state^.julia_interface^.animation_reset_cooldown_remaining -= dt
        if state^.julia_interface^.animation_reset_cooldown_remaining < 0 {
            state^.julia_interface^.animation_reset_cooldown_remaining = 0
        }
    }

    switched_animation := false
    if state^.julia_interface^.selected_animation_index !=
        state^.julia_interface^.current_animation_index {
        previous_animation_index := state^.julia_interface^.current_animation_index
        change_current_animation_loop(state, state^.julia_interface^.selected_animation_index)
        switched_animation =
            state^.julia_interface^.current_animation_index == state^.julia_interface^.selected_animation_index &&
            state^.julia_interface^.current_animation_index != previous_animation_index
    }

    if state^.julia_interface^.pending_animation_reset &&
        state^.julia_interface^.current_animation_index == state^.julia_interface^.selected_animation_index {
        if switched_animation {
            state^.julia_interface^.pending_animation_reset = false
        } else {
            if state^.julia_interface^.animation_reset_cooldown_remaining <= 0 {
                reset_current_animation_loop(state)
                state^.julia_interface^.animation_reset_cooldown_remaining = ANIMATION_RESET_MIN_INTERVAL
                state^.julia_interface^.pending_animation_reset = false
            }
        }
    }
}

//   Execute the Julia global loop callback for one simulation step.
//
// Parameters:
//   - state: Global runtime state forwarded to Julia.
//   - dt: Step delta forwarded to Julia global loop.
//
// Notes:
//   - Julia exceptions are logged and ignored for this step.
call_global_euclid_loop :: proc(
    state: ^core.Euclid_General_State, dt: f32) {

    state_value := julialib.jl_box_voidpointer(state)
    dt_value := julialib.jl_box_float32(dt)

    julialib.jl_call2(state^.julia_interface^.global_loop, state_value, dt_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("global_euclid_loop")
        return
    }
}

//   Execute the currently selected Julia animation loop callback for one simulation step.
//
// Parameters:
//   - state: Global runtime state forwarded to the current animation loop.
//   - dt: Step delta forwarded to the current animation loop.
//
// Notes:
//   - No-op when the current animation has no loop callback.
//   - Julia exceptions are logged and ignored for this step.
call_current_animation_loop :: proc(
    state: ^core.Euclid_General_State, dt: f32) {

    if state^.julia_interface^.current_animation == nil {
        return
    }

    if state^.julia_interface^.current_animation.loop == nil {
        return
    }

    state_value := julialib.jl_box_voidpointer(state)
    dt_value := julialib.jl_box_float32(dt)

    julialib.jl_call2(state^.julia_interface^.current_animation^.loop,
        state_value, dt_value)

    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Current animation loop")
        return
    }
}

//   Switch to a selected animation, cleaning previous state and initializing the new loop.
//
// Notes:
//   - Clears animation-owned kine data and tool visibility before initializing the target animation.
//   - Returns early when the requested index is out of range or a Julia exception occurs.
change_current_animation_loop :: proc(
    state: ^core.Euclid_General_State, newIndex: int) {

    if newIndex < -1 || newIndex >= state^.julia_interface^.next_animation_index {
        return
    }

    animation := &state^.julia_interface^.animations[newIndex]
    if newIndex < 0 {
        animation = &state^.julia_interface^.null_animation
    }

    state_value := julialib.jl_box_voidpointer(state)

    if state^.julia_interface^.current_animation != nil &&
        state^.julia_interface^.current_animation^.loop != nil {
        julialib.jl_call1(state^.julia_interface^.current_animation^.clean, state_value)

        if julialib.jl_exception_occurred() != nil {
            print_julia_exception("Cleaning previous animation loop")
            return
        }
    }

    kine.kine_clear_animation_data(state^.point_system, state^.particle_system, state^.iso_scale)
    hide_pen(state)
    hide_compass(state)
    for i in 0..<len(state^.anim_metadata) {
        state^.anim_metadata[i] = 0.0
    }
    state^.drawing_sound_enabled = true

    julialib.jl_call1(animation^.initiate, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Initiating new animation loop")
        return
    }

    state^.julia_interface^.current_animation = animation
    state^.julia_interface^.current_animation_index = newIndex
}

//   Restart the currently selected animation by running clean then initiate callbacks.
//
// Notes:
//   - No-op when the current animation does not provide a loop callback.
//   - Reuses the same state reset behavior as animation switching.
reset_current_animation_loop :: proc(
    state: ^core.Euclid_General_State) {

    if state^.julia_interface^.current_animation^.loop == nil {
        return
    }

    state_value := julialib.jl_box_voidpointer(state)

    julialib.jl_call1(state^.julia_interface^.current_animation^.clean, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Cleaning previous animation loop")
        return
    }

    kine.kine_clear_animation_data(state^.point_system, state^.particle_system, state^.iso_scale)
    hide_pen(state)
    hide_compass(state)
    for i in 0..<len(state^.anim_metadata) {
        state^.anim_metadata[i] = 0.0
    }
    state^.drawing_sound_enabled = true

    julialib.jl_call1(state^.julia_interface^.current_animation^.initiate, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Initiating new animation loop")
        return
    }
}

//   Select the first non-scratchpad animation as default selection.
select_default_animation :: proc(state: ^core.Euclid_General_State) {
    if state == nil || state^.julia_interface == nil {
        return
    }

    target_index := -1
    for i in 0..<state^.julia_interface^.next_animation_index {
        if state^.julia_interface^.animations[i].name == SCRATCHPAD_ANIMATION_NAME {
            continue
        }
        target_index = i
        break
    }
    if target_index < 0 {
        return
    }

    for i in 0..<state^.julia_interface^.next_animation_index {
        state^.julia_interface^.animations[i].is_selected = (i == target_index)
    }
    state^.julia_interface^.selected_animation_index = target_index
}

//   Clear animation registry state and reset interface selection fields to defaults.
reset_julia_interface_registry :: proc(state: ^core.Euclid_General_State) {
    clean_julia_interfaces(state)

    state^.julia_interface^.null_animation = {}
    state^.julia_interface^.current_animation = &state^.julia_interface^.null_animation
    state^.julia_interface^.current_animation_index = -1
    state^.julia_interface^.selected_animation_index = -1
    state^.julia_interface^.pending_animation_reset = false
    state^.julia_interface^.animation_reset_cooldown_remaining = 0
    state^.julia_interface^.next_animation_index = 0
}

//   Find an animation index by its registered stable UUID identity.
//
// Returns:
//   - Animation index when found.
//   - -1 when no matching UUID exists in the current registry.
find_animation_index_by_stable_id :: proc(
    state: ^core.Euclid_General_State, stable_id: uuid.Identifier) -> int {

    for i in 0..<state^.julia_interface^.next_animation_index {
        animation := state^.julia_interface^.animations[i]
        if animation.stable_id == stable_id {
            return i
        }
    }

    return -1
}

//   Restore the current animation selection after a successful script reload.
restore_current_animation_after_reload :: proc(
    state: ^core.Euclid_General_State,
    animation_stable_id: uuid.Identifier) {

    restored_index := find_animation_index_by_stable_id(state, animation_stable_id)
    if restored_index >= 0 {
        state^.julia_interface^.selected_animation_index = restored_index
        change_current_animation_loop(state, restored_index)
        return
    }

    fmt.eprintln("Julia asset reload: unable to restore animation for requested stable_id")
}

//   Detect packaged asset updates and hot-reload Julia script/interface state when changed.
//
// Notes:
//   - Preserves the current animation by name when possible after reload.
reload_packaged_assets_if_updated :: proc(state: ^core.Euclid_General_State) {
    archive_mtime, ok := files.packaged_asset_archive_modification_unix_nano()
    if !ok {
        return
    }

    if state^.julia_interface^.asset_archive_mod_time_unix_nano == 0 {
        state^.julia_interface^.asset_archive_mod_time_unix_nano = archive_mtime
        return
    }
    if archive_mtime == state^.julia_interface^.asset_archive_mod_time_unix_nano {
        return
    }

    if !files.reload_packaged_assets_root() {
        fmt.eprintln("Julia asset reload skipped: failed to re-extract assets package")
        return
    }
    if !include_packaged_script(false) {
        fmt.eprintln("Julia asset reload skipped: failed to re-include script.jl")
        return
    }

    current_animation_stable_id: uuid.Identifier
    if state^.julia_interface^.current_animation_index >= 0 &&
        state^.julia_interface^.current_animation_index < state^.julia_interface^.next_animation_index {
        active_animation := state^.julia_interface^.animations[
            state^.julia_interface^.current_animation_index]
        current_animation_stable_id = active_animation.stable_id
    }

    state^.julia_interface^.asset_archive_mod_time_unix_nano = archive_mtime
    refresh_julia_interface_handles(state)
    reset_julia_interface_registry(state)
    init_euclid_scripts(state)
    restore_current_animation_after_reload(
        state,
        current_animation_stable_id)

    // Keep Odin-side scratchpad editor buffer aligned with Julia session reset on reload.
    state^.ui_runtime.scratchpad_input_len = 0
    state^.ui_runtime.scratchpad_input_cursor = 0
    state^.ui_runtime.scratchpad_follow_output = false
}

//   Increment cycle-boundary generation counter for one-time consumer notification.
notify_animation_cycle_boundary_local :: proc(state: ^core.Euclid_General_State) {
    if state == nil {
        return
    }

    state^.cycle_boundary_generation += 1
}

//   Consume a pending cycle-boundary notification exactly once.
//
// Notes:
//   - Returns true only when a newer generation is observed and consumed.
consume_animation_cycle_boundary :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil {
        return false
    }

    if state^.consumed_cycle_boundary_generation == state^.cycle_boundary_generation {
        return false
    }

    state^.consumed_cycle_boundary_generation = state^.cycle_boundary_generation
    return true
}

//   Parse a bridge-provided animation stable UUID string into typed identity.
//
// Parameters:
//   - stable_id: Null-terminated UUID text from Julia bridge registration call.
//   - name: Animation display name used only for diagnostics.
//
// Returns:
//   - Parsed UUID identifier when successful.
//   - false when input is nil or malformed.
parse_animation_stable_id :: proc(stable_id, name: cstring) -> (uuid.Identifier, bool) {
    if stable_id == nil {
        fmt.eprintln("add animation interface failed: nil stable_id for ", string(name))
        return {}, false
    }

    stable_id_text := string(stable_id)
    id, read_error := uuid.read(stable_id_text)
    if read_error != .None {
        fmt.eprintln(
            "add animation interface failed: invalid stable_id '",
            stable_id_text,
            "' for ",
            string(name))
        return {}, false
    }

    return id, true
}

//   Find an already registered animation by stable UUID identity.
//
// Returns:
//   - Animation index when found.
//   - -1 when no matching UUID exists in the current registry.
find_registered_animation_by_stable_id :: proc(
    state: ^core.Euclid_General_State, stable_id: uuid.Identifier) -> int {

    for i in 0..<state^.julia_interface^.next_animation_index {
        if state^.julia_interface^.animations[i].stable_id == stable_id {
            return i
        }
    }

    return -1
}

//   Reject duplicate stable UUID registration before insertion.
//
// Parameters:
//   - name: New animation display name being registered.
//   - stable_id_text: Original UUID text used for diagnostics.
//   - stable_id: Parsed UUID identity candidate.
//   - parent_id: Parent animation index for child registrations, or -1 for root.
//
// Returns:
//   - true when duplicate is detected and caller should abort registration.
reject_duplicate_stable_id :: proc(
    state: ^core.Euclid_General_State,
    name, stable_id_text: cstring,
    stable_id: uuid.Identifier,
    parent_id: int) -> bool {

    existing_index := find_registered_animation_by_stable_id(state, stable_id)
    if existing_index < 0 {
        return false
    }

    existing_name := state^.julia_interface^.animations[existing_index].name
    fmt.eprintln(
        "add animation interface failed: duplicate stable_id '",
        string(stable_id_text),
        "' for ",
        string(name),
        " conflicts with existing animation index ",
        existing_index,
        " name '",
        existing_name,
        "' parent_id=",
        parent_id)
    return true
}