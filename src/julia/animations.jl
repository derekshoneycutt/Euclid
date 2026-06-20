module EuclidAnimations

using ..EuclidBridge

using LinearAlgebra

export animate_pen_descend, animate_pen_rise, animate_compass_descend, animate_compass_rise,
    animate_pen_tilt, animate_pen_cone, animate_pen_drag, animate_pen_arcmove,
    animate_compass_arcmove,
    animate_pen_tilt_and_drag, animate_draw_point, animate_draw_line, animate_draw_filledcircle

const PenLength = 0.14f0

const PenStraightFloorAngle = π / 2f0

const PenDrawLineAngle = π / 3f0

const PenConeRadius = 0.02f0
const PenConeSpinSpeed = 6f0
const PenConeTipHeight = Float32(sqrt(PenLength * PenLength - PenConeRadius * PenConeRadius))
const PenConeFloorAngle = Float32(atan(PenConeTipHeight, PenConeRadius))

const TiltToConeDuration = 0.15f0
const GroundTrailDuration = 0.7f0
const GroundTrailEndTime = TiltToConeDuration + GroundTrailDuration

const TiltToLineDuration = 0.15f0
const GroundLineDuration = 0.7f0
const GroundLineEndTime = TiltToLineDuration + GroundLineDuration

const MarkerRadialTrailSamples = 8f0


function place_pen_at_angles(
    state_ptr::Ptr{Cvoid}, penX::Float32, penY::Float32, baseZ::Float32,
    floorAngle::Float32, azimuth::Float32)

    horizontalLength = PenLength * Float32(cos(floorAngle))
    verticalLength = PenLength * Float32(sin(floorAngle))

    tipX = penX + horizontalLength * Float32(cos(azimuth))
    tipY = penY + horizontalLength * Float32(sin(azimuth))
    tipZ = baseZ + verticalLength

    EuclidBridge.lock_pen_joint1(state_ptr, penX, penY, baseZ)
    EuclidBridge.move_pen_joint2(state_ptr, tipX, tipY, tipZ)
end


function place_pen_at_angles(
    state_ptr::Ptr{Cvoid}, penpos::Vector{Float32},
    floorAngle::Float32, azimuth::Float32)

    place_pen_at_angles(state_ptr, penpos[1], penpos[2], penpos[3], floorAngle, azimuth)
end


function emit_filledcircle_radius_trail(
    state_ptr::Ptr{Cvoid}, jointPoint::Vector{Float32},
    endPoint::Vector{Float32}, color)

    for i in 0:MarkerRadialTrailSamples
        t = (Float32(i) / Float32(MarkerRadialTrailSamples)) +
            Float32(rand() - 0.5f0) / MarkerRadialTrailSamples
        markerpoint = jointPoint + (endPoint - jointPoint) * t
        EuclidBridge.emit_trailing_particle(state_ptr, markerpoint, color)
    end
end



"""
Animate pen descent from a raised Z offset to the drawing plane.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the descend phase.
- topz : Starting Z height above the drawing plane.
- penx : Pen base X position.
- peny : Pen base Y position.

Returns:

- nothing
"""
function animate_pen_descend(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    topz::Float32, penx::Float32, peny::Float32)

    t = clamp(timer / duration, 0f0, 1f0)
    penz = topz - (topz * t)
    EuclidBridge.lock_pen_joint1(state_ptr, penx, peny, penz)
    EuclidBridge.move_pen_joint2(state_ptr, penx, peny, penz + PenLength)
    EuclidBridge.set_pen_active(state_ptr, 0, :white)
    EuclidBridge.show_pen(state_ptr)
end

"""
Animate compass descent from a raised Z offset to the drawing plane.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the descend phase.
- topz : Starting Z height above the drawing plane.
- joint1x : Compass joint 1 X position.
- joint1y : Compass joint 1 Y position.
- joint2x : Compass joint 2 X position.
- joint2y : Compass joint 2 Y position.

Returns:

- nothing
"""
function animate_compass_descend(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    topz::Float32, joint1x::Float32, joint1y::Float32,
    joint2x::Float32, joint2y::Float32)

    t = clamp(timer / duration, 0f0, 1f0)
    tipZ = topz + (0f0 - topz) * t
    EuclidBridge.set_compass_active(state_ptr, 0, :white)
    EuclidBridge.lock_compass_joint1(state_ptr, joint1x, joint1y, tipZ)
    EuclidBridge.lock_compass_joint2(state_ptr, joint2x, joint2y, tipZ)
    EuclidBridge.show_compass(state_ptr)
end

"""
Animate pen rise from the drawing plane to a raised Z offset.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the rise phase.
- topz : Target Z height above the drawing plane.
- penx : Pen base X position.
- peny : Pen base Y position.

Returns:

- nothing
"""
function animate_pen_rise(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    topz::Float32, penx::Float32, peny::Float32)

    t = clamp(timer / duration, 0f0, 1f0)
    penz = topz * t
    EuclidBridge.lock_pen_joint1(state_ptr, penx, peny, penz)
    EuclidBridge.move_pen_joint2(state_ptr, penx, peny, penz + PenLength)
    EuclidBridge.set_pen_active(state_ptr, 0, :white)
    EuclidBridge.show_pen(state_ptr)
end

"""
Animate compass rise from the drawing plane to a raised Z offset.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the rise phase.
- topz : Target Z height above the drawing plane.
- joint1x : Compass joint 1 X position.
- joint1y : Compass joint 1 Y position.
- joint2x : Compass joint 2 X position.
- joint2y : Compass joint 2 Y position.

Returns:

- nothing
"""
function animate_compass_rise(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    topz::Float32, joint1x::Float32, joint1y::Float32,
    joint2x::Float32, joint2y::Float32)

    t = clamp(timer / duration, 0f0, 1f0)
    tipZ = 0f0 + (topz - 0f0) * t

    EuclidBridge.lock_compass_joint1(state_ptr, joint1x, joint1y, tipZ)
    EuclidBridge.lock_compass_joint2(state_ptr, joint2x, joint2y, tipZ)
    EuclidBridge.set_compass_active(state_ptr, 0, :white)
    EuclidBridge.show_compass(state_ptr)
end

"""
Animate pen floor-angle interpolation at a fixed pen base position.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the tilt phase.
- penx : Pen base X position.
- peny : Pen base Y position.
- penz : Pen base Z position.
- startθ : Starting floor angle in radians.
- endθ : Ending floor angle in radians.
- azimuth : Pen azimuth angle in radians.

Returns:

- nothing
"""
function animate_pen_tilt(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    penx::Float32, peny::Float32, penz::Float32,
    startθ::Float32, endθ::Float32, azimuth::Float32)

    animate_pen_tilt(state_ptr, timer, duration, [penx, peny, penz], startθ, endθ, azimuth)
end

function animate_pen_tilt(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    penpos::Vector{Float32},
    startθ::Float32, endθ::Float32, azimuth::Float32)

    t = clamp(timer / duration, 0f0, 1f0)
    floorAngle = startθ + (endθ - startθ) * t

    place_pen_at_angles(state_ptr, penpos, floorAngle, azimuth)
    EuclidBridge.set_pen_active(state_ptr, 0, :white)
    EuclidBridge.show_pen(state_ptr)
end

"""
Animate continuous conical pen motion around a fixed pen base position.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- penx : Pen base X position.
- peny : Pen base Y position.
- penz : Pen base Z position.
- penFloorθ : Pen floor angle in radians.
- spinSpeed : Angular spin speed in radians per second.

Returns:

- nothing
"""
function animate_pen_cone(
    state_ptr::Ptr{Cvoid},
    timer::Float32,
    penx::Float32, peny::Float32, penz::Float32, penFloorθ::Float32,
    spinSpeed::Float32)

    animate_pen_cone(state_ptr, timer, [penx, peny, penz], penFloorθ, spinSpeed)
end

function animate_pen_cone(
    state_ptr::Ptr{Cvoid},
    timer::Float32,
    penpos::Vector{Float32}, penFloorθ::Float32,
    spinSpeed::Float32)

    θ = timer * spinSpeed

    place_pen_at_angles(state_ptr, penpos, penFloorθ, θ)
    EuclidBridge.show_pen(state_ptr)
end

"""
Animate pen drag from start to end while emitting trailing particles.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the drag phase.
- startpos : Starting tip position vector [x, y, z].
- endpos : Ending tip position vector [x, y, z].
- dragθ : Pen floor angle used during drag.
- dragAzimuth : Pen azimuth used during drag.
- color : Trail and active pen color.

Returns:

- tippos : Interpolated pen tip position at time timer.
"""
function animate_pen_drag(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    startpos::Vector{Float32},
    endpos::Vector{Float32},
    dragθ::Float32, dragAzimuth::Float32, color)

    t = clamp(timer / duration, 0f0, 1f0)

    tippos = startpos + (endpos - startpos) * t

    EuclidBridge.show_pen(state_ptr)
    EuclidBridge.set_pen_active(state_ptr, 1, color)
    place_pen_at_angles(state_ptr, tippos, dragθ, dragAzimuth)

    EuclidBridge.emit_trailing_particle(state_ptr, tippos, color)

    return tippos
end

"""
Animate pen transfer along an elevated arc between two positions.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the arc move.
- startpos : Starting position vector [x, y, z].
- endpos : Ending position vector [x, y, z].
- height : Arc peak height scale.
- periods : Number of sinusoidal periods over the move.
- strikecolor : Particle strike color near the floor, or :none.

Returns:

- nothing
"""
function animate_pen_arcmove(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    startpos::Vector{Float32},
    endpos::Vector{Float32},
    height::Float32, periods::Integer, strikecolor)

    t = clamp(timer / duration, 0f0, 1f0)
    EuclidBridge.set_pen_active(state_ptr, 0, :white)

    vec = endpos - startpos
    tvec = t * vec
    tvec[3] = sin(t * periods * π) * height
    usePoint = startpos + tvec
    usePoint[3] = abs(clamp(usePoint[3], -1f0, 1f0))
    place_pen_at_angles(state_ptr, usePoint, π / 2f0, 0f0)
    if usePoint[3] < 0.05 && strikecolor != :none
        EuclidBridge.emit_trailing_particle(state_ptr, usePoint, strikecolor)
    end
end

@inline xy_cross(ax::Float32, ay::Float32, bx::Float32, by::Float32) = ax * by - ay * bx

@inline function point_on_segment_xy(
    a::Vector{Float32}, b::Vector{Float32}, p::Vector{Float32}, eps::Float32)

    return (
        p[1] >= min(a[1], b[1]) - eps && p[1] <= max(a[1], b[1]) + eps &&
        p[2] >= min(a[2], b[2]) - eps && p[2] <= max(a[2], b[2]) + eps
    )
end

@inline function segments_intersect_xy(
    a1::Vector{Float32}, a2::Vector{Float32},
    b1::Vector{Float32}, b2::Vector{Float32})

    eps = 1f-5

    o1 = xy_cross(a2[1] - a1[1], a2[2] - a1[2], b1[1] - a1[1], b1[2] - a1[2])
    o2 = xy_cross(a2[1] - a1[1], a2[2] - a1[2], b2[1] - a1[1], b2[2] - a1[2])
    o3 = xy_cross(b2[1] - b1[1], b2[2] - b1[2], a1[1] - b1[1], a1[2] - b1[2])
    o4 = xy_cross(b2[1] - b1[1], b2[2] - b1[2], a2[1] - b1[1], a2[2] - b1[2])

    if ((o1 > eps && o2 < -eps) || (o1 < -eps && o2 > eps)) &&
       ((o3 > eps && o4 < -eps) || (o3 < -eps && o4 > eps))
        return true
    end

    if abs(o1) <= eps && point_on_segment_xy(a1, a2, b1, eps)
        return true
    end
    if abs(o2) <= eps && point_on_segment_xy(a1, a2, b2, eps)
        return true
    end
    if abs(o3) <= eps && point_on_segment_xy(b1, b2, a1, eps)
        return true
    end
    if abs(o4) <= eps && point_on_segment_xy(b1, b2, a2, eps)
        return true
    end

    return false
end

@inline function avg_radius_to_xy_center(
    startJoint::Vector{Float32}, endJoint::Vector{Float32}, centerX::Float32, centerY::Float32)

    startRadius = hypot(startJoint[1] - centerX, startJoint[2] - centerY)
    endRadius = hypot(endJoint[1] - centerX, endJoint[2] - centerY)
    return (startRadius + endRadius) * 0.5f0
end

@inline function apply_xy_detour_arc!(
    outsidePoint::Vector{Float32},
    outsideStart::Vector{Float32}, outsideEnd::Vector{Float32},
    insideStart::Vector{Float32}, insideEnd::Vector{Float32},
    t::Float32)

    dirX = outsideEnd[1] - outsideStart[1]
    dirY = outsideEnd[2] - outsideStart[2]
    dirLen = hypot(dirX, dirY)
    if dirLen <= 1f-6
        return
    end

    normalX = -dirY / dirLen
    normalY = dirX / dirLen

    relX = outsideStart[1] - insideStart[1]
    relY = outsideStart[2] - insideStart[2]
    side = sign(xy_cross(dirX, dirY, relX, relY))
    if side == 0f0
        side = 1f0
    end

    spanStart = hypot(outsideStart[1] - insideStart[1], outsideStart[2] - insideStart[2])
    spanEnd = hypot(outsideEnd[1] - insideEnd[1], outsideEnd[2] - insideEnd[2])
    avgSpan = (spanStart + spanEnd) * 0.5f0
    arcAmplitude = clamp(avgSpan * 0.15f0, 0.01f0, 0.05f0)

    offset = sin(t * π) * arcAmplitude * side
    outsidePoint[1] += normalX * offset
    outsidePoint[2] += normalY * offset
end

"""
Animate compass transfer along an elevated arc between two joint pairs.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the arc move.
- startJoint1 : Starting position of compass joint 1 [x, y, z].
- endJoint1 : Ending position of compass joint 1 [x, y, z].
- startJoint2 : Starting position of compass joint 2 [x, y, z].
- endJoint2 : Ending position of compass joint 2 [x, y, z].
- height : Arc peak height scale.
- periods : Number of sinusoidal periods over the move.
- strikecolor : Particle strike color near the floor, or :none.

Returns:

- nothing
"""
function animate_compass_arcmove(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    startJoint1::Vector{Float32},
    endJoint1::Vector{Float32},
    startJoint2::Vector{Float32},
    endJoint2::Vector{Float32},
    height::Float32, periods::Integer, strikecolor)

    t = clamp(timer / duration, 0f0, 1f0)
    EuclidBridge.set_compass_active(state_ptr, 0, :white)

    vec1 = endJoint1 - startJoint1
    vec2 = endJoint2 - startJoint2

    tvec1 = t * vec1
    tvec2 = t * vec2

    zArc = sin(t * periods * π) * height
    tvec1[3] = zArc
    tvec2[3] = zArc

    usePoint1 = startJoint1 + tvec1
    usePoint2 = startJoint2 + tvec2

    if segments_intersect_xy(startJoint1, endJoint1, startJoint2, endJoint2)
        centerX = (startJoint1[1] + startJoint2[1] + endJoint1[1] + endJoint2[1]) * 0.25f0
        centerY = (startJoint1[2] + startJoint2[2] + endJoint1[2] + endJoint2[2]) * 0.25f0

        joint1Radius = avg_radius_to_xy_center(startJoint1, endJoint1, centerX, centerY)
        joint2Radius = avg_radius_to_xy_center(startJoint2, endJoint2, centerX, centerY)

        if joint1Radius >= joint2Radius
            apply_xy_detour_arc!(
                usePoint1,
                startJoint1, endJoint1,
                startJoint2, endJoint2,
                t,
            )
        else
            apply_xy_detour_arc!(
                usePoint2,
                startJoint2, endJoint2,
                startJoint1, endJoint1,
                t,
            )
        end
    end

    usePoint1[3] = abs(clamp(usePoint1[3], -1f0, 1f0))
    usePoint2[3] = abs(clamp(usePoint2[3], -1f0, 1f0))

    EuclidBridge.lock_compass_joint1(state_ptr, usePoint1)
    EuclidBridge.lock_compass_joint2(state_ptr, usePoint2)
    EuclidBridge.show_compass(state_ptr)

    if usePoint1[3] < 0.05 && strikecolor != :none
        EuclidBridge.emit_trailing_particle(state_ptr, usePoint1, strikecolor)
        EuclidBridge.emit_trailing_particle(state_ptr, usePoint2, strikecolor)
    end
end

"""
Animate a full line stroke with tilt-in, drag, and tilt-out phases.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the stroke sequence.
- startpos : Starting position vector [x, y, z].
- endpos : Ending position vector [x, y, z].
- color : Stroke and particle color.

Returns:

- nothing
"""
function animate_pen_tilt_and_drag(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    startpos::Vector{Float32}, endpos::Vector{Float32}, color)

    t = clamp(timer / duration, 0f0, 1f0)

    azimuth = Float32(atan(endpos[2] - startpos[2], endpos[1] - startpos[1]))
    if t < TiltToLineDuration
        animate_pen_tilt(
            state_ptr, timer, duration * TiltToLineDuration, startpos,
            PenStraightFloorAngle, PenDrawLineAngle, azimuth)
    elseif t < GroundLineEndTime
        tippos = animate_pen_drag(
            state_ptr, timer - duration * TiltToLineDuration, duration * GroundLineDuration,
            startpos, endpos, PenDrawLineAngle, azimuth, color)

        EuclidBridge.emit_trailing_particle(state_ptr, tippos, color)

        EuclidBridge.set_pen_active(state_ptr, 0, color)
    else
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), endpos,
            PenDrawLineAngle, PenStraightFloorAngle, azimuth)
    end
end

"""
Animate drawing a point with tilt-in, cone contact, and tilt-out phases.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the point draw sequence.
- penpos : Pen base position vector [x, y, z].
- penbrush : Brush size for the point primitive.
- pencolor : Point and trail color.
- pointId : Host point id to update and show.

Returns:

- nothing
"""
function animate_draw_point(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    penpos::Vector{Float32}, penbrush::Float32, pencolor,
    pointId::Integer)

    t = clamp(timer / duration, 0f0, 1f0)

    if t < TiltToConeDuration
        animate_pen_tilt(
            state_ptr, timer, duration * TiltToConeDuration, penpos,
            PenStraightFloorAngle, PenConeFloorAngle, 0f0)
    elseif t < GroundTrailEndTime
        animate_pen_cone(
            state_ptr, timer - duration * TiltToConeDuration,
            penpos, PenConeFloorAngle, PenConeSpinSpeed)

        EuclidBridge.set_point_color(state_ptr, pointId, pencolor)
        EuclidBridge.set_point_position(state_ptr, pointId, penpos)
        EuclidBridge.set_point_brush(state_ptr, pointId, penbrush)
        EuclidBridge.show_point(state_ptr, pointId)

        EuclidBridge.emit_trailing_particle(state_ptr, penpos, pencolor)

        EuclidBridge.set_pen_active(state_ptr, 1, pencolor)
    else
        endAzimuth = (GroundTrailDuration * duration) * PenConeSpinSpeed
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), penpos,
            PenConeFloorAngle, PenStraightFloorAngle, endAzimuth)
    end
end

function animate_draw_point(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    penx::Float32, peny::Float32, penz::Float32, penbrush::Float32, pencolor,
    pointId::Integer)

    animate_draw_point(
        state_ptr, timer, duration, [penx, peny, penz], penbrush, pencolor, pointId)
end

"""
Animate drawing a line primitive with pen motion and endpoint updates.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the line draw sequence.
- startpos : Starting line endpoint vector [x, y, z].
- endpos : Ending line endpoint vector [x, y, z].
- penbrush : Brush size for the line host primitive.
- pencolor : Line and trail color.
- lineHostId : Host point id representing the line primitive.
- lineJoint1Id : Start endpoint control id.
- lineJoint2Id : End endpoint control id.

Returns:

- nothing
"""
function animate_draw_line(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    startpos::Vector{Float32}, endpos::Vector{Float32},
    penbrush::Float32, pencolor,
    lineHostId::Integer, lineJoint1Id::Integer, lineJoint2Id::Integer)

    t = clamp(timer / duration, 0f0, 1f0)

    azimuth = Float32(atan(endpos[2] - startpos[2], endpos[1] - startpos[1]))
    if t < TiltToLineDuration
        animate_pen_tilt(
            state_ptr, timer, duration * TiltToLineDuration, startpos,
            PenStraightFloorAngle, PenDrawLineAngle, azimuth)
    elseif t < GroundLineEndTime
        tippos = animate_pen_drag(
            state_ptr, timer - duration * TiltToLineDuration, duration * GroundLineDuration,
            startpos, endpos, PenDrawLineAngle, azimuth, pencolor)

        EuclidBridge.set_point_color(state_ptr, lineHostId, pencolor)
        EuclidBridge.set_point_brush(state_ptr, lineHostId, penbrush)
        EuclidBridge.set_point_position(state_ptr, lineJoint1Id, startpos)
        EuclidBridge.set_point_position(state_ptr, lineJoint2Id, tippos)
        EuclidBridge.show_point(state_ptr, lineHostId)

        EuclidBridge.emit_trailing_particle(state_ptr, tippos, pencolor)

        EuclidBridge.set_pen_active(state_ptr, 1, pencolor)
    else
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), endpos,
            PenDrawLineAngle, PenStraightFloorAngle, azimuth)
    end
end

"""
Animate drawing a circle sector using compass motion.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the circle draw sequence.
- jointPoint : Compass pivot position vector [x, y, z].
- startPoint : Marker start point vector [x, y, z].
- angleTheta : Sweep angle in radians.
- radius : Marker radius.
- brush : Brush size for the marker host primitive.
- color : Marker and trail color.
- markerHostId : Host id for the filled marker primitive.
- markerStartId : Start control point id for marker geometry.
- markerEndId : End control point id for marker geometry.

Returns:

- nothing
"""
function animate_draw_circle(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    jointPoint::Vector{Float32}, startPoint::Vector{Float32},
    angleTheta::Float32, radius::Float32, brush::Float32, color,
    markerHostId::Integer, markerStartId::Integer, markerEndId::Integer,)

    t = clamp(timer / duration, 0f0, 1f0)
    startTheta = Float32(atan(startPoint[2] - jointPoint[2], startPoint[1] - jointPoint[1]))
    theta = startTheta + angleTheta * t

    endPoint = [
        jointPoint[1] + radius * Float32(cos(theta)),
        jointPoint[2] + radius * Float32(sin(theta)),
        0f0]

    EuclidBridge.lock_compass_joint1(state_ptr, jointPoint)
    EuclidBridge.set_compass_active(state_ptr, 3, color)
    EuclidBridge.lock_compass_joint2(state_ptr, endPoint)
    EuclidBridge.show_compass(state_ptr)

    EuclidBridge.set_point_color(state_ptr, markerHostId, color)
    EuclidBridge.set_point_brush(state_ptr, markerHostId, brush)
    EuclidBridge.set_point_position(state_ptr, markerStartId, startPoint)
    EuclidBridge.set_point_position(state_ptr, markerEndId, endPoint)
    EuclidBridge.show_point(state_ptr, markerHostId)

    EuclidBridge.emit_trailing_particle(state_ptr, endPoint, color)
end

"""
Animate drawing a filled circular sector marker using compass motion.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the marker draw sequence.
- jointPoint : Compass pivot position vector [x, y, z].
- startPoint : Marker start point vector [x, y, z].
- angleTheta : Sweep angle in radians.
- radius : Marker radius.
- brush : Brush size for the marker host primitive.
- color : Marker and trail color.
- markerHostId : Host id for the filled marker primitive.
- markerStartId : Start control point id for marker geometry.
- markerEndId : End control point id for marker geometry.

Returns:

- nothing
"""
function animate_draw_filledcircle(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    jointPoint::Vector{Float32}, startPoint::Vector{Float32},
    angleTheta::Float32, radius::Float32, brush::Float32, color,
    markerHostId::Integer, markerStartId::Integer, markerEndId::Integer,)

    t = clamp(timer / duration, 0f0, 1f0)
    startTheta = Float32(atan(startPoint[2] - jointPoint[2], startPoint[1] - jointPoint[1]))
    theta = startTheta + angleTheta * t

    endPoint = [
        jointPoint[1] + radius * Float32(cos(theta)),
        jointPoint[2] + radius * Float32(sin(theta)),
        0f0]

    EuclidBridge.lock_compass_joint1(state_ptr, jointPoint)
    EuclidBridge.set_compass_active(state_ptr, 3, color)
    EuclidBridge.lock_compass_joint2(state_ptr, endPoint)
    EuclidBridge.show_compass(state_ptr)

    EuclidBridge.set_point_color(state_ptr, markerHostId, color)
    EuclidBridge.set_point_brush(state_ptr, markerHostId, brush)
    EuclidBridge.set_point_position(state_ptr, markerStartId, startPoint)
    EuclidBridge.set_point_position(state_ptr, markerEndId, endPoint)
    EuclidBridge.show_point(state_ptr, markerHostId)

    emit_filledcircle_radius_trail(state_ptr, jointPoint, endPoint, color)
end

end
