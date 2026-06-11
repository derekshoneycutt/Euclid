module ElementsOneDefinitionSurfaceExtremity

using LinearAlgebra

include("../../euclidbridge.jl")

export get_view_text, initialize, clean, loop

const Corner1 = [0f0, 0f0, 0f0]
const Corner2 = [1f0, 0f0, 0f0]
const Corner3 = [1f0, 1f0, 0f0]
const Corner4 = [0f0, 1f0, 0f0]

const LineColor1 = :steelblue
const LineColor2 = :palevioletred1
const LineColor3 = :steelblue
const LineColor4 = :palevioletred1
const LineBrush = 5f0

const PenTopZ = 1.4f0
const PenLength = 0.14f0
const PenTiltFloorAngle = π / 4f0

const DescendDuration = 1.8f0
const TiltDuration = 0.7f0
const DrawDuration = 1.6f0
const CornerStraightenDuration = 0.45f0
const EndLiftDuration = 1.6f0
const HidePauseDuration = 0.35f0

const SegmentVec1 = Corner2 - Corner1
const SegmentVecLen1 = norm(SegmentVec1)
const PenDirX1 = SegmentVecLen1 > 0f0 ? SegmentVec1[1] / SegmentVecLen1 : 1f0
const PenDirY1 = SegmentVecLen1 > 0f0 ? SegmentVec1[2] / SegmentVecLen1 : 0f0

const SegmentVec2 = Corner3 - Corner2
const SegmentVecLen2 = norm(SegmentVec2)
const PenDirX2 = SegmentVecLen2 > 0f0 ? SegmentVec2[1] / SegmentVecLen2 : 1f0
const PenDirY2 = SegmentVecLen2 > 0f0 ? SegmentVec2[2] / SegmentVecLen2 : 0f0

const SegmentVec3 = Corner4 - Corner3
const SegmentVecLen3 = norm(SegmentVec3)
const PenDirX3 = SegmentVecLen3 > 0f0 ? SegmentVec3[1] / SegmentVecLen3 : 1f0
const PenDirY3 = SegmentVecLen3 > 0f0 ? SegmentVec3[2] / SegmentVecLen3 : 0f0

const SegmentVec4 = Corner1 - Corner4
const SegmentVecLen4 = norm(SegmentVec4)
const PenDirX4 = SegmentVecLen4 > 0f0 ? SegmentVec4[1] / SegmentVecLen4 : 1f0
const PenDirY4 = SegmentVecLen4 > 0f0 ? SegmentVec4[2] / SegmentVecLen4 : 0f0

const MetaEdge1HostId = 1
const MetaEdge1Joint1Id = 2
const MetaEdge1Joint2Id = 3
const MetaEdge2HostId = 4
const MetaEdge2Joint1Id = 5
const MetaEdge2Joint2Id = 6
const MetaEdge3HostId = 7
const MetaEdge3Joint1Id = 8
const MetaEdge3Joint2Id = 9
const MetaEdge4HostId = 10
const MetaEdge4Joint1Id = 11
const MetaEdge4Joint2Id = 12
const MetaPhase = 13
const MetaTimer = 14

const PhaseDescend = 0f0
const PhaseTilt1 = 1f0
const PhaseDraw1 = 2f0
const PhaseStraightenAt2 = 3f0
const PhaseTilt2 = 4f0
const PhaseDraw2 = 5f0
const PhaseStraightenAt3 = 6f0
const PhaseTilt3 = 7f0
const PhaseDraw3 = 8f0
const PhaseStraightenAt4 = 9f0
const PhaseTilt4 = 10f0
const PhaseDraw4 = 11f0
const PhaseStraightenAt1 = 12f0
const PhaseEndLift = 13f0
const PhaseHideLines = 14f0

function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Surface Extremities:

The extremities of a surface are lines."""
end

function place_pen_at_floor_angle(
    state_ptr::Ptr{Cvoid}, tipX::Float32, tipY::Float32, tipZ::Float32,
    floorAngle::Float32, dirX::Float32, dirY::Float32)

    horizontalLength = PenLength * Float32(cos(floorAngle))
    verticalLength = PenLength * Float32(sin(floorAngle))

    shaftX = tipX + dirX * horizontalLength
    shaftY = tipY + dirY * horizontalLength
    shaftZ = tipZ + verticalLength

    EuclidBridge.lock_pen_joint1(state_ptr, tipX, tipY, tipZ)
    EuclidBridge.move_pen_joint2(state_ptr, shaftX, shaftY, shaftZ)
end

function set_edge_progress(
    state_ptr::Ptr{Cvoid}, joint1Id::Integer, joint2Id::Integer,
    startPoint::Vector{Float32}, endPoint::Vector{Float32}, t::Float32)

    tipX = startPoint[1] + (endPoint[1] - startPoint[1]) * t
    tipY = startPoint[2] + (endPoint[2] - startPoint[2]) * t
    tipZ = startPoint[3] + (endPoint[3] - startPoint[3]) * t

    EuclidBridge.set_point_position(state_ptr, joint1Id, startPoint[1], startPoint[2], startPoint[3])
    EuclidBridge.set_point_position(state_ptr, joint2Id, tipX, tipY, tipZ)
end

function hide_edge_and_collapse(
    state_ptr::Ptr{Cvoid}, hostId::Integer, joint1Id::Integer, joint2Id::Integer,
    corner::Vector{Float32})

    EuclidBridge.hide_point(state_ptr, hostId)
    EuclidBridge.set_point_position(state_ptr, joint1Id, corner[1], corner[2], corner[3])
    EuclidBridge.set_point_position(state_ptr, joint2Id, corner[1], corner[2], corner[3])
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    edge1HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge1HostId))
    edge1Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge1Joint1Id))
    edge1Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge1Joint2Id))

    edge2HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge2HostId))
    edge2Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge2Joint1Id))
    edge2Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge2Joint2Id))

    edge3HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge3HostId))
    edge3Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge3Joint1Id))
    edge3Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge3Joint2Id))

    edge4HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge4HostId))
    edge4Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge4Joint1Id))
    edge4Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge4Joint2Id))

    hide_edge_and_collapse(state_ptr, edge1HostId, edge1Joint1Id, edge1Joint2Id, Corner1)
    hide_edge_and_collapse(state_ptr, edge2HostId, edge2Joint1Id, edge2Joint2Id, Corner2)
    hide_edge_and_collapse(state_ptr, edge3HostId, edge3Joint1Id, edge3Joint2Id, Corner3)
    hide_edge_and_collapse(state_ptr, edge4HostId, edge4Joint1Id, edge4Joint2Id, Corner4)

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 0, LineColor1)
    place_pen_at_floor_angle(
        state_ptr, Corner1[1], Corner1[2], PenTopZ, π / 2f0, PenDirX1, PenDirY1)
end

function initialize(state_ptr::Ptr{Cvoid})
    edge1 = EuclidBridge.create_new_line(
        state_ptr,
        Corner1[1], Corner1[2], Corner1[3],
        Corner1[1], Corner1[2], Corner1[3],
        LineColor1, 0f0)
    edge2 = EuclidBridge.create_new_line(
        state_ptr,
        Corner2[1], Corner2[2], Corner2[3],
        Corner2[1], Corner2[2], Corner2[3],
        LineColor2, 0f0)
    edge3 = EuclidBridge.create_new_line(
        state_ptr,
        Corner3[1], Corner3[2], Corner3[3],
        Corner3[1], Corner3[2], Corner3[3],
        LineColor3, 0f0)
    edge4 = EuclidBridge.create_new_line(
        state_ptr,
        Corner4[1], Corner4[2], Corner4[3],
        Corner4[1], Corner4[2], Corner4[3],
        LineColor4, 0f0)

    EuclidBridge.set_animation_meta(state_ptr, MetaEdge1HostId, Float32(edge1.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaEdge1Joint1Id, Float32(edge1.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaEdge1Joint2Id, Float32(edge1.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaEdge2HostId, Float32(edge2.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaEdge2Joint1Id, Float32(edge2.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaEdge2Joint2Id, Float32(edge2.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaEdge3HostId, Float32(edge3.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaEdge3Joint1Id, Float32(edge3.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaEdge3Joint2Id, Float32(edge3.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaEdge4HostId, Float32(edge4.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaEdge4Joint1Id, Float32(edge4.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaEdge4Joint2Id, Float32(edge4.joint2Id))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    edge1HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge1HostId))
    edge1Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge1Joint1Id))
    edge1Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge1Joint2Id))

    edge2HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge2HostId))
    edge2Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge2Joint1Id))
    edge2Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge2Joint2Id))

    edge3HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge3HostId))
    edge3Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge3Joint1Id))
    edge3Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge3Joint2Id))

    edge4HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge4HostId))
    edge4Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge4Joint1Id))
    edge4Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaEdge4Joint2Id))

    if edge1HostId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        t = clamp(timer / DescendDuration, 0f0, 1f0)
        tipZ = PenTopZ + (Corner1[3] - PenTopZ) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor1)
        place_pen_at_floor_angle(
            state_ptr, Corner1[1], Corner1[2], tipZ, π / 2f0, PenDirX1, PenDirY1)

        timer += dt
        if timer >= DescendDuration
            phase = PhaseTilt1
            timer = 0f0
            place_pen_at_floor_angle(
                state_ptr, Corner1[1], Corner1[2], Corner1[3], π / 2f0, PenDirX1, PenDirY1)
        end
    elseif phase == PhaseTilt1
        t = clamp(timer / TiltDuration, 0f0, 1f0)
        floorAngle = π / 2f0 + (PenTiltFloorAngle - π / 2f0) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor1)
        place_pen_at_floor_angle(
            state_ptr, Corner1[1], Corner1[2], Corner1[3], floorAngle, PenDirX1, PenDirY1)

        timer += dt
        if timer >= TiltDuration
            phase = PhaseDraw1
            timer = 0f0
        end
    elseif phase == PhaseDraw1
        t = clamp(timer / DrawDuration, 0f0, 1f0)

        tipX = Corner1[1] + (Corner2[1] - Corner1[1]) * t
        tipY = Corner1[2] + (Corner2[2] - Corner1[2]) * t
        tipZ = Corner1[3] + (Corner2[3] - Corner1[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor1)
        place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, PenTiltFloorAngle, PenDirX1, PenDirY1)

        EuclidBridge.show_point(state_ptr, edge1HostId)
        EuclidBridge.set_point_color(state_ptr, edge1HostId, LineColor1)
        EuclidBridge.set_point_brush(state_ptr, edge1HostId, LineBrush)
        set_edge_progress(state_ptr, edge1Joint1Id, edge1Joint2Id, Corner1, Corner2, t)
        EuclidBridge.emit_trailing_particle(state_ptr, tipX, tipY, LineColor1)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseStraightenAt2
            timer = 0f0
            set_edge_progress(state_ptr, edge1Joint1Id, edge1Joint2Id, Corner1, Corner2, 1f0)
        end
    elseif phase == PhaseStraightenAt2
        t = clamp(timer / CornerStraightenDuration, 0f0, 1f0)
        floorAngle = PenTiltFloorAngle + (π / 2f0 - PenTiltFloorAngle) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor2)
        place_pen_at_floor_angle(
            state_ptr, Corner2[1], Corner2[2], Corner2[3], floorAngle, PenDirX1, PenDirY1)

        timer += dt
        if timer >= CornerStraightenDuration
            phase = PhaseTilt2
            timer = 0f0
        end
    elseif phase == PhaseTilt2
        t = clamp(timer / TiltDuration, 0f0, 1f0)
        floorAngle = π / 2f0 + (PenTiltFloorAngle - π / 2f0) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor2)
        place_pen_at_floor_angle(
            state_ptr, Corner2[1], Corner2[2], Corner2[3], floorAngle, PenDirX2, PenDirY2)

        timer += dt
        if timer >= TiltDuration
            phase = PhaseDraw2
            timer = 0f0
        end
    elseif phase == PhaseDraw2
        t = clamp(timer / DrawDuration, 0f0, 1f0)

        tipX = Corner2[1] + (Corner3[1] - Corner2[1]) * t
        tipY = Corner2[2] + (Corner3[2] - Corner2[2]) * t
        tipZ = Corner2[3] + (Corner3[3] - Corner2[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor2)
        place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, PenTiltFloorAngle, PenDirX2, PenDirY2)

        EuclidBridge.show_point(state_ptr, edge2HostId)
        EuclidBridge.set_point_color(state_ptr, edge2HostId, LineColor2)
        EuclidBridge.set_point_brush(state_ptr, edge2HostId, LineBrush)
        set_edge_progress(state_ptr, edge2Joint1Id, edge2Joint2Id, Corner2, Corner3, t)
        EuclidBridge.emit_trailing_particle(state_ptr, tipX, tipY, LineColor2)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseStraightenAt3
            timer = 0f0
            set_edge_progress(state_ptr, edge2Joint1Id, edge2Joint2Id, Corner2, Corner3, 1f0)
        end
    elseif phase == PhaseStraightenAt3
        t = clamp(timer / CornerStraightenDuration, 0f0, 1f0)
        floorAngle = PenTiltFloorAngle + (π / 2f0 - PenTiltFloorAngle) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor3)
        place_pen_at_floor_angle(
            state_ptr, Corner3[1], Corner3[2], Corner3[3], floorAngle, PenDirX2, PenDirY2)

        timer += dt
        if timer >= CornerStraightenDuration
            phase = PhaseTilt3
            timer = 0f0
        end
    elseif phase == PhaseTilt3
        t = clamp(timer / TiltDuration, 0f0, 1f0)
        floorAngle = π / 2f0 + (PenTiltFloorAngle - π / 2f0) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor3)
        place_pen_at_floor_angle(
            state_ptr, Corner3[1], Corner3[2], Corner3[3], floorAngle, PenDirX3, PenDirY3)

        timer += dt
        if timer >= TiltDuration
            phase = PhaseDraw3
            timer = 0f0
        end
    elseif phase == PhaseDraw3
        t = clamp(timer / DrawDuration, 0f0, 1f0)

        tipX = Corner3[1] + (Corner4[1] - Corner3[1]) * t
        tipY = Corner3[2] + (Corner4[2] - Corner3[2]) * t
        tipZ = Corner3[3] + (Corner4[3] - Corner3[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor3)
        place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, PenTiltFloorAngle, PenDirX3, PenDirY3)

        EuclidBridge.show_point(state_ptr, edge3HostId)
        EuclidBridge.set_point_color(state_ptr, edge3HostId, LineColor3)
        EuclidBridge.set_point_brush(state_ptr, edge3HostId, LineBrush)
        set_edge_progress(state_ptr, edge3Joint1Id, edge3Joint2Id, Corner3, Corner4, t)
        EuclidBridge.emit_trailing_particle(state_ptr, tipX, tipY, LineColor3)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseStraightenAt4
            timer = 0f0
            set_edge_progress(state_ptr, edge3Joint1Id, edge3Joint2Id, Corner3, Corner4, 1f0)
        end
    elseif phase == PhaseStraightenAt4
        t = clamp(timer / CornerStraightenDuration, 0f0, 1f0)
        floorAngle = PenTiltFloorAngle + (π / 2f0 - PenTiltFloorAngle) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor4)
        place_pen_at_floor_angle(
            state_ptr, Corner4[1], Corner4[2], Corner4[3], floorAngle, PenDirX3, PenDirY3)

        timer += dt
        if timer >= CornerStraightenDuration
            phase = PhaseTilt4
            timer = 0f0
        end
    elseif phase == PhaseTilt4
        t = clamp(timer / TiltDuration, 0f0, 1f0)
        floorAngle = π / 2f0 + (PenTiltFloorAngle - π / 2f0) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor4)
        place_pen_at_floor_angle(
            state_ptr, Corner4[1], Corner4[2], Corner4[3], floorAngle, PenDirX4, PenDirY4)

        timer += dt
        if timer >= TiltDuration
            phase = PhaseDraw4
            timer = 0f0
        end
    elseif phase == PhaseDraw4
        t = clamp(timer / DrawDuration, 0f0, 1f0)

        tipX = Corner4[1] + (Corner1[1] - Corner4[1]) * t
        tipY = Corner4[2] + (Corner1[2] - Corner4[2]) * t
        tipZ = Corner4[3] + (Corner1[3] - Corner4[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor4)
        place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, PenTiltFloorAngle, PenDirX4, PenDirY4)

        EuclidBridge.show_point(state_ptr, edge4HostId)
        EuclidBridge.set_point_color(state_ptr, edge4HostId, LineColor4)
        EuclidBridge.set_point_brush(state_ptr, edge4HostId, LineBrush)
        set_edge_progress(state_ptr, edge4Joint1Id, edge4Joint2Id, Corner4, Corner1, t)
        EuclidBridge.emit_trailing_particle(state_ptr, tipX, tipY, LineColor4)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseStraightenAt1
            timer = 0f0
            set_edge_progress(state_ptr, edge4Joint1Id, edge4Joint2Id, Corner4, Corner1, 1f0)
        end
    elseif phase == PhaseStraightenAt1
        t = clamp(timer / CornerStraightenDuration, 0f0, 1f0)
        floorAngle = PenTiltFloorAngle + (π / 2f0 - PenTiltFloorAngle) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor4)
        place_pen_at_floor_angle(
            state_ptr, Corner1[1], Corner1[2], Corner1[3], floorAngle, PenDirX4, PenDirY4)

        timer += dt
        if timer >= CornerStraightenDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        t = clamp(timer / EndLiftDuration, 0f0, 1f0)
        tipZ = Corner1[3] + (PenTopZ - Corner1[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor1)
        place_pen_at_floor_angle(
            state_ptr, Corner1[1], Corner1[2], tipZ, π / 2f0, PenDirX1, PenDirY1)

        timer += dt
        if timer >= EndLiftDuration
            EuclidBridge.hide_pen(state_ptr)
            place_pen_at_floor_angle(
                state_ptr, Corner1[1], Corner1[2], PenTopZ, π / 2f0, PenDirX1, PenDirY1)
            phase = PhaseHideLines
            timer = 0f0
        end
    elseif phase == PhaseHideLines
        hide_edge_and_collapse(state_ptr, edge1HostId, edge1Joint1Id, edge1Joint2Id, Corner1)
        hide_edge_and_collapse(state_ptr, edge2HostId, edge2Joint1Id, edge2Joint2Id, Corner2)
        hide_edge_and_collapse(state_ptr, edge3HostId, edge3Joint1Id, edge3Joint2Id, Corner3)
        hide_edge_and_collapse(state_ptr, edge4HostId, edge4Joint1Id, edge4Joint2Id, Corner4)

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
