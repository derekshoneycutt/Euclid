package view

import native "native"

import bridgemodel "../bridge/model"

import "../files"
import julia "../bridge"
import evidence_profile "../evidence/profile"
import evidence_session "../evidence/session"
import "ui"

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:thread"

import rl "vendor:raylib"

STARTUP_TRACK_COLOR :: rl.Color{86, 55, 66, 255}
STARTUP_PROGRESS_COLOR :: rl.Color{175, 150, 150, 255}
STARTUP_WARNING_TEXT :: cstring("Julia is not responding")
JULIA_UNRESPONSIVE_SECONDS :: 10.0
STARTUP_COMPLETION_SECONDS :: f32(0.24)

//   Created Julia runtime service plus its completed initialize request id.
Loading_Julia_Service :: struct {
    service:       ^bridgemodel.Julia_Runtime_Service,
    initialize_id: u64,
}

Packaged_Assets_Worker_Result :: struct {
    ok: bool,
}


// Draw one startup frame from the progressively assembled UI silhouette.
draw_startup_frame :: proc(
    outline: ^Startup_Outline, progress: f32,
    show_julia_warning := false) {
    metrics := ui.ui_current_window_metrics()
    _ = startup_outline_reconcile(outline, metrics)
    startup_outline_set_target(outline, progress)
    startup_outline_advance(outline,
        min(max(rl.GetFrameTime(), f32(0)), f32(0.05)))
    rl.BeginDrawing()
    rl.ClearBackground(native.to_raylib_color(BACKGROUND_COLOR))
    startup_outline_draw(outline, STARTUP_TRACK_COLOR, STARTUP_PROGRESS_COLOR)
    if show_julia_warning {
        regular_font := rl.GetFontDefault()
        font_size: f32 = 18
        text_width := rl.MeasureTextEx(
            regular_font, STARTUP_WARNING_TEXT, font_size, 0).x
        text_position := startup_warning_position(metrics, text_width, font_size)
        rl.DrawTextEx(regular_font, STARTUP_WARNING_TEXT, text_position, font_size, 0,
            native.to_raylib_color(UI_TEXT_COLOR))
    }
    rl.EndDrawing()
}

// Quickly finish the assembled silhouette after every runtime owner is ready.
finish_startup_outline :: proc(outline: ^Startup_Outline) {
    started_at := rl.GetTime()
    initial_distance := outline^.reveal_distance
    for {
        elapsed := f32(rl.GetTime() - started_at)
        progress := clamp(elapsed / STARTUP_COMPLETION_SECONDS, f32(0), f32(1))
        eased := 1 - (1 - progress) * (1 - progress) * (1 - progress)
        outline^.reveal_distance = initial_distance +
            (outline^.total_length - initial_distance) * eased
        draw_startup_frame(outline, 1)
        if progress >= 1 {return}
        if rl.WindowShouldClose() {runtime.exit(0)}
        free_all(context.temp_allocator)
    }
}


//   Prepare packaged assets and publish readiness to the joining display thread.
prepare_assets_worker :: proc(thread_handle: ^thread.Thread) {
    result := cast(^Packaged_Assets_Worker_Result)thread_handle.data
    result^.ok = files.packaged_asset_archive_exists_root() &&
        files.ensure_packaged_assets_unpacked_root()
}

//   Keep drawing and pumping window events until one startup worker is ready.
finish_startup_worker :: proc(
    worker: ^thread.Thread, outline: ^Startup_Outline, progress: f32) {
    if worker == nil {
        return
    }
    for !thread.is_done(worker) {
        draw_startup_frame(outline, progress)
        _ = rl.WindowShouldClose()
        free_all(context.temp_allocator)
    }
    thread.destroy(worker)
}

//   Draw startup frames until the requested Julia worker event is available.
finish_julia_startup_request :: proc(
    service: ^bridgemodel.Julia_Runtime_Service, request_id: u64,
    expected_kind: bridgemodel.Julia_Event_Kind,
    outline: ^Startup_Outline, progress: f32) -> bool {

    started_at := rl.GetTime()
    reported_unresponsive := false
    for {
        event, ok := julia.try_route_julia_egress(service)
        if ok && event.request_id == request_id && event.kind == expected_kind {
            if !event.succeeded {
                fmt.eprintln("Julia startup operation failed; request id: ", request_id)
            }
            return event.succeeded
        }
        if rl.GetTime() - started_at >= JULIA_UNRESPONSIVE_SECONDS {
            if !reported_unresponsive {
                fmt.eprintln(
                    "Julia startup operation is not responding; request id: ", request_id)
                reported_unresponsive = true
            }
        }
        draw_startup_frame(outline, progress, reported_unresponsive)
        if rl.WindowShouldClose() {
            fmt.eprintln(
                "Window closed before Julia startup completed; terminating process.")
            runtime.exit(0)
        }
        free_all(context.temp_allocator)
    }
}

//   Prepare packaged assets while keeping the startup window responsive.
prepare_assets_with_loading :: proc(
    outline: ^Startup_Outline, progress: f32) -> bool {
    result: Packaged_Assets_Worker_Result
    worker := thread.create(prepare_assets_worker)
    if worker == nil {
        return files.ensure_packaged_assets_unpacked_root()
    }
    worker.data = &result
    worker.init_context = context
    thread.start(worker)
    finish_startup_worker(worker, outline, progress)
    return result.ok
}

//   Display and begin timing one blocking startup phase.
begin_startup_phase :: proc(
    outline: ^Startup_Outline, label: string, progress: f32) -> f64 {
    draw_startup_frame(outline, progress)
    fmt.println("Startup: ", label, "...")
    return rl.GetTime()
}

//   Log elapsed wall time for one completed startup phase.
end_startup_phase :: proc(label: string, started_at: f64) {
    elapsed_ms := int((rl.GetTime() - started_at) * 1000)
    fmt.println("Startup: ", label, " completed in ", elapsed_ms, " ms")
}

//   Create the Julia runtime service and finish its Initialize phase.
//
// Returns:
//   - result: Created service and initialize id when ok.
//   - ok: true when the service was created and initialized.
loading_start_julia_service :: proc(
    out: ^Loading_Julia_Service, outline: ^Startup_Outline,
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
        julia_service, initialize_id, .Initialized, outline, 0.35) {
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
    outline: ^Startup_Outline) -> (^Euclid_General_State, bool) {

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
        julia_service, content_id, .Invoke_Complete, outline, 0.65) {
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
    profile: ^evidence_profile.State, outline: ^Startup_Outline) -> bool {
    evidence_profile.zone_begin(profile, "prepare assets")
    started_at := begin_startup_phase(outline, "Preparing assets", 0.15)
    assets_ok := prepare_assets_with_loading(outline, 0.15)
    end_startup_phase("Preparing assets", started_at)
    evidence_profile.zone_end(profile)
    if !assets_ok {
        fmt.eprintln("Packaged asset preparation failed; aborting startup.")
    }
    return assets_ok
}

//   Initialize presentation resources as one measured startup phase.
loading_initialize_graphics_phase :: proc(
    profile: ^evidence_profile.State, state: ^Euclid_General_State,
    settings: ^Euclid_Run_Settings, outline: ^Startup_Outline) {
    evidence_profile.zone_begin(profile, "load graphics")
    started_at := begin_startup_phase(
        outline, "Loading fonts and graphics", 0.85)
    initialize_window_resources(state, settings)
    end_startup_phase("Loading fonts and graphics", started_at)
    evidence_profile.zone_end(profile)
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
initialize_window_runtime_with_loading :: proc(
    settings: ^Euclid_Run_Settings,
    timing_profile: ^evidence_profile.State) -> (Euclid_Runtime_Session, bool) {

    startup_started_at := rl.GetTime()
    metrics := ui.ui_current_window_metrics()
    layout := ui.resolve_initial_layout_mode(settings^.window.layout,
        f32(metrics.width), f32(metrics.height))
    outline := startup_outline_create(metrics, layout, settings^.window.layout)
    if !loading_prepare_assets_phase(timing_profile, &outline) {
        return {}, false
    }

    evidence_profile.zone_begin(timing_profile, "start Julia")
    started_at := begin_startup_phase(&outline, "Starting Julia", 0.35)
    started_service: Loading_Julia_Service
    if !loading_start_julia_service(
        &started_service, &outline,
        julia_worker_profile_path(settings^.profile_path)) {
        return {}, false
    }
    end_startup_phase("Starting Julia", started_at)
    evidence_profile.zone_end(timing_profile)

    evidence_profile.zone_begin(timing_profile, "load content")
    started_at = begin_startup_phase(&outline, "Loading content", 0.65)
    state, content_ok := loading_load_content(
        started_service.service, settings, started_service.initialize_id,
        &outline)
    if !content_ok {
        return {}, false
    }
    end_startup_phase("Loading content", started_at)
    evidence_profile.zone_end(timing_profile)

    loading_initialize_graphics_phase(
        timing_profile, state, settings, &outline)
    finish_startup_outline(&outline)
    end_startup_phase("Total startup", startup_started_at)
    return loading_runtime_session(state, started_service.service)
}
