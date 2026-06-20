module ElementsOneDefinitionDiameter

using ..EuclidBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const CenterPoint = [0.50f0, 0.50f0, 0f0]
const Radius = 0.24f0
const CircleStartPoint = [CenterPoint[1] + Radius, CenterPoint[2], 0f0]
const DiameterStartPoint = [CenterPoint[1] - Radius, CenterPoint[2], 0f0]
const DiameterEndPoint = [CenterPoint[1] + Radius, CenterPoint[2], 0f0]
const CircleSweepTheta = Float32(2f0 * π)

const CenterColor = :palevioletred1
const CircleColor = :khaki3
const DiameterColor = :steelblue
const CenterMaxBrush = 5f0
const CircleBrush = 5f0
const DiameterBrush = 5f0

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const PenDescendDuration = 1.8f0
const PointDrawDuration = 2.8f0
const PenRiseDuration = 1.8f0
const CompassDescendDuration = 1.8f0
const CircleDrawDuration = 4.4f0
const CompassRiseDuration = 2.8f0
const DiameterPenDescendDuration = 1.8f0
const DiameterDrawDuration = 3.8f0
const DiameterPenRiseDuration = 1.8f0
const HidePauseDuration = 1.5f0

const MetaCenterPointId = 1
const MetaCircleHostId = 2
const MetaCircleStartId = 3
const MetaCircleEndId = 4
const MetaDiameterHostId = 5
const MetaDiameterJoint1Id = 6
const MetaDiameterJoint2Id = 7
const MetaPhase = 8
const MetaTimer = 9

const PhasePenDescend = 0f0
const PhaseDrawCenter = 1f0
const PhasePenRise = 2f0
const PhaseCompassDescend = 3f0
const PhaseDrawCircle = 4f0
const PhaseCompassRise = 5f0
const PhaseDiameterPenDescend = 6f0
const PhaseDrawDiameter = 7f0
const PhaseDiameterPenRise = 8f0
const PhaseHideAll = 9f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Diameter

A diameter of the circle is any straight line drawn through the center and terminated in both directions by the circumference of the circle, and such a straight line also bisects the circle."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    centerPointId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaCenterPointId))
    circleHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaCircleHostId))
    circleEndId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaCircleEndId))
    diameterHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaDiameterHostId))
    diameterJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaDiameterJoint2Id))

    EuclidBridge.hide_point_batch(state_ptr, [centerPointId, circleHostId, diameterHostId])

    EuclidBridge.set_point_position(
        state_ptr, circleEndId,
        CircleStartPoint[1], CircleStartPoint[2], CircleStartPoint[3])
    EuclidBridge.set_point_position(
        state_ptr, diameterJoint2Id,
        DiameterStartPoint[1], DiameterStartPoint[2], DiameterStartPoint[3])

    EuclidBridge.hide_pen(state_ptr)
    EuclidBridge.hide_compass(state_ptr)

    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 0, CenterColor)
    EuclidBridge.set_compass_active(state_ptr, 0, CircleColor)
    EuclidBridge.lock_compass_joint1(state_ptr, CenterPoint[1], CenterPoint[2], CompassTopZ)
    EuclidBridge.lock_compass_joint2(
        state_ptr, CircleStartPoint[1], CircleStartPoint[2], CompassTopZ)

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
end

function initialize(state_ptr::Ptr{Cvoid})
    centerPoint = EuclidBridge.create_new_point(
        state_ptr, CenterPoint, CenterColor, 0f0)
    circle = EuclidBridge.create_new_circle(
        state_ptr, CenterPoint, Radius, 0f0, 0f0, CircleColor, 0f0)
    diameter = EuclidBridge.create_new_line(
        state_ptr,
        DiameterStartPoint[1], DiameterStartPoint[2], DiameterStartPoint[3],
        DiameterStartPoint[1], DiameterStartPoint[2], DiameterStartPoint[3],
        DiameterColor, 0f0)

    EuclidBridge.set_animation_meta(state_ptr, MetaCenterPointId, Float32(centerPoint.index))

    EuclidBridge.set_animation_meta(state_ptr, MetaCircleHostId, Float32(circle.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaCircleStartId, Float32(circle.startId))
    EuclidBridge.set_animation_meta(state_ptr, MetaCircleEndId, Float32(circle.endId))

    EuclidBridge.set_animation_meta(state_ptr, MetaDiameterHostId, Float32(diameter.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaDiameterJoint1Id, Float32(diameter.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaDiameterJoint2Id, Float32(diameter.joint2Id))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    centerPointId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaCenterPointId))
    circleHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaCircleHostId))
    circleStartId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaCircleStartId))
    circleEndId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaCircleEndId))
    diameterHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaDiameterHostId))
    diameterJoint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaDiameterJoint1Id))
    diameterJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaDiameterJoint2Id))

    if centerPointId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration, PenTopZ, CenterPoint[1], CenterPoint[2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawCenter
            timer = 0f0
        end
    elseif phase == PhaseDrawCenter
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, CenterPoint,
            CenterMaxBrush, CenterColor, centerPointId)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhasePenRise
            timer = 0f0
        end
    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration, PenTopZ, CenterPoint[1], CenterPoint[2])

        timer += dt
        if timer >= PenRiseDuration
            EuclidBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescend
            timer = 0f0
        end
    elseif phase == PhaseCompassDescend
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, CompassDescendDuration, CompassTopZ,
            CenterPoint[1], CenterPoint[2], CircleStartPoint[1], CircleStartPoint[2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawCircle
            timer = 0f0
        end
    elseif phase == PhaseDrawCircle
        EuclidAnimations.animate_draw_circle(
            state_ptr, timer, CircleDrawDuration, CenterPoint, CircleStartPoint,
            CircleSweepTheta, Radius, CircleBrush, CircleColor,
            circleHostId, circleStartId, circleEndId)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            CenterPoint[1], CenterPoint[2], CircleStartPoint[1], CircleStartPoint[2])

        timer += dt
        if timer >= CompassRiseDuration
            EuclidBridge.hide_compass(state_ptr)
            EuclidBridge.show_pen(state_ptr)
            EuclidBridge.set_pen_active(state_ptr, 0, DiameterColor)
            phase = PhaseDiameterPenDescend
            timer = 0f0
        end
    elseif phase == PhaseDiameterPenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DiameterPenDescendDuration,
            PenTopZ, DiameterStartPoint[1], DiameterStartPoint[2])

        timer += dt
        if timer >= DiameterPenDescendDuration
            phase = PhaseDrawDiameter
            timer = 0f0
        end
    elseif phase == PhaseDrawDiameter
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DiameterDrawDuration, DiameterStartPoint, DiameterEndPoint,
            DiameterBrush, DiameterColor,
            diameterHostId, diameterJoint1Id, diameterJoint2Id)

        timer += dt
        if timer >= DiameterDrawDuration
            phase = PhaseDiameterPenRise
            timer = 0f0
        end
    elseif phase == PhaseDiameterPenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, DiameterPenRiseDuration, PenTopZ,
            DiameterEndPoint[1], DiameterEndPoint[2])

        timer += dt
        if timer >= DiameterPenRiseDuration
            EuclidBridge.hide_pen(state_ptr)
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

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
