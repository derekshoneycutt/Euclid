package julia


// Julia module provides the Odin-Julia Bridge to coordinate all actions between the 2
// languages. The functions in this file are the Odin side, providing all that is
// needed to initiate the Julia system and load the script files from Odin. The Bridge
// provides all methods that reach into Julia, and the types that are sent back and forth.

import "../julialib"
import "../core"
import "../files"
import "../audio"
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
    julialib.jl_init()

    _ = include_packaged_script(true)
}

//   Shut down the Julia runtime and flush Julia-side teardown hooks.
//
// Notes:
//   - Should be paired with initiate_julia at application shutdown.
end_julia :: proc() {
    julialib.jl_atexit_hook(0)
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

    ret.init_scripts = julialib.jl_get_function(main_module, "init_euclid_scripts")
    ret.global_loop = julialib.jl_get_function(main_module, "global_euclid_loop")
    ret.scratchpad_classify_input = julialib.jl_get_function(
        main_module, "scratchpad_classify_input")
    ret.scratchpad_complete_backslash = julialib.jl_get_function(
        main_module, "scratchpad_complete_backslash")
    ret.scratchpad_complete_input = julialib.jl_get_function(
        main_module, "scratchpad_complete_input")
    ret.scratchpad_queue_input = julialib.jl_get_function(
        main_module, "scratchpad_queue_input")
    ret.scratchpad_save_history_to_file = julialib.jl_get_function(
        main_module, "scratchpad_save_history_to_file")
    ret.scratchpad_history_previous = julialib.jl_get_function(
        main_module, "scratchpad_history_previous")
    ret.scratchpad_history_next = julialib.jl_get_function(
        main_module, "scratchpad_history_next")
    ret.scratchpad_history_reset_cursor = julialib.jl_get_function(
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

    state_value := julialib.jl_box_voidpointer(state)
    text_c := strings.clone_to_cstring(text, context.temp_allocator)
    text_value := julialib.jl_cstr_to_string(text_c)
    result := julialib.jl_call2(state^.julia_interface^.scratchpad_classify_input,
        state_value, text_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_classify_input")
        return SCRATCHPAD_PARSE_ERROR
    }

    return i32(julialib.jl_unbox_int32(result))
}

//   Resolve one phase-1 scratchpad backslash token to a Unicode replacement.
//
// Returns:
//   - Replacement text when Julia REPL backslash completion resolves a single match.
//   - Empty string when no completion should be applied.
scratchpad_complete_backslash :: proc(
    state: ^core.Euclid_General_State, token: string) -> string {

    if state == nil || state^.julia_interface == nil {
        return ""
    }
    if state^.julia_interface^.scratchpad_complete_backslash == nil {
        return ""
    }

    state_value := julialib.jl_box_voidpointer(state)
    token_c := strings.clone_to_cstring(token, context.temp_allocator)
    token_value := julialib.jl_cstr_to_string(token_c)
    result := julialib.jl_call2(state^.julia_interface^.scratchpad_complete_backslash,
        state_value, token_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_complete_backslash")
        return ""
    }

    return strings.clone(string(julialib.jl_string_ptr(result)), context.temp_allocator)
}

//   Resolve one generic scratchpad completion request from full input text and caret byte offset.
//
// Returns:
//   - Encoded completion payload when Julia resolves an applicable replacement.
//   - Empty string when no completion should be applied.
scratchpad_complete_input :: proc(
    state: ^core.Euclid_General_State,
    text: string,
    caret_byte: int) -> string {

    if state == nil || state^.julia_interface == nil {
        return ""
    }
    if state^.julia_interface^.scratchpad_complete_input == nil {
        return ""
    }

    state_value := julialib.jl_box_voidpointer(state)
    text_c := strings.clone_to_cstring(text, context.temp_allocator)
    text_value := julialib.jl_cstr_to_string(text_c)
    caret_value := julialib.jl_box_int64(i64(caret_byte))
    args: [3]^julialib.jl_value_t = {state_value, text_value, caret_value}
    result := julialib.jl_call(state^.julia_interface^.scratchpad_complete_input, &args[0], 3)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_complete_input")
        return ""
    }

    return strings.clone(string(julialib.jl_string_ptr(result)), context.temp_allocator)
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

    state_value := julialib.jl_box_voidpointer(state)
    text_c := strings.clone_to_cstring(text, context.temp_allocator)
    text_value := julialib.jl_cstr_to_string(text_c)
    result := julialib.jl_call2(state^.julia_interface^.scratchpad_queue_input,
        state_value, text_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_queue_input")
        return false
    }

    return julialib.jl_unbox_bool(result) != 0
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

    state_value := julialib.jl_box_voidpointer(state)
    path_c := strings.clone_to_cstring(path, context.temp_allocator)
    path_value := julialib.jl_cstr_to_string(path_c)
    result := julialib.jl_call2(state^.julia_interface^.scratchpad_save_history_to_file,
        state_value, path_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_save_history_to_file")
        return false
    }

    return julialib.jl_unbox_bool(result) != 0
}

//   Move scratchpad history cursor one step backward and return suggested input.
//
// Notes:
//   - The helper forwards the request through the registered Julia callback and
//     returns the resolved suggestion text for the UI to display.
scratchpad_history_previous :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_interface == nil {
        return ""
    }
    if state^.julia_interface^.scratchpad_history_previous == nil {
        return ""
    }

    state_value := julialib.jl_box_voidpointer(state)
    result := julialib.jl_call1(
        state^.julia_interface^.scratchpad_history_previous, state_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_history_previous")
        return ""
    }

    return strings.clone(string(julialib.jl_string_ptr(result)), context.temp_allocator)
}

//   Move scratchpad history cursor one step forward and return suggested input.
//
// Notes:
//   - The helper forwards the request through the registered Julia callback and
//     returns the next suggested input text when the history cursor advances.
scratchpad_history_next :: proc(state: ^core.Euclid_General_State) -> string {
    if state == nil || state^.julia_interface == nil {
        return ""
    }
    if state^.julia_interface^.scratchpad_history_next == nil {
        return ""
    }

    state_value := julialib.jl_box_voidpointer(state)
    result := julialib.jl_call1(state^.julia_interface^.scratchpad_history_next, state_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_history_next")
        return ""
    }

    return strings.clone(string(julialib.jl_string_ptr(result)), context.temp_allocator)
}

//   Reset scratchpad history cursor to the position after the most recent entry.
//
// Notes:
//   - The helper forwards the reset request to Julia and reports whether the
//     callback completed successfully.
scratchpad_history_reset_cursor :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_interface == nil {
        return false
    }
    if state^.julia_interface^.scratchpad_history_reset_cursor == nil {
        return false
    }

    state_value := julialib.jl_box_voidpointer(state)
    result := julialib.jl_call1(
        state^.julia_interface^.scratchpad_history_reset_cursor, state_value)

    if julialib.jl_exception_occurred() != nil || result == nil {
        print_julia_exception("scratchpad_history_reset_cursor")
        return false
    }

    return julialib.jl_unbox_bool(result) != 0
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

//   Resolve Julia Main module handle used for bridge function lookup.
resolve_main_module :: proc() -> ^julialib.jl_module_t {
    main_value := julialib.jl_eval_string("Main")
    if main_value == nil || julialib.jl_exception_occurred() != nil {
        return nil
    }
    return (^julialib.jl_module_t)(main_value)
}

//   Resolve Julia Base module handle used for exception formatting.
resolve_base_module :: proc() -> ^julialib.jl_module_t {
    base_value := julialib.jl_eval_string("Base")
    if base_value == nil || julialib.jl_exception_occurred() != nil {
        return nil
    }
    return (^julialib.jl_module_t)(base_value)
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
resolve_main_include_function :: proc(exit_on_failure: bool) -> (^julialib.jl_value_t, bool) {
    main_module := resolve_main_module()
    if main_module == nil {
        fmt.eprintln("Failed to resolve Julia Main module.")
        return nil, include_packaged_script_failure(exit_on_failure)
    }

    include_fn := julialib.jl_get_function(main_module, "include")
    if include_fn == nil {
        fmt.eprintln("Failed to resolve Julia include function from Main.")
        return nil, include_packaged_script_failure(exit_on_failure)
    }

    return include_fn, true
}

//   Call Main.include on the packaged Julia entry script path.
call_include_packaged_script :: proc(
    include_fn: ^julialib.jl_value_t,
    script_path: string,
    exit_on_failure: bool) -> bool {

    script_cstr := strings.clone_to_cstring(script_path, context.temp_allocator)
    script_value := julialib.jl_cstr_to_string(script_cstr)
    include_result := julialib.jl_call1(include_fn, script_value)
    if julialib.jl_exception_occurred() != nil || include_result == nil {
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

    state^.julia_interface^.init_scripts = julialib.jl_get_function(main_module, "init_euclid_scripts")
    state^.julia_interface^.global_loop = julialib.jl_get_function(main_module, "global_euclid_loop")
    state^.julia_interface^.scratchpad_classify_input = julialib.jl_get_function(
        main_module, "scratchpad_classify_input")
    state^.julia_interface^.scratchpad_queue_input = julialib.jl_get_function(
        main_module, "scratchpad_queue_input")
    state^.julia_interface^.scratchpad_save_history_to_file = julialib.jl_get_function(
        main_module, "scratchpad_save_history_to_file")
    state^.julia_interface^.scratchpad_history_previous = julialib.jl_get_function(
        main_module, "scratchpad_history_previous")
    state^.julia_interface^.scratchpad_history_next = julialib.jl_get_function(
        main_module, "scratchpad_history_next")
    state^.julia_interface^.scratchpad_history_reset_cursor = julialib.jl_get_function(
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

//   Emit dust for line segments connected to a point when a crossing/touch event occurs.
//
// Notes:
//   - If a connected line lies on z=0, emit sampled pushes along the segment.
//   - If a connected line straddles z=0, emit one push at the segment crossing point.
push_dust_for_connected_lines_on_floor_event :: proc(
    state: ^core.Euclid_General_State,
    point_index: int) {

    next_index := state^.point_system^.next_point_index
    if point_index < 0 || point_index >= next_index {
        return
    }

    for host_index in 0..<next_index {
        host := state^.point_system^.points[host_index]
        if host.kind != .Line {
            continue
        }

        p1 := host.child_point_head
        if p1 < 0 || p1 >= next_index {
            continue
        }

        p2 := state^.point_system^.points[p1].next_child_point
        if p2 < 0 || p2 >= next_index {
            continue
        }

        if p1 != point_index && p2 != point_index {
            continue
        }

        pos1, has_pos1 := state^.point_system^.points[p1].position.?
        pos2, has_pos2 := state^.point_system^.points[p2].position.?
        if !has_pos1 || !has_pos2 {
            continue
        }

        sign1 := floor_contact_sign(pos1.z)
        sign2 := floor_contact_sign(pos2.z)

        if sign1 == 0 && sign2 == 0 {
            samples := COMPASS_LINE_DUST_SAMPLES
            inv_samples := f32(1.0) / f32(samples)
            for i in 0..<samples {
                t := f32(i) * inv_samples
                x := math.lerp(pos1.x, pos2.x, t)
                y := math.lerp(pos1.y, pos2.y, t)
                particles.push_dust_away_from_xy(state^.particle_system, x, y)
            }
            continue
        }

        if sign1 * sign2 >= 0 {
            continue
        }

        dz := pos2.z - pos1.z
        if math.abs(dz) <= FLOOR_CONTACT_Z_EPSILON {
            continue
        }

        t := -pos1.z / dz
        t = math.clamp(t, 0, 1)

        x := math.lerp(pos1.x, pos2.x, t)
        y := math.lerp(pos1.y, pos2.y, t)
        particles.push_dust_away_from_xy(state^.particle_system, x, y)
    }
}

//   Classify one z value relative to floor contact dead-zone.
floor_contact_sign :: #force_inline proc(z: f32) -> int {
    if z > FLOOR_CONTACT_Z_EPSILON {
        return 1
    }
    if z < -FLOOR_CONTACT_Z_EPSILON {
        return -1
    }
    return 0
}

//   Emit one dust push only when a point newly reaches or crosses z=0.
//
// Notes:
//   - Remaining on the floor plane emits no repeated pushes.
//   - Leaving the floor plane emits no push.
push_dust_if_floor_crossing :: proc(
    state: ^core.Euclid_General_State,
    previous_pos, current_pos: core.Vector3,
    has_previous: bool) -> bool {

    if !has_previous {
        return false
    }

    previous_sign := floor_contact_sign(previous_pos.z)
    current_sign := floor_contact_sign(current_pos.z)

    if previous_sign == 0 && current_sign == 0 {
        return false
    }

    if previous_sign != 0 && current_sign == 0 {
        particles.push_dust_away_from_xy(state^.particle_system, current_pos.x, current_pos.y)
        return true
    }

    if previous_sign == 0 && current_sign != 0 {
        return false
    }

    if previous_sign * current_sign >= 0 {
        return false
    }

    dz := current_pos.z - previous_pos.z
    if math.abs(dz) <= FLOOR_CONTACT_Z_EPSILON {
        return false
    }

    t := -previous_pos.z / dz
    t = math.clamp(t, 0, 1)

    x := math.lerp(previous_pos.x, current_pos.x, t)
    y := math.lerp(previous_pos.y, current_pos.y, t)
    particles.push_dust_away_from_xy(state^.particle_system, x, y)
    return true
}

//   Print Julia exception type/message details for a named bridge context.
//
// Notes:
//   - Falls back to type-only output when Base sprint/showerror cannot be resolved.
print_julia_exception :: proc(contextOfErr: string) {
    ex_raw := julialib.jl_exception_occurred()
    if ex_raw == nil {
        return
    }

    ex := (^julialib.jl_value_t)(ex_raw)

    ex_type := cstring(julialib.jl_typeof_str(ex_raw))

    base_module := resolve_base_module()
    if base_module == nil {
        fmt.println("Julia exception in ", contextOfErr, " type=", ex_type)
        return
    }

    sprint_fn := julialib.jl_get_function(base_module, "sprint")
    showerror_fn := julialib.jl_get_function(base_module, "showerror")
    catch_backtrace_fn := julialib.jl_get_function(base_module, "catch_backtrace")

    if sprint_fn == nil || showerror_fn == nil {
        fmt.println("Julia exception in ", contextOfErr, " type=", ex_type)
        fmt.println("Julia exception formatter unavailable (Base.sprint/Base.showerror).")
        return
    }

    bt_val: ^julialib.jl_value_t = nil
    if catch_backtrace_fn != nil {
        bt_val = julialib.jl_call0(catch_backtrace_fn)
        if julialib.jl_exception_occurred() != nil {
            bt_val = nil
        }
    }

    msg_val: ^julialib.jl_value_t = nil
    if bt_val != nil {
        args: [3]^julialib.jl_value_t = {(^julialib.jl_value_t)(showerror_fn), ex, bt_val}
        msg_val = julialib.jl_call(sprint_fn, &args[0], 3)
    } else {
        args: [2]^julialib.jl_value_t = {(^julialib.jl_value_t)(showerror_fn), ex}
        msg_val = julialib.jl_call(sprint_fn, &args[0], 2)
    }

    if julialib.jl_exception_occurred() != nil || msg_val == nil {
        fmt.println("Julia exception in ", contextOfErr, " type=", ex_type)
        fmt.println("Failed to format exception text via Base.sprint(showerror, ...).")
        return
    }

    msg := julialib.jl_string_ptr(msg_val)
    fmt.println("Julia exception in ", contextOfErr, " type=", ex_type)
    fmt.println(msg)
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


//   Convert a bridge math-op kind into the matching dynview command kind.
//
// Notes:
//   - Unsupported bridge kinds fall back to a text run so the importer can keep
//     making progress instead of failing the whole program.
dynview_math_command_kind_from_bridge :: #force_inline proc(
    kind: i32) -> (core.Ui_Dynview_Command_Kind, bool) {
    switch kind {
    case BRIDGE_DYNVIEW_MATH_OP_TEXT_RUN:
        return .TextRun, true
    case BRIDGE_DYNVIEW_MATH_OP_MATH_GLYPH_RUN:
        return .MathGlyphRun, true
    case BRIDGE_DYNVIEW_MATH_OP_SCRIPT_ATTACH_RECURSIVE:
        return .ScriptAttachRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_FRACTION_RECURSIVE:
        return .FracRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_STRETCH_DELIMITER_RECURSIVE:
        return .StretchDelimiterRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_MATRIX_RECURSIVE:
        return .MatrixRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_LARGE_OP_RECURSIVE:
        return .LargeOpRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_ACCENT_BAR_RECURSIVE:
        return .AccentBarRecursive, true
    case BRIDGE_DYNVIEW_MATH_OP_RADICAL_BAR_RECURSIVE:
        return .RadicalBarRecursive, true
    }
    return .TextRun, false
}

//   Return whether an op's text spans fit inside the shared text blob.
//
// Notes:
//   - Each span is checked against the shared blob bounds before the importer
//     emits any dynview command using the payload offsets.
dynview_math_op_spans_valid :: #force_inline proc(
    op: Bridge_Dynview_Math_Op, blob_count: int) -> bool {
    if op.text_offset < 0 || op.text_len < 0 ||
        op.index_text_offset < 0 || op.index_text_len < 0 ||
        op.sup_text_offset < 0 || op.sup_text_len < 0 ||
        op.sub_text_offset < 0 || op.sub_text_len < 0 {
        return false
    }

    return int(op.text_offset + op.text_len) <= blob_count &&
        int(op.index_text_offset + op.index_text_len) <= blob_count &&
        int(op.sup_text_offset + op.sup_text_len) <= blob_count &&
        int(op.sub_text_offset + op.sub_text_len) <= blob_count
}

//   Import one recursive child program into the dynview compile cache.
//
// Notes:
//   - The helper reserves the next available program id and reuses the shared
//     recursive importer to pull the requested subtree into the cache.
dynview_import_child_program :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    block_id: i32,
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: int,
    cursor: ^int,
    direct_count: int,
    blob_offset, blob_count: int,
    next_program_id: ^int) -> (program_id: i32, status: i32) {

    if direct_count <= 0 || next_program_id == nil {
        return 0, BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if next_program_id^ >= core.UI_DYNVIEW_MAX_MATH_PROGRAMS {
        return 0, BRIDGE_STATUS_INVALID_ARGUMENT
    }

    host_program_id := next_program_id^
    next_program_id^ += 1
    child_status: i32 = dynview_import_math_program_from_ops(cache, block_id, ops,
        op_count, cursor, direct_count, blob_offset, blob_count, host_program_id,
        next_program_id)
    if child_status != BRIDGE_STATUS_OK {
        return 0, child_status
    }

    return i32(host_program_id), BRIDGE_STATUS_OK
}

//   Import the numerator and denominator subprograms for a fraction op.
//
// Notes:
//   - The fraction branches are imported from the same flat bridge stream.
//   - The helper advances the shared cursor and program allocation state for both
//     children before returning the assigned program ids.
dynview_import_fraction_children :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    block_id: i32,
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: int,
    cursor: ^int,
    op: Bridge_Dynview_Math_Op,
    blob_offset, blob_count: int,
    next_program_id: ^int) -> (numerator_program_id: i32, denominator_program_id: i32, status: i32) {

    numerator_direct_count := int(op.child_program_id)
    denominator_direct_count := int(op.secondary_child_program_id)
    if numerator_direct_count <= 0 || denominator_direct_count <= 0 {
        return 0, 0, BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if next_program_id^ + 1 >= core.UI_DYNVIEW_MAX_MATH_PROGRAMS {
        return 0, 0, BRIDGE_STATUS_INVALID_ARGUMENT
    }

    numerator_result, numerator_status := dynview_import_child_program(cache, block_id,
        ops, op_count, cursor, numerator_direct_count, blob_offset, blob_count,
        next_program_id)
    if numerator_status != BRIDGE_STATUS_OK {
        return 0, 0, numerator_status
    }

    denominator_result, denominator_status := dynview_import_child_program(cache,
        block_id, ops, op_count, cursor, denominator_direct_count,
        blob_offset, blob_count, next_program_id)
    if denominator_status != BRIDGE_STATUS_OK {
        return 0, 0, denominator_status
    }

    return numerator_result, denominator_result, BRIDGE_STATUS_OK
}

//   Import one math program from the flat bridge op stream.
//
// Notes:
//   - The helper reserves command slots for the requested subtree size and then
//     walks the bridge ops into the dynview compile cache.
dynview_import_math_program_from_ops :: proc(
    cache: ^core.Ui_Dynview_Compile_Cache,
    block_id: i32,
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: int,
    cursor: ^int,
    direct_count: int,
    blob_offset, blob_count: int,
    program_id: int,
    next_program_id: ^int) -> i32 {

    if direct_count <= 0 || cache == nil || cursor == nil || next_program_id == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    command_start := cache^.math_command_count
    if command_start + direct_count > core.UI_DYNVIEW_MAX_MATH_COMMANDS {
        return BRIDGE_STATUS_OUT_OF_CAPACITY
    }
    cache^.math_command_count += direct_count

    for local_index in 0..<direct_count {
        if cursor^ >= op_count {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }

        op := ops[cursor^]
        cursor^ += 1
        command_kind, ok := dynview_math_command_kind_from_bridge(op.kind)
        if !ok || !dynview_math_op_spans_valid(op, blob_count) {
            return BRIDGE_STATUS_INVALID_ARGUMENT
        }

        child_program_id := i32(op.child_program_id)
        secondary_child_program_id: i32 = 0
        status: i32 = BRIDGE_STATUS_OK
        switch command_kind {
        case .ScriptAttachRecursive, .AccentBarRecursive, .RadicalBarRecursive:
            child_direct_count := int(op.child_program_id)
            if child_direct_count <= 0 {
                return BRIDGE_STATUS_INVALID_ARGUMENT
            }
            child_program_id, status = dynview_import_child_program(cache, block_id,
                ops, op_count, cursor, child_direct_count, blob_offset, blob_count,
                next_program_id)
            if status != BRIDGE_STATUS_OK {
                return status
            }
        case .FracRecursive:
            numerator_program_id, denominator_program_id, child_status :=
                dynview_import_fraction_children(cache, block_id, ops, op_count, cursor,
                    op, blob_offset, blob_count, next_program_id)
            if child_status != BRIDGE_STATUS_OK {
                return child_status
            }
            child_program_id = numerator_program_id
            secondary_child_program_id = denominator_program_id
        case .StretchDelimiterRecursive:
            child_direct_count := int(op.child_program_id)
            if child_direct_count > 0 {
                child_program_id, status = dynview_import_child_program(cache, block_id,
                    ops, op_count, cursor, child_direct_count, blob_offset, blob_count,
                    next_program_id)
                if status != BRIDGE_STATUS_OK {
                    return status
                }
            } else {
                child_program_id = 0
            }
        case .MatrixRecursive:
            child_direct_count := int(op.child_program_id)
            if child_direct_count <= 0 {
                return BRIDGE_STATUS_INVALID_ARGUMENT
            }
            child_program_id, status = dynview_import_child_program(cache, block_id,
                ops, op_count, cursor, child_direct_count, blob_offset, blob_count,
                next_program_id)
            if status != BRIDGE_STATUS_OK {
                return status
            }
        case .BeginBlock:
        case .EndBlock:
        case .TextRun:
        case .MathGlyphRun:
        case .MathBlock:
        case .LargeOpRecursive:
        case .CopyableTextRun:
        case .LineBreak:
        case .Divider:
        case .InlineLine:
        case .InlineBox:
        case .InlineCircle:
        case .InlineFilledBox:
        case .InlineFilledCircle:
        case .InlinePieSection:
        }

        cache^.math_commands[command_start + local_index] = core.Ui_Dynview_Command{
            kind = command_kind,
            block_id = block_id,
            style_id = op.style_id,
            math_program_id = child_program_id,
            secondary_math_program_id = secondary_child_program_id,
            text_offset = blob_offset + int(op.text_offset),
            text_len = int(op.text_len),
            script_base_text_offset = blob_offset + int(op.text_offset),
            script_base_text_len = int(op.text_len),
            script_sup_text_offset = blob_offset + int(op.sup_text_offset),
            script_sup_text_len = int(op.sup_text_len),
            script_sub_text_offset = blob_offset + int(op.sub_text_offset),
            script_sub_text_len = int(op.sub_text_len),
            script_style_id = op.script_style_id,
            script_scale = op.script_scale,
            script_sup_raise = op.script_sup_raise,
            script_sub_drop = op.script_sub_drop,
            script_gap = op.script_gap,
            accent_mode = op.accent_mode,
            radical_mode = op.radical_mode,
            large_op_kind = op.large_op_kind,
            radical_index_text_offset = blob_offset + int(op.index_text_offset),
            radical_index_text_len = int(op.index_text_len),
            accent_style_id = op.accent_style_id,
            accent_thickness = op.accent_thickness,
            accent_offset = op.accent_offset,
        }
    }

    cache^.math_programs[program_id] = core.Ui_Dynview_Math_Program{
        valid = true,
        command_start = command_start,
        command_count = direct_count,
    }
    return BRIDGE_STATUS_OK
}

//   Return a pointer to the dynview runtime for the current bridge state.
//
// Notes:
//   - The helper reuses the bridge state's saved context so the caller can access
//     the active dynview runtime without reaching into the state internals.
dynview_require_runtime :: proc(
    state: ^core.Euclid_General_State,
    runtime_out: ^^core.Ui_Dynview_Runtime) -> i32 {

    if state == nil || runtime_out == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }

    context = state^.saved_context
    runtime_out^ = &state^.ui_runtime.dynview_runtime
    return BRIDGE_STATUS_OK
}

//   Return a pointer to the active dynview command buffer.
//
// Notes:
//   - The helper exposes the current command buffer while optionally enforcing
//     that a dynview block is already open before commands are appended.
dynview_require_buffer :: proc(
    runtime: ^core.Ui_Dynview_Runtime,
    buffer_out: ^^core.Ui_Dynview_Command_Buffer,
    require_open_block: bool) -> i32 {

    if runtime == nil || buffer_out == nil {
        return BRIDGE_STATUS_INVALID_ARGUMENT
    }
    if !runtime^.enabled {
        return BRIDGE_STATUS_OK
    }

    buffer_out^ = &runtime^.command_buffer
    buffer := buffer_out^
    if require_open_block && !buffer^.stream_open_block {
        return dynview_fail(runtime, BRIDGE_STATUS_ILLEGAL_STATE)
    }
    return BRIDGE_STATUS_OK
}

//   Count the extra math programs and commands needed by recursive ops.
//
// Notes:
//   - Recursive math nodes reserve additional program and command slots based on
//     their child structure so the compile cache can be sized up front.
dynview_count_recursive_math_capacity :: proc(
    ops: [^]Bridge_Dynview_Math_Op,
    op_count: int) -> (extra_programs: int, extra_commands: int) {

    for i in 0..<op_count {
        switch ops[i].kind {
        case BRIDGE_DYNVIEW_MATH_OP_ACCENT_BAR_RECURSIVE,
            BRIDGE_DYNVIEW_MATH_OP_RADICAL_BAR_RECURSIVE,
            BRIDGE_DYNVIEW_MATH_OP_SCRIPT_ATTACH_RECURSIVE:
            extra_programs += 1
            extra_commands += 1
        case BRIDGE_DYNVIEW_MATH_OP_FRACTION_RECURSIVE:
            extra_programs += 2
            extra_commands += 2
        case BRIDGE_DYNVIEW_MATH_OP_STRETCH_DELIMITER_RECURSIVE,
            BRIDGE_DYNVIEW_MATH_OP_MATRIX_RECURSIVE:
            if ops[i].child_program_id > 0 {
                extra_programs += 1
                extra_commands += 1
            }
        }
    }

    return
}

//   Update one point position and emit floor-crossing dust only.
set_point_position_with_floor_crossing_dust :: #force_inline proc(
    state: ^core.Euclid_General_State,
    index: int,
    pos: core.Vector3) {

    previous_pos, has_previous := state^.point_system^.points[index].position.?
    state^.point_system^.points[index].position = pos
    if push_dust_if_floor_crossing(state, previous_pos, pos, has_previous) {
        if state^.drawing_sound_enabled {
            if index == state^.pen.joint1_id || index == state^.pen.joint2_id ||
                index == state^.compass.joint1_id || index == state^.compass.joint2_id {
                audio.trigger_hit_sound(&state^.chalk_audio)
            }
        }
        push_dust_for_connected_lines_on_floor_event(state, index)
    }
}

//   Update one point position and emit floor-contact plus crossing dust effects.
set_point_position_with_floor_dust_effects :: #force_inline proc(
    state: ^core.Euclid_General_State,
    index: int,
    pos: core.Vector3) {

    set_point_position_with_floor_crossing_dust(state, index, pos)
    push_dust_if_floor_contact(state, pos)

    is_floor_contact :=
        state^.drawing_sound_enabled &&
        pos.z <= FLOOR_CONTACT_Z_EPSILON && pos.z >= -FLOOR_CONTACT_Z_EPSILON
    dt := state^.current_delta_time

    pen_active_child := -1
    if state^.pen.host_id >= 0 && state^.pen.host_id < MAX_KINEPOINTS {
        pen_active_child = state^.point_system^.points[state^.pen.host_id].active_child
    }

    compass_active_child := -1
    if state^.compass.host_id >= 0 && state^.compass.host_id < MAX_KINEPOINTS {
        compass_active_child = state^.point_system^.points[state^.compass.host_id].active_child
    }

    if index == state^.pen.joint1_id {
        audio.register_pen_tip_motion(&state^.chalk_audio, pos,
            is_floor_contact && pen_active_child == 1, dt)
    } else if index == state^.compass.joint1_id {
        audio.register_compass_tip1_motion(&state^.chalk_audio, pos,
            is_floor_contact && compass_active_child == 1, dt)
    } else if index == state^.compass.joint2_id {
        audio.register_compass_tip2_motion(&state^.chalk_audio, pos,
            is_floor_contact && compass_active_child == 3, dt)
    }
}
