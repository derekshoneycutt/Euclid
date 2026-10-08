package view

import input "input"
import native "native"
import core "../core"
import evidence_profile "../evidence/profile"
import log "core:log"
import viewmodel "ui/model"
import capturebackend "capture/backend"
import terminalservice "terminal/service"
import viewtelemetry "telemetry"

// initialize_and_run_sdl_session admits native fonts and Terminal textures.
initialize_and_run_sdl_session :: proc(
    settings: ^core.Euclid_Run_Settings, session: Euclid_Runtime_Session,
    display: Display_Loop_Context) -> int {
    platform := display.platform
    draw_runtime := display.draw_runtime
    font_owner := sdl_font_texture_context(display)
    if !initialize_sdl_render_resources(
        settings, session.state, &font_owner, platform, draw_runtime) {
        _ = shutdown_window_runtime(session)
        return 1
    }
    return run_sdl_capture_session(settings, session, display, &font_owner)
}

// Bind display-lifetime capture and Terminal backends around the initialized window loop.
run_sdl_capture_session :: proc(
    settings: ^core.Euclid_Run_Settings, session: Euclid_Runtime_Session,
    display: Display_Loop_Context, font_owner: ^Sdl_Font_Texture_Context) -> int {
    platform := display.platform
    draw_runtime := display.draw_runtime
    chalk_audio: native.Sdl_Chalk_Audio_Runtime
    defer native.sdl_chalk_audio_destroy(&chalk_audio)
    bound_display := bind_sdl_chalk_audio(display, &chalk_audio)
    framebuffer_owner := capturebackend.Sdl_Framebuffer_Context{platform = platform}
    if !capturebackend.bind_sdl_framebuffer_capture(&framebuffer_owner) {
        log.error("display_framebuffer_start_failed")
        _ = shutdown_window_runtime(session)
        return 1
    }
    defer capturebackend.unbind_sdl_framebuffer_capture(&framebuffer_owner)
    gif_capture_owner: capturebackend.Sdl_Gif_Capture_Context
    if !capturebackend.bind_sdl_gif_capture(
        &gif_capture_owner, &session.state^.gif_capture) {
        log.error("display_gif_capture_start_failed")
        _ = shutdown_window_runtime(session)
        return 1
    }
    defer capturebackend.unbind_sdl_gif_capture(&gif_capture_owner)
    if !terminalservice.terminal_graphics_bind_native(
        session.state, platform, draw_runtime) {
        log.error("terminal_graphics_native_bind_failed")
        _ = shutdown_window_runtime(session)
        return 1
    }
    font_owner.submit_immediately = false
    return run_initialized_window_session(settings, session, bound_display,
        capturebackend.sdl_framebuffer_operations(&framebuffer_owner))
}


// run_sdl_platform_session owns draw, input, and Euclid state on one platform.
run_sdl_platform_session :: proc(
    settings: ^core.Euclid_Run_Settings, display_profile: ^evidence_profile.State,
    platform: ^native.Sdl_Platform,
    startup: ^Session_Startup_Inputs) -> int {
    draw_runtime: native.Sdl_Draw_Runtime
    if !native.sdl_draw_runtime_create(
        &draw_runtime, platform^.device, sdl_draw_shader_paths(),
        platform^.sample_count) {
        log.error("sdl_draw_runtime_create_failed")
        return 1
    }
    defer native.sdl_draw_runtime_destroy(&draw_runtime, platform^.device)
    admit_optional_draw_pipelines(&draw_runtime, platform)

    input_runtime := input.input_runtime_create(context.allocator)
    if input_runtime == nil {
        return 1
    }
    defer input.input_runtime_destroy(input_runtime, context.allocator)

    session, ok := initialize_window_runtime_with_loading(
        settings, display_profile, platform, &draw_runtime, startup)
    evidence_profile.zone_end(display_profile)
    if !ok {
        log.error("display_runtime_start_failed")
        return 1
    }
    display := display_loop_context(
        platform, &draw_runtime, input_runtime, session, display_profile)
    result := initialize_and_run_sdl_session(settings, session, display)
    viewtelemetry.report_draw_runtime_summary(&draw_runtime)
    return result
}

//   - Owns state/window setup and teardown via deferred cleanup calls.
//   - Resets temp allocator each frame after drawing.
//
// Parameters:
//   - settings: The settings describing how to operate the window
//
// Returns:
//   - exit_code: non-zero when strict trace validation failed.
run_window_loop :: proc(
    settings: ^core.Euclid_Run_Settings,
    startup: ^Session_Startup_Inputs = nil) -> int {
    display_profile: evidence_profile.State
    init_display_profile(&display_profile, settings^.profile_path)
    defer evidence_profile.destroy(&display_profile)
    platform := new(native.Sdl_Platform, context.allocator)
    defer free(platform, context.allocator)
    if !native.sdl_platform_create(platform, {
        title = viewmodel.WINDOW_TITLE,
        width = settings^.window.width,
        height = settings^.window.height,
        resizable = settings^.window.mode == .Resizable,
        vsync = settings^.do_vsync,
        antialiasing = settings^.do_antialiasing,
    }) {
        log.error("sdl_platform_create_failed")
        return 1
    }
    defer native.sdl_platform_destroy(platform)
    return run_sdl_platform_session(settings, &display_profile, platform, startup)
}
