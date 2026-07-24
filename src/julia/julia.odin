package julia


// Julia module provides the Odin-Julia Bridge to coordinate all actions between the 2
// languages. The functions in this file are the Odin side, providing all that is
// needed to initiate the Julia system and load the script files from Odin. The Bridge
// provides all methods that reach into Julia, and the types that are sent back and forth.

import "../core"
import "../files"
import "../particles"
import "../kine"

import "base:runtime"
import "core:encoding/uuid"
import "core:fmt"
import "core:math"
import "core:strings"

LABEL_DUST_X_OFFSET :: -0.01
LABEL_DUST_Y_OFFSET :: -0.03
SCRATCHPAD_ANIMATION_NAME :: "Scratchpad"
SCRATCHPAD_PARSE_ERROR :: i32(0)
SCRATCHPAD_PARSE_INCOMPLETE :: i32(1)
SCRATCHPAD_PARSE_COMPLETE :: i32(2)

//   Initialize the Julia runtime and load the packaged bridge script into Main.
//
// Notes:
//   - Intended to be called once during application startup before Julia bridge calls.
//   - Exits immediately if packaged script include fails.
initiate_julia :: proc() {
    jl_init()

    _ = include_packaged_script(true)
}

//   Shut down the Julia runtime and flush Julia-side teardown hooks.
//
// Notes:
//   - Should be paired with initiate_julia at application shutdown.
end_julia :: proc() {
    jl_atexit_hook(0)
}

//   Allocate and initialize the host-side Julia interface handle table.
//
// Returns:
//   - Pointer to a newly allocated interface struct with resolved core Julia callbacks when available.
//   - A valid allocation is returned even if Main cannot be resolved; callback slots remain unset in that case.
retrieve_interface :: proc() -> ^core.Euclid_Julia_Interface {
    ret := new(core.Euclid_Julia_Interface)

    main_module := resolve_main_module()
    if main_module == nil {
        return ret
    }

    ret.init_scripts = jl_get_function(main_module, "init_euclid_scripts")
    ret.global_loop = jl_get_function(main_module, "global_euclid_loop")
    ret.scratchpad_classify_input = jl_get_function(
        main_module, "scratchpad_classify_input")
    ret.scratchpad_queue_input = jl_get_function(
        main_module, "scratchpad_queue_input")
    ret.scratchpad_save_history_to_file = jl_get_function(
        main_module, "scratchpad_save_history_to_file")
    ret.scratchpad_history_previous = jl_get_function(
        main_module, "scratchpad_history_previous")
    ret.scratchpad_history_next = jl_get_function(
        main_module, "scratchpad_history_next")
    ret.scratchpad_history_reset_cursor = jl_get_function(
        main_module, "scratchpad_history_reset_cursor")
    ret.asset_archive_mod_time_unix_nano = 0
    ret.current_animation_index = -1
    ret.selected_animation_index = -1
    ret.animation_reset_cooldown_remaining = 0

    return ret
}

//   Release owned animation-name strings registered in the Julia interface table.
//
// Parameters:
//   - state: Global runtime state whose Julia interface registry is being cleared.
//
// Notes:
//   - This frees only cloned name storage; it does not free the interface struct itself.
clean_julia_interfaces :: proc(state: ^core.Euclid_General_State) {
    for i in 0..<state^.julia_interface^.next_animation_index {
        animation := state^.julia_interface^.animations[i]
        delete(animation.name)
    }
}

//   Invoke Julia-side script initialization and optional null-animation init hook.
//
// Parameters:
//   - state: Global runtime state passed through to Julia callback entry points.
//
// Notes:
//   - Julia exceptions are reported and the call returns early without panicking.
init_euclid_scripts :: proc(
    state: ^core.Euclid_General_State) {

    state_value := jl_box_voidpointer(state)

    jl_call1(state^.julia_interface^.init_scripts, state_value)
    if jl_exception_occurred() != nil {
        print_julia_exception("init_euclid_scripts")
        return
    }

    if state^.julia_interface^.null_animation.initiate != nil {
        jl_call1(state^.julia_interface^.null_animation.initiate, state_value)
        if jl_exception_occurred() != nil {
            print_julia_exception("init_euclid_scripts")
            return
        }
    }

    if state^.julia_interface^.selected_animation_index < 0 {
        select_default_animation(state)
    }
}

//   Classify scratchpad text as parse-error/incomplete/complete.
//
// Returns:
//   - SCRATCHPAD_PARSE_ERROR when input has syntax errors.
//   - SCRATCHPAD_PARSE_INCOMPLETE when input is a valid prefix.
//   - SCRATCHPAD_PARSE_COMPLETE when input is complete.
scratchpad_classify_input :: proc(
    state: ^core.Euclid_General_State, text: string) -> i32 {

    if state == nil || state^.julia_interface == nil {
        return SCRATCHPAD_PARSE_ERROR
    }
    if state^.julia_interface^.scratchpad_classify_input == nil {
        return SCRATCHPAD_PARSE_ERROR
    }

    state_value := jl_box_voidpointer(state)
    text_c := strings.clone_to_cstring(text, context.temp_allocator)
    text_value := jl_cstr_to_string(text_c)
    result := jl_call2(state^.julia_interface^.scratchpad_classify_input,
        state_value, text_value)

    if jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_classify_input")
        return SCRATCHPAD_PARSE_ERROR
    }

    return i32(jl_unbox_int32(result))
}

//   Queue a complete scratchpad input for one-per-frame execution.
//
// Returns:
//   - true when queued successfully.
//   - false when queueing fails.
scratchpad_queue_input :: proc(
    state: ^core.Euclid_General_State, text: string) -> bool {

    if state == nil || state^.julia_interface == nil {
        return false
    }
    if state^.julia_interface^.scratchpad_queue_input == nil {
        return false
    }

    state_value := jl_box_voidpointer(state)
    text_c := strings.clone_to_cstring(text, context.temp_allocator)
    text_value := jl_cstr_to_string(text_c)
    result := jl_call2(state^.julia_interface^.scratchpad_queue_input,
        state_value, text_value)

    if jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_queue_input")
        return false
    }

    return jl_unbox_bool(result) != 0
}

//   Save scratchpad history entries to a file path through Julia runtime.
//
// Returns:
//   - true when history is written successfully.
//   - false when bridge callback is unavailable or writing fails.
scratchpad_save_history_to_file :: proc(
    state: ^core.Euclid_General_State, path: string) -> bool {

    if state == nil || state^.julia_interface == nil {
        return false
    }
    if state^.julia_interface^.scratchpad_save_history_to_file == nil {
        return false
    }

    state_value := jl_box_voidpointer(state)
    path_c := strings.clone_to_cstring(path, context.temp_allocator)
    path_value := jl_cstr_to_string(path_c)
    result := jl_call2(state^.julia_interface^.scratchpad_save_history_to_file,
        state_value, path_value)

    if jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_save_history_to_file")
        return false
    }

    return jl_unbox_bool(result) != 0
}

//   Move scratchpad history cursor one step backward and return suggested input.
scratchpad_history_previous :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_interface == nil {
        return ""
    }
    if state^.julia_interface^.scratchpad_history_previous == nil {
        return ""
    }

    state_value := jl_box_voidpointer(state)
    result := jl_call1(
        state^.julia_interface^.scratchpad_history_previous, state_value)

    if jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_history_previous")
        return ""
    }

    return strings.clone(string(jl_string_ptr(result)), context.temp_allocator)
}

//   Move scratchpad history cursor one step forward and return suggested input.
scratchpad_history_next :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_interface == nil {
        return ""
    }
    if state^.julia_interface^.scratchpad_history_next == nil {
        return ""
    }

    state_value := jl_box_voidpointer(state)
    result := jl_call1(state^.julia_interface^.scratchpad_history_next, state_value)

    if jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_history_next")
        return ""
    }

    return strings.clone(string(jl_string_ptr(result)), context.temp_allocator)
}

//   Reset scratchpad history cursor to the position after the most recent entry.
scratchpad_history_reset_cursor :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_interface == nil {
        return false
    }
    if state^.julia_interface^.scratchpad_history_reset_cursor == nil {
        return false
    }

    state_value := jl_box_voidpointer(state)
    result := jl_call1(
        state^.julia_interface^.scratchpad_history_reset_cursor, state_value)

    if jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_history_reset_cursor")
        return false
    }

    return jl_unbox_bool(result) != 0
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

    state_value := jl_box_voidpointer(state)

    result := jl_call1(
        state^.julia_interface^.current_animation^.get_view_text, state_value)

    if jl_exception_occurred() != nil {
        print_julia_exception("Current animation get view text")
        return ""
    }
    if result == nil {
        return ""
    }

    return strings.clone(string(jl_string_ptr(result)), context.temp_allocator)
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

    state_value := jl_box_voidpointer(state)
    dt_value := jl_box_float32(dt)

    jl_call2(state^.julia_interface^.global_loop, state_value, dt_value)
    if jl_exception_occurred() != nil {
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

    state_value := jl_box_voidpointer(state)
    dt_value := jl_box_float32(dt)

    jl_call2(state^.julia_interface^.current_animation^.loop,
        state_value, dt_value)

    if jl_exception_occurred() != nil {
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
    
    state_value := jl_box_voidpointer(state)

    if state^.julia_interface^.current_animation != nil &&
        state^.julia_interface^.current_animation^.loop != nil {
        jl_call1(state^.julia_interface^.current_animation^.clean, state_value)
    
        if jl_exception_occurred() != nil {
            print_julia_exception("Cleaning previous animation loop")
            return
        }
    }
    
    kine.kine_clear_animation_data(state^.point_system, state^.particle_system)
    hide_pen(state)
    hide_compass(state)
    for i in 0..<len(state^.anim_metadata) {
        state^.anim_metadata[i] = 0.0
    }

   jl_call1(animation^.initiate, state_value)
    if jl_exception_occurred() != nil {
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
    
    state_value := jl_box_voidpointer(state)

   jl_call1(state^.julia_interface^.current_animation^.clean, state_value)
    if jl_exception_occurred() != nil {
        print_julia_exception("Cleaning previous animation loop")
        return
    }
    
    kine.kine_clear_animation_data(state^.point_system, state^.particle_system)
    hide_pen(state)
    hide_compass(state)
    for i in 0..<len(state^.anim_metadata) {
        state^.anim_metadata[i] = 0.0
    }
    
   jl_call1(state^.julia_interface^.current_animation^.initiate, state_value)
    if jl_exception_occurred() != nil {
        print_julia_exception("Initiating new animation loop")
        return
    }
}

//   Resolve Julia Main module handle used for bridge function lookup.
resolve_main_module :: proc() -> ^jl_module_t {
    main_value := jl_eval_string("Main")
    if main_value == nil || jl_exception_occurred() != nil {
        return nil
    }
    return (^jl_module_t)(main_value)
}

//   Resolve Julia Base module handle used for exception formatting.
resolve_base_module :: proc() -> ^jl_module_t {
    base_value := jl_eval_string("base")
    if base_value == nil || jl_exception_occurred() != nil {
        return nil
    }
    return (^jl_module_t)(base_value)
}

//   Return false for include failure and exit the process when configured.
include_packaged_script_failure :: proc(exit_on_failure: bool) -> bool {
    if exit_on_failure {
        runtime.exit(1)
    }

    return false
}

//   Resolve the packaged Julia script path needed for Main.include.
resolve_packaged_script_include_path :: proc(exit_on_failure: bool) -> (string, bool) {
    script_path := files.packaged_asset_path("julia/script.jl", context.temp_allocator)
    if len(script_path) == 0 {
        fmt.eprintln("Failed to resolve packaged Julia script path.")
        fmt.eprintln("Expected assets package directory next to executable: assets.pkg")
        return "", include_packaged_script_failure(exit_on_failure)
    }

    return script_path, true
}

//   Resolve the Main.include function used to load packaged Julia scripts.
resolve_main_include_function :: proc(exit_on_failure: bool) -> (^jl_value_t, bool) {
    main_module := resolve_main_module()
    if main_module == nil {
        fmt.eprintln("Failed to resolve Julia Main module.")
        return nil, include_packaged_script_failure(exit_on_failure)
    }

    include_fn := jl_get_function(main_module, "include")
    if include_fn == nil {
        fmt.eprintln("Failed to resolve Julia include function from Main.")
        return nil, include_packaged_script_failure(exit_on_failure)
    }

    return include_fn, true
}

//   Call Main.include on the packaged Julia entry script path.
call_include_packaged_script :: proc(
    include_fn: ^jl_value_t,
    script_path: string,
    exit_on_failure: bool) -> bool {

    script_cstr := strings.clone_to_cstring(script_path, context.temp_allocator)
    script_value := jl_cstr_to_string(script_cstr)
    include_result := jl_call1(include_fn, script_value)
    if jl_exception_occurred() != nil || include_result == nil {
        fmt.eprintln("Failed to initialize Julia scripts via Main.include(path).")
        fmt.eprintln("Resolved script path: ", script_path)
        fmt.eprintln("Verify assets.pkg/julia/script.jl exists next to the executable.")
        print_julia_exception("initiate_julia include assets.pkg/julia/script.jl")
        return include_packaged_script_failure(exit_on_failure)
    }

    return true
}

//   Include the packaged Julia entry script through Main.include and report failures.
//
// Notes:
//   - When exit_on_failure is true, unrecoverable include errors terminate the process.
include_packaged_script :: proc(exit_on_failure: bool) -> bool {
    script_path, path_ok := resolve_packaged_script_include_path(exit_on_failure)
    if !path_ok {
        return false
    }

    include_fn, include_ok := resolve_main_include_function(exit_on_failure)
    if !include_ok {
        return false
    }

    return call_include_packaged_script(include_fn, script_path, exit_on_failure)
}

//   Refresh cached Julia callback handles after script reload.
refresh_julia_interface_handles :: proc(state: ^core.Euclid_General_State) {
    main_module := resolve_main_module()
    if main_module == nil {
        return
    }

    state^.julia_interface^.init_scripts = jl_get_function(main_module, "init_euclid_scripts")
    state^.julia_interface^.global_loop = jl_get_function(main_module, "global_euclid_loop")
    state^.julia_interface^.scratchpad_classify_input = jl_get_function(
        main_module, "scratchpad_classify_input")
    state^.julia_interface^.scratchpad_queue_input = jl_get_function(
        main_module, "scratchpad_queue_input")
    state^.julia_interface^.scratchpad_save_history_to_file = jl_get_function(
        main_module, "scratchpad_save_history_to_file")
    state^.julia_interface^.scratchpad_history_previous = jl_get_function(
        main_module, "scratchpad_history_previous")
    state^.julia_interface^.scratchpad_history_next = jl_get_function(
        main_module, "scratchpad_history_next")
    state^.julia_interface^.scratchpad_history_reset_cursor = jl_get_function(
        main_module, "scratchpad_history_reset_cursor")
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

//   Return whether a point index is within runtime point capacity bounds.
is_point_index_in_bounds :: #force_inline proc(index: int) -> bool {
    return index >= 0 && index < MAX_KINEPOINTS
}

//   Return whether a constraint index is within runtime constraint capacity bounds.
is_constraint_index_in_bounds :: #force_inline proc(index: int) -> bool {
    return index >= 0 && index < MAX_KINECONSTRAINTS
}

//   Validate that a constraint kind integer maps to a supported single kind value.
is_valid_constraint_kind_value :: #force_inline proc(kind: i32) -> bool {
    return kind >= KINE_CONSTRAINT_KIND_MIN && kind <= KINE_CONSTRAINT_KIND_MAX
}

//   Convert a boolean value to C-ABI friendly u8 representation.
to_u8 :: #force_inline proc(v: bool) -> u8 {
    if v {
        return 1
    }
    return 0
}

//   Build an invalid/sentinel constraint view result for failed lookups.
constraint_view_invalid :: #force_inline proc() -> Bridge_Constraint_View {
    return Bridge_Constraint_View{
        valid = 0,
        index = -1,
        traits = 0,
        on_point = -1,
        restriction = {0, 0, 0},
        bounce = 0,
        allowance = 0,
        depend_on = -1,
        has_child_offset = 0,
        child_offset = 0,
        do_apply = 0,
    }
}

//   Emit floor-contact dust when a point is close to the drawing plane.
push_dust_if_floor_contact :: proc(state: ^core.Euclid_General_State, pos: core.Vector3) {
    if f32(math.abs(f64(pos.z))) <= FLOOR_CONTACT_Z_EPSILON {
        particles.push_dust_away_from_xy(state^.particle_system, pos.x, pos.y)
    }
}

//   Emit sampled floor-contact dust along the active compass segment.
//
// Notes:
//   - No-op unless both compass joints are valid and near floor height.
push_dust_for_compass_segment_if_floor_contact :: proc(state: ^core.Euclid_General_State) {
    pointIndex1 := state^.compass.joint1_id
    pointIndex2 := state^.compass.joint2_id
    if pointIndex1 < 0 || pointIndex1 >= MAX_KINEPOINTS ||
        pointIndex2 < 0 || pointIndex2 >= MAX_KINEPOINTS {
        return
    }

    point1 := state^.point_system^.points[pointIndex1].position.? or_else {0, 0, 0}
    point2 := state^.point_system^.points[pointIndex2].position.? or_else {0, 0, 0}

    if f32(math.abs(f64(point1.z))) > FLOOR_CONTACT_Z_EPSILON ||
        f32(math.abs(f64(point2.z))) > FLOOR_CONTACT_Z_EPSILON {
        return
    }

    samples := COMPASS_LINE_DUST_SAMPLES
    inv_samples := f32(1.0) / f32(samples)
    for i in 0..<samples {
        t := f32(i) * inv_samples
        x := math.lerp(point1.x, point2.x, t)
        y := math.lerp(point1.y, point2.y, t)
        particles.push_dust_away_from_xy(state^.particle_system, x, y)
    }
}

//   Print Julia exception type/message details for a named bridge context.
//
// Notes:
//   - Falls back to type-only output when Base sprint/showerror cannot be resolved.
print_julia_exception :: proc(contextOfErr: string) {
    ex_raw := jl_exception_occurred()
    if ex_raw == nil {
        return
    }

    ex := (^jl_value_t)(ex_raw)

    ex_type := cstring(jl_typeof_str(ex_raw))

    base_module := resolve_base_module()
    if base_module == nil {
        fmt.println("Julia exception in ", contextOfErr, " type=", ex_type)
        return
    }

    sprint_fn := jl_get_function(base_module, "sprint")
    showerror_fn := jl_get_function(base_module, "showerror")

    if sprint_fn == nil || showerror_fn == nil {
        fmt.println("Julia exception in ", contextOfErr, " type=", ex_type)
        return
    }

    args: [2]^jl_value_t = {(^jl_value_t)(showerror_fn), ex}
    msg_val := jl_call(sprint_fn, &args[0], 2)

    if jl_exception_occurred() != nil || msg_val == nil {
        fmt.println("Julia exception in ", contextOfErr, " type=", ex_type)
        return
    }

    msg := jl_string_ptr(msg_val)
    fmt.println("Julia exception in ", contextOfErr, " type=", ex_type, " msg=", msg)
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


//   Emit a dust push when a label point becomes visible.
//
// Notes:
//   - Applies a single large push for consistent label-show behavior.
emit_label_show_dust_push :: #force_inline proc(
    state: ^core.Euclid_General_State, point: ^core.Kine_Shape_Point) {
    pos, has_pos := point^.position.?
    if !has_pos || point^.kind != .Label || pos.z > 0.05 {
        return
    }

    particles.push_dust_away_from_xy_large(state^.particle_system,
        pos.x + LABEL_DUST_X_OFFSET, pos.y + LABEL_DUST_Y_OFFSET)
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

//   Convert bridge decoration integer values to label decoration enum values.
//
// Parameters:
//   - kind: Bridge decoration constant encoded as i32.
//
// Returns:
//   - Matching label decoration enum value, or .None for unsupported values.
label_decoration_kind_from_i32 :: #force_inline proc(kind: i32) -> core.Kine_Label_Decoration_Kind {
    switch kind {
    case BRIDGE_LABEL_DECORATION_PRIME:
        return .Prime
    case BRIDGE_LABEL_DECORATION_DOUBLEPRIME:
        return .DoublePrime
    case BRIDGE_LABEL_DECORATION_TRIPLEPRIME:
        return .TriplePrime
    case BRIDGE_LABEL_DECORATION_HAT:
        return .Hat
    case BRIDGE_LABEL_DECORATION_BAR:
        return .Bar
    }

    return .None
}

//   Mark dynview stream state as failed and lock compile cache into invalid state.
//
// Notes:
//   - Preserves the first encountered error code for diagnostic stability.
dynview_fail :: #force_inline proc(runtime: ^core.Ui_Dynview_Runtime, code: i32) -> i32 {
    runtime^.command_buffer.has_stream_error = true
    if runtime^.compile_cache.last_error_code == 0 {
        runtime^.compile_cache.last_error_code = code
    }
    runtime^.compile_cache.is_valid = false
    return code
}

//   Append one dynview command to the command buffer.
//
// Returns:
//   - BRIDGE_STATUS_OK when command is enqueued.
//   - BRIDGE_STATUS_OUT_OF_CAPACITY when command buffer is full.
dynview_push_command :: #force_inline proc(
    runtime: ^core.Ui_Dynview_Runtime,
    command: core.Ui_Dynview_Command) -> i32 {

    buffer := &runtime^.command_buffer
    if buffer^.command_count >= len(buffer^.commands) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }

    buffer^.commands[buffer^.command_count] = command
    buffer^.command_count += 1
    runtime^.compile_cache.is_valid = false
    return BRIDGE_STATUS_OK
}

//   Append text bytes into dynview payload storage and return payload span.
//
// Parameters:
//   - text: Text payload to append to the shared dynview byte buffer.
//   - offset_out: Receives start offset of appended bytes.
//   - count_out: Receives appended byte count.
//
// Returns:
//   - BRIDGE_STATUS_OK when payload is appended.
//   - BRIDGE_STATUS_OUT_OF_CAPACITY when byte buffer has insufficient space.
dynview_append_text_payload :: #force_inline proc(
    runtime: ^core.Ui_Dynview_Runtime,
    text: string,
    offset_out, count_out: ^int) -> i32 {

    buffer := &runtime^.command_buffer
    text_len := len(text)
    if buffer^.text_bytes_len + text_len > len(buffer^.text_bytes) {
        return dynview_fail(runtime, BRIDGE_STATUS_OUT_OF_CAPACITY)
    }

    start := buffer^.text_bytes_len
    for i in 0..<text_len {
        buffer^.text_bytes[start + i] = text[i]
    }

    buffer^.text_bytes_len += text_len
    offset_out^ = start
    count_out^ = text_len
    return BRIDGE_STATUS_OK
}

