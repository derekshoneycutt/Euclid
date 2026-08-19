module ElementsOneProclusScalene

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const APoint = [0.40f0, 0.60f0, 0f0]
const BPoint = [0.60f0, 0.40f0, 0f0]
const Radius = norm(BPoint - APoint)
const CPointTheta = π / 3f0
const CPoint = APoint + Radius * [cos(CPointTheta), sin(CPointTheta), 0f0]
const DPoint = APoint + (Radius * 0.7f0) * [cos(CPointTheta), sin(CPointTheta), 0f0]
const CircleSweepTheta = 2f0 * π
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const ALabelPoint = [0.39f0, 0.65f0, 0f0]
const BLabelPoint = [0.64f0, 0.40f0, 0f0]
const CLabelPoint = APoint + (Radius + 0.07f0) *
    [cos(CPointTheta), sin(CPointTheta), 0f0]
const DLabelPoint = APoint + (Radius * 0.7f0) *
    [cos(CPointTheta), sin(CPointTheta), 0f0] + [-0.01f0, 0.04f0, 0f0]

const LineABColor = :grey60
const LineDBColor = :khaki3
const LineCAColor = :palevioletred1
const Circle1Color = :steelblue
const Circle2Color = :palevioletred1
const LabelColor = :plum1
const LineMaxBrush = 5f0
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
const MetaCircle1HostId = 10
const MetaCircle1StartId = 11
const MetaCircle1EndId = 12
const MetaCircle2HostId = 20
const MetaCircle2StartId = 21
const MetaCircle2EndId = 22
const MetaLineDBHostId = 30
const MetaLineDBJoint1Id = 31
const MetaLineDBJoint2Id = 32
const MetaLineCAHostId = 40
const MetaLineCAJoint1Id = 41
const MetaLineCAJoint2Id = 42
const MetaLabelAId = 51
const MetaLabelBId = 52
const MetaLabelCId = 53
const MetaLabelDId = 54
const MetaPhase = 100
const MetaTimer = 101

const PhasePenDescend = 0f0
const PhaseDrawLine = 1f0
const PhasePenRise = 2f0
const PhaseCompassDescend = 10f0
const PhaseDrawCircle1 = 21f0
const PhaseCompassArcToBA = 30f0
const PhaseDrawCircle2 = 31f0
const PhaseCompassRise = 40f0
const PhasePenDescend2 = 41f0
const PhaseDrawLineDB = 51f0
const PhaseArcMovePen = 60f0
const PhaseDrawLineCA = 61f0
const PhasePenRise2 = 90f0
const PhaseHideAll = 100f0


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Proclus - Scalene Triangle

On a given finite straight line to construct an scalene triangle.

This follows Euclid's Elements Book I, Proposition I, with modifications.

Suppose AC to be a radius of one of the two circles, and D a point on AC lying in that portion of the circle with center A which is outside the circle with center B, Then, joining BD as in the figure, we have a triangle which obviously has all its sides unequal, that is, a scalene triangle."""
    latex = raw"""\textbf{Euclid Elements - Book I - Proclus - Scalene Triangle}

On a given finite straight line to construct an scalene triangle.

\textit{This follows Euclid's Elements Book I, Proposition I, with modifications.}

Suppose $AC$ \euclidline[color=palevioletred1,length=3,thickness=4] to be a radius of one of the
two circles \euclidcircle[color=steelblue,size=1,thickness=2], and
$D$ \euclidpoint[color=palevioletred1,size=0.5] a point on $AC$ \euclidline[color=palevioletred1,length=3,thickness=4]
lying in that portion of the circle with center $A$ \euclidpoint[color=grey60,size=0.5] which is outside the
circle \euclidcircle[color=palevioletred1,size=1,thickness=2] with
center $B$ \euclidpoint[color=grey,size=0.5]. Then, joining
$BD$ \euclidline[color=khaki3,length=3,thickness=4] as in the figure, we have a triangle which obviously has all its sides unequal, that is,
a scalene triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=grey60,edge3_color=khaki3]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    circle_b_c_d_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle1HostId))
    circle_b_c_d_start_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle1StartId))
    circle_b_c_d_end_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle1EndId))

    circle_a_c_e_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle2HostId))
    circle_a_c_e_start_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle2StartId))
    circle_a_c_e_end_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle2EndId))

    line_a_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABHostId))
    line_a_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABJoint2Id))

    line_d_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineDBHostId))
    line_d_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineDBJoint2Id))

    line_c_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineCAHostId))
    line_c_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineCAJoint2Id))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [label_a_id, label_b_id, label_c_id, label_d_id,
         line_a_b_host_id, line_d_b_host_id, line_c_a_host_id,
         circle_b_c_d_host_id, circle_a_c_e_host_id
        ])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
        
    OdinJuliaBridge.lock_compass_joint1(state_ptr, APoint[1], APoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, BPoint[1], BPoint[2], CompassTopZ)

    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_b_joint2_id, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_d_b_joint2_id, DPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_c_a_joint2_id, CPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle_b_c_d_start_id, BPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle_b_c_d_end_id, BPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle_b_c_d_host_id, 0f0)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle_a_c_e_start_id, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle_a_c_e_end_id, APoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle_a_c_e_host_id, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, APoint, APoint, LineABColor, 0f0)
    circle_b_c_d = OdinJuliaBridge.create_new_circle(
        state_ptr, APoint, Radius, 7f0 * π / 4f0, 7f0 * π / 4f0, Circle1Color, 0f0)
    circle_a_c_e = OdinJuliaBridge.create_new_circle(
        state_ptr, BPoint, Radius, 3f0 * π / 4f0, 3f0 * π / 4f0, Circle2Color, 0f0)
    line_c_a = OdinJuliaBridge.create_new_line(
        state_ptr, CPoint, CPoint, LineCAColor, 0f0)
    line_d_b = OdinJuliaBridge.create_new_line(
        state_ptr, DPoint, DPoint, LineDBColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    label_d = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', DLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, label_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, label_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, label_c.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, label_d.index)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABHostId, line_a_b.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint1Id, line_a_b.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint2Id, line_a_b.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineDBHostId, line_d_b.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineDBJoint1Id, line_d_b.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineDBJoint2Id, line_d_b.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAHostId, line_c_a.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAJoint1Id, line_c_a.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAJoint2Id, line_c_a.joint2_id)

    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaCircle1HostId, circle_b_c_d.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaCircle1StartId, circle_b_c_d.start_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaCircle1EndId, circle_b_c_d.end_id)

    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaCircle2HostId, circle_a_c_e.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaCircle2StartId, circle_a_c_e.start_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaCircle2EndId, circle_a_c_e.end_id)

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line_a_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABHostId))
    line_a_b_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABJoint1Id))
    line_a_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineABJoint2Id))

    line_d_b_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineDBHostId))
    line_d_b_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineDBJoint1Id))
    line_d_b_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineDBJoint2Id))

    line_c_a_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineCAHostId))
    line_c_a_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineCAJoint1Id))
    line_c_a_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineCAJoint2Id))

    circle_b_c_d_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle1HostId))
    circle_b_c_d_start_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle1StartId))
    circle_b_c_d_end_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle1EndId))

    circle_a_c_e_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle2HostId))
    circle_a_c_e_start_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle2StartId))
    circle_a_c_e_end_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircle2EndId))

    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))

    if line_a_b_host_id < 0 || line_d_b_host_id < 0 || line_c_a_host_id < 0 ||
       circle_b_c_d_host_id < 0 || circle_a_c_e_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, APoint, BPoint,
            LineMaxBrush, LineABColor, line_a_b_host_id,
            line_a_b_joint1_id, line_a_b_joint2_id)

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
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, CircleDrawDuration, APoint, BPoint,
            CircleSweepTheta, Radius, CircleBrush, Circle1Color,
            circle_b_c_d_host_id, circle_b_c_d_start_id, circle_b_c_d_end_id)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassArcToBA
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle_b_c_d_end_id, BPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle_b_c_d_host_id, 2f0π)
        end
    elseif phase == PhaseCompassArcToBA
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            APoint, BPoint, BPoint, APoint,
            CompassArcMoveHeight, 1, :none)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawCircle2
            timer = 0f0
        end
    elseif phase == PhaseDrawCircle2
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, CircleDrawDuration, BPoint, APoint,
            CircleSweepTheta, Radius, CircleBrush, Circle2Color,
            circle_a_c_e_host_id, circle_a_c_e_start_id, circle_a_c_e_end_id)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle_a_c_e_end_id, APoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle_a_c_e_host_id, 2f0π)
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
            state_ptr, timer, DescendDuration, PenTopZ, CPoint[1], CPoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLineCA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
        end
    elseif phase == PhaseDrawLineCA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, CPoint, APoint,
            LineMaxBrush, LineCAColor, line_c_a_host_id,
            line_c_a_joint1_id, line_c_a_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseArcMovePen
            timer = 0f0
        end
    elseif phase == PhaseArcMovePen
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndArcMovePenDuration,
            APoint, DPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndArcMovePenDuration
            phase = PhaseDrawLineDB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_d_id)
        end
    elseif phase == PhaseDrawLineDB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, DPoint, BPoint,
            LineMaxBrush, LineDBColor, line_d_b_host_id,
            line_d_b_joint1_id, line_d_b_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenRise2
            timer = 0f0
        end
    elseif phase == PhasePenRise2
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, BPoint[1], BPoint[2])

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
