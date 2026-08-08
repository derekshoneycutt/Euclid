package view

// Here is where we initialize the application state and load up the window, running
// the loop for the lifetime of this instance.

import view_core "core"
import "ui"
import "../dynview"
import "../core"
import "../audio"
import "../shapes"
import julia "../bridge"
import "../files"

import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import "core:strings"
import "core:thread"

import rl "vendor:raylib"

MAX_SHAPESPOINTS :: core.MAX_SHAPESPOINTS
TOOL_LENGTH :: core.TOOL_LENGTH

Vector2 :: core.Vector2
Vector3 :: core.Vector3
Iso_Scale :: core.Iso_Scale
Shapes_Point_Type :: core.Shapes_Point_Type
Shapes_Point :: core.Shapes_Point
Shapes_Constraint :: core.Shapes_Constraint
Shapes_Point_System :: core.Shapes_Point_System
Particle :: core.Particle
Particle_System :: core.Particle_System
Euclid_Drawing_Surface :: core.Euclid_Drawing_Surface
Euclid_General_State :: core.Euclid_General_State
Euclid_Run_Settings :: core.Euclid_Run_Settings

ISO_SCALE_VALUE :: view_core.ISO_SCALE_VALUE
ISO_X_OFFSET :: view_core.ISO_X_OFFSET
ISO_Y_OFFSET :: view_core.ISO_Y_OFFSET

LIMIT_FPS :: view_core.LIMIT_FPS
FIXED_DT :: view_core.FIXED_DT
MAX_FRAME_DT :: view_core.MAX_FRAME_DT
MAX_STEPS_PER_FRAME :: view_core.MAX_STEPS_PER_FRAME
FPS_AVERAGE_BUCKET_COUNT :: view_core.FPS_AVERAGE_BUCKET_COUNT

ALLOWED_CONSTRAINT_ERROR :: view_core.ALLOWED_CONSTRAINT_ERROR

WINDOW_HEIGHT :: view_core.WINDOW_HEIGHT
WINDOW_WIDTH :: view_core.WINDOW_WIDTH

VIEW_HEIGHT :: view_core.VIEW_HEIGHT
BOTTOM_BAR_HEIGHT :: view_core.BOTTOM_BAR_HEIGHT
VIEW_WIDTH :: view_core.VIEW_WIDTH
RIGHT_BAR_WIDTH :: view_core.RIGHT_BAR_WIDTH

WINDOW_TITLE :: view_core.WINDOW_TITLE

BACKGROUND_COLOR :: view_core.BACKGROUND_COLOR
TOOL_COLOR :: view_core.TOOL_COLOR

UI_BACK_COLOR :: view_core.UI_BACK_COLOR
UI_BORDER_COLOR :: view_core.UI_BORDER_COLOR
UI_TEXT_COLOR :: view_core.UI_TEXT_COLOR

UI_COMPONENT_BACKGROUND_COLOR :: view_core.UI_COMPONENT_BACKGROUND_COLOR

SURFACE_COLOR :: view_core.SURFACE_COLOR
SURFACE_EDGE_SIZE :: view_core.SURFACE_EDGE_SIZE
SURFACE_EDGE_COLOR :: view_core.SURFACE_EDGE_COLOR

STARTUP_SPINNER_OFFSETS :: [8]rl.Vector2{
    {0, -18}, {13, -13}, {18, 0}, {13, 13},
    {0, 18}, {-13, 13}, {-18, 0}, {-13, -13},
}
STARTUP_TRACK_COLOR :: rl.Color{86, 55, 66, 255}
STARTUP_PROGRESS_COLOR :: rl.Color{175, 150, 150, 255}
STARTUP_WARNING_TEXT :: cstring("Julia is not responding")
JULIA_UNRESPONSIVE_SECONDS :: 10.0
JULIA_SHUTDOWN_TIMEOUT_SECONDS :: 5.0


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


//   Run full app lifecycle loop: init state/window, fixed updates, frame draw, cleanup.
//
// Notes:
//   - Owns state/window setup and teardown via deferred cleanup calls.
//   - Resets temp allocator each frame after drawing.
//
// Parameters:
//   - settings: The settings describing how to operate the window
//
// Returns:
//   - none.
run_window_loop :: proc(settings: ^Euclid_Run_Settings) {
    open_window(settings)
    defer rl.CloseWindow()

    state, julia_service := initialize_application_with_loading(settings)
    defer free_animations_state(state)
    defer shutdown_window_resources(state)
    defer destroy_simulation_executor(state^.simulation_executor)
    defer shutdown_julia_runtime(julia_service)

    free_all(context.temp_allocator)

    for !rl.WindowShouldClose() {
        ui.apply_scratchpad_async_results(state, &state^.ui_runtime)
        julia.publish_available_view_snapshot(state)
        alpha := accumulate_and_update_systems(state)
        run_parallel_frame_preparation(state, alpha)
        julia.try_request_view_snapshot(state)
        audio.update_chalk_runtime(&state^.chalk_audio)

        rl.BeginDrawing()
            draw_frame(state, alpha)
        rl.EndDrawing()

        if !state^.ui_runtime.simulation_paused && state^.ui_runtime.gif_capture_phase == .Recording {
            if !view_core.gif_capture_submit_frame(state) {
                view_core.gif_capture_abort_session(&state^.gif_capture)
                state^.ui_runtime.gif_capture_phase = .Error
                view_core.set_gif_status_note(&state^.ui_runtime, "Error: failed to submit GIF frame.")
            }
        }

        free_all(context.temp_allocator)
    }
}

//   Initialize application phases while the startup window remains responsive.
initialize_application_with_loading :: proc(
    settings: ^Euclid_Run_Settings) -> (^Euclid_General_State, ^julia.Julia_Runtime_Service) {

    startup_started_at := rl.GetTime()
    started_at := begin_startup_phase("Preparing assets", 0.15)
    prepare_assets_with_loading(0.15)
    end_startup_phase("Preparing assets", started_at)

    started_at = begin_startup_phase("Starting Julia", 0.35)
    font_preparation := view_core.Baseline_Font_Preparation{}
    font_worker := thread.create_and_start_with_data(rawptr(&font_preparation), prepare_fonts_worker)
    julia_service, service_err := julia.create_julia_runtime_service()
    assert(service_err == .None && julia_service != nil, "failed to create Julia runtime service")
    initialize_id, initialize_sent := julia.try_submit_julia_request(julia_service, .Initialize)
    if !initialize_sent || !finish_julia_startup_request(
        julia_service, initialize_id, .Initialized, 0.35) {
        fmt.eprintln("Julia initialization failed; terminating process.")
        runtime.exit(1)
    }
    end_startup_phase("Starting Julia", started_at)

    started_at = begin_startup_phase("Loading content", 0.65)
    state := initiate_animations_state(julia_service)
    content_id, content_sent := julia.try_submit_julia_request(
        julia_service, .Invoke, julia.initialize_julia_state_task, rawptr(state))
    if !content_sent || !finish_julia_startup_request(
        julia_service, content_id, .Invoke_Complete, 0.65) {
        fmt.eprintln("Julia content initialization failed; terminating process.")
        runtime.exit(1)
    }
    julia.mark_julia_runtime_ready(julia_service)
    end_startup_phase("Loading content", started_at)

    started_at = begin_startup_phase("Loading fonts and graphics", 0.85)
    finish_startup_worker(font_worker, 0.85)
    initialize_window_resources(state, settings, &font_preparation)
    end_startup_phase("Loading fonts and graphics", started_at)
    draw_startup_frame(1.0)
    end_startup_phase("Total startup", startup_started_at)
    return state, julia_service
}




//   Allocate and initialize persistent runtime state for simulation and rendering.
//
// Notes:
//   - Allocates long-lived runtime state and returns ownership to caller.
initiate_animations_state :: proc(
    julia_service: ^julia.Julia_Runtime_Service) -> ^Euclid_General_State {
    iso_scale := new(Iso_Scale)
    iso_scale^.scale = ISO_SCALE_VALUE
    iso_scale^.x_offset = ISO_X_OFFSET
    iso_scale^.y_offset = ISO_Y_OFFSET
    view_core.recompute_iso_scale_precompute(iso_scale)
    iso_scale^.main_light_dir = linalg.normalize(Vector3{0.35, -0.45, -1.0})
    iso_scale^.use_directional_shadow = true

    drawing_surface := new(Euclid_Drawing_Surface)
    drawing_surface^.zeros = Vector3{0 - SURFACE_EDGE_SIZE, 0 - SURFACE_EDGE_SIZE, 0}
    drawing_surface^.right_up = Vector3{1 + SURFACE_EDGE_SIZE, 0 - SURFACE_EDGE_SIZE, 0}
    drawing_surface^.left_down = Vector3{0 - SURFACE_EDGE_SIZE, 1 + SURFACE_EDGE_SIZE, 0}
    drawing_surface^.right_down = Vector3{1 + SURFACE_EDGE_SIZE, 1 + SURFACE_EDGE_SIZE, 0}
    drawing_surface^.color = SURFACE_COLOR
    drawing_surface^.edge_color = SURFACE_EDGE_COLOR
    drawing_surface^.edge_size = SURFACE_EDGE_SIZE

    particle_system := new(Particle_System)
    particle_system^.use_max_dust_particles = core.MAX_LOW_PARTICLES

    point_system := new(Shapes_Point_System)

    compass := shapes.init_compass(point_system, TOOL_LENGTH, TOOL_COLOR, 5)
    pen := shapes.init_pen(point_system, TOOL_LENGTH, TOOL_COLOR, 5)
    shapes.freeze_system_indices(point_system)

    shapes.apply_all_constraints_to_error(point_system, ALLOWED_CONSTRAINT_ERROR)
    shapes.update_last_cache_vectors(point_system)


    state := new(Euclid_General_State)
    state^.saved_context = context
    state^.julia_runtime_service = julia_service
    state^.julia_interface_active_slot = 0
    state^.julia_interface = &state^.julia_interface_slots[0]
    state^.iso_scale = iso_scale
    state^.draw_surface = drawing_surface
    state^.point_system = point_system
    state^.particle_system = particle_system
    state^.user_drawing_sound_enabled = true
    state^.animation_drawing_sound_enabled = true
    state^.compass = compass
    state^.pen = pen
    state^.current_delta_time = FIXED_DT
    state^.accumulator = 0
    state^.ui_runtime.limit_fps = true
    state^.ui_runtime.simulation_paused = false
    state^.ui_runtime.use_simd_batch_projection = view_core.simd_batch_projection_available()
    dynview.set_enabled(&state.dynview, dynview.DYNVIEW_ENABLED_DEFAULT)
    state^.ui_runtime.gif_downsample_factor = 2
    state^.ui_runtime.gif_frame_step = 2
    state^.ui_runtime.gif_capture_phase = .Idle
    view_core.clear_gif_status_note(&state^.ui_runtime)
    view_core.screenshake_clear(state^.iso_scale)
    state^.simulation_executor = create_simulation_executor(state)


    return state
}

//   Ask the Julia owner thread to tear down Julia, then release the service.
shutdown_julia_runtime :: proc(service: ^julia.Julia_Runtime_Service) {
    started_at := rl.GetTime()
    shutdown_id: u64
    sent := false
    for !sent {
        shutdown_id, sent = julia.try_submit_julia_request(service, .Shutdown)
        _, _ = julia.try_receive_julia_event(service)
        if rl.GetTime() - started_at >= JULIA_SHUTDOWN_TIMEOUT_SECONDS {
            fmt.eprintln("Julia shutdown request queue remained saturated; terminating process.")
            runtime.exit(1)
        }
        thread.yield()
    }
    for {
        event, ok := julia.try_receive_julia_event(service)
        if ok && event.request_id == shutdown_id && event.kind == .Shutdown_Complete {
            break
        }
        if rl.GetTime() - started_at >= JULIA_SHUTDOWN_TIMEOUT_SECONDS {
            fmt.eprintln("Julia shutdown timed out; terminating process.")
            runtime.exit(1)
        }
        thread.yield()
    }
    julia.destroy_julia_runtime_service(service)
}

//   Release runtime state allocations and finalize Julia/GIF runtime resources.
//
// Notes:
//   - Must be paired with initiate_animations_state to release owned allocations.
free_animations_state :: proc(state : ^Euclid_General_State) {
    view_core.gif_capture_destroy_session(&state^.gif_capture)
    julia.destroy_julia_interface_resources(state)
    free(state^.particle_system)
    free(state^.point_system)
    free(state^.draw_surface)
    free(state^.iso_scale)
    free(state)
}

//   Open the startup window without requiring packaged assets or application state.
//
// Notes:
//   - Should be paired with rl.CloseWindow on shutdown.
open_window :: proc(settings: ^Euclid_Run_Settings) {
    if settings.do_antialiasing && settings.do_vsync {
        rl.SetConfigFlags({.MSAA_4X_HINT, .VSYNC_HINT, .WINDOW_HIGHDPI})
    } else if settings.do_antialiasing {
        rl.SetConfigFlags({.MSAA_4X_HINT, .WINDOW_HIGHDPI})
    } else if settings.do_vsync {
        rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI})
    } else {
        rl.SetConfigFlags({.WINDOW_HIGHDPI})
    }

    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)
    rl.SetTargetFPS(LIMIT_FPS)
}

//   Initialize audio, icon, shader, and font resources after application state exists.
initialize_window_resources :: proc(
    state: ^Euclid_General_State, settings: ^Euclid_Run_Settings,
    font_preparation: ^view_core.Baseline_Font_Preparation) {

    rl.InitAudioDevice()
    if !rl.IsAudioDeviceReady() {
        fmt.eprintln("warning: failed to initialize audio device; chalk sound disabled")
    } else {
        audio.init_chalk_runtime(&state^.chalk_audio)
    }

    if state^.ui_runtime.limit_fps {
        rl.SetTargetFPS(LIMIT_FPS)
    } else {
        rl.SetTargetFPS(0)
    }

    icon_file := strings.clone_to_cstring(
        files.packaged_asset_path("compass_icon.png", context.temp_allocator), context.temp_allocator)
    if rl.FileExists(icon_file) {
        icon_image := rl.LoadImage(icon_file)
        rl.SetWindowIcon(icon_image)
        rl.UnloadImage(icon_image)
    }

    init_stroke3d_shader(state)

    font_size: i32 = view_core.JULIA_MONO_FONT_LOAD_SIZE
    if !view_core.font_runtime_init_from_preparation(state, font_preparation, font_size) {
        fmt.eprintln("warning: failed to preload baseline JuliaMono fonts (Regular/Bold/RegularItalic); text rendering may fallback")
    }
}

//   Shutdown state-dependent render and audio resources before closing the window.
//
// Notes:
//   - Intended as the shutdown pair for initialize_window_resources.
shutdown_window_resources :: proc(state : ^Euclid_General_State) {
    audio.shutdown_chalk_runtime(&state^.chalk_audio)
    if rl.IsAudioDeviceReady() {
        rl.CloseAudioDevice()
    }
    shutdown_particle_render_resources(state)
    shutdown_stroke3d_shader(state)
    view_core.font_runtime_unload_all(state)
}

//   Update rolling FPS statistics used for average-FPS overlay display.
update_average_fps :: proc(state: ^Euclid_General_State, frame_dt: f32) {
    if frame_dt <= 0 {
        return
    }

    ui_runtime := &state^.ui_runtime
    remaining := frame_dt

    for remaining > 0 {
        space := 1.0 - ui_runtime.fps_avg_bucket_elapsed
        step := remaining
        if step > space {
            step = space
        }

        cursor := ui_runtime.fps_avg_bucket_cursor
        ui_runtime.fps_avg_bucket_seconds[cursor] += step
        ui_runtime.fps_avg_rolling_seconds += step
        ui_runtime.fps_avg_bucket_elapsed += step
        remaining -= step

        if ui_runtime.fps_avg_bucket_elapsed >= 1.0 {
            next_cursor := (cursor + 1) % FPS_AVERAGE_BUCKET_COUNT

            ui_runtime.fps_avg_rolling_seconds -= ui_runtime.fps_avg_bucket_seconds[next_cursor]
            ui_runtime.fps_avg_rolling_frames -= ui_runtime.fps_avg_bucket_frames[next_cursor]

            ui_runtime.fps_avg_bucket_seconds[next_cursor] = 0
            ui_runtime.fps_avg_bucket_frames[next_cursor] = 0

            ui_runtime.fps_avg_bucket_cursor = next_cursor
            ui_runtime.fps_avg_bucket_elapsed = 0
        }
    }

    cursor := ui_runtime.fps_avg_bucket_cursor
    ui_runtime.fps_avg_bucket_frames[cursor] += 1
    ui_runtime.fps_avg_rolling_frames += 1

    if ui_runtime.fps_avg_rolling_seconds > 0 {
        ui_runtime.fps_avg_live =
            f32(ui_runtime.fps_avg_rolling_frames) / ui_runtime.fps_avg_rolling_seconds
    } else {
        ui_runtime.fps_avg_live = 0
    }
}

//   Run fixed-step simulation updates and return interpolation alpha for rendering.
accumulate_and_update_systems :: proc(state : ^Euclid_General_State) -> f32 {
    view_core.recompute_iso_scale_precompute(state^.iso_scale)

    frame_dt := rl.GetFrameTime()
    if frame_dt > MAX_FRAME_DT {
        frame_dt = MAX_FRAME_DT
    }
    update_average_fps(state, frame_dt)
    view_core.screenshake_update(state^.iso_scale, frame_dt)

    if state^.ui_runtime.simulation_paused {
        state^.accumulator = 0
        return 0
    }

    state^.accumulator += frame_dt

    shapes.update_last_cache_vectors(state^.point_system)
    step_count := 0
    for state^.accumulator >= FIXED_DT {
        // Never expose worker-commanded tool dimensions before constraints normalize them.
        julia.publish_available_animation_tick(state)
        julia.schedule_animation_tick(state, FIXED_DT)
        run_parallel_simulation_step(state^.simulation_executor, FIXED_DT)
        view_core.gif_capture_update_fixed_step(state)

        state^.accumulator -= FIXED_DT
        step_count += 1
        if step_count >= MAX_STEPS_PER_FRAME {
            state^.accumulator = 0
            break
        }
    }

    alpha := state^.accumulator / FIXED_DT
    return alpha
}

//   Render one full frame including world, particles, UI panels, and capture step.
draw_frame :: proc(state : ^Euclid_General_State, alpha: f32) {
    rl.ClearBackground(BACKGROUND_COLOR)

    base_x_offset := state^.iso_scale^.x_offset
    base_y_offset := state^.iso_scale^.y_offset

    apply_world_shake := state^.particle_system != nil &&
        state^.ui_runtime.gif_capture_phase != .Recording
    if apply_world_shake {
        state^.iso_scale^.x_offset += state^.iso_scale^.screenshake_offset_x
        state^.iso_scale^.y_offset += state^.iso_scale^.screenshake_offset_y
    }

    draw_drawing_surface(state)

    draw_Shapes_points_low_cached(state)
    render_low_particles(state^.particle_system, state)
    draw_Shapes_shapes_shadows_cached(state)
    draw_Shapes_points_shadows_cached(state)
    render_particles(state^.particle_system, state)
    draw_Shapes_points_high_merged_cached(state)
    render_high_particles(state^.particle_system, state)

    state^.iso_scale^.x_offset = base_x_offset
    state^.iso_scale^.y_offset = base_y_offset

    ui.draw_ui_panels(state)

    if state^.ui_runtime.display_fps {
        fps_flags := core.Font_Variant_Flags.Medium
        mono_font := view_core.font_runtime_resolve(
            state,
            fps_flags,
            view_core.JULIA_MONO_FONT_LOAD_SIZE)

        fps_text := fmt.tprintf("FPS: %d", rl.GetFPS())
        fps_text_c := strings.clone_to_cstring(fps_text, context.temp_allocator)
        rl.DrawTextEx(mono_font, fps_text_c, rl.Vector2{10, 10}, 18, 0, UI_TEXT_COLOR)

        avg_text := fmt.tprintf("Avg FPS (60s): %.1f", state^.ui_runtime.fps_avg_live)
        avg_text_c := strings.clone_to_cstring(avg_text, context.temp_allocator)
        rl.DrawTextEx(mono_font, avg_text_c, rl.Vector2{10, 30}, 18, 0, UI_TEXT_COLOR)
    }
}
