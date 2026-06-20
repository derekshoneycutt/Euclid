module ElementsOneDefinitionPoint

using ..OdinJuliaBridge
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
    """Euclid Elements - Book I - Definition: Point

A point is that which has no part."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    pointId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointId))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_point(state_ptr, pointId)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PointColor)
end

function initialize(state_ptr::Ptr{Cvoid})
    point = OdinJuliaBridge.create_new_point(
        state_ptr, Point, PointColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointId, Float32(point.index))
    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    pointId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointId))
    if pointId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

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
            OdinJuliaBridge.hide_pen(state_ptr)
            OdinJuliaBridge.hide_point(state_ptr, pointId)
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
