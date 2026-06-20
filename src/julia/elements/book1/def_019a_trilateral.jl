module ElementsOneDefinitionTrilateral

using ..EuclidBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.31f0, 0.70f0, 0f0]
const VertexB = [0.50f0, 0.34f0, 0f0]
const VertexC = [0.69f0, 0.70f0, 0f0]
const PenTopZ = 1.4f0

const TriangleColor = :steelblue
const TriangleMaxBrush = 5f0
const TriangleBaseColor = EuclidBridge.bridge_color(TriangleColor)
const FlickerColor = :white
const FlickerSamplesPerFrame = 8

const DescendDuration = 1.8f0
const DrawDuration = 3.1f0
const RiseDuration = 1.8f0
const FlickerDuration = 1f0

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
const MetaTriangleHostId = 12
const MetaTriangleJoint1Id = 13
const MetaTriangleJoint2Id = 14
const MetaTriangleJoint3Id = 15

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhaseRise = 4f0


function random_triangle_point(a::Vector{Float32}, b::Vector{Float32}, c::Vector{Float32})
    u = rand(Float32)
    v = rand(Float32)

    if u + v > 1f0
        u = 1f0 - u
        v = 1f0 - v
    end

    [
        a[1] + u * (b[1] - a[1]) + v * (c[1] - a[1]),
        a[2] + u * (b[2] - a[2]) + v * (c[2] - a[2]),
        0f0,
    ]
end

function set_triangle_alpha(state_ptr::Ptr{Cvoid}, triangleHostId, alpha01)
    t = clamp(alpha01, 0f0, 1f0)
    alpha = UInt8(round(Int, Float32(TriangleBaseColor.a) * t))
    color = EuclidBridge.BridgeColor(
        TriangleBaseColor.r,
        TriangleBaseColor.g,
        TriangleBaseColor.b,
        alpha)
    EuclidBridge.set_point_color(state_ptr, triangleHostId, color)
end


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Rectilineal Figures - Trilateral

Rectilineal figures are those which are contained by straight lines, trilateral figures being those contained by three..."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))
    triangleHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaTriangleHostId))

    EuclidBridge.hide_point_batch(state_ptr, [line1HostId, line2HostId, line3HostId, triangleHostId])
    set_triangle_alpha(state_ptr, triangleHostId, 0f0)

    EuclidBridge.set_point_position(
        state_ptr, line1Joint2Id, VertexA[1], VertexA[2], VertexA[3])
    EuclidBridge.set_point_position(
        state_ptr, line2Joint2Id, VertexB[1], VertexB[2], VertexB[3])
    EuclidBridge.set_point_position(
        state_ptr, line3Joint2Id, VertexC[1], VertexC[2], VertexC[3])

    EuclidBridge.hide_pen(state_ptr)
    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 0, TriangleColor)

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
end

function initialize(state_ptr::Ptr{Cvoid})
    line1 = EuclidBridge.create_new_line(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexA[1], VertexA[2], VertexA[3],
        TriangleColor, 0f0)
    line2 = EuclidBridge.create_new_line(
        state_ptr,
        VertexB[1], VertexB[2], VertexB[3],
        VertexB[1], VertexB[2], VertexB[3],
        TriangleColor, 0f0)
    line3 = EuclidBridge.create_new_line(
        state_ptr,
        VertexC[1], VertexC[2], VertexC[3],
        VertexC[1], VertexC[2], VertexC[3],
        TriangleColor, 0f0)
    triangle = EuclidBridge.create_new_triangle(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexC[1], VertexC[2], VertexC[3],
        VertexB[1], VertexB[2], VertexB[3],
        TriangleColor)

    EuclidBridge.set_animation_meta(state_ptr, MetaLine1HostId, Float32(line1.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, Float32(line1.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, Float32(line1.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaLine2HostId, Float32(line2.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, Float32(line2.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, Float32(line2.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaLine3HostId, Float32(line3.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine3Joint1Id, Float32(line3.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine3Joint2Id, Float32(line3.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaTriangleHostId, Float32(triangle.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaTriangleJoint1Id, Float32(triangle.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaTriangleJoint2Id, Float32(triangle.joint2Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaTriangleJoint3Id, Float32(triangle.joint3Id))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1Joint1Id))
    line1Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2Joint1Id))
    line2Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine3Joint1Id))
    line3Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))
    triangleHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaTriangleHostId))

    if line1HostId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

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
            TriangleMaxBrush, TriangleColor, line2HostId, line2Joint1Id, line2Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide3
            timer = 0f0
        end
    elseif phase == PhaseDrawSide3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexC, VertexA,
            TriangleMaxBrush, TriangleColor, line3HostId, line3Joint1Id, line3Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseRise
            timer = 0f0
        end
    elseif phase == PhaseRise
        set_triangle_alpha(state_ptr, triangleHostId, timer / FlickerDuration)
        EuclidBridge.show_point(state_ptr, triangleHostId)

        if timer <= FlickerDuration
            for _ in 1:FlickerSamplesPerFrame
                samplePos = random_triangle_point(VertexA, VertexB, VertexC)
                EuclidBridge.emit_flicker_particle(state_ptr, samplePos[1], samplePos[2], FlickerColor)
            end
        end

        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, RiseDuration, PenTopZ, VertexA[1], VertexA[2])

        timer += dt
        if timer >= RiseDuration
            EuclidBridge.hide_pen(state_ptr)
            reset_cycle_state(state_ptr)
            return
        end
    end

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
