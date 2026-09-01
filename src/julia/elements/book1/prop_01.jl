module ElementsOneProposition01

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint = [0.40f0, 0.60f0, 0f0]
const EndPoint = [0.60f0, 0.40f0, 0f0]
const Radius = norm(EndPoint - StartPoint)
const Intersection = StartPoint + Radius * [cos(π / 12f0), sin(π / 12f0), 0f0]
const CircleSweepTheta = 2f0 * π
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const ALabelPoint = [0.39f0, 0.65f0, 0f0]
const BLabelPoint = [0.64f0, 0.40f0, 0f0]
const CLabelPoint = [0.73f0, 0.73f0, 0f0]
const DLabelPoint = [0.18f0, 0.82f0, 0f0]
const ELabelPoint = [0.83f0, 0.21f0, 0f0]

const LineABColor = :grey60
const LineCBColor = :palevioletred1
const LineCAColor = :khaki3
const CircleBCDColor = :steelblue
const CircleACEColor = :palevioletred1
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

"""Complete immutable state for one Proposition I animation generation."""
struct AnimationState
    lines::NTuple{3,LineIds}
    circles::NTuple{2,CircleIds}
    labels::NTuple{5,Int64}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhasePenDescend = 0f0
const PhaseDrawLine = 1f0
const PhasePenRise = 2f0
const PhaseCompassDescend = 10f0
const PhaseDrawCircleBCD = 21f0
const PhaseCompassArcToBA = 30f0
const PhaseDrawCircleACE = 31f0
const PhaseCompassRise = 40f0
const PhasePenDescend2 = 41f0
const PhaseDrawLineCB = 51f0
const PhaseArcMovePen = 60f0
const PhaseDrawLineCA = 61f0
const PhasePenRise2 = 90f0
const PhaseHideAll = 100f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, state.circles, state.labels, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Proposition I

On a given finite straight line to construct an equilateral triangle.

Let AB be the given finite straight line.

Thus it is required to construct an equilateral triangle on the straing line AB.
With center A and distance AB let the circle BCD be described;
again, with center B and distance BA let the circle ACE be described;
and from the point C, in which the circles cut one another, to the points A, B let the straight lines CA, CB be joined.

Now, since the point A is the center of the circle CDB, AC is equal to AB.
Again, since the point B is the center of the circle CAE, BC is equal to BA.
But CA was also proved equal to AB; therefore each of the straight lines CA, CB is equal to AB.
And things which are equal to the same thing are also equal to one another; therefore CA is also equal to CB.
Therefore the three straight lines CA, AB, BC are equal to one another.
Therefore the triangle ABC is equilateral; and it has been constructed on the given finite straight line AB.

Being what it was required to do."""
    latex = raw"""\textbf{Euclid Elements - Book I - Proposition I}

\textit{On a given finite straight line to construct an equilateral triangle.}

Let $AB$ \euclidline[color=grey60,length=3,thickness=4] be the given finite straight line.

Thus it is required to construct an equilateral triangle on the straing line $AB$.\\
With center $A$ and distance $AB$ let the circle $BCD$ \euclidcircle[color=steelblue,size=1,thickness=2] be described;\\
again, with center $B$ and distance $BA$ let the circle $ACE$ \euclidcircle[color=palevioletred1,size=1,thickness=2] be described;\\
and from the point $C$, in which the circles cut one another, to the points $A$, $B$ let the straight lines $CA$ \euclidline[color=khaki3,length=3,thickness=4], $CB$ \euclidline[color=palevioletred1,length=3,thickness=4] be joined.

Now, since the point $A$ is the center of the circle $CDB$ \euclidcircle[color=steelblue,size=1,thickness=2], $AC$ \euclidline[color=khaki3,length=3,thickness=4] is equal to $AB$ \euclidline[color=grey60,length=3,thickness=4].\\
Again, since the point B is the center of the circle $CAE$ \euclidcircle[color=palevioletred1,size=1,thickness=2], $BC$ \euclidline[color=palevioletred1,length=3,thickness=4] is equal to $BA$ \euclidline[color=grey60,length=3,thickness=4].\\
But $CA$ \euclidline[color=khaki3,length=3,thickness=4] was also proved equal to $AB$ \euclidline[color=grey60,length=3,thickness=4]; therefore each of the straight lines $CA$ \euclidline[color=khaki3,length=3,thickness=4], $CB$ \euclidline[color=palevioletred1,length=3,thickness=4] is equal to $AB$ \euclidline[color=grey60,length=3,thickness=4].\\
And things which are equal to the same thing are also equal to one another; therefore $CA$ \euclidline[color=khaki3,length=3,thickness=4] is also equal to $CB$ \euclidline[color=palevioletred1,length=3,thickness=4].\\
Therefore the three straight lines $CA$ \euclidline[color=khaki3,length=3,thickness=4], $AB$ \euclidline[color=grey60,length=3,thickness=4], $BC$ \euclidline[color=palevioletred1,length=3,thickness=4] are equal to one another.\\
Therefore the triangle $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=grey60,edge3_color=palevioletred1] is equilateral; and it has been constructed on the given finite straight line $AB$ \euclidline[color=grey60,length=3,thickness=4].

Being what it was required to do."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_a_b_host_id = state.lines[1].host
    line_a_b_joint2_id = state.lines[1].joint2
    line_c_b_host_id = state.lines[2].host
    line_c_b_joint2_id = state.lines[2].joint2
    line_c_a_host_id = state.lines[3].host
    line_c_a_joint2_id = state.lines[3].joint2
    circle_b_c_d_host_id = state.circles[1].host
    circle_b_c_d_start_id = state.circles[1].start
    circle_b_c_d_end_id = state.circles[1].finish
    circle_a_c_e_host_id = state.circles[2].host
    circle_a_c_e_start_id = state.circles[2].start
    circle_a_c_e_end_id = state.circles[2].finish
    label_a_id, label_b_id, label_c_id, label_d_id, label_e_id = state.labels

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhasePenDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [label_a_id, label_b_id, label_c_id, label_d_id, label_e_id,
         line_a_b_host_id, line_c_b_host_id, line_c_a_host_id,
         circle_b_c_d_host_id, circle_a_c_e_host_id])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
        
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, StartPoint[1], StartPoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, EndPoint[1], EndPoint[2], CompassTopZ)

    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_b_joint2_id, StartPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_c_b_joint2_id, Intersection)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_c_a_joint2_id, Intersection)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle_b_c_d_start_id, EndPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle_b_c_d_end_id, EndPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle_b_c_d_host_id, 0f0)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle_a_c_e_start_id, StartPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle_a_c_e_end_id, StartPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle_a_c_e_host_id, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint, StartPoint, LineABColor, 0f0)
    circle_b_c_d = OdinJuliaBridge.create_new_circle(
        state_ptr, StartPoint, Radius, 7f0 * π / 4f0, 7f0 * π / 4f0, CircleBCDColor, 0f0)
    circle_a_c_e = OdinJuliaBridge.create_new_circle(
        state_ptr, EndPoint, Radius, 3f0 * π / 4f0, 3f0 * π / 4f0, CircleACEColor, 0f0)
    line_c_b = OdinJuliaBridge.create_new_line(
        state_ptr, Intersection, Intersection, LineCBColor, 0f0)
    line_c_a = OdinJuliaBridge.create_new_line(
        state_ptr, Intersection, Intersection, LineCAColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    label_d = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', DLabelPoint, LabelColor, 16f0)
    label_e = OdinJuliaBridge.create_new_label(
        state_ptr, 'E', ELabelPoint, LabelColor, 16f0)

    lines = (
        LineIds(line_a_b.host_id, line_a_b.joint1_id, line_a_b.joint2_id),
        LineIds(line_c_b.host_id, line_c_b.joint1_id, line_c_b.joint2_id),
        LineIds(line_c_a.host_id, line_c_a.joint1_id, line_c_a.joint2_id))
    circles = (
        CircleIds(circle_b_c_d.host_id, circle_b_c_d.start_id, circle_b_c_d.end_id),
        CircleIds(circle_a_c_e.host_id, circle_a_c_e.start_id, circle_a_c_e.end_id))
    labels = (label_a.index, label_b.index, label_c.index, label_d.index, label_e.index)
    state = AnimationState(lines, circles, labels, PhasePenDescend, 0f0)
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
    line_a_b_host_id = state.lines[1].host
    line_a_b_joint1_id = state.lines[1].joint1
    line_a_b_joint2_id = state.lines[1].joint2
    line_c_b_host_id = state.lines[2].host
    line_c_b_joint1_id = state.lines[2].joint1
    line_c_b_joint2_id = state.lines[2].joint2
    line_c_a_host_id = state.lines[3].host
    line_c_a_joint1_id = state.lines[3].joint1
    line_c_a_joint2_id = state.lines[3].joint2
    circle_b_c_d_host_id = state.circles[1].host
    circle_b_c_d_start_id = state.circles[1].start
    circle_b_c_d_end_id = state.circles[1].finish
    circle_a_c_e_host_id = state.circles[2].host
    circle_a_c_e_start_id = state.circles[2].start
    circle_a_c_e_end_id = state.circles[2].finish
    label_a_id, label_b_id, label_c_id, label_d_id, label_e_id = state.labels

    if line_a_b_host_id < 0 || line_c_b_host_id < 0 || line_c_a_host_id < 0 ||
       circle_b_c_d_host_id < 0 || circle_a_c_e_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, StartPoint[1], StartPoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine
            timer = 0f0

            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            StartPoint, EndPoint;
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
            state_ptr, timer, EndLiftDuration, PenTopZ, EndPoint[1], EndPoint[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseCompassDescend
            timer = 0f0
        end
    elseif phase == PhaseCompassDescend
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, CompassDescendDuration, CompassTopZ,
            StartPoint[1], StartPoint[2], EndPoint[1], EndPoint[2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawCircleBCD
            timer = 0f0
        end
    elseif phase == PhaseDrawCircleBCD
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, CircleDrawDuration, StartPoint,
            EndPoint, CircleSweepTheta, Radius;
            brush=CircleBrush,
            color=CircleBCDColor,
            marker_host_id=circle_b_c_d_host_id,
            marker_start_id=circle_b_c_d_start_id,
            marker_end_id=circle_b_c_d_end_id)

        if (timer / CircleDrawDuration) >= 0.15
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
        end
        if (timer / CircleDrawDuration) >= 0.5
            OdinJuliaBridge.show_point(state_ptr, label_d_id)
        end

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassArcToBA
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle_b_c_d_end_id, EndPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle_b_c_d_host_id, 2f0π)
        end
    elseif phase == PhaseCompassArcToBA
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            StartPoint, EndPoint, EndPoint, StartPoint)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawCircleACE
            timer = 0f0
        end
    elseif phase == PhaseDrawCircleACE
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, CircleDrawDuration, EndPoint,
            StartPoint, CircleSweepTheta, Radius;
            brush=CircleBrush,
            color=CircleACEColor,
            marker_host_id=circle_a_c_e_host_id,
            marker_start_id=circle_a_c_e_start_id,
            marker_end_id=circle_a_c_e_end_id)

        if (timer / CircleDrawDuration) >= 0.5
            OdinJuliaBridge.show_point(state_ptr, label_e_id)
        end

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle_a_c_e_end_id, StartPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle_a_c_e_host_id, 2f0π)
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            EndPoint[1], EndPoint[2], StartPoint[1], StartPoint[2])

        timer += dt
        if timer >= CompassRiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescend2
            timer = 0f0
        end
    elseif phase == PhasePenDescend2
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ,
            Intersection[1], Intersection[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLineCB
            timer = 0f0
        end
    elseif phase == PhaseDrawLineCB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            Intersection, EndPoint;
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
            EndPoint, Intersection, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndArcMovePenDuration
            phase = PhaseDrawLineCA
            timer = 0f0
        end
    elseif phase == PhaseDrawLineCA
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            Intersection, StartPoint;
            penbrush=LineMaxBrush,
            pencolor=LineCAColor,
            line_host_id=line_c_a_host_id,
            line_joint1_id=line_c_a_joint1_id,
            line_joint2_id=line_c_a_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenRise2
            timer = 0f0
            #OdinJuliaBridge.hide_point_batch(state_ptr,
            #    [label_d_id, label_e_id, circle_b_c_d_host_id, circle_a_c_e_host_id])
        end
    elseif phase == PhasePenRise2
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, StartPoint[1], StartPoint[2])

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

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

end
