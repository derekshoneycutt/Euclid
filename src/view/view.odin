package view

import "../core"
import "../surface"
import "../kine"
import "../julia"
import "../particles"

import rl "vendor:raylib"
import "core:math/linalg"

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
MAX_KINEPOINTS :: core.MAX_KINEPOINTS
TOOL_LENGTH :: core.TOOL_LENGTH

IsoScaleValue :: 800
IsoXOffset :: 450
IsoYOffset :: 450

LIMIT_FPS :: 60
FIXED_DT :: f32(1.0 / LIMIT_FPS)
MAX_FRAME_DT :: f32(0.25)
MAX_STEPS_PER_FRAME :: 6

AllowedConstraintError :: 0.0001

WindowHeight :: 720
WindowWidth :: 1280

ViewHeight :: 500
BottomBarHeight :: WindowHeight - ViewHeight
ViewWidth :: 900
RightBarWidth :: WindowWidth - ViewWidth

WindowTitle :: "Euclid's Elements"

BackgroundColor :: rl.Color{36, 5, 16, 255}
ItemColor :: rl.Color{96, 72, 82, 255}

UIBackColor :: rl.Color{66, 35, 46, 255}
BorderColor :: rl.Color{86, 55, 66, 255}
TextColor :: rl.Color{175, 150, 150, 255}

ComponentBackgroundColor :: rl.Color{25, 25, 25, 255}

run_window_loop :: proc() {
    isoScale := IsoScale{ IsoScaleValue, IsoXOffset, IsoYOffset, {0.35, -0.45, -1.0}, true }
    isoScale.MainLightDir = linalg.normalize(isoScale.MainLightDir)

    drawingSurface := surface.init_drawing_surface()

    particleSystem := new(ParticleSystem)
    defer free(particleSystem)
    particleSystem^.UseMaxDustParticles = core.MAX_LOW_PARTICLES
    
    juliaInterface := julia.retrieve_interface()
    defer free(juliaInterface)
    juliaInterface^.CurrentAnimation = &juliaInterface^.NullAnimation
    juliaInterface^.CurrentAnimationIndex = -1
    juliaInterface^.SelectedAnimationIndex = -1
    juliaInterface^.PendingAnimationReset = false
    juliaInterface^.AnimationResetCooldownRemaining = 0

    pointSystem := new(KinePointSystem)
    defer free(pointSystem)

    compass := kine.init_kineshape_compass(pointSystem, TOOL_LENGTH, ItemColor, 5)
    pen := kine.init_kineshape_pen(pointSystem, TOOL_LENGTH, ItemColor, 5)
    kine.kine_freeze_system_indices(pointSystem)

    tree_scroll_y: f32 = 0
    view_text_scroll_y: f32 = 0

    state := new(EuclidGeneralState)
    defer free(state)
    state^.SavedContext = context
    state^.IsoScale = &isoScale
    state^.DrawSurface = &drawingSurface
    state^.JuliaInterface = juliaInterface
    state^.PointSystem = pointSystem
    state^.ParticleSystem = particleSystem
    state^.Compass = compass
    state^.Pen = pen
    state^.CurrentDeltaTime = FIXED_DT
    state^.UIRuntime.GifDownsampleFactor = 2
    state^.UIRuntime.GifFrameStep = 2
    state^.UIRuntime.GifCapturePhase = .Idle

    gif_session := GifCaptureSession{}
    defer gif_capture_abort_session(&gif_session)

    julia.init_euclid_scripts(state)
    defer julia.clean_julia_interfaces(state)

    kine.apply_all_constraints_to_error(state^.PointSystem, AllowedConstraintError)
    kine.kine_update_last_cache_vectors(pointSystem)

    rl.SetConfigFlags({.MSAA_4X_HINT, .VSYNC_HINT})
	rl.InitWindow(WindowWidth, WindowHeight, WindowTitle)
	defer rl.CloseWindow()

    rl.SetTargetFPS(LIMIT_FPS)

    init_stroke3d_shader(state)
    defer shutdown_stroke3d_shader(state)

    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),
        i32(rl.ColorToInt(BackgroundColor)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BASE_COLOR_FOCUSED),
        i32(rl.ColorToInt(BorderColor)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BASE_COLOR_PRESSED),
        i32(rl.ColorToInt(BorderColor)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BORDER_COLOR_NORMAL),
        i32(rl.ColorToInt(BorderColor)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BORDER_COLOR_FOCUSED),
        i32(rl.ColorToInt(BorderColor)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.BORDER_COLOR_PRESSED),
        i32(rl.ColorToInt(BorderColor)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),
        i32(rl.ColorToInt(TextColor)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.TEXT_COLOR_FOCUSED),
        i32(rl.ColorToInt(TextColor)))
    rl.GuiSetStyle(.SLIDER, i32(rl.GuiControlProperty.TEXT_COLOR_PRESSED),
        i32(rl.ColorToInt(TextColor)))

    accumulator: f32 = 0
	for !rl.WindowShouldClose() {
        frame_dt := rl.GetFrameTime()
        if frame_dt > MAX_FRAME_DT {
            frame_dt = MAX_FRAME_DT
        }
        accumulator += frame_dt

        kine.kine_update_last_cache_vectors(pointSystem)
        stepCount := 0
        for accumulator >= FIXED_DT {
            julia.update_running_animations(state, FIXED_DT)
            julia.call_global_euclid_loop(state, FIXED_DT)
            julia.call_current_animation_loop(state, FIXED_DT)
            particles.update_particles(state^.ParticleSystem, FIXED_DT)
            kine.apply_all_constraints_to_error(state^.PointSystem, AllowedConstraintError)
            gif_capture_update_fixed_step(state, &gif_session)

            accumulator -= FIXED_DT
            stepCount += 1
            if stepCount >= MAX_STEPS_PER_FRAME {
                accumulator = 0
                break
            }
        }

        alpha := accumulator / FIXED_DT

        kine.build_kine_draw_cache(state^.PointSystem, alpha)

		rl.BeginDrawing()
        {
            rl.ClearBackground(BackgroundColor)

            draw_drawing_surface(state^.DrawSurface, state)

            draw_kine_points_low_cached(state)
            render_low_particles(state^.ParticleSystem, state)
            draw_kine_points_shadows_cached(state)
            render_particles(state^.ParticleSystem, state)
            draw_kine_points_high_cached(state)
            render_high_particles(state^.ParticleSystem, state)

            if state^.UIRuntime.GifCapturePhase == .Recording {
                if !gif_capture_submit_frame(state, &gif_session) {
                    gif_capture_abort_session(&gif_session)
                    state^.UIRuntime.GifCapturePhase = .Error
                }
            }

            rl.DrawRectangleRec(rl.Rectangle{0, ViewHeight, ViewWidth, BottomBarHeight}, UIBackColor)
            draw_view_text_panel(state, &view_text_scroll_y)

            rl.DrawRectangleRec(rl.Rectangle{ViewWidth, 0, RightBarWidth, WindowHeight}, UIBackColor)
            draw_tree_view(state, &tree_scroll_y)

            if state^.UIRuntime.DisplayFPS {
                rl.DrawFPS(10, 10)
            }
        }
		rl.EndDrawing()

        free_all(context.temp_allocator)
	}
}
