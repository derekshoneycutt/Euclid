module ElementsOneDefinitionMultilateral

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.50f0, 0.76f0, 0f0]
const VertexB = [0.70f0, 0.62f0, 0f0]
const VertexC = [0.62f0, 0.36f0, 0f0]
const VertexD = [0.38f0, 0.36f0, 0f0]
const VertexE = [0.30f0, 0.62f0, 0f0]
const PenTopZ = 1.4f0

const PentagonColor = :steelblue
const PentagonMaxBrush = 5f0
const PentagonBaseColor = OdinJuliaBridge.bridge_color(PentagonColor)
const FlickerColor = :white
const FlickerSamplesPerFrame = 8

const DescendDuration = 1.8f0
const DrawDuration = 2.25f0
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
const MetaLine4HostId = 10
const MetaLine4Joint1Id = 11
const MetaLine4Joint2Id = 12
const MetaLine5HostId = 13
const MetaLine5Joint1Id = 14
const MetaLine5Joint2Id = 15
const MetaShapeHostId = 16
const MetaShapeJoint1Id = 17
const MetaShapeJoint2Id = 18
const MetaShapeJoint3Id = 19
const MetaShapeJoint4Id = 20
const MetaShapeJoint5Id = 21
const MetaPhase = 22
const MetaTimer = 23

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhaseDrawSide4 = 4f0
const PhaseDrawSide5 = 5f0
const PhaseRise = 6f0


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

function random_pentagon_point()
    t = rand(Float32)
    if t < 1f0 / 3f0
        return random_triangle_point(VertexA, VertexB, VertexC)
    elseif t < 2f0 / 3f0
        return random_triangle_point(VertexA, VertexC, VertexD)
    end
    random_triangle_point(VertexA, VertexD, VertexE)
end

function set_pentagon_alpha(state_ptr::Ptr{Cvoid}, shapeHostId, alpha01)
    t = clamp(alpha01, 0f0, 1f0)
    alpha = UInt8(round(Int, Float32(PentagonBaseColor.a) * t))
    color = OdinJuliaBridge.BridgeColor(
        PentagonBaseColor.r,
        PentagonBaseColor.g,
        PentagonBaseColor.b,
        alpha)
    OdinJuliaBridge.set_point_color(state_ptr, shapeHostId, color)
end


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Rectilineal Figures - Multilateral

Rectilineal figures are those which are contained by straight lines, ... and multilateral those contained by more than four straight lines."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))

    line4HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine4HostId))
    line4Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine4Joint2Id))

    line5HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine5HostId))
    line5Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine5Joint2Id))

    shapeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaShapeHostId))

    OdinJuliaBridge.hide_point_batch(state_ptr, [line1HostId, line2HostId, line3HostId, line4HostId, line5HostId, shapeHostId])
    set_pentagon_alpha(state_ptr, shapeHostId, 0f0)

    OdinJuliaBridge.set_point_position(
        state_ptr, line1Joint2Id, VertexA[1], VertexA[2], VertexA[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line2Joint2Id, VertexB[1], VertexB[2], VertexB[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line3Joint2Id, VertexC[1], VertexC[2], VertexC[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line4Joint2Id, VertexD[1], VertexD[2], VertexD[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line5Joint2Id, VertexE[1], VertexE[2], VertexE[3])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PentagonColor)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexA[1], VertexA[2], VertexA[3],
        PentagonColor, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexB[1], VertexB[2], VertexB[3],
        VertexB[1], VertexB[2], VertexB[3],
        PentagonColor, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexC[1], VertexC[2], VertexC[3],
        VertexC[1], VertexC[2], VertexC[3],
        PentagonColor, 0f0)
    line4 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexD[1], VertexD[2], VertexD[3],
        VertexD[1], VertexD[2], VertexD[3],
        PentagonColor, 0f0)
    line5 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexE[1], VertexE[2], VertexE[3],
        VertexE[1], VertexE[2], VertexE[3],
        PentagonColor, 0f0)
    pentagon = OdinJuliaBridge.create_new_pentagon(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexE[1], VertexE[2], VertexE[3],
        VertexD[1], VertexD[2], VertexD[3],
        VertexC[1], VertexC[2], VertexC[3],
        VertexB[1], VertexB[2], VertexB[3],
        PentagonColor)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1HostId, Float32(line1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, Float32(line1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, Float32(line1.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2HostId, Float32(line2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, Float32(line2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, Float32(line2.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3HostId, Float32(line3.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint1Id, Float32(line3.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint2Id, Float32(line3.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine4HostId, Float32(line4.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine4Joint1Id, Float32(line4.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine4Joint2Id, Float32(line4.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine5HostId, Float32(line5.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine5Joint1Id, Float32(line5.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine5Joint2Id, Float32(line5.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeHostId, Float32(pentagon.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint1Id, Float32(pentagon.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint2Id, Float32(pentagon.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint3Id, Float32(pentagon.joint3Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint4Id, Float32(pentagon.joint4Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint5Id, Float32(pentagon.joint5Id))

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

    line4HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine4HostId))
    line4Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine4Joint1Id))
    line4Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine4Joint2Id))

    line5HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine5HostId))
    line5Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine5Joint1Id))
    line5Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine5Joint2Id))

    shapeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaShapeHostId))

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
            PentagonMaxBrush, PentagonColor, line1HostId, line1Joint1Id, line1Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide2
            timer = 0f0
        end
    elseif phase == PhaseDrawSide2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexB, VertexC,
            PentagonMaxBrush, PentagonColor, line2HostId, line2Joint1Id, line2Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide3
            timer = 0f0
        end
    elseif phase == PhaseDrawSide3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexC, VertexD,
            PentagonMaxBrush, PentagonColor, line3HostId, line3Joint1Id, line3Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide4
            timer = 0f0
        end
    elseif phase == PhaseDrawSide4
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexD, VertexE,
            PentagonMaxBrush, PentagonColor, line4HostId, line4Joint1Id, line4Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide5
            timer = 0f0
        end
    elseif phase == PhaseDrawSide5
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexE, VertexA,
            PentagonMaxBrush, PentagonColor, line5HostId, line5Joint1Id, line5Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseRise
            timer = 0f0
        end
    elseif phase == PhaseRise
        set_pentagon_alpha(state_ptr, shapeHostId, timer / FlickerDuration)
        OdinJuliaBridge.show_point(state_ptr, shapeHostId)

        if timer <= FlickerDuration
            for _ in 1:FlickerSamplesPerFrame
                samplePos = random_pentagon_point()
                OdinJuliaBridge.emit_flicker_particle(state_ptr, samplePos, FlickerColor)
            end
        end

        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, RiseDuration, PenTopZ, VertexA[1], VertexA[2])

        timer += dt
        if timer >= RiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
