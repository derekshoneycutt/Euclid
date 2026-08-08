package bridge

import "../julialib"
import "../core"
import "../files"

import "base:runtime"
import "core:fmt"
import "core:strings"
import vmem "core:mem/virtual"

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
    ret.current_animation = &ret.null_animation
    ret.selected_animation = nil
    ret.animation_reset_cooldown_remaining = 0

    return ret
}

//   Ensure the animation-name arena allocator exists for bridge registry storage.
//
// Parameters:
//   - state: Global runtime state containing the Julia interface.
//
// Returns:
//   - ok: true when name arena allocator is ready for use.
ensure_julia_interface_name_arena :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_interface == nil {
        return false
    }

    iface := state^.julia_interface
    if iface^.animation_name_arena_initialized {
        return true
    }

    err := vmem.arena_init_growing(&iface^.animation_name_arena)
    if err != nil {
        iface^.animation_name_allocator = {}
        iface^.animation_name_arena_initialized = false
        return false
    }

    iface^.animation_name_allocator = vmem.arena_allocator(&iface^.animation_name_arena)
    iface^.animation_name_arena_initialized = true
    return true
}

//   Release animation-name arena allocations registered in the Julia interface table.
//
// Parameters:
//   - state: Global runtime state whose Julia interface registry is being cleared.
//
// Notes:
//   - This resets the animation-name arena for reuse on hot reload.
clean_julia_interfaces :: proc(state: ^core.Euclid_General_State) {
    if state == nil || state^.julia_interface == nil {
        return
    }

    iface := state^.julia_interface
    if iface^.animation_name_arena_initialized {
        vmem.arena_free_all(&iface^.animation_name_arena)
    }

    iface^.animation_head = nil
    iface^.animation_tail = nil
    iface^.animation_count = 0
    iface^.animation_lookup_entries = nil
    iface^.animation_lookup_capacity = 0
    iface^.animation_lookup_count = 0
    iface^.selected_animation = nil
    iface^.current_animation = &iface^.null_animation
}

//   Destroy Julia interface arena resources prior to freeing the interface struct.
//
// Parameters:
//   - state: Global runtime state whose Julia interface allocators should be destroyed.
destroy_julia_interface_resources :: proc(state: ^core.Euclid_General_State) {
    if state == nil || state^.julia_interface == nil {
        return
    }

    iface := state^.julia_interface
    clean_julia_interfaces(state)
    if iface^.animation_name_arena_initialized {
        vmem.arena_destroy(&iface^.animation_name_arena)
    }

    iface^.animation_name_allocator = {}
    iface^.animation_name_arena_initialized = false
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