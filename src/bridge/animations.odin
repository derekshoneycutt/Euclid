package bridge

import "../julialib"
import "../core"
import protocol "../core/protocol"
import "../files"
import evidence_session "../evidence/session"
import evidence_trace "../evidence/trace"
import "../shapes"
import termsession "../terminal/session"
import terminalview "../view/terminal"

import "core:c"
import "core:encoding/uuid"
import "core:fmt"
import "core:log"
import "core:strings"

TERMINAL_ANIMATION_NAME :: "Terminal"
ANIMATION_LOOKUP_INITIAL_RESERVE :: 512
ANIMATION_LOOKUP_LOAD_FACTOR_NUMERATOR :: 7
ANIMATION_LOOKUP_LOAD_FACTOR_DENOMINATOR :: 10
ANIMATION_LIFECYCLE_ACTIVATE :: i32(1)
ANIMATION_LIFECYCLE_RESET :: i32(2)
ANIMATION_LIFECYCLE_RELOAD :: i32(4)
ANIMATION_LIFECYCLE_NATIVE_RESET :: i32(1)
ANIMATION_LIFECYCLE_COMPLETED :: i32(2)

Julia_Interface_Reload_Transaction :: struct {
    state: ^core.Euclid_General_State,
    host: ^Julia_Runtime_Host,
    request: core.Animation_Lifecycle_Requested,
    archive_mtime: i64,
    stable_id: uuid.Identifier,
    candidate: ^julialib.jl_value_t,
    service: ^Julia_Runtime_Service,
    previous_interface: ^core.Euclid_Julia_Interface,
    staged_interface: ^core.Euclid_Julia_Interface,
    staged_slot: int,
    target: ^core.Euclid_Julia_Animation_Interface,
}

//   Invoke one Julia callback through the stack-preserving diagnostic boundary.
call_julia_callback1 :: proc(
    state: ^core.Euclid_General_State, callback, argument: ^julialib.jl_value_t) {

    julialib.jl_call2(
        state^.julia_interface^.invoke_with_exception_diagnostics,
        callback, argument)
}

//   Invoke one two-argument Julia callback through the diagnostic boundary.
call_julia_callback2 :: proc(
    state: ^core.Euclid_General_State, callback, first,
    second: ^julialib.jl_value_t) {

    julialib.jl_call3(
        state^.julia_interface^.invoke_with_exception_diagnostics,
        callback, first, second)
}

//   Invoke Julia-side script initialization and select initial catalog metadata.
//
// Parameters:
//   - state: Global runtime state passed through to Julia callback entry points.
//
// Notes:
//   - Julia exceptions are reported and the call returns early without panicking.
init_euclid_scripts :: proc(state: ^core.Euclid_General_State) -> bool {
    service := state^.julia_runtime_service
    if service == nil || service^.runtime_host == nil {
        log.error("julia_content_runtime_host_missing")
        return false
    }
    state_value := julialib.jl_box_voidpointer(state)

    call_julia_callback2(
        state, state^.julia_interface^.init_scripts,
        service^.runtime_host, state_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("init_euclid_scripts")
        return false
    }
    if !finish_registered_euclid_generation(state) {
        log.error("julia_content_finish_generation_failed")
        return false
    }
    return true
}

//   Complete native initialization after one generation registers its callbacks.
finish_registered_euclid_generation :: proc(
    state: ^core.Euclid_General_State) -> bool {
    if state^.julia_interface^.selected_animation == nil {
        select_default_animation(state)
    }
    return true
}

//   Register one explicitly rooted candidate without executing animation policy.
init_euclid_generation :: proc(
    state: ^core.Euclid_General_State,
    generation: ^julialib.jl_value_t) -> bool {

    main_module := resolve_main_module()
    if main_module == nil || generation == nil {
        return false
    }
    callback := julialib.jl_get_function(
        main_module, "register_euclid_generation")
    if callback == nil {
        return false
    }
    args: [3]^julialib.jl_value_t = {
        state^.julia_runtime_service^.runtime_host,
        generation,
        julialib.jl_box_voidpointer(state),
    }
    _ = julialib.jl_call(callback, &args[0], 3)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("register_euclid_generation")
        return false
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
    if !invoke_animation_lifecycle_transaction(state) {
        if service^.reload_state == .Quiescing {
            service^.reload_state = .Idle
        }
        route_retained_display_view_content(service)
        return false
    }
    if service^.reload_state == .Quiescing {
        service^.reload_state = .Idle
    }
    service^.animation_generation += 1
    service^.animation_accumulated_dt = 0
    release_completed_animation_ticks(service)
    route_retained_display_view_content(service)
    return true
}

//   Verify one typed request owns the pending lifecycle transaction incarnation.
animation_lifecycle_request_owns_slot :: proc(
    service: ^Julia_Runtime_Service,
    request: core.Animation_Lifecycle_Requested) -> bool {
    slot := &service^.animation_lifecycle_slot
    return request.handle.index == 0 && slot^.state == .Pending &&
        slot^.reservation_generation == request.handle.reservation_generation &&
        slot^.request_id == request.request_id &&
        slot^.runtime_generation == request.runtime_generation &&
        slot^.animation_generation == request.animation_generation
}

//   Verify frozen lifecycle intent still matches display-prepared authoritative state.
animation_lifecycle_intent_matches :: proc(
    service: ^Julia_Runtime_Service,
    slot: ^core.Animation_Lifecycle_Slot) -> bool {
    state := slot^.host_state
    if state == nil || state^.julia_interface == nil {
        return false
    }
    selected := state^.julia_interface^.selected_animation
    if selected == nil {
        selected = &state^.julia_interface^.null_animation
    }
    return slot^.runtime_generation == service^.runtime_generation &&
        slot^.animation_generation == service^.animation_generation &&
        slot^.selected_stable_id == selected^.stable_id &&
        slot^.reset_requested == state^.julia_interface^.pending_animation_reset &&
        slot^.reload_requested == service^.reload_requested
}

//   Publish one lifecycle outcome and release the worker-owned slot for handoff.
complete_animation_lifecycle_slot :: proc(
    slot: ^core.Animation_Lifecycle_Slot, succeeded: bool) {
    slot^.outcome = .Committed if succeeded else .Rolled_Back
    slot^.state = .Complete
}

//   Execute one validated reload, selection, or reset against the supervisor.
execute_animation_lifecycle_transition :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service,
    host: ^Julia_Runtime_Host, request: core.Animation_Lifecycle_Requested,
    animation: ^core.Euclid_Julia_Animation_Interface) -> bool {
    if animation_reload_update_needed(state) {
        return reload_packaged_assets_if_updated(
            state, service, host, request, animation)
    }
    operation := ANIMATION_LIFECYCLE_RESET
    if animation != state^.julia_interface^.current_animation {
        operation = ANIMATION_LIFECYCLE_ACTIVATE
    }
    succeeded := invoke_actor_animation_lifecycle(
        service, host, request, animation, operation)
    if succeeded && operation == ANIMATION_LIFECYCLE_ACTIVATE {
        commit_animation_selection(state, animation)
        state^.julia_interface^.pending_animation_reset = false
    } else if succeeded {
        commit_animation_reset_bookkeeping(state)
    }
    return succeeded
}

//   Apply one lifecycle transition on the Julia owner thread.
update_animation_lifecycle :: proc(
    service: ^Julia_Runtime_Service,
    host: ^Julia_Runtime_Host,
    request: core.Animation_Lifecycle_Requested) -> bool {
    slot := &service^.animation_lifecycle_slot
    if !animation_lifecycle_request_owns_slot(service, request) {
        log.warnf(
            "animation_lifecycle_request_rejected request_id=%d slot_generation=%d",
            request.request_id, request.handle.reservation_generation)
        return false
    }
    if !animation_lifecycle_intent_matches(service, slot) {
        log.warnf(
            "animation_lifecycle_intent_stale request_id=%d runtime_generation=%d animation_generation=%d",
            request.request_id, request.runtime_generation,
            request.animation_generation)
        complete_animation_lifecycle_slot(slot, false)
        return false
    }
    state := slot^.host_state
    assert_julia_runtime_owner(state)
    context = state^.saved_context
    animation := state^.julia_interface^.selected_animation
    if animation == nil {
        animation = &state^.julia_interface^.null_animation
    }
    service^.presentation_animation_generation_override =
        service^.animation_generation + 1
    service^.presentation_animation_override = animation
    defer service^.presentation_animation_generation_override = 0
    defer service^.presentation_animation_override = nil
    succeeded := execute_animation_lifecycle_transition(
        state, service, host, request, animation)
    complete_animation_lifecycle_slot(slot, succeeded)
    return succeeded
}

//   Report whether explicit or archive-driven reload work owns this lifecycle turn.
animation_reload_update_needed :: proc(state: ^core.Euclid_General_State) -> bool {
    service := state^.julia_runtime_service
    if service != nil && service^.reload_requested {
        return true
    }
    archive_mtime, ok := files.packaged_asset_archive_modification_unix_nano()
    if !ok {
        return false
    }
    if state^.julia_interface^.asset_archive_mod_time_unix_nano == 0 {
        state^.julia_interface^.asset_archive_mod_time_unix_nano = archive_mtime
        return false
    }
    archive_changed :=
        archive_mtime != state^.julia_interface^.asset_archive_mod_time_unix_nano
    return archive_changed &&
        (service == nil || archive_mtime != service^.reload_failed_mtime_unix_nano)
}

//   Complete one supervisor lifecycle status, including the native reset barrier.
complete_actor_animation_lifecycle :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request_id: u64, operation, status: i32) -> bool {
    if status != ANIMATION_LIFECYCLE_NATIVE_RESET {
        return status == ANIMATION_LIFECYCLE_COMPLETED
    }
    reset_succeeded := reset_animation_switch_state(host^.native_state)
    if operation == ANIMATION_LIFECYCLE_RELOAD &&
        service^.reload_failure_injection == .Animation_Enter {
        service^.reload_failure_injection = .None
        reset_succeeded = false
    }
    return acknowledge_actor_animation_reset(host, request_id, reset_succeeded)
}

//   Invoke one lifecycle transaction and service its typed native reset barrier.
invoke_actor_animation_lifecycle :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request: core.Animation_Lifecycle_Requested,
    animation: ^core.Euclid_Julia_Animation_Interface,
    operation: i32) -> bool {
    if host == nil || host^.runtime == nil || host^.animation_lifecycle == nil ||
        host^.animation_lifecycle_payload_type == nil || animation == nil {
        return false
    }
    if operation == ANIMATION_LIFECYCLE_RELOAD &&
        service^.reload_failure_injection == .Candidate_Load {
        service^.reload_failure_injection = .None
        return false
    }
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        return false
    }
    uuid_buffer: [36]u8
    stable_id := uuid.to_string(animation^.stable_id, uuid_buffer[:])
    payload := Native_Animation_Lifecycle_Payload{
        request_id = request.request_id,
        runtime_generation = service^.runtime_generation,
        animation_generation = service^.animation_generation + 1,
        operation = operation,
    }
    frame := Julia_Animation_Lifecycle_Gc_Frame{
        encoded_root_count = 3 << 2,
        previous = gc_stack^,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    defer gc_stack^ = frame.previous
    frame.roots[0] = host^.runtime
    frame.roots[1] = julialib.jl_new_bits(
        host^.animation_lifecycle_payload_type, &payload)
    frame.roots[2] = julialib.jl_pchar_to_string(
        cstring(raw_data(stable_id)), len(stable_id))
    if frame.roots[1] == nil || frame.roots[2] == nil {
        return false
    }
    result := julialib.jl_call(host^.animation_lifecycle, &frame.roots[0], 3)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("animation_host_lifecycle")
        return false
    }
    status := i32(julialib.jl_unbox_int32(result))
    return complete_actor_animation_lifecycle(
        service, host, request.request_id, operation, status)
}

//   Return native reset completion to the supervisor and await its exact result.
acknowledge_actor_animation_reset :: proc(
    host: ^Julia_Runtime_Host, request_id: u64, accepted: bool) -> bool {
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil || host^.animation_lifecycle_acknowledge_reset == nil {
        return false
    }
    frame := Julia_Animation_Lifecycle_Gc_Frame{
        encoded_root_count = 3 << 2,
        previous = gc_stack^,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    defer gc_stack^ = frame.previous
    frame.roots[0] = host^.runtime
    frame.roots[1] = julialib.jl_box_uint64(request_id)
    frame.roots[2] = julialib.jl_box_bool(c.int8_t(accepted))
    result := julialib.jl_call(
        host^.animation_lifecycle_acknowledge_reset, &frame.roots[0], 3)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("animation_host_acknowledge_reset")
        return false
    }
    return julialib.jl_unbox_bool(result) != 0
}

//   Resolve one checked tick handle and produce its immutable scene batch.
generate_animation_tick :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request: core.Animation_Tick_Requested) -> bool {
    if request.handle.index < 0 ||
        int(request.handle.index) >= len(service^.animation_tick_slots) {
        return false
    }
    slot := &service^.animation_tick_slots[request.handle.index]
    if slot^.state != .Pending ||
        slot^.reservation_generation != request.handle.reservation_generation ||
        slot^.request_id != request.request_id ||
        slot^.generation != request.animation_generation ||
        slot^.sequence != request.sequence {
        return false
    }
    state := slot^.host_state
    assert_julia_runtime_owner(state)
    context = state^.saved_context
    state^.animation_query_snapshot_target = &slot^.query_snapshot
    begin_scene_command_batch(state, &slot^.scene_batch)
    defer end_scene_command_batch(state)
    defer state^.animation_query_snapshot_target = nil
    call_global_euclid_loop(state, slot^.dt)
    animation := slot^.animation
    callback_succeeded := animation == nil ||
        invoke_actor_animation_tick(service, host, request, slot, animation)
    if !callback_succeeded {
        slot^.scene_batch.overflowed = true
    }
    slot^.state = .Complete
    return callback_succeeded
}

//   Transfer one checked primitive tick payload through the actor host adapter.
invoke_actor_animation_tick :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request: core.Animation_Tick_Requested, slot: ^core.Animation_Tick_Slot,
    animation: ^core.Euclid_Julia_Animation_Interface) -> bool {
    if host == nil || host^.runtime == nil || host^.animation_tick == nil ||
        host^.animation_tick_payload_type == nil {
        return false
    }
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        return false
    }
    uuid_buffer: [36]u8
    stable_id := uuid.to_string(animation^.stable_id, uuid_buffer[:])
    payload := Native_Animation_Tick_Payload{
        request_id = request.request_id,
        runtime_generation = service^.runtime_generation,
        animation_generation = request.animation_generation,
        sequence = request.sequence,
        slot_index = request.handle.index,
        reservation_generation = request.handle.reservation_generation,
        dt = slot^.dt,
    }
    frame := Julia_Animation_Tick_Gc_Frame{
        encoded_root_count = 3 << 2,
        previous = gc_stack^,
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&frame)
    defer gc_stack^ = frame.previous
    frame.roots[0] = host^.runtime
    frame.roots[1] = julialib.jl_new_bits(
        host^.animation_tick_payload_type, &payload)
    frame.roots[2] = julialib.jl_pchar_to_string(
        cstring(raw_data(stable_id)), len(stable_id))
    if frame.roots[1] == nil || frame.roots[2] == nil {
        return false
    }
    result := julialib.jl_call(host^.animation_tick, &frame.roots[0], 3)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("animation_host_tick")
        return false
    }
    return julialib.jl_unbox_bool(result) != 0
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
    if state^.julia_runtime_service != nil &&
        state^.julia_runtime_service^.reload_requested {
        return true
    }
    return animation_reload_update_needed(state)
}

//   Read the current animation generation from the runtime service (0 when absent).
current_animation_generation :: proc(state: ^core.Euclid_General_State) -> u64 {
    if state^.julia_runtime_service == nil {
        return 0
    }
    return state^.julia_runtime_service^.animation_generation
}

//   Publish cooldown and evidence after one actor-owned native reset commits.
commit_animation_reset_bookkeeping :: proc(state: ^core.Euclid_General_State) {
    state^.julia_interface^.animation_reset_cooldown_remaining =
        ANIMATION_RESET_MIN_INTERVAL
    state^.julia_interface^.pending_animation_reset = false
    record_julia_evidence(state, {
        lane = .Domain,
        kind = .Animation_Reset_Committed,
        correlation_kind = .Animation,
        correlation = current_animation_generation(state),
        generation = current_animation_generation(state),
        flags = {.Required},
    })
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

    call_julia_callback2(
        state, state^.julia_interface^.global_loop, state_value, dt_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("global_euclid_loop")
        return
    }
}

//   Publish the selected animation pointer and its next host-owned generation.
commit_animation_selection :: proc(
    state: ^core.Euclid_General_State,
    animation: ^core.Euclid_Julia_Animation_Interface) {
    state^.julia_interface^.current_animation = animation
    animation_generation: u64 = 0
    if state^.julia_runtime_service != nil {
        animation_generation = state^.julia_runtime_service^.animation_generation + 1
    }
    record_julia_evidence(state, {
        lane = .Domain,
        kind = .Animation_Selected,
        correlation_kind = .Animation,
        correlation = animation_generation,
        generation = animation_generation,
        flags = {.Required},
    })
}

//   Record one successful UUID binding against its owning runtime generation.
record_animation_loaded :: proc(
    state: ^core.Euclid_General_State,
    animation: ^core.Euclid_Julia_Animation_Interface,
    generation: ^julialib.jl_value_t) {
    runtime_generation := state^.julia_runtime_service^.runtime_generation
    if generation != nil {
        runtime_generation += 1
    }
    record_julia_evidence(state, {
        lane = .Domain,
        kind = .Animation_Loaded,
        correlation_kind = .Animation,
        correlation = animation_hash_stable_id(animation^.stable_id),
        generation = runtime_generation,
        flags = {.Required},
    })
}

//   Clear animation-owned native state into the generation about to initiate.
reset_animation_switch_state :: proc(state: ^core.Euclid_General_State) -> bool {
    target_generation := current_animation_generation(state) + 1
    if state^.terminal.initialized && state^.julia_runtime_service != nil {
        _ = send_terminal_ingress(
            state^.julia_runtime_service, protocol.Terminal_Session_Closed{
                animation_generation = state^.terminal.animation_generation,
            })
    }
    termsession.terminal_session_destroy(&state^.shell.session)
    state^.shell.phase = .Inactive
    if state^.terminal_graphics_release != nil &&
       state^.simulation_executor != nil {
        state^.terminal_graphics_release(
            state^.terminal_graphics_user_data,
            &state^.simulation_executor^.pool)
    }
    terminalview.terminal_destroy(&state^.terminal)
    if core.animation_storage_begin_generation(
        &state^.animation_memory,
        &state^.animation_values,
        &state^.dynview_documents,
        target_generation) != .Ok {
        return false
    }
    shapes.clear_animation_data(
        state^.point_system, state^.particle_system, state^.iso_scale)
    hide_pen(state)
    hide_compass(state)
    state^.animation_drawing_sound_enabled = true
    return true
}

//   Synchronize one programmatic animation selection and request its tree reveal.
select_animation_programmatically :: proc(
    state: ^core.Euclid_General_State,
    selected: ^core.Euclid_Julia_Animation_Interface) -> bool {

    if state == nil || state^.julia_interface == nil || selected == nil {
        return false
    }

    ji := state^.julia_interface
    found := false
    for node := ji^.animation_head; node != nil; node = node^.next_in_registry {
        found = found || node == selected
    }
    if !found {
        return false
    }

    for node := ji^.animation_head; node != nil; node = node^.next_in_registry {
        node^.is_selected = node == selected
    }
    ji^.selected_animation = selected
    ancestor := selected^.parent
    for steps := 0; ancestor != nil && steps < ji^.animation_count; steps += 1 {
        ancestor^.is_expanded = true
        ancestor = ancestor^.parent
    }
    state^.ui_runtime.tree_reveal_pending = true
    state^.ui_runtime.tree_reveal_stable_id = selected^.stable_id
    return true
}

//   Select the first non-Terminal animation as default selection.
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
        if node^.name == TERMINAL_ANIMATION_NAME {
            continue
        }

        target = node
        break
    }

    if target == nil {
        return
    }

    _ = select_animation_programmatically(state, target)
}

//   Select one animation by stable UUID without involving UI input handling.
//
// Parameters:
//   - state: Global runtime state containing the active Julia interface.
//   - stable_id: Stable animation UUID to select.
//
// Returns:
//   - ok: true when the animation exists and selection state was updated.
select_animation_by_stable_id :: proc(
    state: ^core.Euclid_General_State,
    stable_id: uuid.Identifier) -> bool {

    if state == nil || state^.julia_interface == nil {
        return false
    }

    selected := find_animation_by_stable_id(state, stable_id)
    if selected == nil {
        return false
    }

    return select_animation_programmatically(state, selected)
}

//   Invoke one harness scenario callback on the Julia owner thread.
//
// Parameters:
//   - state: Global runtime state forwarded to Julia.
//   - scenario_name: Scenario function name resolved from Main.
//   - step_count: Number of deterministic fixed steps already executed.
//
// Returns:
//   - ok: true when the scenario callback completed successfully.
invoke_harness_scenario :: proc(
    state: ^core.Euclid_General_State,
    scenario_name: string,
    step_count: int) -> bool {

    if state == nil || len(scenario_name) == 0 {
        return false
    }

    return invoke_harness_transaction(state, scenario_name, i64(step_count))
}

//   Execute one harness scenario callback after deterministic stepping.
run_harness_scenario :: proc(
    host: ^Julia_Runtime_Host,
    request: core.Harness_Scenario_Requested) -> bool {
    state := host^.native_state
    assert_julia_runtime_owner(state)
    context = state^.saved_context

    main_module := resolve_main_module()
    if main_module == nil || len(request.scenario_name) == 0 {
        return false
    }

    callback := julialib.jl_get_function(
        main_module, "invoke_generation_harness_scenario")
    if callback == nil || host^.runtime == nil {
        return false
    }

    scenario_bytes := transmute([]u8)request.scenario_name
    state_value := julialib.jl_box_voidpointer(state)
    step_value := julialib.jl_box_int64(request.step_count)
    result := julialib.jl_call4(
        callback,
        host^.runtime,
        julialib.jl_pchar_to_string(
            cstring(raw_data(scenario_bytes)), len(scenario_bytes)),
        state_value,
        step_value)
    if julialib.jl_exception_occurred() != nil {
        print_julia_exception("harness scenario")
        return false
    }
    if result == nil {
        return false
    }
    return julialib.jl_unbox_bool(result) != 0
}

/* TODO: Can we kill this?
//   Clear animation registry state and reset interface selection fields to defaults.
reset_julia_interface_registry :: proc(state: ^core.Euclid_General_State) {
    clean_julia_interfaces(state)

    state^.julia_interface^.null_animation = {}
    state^.julia_interface^.current_animation = &state^.julia_interface^.null_animation
    state^.julia_interface^.selected_animation = nil
    state^.julia_interface^.pending_animation_reset = false
    state^.julia_interface^.animation_reset_cooldown_remaining = 0
}*/

//   Find an animation pointer by its registered stable UUID identity.
find_animation_by_stable_id :: proc(
    state: ^core.Euclid_General_State,
    stable_id: uuid.Identifier) -> ^core.Euclid_Julia_Animation_Interface {

    if state == nil || state^.julia_interface == nil {
        return nil
    }

    return animation_lookup_find(state^.julia_interface, stable_id)
}

//   Record one reload lifecycle event using current runtime service state.
//
// Parameters:
//   - state: Global runtime state containing trace and Julia service pointers.
//   - event_name: Runtime lifecycle event name to emit.
//
// Returns:
//   - none.
record_runtime_reload_event :: proc(
    state: ^core.Euclid_General_State, event_name: string) {
    if state == nil {
        return
    }
    service := state^.julia_runtime_service
    kind := evidence_trace.Kind.Runtime_Reload_Started
    flags: evidence_trace.Flags = {.Required}
    if event_name == "runtime.reload_committed" {
        kind = .Runtime_Reload_Committed
    } else if event_name == "runtime.reload_rolled_back" {
        kind = .Runtime_Reload_Rolled_Back
        flags += {.Failure}
    }
    target_generation := service != nil ? service^.runtime_generation : 0
    if event_name != "runtime.reload_committed" {
        target_generation += 1
    }
    record_julia_evidence(state, {
        lane = .Lifecycle,
        kind = kind,
        correlation_kind = .Runtime_Request,
        correlation = target_generation,
        generation = target_generation,
        flags = flags,
    })
}

//   Detect packaged asset updates and hot-reload Julia script/interface state when changed.
reload_packaged_assets_if_updated :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service,
    host: ^Julia_Runtime_Host, request: core.Animation_Lifecycle_Requested,
    target: ^core.Euclid_Julia_Animation_Interface) -> bool {
    archive_mtime, ok := files.packaged_asset_archive_modification_unix_nano()
    if !ok {
        return true
    }

    force_reload := service != nil && service^.reload_requested
    if service != nil {
        service^.reload_requested = false
    }
    if !force_reload && asset_archive_mtime_current(state, archive_mtime) {
        return true
    }
    if !force_reload && service != nil &&
        archive_mtime == service^.reload_failed_mtime_unix_nano {
        return true
    }
    if service != nil {
        service^.reload_state = .Including
    }
    record_runtime_reload_event(state, "runtime.reload_started")

    if !refresh_packaged_assets(state, service, archive_mtime) {
        return false
    }

    reloaded := stage_julia_interface_reload(
        state, host, request, archive_mtime, target^.stable_id)
    if !reloaded {
        record_runtime_reload_event(state, "runtime.reload_rolled_back")
        return false
    }

    record_runtime_reload_event(state, "runtime.reload_committed")
    return true
}

//   Track the archive mtime and report whether it already matches the active state.
//
// Returns:
//   - true when the archive mtime is unchanged (or just seeded), so no reload is needed.
asset_archive_mtime_current :: proc(
    state: ^core.Euclid_General_State, archive_mtime: i64) -> bool {

    if state^.julia_interface^.asset_archive_mod_time_unix_nano == 0 {
        state^.julia_interface^.asset_archive_mod_time_unix_nano = archive_mtime
        return true
    }
    return archive_mtime == state^.julia_interface^.asset_archive_mod_time_unix_nano
}

//   Re-extract packaged assets, rolling back and reporting on failure.
//
// Returns:
//   - true when the candidate source tree was refreshed successfully.
refresh_packaged_assets :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service, archive_mtime: i64) -> bool {

    if !files.reload_packaged_assets_root() {
        fmt.eprintln("Julia asset reload skipped: failed to re-extract assets package")
        mark_julia_reload_failed(service, archive_mtime)
        record_runtime_reload_event(state, "runtime.reload_rolled_back")
        return false
    }
    return true
}

//   Construct one generation into a caller-rooted Julia value slot.
create_julia_runtime_generation :: proc() -> ^julialib.jl_value_t {
    main_module := resolve_main_module()
    if main_module == nil {
        return nil
    }
    constructor := julialib.jl_get_function(
        main_module, "create_euclid_runtime_generation")
    if constructor == nil {
        return nil
    }
    generation := julialib.jl_call0(constructor)
    if generation == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("create_euclid_runtime_generation")
        return nil
    }
    return generation
}

//   Commit one validated candidate as the runtime host's active generation.
commit_julia_runtime_generation :: proc(
    service: ^Julia_Runtime_Service,
    generation: ^julialib.jl_value_t) -> bool {

    main_module := resolve_main_module()
    if main_module == nil || service == nil || service^.runtime_host == nil ||
        generation == nil {
        return false
    }
    callback := julialib.jl_get_function(
        main_module, "commit_euclid_runtime_generation")
    if callback == nil {
        return false
    }
    result := julialib.jl_call2(callback, service^.runtime_host, generation)
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("commit_euclid_runtime_generation")
        return false
    }
    return julialib.jl_unbox_bool(result) != 0
}

//   Root one candidate generation in the runtime host before actor validation.
stage_julia_runtime_generation :: proc(
    service: ^Julia_Runtime_Service,
    generation: ^julialib.jl_value_t) -> bool {
    main_module := resolve_main_module()
    if main_module == nil || service == nil || service^.runtime_host == nil ||
        generation == nil {
        return false
    }
    callback := julialib.jl_get_function(
        main_module, "stage_euclid_runtime_generation")
    if callback == nil {
        return false
    }
    result := julialib.jl_call2(callback, service^.runtime_host, generation)
    return result != nil && julialib.jl_exception_occurred() == nil &&
        julialib.jl_unbox_bool(result) != 0
}

//   Retire the runtime host's uncommitted candidate after rollback.
discard_julia_runtime_generation :: proc(service: ^Julia_Runtime_Service) {
    main_module := resolve_main_module()
    if main_module == nil || service == nil || service^.runtime_host == nil {
        return
    }
    callback := julialib.jl_get_function(
        main_module, "discard_euclid_runtime_generation")
    if callback != nil {
        _ = julialib.jl_call1(callback, service^.runtime_host)
    }
}

//   Register and validate one fresh interface before retiring the active generation.
stage_julia_interface_reload :: proc(
    state: ^core.Euclid_General_State, host: ^Julia_Runtime_Host,
    request: core.Animation_Lifecycle_Requested, archive_mtime: i64,
    stable_id: uuid.Identifier) -> bool {

    service := state^.julia_runtime_service
    if service == nil || service^.runtime_host == nil {
        return false
    }
    service^.reload_state = .Registering
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        fmt.eprintln("Julia asset reload: owner thread has no GC stack")
        mark_julia_reload_failed(service, archive_mtime)
        return false
    }
    candidate: ^julialib.jl_value_t
    candidate_frame := Julia_Runtime_Gc_Frame{
        encoded_root_count = (1 << 2) | 1,
        previous = gc_stack^,
        root = rawptr(&candidate),
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&candidate_frame)
    defer gc_stack^ = candidate_frame.previous
    candidate = create_julia_runtime_generation()
    if candidate == nil {
        fmt.eprintln("Julia asset reload: candidate generation construction failed")
        mark_julia_reload_failed(service, archive_mtime)
        return false
    }
    transaction := Julia_Interface_Reload_Transaction{
        state = state,
        host = host,
        request = request,
        archive_mtime = archive_mtime,
        stable_id = stable_id,
        candidate = candidate,
        service = service,
    }
    return validate_julia_interface_reload(&transaction)
}

//   Register one candidate and select its requested target without entering it.
initialize_and_restore_julia_candidate :: proc(
    state: ^core.Euclid_General_State, stable_id: uuid.Identifier,
    candidate: ^julialib.jl_value_t) -> (bool, bool) {
    initialized := init_euclid_generation(state, candidate)
    if !initialized {
        return false, false
    }
    target := find_animation_by_stable_id(state, stable_id)
    if target == nil &&
        stable_id == state^.julia_interface^.null_animation.stable_id {
        target = &state^.julia_interface^.null_animation
        state^.julia_interface^.selected_animation = target
        return true, true
    }
    return true, select_animation_programmatically(state, target)
}

//   Roll back one candidate transaction after an explicit diagnostic.
reject_julia_interface_reload :: proc(
    transaction: ^Julia_Interface_Reload_Transaction,
    message: string, discard_candidate: bool) -> bool {
    fmt.eprintln(message)
    if discard_candidate {
        discard_julia_runtime_generation(transaction^.service)
    }
    rollback_julia_interface_reload(
        transaction^.state, transaction^.previous_interface,
        transaction^.staged_interface, transaction^.service,
        transaction^.archive_mtime)
    return false
}

//   Register and resolve the requested animation in one inactive interface.
prepare_julia_interface_reload_candidate :: proc(
    transaction: ^Julia_Interface_Reload_Transaction) -> bool {
    state := transaction^.state
    transaction^.previous_interface = state^.julia_interface
    transaction^.staged_interface, transaction^.staged_slot =
        julia_interface_staging_slot(state)
    staged_interface := transaction^.staged_interface
    prepare_julia_interface_generation(staged_interface)
    if !julia_interface_handles_valid(staged_interface) {
        fmt.eprintln("Julia asset reload: stable callback validation failed")
        clean_julia_interface_instance(staged_interface)
        mark_julia_reload_failed(transaction^.service, transaction^.archive_mtime)
        return false
    }
    staged_interface^.asset_archive_mod_time_unix_nano = transaction^.archive_mtime
    state^.julia_interface = staged_interface
    initialized, restored := initialize_and_restore_julia_candidate(
        state, transaction^.stable_id, transaction^.candidate)
    if !initialized || !restored {
        message := "Julia asset reload: active animation restoration failed"
        if !initialized { message = "Julia asset reload: candidate registration failed" }
        return reject_julia_interface_reload(transaction, message, false)
    }
    transaction^.target = state^.julia_interface^.selected_animation
    return true
}

//   Activate and commit one prepared candidate generation through the supervisor.
activate_julia_interface_reload_candidate :: proc(
    transaction: ^Julia_Interface_Reload_Transaction) -> bool {
    service := transaction^.service
    candidate := transaction^.candidate
    if !stage_julia_runtime_generation(service, candidate) {
        return reject_julia_interface_reload(transaction,
            "Julia asset reload: candidate host staging failed", false)
    }
    if !invoke_actor_animation_lifecycle(
        service, transaction^.host, transaction^.request,
        transaction^.target, ANIMATION_LIFECYCLE_RELOAD) {
        return reject_julia_interface_reload(transaction,
            "Julia asset reload: candidate activation failed", true)
    }
    if !commit_julia_runtime_generation(service, candidate) {
        return reject_julia_interface_reload(transaction,
            "Julia asset reload: candidate commit failed", true)
    }
    return true
}

//   Validate one rooted candidate against the inactive interface and publish on success.
validate_julia_interface_reload :: proc(
    transaction: ^Julia_Interface_Reload_Transaction) -> bool {
    if !prepare_julia_interface_reload_candidate(transaction) ||
        !activate_julia_interface_reload_candidate(transaction) {
        return false
    }
    state := transaction^.state
    commit_animation_selection(state, transaction^.target)
    record_animation_loaded(state, transaction^.target, transaction^.candidate)
    publish_julia_interface_reload(
        state, transaction^.previous_interface,
        transaction^.staged_slot, transaction^.service)
    return true
}

//   Restore the active generation after staged registration or activation fails.
rollback_julia_interface_reload :: proc(
    state: ^core.Euclid_General_State,
    previous_interface, staged_interface: ^core.Euclid_Julia_Interface,
    service: ^Julia_Runtime_Service, archive_mtime: i64) {

    clean_julia_interface_instance(staged_interface)
    state^.julia_interface = previous_interface
    service^.reload_failure_injection = .None
    julialib.jl_gc_collect(.JL_GC_FULL)
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

    if service != nil {
        service^.reload_failure_injection = .None
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
    animation_generation: u64 = 0
    if state^.julia_runtime_service != nil {
        animation_generation = state^.julia_runtime_service^.animation_generation
    }
    animation_tick_sequence: u64 = 0
    if state^.julia_runtime_service != nil {
        animation_tick_sequence = state^.julia_runtime_service^.animation_tick_sequence
    }
    record_julia_evidence(state, {
        lane = .Domain,
        kind = .Animation_Cycle_Boundary,
        correlation_kind = .Animation_Tick,
        correlation = animation_tick_sequence,
        generation = animation_generation,
        flags = {.Required},
    })
}

//   Record one semantic event from the Julia owner without formatting or allocation.
record_julia_evidence :: proc(
    state: ^core.Euclid_General_State, event: evidence_trace.Event) {
    if state == nil || state.julia_runtime_service == nil {
        return
    }
    service := state.julia_runtime_service
    _ = evidence_session.session_record(
        service.evidence_session, &service.evidence_ring, event)
}

/* TODO : Can we kill this?
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
}*/

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

    return rehash_animation_lookup(ji, old_entries, old_capacity)
}

//   Reinsert every occupied entry from the old lookup table into the grown one.
//
// Returns:
//   - true when all occupied entries rehash without collision or overflow.
rehash_animation_lookup :: proc(
    ji: ^core.Euclid_Julia_Interface,
    old_entries: []core.Euclid_Julia_Animation_Lookup_Entry,
    old_capacity: int) -> bool {

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

        ji^.animation_lookup_entries[insert_index] =
            core.Euclid_Julia_Animation_Lookup_Entry{
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
    entry: ^julialib.jl_value_t,
    name: cstring,
    stable_id: uuid.Identifier,
    parent: ^core.Euclid_Julia_Animation_Interface) -> (
        ^core.Euclid_Julia_Animation_Interface, bool) {

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

    node^.entry = entry
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
