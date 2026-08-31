module ElementsOneProclusIsosceles

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const APoint = [0.466667f0, 0.53333336f0, 0f0]
const BPoint = [0.53333336f0, 0.466667f0, 0f0]
const Radius = norm(BPoint - APoint)
const ExtAPoint = [0.40f0, 0.60f0, 0f0]
const ExtBPoint = [0.60f0, 0.40f0, 0f0]
const ExtRadius = norm(ExtBPoint - ExtAPoint)
const Intersection = ExtAPoint + ExtRadius * [cos(π / 12f0), sin(π / 12f0), 0f0]
const CircleSweepTheta = 2f0 * π
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const ALabelPoint = APoint - [0.03f0, -0.02f0, 0f0]
const BLabelPoint = BPoint + [0.01f0, -0.01f0, 0f0]
const CLabelPoint = [0.73f0, 0.73f0, 0f0]

const LineABColor = :grey60
const LineCBColor = :steelblue
const LineCAColor = :palevioletred1
const Circle1Color = :khaki3
const Circle2Color = :steelblue
const Circle3Color = :grey60
const Circle4Color = :palevioletred1
const LabelColor = :plum1
const LineMaxBrush = 5f0
const CircleBrush = 5f0

const DescendDuration = 1.8f0
const LineDrawDuration = 2.8f0
const EndLiftDuration = 1.8f0
const CompassDescendDuration = 1.8f0
const CircleDrawDuration = 4.4f0
const CompassArcMoveDuration = 1.6f0
const CompassRiseDuration = 2.8f0
const EndArcMovePenDuration = 2f0
const HidePauseDuration = 1.5f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Stable native handles for one circle owned by the animation."""
struct CircleIds
    host::Int64
    start::Int64
    finish::Int64
end

"""Complete immutable state for one Proclus isosceles animation generation."""
struct AnimationState
    lines::NTuple{3,LineIds}
    circles::NTuple{4,CircleIds}
    labels::NTuple{3,Int64}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhasePenDescend = 0f0
const PhaseDrawLine = 1f0
const PhasePenRise = 2f0
const PhaseCompassDescend = 10f0
const PhaseDrawCircle1 = 21f0
const PhaseCompassArcToBA = 30f0
const PhaseDrawCircle2 = 31f0
const PhaseCompassRise = 40f0
const PhasePenDescend2 = 41f0
const PhaseExtendPointA = 42f0
const PhaseMoveToPointB = 45f0
const PhaseExtendPointB = 46f0
const PhasePenRise2 = 50f0
const PhaseCompassDescend2 = 51f0
const PhaseDrawCircle3 = 52f0
const PhaseCompassArcToBA2 = 55f0
const PhaseDrawCircle4 = 56f0
const PhaseCompassRise2 = 60f0
const PhasePenDescend3 = 61f0
const PhaseDrawLineCB = 62f0
const PhaseArcMovePen = 65f0
const PhaseDrawLineCA = 66f0
const PhasePenRise3 = 90f0
const PhaseHideAll = 100f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, state.circles, state.labels, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Proclus - Isosceles Triangle

On a given finite straight line to construct an isosceles triangle.

This follows Euclid's Elements Book I, Proposition I, with modifications.

To make an isosceles triangle he produces AB in both directions to meet the respective circles in D, E and then describes circles with A, B as centers and AE, BD as radii respectively. The result is an isosceles triangle with each of two sides double of the third side."""
    latex = raw"""\textbf{Euclid Elements - Book I - Proclus - Isosceles Triangle}

On a given finite straight line to construct an isosceles triangle.

\textit{This follows Euclid's Elements Book I, Proposition I, with modifications.}

To make an isosceles triangle he produces $AB$ \euclidline[color=grey60,length=3,thickness=4] in both
directions to meet the respective circles in $D$ \euclidcircle[color=khaki3,size=1,thickness=2],
$E$ \euclidcircle[color=steelblue,size=1,thickness=2] and then describes circles with
$A$ \euclidcircle[color=palevioletred1,size=1,thickness=2],
$B$ \euclidcircle[color=grey60,size=1,thickness=2] as centers and
$AE$ \euclidline[color=grey60,length=3,thickness=4],
$BD$ \euclidline[color=grey60,length=3,thickness=4] as radii respectively.
The result is an isosceles triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=grey60,edge3_color=steelblue] with each of two sides double of the third side."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_a_b, line_c_b, line_c_a = state.lines
    circle1, circle2, circle3, circle4 = state.circles
    label_a_id, label_b_id, label_c_id = state.labels
    line_a_b_host_id = line_a_b.host
    line_a_b_joint1_id = line_a_b.joint1
    line_a_b_joint2_id = line_a_b.joint2
    line_c_b_host_id = line_c_b.host
    line_c_b_joint2_id = line_c_b.joint2
    line_c_a_host_id = line_c_a.host
    line_c_a_joint2_id = line_c_a.joint2
    circle1_host_id = circle1.host
    circle1_start_id = circle1.start
    circle1_end_id = circle1.finish
    circle2_host_id = circle2.host
    circle2_start_id = circle2.start
    circle2_end_id = circle2.finish
    circle3_host_id = circle3.host
    circle3_start_id = circle3.start
    circle3_end_id = circle3.finish
    circle4_host_id = circle4.host
    circle4_start_id = circle4.start
    circle4_end_id = circle4.finish

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [label_a_id, label_b_id, label_c_id,
         line_a_b_host_id, line_c_b_host_id, line_c_a_host_id,
         circle1_host_id, circle2_host_id, circle3_host_id, circle4_host_id
        ])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
        
    OdinJuliaBridge.lock_compass_joint1(state_ptr, APoint[1], APoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, BPoint[1], BPoint[2], CompassTopZ)

    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_b_joint1_id, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_b_joint2_id, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_c_b_joint2_id, Intersection)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_c_a_joint2_id, Intersection)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle1_start_id, BPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle1_end_id, BPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle1_host_id, 0f0)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle2_start_id, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle2_end_id, APoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle2_host_id, 0f0)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle3_start_id, ExtBPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle3_end_id, ExtBPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle3_host_id, 0f0)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle4_start_id, ExtAPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle4_end_id, ExtAPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle4_host_id, 0f0)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhasePenDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, APoint, APoint, LineABColor, 0f0)
    circle1 = OdinJuliaBridge.create_new_circle(
        state_ptr, APoint, Radius, 7f0 * π / 4f0, 7f0 * π / 4f0, Circle1Color, 0f0)
    circle2 = OdinJuliaBridge.create_new_circle(
        state_ptr, BPoint, Radius, 3f0 * π / 4f0, 3f0 * π / 4f0, Circle2Color, 0f0)
    circle3 = OdinJuliaBridge.create_new_circle(
        state_ptr, ExtAPoint, ExtRadius, 7f0 * π / 4f0, 7f0 * π / 4f0, Circle3Color, 0f0)
    circle4 = OdinJuliaBridge.create_new_circle(
        state_ptr, ExtBPoint, ExtRadius, 3f0 * π / 4f0, 3f0 * π / 4f0, Circle4Color, 0f0)
    line_c_b = OdinJuliaBridge.create_new_line(
        state_ptr, Intersection, Intersection,
        LineCBColor, 0f0)
    line_c_a = OdinJuliaBridge.create_new_line(
        state_ptr, Intersection, Intersection,
        LineCAColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)

    state = AnimationState(
        (LineIds(line_a_b.host_id, line_a_b.joint1_id, line_a_b.joint2_id),
            LineIds(line_c_b.host_id, line_c_b.joint1_id, line_c_b.joint2_id),
            LineIds(line_c_a.host_id, line_c_a.joint1_id, line_c_a.joint2_id)),
        (CircleIds(circle1.host_id, circle1.start_id, circle1.end_id),
            CircleIds(circle2.host_id, circle2.start_id, circle2.end_id),
            CircleIds(circle3.host_id, circle3.start_id, circle3.end_id),
            CircleIds(circle4.host_id, circle4.start_id, circle4.end_id)),
        (label_a.index, label_b.index, label_c.index), PhasePenDescend, 0f0)
    reset_cycle_state(state_ptr, state)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    line_a_b, line_c_b, line_c_a = state.lines
    circle1, circle2, circle3, circle4 = state.circles
    label_a_id, label_b_id, label_c_id = state.labels
    line_a_b_host_id = line_a_b.host
    line_a_b_joint1_id = line_a_b.joint1
    line_a_b_joint2_id = line_a_b.joint2
    line_c_b_host_id = line_c_b.host
    line_c_b_joint1_id = line_c_b.joint1
    line_c_b_joint2_id = line_c_b.joint2
    line_c_a_host_id = line_c_a.host
    line_c_a_joint1_id = line_c_a.joint1
    line_c_a_joint2_id = line_c_a.joint2
    circle1_host_id = circle1.host
    circle1_start_id = circle1.start
    circle1_end_id = circle1.finish
    circle2_host_id = circle2.host
    circle2_start_id = circle2.start
    circle2_end_id = circle2.finish
    circle3_host_id = circle3.host
    circle3_start_id = circle3.start
    circle3_end_id = circle3.finish
    circle4_host_id = circle4.host
    circle4_start_id = circle4.start
    circle4_end_id = circle4.finish

    if line_a_b_host_id < 0 || line_c_b_host_id < 0 || line_c_a_host_id < 0 ||
        circle1_host_id < 0 || circle2_host_id < 0 ||
        circle3_host_id < 0 || circle4_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, APoint[1], APoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine
            timer = 0f0

            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            APoint, BPoint;
            penbrush=LineMaxBrush,
            pencolor=LineABColor,
            line_host_id=line_a_b_host_id,
            line_joint1_id=line_a_b_joint1_id,
            line_joint2_id=line_a_b_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenRise
            timer = 0f0

            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, BPoint[1], BPoint[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseCompassDescend
            timer = 0f0
        end
    elseif phase == PhaseCompassDescend
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, CompassDescendDuration, CompassTopZ,
            APoint[1], APoint[2], BPoint[1], BPoint[2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawCircle1
            timer = 0f0
        end
    elseif phase == PhaseDrawCircle1
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, CircleDrawDuration, APoint,
            BPoint, CircleSweepTheta, Radius;
            brush=CircleBrush,
            color=Circle1Color,
            marker_host_id=circle1_host_id,
            marker_start_id=circle1_start_id,
            marker_end_id=circle1_end_id)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassArcToBA
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle1_end_id, BPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle1_host_id, 2f0π)
        end
    elseif phase == PhaseCompassArcToBA
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            APoint, BPoint, BPoint, APoint)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawCircle2
            timer = 0f0
        end
    elseif phase == PhaseDrawCircle2
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, CircleDrawDuration, BPoint,
            APoint, CircleSweepTheta, Radius;
            brush=CircleBrush,
            color=Circle2Color,
            marker_host_id=circle2_host_id,
            marker_start_id=circle2_start_id,
            marker_end_id=circle2_end_id)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle2_end_id, APoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle2_host_id, 2f0π)
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            BPoint[1], BPoint[2], APoint[1], APoint[2])

        timer += dt
        if timer >= CompassRiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescend2
            timer = 0f0
        end
    elseif phase == PhasePenDescend2
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, APoint[1], APoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseExtendPointA
            timer = 0f0
        end
    elseif phase == PhaseExtendPointA
        EuclidAnimations.animate_extend_line(
            state_ptr, timer, LineDrawDuration,
            BPoint, APoint, ExtAPoint, LineMaxBrush, LineABColor;
            line_host_id=line_a_b_host_id,
            line_joint1_id=line_a_b_joint2_id,
            line_joint2_id=line_a_b_joint1_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndArcMovePenDuration,
            ExtAPoint, BPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndArcMovePenDuration
            phase = PhaseExtendPointB
            timer = 0f0
        end
    elseif phase == PhaseExtendPointB
        EuclidAnimations.animate_extend_line(
            state_ptr, timer, LineDrawDuration,
            ExtAPoint, BPoint, ExtBPoint, LineMaxBrush, LineABColor;
            line_host_id=line_a_b_host_id,
            line_joint1_id=line_a_b_joint1_id,
            line_joint2_id=line_a_b_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenRise2
            timer = 0f0
        end
    elseif phase == PhasePenRise2
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, ExtBPoint[1], ExtBPoint[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseCompassDescend2
            timer = 0f0
        end
    elseif phase == PhaseCompassDescend2
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, CompassDescendDuration, CompassTopZ,
            ExtAPoint[1], ExtAPoint[2], ExtBPoint[1], ExtBPoint[2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawCircle3
            timer = 0f0
        end
    elseif phase == PhaseDrawCircle3
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, CircleDrawDuration, ExtAPoint,
            ExtBPoint, CircleSweepTheta, ExtRadius;
            brush=CircleBrush,
            color=Circle3Color,
            marker_host_id=circle3_host_id,
            marker_start_id=circle3_start_id,
            marker_end_id=circle3_end_id)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassArcToBA2
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle3_end_id, ExtBPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle3_host_id, 2f0π)
        end
    elseif phase == PhaseCompassArcToBA2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            ExtAPoint, ExtBPoint, ExtBPoint, ExtAPoint)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawCircle4
            timer = 0f0
        end
    elseif phase == PhaseDrawCircle4
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, CircleDrawDuration, ExtBPoint,
            ExtAPoint, CircleSweepTheta, ExtRadius;
            brush=CircleBrush,
            color=Circle4Color,
            marker_host_id=circle4_host_id,
            marker_start_id=circle4_start_id,
            marker_end_id=circle4_end_id)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassRise2
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle4_end_id, ExtAPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle4_host_id, 2f0π)
        end
    elseif phase == PhaseCompassRise2
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            ExtBPoint[1], ExtBPoint[2], ExtAPoint[1], ExtAPoint[2])

        timer += dt
        if timer >= CompassRiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescend3
            timer = 0f0
        end
    elseif phase == PhasePenDescend3
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ,
            Intersection[1], Intersection[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLineCB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
        end
    elseif phase == PhaseDrawLineCB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            Intersection, BPoint;
            penbrush=LineMaxBrush,
            pencolor=LineCBColor,
            line_host_id=line_c_b_host_id,
            line_joint1_id=line_c_b_joint1_id,
            line_joint2_id=line_c_b_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseArcMovePen
            timer = 0f0
        end
    elseif phase == PhaseArcMovePen
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndArcMovePenDuration,
            BPoint, Intersection, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndArcMovePenDuration
            phase = PhaseDrawLineCA
            timer = 0f0
        end
    elseif phase == PhaseDrawLineCA
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            Intersection, APoint;
            penbrush=LineMaxBrush,
            pencolor=LineCAColor,
            line_host_id=line_c_a_host_id,
            line_joint1_id=line_c_a_joint1_id,
            line_joint2_id=line_c_a_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenRise3
            timer = 0f0
        end
    elseif phase == PhasePenRise3
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, APoint[1], APoint[2])

        timer += dt
        if timer >= EndLiftDuration
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

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
end

end
