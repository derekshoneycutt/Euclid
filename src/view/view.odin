package view

import core "../core"
import julia "../bridge"
import viewcontent "content"
import native "native"
import startup "startup"
import inputbackend "input/backend"
import evidence_profile "../evidence/profile"
import capturebackend "capture/backend"
import viewscenario "scenario"
import terminalservice "terminal/service"
import viewtelemetry "telemetry"
import viewmodel "ui/model"
import thread "core:thread"
import log "core:log"

// Window_Session owns stable display resources from callback admission through AppQuit.
Window_Session :: struct {
    settings: core.Euclid_Run_Settings,
    startup_inputs: Session_Startup_Inputs,
    platform: native.Sdl_Platform,
    draw: native.Sdl_Draw_Runtime,
    profile: evidence_profile.State,
    loading: Window_Loading,
    runtime: Euclid_Runtime_Session,
    font_owner: Sdl_Font_Texture_Context,
    audio: native.Sdl_Chalk_Audio_Runtime,
    framebuffer: capturebackend.Sdl_Framebuffer_Context,
    gif: capturebackend.Sdl_Gif_Capture_Context,
    scenario: viewscenario.Scenario_Runtime,
    scenario_preparation: Window_Scenario_Preparation,
    clock: native.Sdl_Frame_Clock,
    gate: native.Sdl_Iteration_Gate,
    events: inputbackend.Sdl_Event_Inbox,
    frame: Window_Frame_Context,
    profile_ready: bool,
    draw_ready: bool,
    render_ready: bool,
    ready: bool,
    failed: bool,
    drawable_unavailable: bool,
}

// window_session_begin admits only native resources; slow startup advances in iterations.
window_session_begin :: proc(owner: ^Window_Session) -> bool {
    init_display_profile(&owner^.profile, owner^.settings.profile_path)
    owner^.profile_ready = true
    settings := &owner^.settings
    if !native.sdl_platform_create(&owner^.platform, {
        title = viewmodel.WINDOW_TITLE,
        width = settings^.window.width,
        height = settings^.window.height,
        resizable = settings^.window.mode == .Resizable,
        vsync = settings^.do_vsync,
        antialiasing = settings^.do_antialiasing,
    }) {
        log.error("sdl_platform_create_failed")
        return false
    }
    inputbackend.sdl_event_inbox_init(&owner^.events, &owner^.platform)
    if !native.sdl_draw_runtime_create(&owner^.draw, owner^.platform.device,
        sdl_draw_shader_paths(), owner^.platform.sample_count) {
        log.error("sdl_draw_runtime_create_failed")
        return false
    }
    owner^.draw_ready = true
    admit_optional_draw_pipelines(&owner^.draw, &owner^.platform)
    owner^.loading.display = startup.loading_display_create(
        &owner^.platform, &owner^.draw)
    return window_loading_begin(owner)
}

// window_session_admit_render binds stable font/capture owners after content initialization.
window_session_admit_render :: proc(owner: ^Window_Session) -> bool {
    display := display_loop_context(&owner^.platform, &owner^.draw,
        &owner^.runtime.state^.input_runtime, owner^.runtime, &owner^.profile)
    owner^.font_owner = sdl_font_texture_context(display)
    // Font failure may leave partial cache state; the shutdown path handles both.
    owner^.render_ready = true
    if !initialize_sdl_render_resources(&owner^.settings, owner^.runtime.state,
        &owner^.font_owner, &owner^.platform, &owner^.draw) {
        return false
    }
    display = bind_sdl_chalk_audio(display, &owner^.audio)
    owner^.framebuffer.platform = &owner^.platform
    if !capturebackend.bind_sdl_framebuffer_capture(&owner^.framebuffer) ||
        !capturebackend.bind_sdl_gif_capture(
            &owner^.gif, &owner^.runtime.state^.gif_capture) ||
        !terminalservice.terminal_graphics_bind_native(
            owner^.runtime.state, &owner^.platform, &owner^.draw) {
        log.error("display_backend_bind_failed")
        return false
    }
    operations := capturebackend.sdl_framebuffer_operations(&owner^.framebuffer)
    when core.SCENARIOS_ENABLED {
        owner^.scenario_preparation = prepare_window_scenario(
            &owner^.settings, owner^.runtime.state, &owner^.scenario, operations)
        if !owner^.scenario_preparation.loaded {
            return false
        }
    }
    owner^.font_owner.submit_immediately = false
    owner^.frame = window_frame_context(
        display, operations, owner^.scenario_preparation)
    native.sdl_frame_clock_reset(&owner^.clock)
    owner^.ready = true
    log.info("display_runtime_ready")
    return true
}

// window_session_step returns running=false on close, scenario completion, or explicit failure.
window_session_step :: proc(owner: ^Window_Session) -> (running, succeeded: bool) {
    now := native.sdl_time_ticks()
    if !native.sdl_iteration_enter(&owner^.gate) {
        return true, true
    }
    defer native.sdl_iteration_leave(&owner^.gate)
    // Lifecycle events must be observed even if presentation is unavailable or paced.
    if !inputbackend.sdl_event_inbox_service(
        &owner^.events, &owner^.platform, !owner^.ready) {
        return false, false
    }
    if owner^.platform.close_requested {
        when core.SCENARIOS_ENABLED {
            if len(owner^.settings.scenario_input) > 0 {
                return false, viewscenario.scenario_runtime_succeeded(
                    owner^.scenario_preparation.runtime)
            }
        }
        return false, true
    }
    limit := !owner^.ready || owner^.drawable_unavailable ||
        owner^.runtime.state^.ui_runtime.rendering.limit_fps
    if !native.sdl_iteration_due(&owner^.gate, now, limit,
        owner^.platform.resize_pending && !owner^.drawable_unavailable) {
        return true, true
    }
    admitted := native.sdl_platform_prepare_frame(&owner^.platform)
    if admitted == .Failed {
        return false, false
    }
    owner^.drawable_unavailable = admitted == .Unavailable
    owner^.frame.presentation_unavailable = owner^.drawable_unavailable
    defer free_all(context.temp_allocator)
    if !owner^.ready {
        return window_loading_step(owner)
    }
    return window_session_ready_step(owner)
}

// window_session_ready_step runs exactly one ordinary frame at admitted extents.
window_session_ready_step :: proc(owner: ^Window_Session) -> (bool, bool) {
    input_frame := inputbackend.sdl_input_callback_frame(
        &owner^.platform, &owner^.runtime.state^.input_runtime, &owner^.events)
    result := run_sdl_geometry_frame(
        owner^.runtime.state, owner^.frame, &owner^.clock, input_frame)
    if result == .Failed {
        return false, false
    }
    owner^.drawable_unavailable = result == .Unavailable
    when core.SCENARIOS_ENABLED {
        if viewscenario.scenario_runtime_finished(
            owner^.scenario_preparation.runtime) {
            return false, viewscenario.scenario_runtime_succeeded(
                owner^.scenario_preparation.runtime)
        }
    }
    return true, true
}

// window_session_destroy joins startup and releases each admitted owner before SDL quits.
window_session_destroy :: proc(owner: ^Window_Session) -> int {
    if owner^.loading.worker != nil {
        thread.join(owner^.loading.worker)
        thread.destroy(owner^.loading.worker)
        owner^.loading.worker = nil
    }
    result := window_session_release_runtime(owner)
    capturebackend.unbind_sdl_gif_capture(&owner^.gif)
    capturebackend.unbind_sdl_framebuffer_capture(&owner^.framebuffer)
    if owner^.draw_ready {
        viewtelemetry.report_draw_runtime_summary(&owner^.draw)
        native.sdl_draw_runtime_destroy(&owner^.draw, owner^.platform.device)
        owner^.draw_ready = false
    }
    native.sdl_platform_destroy(&owner^.platform)
    if owner^.profile_ready {
        evidence_profile.destroy(&owner^.profile)
        owner^.profile_ready = false
    }
    return result
}

// window_session_release_runtime preserves shutdown/evidence ordering after partial admission.
window_session_release_runtime :: proc(owner: ^Window_Session) -> int {
    native.sdl_chalk_audio_destroy(&owner^.audio)
    if owner^.draw_ready && owner^.draw.texture_operations.count > 0 {
        if !native.sdl_draw_submit_texture_operations(&owner^.platform, &owner^.draw) {
            log.error("display_shutdown_texture_submit_failed")
            owner^.failed = true
        }
    }
    result := 0
    session := owner^.runtime
    if session.state != nil {
        log.infof("display_loop_stopped fixed_step=%d scenario_active=%v",
            session.state^.fixed_step, owner^.scenario_preparation.runtime != nil)
        if owner^.render_ready {
            result = shutdown_window_runtime(session,
                owner^.scenario_preparation.runtime,
                owner^.settings.scenario_artifact_output)
        } else {
            result = shutdown_runtime_session(session)
        }
    } else {
        if session.julia_service != nil {
            shutdown_starting_julia_runtime(session.julia_service)
            julia.destroy_julia_runtime_service(session.julia_service)
        }
        if session.content_service != nil {
            viewcontent.content_service_destroy_owned(session.content_service)
        }
    }
    owner^.runtime = {}
    if owner^.failed {
        return 1
    }
    return result
}
