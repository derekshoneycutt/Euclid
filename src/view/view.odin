package view

import ec "../core"
import surf "../surface"
import "../kine"

import rl "vendor:raylib"
import "core:math"
import "core:math/linalg"

Vector2 :: ec.Vector2
Vector3 :: ec.Vector3
KineShapePoint :: kine.KineShapePoint
KineConstraint :: kine.KineConstraint

IsoScaleValue :: 900
IsoXOffset :: 450
IsoYOffset :: 250

FIXED_DT :: f32(1.0 / 120.0)
MAX_FRAME_DT :: f32(0.25)
MAX_STEPS_PER_FRAME :: 6

AllowedConstraintError :: 0.0001

WindowHeight :: 720
WindowWidth :: 1280

WindowTitle :: "Euclid's Elements"

BackgroundColor :: rl.Color{36, 5, 16, 255}
ItemColor :: rl.Color{175, 150, 150, 255}

EuclidGeneralState :: struct {
    IsoScale : ^IsoScale,

    DrawSurface: ^surf.EuclidDrawingSurface,

    KinePoints: [dynamic]KineShapePoint,
    KineConstraints: [dynamic]KineConstraint,

    ScaleScaler: ^ViewScaler,
    XOffsetScaler: ^ViewScaler,
    YOffsetScaler: ^ViewScaler,
}

run_window_loop :: proc() {
    //rl.SetConfigFlags({.MSAA_4X_HINT})//, .VSYNC_HINT})
	rl.InitWindow(WindowWidth, WindowHeight, WindowTitle)

    isoScale := IsoScale{ IsoScaleValue, IsoXOffset, IsoYOffset }

    scaleScaler := init_view_scaler(
        init = f32(IsoScaleValue) / f32(WindowWidth),
        position = { 30, 60 },
        size = 100,
        indicator = 20,
        brushes = 5.0,
        horizontal = false)
    yOffsetScaler := init_view_scaler(
        init = f32(IsoYOffset) / f32(WindowHeight),
        position = { 30, 200 },
        size = 100,
        indicator = 20,
        brushes = 5.0,
        horizontal = false)
    xOffsetScaler := init_view_scaler(
        init = f32(IsoYOffset) / f32(WindowWidth),
        position = { 30, 340 },
        size = 100,
        indicator = 20,
        brushes = 5.0,
        horizontal = true)

    drawingSurface := surf.init_drawing_surface()

    kinePoints := make([dynamic]kine.KineShapePoint)
    defer delete(kinePoints)
    kineConstraints := make([dynamic]kine.KineConstraint)
    defer delete(kineConstraints)

    currentRot: f32 = math.PI / 4
    circleRadius: f32 = 0.25
    outPos := Vector3{ 0.5 + circleRadius * math.cos(currentRot), 0.5 + circleRadius * math.sin(currentRot), 0 }
    lastOutPos := outPos

    compass := kine.init_kineshape_compass(
        &kinePoints, &kineConstraints,
        {0.5, 0.5, 0}, {0.675, 0.375, 0.35}, outPos,
        0.35, ItemColor, 5)

    state := EuclidGeneralState{ &isoScale, &drawingSurface, kinePoints, kineConstraints,
        &scaleScaler, &xOffsetScaler, &yOffsetScaler }

    // Init Julia here e.g. init_euclid_scripts w/ pointer to state
    // TODO: below needs interface and construction with julia preferrably
    lockPoint1 := KineConstraint{ .SnapPoint, 1, { 0.5, 0.5, 0 }, 0, 0, 0, nil, true }
    lockPoint2 := KineConstraint{ .SnapPoint, 3, outPos, 0, 0, 0, nil, true }
    constraintLock1Id := len(kineConstraints)
    constraintLock2Id := constraintLock1Id + 1
    append(&kineConstraints, lockPoint1, lockPoint2)
    // end temporary section with possible future julia bindings

    kine.apply_all_constraints_to_error(
        &state.KineConstraints, &state.KinePoints, AllowedConstraintError)

    lastPointVecs := make([dynamic]Maybe(Vector3))
    defer delete(lastPointVecs)
    for &point in kinePoints {
        append(&lastPointVecs, point.Position)
    }

    accumulator: f32 = 0
	for !rl.WindowShouldClose() {
        frame_dt := rl.GetFrameTime()
        if frame_dt > MAX_FRAME_DT {
            frame_dt = MAX_FRAME_DT
        }
        accumulator += frame_dt

        if try_scaler_mouse_adjust(state.ScaleScaler) {
            isoScale.Scale = scaleScaler.CurrentValue * WindowWidth
        }
        else if try_scaler_mouse_adjust(state.XOffsetScaler) {
            isoScale.XOffset = xOffsetScaler.CurrentValue * WindowWidth
        }
        else if try_scaler_mouse_adjust(state.YOffsetScaler) {
            isoScale.YOffset = yOffsetScaler.CurrentValue * WindowHeight
        }

        for i in 1..<len(kinePoints) {
            lastPointVecs[i] = kinePoints[i].Position
        }
        lastOutPos = outPos
        stepCount := 0
        for accumulator >= FIXED_DT {
            // do this animation in julia
            currentRot -= FIXED_DT * math.PI / 2.0
            if currentRot < 0 {
                currentRot += 2.0 * math.PI
            }
            outPos := Vector3{
                0.5 + circleRadius * math.cos(currentRot),
                0.5 + circleRadius * math.sin(currentRot),
                0
            }
            compass.Joint2^.Position = outPos
            state.KineConstraints[constraintLock2Id].Restriction = outPos
            // end temp section to be done in julia

            kine.apply_all_constraints_to_error(
                &state.KineConstraints, &state.KinePoints, AllowedConstraintError)

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

            draw_kine_points(&lastPointVecs, &state, alpha)

            draw_view_scaler(state.ScaleScaler)
            draw_view_scaler(state.YOffsetScaler)
            draw_view_scaler(state.XOffsetScaler)

            rl.DrawFPS(10, 10)
		rl.EndDrawing()
	}

	rl.CloseWindow()
}
