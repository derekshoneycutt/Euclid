package view


import fontmodel "font/model"
import font "font"
import input "input"
import native "native"
import viewcontent "content"
import ui "ui"
import core "../core"
import dynview "../dynview"
import julia "../bridge"
import capture "../evidence/capture"
import evidence_profile "../evidence/profile"
import evidence_session "../evidence/session"
import log "core:log"
import worldmodel "world/model"
import simulationmodel "simulation/model"
import viewmodel "ui/model"
import viewcapture "capture"
import viewmessages "messages"
import world "world"
import uisemantics "ui/semantics"
import viewpresentation "presentation"
import viewscenario "scenario"
import terminalservice "terminal/service"
import uiaccessibility "ui/accessibility"
import viewpreferences "preferences"
import libraryservice "ui/library/service"
import viewsimulation "simulation"
import inputbackend "input/backend"
import viewtelemetry "telemetry"
import uiterminal "ui/terminal"
import uisplitter "ui/layout/splitter"
import uioverlay "ui/overlay"
import uianimation "ui/animation"
import capturemodel "capture/model"

// Here is where we initialize the application state and load up the window, running
// the loop for the lifetime of this instance.


// Display-lifetime services and optional scenario sinks used by each window frame.
Window_Frame_Context :: struct {
    platform: ^native.Sdl_Platform,
    draw_runtime: ^native.Sdl_Draw_Runtime,
    chalk_audio: ^native.Sdl_Chalk_Audio_Runtime,
    input_runtime: ^input.Input_Runtime,
    presentation: ^viewpresentation.Presentation_Runtime,
    content_service: ^viewcontent.Content_Service,
    scenario_runtime: ^viewscenario.Scenario_Runtime,
    capture_sink: capture.Sink,
    framebuffer_operations: capturemodel.Framebuffer_Capture_Operations,
    display_profile: ^evidence_profile.State,
}

//   Frame-local values consumed only by observational drawing.
Frame_Draw_Preparation :: struct {
    input_frame: input.Input_Frame,
    terminal_frame: uiterminal.Terminal_Prepared_Frame,
    controls: ui.Ui_Control_Preparation,
    splitters: uisplitter.Splitter_Preparation,
    layout_interaction: ui.Ui_Layout_Interaction_Preparation,
}

//   - Owns state/window setup and teardown via deferred cleanup calls.
//   - Resets temp allocator each frame after drawing.
//
// Parameters:
//   - settings: The settings describing how to operate the window
//
// Returns:
//   - exit_code: non-zero when strict trace validation failed.
//   Submit one GIF frame while recording, aborting and noting the error on failure.
run_gif_capture_frame :: proc(
    state: ^core.Euclid_General_State,
    operations: capturemodel.Framebuffer_Capture_Operations) {
    if state^.gif_capture_status.gif_capture_phase != .Recording {
        return
    }
    state^.gif_capture.recording_presentations += 1
    if state^.ui_runtime.simulation_paused {
        state^.gif_capture.paused_presentations += 1
        return
    }
    if viewcapture.gif_capture_submit_frame(state, operations) {
        return
    }
    viewcapture.gif_capture_abort_session(&state^.gif_capture)
    state^.gif_capture_status.gif_capture_phase = .Error
    viewcapture.set_gif_status_note(&state^.gif_capture_status,
        viewmessages.shell_message(state, .Gif_Error_Submit_Frame))
}

//   Publish frame evidence, close profiling zones, and release temporary storage.
finish_window_frame :: proc(
    state: ^core.Euclid_General_State, display_profile: ^evidence_profile.State,
    presented := true) {
    if presented {
        _ = evidence_session.session_record(
            &state^.evidence_session, &state^.evidence_ring, {
                lane = .Presentation,
                kind = .Frame_Presented,
                correlation_kind = .Fixed_Step,
                correlation = state^.fixed_step,
                tick = state^.fixed_step,
            })
    }
    evidence_session.session_accept_ring(
        &state^.evidence_session, &state^.evidence_ring)
    evidence_profile.zone_end(display_profile)
    evidence_profile.frame(display_profile)
    free_all(context.temp_allocator)
}

//   Synchronize Dynview shaping when the resident math-font generation changes.
sync_window_math_shaping :: proc(state: ^core.Euclid_General_State) {
    entry := &state^.font_cache.entries[int(font.Font_Key.Math_Regular)]
    generation_changed :=
        state^.dynview.math_shaping.generation != entry.generation &&
        state^.dynview.math_shaping.failed_generation != entry.generation
    if !generation_changed {
        return
    }
    if font.math_shaping_sync(&state^.font_cache, &state^.dynview.math_shaping) {
        log.infof("dynview_math_shaper_ready generation=%d",
            state^.dynview.math_shaping.generation)
    } else {
        log.errorf("dynview_math_shaper_failed generation=%d", entry.generation)
    }
    dynview.invalidate(&state^.dynview, dynview.DYNVIEW_INVALIDATE_FONT)
}

// Track effective JuliaMono face generations after display-thread publication.
sync_window_prose_shaping :: proc(state: ^core.Euclid_General_State) {
    count := int(font.Font_Key.Math_Regular)
    effective_keys: [int(font.Font_Key.Math_Regular)]fontmodel.Font_Key
    generations: [int(font.Font_Key.Math_Regular)]u64
    for key_index in 0..<count {
        identity, ready := font.cache_shaping_identity(
            &state^.font_cache, font.Font_Key(key_index))
        if !ready {
            return
        }
        effective_keys[key_index] = identity.key
        generations[key_index] = identity.generation
    }
    dynview.track_prose_fonts(
        &state^.dynview, effective_keys[:], generations[:])
}

// Apply accepted scenario UI state before panel geometry and Dynview layout are prepared.
service_scenario_before_ui :: proc(ctx: Window_Frame_Context) {
    when core.SCENARIOS_ENABLED {
        if ctx.scenario_runtime != nil {
            _ = viewscenario.scenario_runtime_apply_pending_ui(ctx.scenario_runtime)
        }
    }
}

// Advance one active scenario before the frame is presented.
service_scenario_before_present :: proc(ctx: Window_Frame_Context) {
    when core.SCENARIOS_ENABLED {
        if ctx.scenario_runtime != nil {
            _ = viewscenario.scenario_runtime_update_current(
                ctx.scenario_runtime, ctx.input_runtime)
        }
    }
}

// Capture one active scenario after the frame is presented.
service_scenario_after_present :: proc(ctx: Window_Frame_Context) {
    when core.SCENARIOS_ENABLED {
        if ctx.scenario_runtime != nil {
            _ = viewscenario.scenario_runtime_after_present(
                ctx.scenario_runtime, ctx.capture_sink)
        }
    }
}

// Apply one portable UI cursor request through the active SDL platform owner.
apply_sdl_cursor :: proc(
    state: ^core.Euclid_General_State, platform: ^native.Sdl_Platform) {
    kind := native.Sdl_Cursor_Kind.Default
    if state^.ui_runtime.cursor == .Text {
        kind = .Text
    } else if state^.ui_runtime.cursor == .Resize_Ew {
        kind = .Resize_Ew
    } else if state^.ui_runtime.cursor == .Resize_Ns {
        kind = .Resize_Ns
    }
    if !native.sdl_platform_set_cursor(platform, kind) {
        log.warn("sdl_cursor_update_failed")
    }
}

// service_sdl_frame_runtime advances non-UI display services for one frame.
service_sdl_frame_runtime :: proc(
    state: ^core.Euclid_General_State, ctx: Window_Frame_Context,
    frame_dt: f32, sample_seconds: f64) {
    state^.ui_runtime.platform_reduce_motion = native.sdl_platform_refresh_motion(
        ctx.platform, sample_seconds)
    font.cache_service(
        &state^.font_cache, &state^.simulation_executor^.pool)
    sync_window_math_shaping(state)
    sync_window_prose_shaping(state)
    julia.publish_available_view_snapshot(state, false)
    viewpresentation.service_presentation_runtime(state, ctx.presentation)
    _ = apply_window_metrics(state, {
        width = ctx.platform^.metrics.logical_width,
        height = ctx.platform^.metrics.logical_height,
    })
    service_scenario_before_ui(ctx)
}

// route_ui_keyboard_frame claims semantic keys and returns ordered remaining input.
route_ui_keyboard_frame :: proc(
    state: ^core.Euclid_General_State, frame: input.Input_Frame,
    storage: []input.Input_Event) -> input.Input_Frame {
    semantic := state^.ui_runtime.semantic_focus
    event_claims := uisemantics.semantic_route_keyboard(
        semantic, frame, state^.ui_runtime.interaction_frame.terminal_focused)
    if uisemantics.semantic_focus_moved(semantic) {
        ui.ui_apply_semantic_focus(&state^.ui_runtime, frame,
            uiterminal.is_terminal_selected(state))
    }
    return input.input_frame_copy_unclaimed_events(frame, &event_claims, storage)
}

// frame_gif_capture_extents resolves logical and render dimensions for capture.
frame_gif_capture_extents :: proc(
    state: ^core.Euclid_General_State,
    platform: ^native.Sdl_Platform) -> capturemodel.Gif_Capture_Extents {
    world_rect := state^.ui_runtime.ui_regions.world_rect
    return {
        logical_width = max(1, int(world_rect.width)),
        logical_height = max(1, int(world_rect.height)),
        screen_width = platform^.metrics.logical_width,
        screen_height = platform^.metrics.logical_height,
        render_width = platform^.metrics.pixel_width,
        render_height = platform^.metrics.pixel_height,
    }
}

// Arbitrate topmost popup input before preparing ordinary geometry and pointer focus.
prepare_sdl_ui_input :: proc(
    state: ^core.Euclid_General_State, ctx: Window_Frame_Context,
    device_frame: input.Input_Frame, frame_dt: f32,
    menu_event_storage: []input.Input_Event) -> (
    input.Input_Frame, ui.Ui_Geometry_Preparation) {
    input_frame := uioverlay.context_menu_route(state, device_frame, menu_event_storage,
        ctx.input_runtime != nil && card(ctx.input_runtime^.mouse_captured) > 0)
    geometry := ui.prepare_ui_geometry(state, input_frame, frame_dt)
    ui.prepare_ui_static_interaction(state, input_frame, geometry.pointer_capture)
    if state^.ui_runtime.context_menu.focus_changed {
        ui.ui_apply_semantic_focus(&state^.ui_runtime,
            input_frame, uiterminal.is_terminal_selected(state))
        state^.ui_runtime.context_menu.focus_changed = false
    }
    return input_frame, geometry
}

// prepare_sdl_frame advances UI, presentation, simulation, and display caches.
prepare_sdl_frame :: proc(
    state: ^core.Euclid_General_State,
    ctx: Window_Frame_Context,
    clock: ^native.Sdl_Frame_Clock,
    device_frame: input.Input_Frame) -> Frame_Draw_Preparation {
    frame_dt := native.sdl_frame_clock_step(clock)
    service_sdl_frame_runtime(state, ctx, frame_dt, device_frame.sample_time_seconds)
    menu_event_storage: [input.INPUT_EVENT_CAPACITY]input.Input_Event
    input_frame, ui_geometry := prepare_sdl_ui_input(
        state, ctx, device_frame, frame_dt, menu_event_storage[:])
    routed_event_storage: [input.INPUT_EVENT_CAPACITY]input.Input_Event
    routed_frame := route_ui_keyboard_frame(state, input_frame, routed_event_storage[:])
    uiaccessibility.drain_accessibility_actions(state, ctx.platform)
    controls := ui.prepare_ui_controls(state, routed_frame, ui_geometry.splitters)
    if state^.simulation_executor != nil {
        viewpreferences.settings_save_service(state, &state^.simulation_executor^.pool)
    }
    libraryservice.service_library_search(state, ctx.content_service, frame_dt)
    terminal_frame := terminalservice.terminal_service_update(
        state, ctx.input_runtime, routed_frame)
    apply_sdl_cursor(state, ctx.platform)
    prepare_sdl_simulation_frame(state, ctx, frame_dt, ui_geometry.compile_dynview)
    layout_interaction := ui.prepare_and_finish_ui_layout(
        state, routed_frame, terminal_frame)
    execute_context_menu_command(state, ctx.input_runtime)
    uiaccessibility.publish_accessibility_controls(state, ctx.platform)
    service_scenario_before_present(ctx)
    return {input_frame, terminal_frame, controls, ui_geometry.splitters,
        layout_interaction}
}

// Step simulation, update drawing audio, and join caches before layout interaction.
prepare_sdl_simulation_frame :: proc(
    state: ^core.Euclid_General_State, ctx: Window_Frame_Context,
    frame_dt: f32, compile_dynview: bool) {
    gif_extents := frame_gif_capture_extents(state, ctx.platform)
    alpha := viewsimulation.accumulate_and_update_systems(state, frame_dt, gif_extents)
    native.sdl_chalk_audio_update(ctx.chalk_audio, &state^.chalk_audio,
        state^.user_drawing_sound_enabled,
        state^.ui_runtime.simulation_paused ||
            state^.ui_runtime.animation_policy_paused,
        frame_dt)
    viewsimulation.run_parallel_frame_preparation_after_ui(state, alpha, compile_dynview)
}

// encode_sdl_world_geometry encodes the clipped world draw stream.
encode_sdl_world_geometry :: proc(
    state: ^core.Euclid_General_State, ctx: Window_Frame_Context,
    encoder: ^native.Draw_Encoder) {
    _ = native.draw_encoder_push_scissor(
        encoder, state^.ui_runtime.ui_regions.world_rect)
    world.draw_encoded_drawing_surface(state, encoder)
    world.draw_encoded_cached_basic_pass(state, encoder, false)
    world.encode_low_particles(state^.particle_system, state, encoder,
        ctx.draw_runtime^.dust_atlas.handle)
    world.draw_encoded_cached_shadow_pass(state, encoder)
    world.draw_encoded_cached_tool_shadow_pass(state, encoder)
    world.encode_mid_particles(state^.particle_system, state, encoder,
        ctx.draw_runtime^.dust_atlas.handle)
    world.draw_encoded_shapes_high_merged_cached(state, encoder)
    world.encode_high_particles(state^.particle_system, state, encoder)
    _ = native.draw_encoder_pop_scissor(encoder)
}

// encode_sdl_ui_geometry encodes panel geometry and deferred text.
encode_sdl_ui_geometry :: proc(
    state: ^core.Euclid_General_State, encoder: ^native.Draw_Encoder,
    prepared: Frame_Draw_Preparation) {
    ui.draw_encoded_panel_geometry(state, encoder, prepared.controls)
    uianimation.draw_encoded_animation_controls(
        state, encoder, prepared.controls.animation_controls)
    uisplitter.draw_encoded_splitters(encoder, prepared.splitters)
    ui.draw_encoded_panel_text(state, encoder, prepared.controls)
    if uiterminal.is_terminal_selected(state) {
        terminalservice.terminal_graphics_set_draw_encoder(state, encoder)
        ui.draw_encoded_view_content(state, encoder, prepared.terminal_frame,
            prepared.layout_interaction.presentation)
        terminalservice.terminal_graphics_set_draw_encoder(state, nil)
    } else {
        ui.draw_encoded_view_content(state, encoder, prepared.terminal_frame,
            prepared.layout_interaction.presentation)
    }
    ui.draw_encoded_focus_outline(&state^.ui_runtime, encoder)
    uioverlay.draw_encoded_tooltip(state, encoder)
    uioverlay.draw_encoded_context_menu(state, encoder)
}

// encode_sdl_geometry_frame builds and submits one bounded geometry frame.
encode_sdl_geometry_frame :: proc(
    state: ^core.Euclid_General_State, ctx: Window_Frame_Context,
    prepared: Frame_Draw_Preparation) -> native.Sdl_Frame_Result {
    font.cache_frame_begin(&state^.font_cache)
    encoder: native.Draw_Encoder
    _ = native.draw_encoder_begin(&encoder, ctx.draw_runtime^.storage, {
        f32(ctx.platform^.metrics.logical_width),
        f32(ctx.platform^.metrics.logical_height),
    }, {ctx.platform^.scene_width, ctx.platform^.scene_height})
    native.draw_encoder_enable_strokes(&encoder, ctx.draw_runtime^.stroke_ready)
    native.draw_encoder_enable_dust_instancing(
        &encoder, ctx.draw_runtime^.dust_ready)
    encode_sdl_world_geometry(state, ctx, &encoder)
    encode_sdl_ui_geometry(state, &encoder, prepared)
    result := native.sdl_platform_present_draw(
        ctx.platform, ctx.draw_runtime, &encoder,
        native.to_sdl_color(worldmodel.BACKGROUND_COLOR))
    font.cache_frame_end(&state^.font_cache)
    return result
}

// Run one SDL geometry frame while later visual capabilities remain dormant.
run_sdl_geometry_frame :: proc(
    state: ^core.Euclid_General_State, ctx: Window_Frame_Context,
    clock: ^native.Sdl_Frame_Clock) -> bool {
    evidence_profile.zone_begin(ctx.display_profile, "display_frame")
    frame_started_at := native.sdl_time_ticks()
    input_frame := inputbackend.sdl_platform_poll_events(ctx.platform, ctx.input_runtime)
    if ctx.platform^.close_requested {
        finish_window_frame(state, ctx.display_profile, false)
        return false
    }
    prepared := prepare_sdl_frame(state, ctx, clock, input_frame)
    result := encode_sdl_geometry_frame(state, ctx, prepared)
    if result == .Failed {
        log.error("sdl_frame_present_failed")
        finish_window_frame(state, ctx.display_profile, false)
        return false
    }
    presented := result == .Presented
    if presented {
        viewtelemetry.publish_draw_frame_observation(state, ctx.draw_runtime)
        viewtelemetry.report_draw_frame_telemetry(state, ctx.draw_runtime)
        run_gif_capture_frame(state, ctx.framebuffer_operations)
        service_scenario_after_present(ctx)
    }
    finish_window_frame(state, ctx.display_profile, presented)
    if state^.ui_runtime.limit_fps {
        native.sdl_delay_until_rate(frame_started_at, u64(simulationmodel.LIMIT_FPS))
    }
    return true
}

// Abort protected GIF work before accepting a changed logical window extent.
apply_window_metrics :: proc(
    state: ^core.Euclid_General_State,
    metrics: viewmodel.Ui_Window_Metrics) -> bool {
    runtime := &state^.ui_runtime
    dimensions_changed := runtime^.window != metrics
    protected := state^.gif_capture_status.gif_capture_phase == .Armed ||
        state^.gif_capture_status.gif_capture_phase == .Recording ||
        state^.gif_capture_status.gif_capture_phase == .Finalizing
    if dimensions_changed && protected {
        previous := state^.gif_capture_status.gif_capture_phase
        viewcapture.gif_capture_abort_session(&state^.gif_capture)
        state^.gif_capture_status.gif_capture_phase = .Error
        state^.gif_capture_status.gif_capture_frame_counter = 0
        viewcapture.set_gif_status_note(&state^.gif_capture_status,
            viewmessages.shell_message(state, .Gif_Cancelled_Window_Resize))
        viewcapture.record_gif_capture_transition(state, previous, .Error)
    }
    return ui.ui_apply_window_metrics(runtime, metrics)
}
