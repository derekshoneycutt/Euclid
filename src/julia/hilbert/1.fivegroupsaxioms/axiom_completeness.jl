module HilbertChapterOneAxiomCompleteness

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const CircleCenter = [0.50f0, 0.50f0, 0f0]
const CircleRadius = 0.25f0
const CircleStartPoint = [CircleCenter[1] + CircleRadius, CircleCenter[2], 0f0]
const CircleSweepTheta = 2f0 * π

const TangentPoint = [CircleCenter[1], CircleCenter[2] + CircleRadius, 0f0]
const TangentOutEnd = [1.00f0, TangentPoint[2], 0f0]

const ExtensionVector = TangentOutEnd - TangentPoint
const ExtensionCenterEnd = CircleCenter + ExtensionVector
const ExtensionTipEnd = TangentPoint + ExtensionVector

const CircleColor = :steelblue
const ExtensionColor = :firebrick

const CircleBrush = 5f0
const ExtensionBrush = 5f0

const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const DescendDuration = 1.8f0
const CircleDrawDuration = 4.0f0
const CircleHighlightDuration = 2.2f0
const ArcMoveDuration = 1.2f0
const ExtensionMoveDuration = 1.8f0
const CompassRiseDuration = 1.6f0
const FinalPauseDuration = 0.25f0

const MetaCircleHostId = 1
const MetaCircleStartId = 2
const MetaCircleEndId = 3
const MetaTangentHostId = 4
const MetaTangentJoint1Id = 5
const MetaTangentJoint2Id = 6
const MetaTrailHostId = 7
const MetaTrailJoint1Id = 8
const MetaTrailJoint2Id = 9
const MetaPhase = 101
const MetaTimer = 102

const PhaseCompassDescend = 0f0
const PhaseDrawMainCircle = 1f0
const PhaseReinforceSweepForward = 2f0
const PhaseReinforceSweepReverse = 3f0
const PhaseArcToTangent = 4f0
const PhaseMoveCenterOut = 5f0
const PhaseHideInvalidExtension = 6f0
const PhaseCompassRise = 7f0
const PhaseFinalPause = 8f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Axiom of Completeness (Vollständigkeit)

To a system of points, straight lines, and planes, it is impossible to add other elements in such a manner that the system thus generalized shall form a new geometry obeying all of the five groups of axioms. In other words, the elements of geometry form a system which is not susceptible of extension, if we regard the five groups of axioms as valid.

This axiom gives us nothing directly concerning the existence of limiting points, or of the idea of convergence. Nevertheless, it enables us to demonstrate Bolzano's theorem by virtue of which, for all sets of points situated upon a straight line between two definite points of the same line, there exists necessarily a point of condensation, that is to say, a limiting point. From a theoretical point of view, the value of this axiom is that it leads indirectly to the introduction of limiting points, and, hence, renders it possible to establish a one-to-one correspondence between the points of a segment and the system of real numbers. However, in what is to follow, no use will be made of the "axiom of completeness."
"""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    circleHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleHostId))
    circleEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleEndId))
    tangentHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTangentHostId))
    tangentJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTangentJoint2Id))
    trailHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTrailHostId))
    trailJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTrailJoint2Id))

    OdinJuliaBridge.hide_point_batch(state_ptr, [circleHostId, tangentHostId, trailHostId])

    OdinJuliaBridge.set_point_position(state_ptr, circleEndId, CircleStartPoint)
    OdinJuliaBridge.set_point_offset(state_ptr, circleHostId, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, tangentJoint2Id, TangentPoint)
    OdinJuliaBridge.set_point_position(state_ptr, trailJoint2Id, CircleCenter)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)

    OdinJuliaBridge.lock_pen_joint1(
        state_ptr, ToolResetOffscreenJoint1[1], ToolResetOffscreenJoint1[2],
        ToolResetOffscreenJoint1[3])
    OdinJuliaBridge.move_pen_joint2(
        state_ptr, ToolResetOffscreenJoint2[1], ToolResetOffscreenJoint2[2],
        ToolResetOffscreenJoint2[3])
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, ToolResetOffscreenJoint1[1], ToolResetOffscreenJoint1[2],
        ToolResetOffscreenJoint1[3], sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, ToolResetOffscreenJoint2[1], ToolResetOffscreenJoint2[2],
        ToolResetOffscreenJoint2[3], sweep = false)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseCompassDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    circle = OdinJuliaBridge.create_new_filledcircle(
        state_ptr, CircleCenter, CircleRadius, 0f0, 0f0, CircleColor, 0f0)
    tangentRay = OdinJuliaBridge.create_new_line(
        state_ptr, TangentPoint, TangentPoint, ExtensionColor, 0f0)
    centerTrail = OdinJuliaBridge.create_new_line(
        state_ptr, CircleCenter, CircleCenter, ExtensionColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleHostId, Float32(circle.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleStartId, Float32(circle.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleEndId, Float32(circle.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTangentHostId, Float32(tangentRay.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaTangentJoint1Id, Float32(tangentRay.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaTangentJoint2Id, Float32(tangentRay.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTrailHostId, Float32(centerTrail.hostId))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaTrailJoint1Id, Float32(centerTrail.joint1Id))
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaTrailJoint2Id, Float32(centerTrail.joint2Id))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    circleHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleHostId))
    circleStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleStartId))
    circleEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleEndId))

    tangentHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTangentHostId))
    tangentJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTangentJoint1Id))
    tangentJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTangentJoint2Id))

    trailHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTrailHostId))
    trailJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTrailJoint1Id))
    trailJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaTrailJoint2Id))

    if circleHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseCompassDescend
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            CircleCenter[1], CircleCenter[2], CircleStartPoint[1], CircleStartPoint[2])
        OdinJuliaBridge.set_compass_active(state_ptr, 3, CircleColor)

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawMainCircle
            timer = 0f0
        end
    elseif phase == PhaseDrawMainCircle
        EuclidAnimations.animate_draw_filledcircle(
            state_ptr, timer, CircleDrawDuration, CircleCenter, CircleStartPoint,
            CircleSweepTheta, CircleRadius, CircleBrush, CircleColor,
            circleHostId, circleStartId, circleEndId)

        timer += dt
        if timer >= CircleDrawDuration
            OdinJuliaBridge.set_point_position(state_ptr, circleEndId, CircleStartPoint)
            OdinJuliaBridge.set_point_offset(state_ptr, circleHostId, 2f0 * π)
            phase = PhaseReinforceSweepForward
            timer = 0f0
        end
    elseif phase == PhaseReinforceSweepForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CircleHighlightDuration,
            CircleCenter, CircleStartPoint, 2f0 * π, CircleRadius, CircleColor)

        timer += dt
        if timer >= CircleHighlightDuration
            phase = PhaseReinforceSweepReverse
            timer = 0f0
        end
    elseif phase == PhaseReinforceSweepReverse
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CircleHighlightDuration,
            CircleCenter, CircleStartPoint, -2f0 * π, CircleRadius, CircleColor)

        timer += dt
        if timer >= CircleHighlightDuration
            phase = PhaseArcToTangent
            timer = 0f0
        end
    elseif phase == PhaseArcToTangent
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            CircleCenter, CircleCenter,
            CircleStartPoint, TangentPoint,
            0.10f0, 1, :none)
        OdinJuliaBridge.set_compass_active(state_ptr, 3, CircleColor)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseMoveCenterOut
            timer = 0f0
        end
    elseif phase == PhaseMoveCenterOut
        t = clamp(timer / ExtensionMoveDuration, 0f0, 1f0)

        centerPoint = CircleCenter + ExtensionVector * t
        tipPoint = TangentPoint + ExtensionVector * t

        OdinJuliaBridge.lock_compass_joint1(state_ptr, centerPoint; sweep = false)
        OdinJuliaBridge.lock_compass_joint2(state_ptr, tipPoint; sweep = false)
        OdinJuliaBridge.set_compass_active(state_ptr, 1, ExtensionColor)
        OdinJuliaBridge.show_compass(state_ptr)

        OdinJuliaBridge.set_point_color(state_ptr, tangentHostId, ExtensionColor)
        OdinJuliaBridge.set_point_brush(state_ptr, tangentHostId, ExtensionBrush)
        OdinJuliaBridge.set_point_position(state_ptr, tangentJoint1Id, TangentPoint)
        OdinJuliaBridge.set_point_position(state_ptr, tangentJoint2Id, tipPoint)
        OdinJuliaBridge.show_point(state_ptr, tangentHostId)

        OdinJuliaBridge.set_point_color(state_ptr, trailHostId, ExtensionColor)
        OdinJuliaBridge.set_point_brush(state_ptr, trailHostId, ExtensionBrush)
        OdinJuliaBridge.set_point_position(state_ptr, trailJoint1Id, CircleCenter)
        OdinJuliaBridge.set_point_position(state_ptr, trailJoint2Id, centerPoint)
        OdinJuliaBridge.show_point(state_ptr, trailHostId)
        OdinJuliaBridge.emit_trailing_particle(state_ptr, centerPoint, ExtensionColor)
        OdinJuliaBridge.emit_trailing_particle(state_ptr, tipPoint, ExtensionColor)

        timer += dt
        if timer >= ExtensionMoveDuration
            OdinJuliaBridge.lock_compass_joint1(
                state_ptr, ExtensionCenterEnd; sweep = false)
            OdinJuliaBridge.lock_compass_joint2(
                state_ptr, ExtensionTipEnd; sweep = false)
            OdinJuliaBridge.set_point_position(state_ptr, trailJoint2Id, ExtensionCenterEnd)
            phase = PhaseHideInvalidExtension
            timer = 0f0
        end
    elseif phase == PhaseHideInvalidExtension
        OdinJuliaBridge.hide_point_batch(state_ptr, [tangentHostId, trailHostId])
        phase = PhaseCompassRise
        timer = 0f0
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            ExtensionCenterEnd[1], ExtensionCenterEnd[2],
            ExtensionTipEnd[1], ExtensionTipEnd[2])
        OdinJuliaBridge.set_compass_active(state_ptr, 0, :white)

        timer += dt
        if timer >= CompassRiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhaseFinalPause
            timer = 0f0
        end
    elseif phase == PhaseFinalPause
        timer += dt
        if timer >= FinalPauseDuration
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end