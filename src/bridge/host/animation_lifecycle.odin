package julia_host

import bridge_scene "../scene"
import bridge_events "../events"
import bridge_animation "../animation"
import bridgemodel "../model"
import shapemodel "../../shapes/model"
import audio "../../audio"
import julialib "../../../libs/julia/bindings"
import core "../../core"
import exerciseheader "../../core/exercise_header"
import animation_model "../../core/animation"
import protocol "../../core/protocol"
import files "../../files"
import particles "../../particles"
import terminalview "../../view/terminal"
import viewterminalmodel "../../view/terminal/model"
import c "core:c"
import uuid "core:encoding/uuid"
import log "core:log"
import time "core:time"
import projection "../../view/world/projection"
import capturemodel "../../view/capture/model"

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
    if state^.ui_runtime.playback.completion_requested {
        _ = try_request_animation_completed(state)
        return
    }
    if state^.ui_runtime.playback.construction_paused ||
        state^.ui_runtime.playback.animation_policy_paused {
        clear_animation_accumulated_time(state^.julia_runtime_service)
        audio.set_drawing_activity(&state^.chalk_audio, false)
        return
    }
    _ = try_request_animation_tick(state, dt)
}

// Drop paused elapsed time without changing committed authored progress.
clear_animation_accumulated_time :: proc(service: ^Julia_Runtime_Service) {
    if service != nil {
        service^.animation_accumulated_dt = 0
        service^.animation_accumulated_authored_dt = 0
        service^.animation_accumulated_accelerated = false
    }
}

// Submit a distinct authored completion using the existing bounded scene-result slot.
try_request_animation_completed :: proc(state: ^core.Euclid_General_State) -> bool {
    service := state^.julia_runtime_service
    if service == nil || service^.animation_tick_pending {
        return false
    }
    if !state^.ui_runtime.playback.construction_paused ||
        state^.julia_interface^.current_animation == nil ||
        state^.julia_interface^.current_animation^.node_kind == .Terminal {
        state^.ui_runtime.playback.completion_requested = false
        state^.ui_runtime.playback.completion_failed = true
        log.warn("animation_completion_rejected_invalid_transport")
        return false
    }
    if capturemodel.gif_capture_locks_playback_rate(
        state^.gif_capture_status.gif_capture_phase,
        state^.gif_capture_status.save_gif_requested) {
        state^.ui_runtime.playback.completion_requested = false
        state^.ui_runtime.playback.completion_failed = true
        log.warn("animation_completion_rejected_during_capture")
        return false
    }
    index := reserve_animation_tick_slot(service)
    if index < 0 {
        return false
    }
    clear_animation_accumulated_time(service)
    service^.animation_tick_sequence += 1
    slot := &service^.animation_tick_slots[index]
    fill_animation_tick_slot(state, slot, 0, 0, false)
    slot^.show_completed = true
    return submit_animation_tick_slot(service, slot, index, 0)
}

//   Run selection, reset, or reload only after asynchronous work is quiescent.
synchronize_animation_lifecycle :: proc(state: ^core.Euclid_General_State) -> bool {
    service := state^.julia_runtime_service
    if service == nil || service^.animation_tick_pending {
        return false
    }
    selecting := state^.julia_interface^.selected_animation !=
        state^.julia_interface^.current_animation
    reopening_completed := !selecting && state^.ui_runtime.playback.completed &&
        !state^.julia_interface^.pending_animation_reset
    header_request_floor := animation_header_request_floor(service, selecting)
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
    service.animation_accumulated_authored_dt = 0
    service.animation_accumulated_accelerated = false
    service.animation_last_commit_accelerated = false
    service^.animation_progress = 0
    particles.formation_reset_generation(
        &state^.particle_system, service^.animation_generation)
    animation_clear_header_after_navigation(state, selecting, header_request_floor)
    restore_animation_completion_intent(state, selecting, reopening_completed)
    release_completed_animation_ticks(service)
    route_retained_display_view_content(service)
    return true
}

// Snapshot pre-transition header traffic so newly selected content remains eligible.
animation_header_request_floor :: proc(
    service: ^Julia_Runtime_Service, selecting: bool) -> u64 {
    if !selecting {
        return 0
    }
    return bridgemodel.exercise_header_request_latest(
        &service^.exercise_header_request_sequence)
}

// Clear instructions only after a committed selection, never for a restart.
animation_clear_header_after_navigation :: proc(
    state: ^core.Euclid_General_State, selecting: bool, request_floor: u64) {
    if !selecting {
        return
    }
    if request_floor > state^.exercise_header.last_request_id {
        state^.exercise_header.last_request_id = request_floor
    }
    exerciseheader.hide(&state^.exercise_header)
}

// Restore held completion after reload or apply completed-first to a new selection.
restore_animation_completion_intent :: proc(
    state: ^core.Euclid_General_State, selecting, reopening_completed: bool) {
    playback := &state^.ui_runtime.playback
    playback^.completed = false
    playback^.completion_failed = false
    playback^.completion_requested = reopening_completed ||
        (selecting && state^.ui_runtime.preferences.values.animation.open_completed &&
         state^.julia_interface^.current_animation^.node_kind != .Terminal)
    playback^.completion_initial = playback^.completion_requested
    if selecting {
        playback^.construction_paused = playback^.completion_requested
    } else if playback^.completion_requested {
        playback^.construction_paused = true
    }
}

//   Verify one typed request owns the pending lifecycle transaction incarnation.
animation_lifecycle_request_owns_slot :: proc(
    service: ^Julia_Runtime_Service,
    request: bridgemodel.Animation_Lifecycle_Requested) -> bool {
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
    slot: ^bridgemodel.Animation_Lifecycle_Slot) -> bool {
    state := cast(^core.Euclid_General_State)slot^.host_state
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
    slot: ^bridgemodel.Animation_Lifecycle_Slot, succeeded: bool) {
    slot^.outcome = .Committed if succeeded else .Rolled_Back
    slot^.state = .Complete
}

//   Execute one validated reload, selection, or reset against the supervisor.
execute_animation_lifecycle_transition :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service,
    host: ^Julia_Runtime_Host, request: bridgemodel.Animation_Lifecycle_Requested,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface) -> bool {
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
        service^.active_content_specification = service^.pending_content_specification
        commit_animation_reset_bookkeeping(state)
    }
    return succeeded
}

//   Apply one lifecycle transition on the Julia owner thread.
update_animation_lifecycle :: proc(
    service: ^Julia_Runtime_Service,
    host: ^Julia_Runtime_Host,
    request: bridgemodel.Animation_Lifecycle_Requested) -> bool {
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
    state := cast(^core.Euclid_General_State)slot^.host_state
    assert_julia_runtime_owner(state)
    context = state^.saved_context
    animation := state^.julia_interface^.selected_animation
    if animation == nil {
        animation = &state^.julia_interface^.null_animation
    }
    animation_prepare_lifecycle_host_context(
        service, request.animation_generation, animation)
    defer service^.presentation_animation_generation_override = 0
    defer service^.presentation_animation_override = nil
    succeeded := execute_animation_lifecycle_transition(
        state, service, host, request, animation)
    complete_animation_lifecycle_slot(slot, succeeded)
    return succeeded
}

// Bind callback-scoped content and header requests to the candidate generation.
animation_prepare_lifecycle_host_context :: proc(
    service: ^Julia_Runtime_Service, generation: u64,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface) {
    service^.presentation_animation_generation_override =
        service^.animation_generation + 1
    service^.presentation_animation_override = animation
    service^.host_exercise_header_animation_generation = generation
}

//   Report whether explicit or archive-driven reload work owns this lifecycle turn.
animation_reload_update_needed :: proc(state: ^core.Euclid_General_State) -> bool {
    service := state^.julia_runtime_service
    if service != nil && service^.reload_requested {
        return true
    }
    asset_config := julia_service_asset_config(service)
    package_identity, ok := files.packaged_asset_package_identity_with_config(
        &asset_config)
    if !ok {
        return false
    }
    if !state^.julia_interface^.asset_package_identity_valid {
        state^.julia_interface^.asset_package_identity = package_identity
        state^.julia_interface^.asset_package_identity_valid = true
        return false
    }
    package_changed :=
        package_identity != state^.julia_interface^.asset_package_identity
    failed := service != nil && service^.reload_failed_package_identity_valid &&
        package_identity == service^.reload_failed_package_identity
    return package_changed && !failed
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

//   Validate one lifecycle call and consume candidate-load failure injection.
animation_lifecycle_invocation_allowed :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface,
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
    return prepare_animation_content_specification(
        host^.native_state, animation, operation == ANIMATION_LIFECYCLE_RELOAD)
}

//   Build one primitive lifecycle payload for the current runtime generation.
make_animation_lifecycle_payload :: proc(
    service: ^Julia_Runtime_Service,
    request: bridgemodel.Animation_Lifecycle_Requested,
    operation: i32) -> Native_Animation_Lifecycle_Payload {
    return {
        request_id = request.request_id,
        runtime_generation = service^.runtime_generation,
        animation_generation = service^.animation_generation + 1,
        operation = operation,
    }
}

//   Validate one lifecycle callback result and complete its native barrier.
finish_animation_lifecycle_invocation :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request_id: u64, operation: i32,
    result: ^julialib.jl_value_t) -> bool {
    if result == nil || julialib.jl_exception_occurred() != nil {
        print_julia_exception("animation_host_lifecycle")
        return false
    }
    status := i32(julialib.jl_unbox_int32(result))
    return complete_actor_animation_lifecycle(
        service, host, request_id, operation, status)
}

//   Invoke one lifecycle transaction and service its typed native reset barrier.
invoke_actor_animation_lifecycle :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request: bridgemodel.Animation_Lifecycle_Requested,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface,
    operation: i32) -> bool {
    if !animation_lifecycle_invocation_allowed(
        service, host, animation, operation) {
        return false
    }
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        return false
    }
    uuid_buffer: [36]u8
    stable_id := uuid.to_string(animation^.stable_id, uuid_buffer[:])
    payload := make_animation_lifecycle_payload(service, request, operation)
    frame: Julia_Animation_Lifecycle_Gc_Frame = {
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
    return finish_animation_lifecycle_invocation(
        service, host, request.request_id, operation, result)
}

//   Return native reset completion to the supervisor and await its exact result.
acknowledge_actor_animation_reset :: proc(
    host: ^Julia_Runtime_Host, request_id: u64, accepted: bool) -> bool {
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil || host^.animation_lifecycle_acknowledge_reset == nil {
        return false
    }
    frame: Julia_Animation_Lifecycle_Gc_Frame = {
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
    request: bridgemodel.Animation_Tick_Requested) -> bool {
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
    state := cast(^core.Euclid_General_State)slot^.host_state
    assert_julia_runtime_owner(state)
    context = state^.saved_context
    animation_prepare_tick_scene_batch(state, service, slot, request)
    defer bridge_scene.end_scene_command_batch(state)
    defer state^.animation_query_snapshot_target = nil
    if !slot^.show_completed {
        call_global_euclid_loop(state, slot.maintenance_dt)
    }
    animation := slot^.animation
    callback_succeeded := animation == nil ||
        invoke_actor_animation_tick(service, host, request, slot, animation)
    if !callback_succeeded {
        slot^.scene_batch.overflowed = true
    }
    slot^.state = .Complete
    return callback_succeeded
}

// Prepare one tick's immutable scene batch and callback-scoped header generation.
animation_prepare_tick_scene_batch :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service,
    slot: ^bridgemodel.Animation_Tick_Slot,
    request: bridgemodel.Animation_Tick_Requested) {
    state^.animation_query_snapshot_target = &slot^.query_snapshot
    bridge_scene.begin_scene_command_batch(state, &slot^.scene_batch)
    slot^.scene_batch.animation_generation = request.animation_generation
    slot^.scene_batch.tick_sequence = request.sequence
    slot^.scene_batch.animation_progress = slot^.effective_progress
    service^.host_exercise_header_animation_generation = request.animation_generation
}

//   Build one primitive tick payload for the reserved immutable slot.
make_animation_tick_payload :: proc(
    service: ^Julia_Runtime_Service,
    request: bridgemodel.Animation_Tick_Requested,
    slot: ^bridgemodel.Animation_Tick_Slot) -> Native_Animation_Tick_Payload {
    return {
        request_id = request.request_id,
        runtime_generation = service^.runtime_generation,
        animation_generation = request.animation_generation,
        sequence = request.sequence,
        slot_index = request.handle.index,
        reservation_generation = request.handle.reservation_generation,
        dt = slot^.dt,
        operation = i32(bridgemodel.Animation_Operation.Show_Completed) if
            slot^.show_completed else i32(bridgemodel.Animation_Operation.Tick),
    }
}

//   Transfer one checked primitive tick payload through the actor host adapter.
invoke_actor_animation_tick :: proc(
    service: ^Julia_Runtime_Service, host: ^Julia_Runtime_Host,
    request: bridgemodel.Animation_Tick_Requested, slot: ^bridgemodel.Animation_Tick_Slot,
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface) -> bool {
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
    payload := make_animation_tick_payload(service, request, slot)
    frame: Julia_Animation_Tick_Gc_Frame = {
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
    bridge_events.record_julia_evidence(state, {
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
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface) {
    state^.julia_interface^.current_animation = animation
    if service := state^.julia_runtime_service; service != nil {
        service^.active_content_specification = service^.pending_content_specification
    }
    animation_generation: u64 = 0
    if state^.julia_runtime_service != nil {
        animation_generation = state^.julia_runtime_service^.animation_generation + 1
    }
    bridge_events.record_julia_evidence(state, {
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
    animation: ^bridgemodel.Euclid_Julia_Animation_Interface,
    generation: ^julialib.jl_value_t) {
    runtime_generation := state^.julia_runtime_service^.runtime_generation
    if generation != nil {
        runtime_generation += 1
    }
    bridge_events.record_julia_evidence(state, {
        lane = .Domain,
        kind = .Animation_Loaded,
        correlation_kind = .Animation,
        correlation = bridge_animation.animation_hash_stable_id(animation^.stable_id),
        generation = runtime_generation,
        flags = {.Required},
    })
}

//   Retire animation-owned native state into the generation about to initiate.
reset_animation_switch_state :: proc(state: ^core.Euclid_General_State) -> bool {
    audio.set_drawing_activity(&state^.chalk_audio, false)
    target_generation := current_animation_generation(state) + 1
    if state^.terminal.initialized && state^.julia_runtime_service != nil {
        _ = send_terminal_ingress(
            state^.julia_runtime_service, protocol.Terminal_Session_Closed{
                animation_generation = state^.terminal.animation_generation,
            })
    }
    if !viewterminalmodel.shell_runtime_close_begin(
        &state^.shell, u64(time.tick_since({}))) {
        return false
    }
    if state^.terminal_graphics_release != nil &&
       state^.simulation_executor != nil {
        state^.terminal_graphics_release(
            state^.terminal_graphics_user_data,
            &state^.simulation_executor^.pool)
    }
    terminalview.terminal_destroy(&state^.terminal,
        animation_model.animation_memory_allocator(&state^.animation_memory))
    particles.discard_dust_tool_contacts(&state^.particle_system)
    if bridge_scene.emit_shape_world_clear_departures(state) {
        projection.screenshake_on_dust_kick(&state^.iso_scale)
    }
    if shapemodel.shape_world_rewind_animation(&state^.shape_world) != .Ok {
        return false
    }
    if bridge_animation.animation_storage_begin_generation(
        &state^.animation_memory, &state^.animation_values,
        &state^.dynview_documents, target_generation) != .Ok {
        return false
    }
    bridge_scene.hide_pen(state)
    bridge_scene.hide_compass(state)
    return true
}
