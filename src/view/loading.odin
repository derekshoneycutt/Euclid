package view

import native "native"

import bridgemodel "../bridge/model"

import "../files"
import julia "../bridge"
import evidence_profile "../evidence/profile"
import evidence_session "../evidence/session"

import "core:fmt"
import "core:log"
import "core:strings"
import "core:thread"

JULIA_UNRESPONSIVE_SECONDS :: 10.0

//   Created Julia runtime service plus its completed initialize request id.
Loading_Julia_Service :: struct {
    service:       ^bridgemodel.Julia_Runtime_Service,
    initialize_id: u64,
}

// Loading_Display owns startup-only reveal state and borrows display GPU owners.
Loading_Display :: struct {
    platform:     ^native.Sdl_Platform,
    draw_runtime: ^native.Sdl_Draw_Runtime,
    outline:      Startup_Outline,
    clock:        native.Sdl_Frame_Clock,
}

Packaged_Assets_Worker_Result :: struct {
    ok: bool,
}

// loading_display_create initializes progressive geometry from live window metrics.
loading_display_create :: proc(
    platform: ^native.Sdl_Platform,
    draw_runtime: ^native.Sdl_Draw_Runtime) -> Loading_Display {
    display := Loading_Display{platform = platform, draw_runtime = draw_runtime}
    display.outline = startup_outline_create({
        platform^.metrics.logical_width, platform^.metrics.logical_height})
    native.sdl_frame_clock_reset(&display.clock)
    return display
}

// present_startup_frame pumps lifecycle events and submits one outlined startup frame.
present_startup_frame :: proc(display: ^Loading_Display) -> bool {
    frame_started_at := native.sdl_time_ticks()
    _ = sdl_platform_poll_events(display^.platform)
    if display^.platform^.close_requested {
        return false
    }
    _ = startup_outline_reconcile(&display^.outline, {
        display^.platform^.metrics.logical_width,
        display^.platform^.metrics.logical_height})
    startup_outline_advance(
        &display^.outline, native.sdl_frame_clock_step(&display^.clock))
    encoder: native.Draw_Encoder
    _ = native.draw_encoder_begin(&encoder, display^.draw_runtime^.storage, {
        f32(display^.platform^.metrics.logical_width),
        f32(display^.platform^.metrics.logical_height),
    }, {display^.platform^.scene_width, display^.platform^.scene_height})
    _ = startup_outline_draw(
        &display^.outline, &encoder, UI_BORDER_COLOR, TOOL_COLOR)
    result := native.sdl_platform_present_draw(
        display^.platform, display^.draw_runtime, &encoder,
        native.to_sdl_color(BACKGROUND_COLOR))
    if result == .Failed {
        log.error("sdl_startup_present_failed")
        return false
    }
    native.sdl_delay_until_rate(frame_started_at, u64(LIMIT_FPS))
    return true
}


//   Prepare packaged assets and publish readiness to the joining display thread.
prepare_assets_worker :: proc(thread_handle: ^thread.Thread) {
    result := cast(^Packaged_Assets_Worker_Result)thread_handle.data
    result^.ok = files.packaged_asset_archive_exists_root() &&
        files.ensure_packaged_assets_unpacked_root()
}

//   Keep drawing and pumping window events until one startup worker is ready.
finish_startup_worker :: proc(
    worker: ^thread.Thread, display: ^Loading_Display) -> bool {
    if worker == nil {
        return true
    }
    startup_active := true
    for !thread.is_done(worker) {
        if startup_active {
            startup_active = present_startup_frame(display)
        }
        free_all(context.temp_allocator)
    }
    thread.destroy(worker)
    return startup_active
}

//   Draw startup frames until the requested Julia worker event is available.
finish_julia_startup_request :: proc(
    service: ^bridgemodel.Julia_Runtime_Service, request_id: u64,
    expected_kind: bridgemodel.Julia_Event_Kind,
    display: ^Loading_Display) -> bool {

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
        if !present_startup_frame(display) {
            fmt.eprintln(
                "Window closed before Julia startup completed; stopping startup.")
            return false
        }
        free_all(context.temp_allocator)
    }
}

//   Prepare packaged assets while keeping the startup window responsive.
prepare_assets_with_loading :: proc(
    display: ^Loading_Display) -> bool {
    result: Packaged_Assets_Worker_Result
    worker := thread.create(prepare_assets_worker)
    if worker == nil {
        return files.ensure_packaged_assets_unpacked_root()
    }
    worker.data = &result
    worker.init_context = context
    thread.start(worker)
    startup_active := finish_startup_worker(worker, display)
    return result.ok && startup_active
}

//   Display and begin timing one blocking startup phase.
begin_startup_phase :: proc(
    display: ^Loading_Display, label: string, progress: f32) -> f64 {
    startup_outline_set_target(&display^.outline, progress)
    _ = present_startup_frame(display)
    fmt.println("Startup: ", label, "...")
    return native.sdl_time_seconds()
}

//   Log elapsed wall time for one completed startup phase.
end_startup_phase :: proc(label: string, started_at: f64) {
    elapsed_ms := int((native.sdl_time_seconds() - started_at) * 1000)
    fmt.println("Startup: ", label, " completed in ", elapsed_ms, " ms")
}

//   Create the Julia runtime service and finish its Initialize phase.
//
// Returns:
//   - result: Created service and initialize id when ok.
//   - ok: true when the service was created and initialized.
loading_start_julia_service :: proc(
    out: ^Loading_Julia_Service, display: ^Loading_Display,
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
    state: ^Euclid_General_State,
    julia_service: ^bridgemodel.Julia_Runtime_Service) -> (^Euclid_General_State, bool) {
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
    settings: ^Euclid_Run_Settings,
    initialize_id: u64,
    display: ^Loading_Display) -> (^Euclid_General_State, bool) {

    state := initiate_animations_state(julia_service, settings)
    if state == nil {
        fmt.eprintln("Runtime state initialization failed.")
        log.error("julia_startup_failed phase=state_create")
        julia.destroy_julia_runtime_service(julia_service)
        return nil, false
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
    profile: ^evidence_profile.State, display: ^Loading_Display) -> bool {
    evidence_profile.zone_begin(profile, "prepare assets")
    started_at := begin_startup_phase(display, "Preparing assets", 0.35)
    assets_ok := prepare_assets_with_loading(display)
    end_startup_phase("Preparing assets", started_at)
    evidence_profile.zone_end(profile)
    if !assets_ok {
        fmt.eprintln("Packaged asset preparation failed; aborting startup.")
    }
    return assets_ok
}

//   Pair initialized runtime owners for transfer to the window loop.
loading_runtime_session :: proc(
    state: ^Euclid_General_State,
    service: ^bridgemodel.Julia_Runtime_Service) -> (Euclid_Runtime_Session, bool) {
    presentation := create_presentation_runtime()
    if presentation == nil {
        _ = shutdown_runtime_session({
            state = state,
            julia_service = service,
        })
        return {}, false
    }
    julia_egress_router_attach(state, presentation)
    return {
        state = state,
        julia_service = service,
        presentation = presentation,
    }, true
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

// Initialize startup phases while the window stays responsive.
initialize_window_runtime_with_loading :: proc(
    settings: ^Euclid_Run_Settings,
    timing_profile: ^evidence_profile.State,
    platform: ^native.Sdl_Platform,
    draw_runtime: ^native.Sdl_Draw_Runtime) -> (Euclid_Runtime_Session, bool) {

    startup_started_at := native.sdl_time_seconds()
    display := loading_display_create(platform, draw_runtime)
    if !loading_prepare_assets_phase(timing_profile, &display) {
        return {}, false
    }
    loading_set_window_icon(platform)

    evidence_profile.zone_begin(timing_profile, "start Julia")
    started_at := begin_startup_phase(&display, "Starting Julia", 0.7)
    started_service: Loading_Julia_Service
    if !loading_start_julia_service(
        &started_service, &display,
        julia_worker_profile_path(settings^.profile_path)) {
        return {}, false
    }
    end_startup_phase("Starting Julia", started_at)
    evidence_profile.zone_end(timing_profile)

    evidence_profile.zone_begin(timing_profile, "load content")
    started_at = begin_startup_phase(&display, "Loading content", 1)
    state, content_ok := loading_load_content(
        started_service.service, settings, started_service.initialize_id,
        &display)
    if !content_ok {
        return {}, false
    }
    end_startup_phase("Loading content", started_at)
    evidence_profile.zone_end(timing_profile)

    end_startup_phase("Total startup", startup_started_at)
    return loading_runtime_session(state, started_service.service)
}
