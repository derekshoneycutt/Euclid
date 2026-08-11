package view

import view_core "core"
import "../files"
import julia "../bridge"
import "../trace"

import "base:runtime"
import "core:fmt"
import "core:thread"

import rl "vendor:raylib"

STARTUP_SPINNER_OFFSETS :: [8]rl.Vector2{
    {0, -18}, {13, -13}, {18, 0}, {13, 13},
    {0, 18}, {-13, 13}, {-18, 0}, {-13, -13},
}
STARTUP_TRACK_COLOR :: rl.Color{86, 55, 66, 255}
STARTUP_PROGRESS_COLOR :: rl.Color{175, 150, 150, 255}
STARTUP_WARNING_TEXT :: cstring("Julia is not responding")
JULIA_UNRESPONSIVE_SECONDS :: 10.0

//   Draw one dependency-free startup frame with spinner and progress bar.
draw_startup_frame :: proc(progress: f32, show_julia_warning := false) {
    center := rl.Vector2{WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2 - 24}
    active_dot := int(rl.GetTime() * 8) % len(STARTUP_SPINNER_OFFSETS)

    rl.BeginDrawing()
    rl.ClearBackground(BACKGROUND_COLOR)
    for offset, index in STARTUP_SPINNER_OFFSETS {
        color := STARTUP_TRACK_COLOR
        if index == active_dot {
            color = STARTUP_PROGRESS_COLOR
        }
        rl.DrawCircleV(center + offset, 4, color)
    }
    rl.DrawRectangleRec(rl.Rectangle{WINDOW_WIDTH / 2 - 140, 380, 280, 4}, STARTUP_TRACK_COLOR)
    rl.DrawRectangleRec(rl.Rectangle{WINDOW_WIDTH / 2 - 140, 380, 280 * progress, 4}, STARTUP_PROGRESS_COLOR)
    if show_julia_warning {
        font := rl.GetFontDefault()
        font_size: f32 = 18
        text_width := rl.MeasureTextEx(font, STARTUP_WARNING_TEXT, font_size, 0).x
        text_position := rl.Vector2{WINDOW_WIDTH / 2 - text_width / 2, 402}
        rl.DrawTextEx(font, STARTUP_WARNING_TEXT, text_position, font_size, 0, UI_TEXT_COLOR)
    }
    rl.EndDrawing()
}

//   Prepare packaged assets on the startup worker's independent temp allocator.
prepare_assets_worker :: proc() {
    files.ensure_packaged_assets_unpacked_root()
}

//   Prepare baseline font glyphs and atlases without touching GPU resources.
prepare_fonts_worker :: proc(data: rawptr) {
    preparation := cast(^view_core.Baseline_Font_Preparation)data
    view_core.font_runtime_prepare_baseline(preparation, view_core.JULIA_MONO_FONT_LOAD_SIZE)
}

//   Keep drawing and pumping window events until one startup worker is ready.
finish_startup_worker :: proc(worker: ^thread.Thread, progress: f32) {
    if worker == nil {
        return
    }
    for !thread.is_done(worker) {
        draw_startup_frame(progress)
        _ = rl.WindowShouldClose()
        free_all(context.temp_allocator)
    }
    thread.destroy(worker)
}

//   Draw startup frames until the requested Julia worker event is available.
finish_julia_startup_request :: proc(
    service: ^julia.Julia_Runtime_Service, request_id: u64,
    expected_kind: julia.Julia_Event_Kind, progress: f32) -> bool {

    started_at := rl.GetTime()
    reported_unresponsive := false
    for {
        event, ok := julia.try_receive_julia_event(service)
        if ok && event.request_id == request_id && event.kind == expected_kind {
            if !event.succeeded {
                fmt.eprintln("Julia startup operation failed; request id: ", request_id)
            }
            return event.succeeded
        }
        if rl.GetTime() - started_at >= JULIA_UNRESPONSIVE_SECONDS {
            if !reported_unresponsive {
                fmt.eprintln("Julia startup operation is not responding; request id: ", request_id)
                reported_unresponsive = true
            }
        }
        draw_startup_frame(progress, reported_unresponsive)
        if rl.WindowShouldClose() {
            fmt.eprintln("Window closed before Julia startup completed; terminating process.")
            runtime.exit(0)
        }
        free_all(context.temp_allocator)
    }
}

//   Prepare packaged assets while keeping the startup window responsive.
prepare_assets_with_loading :: proc(progress: f32) {
    worker := thread.create_and_start(prepare_assets_worker)
    if worker == nil {
        files.ensure_packaged_assets_unpacked_root()
        return
    }
    finish_startup_worker(worker, progress)
}

//   Display and begin timing one blocking startup phase.
begin_startup_phase :: proc(label: string, progress: f32) -> f64 {
    draw_startup_frame(progress)
    fmt.println("Startup: ", label, "...")
    return rl.GetTime()
}

//   Log elapsed wall time for one completed startup phase.
end_startup_phase :: proc(label: string, started_at: f64) {
    elapsed_ms := int((rl.GetTime() - started_at) * 1000)
    fmt.println("Startup: ", label, " completed in ", elapsed_ms, " ms")
}

//   Initialize startup phases while the window stays responsive.
//
// Notes:
//   - Drives runtime startup through visible progress frames so window event processing never stalls.
//   - Shares runtime-state ownership with the headless session path after startup completes.
initialize_window_runtime_with_loading :: proc(
    settings: ^Euclid_Run_Settings) -> (Euclid_Runtime_Session, bool) {

    startup_started_at := rl.GetTime()
    started_at := begin_startup_phase("Preparing assets", 0.15)
    prepare_assets_with_loading(0.15)
    end_startup_phase("Preparing assets", started_at)

    started_at = begin_startup_phase("Starting Julia", 0.35)
    font_preparation := view_core.Baseline_Font_Preparation{}
    font_worker := thread.create_and_start_with_data(rawptr(&font_preparation), prepare_fonts_worker)
    julia_service, service_err := julia.create_julia_runtime_service()
    if service_err != .None || julia_service == nil {
        fmt.eprintln("Failed to create Julia runtime service.")
        return {}, false
    }
    initialize_id, initialize_sent := julia.try_submit_julia_request(julia_service, .Initialize)
    if !initialize_sent || !finish_julia_startup_request(
        julia_service, initialize_id, .Initialized, 0.35) {
        fmt.eprintln("Julia initialization failed.")
        julia.destroy_julia_runtime_service(julia_service)
        return {}, false
    }
    end_startup_phase("Starting Julia", started_at)

    started_at = begin_startup_phase("Loading content", 0.65)
    state := initiate_animations_state(julia_service, settings)
    if state == nil {
        fmt.eprintln("Runtime state initialization failed.")
        julia.destroy_julia_runtime_service(julia_service)
        return {}, false
    }
    _ = trace.record_runtime_event_ex(
        &state^.trace_state, "runtime.starting", julia_service^.runtime_generation,
        int(julia_service^.reload_state), initialize_id)
    content_id, content_sent := julia.try_submit_julia_request(
        julia_service, .Invoke, julia.initialize_julia_state_task, rawptr(state))
    if !content_sent || !finish_julia_startup_request(
        julia_service, content_id, .Invoke_Complete, 0.65) {
        fmt.eprintln("Julia content initialization failed.")
        shutdown_runtime_session(Euclid_Runtime_Session{
            state = state,
            julia_service = julia_service,
        })
        return {}, false
    }
    julia.mark_julia_runtime_ready(julia_service)
    _ = trace.record_runtime_event_ex(
        &state^.trace_state, "runtime.ready", julia_service^.runtime_generation,
        int(julia_service^.reload_state), content_id)
    end_startup_phase("Loading content", started_at)

    started_at = begin_startup_phase("Loading fonts and graphics", 0.85)
    finish_startup_worker(font_worker, 0.85)
    initialize_window_resources(state, settings, &font_preparation)
    end_startup_phase("Loading fonts and graphics", started_at)
    draw_startup_frame(1.0)
    end_startup_phase("Total startup", startup_started_at)
    return Euclid_Runtime_Session{state = state, julia_service = julia_service}, true
}
