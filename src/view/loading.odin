package view

import native "native"
import bridgemodel "../bridge/model"
import viewcontent "content"
import files "../files"
import julia "../bridge"
import evidence_profile "../evidence/profile"
import evidence_session "../evidence/session"
import fmt "core:fmt"
import log "core:log"
import strings "core:strings"
import core "../core"
import startup "startup"

JULIA_UNRESPONSIVE_SECONDS :: 10.0

//   Created Julia runtime service plus its completed initialize request id.
Loading_Julia_Service :: struct {
    service: ^bridgemodel.Julia_Runtime_Service,
    initialize_id: u64,
}


//   Draw startup frames until the requested Julia worker event is available.
finish_julia_startup_request :: proc(
    service: ^bridgemodel.Julia_Runtime_Service, request_id: u64,
    expected_kind: bridgemodel.Julia_Event_Kind,
    display: ^startup.Loading_Display) -> bool {

    started_at := native.sdl_time_seconds()
    reported_unresponsive := false
    for {
        event, ok := julia.try_route_julia_egress(service)
        if ok && event.request_id == request_id && event.kind == expected_kind {
            if !event.succeeded {
                fmt.eprintln("Julia startup operation failed; request id: ", request_id)
            }
            return event.succeeded
        }
        if native.sdl_time_seconds() - started_at >= JULIA_UNRESPONSIVE_SECONDS {
            if !reported_unresponsive {
                fmt.eprintln(
                    "Julia startup operation is not responding; request id: ", request_id)
                reported_unresponsive = true
            }
        }
        if !startup.present_startup_frame(display) {
            fmt.eprintln(
                "Window closed before Julia startup completed; stopping startup.")
            return false
        }
        free_all(context.temp_allocator)
    }
}


//   Create the Julia runtime service and finish its Initialize phase.
//
// Returns:
//   - result: Created service and initialize id when ok.
//   - ok: true when the service was created and initialized.
loading_start_julia_service :: proc(
    out: ^Loading_Julia_Service, display: ^startup.Loading_Display,
    profile_path: string = "") -> bool {
    julia_service, service_err := julia.create_julia_runtime_service(profile_path)
    if service_err != .None || julia_service == nil {
        fmt.eprintln("Failed to create Julia runtime service.")
        log.errorf("julia_startup_failed phase=service_create error=%d",
            int(service_err))
        return false
    }
    initialize_id, initialize_sent :=
        julia.try_submit_runtime_initialize(julia_service)
    if !initialize_sent {
        log.error("julia_startup_failed phase=initialize_submit")
        fmt.eprintln("Julia initialization failed.")
        julia.destroy_julia_runtime_service(julia_service)
        return false
    }
    if !finish_julia_startup_request(
        julia_service, initialize_id, .Initialized, display) {
        fmt.eprintln("Julia initialization failed.")
        log.errorf("julia_startup_failed phase=initialize_wait request_id=%d",
            initialize_id)
        julia.destroy_julia_runtime_service(julia_service)
        return false
    }
    out.service = julia_service
    out.initialize_id = initialize_id
    return true
}

//   Report content startup failure and release the partially initialized session.
loading_content_failed :: proc(
    state: ^core.Euclid_General_State,
    julia_service: ^bridgemodel.Julia_Runtime_Service) -> (
        ^core.Euclid_General_State, bool) {
    fmt.eprintln("Julia content initialization failed.")
    shutdown_runtime_session(Euclid_Runtime_Session{
        state = state,
        julia_service = julia_service,
    })
    return nil, false
}

//   Allocate runtime state and finish the Julia content Invoke phase.
//
// Returns:
//   - state: Initialized general state when ok.
//   - ok: true when state was created and content initialization completed.
loading_load_content :: proc(
    julia_service: ^bridgemodel.Julia_Runtime_Service,
    content_service: ^viewcontent.Content_Service,
    settings: ^core.Euclid_Run_Settings,
    initialize_id: u64,
    display: ^startup.Loading_Display) -> (^core.Euclid_General_State, bool) {

    state := initiate_animations_state(julia_service, settings)
    if state == nil {
        fmt.eprintln("Runtime state initialization failed.")
        log.error("julia_startup_failed phase=state_create")
        julia.destroy_julia_runtime_service(julia_service)
        return nil, false
    }
    if !session_materialize_content(state, content_service) {
        log.error("content_startup_failed phase=registry_materialize")
        return loading_content_failed(state, julia_service)
    }
    record_runtime_lifecycle(state, .Runtime_Starting, initialize_id)
    content_id, content_sent := julia.try_submit_runtime_content_initialize(
        julia_service, state)
    if !content_sent {
        log.error("julia_startup_failed phase=content_submit")
        return loading_content_failed(state, julia_service)
    }
    if !finish_julia_startup_request(
        julia_service, content_id, .Invoke_Complete, display) {
        log.errorf("julia_startup_failed phase=content_wait request_id=%d",
            content_id)
        return loading_content_failed(state, julia_service)
    }
    julia.mark_julia_runtime_ready(julia_service)
    record_runtime_lifecycle(state, .Runtime_Ready, content_id)
    evidence_session.session_accept_ring(
        &state^.evidence_session, &state^.evidence_ring)
    return state, true
}

//   Prepare packaged assets as one measured startup phase.
loading_prepare_assets_phase :: proc(
    profile: ^evidence_profile.State,
    display: ^startup.Loading_Display) -> bool {
    evidence_profile.zone_begin(profile, "prepare assets")
    started_at := startup.begin_startup_phase(display, "Preparing assets", 0.35)
    assets_ok := startup.prepare_assets_with_loading(display)
    startup.end_startup_phase("Preparing assets", started_at)
    evidence_profile.zone_end(profile)
    if !assets_ok {
        fmt.eprintln("Packaged asset preparation failed; aborting startup.")
    }
    return assets_ok
}

//   Pair initialized runtime owners for transfer to the window loop.
loading_runtime_session :: proc(
    state: ^core.Euclid_General_State,
    service: ^bridgemodel.Julia_Runtime_Service,
    content_service: ^viewcontent.Content_Service,
    startup_inputs: ^Session_Startup_Inputs = nil) -> (Euclid_Runtime_Session, bool) {
    session := Euclid_Runtime_Session{
        state = state,
        julia_service = service,
        content_service = content_service,
        startup = session_startup_inputs(startup_inputs),
    }
    session_apply_startup_preferences(
        state, session.startup.preferences, session.startup.user_store)
    if !session_start_presentation(&session) {
        _ = shutdown_runtime_session(session)
        return {}, false
    }
    return session, true
}

//   Initialize startup phases while the window stays responsive.
//
// Notes:
//   - Drives runtime startup through visible progress frames so window event processing never stalls.
//   - Shares runtime-state ownership with the headless session path after startup completes.
loading_set_window_icon :: proc(platform: ^native.Sdl_Platform) {
    icon_path := strings.clone_to_cstring(
        files.packaged_asset_path("compass_icon.png", context.temp_allocator),
        context.temp_allocator)
    if !native.sdl_platform_set_icon(platform, icon_path) {
        log.warn("sdl_window_icon_failed")
    }
}

// Start catalogue and Julia services during the visible startup phase.
loading_start_runtime_services :: proc(
    timing_profile: ^evidence_profile.State, display: ^startup.Loading_Display,
    settings: ^core.Euclid_Run_Settings, started: ^Loading_Julia_Service,
    content_service: ^^viewcontent.Content_Service) -> bool {
    evidence_profile.zone_begin(timing_profile, "start Julia")
    started_at := startup.begin_startup_phase(display, "Starting Julia", 0.7)
    content_service^ = session_create_content_service()
    if content_service^ == nil {
        return false
    }
    if !loading_start_julia_service(
        started, display, julia_worker_profile_path(settings^.profile_path)) {
        viewcontent.content_service_destroy_owned(content_service^)
        content_service^ = nil
        return false
    }
    startup.end_startup_phase("Starting Julia", started_at)
    evidence_profile.zone_end(timing_profile)
    return true
}

// Initialize startup phases while the window stays responsive.
initialize_window_runtime_with_loading :: proc(
    settings: ^core.Euclid_Run_Settings,
    timing_profile: ^evidence_profile.State,
    platform: ^native.Sdl_Platform,
    draw_runtime: ^native.Sdl_Draw_Runtime,
    startup_inputs: ^Session_Startup_Inputs = nil) -> (Euclid_Runtime_Session, bool) {

    startup_started_at := native.sdl_time_seconds()
    display := startup.loading_display_create(platform, draw_runtime)
    if !loading_prepare_assets_phase(timing_profile, &display) {
        return {}, false
    }
    loading_set_window_icon(platform)

    started_service: Loading_Julia_Service
    content_service: ^viewcontent.Content_Service
    if !loading_start_runtime_services(
        timing_profile, &display, settings, &started_service, &content_service) {
        return {}, false
    }

    evidence_profile.zone_begin(timing_profile, "load content")
    started_at := startup.begin_startup_phase(&display, "Loading content", 1)
    state, content_ok := loading_load_content(
        started_service.service, content_service, settings,
        started_service.initialize_id, &display)
    if !content_ok {
        viewcontent.content_service_destroy_owned(content_service)
        return {}, false
    }
    startup.end_startup_phase("Loading content", started_at)
    evidence_profile.zone_end(timing_profile)

    startup.end_startup_phase("Total startup", startup_started_at)
    return loading_runtime_session(
        state, started_service.service, content_service, startup_inputs)
}
