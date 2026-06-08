module ElementsOneDefinitionPoint

import ..EuclidBridge

export get_view_text, initialize, clean, loop

const PointX = 0.5f0
const PointY = 0.5f0
const PointZ = 0f0

const PointColor = :steelblue
const PointMaxBrush = 5f0

const PenTopZ = 1.4f0
const PenBottomZ = 0f0
const PenLength = 0.14f0
const PenConeRadius = 0.02f0
const PenConeSpinSpeed = 8f0
const PenConeTipHeight = Float32(sqrt(PenLength * PenLength - PenConeRadius * PenConeRadius))

const DescendDuration = 3f0
const GroundTrailDuration = 2f0
const RiseDuration = 3f0
const PointFadeSpeed = 8f0

const MetaPointId = 1
const MetaPhase = 2
const MetaTimer = 3

const PhaseDescend = 0f0
const PhaseGroundTrail = 1f0
const PhaseRise = 2f0
const PhasePointFade = 3f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: 1. Point:

A point is that which has no part."""
end

function show_full_point(state_ptr::Ptr{Cvoid}, pointId::Integer)
    EuclidBridge.show_point(state_ptr, pointId)
    EuclidBridge.set_point_color(state_ptr, pointId, PointColor)
    EuclidBridge.set_point_position(state_ptr, pointId, PointX, PointY, PointZ)
    EuclidBridge.set_point_brush(state_ptr, pointId, PointMaxBrush)
end

function place_pen(state_ptr::Ptr{Cvoid}, z::Float32)
    EuclidBridge.lock_pen_joint1(state_ptr, PointX, PointY, z)
    EuclidBridge.move_pen_joint2(state_ptr, PointX, PointY, z + PenLength)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    pointId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPointId))

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    EuclidBridge.hide_point(state_ptr, pointId)
    EuclidBridge.set_point_brush(state_ptr, pointId, 0f0)

    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 1, PointColor)
    place_pen(state_ptr, PenTopZ)
end

function initialize(state_ptr::Ptr{Cvoid})
    point = EuclidBridge.create_new_point(
        state_ptr,
        PointX, PointY, PointZ,
        PointColor,
        0f0)

    EuclidBridge.set_animation_meta(state_ptr, MetaPointId, Float32(point.index))
    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
    pointId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPointId))
    EuclidBridge.set_point_brush(state_ptr, pointId, 0f0)
    EuclidBridge.hide_point(state_ptr, pointId)
    EuclidBridge.hide_pen(state_ptr)
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    pointId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPointId))
    if pointId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        t = timer / DescendDuration
        if t > 1f0
            t = 1f0
        end

        penZ = PenTopZ + (PenBottomZ - PenTopZ) * t
        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, PointColor)
        place_pen(state_ptr, penZ)

        timer += dt
        if timer >= DescendDuration
            phase = PhaseGroundTrail
            timer = 0f0

            show_full_point(state_ptr, pointId)
            place_pen(state_ptr, PenBottomZ)
        end
    elseif phase == PhaseGroundTrail
        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, PointColor)

        theta = timer * PenConeSpinSpeed
        tipX = PointX + PenConeRadius * Float32(cos(theta))
        tipY = PointY + PenConeRadius * Float32(sin(theta))
        tipZ = PenBottomZ + PenConeTipHeight

        EuclidBridge.lock_pen_joint1(state_ptr, PointX, PointY, PenBottomZ)
        EuclidBridge.move_pen_joint2(state_ptr, tipX, tipY, tipZ)

        show_full_point(state_ptr, pointId)

        EuclidBridge.emit_trailing_particle(state_ptr, PointX, PointY, PointColor)

        timer += dt
        if timer >= GroundTrailDuration
            phase = PhaseRise
            timer = 0f0
        end
    elseif phase == PhaseRise
        t = timer / RiseDuration
        if t > 1f0
            t = 1f0
        end

        penZ = PenBottomZ + (PenTopZ - PenBottomZ) * t
        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, PointColor)
        place_pen(state_ptr, penZ)

        show_full_point(state_ptr, pointId)

        timer += dt
        if timer >= RiseDuration
            phase = PhasePointFade
            timer = 0f0
            EuclidBridge.hide_pen(state_ptr)
            place_pen(state_ptr, PenTopZ)
        end
    else
        point = EuclidBridge.get_point(state_ptr, pointId)
        nextBrush = point.brushSize - PointFadeSpeed * dt

        if nextBrush <= 0f0
            EuclidBridge.set_point_brush(state_ptr, pointId, 0f0)
            EuclidBridge.hide_point(state_ptr, pointId)
            reset_cycle_state(state_ptr)
            return
        else
            EuclidBridge.show_point(state_ptr, pointId)
            EuclidBridge.set_point_brush(state_ptr, pointId, nextBrush)
        end
    end

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
