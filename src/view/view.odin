package view

// Here is where we initialize the application state and load up the window, running
// the loop for the lifetime of this instance.

import "../core"
import "../kine"
import "../julia"
import "../particles"
import "../files"

import "core:math/linalg"
import "core:strings"

import rl "vendor:raylib"

MAX_KINEPOINTS :: core.MAX_KINEPOINTS
TOOL_LENGTH :: core.TOOL_LENGTH

ISO_SCALE_VALUE :: 800
ISO_X_OFFSET :: 450
ISO_Y_OFFSET :: 450

LIMIT_FPS :: 60
FIXED_DT :: 1.0 / LIMIT_FPS
MAX_FRAME_DT :: 0.25
MAX_STEPS_PER_FRAME :: 6

ALLOWED_CONSTRAINT_ERROR :: 0.0001

WINDOW_HEIGHT :: 720
WINDOW_WIDTH :: 1280

VIEW_HEIGHT :: 500
BOTTOM_BAR_HEIGHT :: WINDOW_HEIGHT - VIEW_HEIGHT
VIEW_WIDTH :: 900
RIGHT_BAR_WIDTH :: WINDOW_WIDTH - VIEW_WIDTH

WINDOW_TITLE :: "Euclid's Elements"

BACKGROUND_COLOR :: rl.Color{36, 5, 16, 255}
TOOL_COLOR :: rl.Color{96, 72, 82, 255}

UI_BACK_COLOR :: rl.Color{66, 35, 46, 255}
UI_BORDER_COLOR :: rl.Color{86, 55, 66, 255}
UI_TEXT_COLOR :: rl.Color{175, 150, 150, 255}

UI_COMPONENT_BACKGROUND_COLOR :: rl.Color{25, 25, 25, 255}

SURFACE_COLOR :: rl.Color{25, 25, 25, 255}
SURFACE_EDGE_SIZE :: 0.05
SURFACE_EDGE_COLOR :: rl.Color{96, 65, 76, 255}

Vector2 :: core.Vector2
Vector3 :: core.Vector3
IsoScale :: core.IsoScale
KineShapePointType :: core.KineShapePointType
KineShapePoint :: core.KineShapePoint
KineConstraint :: core.KineConstraint
KinePointSystem :: core.KinePointSystem
Particle :: core.Particle
ParticleSystem :: core.ParticleSystem
EuclidDrawingSurface :: core.EuclidDrawingSurface
EuclidGeneralState :: core.EuclidGeneralState

initiate_animations_state :: proc() -> ^EuclidGeneralState {
    isoScale := new(IsoScale)
    isoScale^.Scale = ISO_SCALE_VALUE
    isoScale^.XOffset = ISO_X_OFFSET
    isoScale^.YOffset = ISO_Y_OFFSET
    isoScale^.MainLightDir = linalg.normalize(Vector3{0.35, -0.45, -1.0})
    isoScale^.UseDirectionalShadow = true

    drawingSurface := new(EuclidDrawingSurface)
    drawingSurface^.Zeros = Vector3{0 - SURFACE_EDGE_SIZE, 0 - SURFACE_EDGE_SIZE, 0}
    drawingSurface^.RightUp = Vector3{1 + SURFACE_EDGE_SIZE, 0 - SURFACE_EDGE_SIZE, 0}
    drawingSurface^.LeftDown = Vector3{0 - SURFACE_EDGE_SIZE, 1 + SURFACE_EDGE_SIZE, 0}
    drawingSurface^.RightDown = Vector3{1 + SURFACE_EDGE_SIZE, 1 + SURFACE_EDGE_SIZE, 0}
    drawingSurface^.Color = SURFACE_COLOR
    drawingSurface^.EdgeColor = SURFACE_EDGE_COLOR
    drawingSurface^.EdgeSize = SURFACE_EDGE_SIZE

    particleSystem := new(ParticleSystem)
    particleSystem^.UseMaxDustParticles = core.MAX_LOW_PARTICLES
    
    juliaInterface := julia.retrieve_interface()
    juliaInterface^.CurrentAnimation = &juliaInterface^.NullAnimation
    juliaInterface^.CurrentAnimationIndex = -1
    juliaInterface^.SelectedAnimationIndex = -1
    juliaInterface^.PendingAnimationReset = false
    juliaInterface^.AnimationResetCooldownRemaining = 0

    pointSystem := new(KinePointSystem)

    compass := kine.init_kineshape_compass(pointSystem, TOOL_LENGTH, TOOL_COLOR, 5)
    pen := kine.init_kineshape_pen(pointSystem, TOOL_LENGTH, TOOL_COLOR, 5)
    kine.kine_freeze_system_indices(pointSystem)

    kine.apply_all_constraints_to_error(pointSystem, ALLOWED_CONSTRAINT_ERROR)
    kine.kine_update_last_cache_vectors(pointSystem)


    state := new(EuclidGeneralState)
    state^.SavedContext = context
    state^.IsoScale = isoScale
    state^.DrawSurface = drawingSurface
    state^.JuliaInterface = juliaInterface
    state^.PointSystem = pointSystem
    state^.ParticleSystem = particleSystem
    state^.Compass = compass
    state^.Pen = pen
    state^.CurrentDeltaTime = FIXED_DT
    state^.Accumulator = 0
    state^.UIRuntime.GifDownsampleFactor = 2
    state^.UIRuntime.GifFrameStep = 2
    state^.UIRuntime.GifCapturePhase = .Idle


    julia.init_euclid_scripts(state)

    return state
}

free_animations_state :: proc(state : ^EuclidGeneralState) {
    gif_capture_abort_session(&state^.GifCapture)
    julia.clean_julia_interfaces(state)
    free(state^.JuliaInterface)
    free(state^.ParticleSystem)
    free(state^.PointSystem)
    free(state^.DrawSurface)
    free(state^.IsoScale)
    free(state)
}

initiate_window :: proc(state : ^EuclidGeneralState) {
    rl.SetConfigFlags({.MSAA_4X_HINT, .VSYNC_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE)

    rl.SetTargetFPS(LIMIT_FPS)

    init_stroke3d_shader(state)

    codepoints := []rune{
		// Basic ASCII (0x20 to 0x7E)
		0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f,
		0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f,
		0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f,
		0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f,
		0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f,
		0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e,
		
		// Greek and Coptic Blocks (0x370 to 0x3CE)
		0x370, 0x371, 0x372, 0x373, 0x374, 0x375, 0x376, 0x377, 0x37a, 0x37b, 0x37c, 0x37d, 0x37e,
		0x384, 0x385, 0x386, 0x388, 0x389, 0x38a, 0x38c, 0x38e, 0x38f,
		0x390, 0x391, 0x392, 0x393, 0x394, 0x395, 0x396, 0x397, 0x398, 0x399, 0x39a, 0x39b, 0x39c, 0x39d, 0x39e, 0x39f,
		0x3a0, 0x3a1, 0x3a3, 0x3a4, 0x3a5, 0x3a6, 0x3a7, 0x3a8, 0x3a9, 0x3aa, 0x3ab, 0x3ac, 0x3ad, 0x3ae, 0x3af,
		0x3b0, 0x3b1, 0x3b2, 0x3b3, 0x3b4, 0x3b5, 0x3b6, 0x3b7, 0x3b8, 0x3b9, 0x3ba, 0x3bb, 0x3bc, 0x3bd, 0x3be, 0x3bf,
		0x3c0, 0x3c1, 0x3c2, 0x3c3, 0x3c4, 0x3c5, 0x3c6, 0x3c7, 0x3c8, 0x3c9, 0x3ca, 0x3cb, 0x3cc, 0x3cd, 0x3ce,

        // etc.
        0x00a7,
	}
	codepoint_count := i32(len(codepoints))
	font_size: i32 = 32
    fontFile := strings.clone_to_cstring(
        files.packaged_asset_path("font.otf", context.temp_allocator), context.temp_allocator)
	font := rl.LoadFontEx(fontFile, font_size, &codepoints[0], codepoint_count)
    state^.Font = font

    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),
        i32(rl.ColorToInt(BACKGROUND_COLOR)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BASE_COLOR_FOCUSED),
        i32(rl.ColorToInt(UI_BORDER_COLOR)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BASE_COLOR_PRESSED),
        i32(rl.ColorToInt(UI_BORDER_COLOR)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BORDER_COLOR_NORMAL),
        i32(rl.ColorToInt(UI_BORDER_COLOR)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BORDER_COLOR_FOCUSED),
        i32(rl.ColorToInt(UI_BORDER_COLOR)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BORDER_COLOR_PRESSED),
        i32(rl.ColorToInt(UI_BORDER_COLOR)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),
        i32(rl.ColorToInt(UI_TEXT_COLOR)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.TEXT_COLOR_FOCUSED),
        i32(rl.ColorToInt(UI_TEXT_COLOR)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.TEXT_COLOR_PRESSED),
        i32(rl.ColorToInt(UI_TEXT_COLOR)))
}

close_window :: proc(state : ^EuclidGeneralState) {
    shutdown_stroke3d_shader(state)
    rl.UnloadFont(state^.Font)
	rl.CloseWindow()
}

accumulate_and_update_systems :: proc(state : ^EuclidGeneralState) -> f32 {
    frame_dt := rl.GetFrameTime()
    if frame_dt > MAX_FRAME_DT {
        frame_dt = MAX_FRAME_DT
    }
    state^.Accumulator += frame_dt

    kine.kine_update_last_cache_vectors(state^.PointSystem)
    stepCount := 0
    for state^.Accumulator >= FIXED_DT {
        julia.update_running_animations(state, FIXED_DT)
        julia.call_global_euclid_loop(state, FIXED_DT)
        julia.call_current_animation_loop(state, FIXED_DT)
        particles.update_particles(state^.ParticleSystem, FIXED_DT)
        kine.apply_all_constraints_to_error(state^.PointSystem, ALLOWED_CONSTRAINT_ERROR)
        gif_capture_update_fixed_step(state)

        state^.Accumulator -= FIXED_DT
        stepCount += 1
        if stepCount >= MAX_STEPS_PER_FRAME {
            state^.Accumulator = 0
            break
        }
    }

    alpha := state^.Accumulator / FIXED_DT
    kine.build_kine_draw_cache(state^.PointSystem, alpha)

    return alpha
}

draw_frame :: proc(state : ^EuclidGeneralState, alpha: f32) {
    rl.ClearBackground(BACKGROUND_COLOR)

    draw_drawing_surface(state)

    draw_kine_points_low_cached(state)
    render_low_particles(state^.ParticleSystem, state)
    draw_kine_points_shadows_cached(state)
    render_particles(state^.ParticleSystem, state)
    draw_kine_points_high_cached(state)
    render_high_particles(state^.ParticleSystem, state)

    if state^.UIRuntime.GifCapturePhase == .Recording {
        if !gif_capture_submit_frame(state) {
            gif_capture_abort_session(&state^.GifCapture)
            state^.UIRuntime.GifCapturePhase = .Error
        }
    }

    rl.DrawRectangleRec(rl.Rectangle{0, VIEW_HEIGHT, VIEW_WIDTH, BOTTOM_BAR_HEIGHT}, UI_BACK_COLOR)
    draw_view_text_panel(state)

    rl.DrawRectangleRec(rl.Rectangle{VIEW_WIDTH, 0, RIGHT_BAR_WIDTH, WINDOW_HEIGHT}, UI_BACK_COLOR)
    draw_tree_view(state)

    if state^.UIRuntime.DisplayFPS {
        rl.DrawFPS(10, 10)
    }
}

run_window_loop :: proc() {
    state := initiate_animations_state()
    defer free_animations_state(state)

    initiate_window(state)
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
