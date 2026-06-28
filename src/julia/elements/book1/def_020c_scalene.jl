module ElementsOneDefinitionScalene

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.22f0, 0.75f0, 0f0]
const VertexB = [0.34f0, 0.47f0, 0f0]
const VertexC = [0.84f0, 0.66f0, 0f0]
const PenTopZ = 1.4f0

const TriangleColor = :steelblue
const TriangleColor2 = :palevioletred1
const TriangleColor3 = :khaki3
const TriangleMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawDuration = 3.1f0
const RiseDuration = 1.8f0

const MetaLine1HostId = 1
const MetaLine1Joint1Id = 2
const MetaLine1Joint2Id = 3
const MetaLine2HostId = 4
const MetaLine2Joint1Id = 5
const MetaLine2Joint2Id = 6
const MetaLine3HostId = 7
const MetaLine3Joint1Id = 8
const MetaLine3Joint2Id = 9
const MetaPhase = 10
const MetaTimer = 11

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhaseRise = 4f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Scalene Triangle

Of trilateral figures, ... and a scalene triangle that which has its three sides unequal."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))

    OdinJuliaBridge.hide_point_batch(state_ptr, [line1HostId, line2HostId, line3HostId])

    OdinJuliaBridge.set_point_position(
        state_ptr, line1Joint2Id, VertexA[1], VertexA[2], VertexA[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line2Joint2Id, VertexB[1], VertexB[2], VertexB[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line3Joint2Id, VertexC[1], VertexC[2], VertexC[3])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, TriangleColor)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexA[1], VertexA[2], VertexA[3],
        TriangleColor, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexB[1], VertexB[2], VertexB[3],
        VertexB[1], VertexB[2], VertexB[3],
        TriangleColor2, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexC[1], VertexC[2], VertexC[3],
        VertexC[1], VertexC[2], VertexC[3],
        TriangleColor3, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1HostId, Float32(line1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, Float32(line1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, Float32(line1.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2HostId, Float32(line2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, Float32(line2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, Float32(line2.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3HostId, Float32(line3.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint1Id, Float32(line3.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint2Id, Float32(line3.joint2Id))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint1Id))
    line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint1Id))
    line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint1Id))
    line3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))

    if line1HostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, VertexA[1], VertexA[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawSide1
            timer = 0f0
        end
    elseif phase == PhaseDrawSide1
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexA, VertexB,
            TriangleMaxBrush, TriangleColor, line1HostId, line1Joint1Id, line1Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide2
            timer = 0f0
        end
    elseif phase == PhaseDrawSide2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexB, VertexC,
            TriangleMaxBrush, TriangleColor2, line2HostId, line2Joint1Id, line2Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide3
            timer = 0f0
        end
    elseif phase == PhaseDrawSide3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexC, VertexA,
            TriangleMaxBrush, TriangleColor3, line3HostId, line3Joint1Id, line3Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseRise
            timer = 0f0
        end
    elseif phase == PhaseRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, RiseDuration, PenTopZ, VertexA[1], VertexA[2])

        timer += dt
        if timer >= RiseDuration
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
