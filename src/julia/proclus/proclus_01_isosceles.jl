module ElementsOneProclusIsosceles

using ..OdinJuliaBridge
using ..EuclidAnimations

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
const MetaCircle3HostId = 15
const MetaCircle3StartId = 16
const MetaCircle3EndId = 17
const MetaCircle4HostId = 25
const MetaCircle4StartId = 26
const MetaCircle4EndId = 27
const MetaLineCBHostId = 30
const MetaLineCBJoint1Id = 31
const MetaLineCBJoint2Id = 32
const MetaLineCAHostId = 40
const MetaLineCAJoint1Id = 41
const MetaLineCAJoint2Id = 42
const MetaLabelAId = 51
const MetaLabelBId = 52
const MetaLabelCId = 53
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


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Proclus - Isosceles Triangle

On a given finite straight line to construct an isosceles triangle.

This follows Euclid's Elements Book I, Proposition I, with modifications.

To make an isosceles triangle he produces AB in both directions to meet the respective circles in D, E and then describes circles with A, B as centers and AE, BD as radii respectively. The result is an isosceles triangle with each of two sides double of the third side."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    circle1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1HostId))
    circle1StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1StartId))
    circle1EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1EndId))

    circle2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2HostId))
    circle2StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2StartId))
    circle2EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2EndId))

    circle3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle3HostId))
    circle3StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle3StartId))
    circle3EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle3EndId))

    circle4HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle4HostId))
    circle4StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle4StartId))
    circle4EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle4EndId))

    lineABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABHostId))
    lineABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint1Id))
    lineABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineABJoint2Id))

    lineCBHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCBHostId))
    lineCBJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCBJoint2Id))

    lineCAHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAHostId))
    lineCAJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLineCAJoint2Id))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [labelAId, labelBId, labelCId,
         lineABHostId, lineCBHostId, lineCAHostId,
         circle1HostId, circle2HostId, circle3HostId, circle4HostId
        ])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
        
    OdinJuliaBridge.lock_compass_joint1(state_ptr, APoint[1], APoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, BPoint[1], BPoint[2], CompassTopZ)

    OdinJuliaBridge.set_point_position(
        state_ptr, lineABJoint1Id, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, lineABJoint2Id, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, lineCBJoint2Id, Intersection)
    OdinJuliaBridge.set_point_position(
        state_ptr, lineCAJoint2Id, Intersection)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle1StartId, BPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle1EndId, BPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle1HostId, 0f0)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle2StartId, APoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle2EndId, APoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle2HostId, 0f0)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle3StartId, ExtBPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle3EndId, ExtBPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle3HostId, 0f0)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle4StartId, ExtAPoint)
    OdinJuliaBridge.set_point_position(
        state_ptr, circle4EndId, ExtAPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle4HostId, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
end

function initialize(state_ptr::Ptr{Cvoid})
    lineAB = OdinJuliaBridge.create_new_line(
        state_ptr, APoint, APoint, LineABColor, 0f0)
    circle1 = OdinJuliaBridge.create_new_circle(
        state_ptr, APoint, Radius, 7f0 * π / 4f0, 7f0 * π / 4f0, Circle1Color, 0f0)
    circle2 = OdinJuliaBridge.create_new_circle(
        state_ptr, BPoint, Radius, 3f0 * π / 4f0, 3f0 * π / 4f0, Circle2Color, 0f0)
    circle3 = OdinJuliaBridge.create_new_circle(
        state_ptr, ExtAPoint, ExtRadius, 7f0 * π / 4f0, 7f0 * π / 4f0, Circle3Color, 0f0)
    circle4 = OdinJuliaBridge.create_new_circle(
        state_ptr, ExtBPoint, ExtRadius, 3f0 * π / 4f0, 3f0 * π / 4f0, Circle4Color, 0f0)
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

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABHostId, Float32(lineAB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint1Id, Float32(lineAB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineABJoint2Id, Float32(lineAB.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCBHostId, Float32(lineCB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCBJoint1Id, Float32(lineCB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCBJoint2Id, Float32(lineCB.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAHostId, Float32(lineCA.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAJoint1Id, Float32(lineCA.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineCAJoint2Id, Float32(lineCA.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle1HostId, Float32(circle1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle1StartId, Float32(circle1.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle1EndId, Float32(circle1.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle2HostId, Float32(circle2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle2StartId, Float32(circle2.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle2EndId, Float32(circle2.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle3HostId, Float32(circle3.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle3StartId, Float32(circle3.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle3EndId, Float32(circle3.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle4HostId, Float32(circle4.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle4StartId, Float32(circle4.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircle4EndId, Float32(circle4.endId))

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

    circle1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1HostId))
    circle1StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1StartId))
    circle1EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle1EndId))

    circle2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2HostId))
    circle2StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2StartId))
    circle2EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle2EndId))

    circle3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle3HostId))
    circle3StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle3StartId))
    circle3EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle3EndId))

    circle4HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle4HostId))
    circle4StartId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle4StartId))
    circle4EndId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaCircle4EndId))

    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))

    if lineABHostId < 0 || lineCBHostId < 0 || lineCAHostId < 0 ||
        circle1HostId < 0 || circle2HostId < 0 || circle3HostId < 0 || circle4HostId < 0
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
            circle1HostId, circle1StartId, circle1EndId)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassArcToBA
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle1EndId, BPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle1HostId, 2f0π)
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
            circle2HostId, circle2StartId, circle2EndId)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle2EndId, APoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle2HostId, 2f0π)
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
            BPoint, APoint, ExtAPoint, LineMaxBrush, LineABColor,
            lineABHostId, lineABJoint2Id, lineABJoint1Id)

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
            ExtAPoint, BPoint, ExtBPoint, LineMaxBrush, LineABColor,
            lineABHostId, lineABJoint1Id, lineABJoint2Id)

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
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, CircleDrawDuration, ExtAPoint, ExtBPoint,
            CircleSweepTheta, ExtRadius, CircleBrush, Circle3Color,
            circle3HostId, circle3StartId, circle3EndId)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassArcToBA2
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle3EndId, ExtBPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle3HostId, 2f0π)
        end
    elseif phase == PhaseCompassArcToBA2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, CompassArcMoveDuration,
            ExtAPoint, ExtBPoint, ExtBPoint, ExtAPoint,
            CompassArcMoveHeight, 1, :none)

        timer += dt
        if timer >= CompassArcMoveDuration
            phase = PhaseDrawCircle4
            timer = 0f0
        end
    elseif phase == PhaseDrawCircle4
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, CircleDrawDuration, ExtBPoint, ExtAPoint,
            CircleSweepTheta, ExtRadius, CircleBrush, Circle4Color,
            circle4HostId, circle4StartId, circle4EndId)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassRise2
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle4EndId, ExtAPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle4HostId, 2f0π)
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
            state_ptr, timer, DescendDuration, PenTopZ, Intersection[1], Intersection[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLineCB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelCId)
        end
    elseif phase == PhaseDrawLineCB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, Intersection, BPoint,
            LineMaxBrush, LineCBColor, lineCBHostId, lineCBJoint1Id, lineCBJoint2Id)

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
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, Intersection, APoint,
            LineMaxBrush, LineCAColor, lineCAHostId, lineCAJoint1Id, lineCAJoint2Id)

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
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
