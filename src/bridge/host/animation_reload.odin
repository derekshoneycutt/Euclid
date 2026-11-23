package julia_host

import bridge_animation "../animation"

import bridge_events "../events"
import bridgemodel "../model"
import julialib "../../../libs/julia/bindings"
import core "../../core"
import files "../../files"
import evidence_trace "../../evidence/trace"
import content "../../view/content"
import uuid "core:encoding/uuid"
import fmt "core:fmt"
import log "core:log"
import strings "core:strings"

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
    bridge_events.record_julia_evidence(state, {
        lane = .Lifecycle,
        kind = kind,
        correlation_kind = .Runtime_Request,
        correlation = target_generation,
        generation = target_generation,
        flags = flags,
    })
}

//   Report whether automatic reload work is already current or known to have failed.
asset_reload_can_skip :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service,
    force_reload: bool, package_identity: [32]byte) -> bool {
    if force_reload {
        return false
    }
    if asset_package_identity_current(state, package_identity) {
        return true
    }
    return service != nil && service^.reload_failed_package_identity_valid &&
        package_identity == service^.reload_failed_package_identity
}

//   Detect packaged asset updates and hot-reload Julia script/interface state when changed.
reload_packaged_assets_if_updated :: proc(
    state: ^core.Euclid_General_State, service: ^Julia_Runtime_Service,
    host: ^Julia_Runtime_Host, request: bridgemodel.Animation_Lifecycle_Requested,
    target: ^bridgemodel.Euclid_Julia_Animation_Interface) -> bool {
    asset_config := julia_service_asset_config(service)
    package_identity, ok := files.packaged_asset_package_identity_with_config(
        &asset_config)
    if !ok {
        return true
    }

    force_reload := service != nil && service^.reload_requested
    if service != nil {
        service^.reload_requested = false
    }
    if asset_reload_can_skip(state, service, force_reload, package_identity) {
        return true
    }
    if service != nil {
        service^.reload_state = .Including
    }
    record_runtime_reload_event(state, "runtime.reload_started")

    if !refresh_packaged_assets(state, service, package_identity) {
        return false
    }

    reloaded := stage_julia_interface_reload(
        state, host, request, package_identity, target^.stable_id)
    if !reloaded {
        record_runtime_reload_event(state, "runtime.reload_rolled_back")
        return false
    }

    record_runtime_reload_event(state, "runtime.reload_committed")
    return true
}

//   Track package identity and report whether it already matches active state.
//
// Returns:
//   - true when package identity is unchanged (or just seeded).
asset_package_identity_current :: proc(
    state: ^core.Euclid_General_State, package_identity: [32]byte) -> bool {

    if !state^.julia_interface^.asset_package_identity_valid {
        state^.julia_interface^.asset_package_identity = package_identity
        state^.julia_interface^.asset_package_identity_valid = true
        return true
    }
    return package_identity == state^.julia_interface^.asset_package_identity
}

//   Re-extract packaged assets, rolling back and reporting on failure.
//
// Returns:
//   - true when the candidate source tree was refreshed successfully.
refresh_packaged_assets :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service, package_identity: [32]byte) -> bool {

    asset_config := julia_service_asset_config(service)
    fingerprint, fingerprint_ok :=
        files.packaged_sysimage_input_fingerprint_with_config(
            &asset_config, context.temp_allocator)
    if !fingerprint_ok ||
       !files.reload_compatible_packaged_assets_root(fingerprint, &asset_config) {
        fmt.eprintln("Julia asset reload skipped: failed to re-extract assets package")
        mark_julia_reload_failed(service, package_identity)
        record_runtime_reload_event(state, "runtime.reload_rolled_back")
        return false
    }
    return true
}

//   Admit the refreshed package database without replacing the active catalogue.
stage_packaged_content_reload :: proc(
    state: ^core.Euclid_General_State,
    service: ^Julia_Runtime_Service, package_identity: [32]byte) -> bool {
    if state == nil || state^.content_service == nil {
        mark_julia_reload_failed(service, package_identity)
        return false
    }
    content_service := state^.content_service
    asset_config := julia_service_asset_config(service)
    asset, asset_ok := files.packaged_content_asset_with_config(
        &asset_config, context.temp_allocator)
    if asset_ok && content.content_service_stage(
        content_service, asset.database_path, asset.corpus_fingerprint) {
        return true
    }
    fmt.eprintln("Julia asset reload: candidate catalogue admission failed")
    mark_julia_reload_failed(service, package_identity)
    return false
}

//   Construct one generation into a caller-rooted Julia value slot.
create_julia_runtime_generation :: proc(
    service: ^Julia_Runtime_Service) -> ^julialib.jl_value_t {
    main_module := resolve_main_module()
    if main_module == nil {
        return nil
    }
    constructor := julialib.jl_get_function(
        main_module, "create_euclid_runtime_generation")
    if constructor == nil {
        return nil
    }
    asset_config := julia_service_asset_config(service)
    content_path, content_ok := resolve_packaged_julia_content_path(
        false, &asset_config)
    if !content_ok {
        return nil
    }
    content_cstr := strings.clone_to_cstring(
        content_path, context.temp_allocator)
    content_value := julialib.jl_cstr_to_string(content_cstr)
    generation := julialib.jl_call1(constructor, content_value)
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

//   Admit one reload transaction and publish its registering state.
begin_julia_interface_reload :: proc(
    state: ^core.Euclid_General_State) -> (^Julia_Runtime_Service, bool) {
    if state == nil {
        return nil, false
    }
    service := state^.julia_runtime_service
    if service == nil || service^.runtime_host == nil {
        return nil, false
    }
    service^.reload_state = .Registering
    return service, true
}

//   Construct one rooted reload candidate and publish construction failure.
create_julia_interface_reload_candidate :: proc(
    service: ^Julia_Runtime_Service,
    package_identity: [32]byte) -> ^julialib.jl_value_t {
    candidate := create_julia_runtime_generation(service)
    if candidate == nil {
        fmt.eprintln("Julia asset reload: candidate generation construction failed")
        mark_julia_reload_failed(service, package_identity)
    }
    return candidate
}

//   Stage catalogue state and validate one fully described reload transaction.
stage_and_validate_julia_interface_reload :: proc(
    transaction: ^Julia_Interface_Reload_Transaction) -> bool {
    if !stage_packaged_content_reload(
        transaction^.state, transaction^.service,
        transaction^.package_identity) {
        return false
    }
    return validate_julia_interface_reload(transaction)
}

//   Require the Julia owner thread's GC stack before rooting a reload candidate.
reload_candidate_gc_stack :: proc(
    service: ^Julia_Runtime_Service,
    package_identity: [32]byte) -> ^^julialib.jl_gcframe_t {
    gc_stack := julialib.jl_get_pgcstack()
    if gc_stack == nil {
        fmt.eprintln("Julia asset reload: owner thread has no GC stack")
        mark_julia_reload_failed(service, package_identity)
    }
    return gc_stack
}

//   Register and validate one fresh interface before retiring the active generation.
stage_julia_interface_reload :: proc(
    state: ^core.Euclid_General_State, host: ^Julia_Runtime_Host,
    request: bridgemodel.Animation_Lifecycle_Requested,
    package_identity: [32]byte,
    stable_id: uuid.Identifier) -> bool {

    service, admitted := begin_julia_interface_reload(state)
    if !admitted {
        return false
    }
    gc_stack := reload_candidate_gc_stack(service, package_identity)
    if gc_stack == nil {
        return false
    }
    candidate: ^julialib.jl_value_t
    candidate_frame: Julia_Runtime_Gc_Frame = {
        encoded_root_count = (1 << 2) | 1,
        previous = gc_stack^,
        root = rawptr(&candidate),
    }
    gc_stack^ = (^julialib.jl_gcframe_t)(&candidate_frame)
    defer gc_stack^ = candidate_frame.previous
    candidate = create_julia_interface_reload_candidate(service, package_identity)
    if candidate == nil {
        return false
    }
    transaction: Julia_Interface_Reload_Transaction = {
        state = state,
        host = host,
        request = request,
        package_identity = package_identity,
        stable_id = stable_id,
        candidate = candidate,
        service = service,
    }
    return stage_and_validate_julia_interface_reload(&transaction)
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
        transaction^.package_identity)
    return false
}

//   Materialize the admitted candidate catalogue into the inactive native registry.
stage_julia_interface_content :: proc(
    transaction: ^Julia_Interface_Reload_Transaction) -> bool {
    staged_interface := transaction^.staged_interface
    content_service := transaction^.state^.content_service
    generation := content.content_service_staged_generation(
        content_service)
     if generation == nil ||
         !bridge_animation.content_generation_materialize(staged_interface, generation) {
        return false
    }
    for source := transaction^.previous_interface^.animation_head;
         source != nil; source = source^.next_in_registry {
        target := bridge_animation.animation_lookup_find(
            staged_interface, source^.stable_id)
        if target != nil {
            target^.is_expanded = source^.is_expanded
        }
    }
    return true
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
        return false
    }
    staged_interface^.asset_package_identity = transaction^.package_identity
    staged_interface^.asset_package_identity_valid = true
    if !stage_julia_interface_content(transaction) {
        return false
    }
    state^.julia_interface = staged_interface
    initialized, restored := initialize_and_restore_julia_candidate(
        state, transaction^.stable_id, transaction^.candidate)
    if !initialized || !restored {
        message := "Julia asset reload: active animation restoration failed"
        if !initialized {
            message = "Julia asset reload: candidate registration failed"
        }
        fmt.eprintln(message)
        return false
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
    return true
}

//   Validate one rooted candidate against the inactive interface and publish on success.
validate_julia_interface_reload :: proc(
    transaction: ^Julia_Interface_Reload_Transaction) -> bool {
    if !prepare_julia_interface_reload_candidate(transaction) {
        return reject_julia_interface_reload(transaction,
            "Julia asset reload: candidate preparation failed", false)
    }
    if !activate_julia_interface_reload_candidate(transaction) {
        return false
    }
    content_service := transaction^.state^.content_service
    if !content.content_service_commit(content_service) {
        return reject_julia_interface_reload(transaction,
            "Julia asset reload: catalogue commit failed", true)
    }
    if !commit_julia_runtime_generation(
        transaction^.service, transaction^.candidate) {
        return reject_julia_interface_reload(transaction,
            "Julia asset reload: candidate commit failed", true)
    }
    state := transaction^.state
    commit_animation_selection(state, transaction^.target)
    record_animation_loaded(state, transaction^.target, transaction^.candidate)
    publish_julia_interface_reload(
        state, transaction^.previous_interface,
        transaction^.staged_slot, transaction^.service)
    if !content.content_service_finalize(content_service) {
        log.error("content_reload_finalize_failed")
    }
    return true
}

//   Restore the active generation after staged registration or activation fails.
rollback_julia_interface_reload :: proc(
    state: ^core.Euclid_General_State,
    previous_interface, staged_interface: ^bridgemodel.Euclid_Julia_Interface,
    service: ^Julia_Runtime_Service, package_identity: [32]byte) {

    if state^.content_service != nil &&
       !content.content_service_discard(state^.content_service) {
        log.error("content_reload_rollback_failed")
    }
    bridge_animation.clean_julia_interface_instance(staged_interface)
    state^.julia_interface = previous_interface
    service^.reload_failure_injection = .None
    julialib.jl_gc_collect(.JL_GC_FULL)
    mark_julia_reload_failed(service, package_identity)
}

//   Publish one validated interface generation and retire its predecessor.
publish_julia_interface_reload :: proc(
    state: ^core.Euclid_General_State,
    previous_interface: ^bridgemodel.Euclid_Julia_Interface,
    staged_slot: int,
    service: ^Julia_Runtime_Service) {

    if service != nil {
        service^.reload_state = .Publishing
    }
    bridge_animation.clean_julia_interface_instance(previous_interface)
    state^.julia_interface_active_slot = staged_slot

    if service != nil {
        service^.reload_failure_injection = .None
        service^.runtime_generation += 1
        service^.reload_failed_package_identity = {}
        service^.reload_failed_package_identity_valid = false
        service^.reload_state = .Idle
    }
}

//   Preserve the active generation and suppress retries for one broken package revision.
mark_julia_reload_failed :: proc(
    service: ^Julia_Runtime_Service, package_identity: [32]byte) {
    if service == nil {
        return
    }
    service^.reload_failed_package_identity = package_identity
    service^.reload_failed_package_identity_valid = true
    service^.reload_state = .Failed
}
