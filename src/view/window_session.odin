package view

import input "input"
import native "native"
import viewcontent "content"
import core "../core"
import capture "../evidence/capture"
import evidence_profile "../evidence/profile"
import fmt "core:fmt"
import log "core:log"
import viewpresentation "presentation"
import viewscenario "scenario"
import capturemodel "capture/model"

// Display_Loop_Context groups display-lifetime native and service owners.
Display_Loop_Context :: struct {
    platform: ^native.Sdl_Platform,
    draw_runtime: ^native.Sdl_Draw_Runtime,
    chalk_audio: ^native.Sdl_Chalk_Audio_Runtime,
    input_runtime: ^input.Input_Runtime,
    presentation: ^viewpresentation.Presentation_Runtime,
    content_service: ^viewcontent.Content_Service,
    display_profile: ^evidence_profile.State,
}

// Optional scenario bindings and admission status for one window session.
Window_Scenario_Preparation :: struct {
    runtime: ^viewscenario.Scenario_Runtime,
    capture_sink: capture.Sink,
    loaded: bool,
}

//   Build the screenshot sink routed through one active scenario runtime.
scenario_capture_sink :: proc(
    runtime: ^viewscenario.Scenario_Runtime) -> capture.Sink {
    return {
        user_data = rawptr(runtime),
        capture = viewscenario.scenario_runtime_capture_screenshot,
    }
}

//   Load optional scenario state into caller-owned session storage.
prepare_window_scenario :: proc(
    settings: ^core.Euclid_Run_Settings, state: ^core.Euclid_General_State,
    runtime: ^viewscenario.Scenario_Runtime,
    framebuffer_operations: capturemodel.Framebuffer_Capture_Operations) ->
        Window_Scenario_Preparation {
    if len(settings^.scenario_input) == 0 {
        return {loaded = true}
    }
    if !viewscenario.scenario_runtime_load_file(
        runtime, state, settings^.scenario_input) {
        fmt.eprintln("Failed to load semantic scenario: ", settings^.scenario_input)
        log.error("scenario_load_failed")
        return {}
    }
    runtime^.framebuffer_operations = framebuffer_operations
    return {runtime, scenario_capture_sink(runtime), true}
}

//   Bind display-lifetime services for one frame loop.
window_frame_context :: proc(
    display: Display_Loop_Context,
    framebuffer_operations: capturemodel.Framebuffer_Capture_Operations,
    scenario: Window_Scenario_Preparation = {}) -> Window_Frame_Context {
    return {
        platform = display.platform,
        draw_runtime = display.draw_runtime,
        chalk_audio = display.chalk_audio,
        input_runtime = display.input_runtime,
        presentation = display.presentation,
        content_service = display.content_service,
        scenario_runtime = scenario.runtime,
        capture_sink = scenario.capture_sink,
        framebuffer_operations = framebuffer_operations,
        display_profile = display.display_profile,
    }
}

//   Initialize optional display profiling and begin the startup zone.
init_display_profile :: proc(
    profile: ^evidence_profile.State, path: string) {
    if len(path) > 0 && !evidence_profile.init_spall(profile, path) {
        fmt.eprintln("Failed to initialize display profile output.")
        log.warn("display_profile_init_failed")
    }
    evidence_profile.thread_name(profile, "display")
    evidence_profile.zone_begin(profile, "total startup")
}

//   Process display frames until the window or active scenario requests completion.
run_window_frames :: proc(
    state: ^core.Euclid_General_State, ctx: Window_Frame_Context) {
    clock: native.Sdl_Frame_Clock
    native.sdl_frame_clock_reset(&clock)
    for !ctx.platform^.close_requested {
        if !run_sdl_geometry_frame(state, ctx, &clock) {
            return
        }
        when core.SCENARIOS_ENABLED {
            if viewscenario.scenario_runtime_finished(ctx.scenario_runtime) {
                return
            }
        }
    }
}

//   Shut down a completed window session and convert scenario failure to process status.
finish_window_session :: proc(
    session: Euclid_Runtime_Session, display: Display_Loop_Context,
    scenario_runtime: ^viewscenario.Scenario_Runtime,
    artifact_output: string) -> int {
    native.sdl_chalk_audio_destroy(display.chalk_audio)
    exit_code := shutdown_window_runtime(
        session, scenario_runtime, artifact_output)
    if scenario_runtime != nil &&
       !viewscenario.scenario_runtime_succeeded(scenario_runtime) {
        return 1
    }
    return exit_code
}

//   Run frames and orderly shutdown for one initialized window session.
run_initialized_window_session :: proc(
    settings: ^core.Euclid_Run_Settings, session: Euclid_Runtime_Session,
    display: Display_Loop_Context,
    framebuffer_operations: capturemodel.Framebuffer_Capture_Operations) -> int {
    state := session.state
    log.info("display_runtime_ready")

    when core.SCENARIOS_ENABLED {
        scenario_runtime: viewscenario.Scenario_Runtime
        scenario := prepare_window_scenario(
            settings, state, &scenario_runtime, framebuffer_operations)
        if !scenario.loaded {
            native.sdl_chalk_audio_destroy(display.chalk_audio)
            _ = shutdown_window_runtime(session)
            return 1
        }

        free_all(context.temp_allocator)
        run_window_frames(state, window_frame_context(
            display, framebuffer_operations, scenario))
        _ = native.sdl_draw_submit_texture_operations(
            display.platform, display.draw_runtime)
        log.infof("display_loop_stopped fixed_step=%d scenario_active=%v",
            state^.fixed_step, scenario.runtime != nil)
        return finish_window_session(
            session, display, scenario.runtime, settings^.scenario_artifact_output)
    } else {
        free_all(context.temp_allocator)
        run_window_frames(state, window_frame_context(
            display, framebuffer_operations))
        _ = native.sdl_draw_submit_texture_operations(
            display.platform, display.draw_runtime)
        log.infof("display_loop_stopped fixed_step=%d", state^.fixed_step)
        native.sdl_chalk_audio_destroy(display.chalk_audio)
        return shutdown_window_runtime(session)
    }
}

// Build one display-loop context from admitted native and session resources.
display_loop_context :: proc(
    platform: ^native.Sdl_Platform, draw_runtime: ^native.Sdl_Draw_Runtime,
    input_runtime: ^input.Input_Runtime, session: Euclid_Runtime_Session,
    display_profile: ^evidence_profile.State) -> Display_Loop_Context {
    return {
        platform = platform,
        draw_runtime = draw_runtime,
        input_runtime = input_runtime,
        presentation = session.presentation,
        content_service = session.content_service,
        display_profile = display_profile,
    }
}
