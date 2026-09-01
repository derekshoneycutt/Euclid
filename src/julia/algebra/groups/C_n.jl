module EuclidAlgebraGroupsCn

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const CenterPoint = [0.50f0, 0.50f0, 0f0]
const Radius = 0.24f0
const CircleStartPoint = [CenterPoint[1] + Radius, CenterPoint[2], 0f0]
const CircleSweepTheta = 2f0 * π

const Point1 = [cos(0) * Radius, sin(0) * Radius, 0] + CenterPoint
const Point2 = [cos(π/6) * Radius, sin(π/6) * Radius, 0] + CenterPoint
const Point3 = [cos(π/3) * Radius, sin(π/3) * Radius, 0] + CenterPoint
const Point4 = [cos(π/2) * Radius, sin(π/2) * Radius, 0] + CenterPoint
const Point5 = [cos(2π/3) * Radius, sin(2π/3) * Radius, 0] + CenterPoint
const Point6 = [cos(5π/6) * Radius, sin(5π/6) * Radius, 0] + CenterPoint
const Point7 = [cos(π) * Radius, sin(π) * Radius, 0] + CenterPoint
const Point8 = [cos(7π/6) * Radius, sin(7π/6) * Radius, 0] + CenterPoint
const Point9 = [cos(4π/3) * Radius, sin(4π/3) * Radius, 0] + CenterPoint
const Point10 = [cos(3π/2) * Radius, sin(3π/2) * Radius, 0] + CenterPoint
const Point11 = [cos(5π/3) * Radius, sin(5π/3) * Radius, 0] + CenterPoint
const Point12 = [cos(11π/6) * Radius, sin(11π/6) * Radius, 0] + CenterPoint

const Point1Color = :steelblue
const Point2Color = :palevioletred1
const Point3Color = :khaki3
const Point4Color = :steelblue
const Point5Color = :palevioletred1
const Point6Color = :khaki3
const Point7Color = :steelblue
const Point8Color = :palevioletred1
const Point9Color = :khaki3
const Point10Color = :steelblue
const Point11Color = :palevioletred1
const Point12Color = :khaki3
const CircleColor = :grey60
const PointMaxBrush = 5f0
const CircleBrush = 5f0

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const PenDescendDuration = 1.8f0
const PointDrawDuration = 1.8f0
const PenRiseDuration = 1.8f0
const PenMoveDuration = 0.8f0
const CompassDescendDuration = 1.8f0
const CircleDrawDuration = 3.9f0
const CompassRiseDuration = 2.8f0
const Rotation1Duration = 2.2f0
const Rotation2Duration = 3.0f0
const Rotation3Duration = 3.8f0
const RotationPauseDuration = 1.0f0
const HidePauseDuration = 1.5f0

"""Stable native handles for the circle owned by the animation."""
struct CircleIds
    host::Int64
    start::Int64
    finish::Int64
end

"""Complete immutable state for one cyclic-group animation generation."""
struct AnimationState
    circle::CircleIds
    points::NTuple{12,Int64}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseCompassDescend = 1f0
const PhaseDrawCircle = 2f0
const PhaseCompassRise = 3f0
const PhasePenDescend = 10f0
const PhaseDrawPoint1 = 11f0
const PhaseDrawPoint2 = 12f0
const PhaseDrawPoint3 = 13f0
const PhaseDrawPoint4 = 14f0
const PhaseDrawPoint5 = 15f0
const PhaseDrawPoint6 = 16f0
const PhaseDrawPoint7 = 17f0
const PhaseDrawPoint8 = 18f0
const PhaseDrawPoint9 = 19f0
const PhaseDrawPoint10 = 20f0
const PhaseDrawPoint11 = 21f0
const PhaseDrawPoint12 = 22f0
const PhaseMovePen1To2 = 30f0
const PhaseMovePen2To3 = 31f0
const PhaseMovePen3To4 = 32f0
const PhaseMovePen4To5 = 33f0
const PhaseMovePen5To6 = 34f0
const PhaseMovePen6To7 = 35f0
const PhaseMovePen7To8 = 36f0
const PhaseMovePen8To9 = 37f0
const PhaseMovePen9To10 = 38f0
const PhaseMovePen10To11 = 39f0
const PhaseMovePen11To12 = 40f0
const PhasePenRise = 60f0
const PhaseRotation1 = 70f0
const PhaseRotation1Pause = 71f0
const PhaseRotation2 = 72f0
const PhaseRotation2Pause = 73f0
const PhaseRotation3 = 74f0
const PhaseRotation3Pause = 75f0
const PhaseHideAll = 100f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.circle, state.points, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = raw"""The cyclic group of rotations

This represents equal rotations around a fixed center. We turn the marked figure by equal steps, and keep track of which step we have reached.

Formally, Cₙ is the cyclic group of rotations by multiples of 2π/n about a fixed center.

Write ρ for one-step rotation. Then Cₙ = {e,ρ,ρ²,...,ρⁿ⁻¹} with ρⁿ=e.

The point is that these rotations compose cleanly: turn by one step, then another, and you still have a rotation of the same kind.

Brief proof it is a group:

1. Closure: ρⁱρʲ = ρⁱ⁺ʲ ᵐᵒᵈ ⁿ, still in the set.
2. Associativity: composition of rotations is associative.
3. Identity: ρ⁰ = e.
4. Inverses: (ρᵏ)⁻¹ = ρⁿ⁻ᵏ.

Also, Cₙ is abelian because turning by one amount and then another gives the same result as doing those turns in the opposite order."""
    latex = raw"""\textbf{The cyclic group of rotations}

This represents equal rotations around a fixed center. We turn the marked figure by equal steps, and keep track of which step we have reached.

Formally, $C_n$ is the cyclic group of rotations by multiples of $\frac{2\pi}{n}$ about a fixed center.

Write $\rho$ for one-step rotation. Then $C_n = \{e,\rho,\rho^2,\dots,\rho^{n-1}\}$ with $\rho^{n}=e$.

The point is that these rotations compose cleanly: turn by one step, then another, and you still have a rotation of the same kind.

Brief proof it is a group:

\textbf{1. Closure}: $\rho^i\rho^j = \rho^{i+j \;\mathrm{mod}\; n}$, still in the set.\\
\textbf{2. Associativity}: composition of rotations is associative.\\
\textbf{3. Identity}: $\rho^0=e$.\\
\textbf{4. Inverses}: $(\rho^k)^{-1}=\rho^{n-k}$.

Also, $C_n$ is abelian because turning by one amount and then another gives the same result as doing those turns in the opposite order."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    circle_hostid = state.circle.host
    circle_endid = state.circle.finish
    point1id, point2id, point3id, point4id, point5id, point6id,
        point7id, point8id, point9id, point10id, point11id, point12id = state.points

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [point1id, point2id, point3id, point4id, point5id, point6id, point7id, point8id,
         point9id, point10id, point11id, point12id, circle_hostid])
    OdinJuliaBridge.set_point_position(
        state_ptr, circle_endid, CircleStartPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle_hostid, 0f0)

    OdinJuliaBridge.set_point_position(
        state_ptr, point1id, Point1)
    OdinJuliaBridge.set_point_position(
        state_ptr, point2id, Point2)
    OdinJuliaBridge.set_point_position(
        state_ptr, point3id, Point3)
    OdinJuliaBridge.set_point_position(
        state_ptr, point4id, Point4)
    OdinJuliaBridge.set_point_position(
        state_ptr, point5id, Point5)
    OdinJuliaBridge.set_point_position(
        state_ptr, point6id, Point6)
    OdinJuliaBridge.set_point_position(
        state_ptr, point7id, Point7)
    OdinJuliaBridge.set_point_position(
        state_ptr, point8id, Point8)
    OdinJuliaBridge.set_point_position(
        state_ptr, point9id, Point9)
    OdinJuliaBridge.set_point_position(
        state_ptr, point10id, Point10)
    OdinJuliaBridge.set_point_position(
        state_ptr, point11id, Point11)
    OdinJuliaBridge.set_point_position(
        state_ptr, point12id, Point12)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)

    OdinJuliaBridge.set_pen_active(state_ptr, 0, Point1Color)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, CircleColor)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, CenterPoint[1], CenterPoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, CircleStartPoint[1], CircleStartPoint[2], CompassTopZ)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseCompassDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    circle = OdinJuliaBridge.create_new_circle(
        state_ptr, CenterPoint, Radius, 0f0, 0f0, CircleColor, 0f0)
    point1 = OdinJuliaBridge.create_new_point(
        state_ptr, Point1, Point1Color, 0f0)
    point2 = OdinJuliaBridge.create_new_point(
        state_ptr, Point2, Point2Color, 0f0)
    point3 = OdinJuliaBridge.create_new_point(
        state_ptr, Point3, Point3Color, 0f0)
    point4 = OdinJuliaBridge.create_new_point(
        state_ptr, Point4, Point4Color, 0f0)
    point5 = OdinJuliaBridge.create_new_point(
        state_ptr, Point5, Point5Color, 0f0)
    point6 = OdinJuliaBridge.create_new_point(
        state_ptr, Point6, Point6Color, 0f0)
    point7 = OdinJuliaBridge.create_new_point(
        state_ptr, Point7, Point7Color, 0f0)
    point8 = OdinJuliaBridge.create_new_point(
        state_ptr, Point8, Point8Color, 0f0)
    point9 = OdinJuliaBridge.create_new_point(
        state_ptr, Point9, Point9Color, 0f0)
    point10 = OdinJuliaBridge.create_new_point(
        state_ptr, Point10, Point10Color, 0f0)
    point11 = OdinJuliaBridge.create_new_point(
        state_ptr, Point11, Point11Color, 0f0)
    point12 = OdinJuliaBridge.create_new_point(
        state_ptr, Point12, Point12Color, 0f0)

    state = AnimationState(
        CircleIds(circle.host_id, circle.start_id, circle.end_id),
        (point1.index, point2.index, point3.index, point4.index,
            point5.index, point6.index, point7.index, point8.index,
            point9.index, point10.index, point11.index, point12.index),
        PhaseCompassDescend, 0f0)
    reset_cycle_state(state_ptr, state)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    circle_hostid = state.circle.host
    circle_startid = state.circle.start
    circle_endid = state.circle.finish
    point1id, point2id, point3id, point4id, point5id, point6id,
        point7id, point8id, point9id, point10id, point11id, point12id = state.points

    if point1id < 0 || point2id < 0 || point3id < 0 || point4id < 0 || point5id < 0 ||
        point6id < 0 ||  point7id < 0 || point8id < 0 || point9id < 0 || point10id < 0 ||
        point11id < 0 || point12id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseCompassDescend
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, CompassDescendDuration, CompassTopZ,
            CenterPoint[1], CenterPoint[2], CircleStartPoint[1], CircleStartPoint[2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawCircle
            timer = 0f0
        end
    elseif phase == PhaseDrawCircle
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, CircleDrawDuration, CenterPoint,
            CircleStartPoint, CircleSweepTheta, Radius;
            brush=CircleBrush,
            color=CircleColor,
            marker_host_id=circle_hostid,
            marker_start_id=circle_startid,
            marker_end_id=circle_endid)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle_endid, CircleStartPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle_hostid, 2f0π)
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            CenterPoint[1], CenterPoint[2], CircleStartPoint[1], CircleStartPoint[2])

        timer += dt
        if timer >= CompassRiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescend
            timer = 0f0
        end
    elseif phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration, PenTopZ, Point1[1], Point1[2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawPoint1
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint1
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point1,
            PointMaxBrush, Point1Color, point1id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMovePen1To2
            timer = 0f0
        end
    elseif phase == PhaseMovePen1To2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PenMoveDuration,
            Point1, Point2, 0.15f0, 1, :none)

        timer += dt
        if timer >= PenMoveDuration
            phase = PhaseDrawPoint2
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint2
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point2,
            PointMaxBrush, Point2Color, point2id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMovePen2To3
            timer = 0f0
        end
    elseif phase == PhaseMovePen2To3
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PenMoveDuration,
            Point2, Point3, 0.15f0, 1, :none)

        timer += dt
        if timer >= PenMoveDuration
            phase = PhaseDrawPoint3
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint3
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point3,
            PointMaxBrush, Point3Color, point3id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMovePen3To4
            timer = 0f0
        end
    elseif phase == PhaseMovePen3To4
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PenMoveDuration,
            Point3, Point4, 0.15f0, 1, :none)

        timer += dt
        if timer >= PenMoveDuration
            phase = PhaseDrawPoint4
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint4
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point4,
            PointMaxBrush, Point4Color, point4id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMovePen4To5
            timer = 0f0
        end
    elseif phase == PhaseMovePen4To5
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PenMoveDuration,
            Point4, Point5, 0.15f0, 1, :none)

        timer += dt
        if timer >= PenMoveDuration
            phase = PhaseDrawPoint5
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint5
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point5,
            PointMaxBrush, Point5Color, point5id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMovePen5To6
            timer = 0f0
        end
    elseif phase == PhaseMovePen5To6
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PenMoveDuration,
            Point5, Point6, 0.15f0, 1, :none)

        timer += dt
        if timer >= PenMoveDuration
            phase = PhaseDrawPoint6
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint6
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point6,
            PointMaxBrush, Point6Color, point6id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMovePen6To7
            timer = 0f0
        end
    elseif phase == PhaseMovePen6To7
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PenMoveDuration,
            Point6, Point7, 0.15f0, 1, :none)

        timer += dt
        if timer >= PenMoveDuration
            phase = PhaseDrawPoint7
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint7
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point7,
            PointMaxBrush, Point7Color, point7id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMovePen7To8
            timer = 0f0
        end
    elseif phase == PhaseMovePen7To8
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PenMoveDuration,
            Point7, Point8, 0.15f0, 1, :none)

        timer += dt
        if timer >= PenMoveDuration
            phase = PhaseDrawPoint8
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint8
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point8,
            PointMaxBrush, Point8Color, point8id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMovePen8To9
            timer = 0f0
        end
    elseif phase == PhaseMovePen8To9
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PenMoveDuration,
            Point8, Point9, 0.15f0, 1, :none)

        timer += dt
        if timer >= PenMoveDuration
            phase = PhaseDrawPoint9
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint9
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point9,
            PointMaxBrush, Point9Color, point9id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMovePen9To10
            timer = 0f0
        end
    elseif phase == PhaseMovePen9To10
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PenMoveDuration,
            Point9, Point10, 0.15f0, 1, :none)

        timer += dt
        if timer >= PenMoveDuration
            phase = PhaseDrawPoint10
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint10
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point10,
            PointMaxBrush, Point10Color, point10id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMovePen10To11
            timer = 0f0
        end
    elseif phase == PhaseMovePen10To11
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PenMoveDuration,
            Point10, Point11, 0.15f0, 1, :none)

        timer += dt
        if timer >= PenMoveDuration
            phase = PhaseDrawPoint11
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint11
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point11,
            PointMaxBrush, Point11Color, point11id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhaseMovePen11To12
            timer = 0f0
        end
    elseif phase == PhaseMovePen11To12
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PenMoveDuration,
            Point11, Point12, 0.15f0, 1, :none)

        timer += dt
        if timer >= PenMoveDuration
            phase = PhaseDrawPoint12
            timer = 0f0
        end
    elseif phase == PhaseDrawPoint12
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, Point12,
            PointMaxBrush, Point12Color, point12id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhasePenRise
            timer = 0f0
        end
    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration, PenTopZ, Point12[1], Point12[2])

        timer += dt
        if timer >= PenRiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseRotation1
            timer = 0f0
        end
    elseif phase == PhaseRotation1
        EuclidAnimations.transform_rotate_point(state_ptr, point1id, Point1,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point2id, Point2,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point3id, Point3,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point4id, Point4,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point5id, Point5,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point6id, Point6,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point7id, Point7,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point8id, Point8,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point9id, Point9,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point10id, Point10,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point11id, Point11,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point12id, Point12,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/6, timer, Rotation1Duration)

        timer += dt
        if timer >= Rotation1Duration
            phase = PhaseRotation1Pause
            timer = 0f0
        end
    elseif phase == PhaseRotation1Pause
        timer += dt
        if timer >= RotationPauseDuration
            phase = PhaseRotation2
            timer = 0f0
        end
    elseif phase == PhaseRotation2
        EuclidAnimations.transform_rotate_point(state_ptr, point1id, Point2,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point2id, Point3,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point3id, Point4,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point4id, Point5,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point5id, Point6,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point6id, Point7,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point7id, Point8,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point8id, Point9,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point9id, Point10,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point10id, Point11,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point11id, Point12,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point12id, Point1,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/3, timer, Rotation2Duration)

        timer += dt
        if timer >= Rotation2Duration
            phase = PhaseRotation2Pause
            timer = 0f0
        end
    elseif phase == PhaseRotation2Pause
        timer += dt
        if timer >= RotationPauseDuration
            phase = PhaseRotation3
            timer = 0f0
        end
    elseif phase == PhaseRotation3
        EuclidAnimations.transform_rotate_point(state_ptr, point1id, Point4,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point2id, Point5,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point3id, Point6,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point4id, Point7,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point5id, Point8,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point6id, Point9,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point7id, Point10,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point8id, Point11,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point9id, Point12,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point10id, Point1,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point11id, Point2,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)
        EuclidAnimations.transform_rotate_point(state_ptr, point12id, Point3,
            [0.5, 0.5, 0], [0.5, 0.5, 1], π/2, timer, Rotation3Duration)

        timer += dt
        if timer >= Rotation3Duration
            phase = PhaseRotation3Pause
            timer = 0f0
        end
    elseif phase == PhaseRotation3Pause
        timer += dt
        if timer >= RotationPauseDuration
            phase = PhaseHideAll
            timer = 0f0
        end
    elseif phase == PhaseHideAll
        timer += dt
        if timer >= HidePauseDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

end
