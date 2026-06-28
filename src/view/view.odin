package view

import "../core"
import "../kine"
import "../julia"
import "../particles"

import rl "vendor:raylib"
import "core:math/linalg"

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

	for !rl.WindowShouldClose() {
        alpha := accumulate_and_update_systems(state)

		rl.BeginDrawing()
            draw_frame(state, alpha)
		rl.EndDrawing()

        free_all(context.temp_allocator)
	}
}
