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

Animation_Lifecycle_Task_Data :: struct {
    state: ^core.Euclid_General_State,
}

//   Invoke Julia-side script initialization and optional null-animation init hook.
//
// Parameters:
//   - state: Global runtime state passed through to Julia callback entry points.
//
// Notes:
//   - Julia exceptions are reported and the call returns early without panicking.
init_euclid_scripts :: proc(state: ^core.Euclid_General_State) -> bool {
    state_value := julialib.jl_box_voidpointer(state)

    julialib.jl_call1(state^.julia_interface^.init_scripts, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("init_euclid_scripts")
        return false
    }

    if state^.julia_interface^.null_animation.initiate != nil {
        julialib.jl_call1(state^.julia_interface^.null_animation.initiate, state_value)
        if julialib.jl_exception_occurred() != nil {
            print_julia_exception("init_euclid_scripts")
            return false
        }
    }

    if state^.julia_interface^.selected_animation == nil {
        select_default_animation(state)
    }
    return true
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
schedule_animation_tick :: proc(state: ^core.Euclid_General_State, dt: f32) {
    advance_animation_reset_cooldown(state, dt)
    if state^.julia_interface^.pending_animation_reset &&
        state^.julia_interface^.animation_reset_cooldown_remaining > 0 {
        return
    }
    if animation_lifecycle_update_needed(state) {
        if !synchronize_animation_lifecycle(state) {
            return
        }
    }
    _ = try_request_animation_tick(state, dt)
}

//   Run selection, reset, or reload only after asynchronous work is quiescent.
synchronize_animation_lifecycle :: proc(state: ^core.Euclid_General_State) -> bool {
    service := state^.julia_runtime_service
    if service == nil || service^.animation_tick_pending {
        return false
    }
    service^.reload_state = .Quiescing
    task_data := Animation_Lifecycle_Task_Data{state = state}
    if !invoke_julia_compatibility_task(state, update_animation_lifecycle_task, rawptr(&task_data)) {
        if service^.reload_state == .Quiescing {
            service^.reload_state = .Idle
        }
        return false
    }
    if service^.reload_state == .Quiescing {
        service^.reload_state = .Idle
    }
    service^.animation_generation += 1
    service^.animation_accumulated_dt = 0
    release_completed_animation_ticks(service)
    return true
}

//   Apply one lifecycle transition on the Julia owner thread.
update_animation_lifecycle_task :: proc(data: rawptr) -> bool {
    task_data := cast(^Animation_Lifecycle_Task_Data)data
    assert_julia_runtime_owner(task_data^.state)
    context = task_data^.state^.saved_context
    return update_running_animations(task_data^.state)
}

//   Produce one immutable scene batch without touching canonical query state.
generate_animation_tick_task :: proc(data: rawptr) -> bool {
    slot := cast(^Animation_Tick_Slot)data
    state := slot^.host_state
    assert_julia_runtime_owner(state)
    context = state^.saved_context
    state^.animation_query_snapshot_target = &slot^.query_snapshot
    begin_scene_command_batch(state, &slot^.scene_batch)
    call_global_euclid_loop(state, slot^.dt)
    callback_succeeded := call_current_animation_loop(state, slot^.dt)
    end_scene_command_batch(state)
    state^.animation_query_snapshot_target = nil
    if !callback_succeeded {
        slot^.scene_batch.overflowed = true
    }
    slot^.state = .Complete
    return callback_succeeded
}

//   Decrement display-owned reset cooldown independently of Julia work.
advance_animation_reset_cooldown :: proc(state: ^core.Euclid_General_State, dt: f32) {
    cooldown := &state^.julia_interface^.animation_reset_cooldown_remaining
    if cooldown^ > 0 {
        cooldown^ = max(cooldown^ - dt, 0)
    }
}

//   Return whether rare lifecycle work must quiesce asynchronous ticks.
animation_lifecycle_update_needed :: proc(state: ^core.Euclid_General_State) -> bool {
    ji := state^.julia_interface
    if ji^.selected_animation != ji^.current_animation {
        return true
    }
    if ji^.pending_animation_reset && ji^.animation_reset_cooldown_remaining <= 0 {
        return true
    }
    archive_mtime, ok := files.packaged_asset_archive_modification_unix_nano()
    if !ok {
        return false
    }
    service := state^.julia_runtime_service
    return ji^.asset_archive_mod_time_unix_nano == 0 ||
        archive_mtime != ji^.asset_archive_mod_time_unix_nano &&
        (service == nil || archive_mtime != service^.reload_failed_mtime_unix_nano)
}

//   Call the active Julia view-text function from the Julia owner thread.
call_current_animation_get_view_text_direct :: proc(
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
update_running_animations :: proc(state: ^core.Euclid_General_State) -> bool {
    if !reload_packaged_assets_if_updated(state) {
        return false
    }

    switched_animation := false
    if state^.julia_interface^.selected_animation !=
        state^.julia_interface^.current_animation {
        previous_animation := state^.julia_interface^.current_animation
        if !change_current_animation_loop(state, state^.julia_interface^.selected_animation) {
            return false
        }
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
                if !reset_current_animation_loop(state) {
                    return false
                }
                state^.julia_interface^.animation_reset_cooldown_remaining = ANIMATION_RESET_MIN_INTERVAL
                state^.julia_interface^.pending_animation_reset = false
            }
        }
    }
    return true
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
call_current_animation_loop :: proc(state: ^core.Euclid_General_State, dt: f32) -> bool {
    if state^.julia_interface^.current_animation == nil {
        return true
    }

    if state^.julia_interface^.current_animation.loop == nil {
        return true
    }

    state_value := julialib.jl_box_voidpointer(state)
    dt_value := julialib.jl_box_float32(dt)

    julialib.jl_call2(state^.julia_interface^.current_animation^.loop,
        state_value, dt_value)

    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Current animation loop")
        return false
    }
    return true
}

//   Switch to a selected animation, cleaning previous state and initializing the new loop.
//
// Notes:
//   - Clears animation-owned shapes data and tool visibility before initializing the target animation.
change_current_animation_loop :: proc(
    state: ^core.Euclid_General_State,
    new_animation: ^core.Euclid_Julia_Animation_Interface) -> bool {

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
            return false
        }
    }

    shapes.clear_animation_data(state^.point_system, state^.particle_system, state^.iso_scale)
    hide_pen(state)
    hide_compass(state)
    for i in 0..<len(state^.anim_metadata) {
        state^.anim_metadata[i] = 0.0
    }
    state^.animation_drawing_sound_enabled = true

    if animation^.initiate != nil {
        julialib.jl_call1(animation^.initiate, state_value)
        if julialib.jl_exception_occurred() != nil {
            print_julia_exception("Initiating new animation loop")
            return false
        }
    }

    state^.julia_interface^.current_animation = animation
    return true
}

//   Restart the currently selected animation by running clean then initiate callbacks.
reset_current_animation_loop :: proc(state: ^core.Euclid_General_State) -> bool {
    if state^.julia_interface^.current_animation^.loop == nil {
        return true
    }

    state_value := julialib.jl_box_voidpointer(state)

    julialib.jl_call1(state^.julia_interface^.current_animation^.clean, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Cleaning previous animation loop")
        return false
    }

    shapes.clear_animation_data(state^.point_system, state^.particle_system, state^.iso_scale)
    hide_pen(state)
    hide_compass(state)
    for i in 0..<len(state^.anim_metadata) {
        state^.anim_metadata[i] = 0.0
    }
    state^.animation_drawing_sound_enabled = true

    julialib.jl_call1(state^.julia_interface^.current_animation^.initiate, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("Initiating new animation loop")
        return false
    }
    return true
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
    animation_stable_id: uuid.Identifier) -> bool {

    restored_animation := find_animation_by_stable_id(state, animation_stable_id)
    if restored_animation != nil {
        state^.julia_interface^.selected_animation = restored_animation
        return change_current_animation_loop(state, restored_animation)
    }

    fmt.eprintln("Julia asset reload: unable to restore animation for requested stable_id")
    return false
}

//   Detect packaged asset updates and hot-reload Julia script/interface state when changed.
reload_packaged_assets_if_updated :: proc(state: ^core.Euclid_General_State) -> bool {
    archive_mtime, ok := files.packaged_asset_archive_modification_unix_nano()
    if !ok {
        return true
    }

    if state^.julia_interface^.asset_archive_mod_time_unix_nano == 0 {
        state^.julia_interface^.asset_archive_mod_time_unix_nano = archive_mtime
        return true
    }
    if archive_mtime == state^.julia_interface^.asset_archive_mod_time_unix_nano {
        return true
    }

    service := state^.julia_runtime_service
    if service != nil && archive_mtime == service^.reload_failed_mtime_unix_nano {
        return true
    }
    if service != nil {
        service^.reload_state = .Including
    }

    if !files.reload_packaged_assets_root() {
        fmt.eprintln("Julia asset reload skipped: failed to re-extract assets package")
        mark_julia_reload_failed(service, archive_mtime)
        return false
    }
    if !include_packaged_script(false) {
        fmt.eprintln("Julia asset reload skipped: failed to re-include script.jl")
        mark_julia_reload_failed(service, archive_mtime)
        return false
    }

    stable_id, has_stable_id := active_animation_stable_id(state)
    return stage_julia_interface_reload(state, archive_mtime, stable_id, has_stable_id)
}

//   Return stable identity for the current non-null animation generation.
active_animation_stable_id :: proc(
    state: ^core.Euclid_General_State) -> (uuid.Identifier, bool) {

    active_animation := state^.julia_interface^.current_animation
    if active_animation == nil || active_animation == &state^.julia_interface^.null_animation {
        return {}, false
    }
    return active_animation^.stable_id, true
}

//   Register and validate one fresh interface before retiring the active generation.
stage_julia_interface_reload :: proc(
    state: ^core.Euclid_General_State, archive_mtime: i64,
    stable_id: uuid.Identifier, has_stable_id: bool) -> bool {

    service := state^.julia_runtime_service
    previous_interface := state^.julia_interface
    if service != nil {
        service^.reload_state = .Registering
    }
    staged_interface, staged_slot := julia_interface_staging_slot(state)
    prepare_julia_interface_generation(staged_interface)
    if !julia_interface_handles_valid(staged_interface) {
        clean_julia_interface_instance(staged_interface)
        mark_julia_reload_failed(service, archive_mtime)
        return false
    }
    staged_interface^.asset_archive_mod_time_unix_nano = archive_mtime
    state^.julia_interface = staged_interface
    initialized := init_euclid_scripts(state)
    restored := initialized
    if initialized && has_stable_id {
        restored = restore_current_animation_after_reload(state, stable_id)
    }
    if !initialized || !restored {
        rollback_julia_interface_reload(
            state, previous_interface, staged_interface, service, archive_mtime)
        return false
    }
    publish_julia_interface_reload(state, previous_interface, staged_slot, service)
    return true
}

//   Restore the active generation after staged registration or activation fails.
rollback_julia_interface_reload :: proc(
    state: ^core.Euclid_General_State,
    previous_interface, staged_interface: ^core.Euclid_Julia_Interface,
    service: ^Julia_Runtime_Service, archive_mtime: i64) {

    clean_julia_interface_instance(staged_interface)
    state^.julia_interface = previous_interface
    _ = reset_current_animation_loop(state)
    mark_julia_reload_failed(service, archive_mtime)
}

//   Publish one validated interface generation and retire its predecessor.
publish_julia_interface_reload :: proc(
    state: ^core.Euclid_General_State,
    previous_interface: ^core.Euclid_Julia_Interface,
    staged_slot: int,
    service: ^Julia_Runtime_Service) {

    if service != nil {
        service^.reload_state = .Publishing
    }
    clean_julia_interface_instance(previous_interface)
    state^.julia_interface_active_slot = staged_slot

    // Keep Odin-side scratchpad editor buffer aligned with Julia session reset on reload.
    state^.ui_runtime.scratchpad_input_len = 0
    state^.ui_runtime.scratchpad_input_cursor = 0
    state^.ui_runtime.scratchpad_follow_output = false
    if service != nil {
        service^.runtime_generation += 1
        service^.reload_failed_mtime_unix_nano = 0
        service^.reload_state = .Idle
    }
}

//   Preserve the active generation and suppress retries for one broken package revision.
mark_julia_reload_failed :: proc(service: ^Julia_Runtime_Service, archive_mtime: i64) {
    if service == nil {
        return
    }
    service^.reload_failed_mtime_unix_nano = archive_mtime
    service^.reload_state = .Failed
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
        new_capacity, ji^.animation_registry_allocator)
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

    if !ensure_julia_interface_registry_arena(state) {
        return nil, false
    }

    ji := state^.julia_interface
    node := new(core.Euclid_Julia_Animation_Interface, ji^.animation_registry_allocator)
    if node == nil {
        return nil, false
    }

    node^.get_view_text = get_view_text
    node^.initiate = initiate
    node^.loop = loop
    node^.clean = clean
    node^.name = strings.clone(string(name), ji^.animation_registry_allocator)
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
