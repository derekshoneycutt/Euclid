module ElementsOneProposition01

using ..OdinJuliaBridge
using ..EuclidAnimations

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
const CompassArcMoveHeight = 0.25f0
const CompassRiseDuration = 2.8f0
const EndArcMovePenDuration = 2f0
const HidePauseDuration = 1.5f0

const MetaLineABHostId = 1
const MetaLineABJoint1Id = 2
const MetaLineABJoint2Id = 3
const MetaCircleBCDHostId = 10
const MetaCircleBCDStartId = 11
const MetaCircleBCDEndId = 12
const MetaCircleACEHostId = 20
const MetaCircleACEStartId = 21
const MetaCircleACEEndId = 22
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
const MetaPhase = 100
const MetaTimer = 101

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


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Proposition I

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
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    circleBCDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleBCDHostId))
    circleBCDStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleBCDStartId))
    circleBCDEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleBCDEndId))

    circleACEHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleACEHostId))
    circleACEStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleACEStartId))
    circleACEEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleACEEndId))

    lineABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABHostId))
    lineABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint2Id))

    lineCBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCBHostId))
    lineCBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCBJoint2Id))

    lineCAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAHostId))
    lineCAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAJoint2Id))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [labelAId, labelBId, labelCId, labelDId, labelEId,
         lineABHostId, lineCBHostId, lineCAHostId,
         circleBCDHostId, circleACEHostId
        ])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
        
    OdinJuliaBridge.lock_compass_joint1(state_ptr, StartPoint[1], StartPoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, EndPoint[1], EndPoint[2], CompassTopZ)

    OdinJuliaBridge.set_point_position(
        state_ptr, lineABJoint2Id, StartPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, lineCBJoint2Id, Intersection)
    OdinJuliaBridge.set_point_position(
        state_ptr, lineCAJoint2Id, Intersection)
    OdinJuliaBridge.set_point_position(
        state_ptr, circleBCDStartId, EndPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circleBCDEndId, EndPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circleBCDHostId, 0f0)
    OdinJuliaBridge.set_point_position(
        state_ptr, circleACEStartId, StartPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circleACEEndId, StartPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circleACEHostId, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    lineAB = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint, StartPoint, LineABColor, 0f0)
    circleBCD = OdinJuliaBridge.create_new_circle(
        state_ptr, StartPoint, Radius, 7f0 * π / 4f0, 7f0 * π / 4f0, CircleBCDColor, 0f0)
    circleACE = OdinJuliaBridge.create_new_circle(
        state_ptr, EndPoint, Radius, 3f0 * π / 4f0, 3f0 * π / 4f0, CircleACEColor, 0f0)
    lineCB = OdinJuliaBridge.create_new_line(
        state_ptr, Intersection, Intersection, LineCBColor, 0f0)
    lineCA = OdinJuliaBridge.create_new_line(
        state_ptr, Intersection, Intersection, LineCAColor, 0f0)

    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    labelD = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', DLabelPoint, LabelColor, 16f0)
    labelE = OdinJuliaBridge.create_new_label(
        state_ptr, 'E', ELabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, Float32(labelD.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelEId, Float32(labelE.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABHostId, Float32(lineAB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint1Id, Float32(lineAB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint2Id, Float32(lineAB.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCBHostId, Float32(lineCB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCBJoint1Id, Float32(lineCB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCBJoint2Id, Float32(lineCB.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAHostId, Float32(lineCA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAJoint1Id, Float32(lineCA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAJoint2Id, Float32(lineCA.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleBCDHostId, Float32(circleBCD.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleBCDStartId, Float32(circleBCD.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleBCDEndId, Float32(circleBCD.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleACEHostId, Float32(circleACE.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleACEStartId, Float32(circleACE.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleACEEndId, Float32(circleACE.endId))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABHostId))
    lineABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint1Id))
    lineABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint2Id))

    lineCBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCBHostId))
    lineCBJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCBJoint1Id))
    lineCBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCBJoint2Id))

    lineCAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAHostId))
    lineCAJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAJoint1Id))
    lineCAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAJoint2Id))

    circleBCDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleBCDHostId))
    circleBCDStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleBCDStartId))
    circleBCDEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleBCDEndId))

    circleACEHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleACEHostId))
    circleACEStartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleACEStartId))
    circleACEEndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleACEEndId))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))

    if lineABHostId < 0 || lineCBHostId < 0 || lineCAHostId < 0 || circleBCDHostId < 0 || circleACEHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, StartPoint[1], StartPoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine
            timer = 0f0

            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, StartPoint, EndPoint,
            LineMaxBrush, LineABColor, lineABHostId, lineABJoint1Id, lineABJoint2Id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenRise
            timer = 0f0

            OdinJuliaBridge.show_point(state_ptr, labelBId)
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
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, CircleDrawDuration, StartPoint, EndPoint,
            CircleSweepTheta, Radius, CircleBrush, CircleBCDColor,
            circleBCDHostId, circleBCDStartId, circleBCDEndId)

        if (timer / CircleDrawDuration) >= 0.15
            OdinJuliaBridge.show_point(state_ptr, labelCId)
        end
        if (timer / CircleDrawDuration) >= 0.5
            OdinJuliaBridge.show_point(state_ptr, labelDId)
        end

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassArcToBA
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circleBCDEndId, EndPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circleBCDHostId, 2f0π)
        end
    elseif phase == PhaseCompassArcToBA
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            StartPoint, EndPoint, EndPoint, StartPoint,
            CompassArcMoveHeight, 1, :none)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawCircleACE
            timer = 0f0
        end
    elseif phase == PhaseDrawCircleACE
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, CircleDrawDuration, EndPoint, StartPoint,
            CircleSweepTheta, Radius, CircleBrush, CircleACEColor,
            circleACEHostId, circleACEStartId, circleACEEndId)

        if (timer / CircleDrawDuration) >= 0.5
            OdinJuliaBridge.show_point(state_ptr, labelEId)
        end

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circleACEEndId, StartPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circleACEHostId, 2f0π)
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
            state_ptr, timer, DescendDuration, PenTopZ, Intersection[1], Intersection[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLineCB
            timer = 0f0
        end
    elseif phase == PhaseDrawLineCB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, Intersection, EndPoint,
            LineMaxBrush, LineCBColor, lineCBHostId, lineCBJoint1Id, lineCBJoint2Id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, Intersection, StartPoint,
            LineMaxBrush, LineCAColor, lineCAHostId, lineCAJoint1Id, lineCAJoint2Id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenRise2
            timer = 0f0
            #OdinJuliaBridge.hide_point_batch(state_ptr,
            #    [labelDId, labelEId, circleBCDHostId, circleACEHostId])
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
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
