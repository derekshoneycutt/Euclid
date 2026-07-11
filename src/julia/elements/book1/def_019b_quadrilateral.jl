module ElementsOneDefinitionQuadrilateral

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.34f0, 0.66f0, 0f0]
const VertexB = [0.66f0, 0.66f0, 0f0]
const VertexC = [0.66f0, 0.34f0, 0f0]
const VertexD = [0.34f0, 0.34f0, 0f0]
const PenTopZ = 1.4f0

const SquareColor = :steelblue
const SquareMaxBrush = 5f0
const SquareBaseColor = OdinJuliaBridge.bridge_color(SquareColor)
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
const MetaShapeHostId = 13
const MetaShapeJoint1Id = 14
const MetaShapeJoint2Id = 15
const MetaShapeJoint3Id = 16
const MetaShapeJoint4Id = 17
const MetaPhase = 18
const MetaTimer = 19

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhaseDrawSide4 = 4f0
const PhaseRise = 5f0


function random_square_point(a::Vector{Float32}, b::Vector{Float32}, d::Vector{Float32})
    u = rand(Float32)
    v = rand(Float32)

    [
        a[1] + u * (b[1] - a[1]) + v * (d[1] - a[1]),
        a[2] + u * (b[2] - a[2]) + v * (d[2] - a[2]),
        0f0,
    ]
end

function set_square_alpha(state_ptr::Ptr{Cvoid}, shapeHostId, alpha01)
    t = clamp(alpha01, 0f0, 1f0)
    alpha = UInt8(round(Int, Float32(SquareBaseColor.a) * t))
    color = OdinJuliaBridge.BridgeColor(
        SquareBaseColor.r,
        SquareBaseColor.g,
        SquareBaseColor.b,
        alpha)
    OdinJuliaBridge.set_point_color(state_ptr, shapeHostId, color)
end


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Rectilineal Figures - Quadrilateral

Rectilineal figures are those which are contained by straight lines, ... quadrilateral those contained by four, ..."""
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

    shapeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaShapeHostId))

    OdinJuliaBridge.hide_point_batch(state_ptr, [line1HostId, line2HostId, line3HostId, line4HostId, shapeHostId])
    set_square_alpha(state_ptr, shapeHostId, 0f0)

    OdinJuliaBridge.set_point_position(
        state_ptr, line1Joint2Id, VertexA[1], VertexA[2], VertexA[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line2Joint2Id, VertexB[1], VertexB[2], VertexB[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line3Joint2Id, VertexC[1], VertexC[2], VertexC[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line4Joint2Id, VertexD[1], VertexD[2], VertexD[3])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, SquareColor)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexA[1], VertexA[2], VertexA[3],
        SquareColor, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexB[1], VertexB[2], VertexB[3],
        VertexB[1], VertexB[2], VertexB[3],
        SquareColor, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexC[1], VertexC[2], VertexC[3],
        VertexC[1], VertexC[2], VertexC[3],
        SquareColor, 0f0)
    line4 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexD[1], VertexD[2], VertexD[3],
        VertexD[1], VertexD[2], VertexD[3],
        SquareColor, 0f0)
    square = OdinJuliaBridge.create_new_square(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexD[1], VertexD[2], VertexD[3],
        VertexC[1], VertexC[2], VertexC[3],
        VertexB[1], VertexB[2], VertexB[3],
        SquareColor)

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

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeHostId, Float32(square.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint1Id, Float32(square.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint2Id, Float32(square.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint3Id, Float32(square.joint3Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint4Id, Float32(square.joint4Id))

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
            SquareMaxBrush, SquareColor, line1HostId, line1Joint1Id, line1Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide2
            timer = 0f0
        end
    elseif phase == PhaseDrawSide2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexB, VertexC,
            SquareMaxBrush, SquareColor, line2HostId, line2Joint1Id, line2Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide3
            timer = 0f0
        end
    elseif phase == PhaseDrawSide3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexC, VertexD,
            SquareMaxBrush, SquareColor, line3HostId, line3Joint1Id, line3Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide4
            timer = 0f0
        end
    elseif phase == PhaseDrawSide4
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawDuration, VertexD, VertexA,
            SquareMaxBrush, SquareColor, line4HostId, line4Joint1Id, line4Joint2Id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseRise
            timer = 0f0
        end
    elseif phase == PhaseRise
        set_square_alpha(state_ptr, shapeHostId, timer / FlickerDuration)
        OdinJuliaBridge.show_point(state_ptr, shapeHostId)

        if timer <= FlickerDuration
            for _ in 1:FlickerSamplesPerFrame
                samplePos = random_square_point(VertexA, VertexB, VertexD)
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
