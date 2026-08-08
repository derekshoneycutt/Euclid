package bridge

import "../julialib"
import "../core"
import "../files"
import "../shapes"

import "core:encoding/uuid"
import "core:fmt"
import "core:strings"

SCRATCHPAD_ANIMATION_NAME :: "Scratchpad"
ANIMATION_LOOKUP_INITIAL_RESERVE :: 512
ANIMATION_LOOKUP_LOAD_FACTOR_NUMERATOR :: 7
ANIMATION_LOOKUP_LOAD_FACTOR_DENOMINATOR :: 10

//   Invoke Julia-side script initialization and optional null-animation init hook.
//
// Parameters:
//   - state: Global runtime state passed through to Julia callback entry points.
//
// Notes:
//   - Julia exceptions are reported and the call returns early without panicking.
init_euclid_scripts :: proc(state: ^core.Euclid_General_State) {
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

    if state^.julia_interface^.selected_animation == nil {
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
perform_animation_frame :: proc(state: ^core.Euclid_General_State, dt: f32) {
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
call_current_animation_get_view_text :: proc(state: ^core.Euclid_General_State) -> string {
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
update_running_animations :: proc(state: ^core.Euclid_General_State, dt: f32) {
    reload_packaged_assets_if_updated(state)

    if state^.julia_interface^.animation_reset_cooldown_remaining > 0 {
        state^.julia_interface^.animation_reset_cooldown_remaining -= dt
        if state^.julia_interface^.animation_reset_cooldown_remaining < 0 {
            state^.julia_interface^.animation_reset_cooldown_remaining = 0
        }
    }

    switched_animation := false
    if state^.julia_interface^.selected_animation !=
        state^.julia_interface^.current_animation {
        previous_animation := state^.julia_interface^.current_animation
        change_current_animation_loop(state, state^.julia_interface^.selected_animation)
        switched_animation =
            state^.julia_interface^.current_animation == state^.julia_interface^.selected_animation &&
            state^.julia_interface^.current_animation != previous_animation
    }

    if state^.julia_interface^.pending_animation_reset &&
        state^.julia_interface^.current_animation == state^.julia_interface^.selected_animation {
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
call_global_euclid_loop :: proc(state: ^core.Euclid_General_State, dt: f32) {
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
call_current_animation_loop :: proc(state: ^core.Euclid_General_State, dt: f32) {
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
//   - Clears animation-owned shapes data and tool visibility before initializing the target animation.
change_current_animation_loop :: proc(
    state: ^core.Euclid_General_State,
    new_animation: ^core.Euclid_Julia_Animation_Interface) {

    animation := new_animation
    if animation == nil {
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

    shapes.clear_animation_data(state^.point_system, state^.particle_system, state^.iso_scale)
    hide_pen(state)
    hide_compass(state)
    for i in 0..<len(state^.anim_metadata) {
        state^.anim_metadata[i] = 0.0
    }
    state^.drawing_sound_enabled = true

    if animation^.initiate != nil {
        julialib.jl_call1(animation^.initiate, state_value)
        if julialib.jl_exception_occurred() != nil {
            print_julia_exception("Initiating new animation loop")
            return
        }
    }

    state^.julia_interface^.current_animation = animation
}

//   Restart the currently selected animation by running clean then initiate callbacks.
reset_current_animation_loop :: proc(state: ^core.Euclid_General_State) {
    if state^.julia_interface^.current_animation^.loop == nil {
        return
    }

    state_value := julialib.jl_box_voidpointer(state)

    julialib.jl_call1(state^.julia_interface^.current_animation^.clean, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Cleaning previous animation loop")
        return
    }

    shapes.clear_animation_data(state^.point_system, state^.particle_system, state^.iso_scale)
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

    ji := state^.julia_interface
    target: ^core.Euclid_Julia_Animation_Interface

    it := animation_iterator_begin(ji)
    for {
        node := animation_iterator_next(&it)
        if node == nil {
            break
        }
        if node^.name == SCRATCHPAD_ANIMATION_NAME {
            continue
        }

        target = node
        break
    }

    if target == nil {
        return
    }

    it = animation_iterator_begin(ji)
    for {
        node := animation_iterator_next(&it)
        if node == nil {
            break
        }
        node^.is_selected = (node == target)
    }

    ji^.selected_animation = target
}

//   Clear animation registry state and reset interface selection fields to defaults.
reset_julia_interface_registry :: proc(state: ^core.Euclid_General_State) {
    clean_julia_interfaces(state)

    state^.julia_interface^.null_animation = {}
    state^.julia_interface^.current_animation = &state^.julia_interface^.null_animation
    state^.julia_interface^.selected_animation = nil
    state^.julia_interface^.pending_animation_reset = false
    state^.julia_interface^.animation_reset_cooldown_remaining = 0
}

//   Find an animation pointer by its registered stable UUID identity.
find_animation_by_stable_id :: proc(
    state: ^core.Euclid_General_State,
    stable_id: uuid.Identifier) -> ^core.Euclid_Julia_Animation_Interface {

    if state == nil || state^.julia_interface == nil {
        return nil
    }

    return animation_lookup_find(state^.julia_interface, stable_id)
}

//   Restore the current animation selection after a successful script reload.
restore_current_animation_after_reload :: proc(
    state: ^core.Euclid_General_State,
    animation_stable_id: uuid.Identifier) {

    restored_animation := find_animation_by_stable_id(state, animation_stable_id)
    if restored_animation != nil {
        state^.julia_interface^.selected_animation = restored_animation
        change_current_animation_loop(state, restored_animation)
        return
    }

    fmt.eprintln("Julia asset reload: unable to restore animation for requested stable_id")
}

//   Detect packaged asset updates and hot-reload Julia script/interface state when changed.
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
    has_current_animation_stable_id := false
    active_animation := state^.julia_interface^.current_animation
    if active_animation != nil && active_animation != &state^.julia_interface^.null_animation {
        current_animation_stable_id = active_animation^.stable_id
        has_current_animation_stable_id = true
    }

    state^.julia_interface^.asset_archive_mod_time_unix_nano = archive_mtime
    refresh_julia_interface_handles(state)
    reset_julia_interface_registry(state)
    init_euclid_scripts(state)
    if has_current_animation_stable_id {
        restore_current_animation_after_reload(state, current_animation_stable_id)
    }

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
find_registered_animation_by_stable_id :: proc(
    state: ^core.Euclid_General_State,
    stable_id: uuid.Identifier) -> ^core.Euclid_Julia_Animation_Interface {

    return find_animation_by_stable_id(state, stable_id)
}

//   Reject duplicate stable UUID registration before insertion.
reject_duplicate_stable_id :: proc(
    state: ^core.Euclid_General_State,
    name, stable_id_text: cstring,
    stable_id: uuid.Identifier,
    parent_stable_id_text: cstring) -> bool {

    existing_animation := find_registered_animation_by_stable_id(state, stable_id)
    if existing_animation == nil {
        return false
    }

    fmt.eprintln(
        "add animation interface failed: duplicate stable_id '",
        string(stable_id_text),
        "' for ",
        string(name),
        " conflicts with existing animation name '",
        existing_animation^.name,
        "' parent_stable_id=",
        string(parent_stable_id_text))
    return true
}

//   Create a forward-only iterator over the animation registry list.
animation_iterator_begin :: proc(
    ji: ^core.Euclid_Julia_Interface) -> core.Euclid_Julia_Animation_Iterator {

    if ji == nil {
        return {}
    }

    return core.Euclid_Julia_Animation_Iterator{current = ji^.animation_head}
}

//   Return the current iterator node and advance to the next registry entry.
animation_iterator_next :: proc(
    it: ^core.Euclid_Julia_Animation_Iterator) -> ^core.Euclid_Julia_Animation_Interface {

    if it == nil || it^.current == nil {
        return nil
    }

    current := it^.current
    it^.current = current^.next_in_registry
    return current
}

//   Attach a child animation to its parent while preserving sibling order.
animation_link_child :: proc(
    parent, child: ^core.Euclid_Julia_Animation_Interface) {

    if parent == nil || child == nil {
        return
    }

    child^.parent = parent
    if parent^.first_child == nil {
        parent^.first_child = child
        parent^.last_child = child
        return
    }

    sibling := parent^.last_child
    sibling^.next_sibling = child
    child^.prev_sibling = sibling
    parent^.last_child = child
}

//   Append a new node to the registry's arena-backed insertion order list.
animation_append_to_registry :: proc(
    ji: ^core.Euclid_Julia_Interface,
    node: ^core.Euclid_Julia_Animation_Interface) {

    if ji == nil || node == nil {
        return
    }

    if ji^.animation_head == nil {
        ji^.animation_head = node
        ji^.animation_tail = node
    } else {
        node^.prev_in_registry = ji^.animation_tail
        ji^.animation_tail^.next_in_registry = node
        ji^.animation_tail = node
    }

    ji^.animation_count += 1
}

//  Generate the hash for a stable UUID value
animation_hash_stable_id :: proc(stable_id: uuid.Identifier) -> u64 {
    bytes := stable_id
    hash: u64 = 1469598103934665603
    for b in bytes {
        hash = (hash ~ u64(b)) * 1099511628211
    }

    if hash == 0 {
        return 1
    }

    return hash
}

//   Probe the UUID lookup table for an occupied match or an insertion slot.
animation_lookup_probe :: proc(
    entries: []core.Euclid_Julia_Animation_Lookup_Entry,
    capacity: int,
    stable_id: uuid.Identifier,
    for_insert: bool) -> (int, bool) {

    if capacity <= 0 || len(entries) < capacity {
        return -1, false
    }

    mask := capacity - 1
    index := int(animation_hash_stable_id(stable_id) & u64(mask))
    for _ in 0..<capacity {
        entry := entries[index]
        if !entry.is_occupied {
            if for_insert {
                return index, false
            }
            return -1, false
        }

        if entry.stable_id == stable_id {
            return index, true
        }

        index = (index + 1) & mask
    }

    return -1, false
}

//   Allocate a lookup table buffer from the registry arena.
animation_lookup_allocate :: proc(
    ji: ^core.Euclid_Julia_Interface,
    new_capacity: int) -> []core.Euclid_Julia_Animation_Lookup_Entry {

    if ji == nil || new_capacity <= 0 || (new_capacity & (new_capacity - 1)) != 0 {
        return nil
    }

    new_entries := make([]core.Euclid_Julia_Animation_Lookup_Entry,
        new_capacity, ji^.animation_name_allocator)
    if len(new_entries) != new_capacity {
        return nil
    }

    return new_entries
}

//   Grow and rehash the UUID lookup table into a larger arena allocation.
animation_lookup_grow :: proc(
    ji: ^core.Euclid_Julia_Interface,
    new_capacity: int) -> bool {

    if ji == nil || new_capacity <= 0 {
        return false
    }

    new_entries := animation_lookup_allocate(ji, new_capacity)
    if len(new_entries) != new_capacity {
        return false
    }

    old_entries := ji^.animation_lookup_entries
    old_capacity := ji^.animation_lookup_capacity

    ji^.animation_lookup_entries = new_entries
    ji^.animation_lookup_capacity = new_capacity
    ji^.animation_lookup_count = 0

    if old_capacity <= 0 {
        return true
    }

    for i in 0..<old_capacity {
        entry := old_entries[i]
        if !entry.is_occupied || entry.animation == nil {
            continue
        }

        insert_index, found := animation_lookup_probe(
            ji^.animation_lookup_entries,
            ji^.animation_lookup_capacity,
            entry.stable_id,
            true)
        if insert_index < 0 || found {
            return false
        }

        ji^.animation_lookup_entries[insert_index] = core.Euclid_Julia_Animation_Lookup_Entry{
            is_occupied = true,
            stable_id = entry.stable_id,
            animation = entry.animation,
        }
        ji^.animation_lookup_count += 1
    }

    return true
}

//   Ensure the lookup table has enough free space for another inserted animation.
animation_lookup_ensure_capacity :: proc(ji: ^core.Euclid_Julia_Interface) -> bool {
    if ji == nil {
        return false
    }

    if ji^.animation_lookup_capacity == 0 {
        return animation_lookup_grow(ji, ANIMATION_LOOKUP_INITIAL_RESERVE)
    }

    next_count := ji^.animation_lookup_count + 1
    if next_count * ANIMATION_LOOKUP_LOAD_FACTOR_DENOMINATOR <
        ji^.animation_lookup_capacity * ANIMATION_LOOKUP_LOAD_FACTOR_NUMERATOR {
        return true
    }

    return animation_lookup_grow(ji, ji^.animation_lookup_capacity * 2)
}

//   Insert a stable UUID to animation pointer mapping into the lookup table.
animation_lookup_insert :: proc(
    ji: ^core.Euclid_Julia_Interface,
    stable_id: uuid.Identifier,
    node: ^core.Euclid_Julia_Animation_Interface) -> bool {

    if ji == nil || node == nil {
        return false
    }

    if !animation_lookup_ensure_capacity(ji) {
        return false
    }

    insert_index, found := animation_lookup_probe(
        ji^.animation_lookup_entries,
        ji^.animation_lookup_capacity,
        stable_id,
        true)
    if insert_index < 0 || found {
        return false
    }

    ji^.animation_lookup_entries[insert_index] = core.Euclid_Julia_Animation_Lookup_Entry{
        is_occupied = true,
        stable_id = stable_id,
        animation = node,
    }
    ji^.animation_lookup_count += 1
    return true
}

//   Resolve a stable UUID to a registry node pointer.
animation_lookup_find :: proc(
    ji: ^core.Euclid_Julia_Interface,
    stable_id: uuid.Identifier) -> ^core.Euclid_Julia_Animation_Interface {

    if ji == nil || ji^.animation_lookup_capacity <= 0 {
        return nil
    }

    index, found := animation_lookup_probe(
        ji^.animation_lookup_entries,
        ji^.animation_lookup_capacity,
        stable_id,
        false)
    if !found || index < 0 {
        return nil
    }

    return ji^.animation_lookup_entries[index].animation
}

//   Construct and register one animation node using arena storage and UUID lookup.
add_animation_to_registry :: proc(
    state: ^core.Euclid_General_State,
    get_view_text, initiate, loop, clean: ^julialib.jl_value_t,
    name: cstring,
    stable_id: uuid.Identifier,
    parent: ^core.Euclid_Julia_Animation_Interface) -> (^core.Euclid_Julia_Animation_Interface, bool) {

    if state == nil || state^.julia_interface == nil {
        return nil, false
    }

    if !ensure_julia_interface_name_arena(state) {
        return nil, false
    }

    ji := state^.julia_interface
    node := new(core.Euclid_Julia_Animation_Interface, ji^.animation_name_allocator)
    if node == nil {
        return nil, false
    }

    node^.get_view_text = get_view_text
    node^.initiate = initiate
    node^.loop = loop
    node^.clean = clean
    node^.name = strings.clone(string(name), ji^.animation_name_allocator)
    node^.stable_id = stable_id

    animation_append_to_registry(ji, node)
    animation_link_child(parent, node)

    if !animation_lookup_insert(ji, stable_id, node) {
        return nil, false
    }

    return node, true
}

//   Resolve a parent animation from the stable UUID text supplied by Julia.
resolve_parent_animation_by_stable_id :: proc(
    state: ^core.Euclid_General_State,
    parent_stable_id_text: cstring) -> (^core.Euclid_Julia_Animation_Interface, bool) {

    if parent_stable_id_text == nil {
        return nil, false
    }

    parsed_parent_stable_id, ok := parse_animation_stable_id(
        parent_stable_id_text,
        parent_stable_id_text)
    if !ok {
        return nil, false
    }

    parent := find_registered_animation_by_stable_id(state, parsed_parent_stable_id)
    if parent == nil {
        return nil, false
    }

    return parent, true
}
