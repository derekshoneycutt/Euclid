module ElementsOneDefinitionPlaneAngle

using LinearAlgebra

include("../../euclidbridge.jl")

export get_view_text, initialize, clean, loop

const JointPoint = [0.30f0, 0.30f0, 0f0]
const LineLength = 0.55f0
const AngleTheta = π / 4f0

const Line1Start = JointPoint
const Line1End = [JointPoint[1] + LineLength, JointPoint[2], 0f0]
const Line2Start = JointPoint
const Line2End = [
    JointPoint[1] + LineLength * Float32(cos(AngleTheta)),
    JointPoint[2] + LineLength * Float32(sin(AngleTheta)),
    0f0,
]

const MarkerRadius = 0.20f0
const MarkerStart = [JointPoint[1] + MarkerRadius, JointPoint[2], 0f0]

const LineColor1 = :steelblue
const LineColor2 = :palevioletred1
const MarkerColor = :khaki3
const LineMaxBrush = 5f0
const MarkerBrush = 1f0
const MarkerRadialTrailSamples = 8f0

const PenTopZ = 1.4f0
const PenLength = 0.14f0
const PenTiltFloorAngle = π / 4f0

const CompassTopZ = 1.4f0

const DescendDuration = 1.8f0
const TiltDuration = 0.8f0
const DrawDuration = 2.2f0
const CornerStraightenDuration = 0.6f0
const ArcMoveDuration = 2.0f0
const ArcMoveHeight = 0.28f0
const EndLiftDuration = 1.6f0
const CompassDescendDuration = 1.4f0
const CompassDrawDuration = 1.25f0
const CompassLiftDuration = 1.4f0
const HidePauseDuration = 0.6f0

const SegmentVec1 = Line1End - Line1Start
const SegmentVecLen1 = norm(SegmentVec1)
const PenDirX1 = SegmentVecLen1 > 0f0 ? SegmentVec1[1] / SegmentVecLen1 : 1f0
const PenDirY1 = SegmentVecLen1 > 0f0 ? SegmentVec1[2] / SegmentVecLen1 : 0f0

const SegmentVec2 = Line2End - Line2Start
const SegmentVecLen2 = norm(SegmentVec2)
const PenDirX2 = SegmentVecLen2 > 0f0 ? SegmentVec2[1] / SegmentVecLen2 : 1f0
const PenDirY2 = SegmentVecLen2 > 0f0 ? SegmentVec2[2] / SegmentVecLen2 : 0f0

const MetaLine1HostId = 1
const MetaLine1Joint1Id = 2
const MetaLine1Joint2Id = 3
const MetaLine2HostId = 4
const MetaLine2Joint1Id = 5
const MetaLine2Joint2Id = 6
const MetaMarkerHostId = 7
const MetaMarkerStartId = 8
const MetaMarkerEndId = 9
const MetaPhase = 10
const MetaTimer = 11

const PhasePenDescend = 0f0
const PhasePenTilt1 = 1f0
const PhasePenDraw1 = 2f0
const PhasePenStraightenAtJoint = 3f0
const PhasePenArcToPivot = 4f0
const PhasePenTilt2 = 5f0
const PhasePenDraw2 = 6f0
const PhasePenStraightenAtEnd = 7f0
const PhasePenLift = 8f0
const PhaseCompassDescend = 9f0
const PhaseCompassDrawMarker = 10f0
const PhaseCompassLift = 11f0
const PhaseHideAll = 12f0

function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Plane Angle:

A plane angle is the inclination to one another of two lines in a plane which meet one another and do not lie in a straight line.

And when the lines containing the angle are straight, the angle is called rectilinear."""
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

function show_full_line(
    state_ptr::Ptr{Cvoid}, hostId::Integer, joint1Id::Integer, joint2Id::Integer,
    startPoint::Vector{Float32}, endPoint::Vector{Float32}, lineColor)

    EuclidBridge.show_point(state_ptr, hostId)
    EuclidBridge.set_point_color(state_ptr, hostId, lineColor)
    EuclidBridge.set_point_brush(state_ptr, hostId, LineMaxBrush)
    EuclidBridge.set_point_position(
        state_ptr, joint1Id, startPoint[1], startPoint[2], startPoint[3])
    EuclidBridge.set_point_position(
        state_ptr, joint2Id, endPoint[1], endPoint[2], endPoint[3])
end

function hide_line(
    state_ptr::Ptr{Cvoid}, hostId::Integer, joint1Id::Integer, joint2Id::Integer,
    collapsePoint::Vector{Float32})

    EuclidBridge.hide_point(state_ptr, hostId)
    EuclidBridge.set_point_position(
        state_ptr, joint1Id, collapsePoint[1], collapsePoint[2], collapsePoint[3])
    EuclidBridge.set_point_position(
        state_ptr, joint2Id, collapsePoint[1], collapsePoint[2], collapsePoint[3])
end

function hide_marker(
    state_ptr::Ptr{Cvoid}, markerHostId::Integer, markerStartId::Integer, markerEndId::Integer)

    EuclidBridge.hide_point(state_ptr, markerHostId)
    EuclidBridge.set_point_position(
        state_ptr, markerStartId, MarkerStart[1], MarkerStart[2], MarkerStart[3])
    EuclidBridge.set_point_position(
        state_ptr, markerEndId, MarkerStart[1], MarkerStart[2], MarkerStart[3])
end

function update_marker(
    state_ptr::Ptr{Cvoid}, markerHostId::Integer, markerStartId::Integer, markerEndId::Integer,
    theta::Float32)

    endX = JointPoint[1] + MarkerRadius * Float32(cos(theta))
    endY = JointPoint[2] + MarkerRadius * Float32(sin(theta))

    EuclidBridge.show_point(state_ptr, markerHostId)
    EuclidBridge.set_point_color(state_ptr, markerHostId, MarkerColor)
    EuclidBridge.set_point_brush(state_ptr, markerHostId, MarkerBrush)
    EuclidBridge.set_point_position(
        state_ptr, markerStartId, MarkerStart[1], MarkerStart[2], MarkerStart[3])
    EuclidBridge.set_point_position(
        state_ptr, markerEndId, endX, endY, 0f0)
end

function emit_marker_radius_trail(state_ptr::Ptr{Cvoid}, endX::Float32, endY::Float32)
    for i in 0:MarkerRadialTrailSamples
        t = (Float32(i) / Float32(MarkerRadialTrailSamples)) +
            Float32(2f0 * rand() - 1f0) / MarkerRadialTrailSamples
        markerpoint = JointPoint + ([endX, endY, JointPoint[3]] - JointPoint) * t
        EuclidBridge.emit_trailing_particle(state_ptr, markerpoint[1], markerpoint[2], MarkerColor)
    end
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1Joint1Id))
    line1Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2Joint1Id))
    line2Joint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    markerHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    markerStartId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerStartId))
    markerEndId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerEndId))

    hide_marker(state_ptr, markerHostId, markerStartId, markerEndId)
    hide_line(state_ptr, line2HostId, line2Joint1Id, line2Joint2Id, Line2Start)
    hide_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start)

    EuclidBridge.hide_compass(state_ptr)
    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 0, LineColor1)
    EuclidBridge.set_compass_active(state_ptr, 0, LineColor1)
    EuclidBridge.lock_compass_joint1(state_ptr, JointPoint[1], JointPoint[2], CompassTopZ)
    EuclidBridge.lock_compass_joint2(state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ)
    place_pen_at_floor_angle(
        state_ptr, Line1Start[1], Line1Start[2], PenTopZ, π / 2f0, PenDirX1, PenDirY1)

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)
end

function initialize(state_ptr::Ptr{Cvoid})
    marker = EuclidBridge.create_new_filledcircle(
        state_ptr,
        JointPoint[1], JointPoint[2], JointPoint[3],
        MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)
    line1 = EuclidBridge.create_new_line(
        state_ptr,
        Line1Start[1], Line1Start[2], Line1Start[3],
        Line1Start[1], Line1Start[2], Line1Start[3],
        LineColor1, 0f0)
    line2 = EuclidBridge.create_new_line(
        state_ptr,
        Line2Start[1], Line2Start[2], Line2Start[3],
        Line2Start[1], Line2Start[2], Line2Start[3],
        LineColor2, 0f0)

    EuclidBridge.set_animation_meta(state_ptr, MetaLine1HostId, Float32(line1.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, Float32(line1.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, Float32(line1.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaLine2HostId, Float32(line2.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, Float32(line2.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, Float32(line2.joint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaMarkerHostId, Float32(marker.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaMarkerStartId, Float32(marker.startId))
    EuclidBridge.set_animation_meta(state_ptr, MetaMarkerEndId, Float32(marker.endId))

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

    markerHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerHostId))
    markerStartId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerStartId))
    markerEndId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaMarkerEndId))

    if line1HostId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhasePenDescend
        t = clamp(timer / DescendDuration, 0f0, 1f0)
        tipZ = PenTopZ + (Line1Start[3] - PenTopZ) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor1)
        place_pen_at_floor_angle(state_ptr, Line1Start[1], Line1Start[2], tipZ, π / 2f0, PenDirX1, PenDirY1)

        timer += dt
        if timer >= DescendDuration
            phase = PhasePenTilt1
            timer = 0f0
            place_pen_at_floor_angle(state_ptr, Line1Start[1], Line1Start[2], Line1Start[3], π / 2f0, PenDirX1, PenDirY1)
        end
    elseif phase == PhasePenTilt1
        t = clamp(timer / TiltDuration, 0f0, 1f0)
        floorAngle = π / 2f0 + (PenTiltFloorAngle - π / 2f0) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor1)
        place_pen_at_floor_angle(state_ptr, Line1Start[1], Line1Start[2], Line1Start[3], floorAngle, PenDirX1, PenDirY1)

        timer += dt
        if timer >= TiltDuration
            phase = PhasePenDraw1
            timer = 0f0
        end
    elseif phase == PhasePenDraw1
        t = clamp(timer / DrawDuration, 0f0, 1f0)

        tipX = Line1Start[1] + (Line1End[1] - Line1Start[1]) * t
        tipY = Line1Start[2] + (Line1End[2] - Line1Start[2]) * t
        tipZ = Line1Start[3] + (Line1End[3] - Line1Start[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor1)
        place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, PenTiltFloorAngle, PenDirX1, PenDirY1)

        EuclidBridge.show_point(state_ptr, line1HostId)
        EuclidBridge.set_point_color(state_ptr, line1HostId, LineColor1)
        EuclidBridge.set_point_brush(state_ptr, line1HostId, LineMaxBrush)
        EuclidBridge.set_point_position(state_ptr, line1Joint1Id, Line1Start[1], Line1Start[2], Line1Start[3])
        EuclidBridge.set_point_position(state_ptr, line1Joint2Id, tipX, tipY, tipZ)
        EuclidBridge.emit_trailing_particle(state_ptr, tipX, tipY, LineColor1)

        timer += dt
        if timer >= DrawDuration
            phase = PhasePenStraightenAtJoint
            timer = 0f0
            show_full_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start, Line1End, LineColor1)
        end
    elseif phase == PhasePenStraightenAtJoint
        t = clamp(timer / CornerStraightenDuration, 0f0, 1f0)
        floorAngle = PenTiltFloorAngle + (π / 2f0 - PenTiltFloorAngle) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor2)
        place_pen_at_floor_angle(state_ptr, Line1End[1], Line1End[2], Line1End[3], floorAngle, PenDirX1, PenDirY1)

        show_full_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start, Line1End, LineColor1)

        timer += dt
        if timer >= CornerStraightenDuration
            phase = PhasePenArcToPivot
            timer = 0f0
        end
    elseif phase == PhasePenArcToPivot
        t = clamp(timer / ArcMoveDuration, 0f0, 1f0)

        tipX = Line1End[1] + (JointPoint[1] - Line1End[1]) * t
        tipY = Line1End[2] + (JointPoint[2] - Line1End[2]) * t
        baseZ = Line1End[3] + (JointPoint[3] - Line1End[3]) * t
        tipZ = baseZ + ArcMoveHeight * Float32(sin(π * t))

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor2)
        place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, π / 2f0, PenDirX1, PenDirY1)

        show_full_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start, Line1End, LineColor1)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePenTilt2
            timer = 0f0
            place_pen_at_floor_angle(state_ptr, JointPoint[1], JointPoint[2], JointPoint[3], π / 2f0, PenDirX2, PenDirY2)
        end
    elseif phase == PhasePenTilt2
        t = clamp(timer / TiltDuration, 0f0, 1f0)
        floorAngle = π / 2f0 + (PenTiltFloorAngle - π / 2f0) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor2)
        place_pen_at_floor_angle(state_ptr, JointPoint[1], JointPoint[2], JointPoint[3], floorAngle, PenDirX2, PenDirY2)

        show_full_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start, Line1End, LineColor1)

        timer += dt
        if timer >= TiltDuration
            phase = PhasePenDraw2
            timer = 0f0
        end
    elseif phase == PhasePenDraw2
        t = clamp(timer / DrawDuration, 0f0, 1f0)

        tipX = Line2Start[1] + (Line2End[1] - Line2Start[1]) * t
        tipY = Line2Start[2] + (Line2End[2] - Line2Start[2]) * t
        tipZ = Line2Start[3] + (Line2End[3] - Line2Start[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 1, LineColor2)
        place_pen_at_floor_angle(state_ptr, tipX, tipY, tipZ, PenTiltFloorAngle, PenDirX2, PenDirY2)

        show_full_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start, Line1End, LineColor1)
        EuclidBridge.show_point(state_ptr, line2HostId)
        EuclidBridge.set_point_color(state_ptr, line2HostId, LineColor2)
        EuclidBridge.set_point_brush(state_ptr, line2HostId, LineMaxBrush)
        EuclidBridge.set_point_position(state_ptr, line2Joint1Id, Line2Start[1], Line2Start[2], Line2Start[3])
        EuclidBridge.set_point_position(state_ptr, line2Joint2Id, tipX, tipY, tipZ)
        EuclidBridge.emit_trailing_particle(state_ptr, tipX, tipY, LineColor2)

        timer += dt
        if timer >= DrawDuration
            phase = PhasePenStraightenAtEnd
            timer = 0f0
            show_full_line(state_ptr, line2HostId, line2Joint1Id, line2Joint2Id, Line2Start, Line2End, LineColor2)
        end
    elseif phase == PhasePenStraightenAtEnd
        t = clamp(timer / CornerStraightenDuration, 0f0, 1f0)
        floorAngle = PenTiltFloorAngle + (π / 2f0 - PenTiltFloorAngle) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor2)
        place_pen_at_floor_angle(state_ptr, Line2End[1], Line2End[2], Line2End[3], floorAngle, PenDirX2, PenDirY2)

        show_full_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start, Line1End, LineColor1)
        show_full_line(state_ptr, line2HostId, line2Joint1Id, line2Joint2Id, Line2Start, Line2End, LineColor2)

        timer += dt
        if timer >= CornerStraightenDuration
            phase = PhasePenLift
            timer = 0f0
        end
    elseif phase == PhasePenLift
        t = clamp(timer / EndLiftDuration, 0f0, 1f0)
        tipZ = Line2End[3] + (PenTopZ - Line2End[3]) * t

        EuclidBridge.show_pen(state_ptr)
        EuclidBridge.set_pen_active(state_ptr, 0, LineColor2)
        place_pen_at_floor_angle(state_ptr, Line2End[1], Line2End[2], tipZ, π / 2f0, PenDirX2, PenDirY2)

        show_full_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start, Line1End, LineColor1)
        show_full_line(state_ptr, line2HostId, line2Joint1Id, line2Joint2Id, Line2Start, Line2End, LineColor2)

        timer += dt
        if timer >= EndLiftDuration
            EuclidBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescend
            timer = 0f0
        end
    elseif phase == PhaseCompassDescend
        t = clamp(timer / CompassDescendDuration, 0f0, 1f0)
        tipZ = CompassTopZ + (0f0 - CompassTopZ) * t

        EuclidBridge.show_compass(state_ptr)
        EuclidBridge.set_compass_active(state_ptr, 0, MarkerColor)
        EuclidBridge.lock_compass_joint1(state_ptr, JointPoint[1], JointPoint[2], tipZ)
        EuclidBridge.lock_compass_joint2(state_ptr, MarkerStart[1], MarkerStart[2], tipZ)

        show_full_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start, Line1End, LineColor1)
        show_full_line(state_ptr, line2HostId, line2Joint1Id, line2Joint2Id, Line2Start, Line2End, LineColor2)

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseCompassDrawMarker
            timer = 0f0
            EuclidBridge.lock_compass_joint1(state_ptr, JointPoint[1], JointPoint[2], 0f0)
            EuclidBridge.move_compass_joint2(state_ptr, MarkerStart[1], MarkerStart[2], 0f0)
        end
    elseif phase == PhaseCompassDrawMarker
        t = clamp(timer / CompassDrawDuration, 0f0, 1f0)
        theta = AngleTheta * t

        endX = JointPoint[1] + MarkerRadius * Float32(cos(theta))
        endY = JointPoint[2] + MarkerRadius * Float32(sin(theta))

        EuclidBridge.show_compass(state_ptr)
        EuclidBridge.set_compass_active(state_ptr, 3, MarkerColor)
        EuclidBridge.lock_compass_joint1(state_ptr, JointPoint[1], JointPoint[2], 0f0)
        EuclidBridge.lock_compass_joint2(state_ptr, endX, endY, 0f0)

        show_full_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start, Line1End, LineColor1)
        show_full_line(state_ptr, line2HostId, line2Joint1Id, line2Joint2Id, Line2Start, Line2End, LineColor2)
        update_marker(state_ptr, markerHostId, markerStartId, markerEndId, theta)
        emit_marker_radius_trail(state_ptr, endX, endY)

        timer += dt
        if timer >= CompassDrawDuration
            phase = PhaseCompassLift
            timer = 0f0
            update_marker(state_ptr, markerHostId, markerStartId, markerEndId, AngleTheta)
        end
    elseif phase == PhaseCompassLift
        t = clamp(timer / CompassLiftDuration, 0f0, 1f0)
        tipZ = 0f0 + (CompassTopZ - 0f0) * t

        endX = JointPoint[1] + MarkerRadius * Float32(cos(AngleTheta))
        endY = JointPoint[2] + MarkerRadius * Float32(sin(AngleTheta))

        EuclidBridge.show_compass(state_ptr)
        EuclidBridge.set_compass_active(state_ptr, 0, MarkerColor)
        EuclidBridge.lock_compass_joint1(state_ptr, JointPoint[1], JointPoint[2], tipZ)
        EuclidBridge.lock_compass_joint2(state_ptr, endX, endY, tipZ)

        show_full_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start, Line1End, LineColor1)
        show_full_line(state_ptr, line2HostId, line2Joint1Id, line2Joint2Id, Line2Start, Line2End, LineColor2)
        update_marker(state_ptr, markerHostId, markerStartId, markerEndId, AngleTheta)

        timer += dt
        if timer >= CompassLiftDuration
            EuclidBridge.hide_compass(state_ptr)
            phase = PhaseHideAll
            timer = 0f0
        end
    elseif phase == PhaseHideAll
        hide_marker(state_ptr, markerHostId, markerStartId, markerEndId)
        hide_line(state_ptr, line2HostId, line2Joint1Id, line2Joint2Id, Line2Start)
        hide_line(state_ptr, line1HostId, line1Joint1Id, line1Joint2Id, Line1Start)

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
