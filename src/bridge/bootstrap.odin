package bridge

import "../julialib"
import "../core"
import "../files"

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import vmem "core:mem/virtual"

when ODIN_OS == .Windows {
    JULIA_SYSIMAGE_FILENAME :: "euclid-sysimage.dll"
} else when ODIN_OS == .Darwin {
    JULIA_SYSIMAGE_FILENAME :: "euclid-sysimage.dylib"
} else {
    JULIA_SYSIMAGE_FILENAME :: "euclid-sysimage.so"
}

//   Resolve the optional custom Julia sysimage beside the Euclid executable.
resolve_julia_sysimage_path :: proc() -> (string, bool) {
    exe_dir, exe_err := os.get_executable_directory(context.temp_allocator)
    if exe_err != nil || len(exe_dir) == 0 {
        return "", false
    }

    image_path, path_err := filepath.join(
        []string{exe_dir, JULIA_SYSIMAGE_FILENAME}, context.temp_allocator)
    if path_err != nil || !os.exists(image_path) {
        return "", false
    }

    return image_path, true
}

//   Initialize the Julia runtime and load the packaged bridge script into Main.
//
// Notes:
//   - Intended to be called once during application startup before Julia bridge calls.
//   - Exits immediately if packaged script include fails.
initiate_julia :: proc() -> bool {
    project_path, project_ok := resolve_packaged_julia_project_path(false)
    if !project_ok {
        return false
    }
    julialib.jl_options.project = strings.clone_to_cstring(
        project_path, context.temp_allocator)

    image_path, has_image := resolve_julia_sysimage_path()
    if has_image {
        fmt.println("Starting Julia with custom sysimage: ", image_path)
        image_path_c := strings.clone_to_cstring(image_path, context.temp_allocator)
        julialib.jl_init_with_image_file(nil, image_path_c)
    } else {
        julialib.jl_init()
    }

    return include_packaged_script(false)
}

//   Shut down the Julia runtime and flush Julia-side teardown hooks.
//
// Notes:
//   - Should be paired with initiate_julia at application shutdown.
end_julia :: proc() {
    julialib.jl_atexit_hook(0)
}

//   Reset and resolve one state-owned Julia interface generation slot.
// The slot address remains stable for the host-state lifetime. Its registry arena is
// retained across reuse and cleared before resolving callbacks for a new generation.
//
// Parameters:
//   - iface: Inactive state-owned generation slot to prepare.
prepare_julia_interface_generation :: proc(iface: ^core.Euclid_Julia_Interface) {
    if iface == nil {
        return
    }

    arena := iface^.animation_registry_arena
    allocator := iface^.animation_registry_allocator
    arena_initialized := iface^.animation_registry_arena_initialized
    if arena_initialized {
        vmem.arena_free_all(&arena)
    }
    iface^ = {}
    iface^.animation_registry_arena = arena
    iface^.animation_registry_allocator = allocator
    iface^.animation_registry_arena_initialized = arena_initialized
    iface^.current_animation = &iface^.null_animation

    main_module := resolve_main_module()
    if main_module == nil {
        return
    }

    resolve_julia_interface_callbacks(iface, main_module)
}

//   Resolve the Julia callback function handles for one interface generation slot.
resolve_julia_interface_callbacks :: proc(
    iface: ^core.Euclid_Julia_Interface, main_module: ^julialib.jl_module_t) {

    iface^.init_scripts = julialib.jl_get_function(main_module, "init_euclid_scripts")
    iface^.global_loop = julialib.jl_get_function(main_module, "global_euclid_loop")
    iface^.scratchpad_classify_input = julialib.jl_get_function(
        main_module, "scratchpad_classify_input")
    iface^.scratchpad_complete_backslash = julialib.jl_get_function(
        main_module, "scratchpad_complete_backslash")
    iface^.scratchpad_complete_input = julialib.jl_get_function(
        main_module, "scratchpad_complete_input")
    iface^.scratchpad_queue_input = julialib.jl_get_function(
        main_module, "scratchpad_queue_input")
    iface^.scratchpad_save_history_to_file = julialib.jl_get_function(
        main_module, "scratchpad_save_history_to_file")
    iface^.scratchpad_history_previous = julialib.jl_get_function(
        main_module, "scratchpad_history_previous")
    iface^.scratchpad_history_next = julialib.jl_get_function(
        main_module, "scratchpad_history_next")
    iface^.scratchpad_history_reset_cursor = julialib.jl_get_function(
        main_module, "scratchpad_history_reset_cursor")
}

//   Return the inactive state-owned interface generation slot for staged registration.
julia_interface_staging_slot :: proc(
    state: ^core.Euclid_General_State) -> (^core.Euclid_Julia_Interface, int) {

    if state == nil || state^.julia_interface_active_slot < 0 ||
        state^.julia_interface_active_slot >= len(state^.julia_interface_slots) {
        return nil, -1
    }
    slot_index :=
        (state^.julia_interface_active_slot + 1) % len(state^.julia_interface_slots)
    return &state^.julia_interface_slots[slot_index], slot_index
}

//   Report whether the required Julia callbacks were resolved for an interface generation.
//   Report whether every required Julia interface handle is present.
julia_interface_handles_valid :: proc(iface: ^core.Euclid_Julia_Interface) -> bool {
    if iface == nil {
        return false
    }

    handles := [?]rawptr{
        iface^.init_scripts,
        iface^.global_loop,
        iface^.scratchpad_classify_input,
        iface^.scratchpad_complete_backslash,
        iface^.scratchpad_complete_input,
        iface^.scratchpad_queue_input,
        iface^.scratchpad_save_history_to_file,
        iface^.scratchpad_history_previous,
        iface^.scratchpad_history_next,
        iface^.scratchpad_history_reset_cursor,
    }
    for handle in handles {
        if handle == nil {
            return false
        }
    }
    return true
}

//   Ensure the animation registry arena allocator exists for bridge storage.
//
// Parameters:
//   - state: Global runtime state containing the Julia interface.
//
// Returns:
//   - ok: true when name arena allocator is ready for use.
ensure_julia_interface_registry_arena :: proc(state: ^core.Euclid_General_State) -> bool {
    if state == nil || state^.julia_interface == nil {
        return false
    }

    iface := state^.julia_interface
    if iface^.animation_registry_arena_initialized {
        return true
    }

    err := vmem.arena_init_growing(&iface^.animation_registry_arena)
    if err != nil {
        iface^.animation_registry_allocator = {}
        iface^.animation_registry_arena_initialized = false
        return false
    }

    iface^.animation_registry_allocator =
        vmem.arena_allocator(&iface^.animation_registry_arena)
    iface^.animation_registry_arena_initialized = true
    return true
}

//   Clear one interface registry while retaining its arena for reuse.
clean_julia_interface_instance :: proc(iface: ^core.Euclid_Julia_Interface) {
    if iface == nil {
        return
    }

    if iface^.animation_registry_arena_initialized {
        vmem.arena_free_all(&iface^.animation_registry_arena)
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
    if state == nil {
        return
    }

    for _, slot_index in state^.julia_interface_slots {
        destroy_julia_interface_instance(&state^.julia_interface_slots[slot_index])
    }
    state^.julia_interface = nil
}

//   Destroy registry allocations owned by one retired interface generation.
destroy_julia_interface_instance :: proc(iface: ^core.Euclid_Julia_Interface) {
    if iface == nil {
        return
    }

    clean_julia_interface_instance(iface)
    if iface^.animation_registry_arena_initialized {
        vmem.arena_destroy(&iface^.animation_registry_arena)
    }

    iface^.animation_registry_allocator = {}
    iface^.animation_registry_arena_initialized = false
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

//   Resolve the packaged Julia project directory that owns Project.toml.
resolve_packaged_julia_project_path :: proc(exit_on_failure: bool) -> (string, bool) {
    project_path := files.packaged_asset_path("julia", context.temp_allocator)
    if len(project_path) == 0 {
        fmt.eprintln("Failed to resolve packaged Julia project path.")
        fmt.eprintln("Expected assets package directory next to executable: assets.pkg")
        return "", include_packaged_script_failure(exit_on_failure)
    }

    return project_path, true
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
resolve_main_include_function :: proc(
    exit_on_failure: bool) -> (^julialib.jl_value_t, bool) {
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

//   Print Julia exception type/message details for a named bridge context.
//
// Notes:
//   - Falls back to type-only output when Base sprint/showerror cannot be resolved.
print_julia_exception :: proc(context_of_error: string) {
    ex_raw := julialib.jl_exception_occurred()
    if ex_raw == nil {
        return
    }

    ex := (^julialib.jl_value_t)(ex_raw)

    ex_type := cstring(julialib.jl_typeof_str(ex_raw))

    base_module := resolve_base_module()
    if base_module == nil {
        fmt.println("Julia exception in ", context_of_error, " type=", ex_type)
        return
    }

    sprint_fn := julialib.jl_get_function(base_module, "sprint")
    showerror_fn := julialib.jl_get_function(base_module, "showerror")
    catch_backtrace_fn := julialib.jl_get_function(base_module, "catch_backtrace")

    if sprint_fn == nil || showerror_fn == nil {
        fmt.println("Julia exception in ", context_of_error, " type=", ex_type)
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

    msg_val := format_julia_exception_message(sprint_fn, showerror_fn, ex, bt_val)
    if julialib.jl_exception_occurred() != nil || msg_val == nil {
        fmt.println("Julia exception in ", context_of_error, " type=", ex_type)
        fmt.println("Failed to format exception text via Base.sprint(showerror, ...).")
        return
    }

    msg := julialib.jl_string_ptr(msg_val)
    fmt.println("Julia exception in ", context_of_error, " type=", ex_type)
    fmt.println(msg)
}

//   Format a Julia exception through Base.sprint(showerror, ...), with optional backtrace.
//
// Returns:
//   - Formatted message value, or nil when formatting fails or raises.
format_julia_exception_message :: proc(
    sprint_fn: ^julialib.jl_value_t, showerror_fn: ^julialib.jl_value_t,
    ex: ^julialib.jl_value_t, bt_val: ^julialib.jl_value_t) -> ^julialib.jl_value_t {

    if bt_val != nil {
        args: [3]^julialib.jl_value_t = {(^julialib.jl_value_t)(showerror_fn), ex, bt_val}
        return julialib.jl_call(sprint_fn, &args[0], 3)
    }
    args: [2]^julialib.jl_value_t = {(^julialib.jl_value_t)(showerror_fn), ex}
    return julialib.jl_call(sprint_fn, &args[0], 2)
}