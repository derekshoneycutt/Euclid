module ElementsOneProclusScalene

using ..OdinJuliaBridge
using ..EuclidAnimations

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
const CLabelPoint = APoint + (Radius + 0.07f0) * [cos(CPointTheta), sin(CPointTheta), 0f0]
const DLabelPoint = APoint + (Radius * 0.7f0) * [cos(CPointTheta), sin(CPointTheta), 0f0] + [-0.01f0, 0.04f0, 0f0]

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
    """Euclid Elements - Book I - Proclus - Scalene Triangle

On a given finite straight line to construct an scalene triangle.

This follows Euclid's Elements Book I, Proposition I, with modifications.

Suppose AC to be a radius of one of the two circles, and D a point on AC lying in that portion of the circle with center A which is outside the circle with center B, Then, joining BD as in the figure, we have a triangle which obviously has all its sides unequal, that is, a scalene triangle."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    circleBCDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1HostId))
    circleBCDStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1StartId))
    circleBCDEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1EndId))

    circleACEHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2HostId))
    circleACEStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2StartId))
    circleACEEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2EndId))

    lineABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABHostId))
    lineABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint2Id))

    lineDBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineDBHostId))
    lineDBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineDBJoint2Id))

    lineCAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAHostId))
    lineCAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAJoint2Id))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [labelAId, labelBId, labelCId, labelDId,
         lineABHostId, lineDBHostId, lineCAHostId,
         circleBCDHostId, circleACEHostId
        ])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
        
    OdinJuliaBridge.lock_compass_joint1(state_ptr, APoint[1], APoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, BPoint[1], BPoint[2], CompassTopZ)

    OdinJuliaBridge.set_point_position(
        state_ptr, lineABJoint2Id, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, lineDBJoint2Id, DPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, lineCAJoint2Id, CPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circleBCDStartId, BPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circleBCDEndId, BPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circleBCDHostId, 0f0)
    OdinJuliaBridge.set_point_position(
        state_ptr, circleACEStartId, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circleACEEndId, APoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circleACEHostId, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    lineAB = OdinJuliaBridge.create_new_line(
        state_ptr, APoint, APoint, LineABColor, 0f0)
    circleBCD = OdinJuliaBridge.create_new_circle(
        state_ptr, APoint, Radius, 7f0 * π / 4f0, 7f0 * π / 4f0, Circle1Color, 0f0)
    circleACE = OdinJuliaBridge.create_new_circle(
        state_ptr, BPoint, Radius, 3f0 * π / 4f0, 3f0 * π / 4f0, Circle2Color, 0f0)
    lineCA = OdinJuliaBridge.create_new_line(
        state_ptr, CPoint, CPoint, LineCAColor, 0f0)
    lineDB = OdinJuliaBridge.create_new_line(
        state_ptr, DPoint, DPoint, LineDBColor, 0f0)

    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    labelD = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', DLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, Float32(labelD.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABHostId, Float32(lineAB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint1Id, Float32(lineAB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint2Id, Float32(lineAB.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineDBHostId, Float32(lineDB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineDBJoint1Id, Float32(lineDB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineDBJoint2Id, Float32(lineDB.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAHostId, Float32(lineCA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAJoint1Id, Float32(lineCA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAJoint2Id, Float32(lineCA.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle1HostId, Float32(circleBCD.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle1StartId, Float32(circleBCD.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle1EndId, Float32(circleBCD.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle2HostId, Float32(circleACE.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle2StartId, Float32(circleACE.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle2EndId, Float32(circleACE.endId))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABHostId))
    lineABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint1Id))
    lineABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint2Id))

    lineDBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineDBHostId))
    lineDBJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineDBJoint1Id))
    lineDBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineDBJoint2Id))

    lineCAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAHostId))
    lineCAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAJoint1Id))
    lineCAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAJoint2Id))

    circleBCDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1HostId))
    circleBCDStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1StartId))
    circleBCDEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1EndId))

    circleACEHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2HostId))
    circleACEStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2StartId))
    circleACEEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2EndId))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))

    if lineABHostId < 0 || lineDBHostId < 0 || lineCAHostId < 0 || circleBCDHostId < 0 || circleACEHostId < 0
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

            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, APoint, BPoint,
            LineMaxBrush, LineABColor, lineABHostId, lineABJoint1Id, lineABJoint2Id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenRise
            timer = 0f0

            OdinJuliaBridge.show_point(state_ptr, labelBId)
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
            circleBCDHostId, circleBCDStartId, circleBCDEndId)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassArcToBA
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circleBCDEndId, BPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circleBCDHostId, 2f0π)
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
            circleACEHostId, circleACEStartId, circleACEEndId)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circleACEEndId, APoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circleACEHostId, 2f0π)
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
            OdinJuliaBridge.show_point(state_ptr, labelCId)
        end
    elseif phase == PhaseDrawLineCA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, CPoint, APoint,
            LineMaxBrush, LineCAColor, lineCAHostId, lineCAJoint1Id, lineCAJoint2Id)

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
            OdinJuliaBridge.show_point(state_ptr, labelDId)
        end
    elseif phase == PhaseDrawLineDB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, DPoint, BPoint,
            LineMaxBrush, LineDBColor, lineDBHostId, lineDBJoint1Id, lineDBJoint2Id)

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
