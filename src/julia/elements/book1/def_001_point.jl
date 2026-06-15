module ElementsOneDefinitionPoint

using ..EuclidBridge
using ..EuclidAnimations

export get_view_text, initialize, clean, loop

const Point = [0.5f0, 0.5f0, 0f0]

const PointColor = :steelblue
const PointMaxBrush = 5f0

const PenTopZ = 1.4f0

const DescendDuration = 3f0
const DrawDuration = 4f0
const RiseDuration = 3f0

const MetaPointId = 1
const MetaPhase = 2
const MetaTimer = 3

const PhaseDescend = 0f0
const PhaseDraw = 1f0
const PhaseRise = 2f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Point:

A point is that which has no part."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    pointId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPointId))

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    EuclidBridge.hide_point(state_ptr, pointId)

    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 0, PointColor)
end

function initialize(state_ptr::Ptr{Cvoid})
    point = EuclidBridge.create_new_point(
        state_ptr, Point, PointColor, 0f0)

    EuclidBridge.set_animation_meta(state_ptr, MetaPointId, Float32(point.index))
    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    pointId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaPointId))
    if pointId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, Point[1], Point[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDraw
            timer = 0f0
        end
    elseif phase == PhaseDraw
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawDuration, Point,
            PointMaxBrush, PointColor, pointId)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseRise
            timer = 0f0
        end
    elseif phase == PhaseRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, RiseDuration, PenTopZ, Point[1], Point[2])

        timer += dt
        if timer >= RiseDuration
            EuclidBridge.hide_pen(state_ptr)
            EuclidBridge.hide_point(state_ptr, pointId)
            reset_cycle_state(state_ptr)
            return
        end
    end

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
