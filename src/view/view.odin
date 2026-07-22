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

    code_points := []rune{
        // Basic ASCII (0x20 to 0x7E)
        0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c,
        0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
        0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46,
        0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x53,
        0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x60,
        0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d,
        0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a,
        0x7b, 0x7c, 0x7d, 0x7e,

        // Latin-1 accented letters and ligatures (common Western/Central European text).
        0x00c0, 0x00c1, 0x00c2, 0x00c3, 0x00c4, 0x00c5, 0x00c6, 0x00c7,
        0x00c8, 0x00c9, 0x00ca, 0x00cb, 0x00cc, 0x00cd, 0x00ce, 0x00cf,
        0x00d0, 0x00d1, 0x00d2, 0x00d3, 0x00d4, 0x00d5, 0x00d6, 0x00d8,
        0x00d9, 0x00da, 0x00db, 0x00dc, 0x00dd, 0x00de,
        0x00e0, 0x00e1, 0x00e2, 0x00e3, 0x00e4, 0x00e5, 0x00e6, 0x00e7,
        0x00e8, 0x00e9, 0x00ea, 0x00eb, 0x00ec, 0x00ed, 0x00ee, 0x00ef,
        0x00f0, 0x00f1, 0x00f2, 0x00f3, 0x00f4, 0x00f5, 0x00f6, 0x00f8,
        0x00f9, 0x00fa, 0x00fb, 0x00fc, 0x00fd, 0x00fe, 0x00ff,
        
        // Greek and Coptic Blocks (0x370 to 0x3CE)
        0x370, 0x371, 0x372, 0x373, 0x374, 0x375, 0x376, 0x377, 0x37a, 0x37b, 0x37c,
        0x37d, 0x37e, 0x384, 0x385, 0x386, 0x388, 0x389, 0x38a, 0x38c, 0x38e, 0x38f,
        0x390, 0x391, 0x392, 0x393, 0x394, 0x395, 0x396, 0x397, 0x398, 0x399, 0x39a,
        0x39b, 0x39c, 0x39d, 0x39e, 0x39f, 0x3a0, 0x3a1, 0x3a3, 0x3a4, 0x3a5, 0x3a6,
        0x3a7, 0x3a8, 0x3a9, 0x3aa, 0x3ab, 0x3ac, 0x3ad, 0x3ae, 0x3af, 0x3b0, 0x3b1,
        0x3b2, 0x3b3, 0x3b4, 0x3b5, 0x3b6, 0x3b7, 0x3b8, 0x3b9, 0x3ba, 0x3bb, 0x3bc,
        0x3bd, 0x3be, 0x3bf, 0x3c0, 0x3c1, 0x3c2, 0x3c3, 0x3c4, 0x3c5, 0x3c6, 0x3c7,
        0x3c8, 0x3c9, 0x3ca, 0x3cb, 0x3cc, 0x3cd, 0x3ce,

        // Alphanumeric superscripts and subscripts.
        // Digits and common operators in superscript/subscript forms.
        0x00b2, 0x00b3, 0x00b9, 0x2070, 0x2071, 0x2074, 0x2075, 0x2076, 0x2077,
        0x2078, 0x2079, 0x207a, 0x207b, 0x207c, 0x207d, 0x207e, 0x207f,
        0x2080, 0x2081, 0x2082, 0x2083, 0x2084, 0x2085, 0x2086, 0x2087,
        0x2088, 0x2089, 0x208a, 0x208b, 0x208c, 0x208d, 0x208e,

        // Superscript letters (Unicode-supported subset).
        0x00aa, 0x00ba, 0x02b0, 0x02b2, 0x02b3, 0x02b7, 0x02b8, 0x02e1,
        0x02e2, 0x02e3, 0x02e4, 0x1d2c, 0x1d2e, 0x1d30, 0x1d31, 0x1d33,
        0x1d34, 0x1d35, 0x1d36, 0x1d37, 0x1d38, 0x1d39, 0x1d3a, 0x1d3c,
        0x1d3e, 0x1d3f, 0x1d40, 0x1d41, 0x1d42, 0x1d43, 0x1d47, 0x1d48,
        0x1d49, 0x1d4d, 0x1d4f, 0x1d50, 0x1d52, 0x1d56, 0x1d57, 0x1d58,
        0x1d5b, 0x1d5d, 0x1d5e, 0x1d5f, 0x1d60, 0x1d61, 0x1d9c, 0x1da0,
        0x1dbb, 0x2c7d,

        // Subscript letters (Unicode-supported subset).
        0x1d62, 0x1d63, 0x1d64, 0x1d65, 0x1d66, 0x1d67, 0x1d68, 0x1d69,
        0x1d6a, 0x2090, 0x2091, 0x2092, 0x2093, 0x2094, 0x2095, 0x2096,
        0x2097, 0x2098, 0x2099, 0x209a, 0x209b, 0x209c, 0x2c7c,

        // Common math symbols beyond ASCII and Greek.
        0x002b, 0x003c, 0x003d, 0x003e, 0x007e, 0x00a7, 0x00ac, 0x00b0, 0x00b1, 0x00b2,
        0x00b3, 0x00b7, 0x00b9, 0x00d7, 0x00f7, 0x2220, 0x2032, 0x2033, 0x220e, 0x2260,
        0x2102, 0x2115, 0x211a,
        0x211d, 0x2124, 0x2190, 0x2191, 0x2192, 0x2193, 0x2194, 0x21d2, 0x21d4, 0x2200,
        0x2203, 0x2205, 0x2208, 0x2209, 0x220b, 0x220f, 0x2211, 0x2212, 0x2217, 0x221a,
        0x221d, 0x221e, 0x2220, 0x2225, 0x2227, 0x2228, 0x2229, 0x222a, 0x222b, 0x2234,
        0x223c, 0x2248, 0x2260, 0x2261, 0x2262, 0x2264, 0x2265, 0x2282, 0x2283, 0x2286,
        0x2287, 0x2295, 0x22a5, 0x25cb,
    }
    code_point_count := i32(len(code_points))
    font_size: i32 = 32
    font_file := strings.clone_to_cstring(
        files.packaged_asset_path("font.ttf", context.temp_allocator), context.temp_allocator)
    font := rl.LoadFontEx(font_file, font_size, &code_points[0], code_point_count)
    state^.font = font

    scratchpad_font_file := strings.clone_to_cstring(
        files.packaged_asset_path("font_mono.ttf", context.temp_allocator), context.temp_allocator)
    scratchpad_font := rl.LoadFontEx(
        scratchpad_font_file, font_size, &code_points[0], code_point_count)
    state^.scratchpad_font = scratchpad_font
}

//   Shutdown render resources, unload font/shader, and close the window.
//
// Notes:
//   - Intended as the shutdown pair for initiate_window.
close_window :: proc(state : ^Euclid_General_State) {
    shutdown_particle_render_resources(state)
    shutdown_stroke3d_shader(state)
    rl.UnloadFont(state^.scratchpad_font)
    rl.UnloadFont(state^.font)
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
        mono_font := state^.scratchpad_font

        fps_text := fmt.tprintf("FPS: %d", rl.GetFPS())
        fps_text_c := strings.clone_to_cstring(fps_text, context.temp_allocator)
        rl.DrawTextEx(mono_font, fps_text_c, rl.Vector2{10, 10}, 18, 0, UI_TEXT_COLOR)

        avg_text := fmt.tprintf("Avg FPS (60s): %.1f", state^.ui_runtime.fps_avg_live)
        avg_text_c := strings.clone_to_cstring(avg_text, context.temp_allocator)
        rl.DrawTextEx(mono_font, avg_text_c, rl.Vector2{10, 30}, 18, 0, UI_TEXT_COLOR)
    }
}
