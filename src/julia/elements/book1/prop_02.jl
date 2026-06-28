module ElementsOneProposition02

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const APoint = [0.40f0, 0.40f0, 0f0]
const BPoint = [0.40f0, 0.40f0, 0f0]
const CPoint = [0.40f0, 0.40f0, 0f0]
const DPoint = [0.40f0, 0.40f0, 0f0]
const EPoint = [0.40f0, 0.40f0, 0f0]
const FPoint = [0.40f0, 0.40f0, 0f0]
const GPoint = [0.40f0, 0.40f0, 0f0]
const LPoint = [0.40f0, 0.40f0, 0f0]
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
    """Euclid Elements - Book I - Proposition II

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
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    #=circleBCDHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircleBCDHostId))
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

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [labelAId, labelBId, labelCId, labelDId, labelEId,
         lineABHostId, lineCBHostId, lineCAHostId,
         circleBCDHostId, circleACEHostId
        ])
        
    OdinJuliaBridge.lock_compass_joint1(state_ptr, APoint[1], APoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, EndPoint[1], EndPoint[2], CompassTopZ)

    OdinJuliaBridge.set_point_position(
        state_ptr, lineABJoint2Id, APoint)
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
        state_ptr, circleACEStartId, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circleACEEndId, APoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circleACEHostId, 0f0)=#

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))
    labelFId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelFId))
    labelGId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelGId))
    labelHId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelHId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))
    labelLId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelLId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [labelAId, labelBId, labelCId, labelDId, labelEId, labelFId, labelGId,
         labelHId, labelKId, labelLId,
        ])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
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
    labelF = OdinJuliaBridge.create_new_label(
        state_ptr, 'F', FLabelPoint, LabelColor, 16f0)
    labelG = OdinJuliaBridge.create_new_label(
        state_ptr, 'G', GLabelPoint, LabelColor, 16f0)
    labelH = OdinJuliaBridge.create_new_label(
        state_ptr, 'H', HLabelPoint, LabelColor, 16f0)
    labelK = OdinJuliaBridge.create_new_label(
        state_ptr, 'K', KLabelPoint, LabelColor, 16f0)
    labelL = OdinJuliaBridge.create_new_label(
        state_ptr, 'L', LLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, Float32(labelD.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelEId, Float32(labelE.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelFId, Float32(labelF.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelGId, Float32(labelG.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelHId, Float32(labelH.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, Float32(labelK.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelLId, Float32(labelL.index))

    #=lineAB = OdinJuliaBridge.create_new_line(
        state_ptr, APoint, APoint, LineABColor, 0f0)
    circleBCD = OdinJuliaBridge.create_new_circle(
        state_ptr, APoint, Radius, 7f0 * π / 4f0, 7f0 * π / 4f0, CircleBCDColor, 0f0)
    circleACE = OdinJuliaBridge.create_new_circle(
        state_ptr, EndPoint, Radius, 3f0 * π / 4f0, 3f0 * π / 4f0, CircleACEColor, 0f0)
    lineCB = OdinJuliaBridge.create_new_line(
        state_ptr, Intersection, Intersection, LineCBColor, 0f0)
    lineCA = OdinJuliaBridge.create_new_line(
        state_ptr, Intersection, Intersection, LineCAColor, 0f0)


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
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleACEEndId, Float32(circleACE.endId))=#

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelEId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelEId))

    #if lineABHostId < 0 || lineCBHostId < 0 || lineCAHostId < 0 || circleBCDHostId < 0 || circleACEHostId < 0
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

            OdinJuliaBridge.show_point(state_ptr, labelAId)
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
