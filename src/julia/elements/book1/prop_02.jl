module ElementsOneProposition02

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const APoint = [0.40f0, 0.40f0, 0f0]
const BPoint = [0.40f0, 0.40f0, 0f0]
const CPoint = [0.40f0, 0.40f0, 0f0]
const DPoint = [0.40f0, 0.40f0, 0f0]
const EPoint = [0.40f0, 0.40f0, 0f0]
const FPoint = [0.40f0, 0.40f0, 0f0]
const CircleSweepTheta = 2f0 * π
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const ALabelPoint = [0.39f0, 0.65f0, 0f0]
const BLabelPoint = [0.64f0, 0.40f0, 0f0]
const CLabelPoint = [0.73f0, 0.73f0, 0f0]
const DLabelPoint = [0.18f0, 0.82f0, 0f0]
const ELabelPoint = [0.83f0, 0.21f0, 0f0]
const FLabelPoint = [0.83f0, 0.21f0, 0f0]
const GLabelPoint = [0.83f0, 0.21f0, 0f0]
const HLabelPoint = [0.83f0, 0.21f0, 0f0]
const KLabelPoint = [0.83f0, 0.21f0, 0f0]
const LLabelPoint = [0.83f0, 0.21f0, 0f0]

const LineABColor = :gray60
const LineCBColor = :palevioletred1
const LineCAColor = :khaki3
const TempCircleColor = :plum1
const CircleCGHColor = :steelblue
const CircleGKLColor = :palevioletred1
const LabelColor = :plum1
const LineMaxBrush = 5f0
const TempCircleBrush = 1f0
const CircleBrush = 5f0

const DescendDuration = 1.8f0
const LineDrawDuration = 2.8f0
const EndLiftDuration = 1.8f0
const CompassDescendDuration = 1.8f0
const CircleDrawDuration = 4.4f0
const CompassArcMoveDuration = 1.6f0
const CompassArcMoveHeight = 0.25f0
const CompassRiseDuration = 2.8f0
const EndArcMovePenDuration = 2f0
const HidePauseDuration = 1.5f0

"""Complete immutable state for one Proposition II animation generation."""
struct AnimationState
    labels::NTuple{10,Int64}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhasePenDescend = 0f0
const PhaseDrawLine = 1f0
const PhasePenRise = 2f0
const PhaseHideAll = 100f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.labels, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Proposition II

To place at a given point (as an extremity) a straight line equal to a given straight line.

Let A be the given point, and BC the given straight line. Thus it is required to place at the point A (as an extremity) a straight line equal to the given straight line BC.

From the point A to the point B let the straight line AB be joined;
and on it let the equilateral triangle DAB be constructed.

Let the straight lines AE, BF be produced in a straight line with DA, DB with center B and distance BC let the circle CGH be described;
and again, with center D and distance DG let the circle GKL be described.

Then, since the point B is the center of the circle CGH, BC is equal to BG.
Again, since the point D is the center of the circle GKL, DL is equal to DG. And in these DA is equal to DB;
therefore the remainder AL is equal to the remainder BG.

But BC was also proved equal to BG; therefore each of the straight lines AL, BC is equal to BG.
And things which are equal to the same thing are also equal to one another; therefore AL is also equal to BC.
Therefore at the given point A the straight line AL is placed equal to the given straight line BC.

(Being) what it was required to do."""
    latex = raw"""\textbf{Euclid Elements - Book I - Proposition II}

\textit{To place at a given point (as an extremity) a straight line equal to a given straight line.}

Let A be the given point, and BC the given straight line. Thus it is required to place at the point A (as an extremity) a straight line equal to the given straight line BC.

From the point A to the point B let the straight line AB be joined;
and on it let the equilateral triangle DAB be constructed.

Let the straight lines AE, BF be produced in a straight line with DA, DB with center B and distance BC let the circle CGH be described;
and again, with center D and distance DG let the circle GKL be described.

Then, since the point B is the center of the circle CGH, BC is equal to BG.
Again, since the point D is the center of the circle GKL, DL is equal to DG. And in these DA is equal to DB;
therefore the remainder AL is equal to the remainder BG.

But BC was also proved equal to BG; therefore each of the straight lines AL, BC is equal to BG.
And things which are equal to the same thing are also equal to one another; therefore AL is also equal to BC.
Therefore at the given point A the straight line AL is placed equal to the given straight line BC.

(Being) what it was required to do."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native label handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    label_a_id, label_b_id, label_c_id, label_d_id, label_e_id,
        label_f_id, label_g_id, label_h_id, label_k_id, label_l_id = state.labels

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhasePenDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [label_a_id, label_b_id, label_c_id, label_d_id,
         label_e_id, label_f_id, label_g_id,
         label_h_id, label_k_id, label_l_id,
        ])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
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
    label_f = OdinJuliaBridge.create_new_label(
        state_ptr, 'F', FLabelPoint, LabelColor, 16f0)
    label_g = OdinJuliaBridge.create_new_label(
        state_ptr, 'G', GLabelPoint, LabelColor, 16f0)
    label_h = OdinJuliaBridge.create_new_label(
        state_ptr, 'H', HLabelPoint, LabelColor, 16f0)
    label_k = OdinJuliaBridge.create_new_label(
        state_ptr, 'K', KLabelPoint, LabelColor, 16f0)
    label_l = OdinJuliaBridge.create_new_label(
        state_ptr, 'L', LLabelPoint, LabelColor, 16f0)

    labels = (
        label_a.index, label_b.index, label_c.index, label_d.index, label_e.index,
        label_f.index, label_g.index, label_h.index, label_k.index, label_l.index)
    reset_cycle_state(
        state_ptr, AnimationState(labels, PhasePenDescend, 0f0))
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    label_a_id = state.labels[1]

    #if line_a_b_host_id < 0 || line_c_b_host_id < 0 || line_c_a_host_id < 0 || 
    #   circle_b_c_d_host_id < 0 || circle_a_c_e_host_id < 0
    #    return
    #end

    phase = state.phase
    timer = state.timer

    if phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, APoint[1], APoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhasePenRise
            timer = 0f0

            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
    elseif phase == PhasePenRise
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

    OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
end

end
