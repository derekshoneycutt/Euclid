package view

// Here is where we initialize the application state and load up the window, running
// the loop for the lifetime of this instance.

import view_core "core"
import "ui"
import "../core"
import "../kine"
import "../julia"
import "../particles"
import "../files"

import "core:fmt"
import "core:math/linalg"
import "core:strings"

import rl "vendor:raylib"

MAX_KINEPOINTS :: core.MAX_KINEPOINTS
TOOL_LENGTH :: core.TOOL_LENGTH

Vector2 :: core.Vector2
Vector3 :: core.Vector3
Iso_Scale :: core.Iso_Scale
Kine_Shape_Point_Type :: core.Kine_Shape_Point_Type
Kine_Shape_Point :: core.Kine_Shape_Point
Kine_Constraint :: core.Kine_Constraint
Kine_Point_System :: core.Kine_Point_System
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
    state := initiate_animations_state()
    defer free_animations_state(state)

    initiate_window(state, settings)
    defer close_window(state)

    free_all(context.temp_allocator)

    for !rl.WindowShouldClose() {
        alpha := accumulate_and_update_systems(state)

        rl.BeginDrawing()
            draw_frame(state, alpha)
        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}




//   Allocate and initialize persistent runtime state for simulation and rendering.
//
// Notes:
//   - Allocates long-lived runtime state and returns ownership to caller.
initiate_animations_state :: proc() -> ^Euclid_General_State {
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

    julia_interface := julia.retrieve_interface()
    julia_interface^.current_animation = &julia_interface^.null_animation
    julia_interface^.current_animation_index = -1
    julia_interface^.selected_animation_index = -1
    julia_interface^.pending_animation_reset = false
    julia_interface^.animation_reset_cooldown_remaining = 0

    point_system := new(Kine_Point_System)

    compass := kine.init_kineshape_compass(point_system, TOOL_LENGTH, TOOL_COLOR, 5)
    pen := kine.init_kineshape_pen(point_system, TOOL_LENGTH, TOOL_COLOR, 5)
    kine.kine_freeze_system_indices(point_system)

    kine.apply_all_constraints_to_error(point_system, ALLOWED_CONSTRAINT_ERROR)
    kine.kine_update_last_cache_vectors(point_system)


    state := new(Euclid_General_State)
    state^.saved_context = context
    state^.iso_scale = iso_scale
    state^.draw_surface = drawing_surface
    state^.julia_interface = julia_interface
    state^.point_system = point_system
    state^.particle_system = particle_system
    state^.compass = compass
    state^.pen = pen
    state^.current_delta_time = FIXED_DT
    state^.accumulator = 0
    state^.ui_runtime.limit_fps = true
    state^.ui_runtime.simulation_paused = false
    state^.ui_runtime.use_simd_batch_projection = view_core.simd_batch_projection_available()
    ui.dynview_set_enabled(&state^.ui_runtime, ui.DYNVIEW_ENABLED_DEFAULT)
    state^.ui_runtime.gif_downsample_factor = 2
    state^.ui_runtime.gif_frame_step = 2
    state^.ui_runtime.gif_capture_phase = .Idle
    view_core.clear_gif_status_note(&state^.ui_runtime)


    julia.init_euclid_scripts(state)

    return state
}

//   Release runtime state allocations and finalize Julia/GIF runtime resources.
//
// Notes:
//   - Must be paired with initiate_animations_state to release owned allocations.
free_animations_state :: proc(state : ^Euclid_General_State) {
    view_core.gif_capture_abort_session(&state^.gif_capture)
    julia.clean_julia_interfaces(state)
    free(state^.julia_interface)
    free(state^.particle_system)
    free(state^.point_system)
    free(state^.draw_surface)
    free(state^.iso_scale)
    free(state)
}

//   Initialize window, shader/font resources, and GUI style settings.
//
// Notes:
//   - Should be paired with close_window on shutdown.
initiate_window :: proc(state : ^Euclid_General_State, settings: ^Euclid_Run_Settings) {
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
    if !view_core.font_runtime_init_with_regular(state, font_size) {
        fmt.eprintln("warning: failed to preload JuliaMono-Regular.ttf; text rendering may fallback")
    }
}

//   Shutdown render resources, unload font/shader, and close the window.
//
// Notes:
//   - Intended as the shutdown pair for initiate_window.
close_window :: proc(state : ^Euclid_General_State) {
    shutdown_particle_render_resources(state)
    shutdown_stroke3d_shader(state)
    view_core.font_runtime_unload_all(state)
    rl.CloseWindow()
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

    if state^.ui_runtime.simulation_paused {
        state^.accumulator = 0
        kine.build_kine_draw_cache(state^.point_system, 0)
        return 0
    }

    state^.accumulator += frame_dt

    kine.kine_update_last_cache_vectors(state^.point_system)
    step_count := 0
    for state^.accumulator >= FIXED_DT {
        julia.perform_animation_frame(state, FIXED_DT)
        particles.update_particles(state^.particle_system, FIXED_DT)
        kine.apply_all_constraints_to_error(state^.point_system, ALLOWED_CONSTRAINT_ERROR)
        view_core.gif_capture_update_fixed_step(state)

        state^.accumulator -= FIXED_DT
        step_count += 1
        if step_count >= MAX_STEPS_PER_FRAME {
            state^.accumulator = 0
            break
        }
    }

    alpha := state^.accumulator / FIXED_DT
    kine.build_kine_draw_cache(state^.point_system, alpha)

    return alpha
}

//   Render one full frame including world, particles, UI panels, and capture step.
draw_frame :: proc(state : ^Euclid_General_State, alpha: f32) {
    rl.ClearBackground(BACKGROUND_COLOR)

    draw_drawing_surface(state)

    draw_kine_points_low_cached(state)
    render_low_particles(state^.particle_system, state)
    draw_kine_points_shadows_cached(state)
    render_particles(state^.particle_system, state)
    draw_kine_points_high_cached(state)
    render_high_particles(state^.particle_system, state)

    if !state^.ui_runtime.simulation_paused && state^.ui_runtime.gif_capture_phase == .Recording {
        if !view_core.gif_capture_submit_frame(state) {
            view_core.gif_capture_abort_session(&state^.gif_capture)
            state^.ui_runtime.gif_capture_phase = .Error
            view_core.set_gif_status_note(&state^.ui_runtime, "Error: failed to submit GIF frame.")
        }
    }

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
