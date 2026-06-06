package view

import "../core"
import "../surface"
import "../kine"
import "../julia"
import "../particles"

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:math/linalg"

Vector2 :: core.Vector2
Vector3 :: core.Vector3
IsoScale :: core.IsoScale
KineShapePoint :: core.KineShapePoint
KineConstraint :: core.KineConstraint
Particle :: core.Particle
ParticleSystem :: core.ParticleSystem
EuclidDrawingSurface :: core.EuclidDrawingSurface
EuclidGeneralState :: core.EuclidGeneralState

IsoScaleValue :: 800
IsoXOffset :: 450
IsoYOffset :: 50

FIXED_DT :: f32(1.0 / 120.0)
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
ItemColor :: rl.Color{175, 150, 150, 255}

UIBackColor :: rl.Color{66, 35, 46, 255}
BorderColor :: rl.Color{86, 55, 66, 255}
TextColor :: rl.Color{175, 150, 150, 255}


run_window_loop :: proc() {
    rl.SetConfigFlags({.MSAA_4X_HINT})//, .VSYNC_HINT})
	rl.InitWindow(WindowWidth, WindowHeight, WindowTitle)
	defer rl.CloseWindow()

    isoScale := IsoScale{ IsoScaleValue, IsoXOffset, IsoYOffset }

    drawingSurface := surface.init_drawing_surface()

    kinePoints := make([dynamic]kine.KineShapePoint)
    defer delete(kinePoints)
    kineConstraints := make([dynamic]kine.KineConstraint)
    defer delete(kineConstraints)

    compass := kine.init_kineshape_compass(
        &kinePoints, &kineConstraints,
        {0.5, 0.5, 0}, {0.675, 0.375, 0.35}, {0.75, 0.25, 0},
        0.35, ItemColor, 5)

    particleSystem := new(ParticleSystem)
    defer free(particleSystem)

    state := EuclidGeneralState{context,
        &isoScale, &drawingSurface, &kinePoints, &kineConstraints,
        particleSystem, &compass, FIXED_DT,
        /* Metadata values start 0: */ 0, 0, 0, 0, 0, 0, 0, 0, 0 }

    julia.init_euclid_scripts(&state)

    kine.apply_all_constraints_to_error(
        state.KineConstraints, state.KinePoints, AllowedConstraintError)

    lastPointVecs := make([dynamic]Maybe(Vector3))
    defer delete(lastPointVecs)
    for &point in kinePoints {
        append(&lastPointVecs, point.Position)
    }

    euclidLoopFunc := julia.get_global_euclid_loop()

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

        for i in 1..<len(kinePoints) {
            lastPointVecs[i] = kinePoints[i].Position
        }
        stepCount := 0
        for accumulator >= FIXED_DT {
            julia.call_global_euclid_loop(euclidLoopFunc, &state, FIXED_DT)

            particles.update_particles(state.ParticleSystem, FIXED_DT)

            kine.apply_all_constraints_to_error(
                state.KineConstraints, state.KinePoints, AllowedConstraintError)

            accumulator -= FIXED_DT
            stepCount += 1
            if stepCount >= MAX_STEPS_PER_FRAME {
                accumulator = 0
                break
            }
        }

        alpha := accumulator / FIXED_DT

		rl.BeginDrawing()
            rl.ClearBackground(BackgroundColor)

            draw_drawing_surface(state.DrawSurface, &state)

            render_particles(state.ParticleSystem, &state)

            draw_kine_points(&lastPointVecs, &state, alpha)

            rl.DrawRectangleRec(rl.Rectangle{0, ViewHeight, ViewWidth, BottomBarHeight}, UIBackColor)
            rl.DrawRectangleRec(rl.Rectangle{ViewWidth, 0, RightBarWidth, WindowHeight}, UIBackColor)

            /*rl.GuiSliderBar(rl.Rectangle{ 1130, 600, 100, 20 }, "Scale:",
                fmt.ctprintf("%f", isoScale.Scale), &isoScale.Scale, 0.0, ViewWidth)
            rl.GuiSliderBar(rl.Rectangle{ 1130, 640, 100, 20 }, "Y Offset:",
                fmt.ctprintf("%f", isoScale.YOffset), &isoScale.YOffset, 0.0, ViewHeight)
            rl.GuiSliderBar(rl.Rectangle{ 1130, 680, 100, 20 }, "X Offset:",
                fmt.ctprintf("%f", isoScale.XOffset), &isoScale.XOffset, 0.0, ViewWidth)*/

            rl.DrawFPS(10, 10)
		rl.EndDrawing()
	}
}
