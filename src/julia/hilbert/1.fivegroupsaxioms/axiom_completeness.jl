module HilbertChapterOneAxiomCompleteness

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

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

"""Stable native handles for one three-point animation object."""
struct ObjectIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one completeness animation generation."""
struct AnimationState
    circle::ObjectIds
    tangent::ObjectIds
    trail::ObjectIds
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseCompassDescend = 0f0
const PhaseDrawMainCircle = 1f0
const PhaseReinforceSweepForward = 2f0
const PhaseReinforceSweepReverse = 3f0
const PhaseArcToTangent = 4f0
const PhaseMoveCenterOut = 5f0
const PhaseHideInvalidExtension = 6f0
const PhaseCompassRise = 7f0
const PhaseFinalPause = 8f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.circle, state.tangent, state.trail, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom of Completeness (Vollständigkeit)

To a system of points, straight lines, and planes, it is impossible to add other elements in such a manner that the system thus generalized shall form a new geometry obeying all of the five groups of axioms. In other words, the elements of geometry form a system which is not susceptible of extension, if we regard the five groups of axioms as valid.

This axiom gives us nothing directly concerning the existence of limiting points, or of the idea of convergence. Nevertheless, it enables us to demonstrate Bolzano's theorem by virtue of which, for all sets of points situated upon a straight line between two definite points of the same line, there exists necessarily a point of condensation, that is to say, a limiting point. From a theoretical point of view, the value of this axiom is that it leads indirectly to the introduction of limiting points, and, hence, renders it possible to establish a one-to-one correspondence between the points of a segment and the system of real numbers. However, in what is to follow, no use will be made of the "axiom of completeness."
"""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom of Completeness (Vollständigkeit)}

To a system of points, straight lines, and planes, it is impossible to add other elements in such a manner that the system thus generalized shall form a new geometry obeying all of the five groups of axioms. In other words, the elements of geometry form a system which is not susceptible of extension, if we regard the five groups of axioms as valid.

This axiom gives us nothing directly concerning the existence of limiting points, or of the idea of convergence. Nevertheless, it enables us to demonstrate Bolzano's theorem by virtue of which, for all sets of points situated upon a straight line between two definite points of the same line, there exists necessarily a point of condensation, that is to say, a limiting point. From a theoretical point of view, the value of this axiom is that it leads indirectly to the introduction of limiting points, and, hence, renders it possible to establish a one-to-one correspondence between the points of a segment and the system of real numbers. However, in what is to follow, no use will be made of the "axiom of completeness."
"""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset cycle timing transactionally before restoring visible animation state."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    circle_hostid = state.circle.host
    circle_endid = state.circle.joint2
    tangent_host_id = state.tangent.host
    tangent_joint2_id = state.tangent.joint2
    trail_host_id = state.trail.host
    trail_joint2_id = state.trail.joint2

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseCompassDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_point_batch(state_ptr, [
        circle_hostid, tangent_host_id, trail_host_id])

    OdinJuliaBridge.set_point_position(state_ptr, circle_endid, CircleStartPoint)
    OdinJuliaBridge.set_point_offset(state_ptr, circle_hostid, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, tangent_joint2_id, TangentPoint)
    OdinJuliaBridge.set_point_position(state_ptr, trail_joint2_id, CircleCenter)

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

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    circle = OdinJuliaBridge.create_new_filledcircle(
        state_ptr, CircleCenter, CircleRadius, 0f0, 0f0, CircleColor, 0f0)
    tangent_ray = OdinJuliaBridge.create_new_line(
        state_ptr, TangentPoint, TangentPoint, ExtensionColor, 0f0)
    center_trail = OdinJuliaBridge.create_new_line(
        state_ptr, CircleCenter, CircleCenter, ExtensionColor, 0f0)

    state = AnimationState(
        ObjectIds(circle.host_id, circle.start_id, circle.end_id),
        ObjectIds(tangent_ray.host_id, tangent_ray.joint1_id, tangent_ray.joint2_id),
        ObjectIds(center_trail.host_id, center_trail.joint1_id, center_trail.joint2_id),
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
    circle_startid = state.circle.joint1
    circle_endid = state.circle.joint2
    tangent_host_id = state.tangent.host
    tangent_joint1_id = state.tangent.joint1
    tangent_joint2_id = state.tangent.joint2
    trail_host_id = state.trail.host
    trail_joint1_id = state.trail.joint1
    trail_joint2_id = state.trail.joint2

    if circle_hostid < 0
        return
    end

    phase = state.phase
    timer = state.timer

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
        EuclidAnimations.animate_draw_filledcircle(state_ptr,
            timer, CircleDrawDuration, CircleCenter,
            CircleStartPoint, CircleSweepTheta, CircleRadius;
            brush=CircleBrush,
            color=CircleColor,
            marker_host_id=circle_hostid,
            marker_start_id=circle_startid,
            marker_end_id=circle_endid)

        timer += dt
        if timer >= CircleDrawDuration
            OdinJuliaBridge.set_point_position(state_ptr, circle_endid, CircleStartPoint)
            OdinJuliaBridge.set_point_offset(state_ptr, circle_hostid, 2f0 * π)
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
            CircleStartPoint, TangentPoint;
            height=0.10f0)
        OdinJuliaBridge.set_compass_active(state_ptr, 3, CircleColor)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseMoveCenterOut
            timer = 0f0
        end
    elseif phase == PhaseMoveCenterOut
        t = clamp(timer / ExtensionMoveDuration, 0f0, 1f0)

        center_point = CircleCenter + ExtensionVector * t
        tip_point = TangentPoint + ExtensionVector * t

        OdinJuliaBridge.lock_compass_joint1(state_ptr, center_point; sweep = false)
        OdinJuliaBridge.lock_compass_joint2(state_ptr, tip_point; sweep = false)
        OdinJuliaBridge.set_compass_active(state_ptr, 1, ExtensionColor)
        OdinJuliaBridge.show_compass(state_ptr)

        OdinJuliaBridge.set_point_color(state_ptr, tangent_host_id, ExtensionColor)
        OdinJuliaBridge.set_point_brush(state_ptr, tangent_host_id, ExtensionBrush)
        OdinJuliaBridge.set_point_position(state_ptr, tangent_joint1_id, TangentPoint)
        OdinJuliaBridge.set_point_position(state_ptr, tangent_joint2_id, tip_point)
        OdinJuliaBridge.show_point(state_ptr, tangent_host_id)

        OdinJuliaBridge.set_point_color(state_ptr, trail_host_id, ExtensionColor)
        OdinJuliaBridge.set_point_brush(state_ptr, trail_host_id, ExtensionBrush)
        OdinJuliaBridge.set_point_position(state_ptr, trail_joint1_id, CircleCenter)
        OdinJuliaBridge.set_point_position(state_ptr, trail_joint2_id, center_point)
        OdinJuliaBridge.show_point(state_ptr, trail_host_id)
        OdinJuliaBridge.emit_trailing_particle(state_ptr, center_point, ExtensionColor)
        OdinJuliaBridge.emit_trailing_particle(state_ptr, tip_point, ExtensionColor)

        timer += dt
        if timer >= ExtensionMoveDuration
            OdinJuliaBridge.lock_compass_joint1(
                state_ptr, ExtensionCenterEnd; sweep = false)
            OdinJuliaBridge.lock_compass_joint2(
                state_ptr, ExtensionTipEnd; sweep = false)
            OdinJuliaBridge.set_point_position(
                state_ptr, trail_joint2_id, ExtensionCenterEnd)
            phase = PhaseHideInvalidExtension
            timer = 0f0
        end
    elseif phase == PhaseHideInvalidExtension
        OdinJuliaBridge.hide_point_batch(state_ptr, [tangent_host_id, trail_host_id])
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
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

end