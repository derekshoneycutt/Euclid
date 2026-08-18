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

const MetaLineABHostId = 1
const MetaLineABJoint1Id = 2
const MetaLineABJoint2Id = 3
const MetaCircleCGHHostId = 10
const MetaCircleCGHStartId = 11
const MetaCircleCGHEndId = 12
const MetaCircleGKLHostId = 20
const MetaCircleGKLStartId = 21
const MetaCircleGKLEndId = 22
const MetaLineCBHostId = 30
const MetaLineCBJoint1Id = 31
const MetaLineCBJoint2Id = 32
const MetaLineCAHostId = 40
const MetaLineCAJoint1Id = 41
const MetaLineCAJoint2Id = 42
const MetaLabelAId = 51
const MetaLabelBId = 52
const MetaLabelCId = 53
const MetaLabelDId = 54
const MetaLabelEId = 55
const MetaLabelFId = 56
const MetaLabelGId = 57
const MetaLabelHId = 58
const MetaLabelKId = 59
const MetaLabelLId = 60
const MetaPhase = 100
const MetaTimer = 101

const PhasePenDescend = 0f0
const PhaseDrawLine = 1f0
const PhasePenRise = 2f0
const PhaseHideAll = 100f0


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

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    #=circle_b_c_d_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleCGHHostId))
    circle_b_c_d_start_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleCGHStartId))
    circle_b_c_d_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleCGHEndId))

    circle_a_c_e_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleGKLHostId))
    circle_a_c_e_start_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleGKLStartId))
    circle_a_c_e_end_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleGKLEndId))

    line_a_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABHostId))
    line_a_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint2Id))

    line_c_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCBHostId))
    line_c_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCBJoint2Id))

    line_c_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAHostId))
    line_c_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAJoint2Id))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [label_a_id, label_b_id, label_c_id, label_d_id, label_e_id,
         line_a_b_host_id, line_c_b_host_id, line_c_a_host_id,
         circle_b_c_d_host_id, circle_a_c_e_host_id
        ])
        
    OdinJuliaBridge.lock_compass_joint1(state_ptr, APoint[1], APoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, EndPoint[1], EndPoint[2], CompassTopZ)

    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_b_joint2_id, APoint)
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
        state_ptr, circle_a_c_e_start_id, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle_a_c_e_end_id, APoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle_a_c_e_host_id, 0f0)=#

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    label_e_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))
    label_f_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelFId))
    label_g_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelGId))
    label_h_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    label_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    label_l_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [label_a_id, label_b_id, label_c_id, label_d_id, label_e_id, label_f_id, label_g_id,
         label_h_id, label_k_id, label_l_id,
        ])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

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

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(label_a.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(label_b.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(label_c.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, Float32(label_d.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelEId, Float32(label_e.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelFId, Float32(label_f.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelGId, Float32(label_g.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHId, Float32(label_h.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, Float32(label_k.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelLId, Float32(label_l.index))

    #=line_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, APoint, APoint, LineABColor, 0f0)
    circle_b_c_d = OdinJuliaBridge.create_new_circle(
        state_ptr, APoint, Radius, 7f0 * π / 4f0, 7f0 * π / 4f0, CircleCGHColor, 0f0)
    circle_a_c_e = OdinJuliaBridge.create_new_circle(
        state_ptr, EndPoint, Radius, 3f0 * π / 4f0, 3f0 * π / 4f0, CircleGKLColor, 0f0)
    line_c_b = OdinJuliaBridge.create_new_line(
        state_ptr, Intersection, Intersection, LineCBColor, 0f0)
    line_c_a = OdinJuliaBridge.create_new_line(
        state_ptr, Intersection, Intersection, LineCAColor, 0f0)


    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABHostId, Float32(line_a_b.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint1Id, Float32(line_a_b.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint2Id, Float32(line_a_b.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCBHostId, Float32(line_c_b.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCBJoint1Id, Float32(line_c_b.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCBJoint2Id, Float32(line_c_b.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAHostId, Float32(line_c_a.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAJoint1Id, Float32(line_c_a.joint1_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAJoint2Id, Float32(line_c_a.joint2_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleCGHHostId, Float32(circle_b_c_d.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleCGHStartId, Float32(circle_b_c_d.start_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleCGHEndId, Float32(circle_b_c_d.end_id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleGKLHostId, Float32(circle_a_c_e.host_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleGKLStartId, Float32(circle_a_c_e.start_id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleGKLEndId, Float32(circle_a_c_e.end_id))=#

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    label_e_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))

    #if line_a_b_host_id < 0 || line_c_b_host_id < 0 || line_c_a_host_id < 0 || circle_b_c_d_host_id < 0 || circle_a_c_e_host_id < 0
    #    return
    #end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

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
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
