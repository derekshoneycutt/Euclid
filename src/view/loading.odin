package view

import native "native"
import startup "startup"
import bridgemodel "../bridge/model"
import files "../files"
import julia "../bridge"
import evidence_profile "../evidence/profile"
import evidence_session "../evidence/session"
import fmt "core:fmt"
import log "core:log"
import strings "core:strings"
import thread "core:thread"

JULIA_UNRESPONSIVE_SECONDS :: 10.0

Window_Loading_Phase :: enum {
    Assets,
    Julia,
    Content,
    Render,
    Ready,
}

// Window_Loading retains request/worker storage until completion or joined teardown.
Window_Loading :: struct {
    display: startup.Loading_Display,
    phase: Window_Loading_Phase,
    worker: ^thread.Thread,
    assets: startup.Packaged_Assets_Worker_Result,
    initialize_id: u64,
    request_id: u64,
    started_at: f64,
    phase_started_at: f64,
    reported_unresponsive: bool,
}

// loading_set_window_icon borrows packaged icon bytes only during the native call.
loading_set_window_icon :: proc(platform: ^native.Sdl_Platform) {
    icon_path := strings.clone_to_cstring(
        files.packaged_asset_path("compass_icon.png", context.temp_allocator),
        context.temp_allocator)
    if !native.sdl_platform_set_icon(platform, icon_path) {
        log.warn("sdl_window_icon_failed")
    }
}

// window_loading_phase begins one measured phase without polling or recursively drawing.
window_loading_phase :: proc(
    owner: ^Window_Session, phase: Window_Loading_Phase,
    label: string, progress: f32) {
    owner^.loading.phase = phase
    owner^.loading.reported_unresponsive = false
    owner^.loading.phase_started_at = startup.begin_startup_phase(
        &owner^.loading.display, label, progress)
}

// window_loading_begin submits the one asset worker using stable result storage.
window_loading_begin :: proc(owner: ^Window_Session) -> bool {
    loading := &owner^.loading
    loading^.started_at = native.sdl_time_seconds()
    window_loading_phase(owner, .Assets, "Preparing assets", 0.35)
    loading^.worker = thread.create(startup.prepare_assets_worker)
    if loading^.worker == nil {
        log.error("startup_asset_worker_create_failed")
        return false
    }
    loading^.worker.data = &loading^.assets
    loading^.worker.init_context = context
    thread.start(loading^.worker)
    return true
}

// window_loading_start_julia joins asset publication before submitting Initialize once.
window_loading_start_julia :: proc(owner: ^Window_Session) -> bool {
    loading := &owner^.loading
    thread.join(loading^.worker)
    thread.destroy(loading^.worker)
    loading^.worker = nil
    if !loading^.assets.ok {
        log.error("startup_assets_failed")
        return false
    }
    startup.end_startup_phase("Preparing assets", loading^.phase_started_at)
    loading_set_window_icon(&owner^.platform)
    window_loading_phase(owner, .Julia, "Starting Julia", 0.7)
    owner^.runtime.content_service = session_create_content_service()
    if owner^.runtime.content_service == nil {
        return false
    }
    service, err := julia.create_julia_runtime_service(
        context.allocator, julia_worker_profile_path(owner^.settings.profile_path))
    owner^.runtime.julia_service = service
    if err != .None || service == nil {
        log.errorf("julia_startup_failed phase=service_create error=%d", int(err))
        return false
    }
    request, sent := julia.try_submit_runtime_initialize(service)
    loading^.initialize_id, loading^.request_id = request, request
    if !sent {
        log.error("julia_startup_failed phase=initialize_submit")
    }
    return sent
}

// window_loading_request observes one correlated completion and reports stalled startup once.
window_loading_request :: proc(
    owner: ^Window_Session,
    expected: bridgemodel.Julia_Event_Kind) -> (complete, succeeded: bool) {
    loading := &owner^.loading
    event, received := julia.try_route_julia_egress(owner^.runtime.julia_service)
    if received && event.request_id == loading^.request_id &&
        event.kind == expected {
        if !event.succeeded {
            log.errorf("julia_startup_failed request_id=%d", loading^.request_id)
        }
        return true, event.succeeded
    }
    if !loading^.reported_unresponsive &&
        native.sdl_time_seconds() - loading^.phase_started_at >=
            JULIA_UNRESPONSIVE_SECONDS {
        fmt.eprintln("Julia startup operation is not responding; request id: ",
            loading^.request_id)
        loading^.reported_unresponsive = true
    }
    return false, true
}

// window_loading_start_content admits runtime storage before one correlated content request.
window_loading_start_content :: proc(owner: ^Window_Session) -> bool {
    startup.end_startup_phase("Starting Julia", owner^.loading.phase_started_at)
    window_loading_phase(owner, .Content, "Loading content", 1)
    session := &owner^.runtime
    session^.state = initiate_animations_state(session^.julia_service, &owner^.settings)
    if session^.state == nil {
        log.error("julia_startup_failed phase=state_create")
        return false
    }
    if !session_materialize_content(session^.state, session^.content_service) {
        log.error("content_startup_failed phase=registry_materialize")
        return false
    }
    record_runtime_lifecycle(
        session^.state, .Runtime_Starting, owner^.loading.initialize_id)
    request, sent := julia.try_submit_runtime_content_initialize(
        session^.julia_service, session^.state)
    owner^.loading.request_id = request
    if !sent {
        log.error("julia_startup_failed phase=content_submit")
    }
    return sent
}

// window_loading_finish_content publishes readiness and display-owned presentation resources.
window_loading_finish_content :: proc(owner: ^Window_Session) -> bool {
    session := &owner^.runtime
    julia.mark_julia_runtime_ready(session^.julia_service)
    record_runtime_lifecycle(
        session^.state, .Runtime_Ready, owner^.loading.request_id)
    evidence_session.session_accept_ring(
        &session^.state^.evidence_session, &session^.state^.evidence_ring)
    session^.startup = owner^.startup_inputs
    if !session_apply_startup_preferences(
        session^.state, session^.startup.preferences,
        session^.startup.collections, session^.startup.user_store) {
        log.error("runtime_startup_failed phase=collections_clone")
        return false
    }
    if !session_start_presentation(session) {
        return false
    }
    startup.end_startup_phase("Loading content", owner^.loading.phase_started_at)
    owner^.loading.phase = .Render
    return true
}

// window_loading_step advances at most one phase and draws at the current admitted size.
window_loading_step :: proc(owner: ^Window_Session) -> (bool, bool) {
    switch owner^.loading.phase {
    case .Assets:
        if thread.is_done(owner^.loading.worker) &&
            !window_loading_start_julia(owner) {
            return false, false
        }
    case .Julia:
        complete, succeeded := window_loading_request(owner, .Initialized)
        if !succeeded || (complete && !window_loading_start_content(owner)) {
            return false, false
        }
    case .Content:
        complete, succeeded := window_loading_request(owner, .Invoke_Complete)
        if !succeeded || (complete && !window_loading_finish_content(owner)) {
            return false, false
        }
    case .Render:
        if !window_session_admit_render(owner) {
            return false, false
        }
        owner^.loading.phase = .Ready
        evidence_profile.zone_end(&owner^.profile)
        startup.end_startup_phase("Total startup", owner^.loading.started_at)
    case .Ready:
    }
    if !owner^.ready && !owner^.drawable_unavailable &&
        !startup.present_startup_frame(&owner^.loading.display) {
        return false, false
    }
    return true, true
}
