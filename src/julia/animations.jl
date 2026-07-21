"""
Reusable animation-motion helpers for EuclidApp scripts.

`EuclidAnimations` provides shared pen/compass motion primitives and higher-level
draw helpers that orchestrate bridge calls through `OdinJuliaBridge`. Animation
modules should consume this API to keep motion pacing and tool behavior consistent
across Euclid content and scratchpad workflows.
"""
module EuclidAnimations

using ..OdinJuliaBridge

using LinearAlgebra

export animate_pen_descend, animate_pen_rise, animate_compass_descend, animate_compass_rise,
    animate_pen_tilt, animate_pen_cone, animate_pen_drag, animate_pen_arcmove,
    animate_compass_arcmove, animate_highlight_point, animate_extend_line,
    animate_pen_tilt_and_drag, animate_draw_point, animate_draw_line, animate_draw_filledcircle,
    animate_draw_circle, animate_compass_fill_arc_highlight,
    animate_repl_draw_point, animate_repl_draw_line,
    animate_repl_draw_circle, animate_repl_draw_filledcircle

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

const ReplToolTravelTopZ = 1.4f0
const ReplDescendShare = 0.2f0
const ReplDrawShare = 0.6f0


function place_pen_at_angles(
    state_ptr::Ptr{Cvoid}, penX::Float32, penY::Float32, baseZ::Float32,
    floorAngle::Float32, azimuth::Float32)

    horizontalLength = PenLength * Float32(cos(floorAngle))
    verticalLength = PenLength * Float32(sin(floorAngle))

    tipX = penX + horizontalLength * Float32(cos(azimuth))
    tipY = penY + horizontalLength * Float32(sin(azimuth))
    tipZ = baseZ + verticalLength

    OdinJuliaBridge.lock_pen_joint1(state_ptr, penX, penY, baseZ)
    OdinJuliaBridge.move_pen_joint2(state_ptr, tipX, tipY, tipZ)
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
        OdinJuliaBridge.emit_trailing_particle(state_ptr, markerpoint, color)
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
    OdinJuliaBridge.lock_pen_joint1(state_ptr, penx, peny, penz)
    OdinJuliaBridge.move_pen_joint2(state_ptr, penx, peny, penz + PenLength)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, :white)
    OdinJuliaBridge.show_pen(state_ptr)
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
    OdinJuliaBridge.set_compass_active(state_ptr, 0, :white)
    OdinJuliaBridge.lock_compass_joint1(state_ptr, joint1x, joint1y, tipZ, sweep = false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, joint2x, joint2y, tipZ, sweep = false)
    OdinJuliaBridge.show_compass(state_ptr)
end

"""
Animate pen rise from the drawing plane to a raised Z offset.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the rise phase.
- startz : Start Z height above the drawing plane where the pen begins.
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
    OdinJuliaBridge.lock_pen_joint1(state_ptr, penx, peny, penz)
    OdinJuliaBridge.move_pen_joint2(state_ptr, penx, peny, penz + PenLength)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, :white)
    OdinJuliaBridge.show_pen(state_ptr)
end
function animate_pen_rise(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    startz::Float32, topz::Float32, penx::Float32, peny::Float32)

    t = clamp(timer / duration, 0f0, 1f0)
    diffz = topz - startz
    penzoffset = diffz * t
    penz = startz + penzoffset
    OdinJuliaBridge.lock_pen_joint1(state_ptr, penx, peny, penz)
    OdinJuliaBridge.move_pen_joint2(state_ptr, penx, peny, penz + PenLength)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, :white)
    OdinJuliaBridge.show_pen(state_ptr)
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

    OdinJuliaBridge.lock_compass_joint1(state_ptr, joint1x, joint1y, tipZ, sweep = false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, joint2x, joint2y, tipZ, sweep = false)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, :white)
    OdinJuliaBridge.show_compass(state_ptr)
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
    OdinJuliaBridge.set_pen_active(state_ptr, 0, :white)
    OdinJuliaBridge.show_pen(state_ptr)
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
    OdinJuliaBridge.show_pen(state_ptr)
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

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 1, color)
    place_pen_at_angles(state_ptr, tippos, dragθ, dragAzimuth)

    OdinJuliaBridge.emit_trailing_particle(state_ptr, tippos, color)

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
    OdinJuliaBridge.set_pen_active(state_ptr, 0, :white)

    vec = endpos - startpos
    tvec = t * vec
    offsetz = abs(clamp(sin(t * periods * π) * height, -1f0, 1f0))
    tvec[3] = tvec[3] + offsetz
    usePoint = startpos + tvec
    place_pen_at_angles(state_ptr, usePoint, π / 2f0, 0f0)
    if usePoint[3] < 0.05 && strikecolor != :none
        particlePoint = [usePoint[1], usePoint[2], 0f0]
        OdinJuliaBridge.emit_trailing_particle(state_ptr, particlePoint, strikecolor)
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

@inline function has_collinear_segment_overlap_xy(
    a1::Vector{Float32}, a2::Vector{Float32},
    b1::Vector{Float32}, b2::Vector{Float32},
    o1::Float32, o2::Float32, o3::Float32, o4::Float32,
    eps::Float32)

    return (
        (abs(o1) <= eps && point_on_segment_xy(a1, a2, b1, eps)) ||
        (abs(o2) <= eps && point_on_segment_xy(a1, a2, b2, eps)) ||
        (abs(o3) <= eps && point_on_segment_xy(b1, b2, a1, eps)) ||
        (abs(o4) <= eps && point_on_segment_xy(b1, b2, a2, eps))
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

    return has_collinear_segment_overlap_xy(a1, a2, b1, b2, o1, o2, o3, o4, eps)
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
    OdinJuliaBridge.set_compass_active(state_ptr, 0, :white)

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

    OdinJuliaBridge.lock_compass_joint1(state_ptr, usePoint1; sweep = false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, usePoint2; sweep = false)
    OdinJuliaBridge.show_compass(state_ptr)

    if usePoint1[3] < 0.05 && strikecolor != :none
        OdinJuliaBridge.emit_trailing_particle(state_ptr, usePoint1, strikecolor)
        OdinJuliaBridge.emit_trailing_particle(state_ptr, usePoint2, strikecolor)
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

        OdinJuliaBridge.emit_trailing_particle(state_ptr, tippos, color)

        OdinJuliaBridge.set_pen_active(state_ptr, 0, color)
    else
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), endpos,
            PenDrawLineAngle, PenStraightFloorAngle, azimuth)
    end
end

"""
Animate highlighting a point with tilt-in, cone contact, and tilt-out phases.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the point draw sequence.
- penpos : Pen base position vector [x, y, z].
- pencolor : Point and trail color.

Returns:

- nothing
"""
function animate_highlight_point(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    penpos::Vector{Float32}, pencolor)

    t = clamp(timer / duration, 0f0, 1f0)

    if t < TiltToConeDuration
        animate_pen_tilt(
            state_ptr, timer, duration * TiltToConeDuration, penpos,
            PenStraightFloorAngle, PenConeFloorAngle, 0f0)
    elseif t < GroundTrailEndTime
        animate_pen_cone(
            state_ptr, timer - duration * TiltToConeDuration,
            penpos, PenConeFloorAngle, PenConeSpinSpeed)

        OdinJuliaBridge.emit_trailing_particle(state_ptr, penpos, pencolor)

        OdinJuliaBridge.set_pen_active(state_ptr, 1, pencolor)
    else
        endAzimuth = (GroundTrailDuration * duration) * PenConeSpinSpeed
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), penpos,
            PenConeFloorAngle, PenStraightFloorAngle, endAzimuth)
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

        OdinJuliaBridge.set_point_color(state_ptr, pointId, pencolor)
        OdinJuliaBridge.set_point_position(state_ptr, pointId, penpos)
        OdinJuliaBridge.set_point_brush(state_ptr, pointId, penbrush)
        OdinJuliaBridge.show_point(state_ptr, pointId)

        OdinJuliaBridge.emit_trailing_particle(state_ptr, penpos, pencolor)

        OdinJuliaBridge.set_pen_active(state_ptr, 1, pencolor)
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

        OdinJuliaBridge.set_point_color(state_ptr, lineHostId, pencolor)
        OdinJuliaBridge.set_point_brush(state_ptr, lineHostId, penbrush)
        OdinJuliaBridge.set_point_position(state_ptr, lineJoint1Id, startpos)
        OdinJuliaBridge.set_point_position(state_ptr, lineJoint2Id, tippos)
        OdinJuliaBridge.show_point(state_ptr, lineHostId)

        OdinJuliaBridge.emit_trailing_particle(state_ptr, tippos, pencolor)

        OdinJuliaBridge.set_pen_active(state_ptr, 1, pencolor)
    else
        animate_pen_tilt(
            state_ptr, timer - duration * GroundTrailEndTime,
            duration * (1f0 - GroundTrailEndTime), endpos,
            PenDrawLineAngle, PenStraightFloorAngle, azimuth)
    end
end

"""
Animate extending drawing a line primitive with pen motion and endpoint updates.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the line draw sequence.
- startpos : Starting line endpoint vector [x, y, z].
- midpos : Starting line endpoint vector for the extension (the previous endpos) [x, y, z].
- endpos : Ending line endpoint vector [x, y, z].
- penbrush : Brush size for the line host primitive.
- pencolor : Line and trail color.
- lineHostId : Host point id representing the line primitive.
- lineJoint1Id : Start endpoint control id.
- lineJoint2Id : End endpoint control id.

Returns:

- nothing
"""
function animate_extend_line(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    startpos::Vector{Float32}, midpos::Vector{Float32}, endpos::Vector{Float32},
    penbrush::Float32, pencolor,
    lineHostId::Integer, lineJoint1Id::Integer, lineJoint2Id::Integer)

    t = clamp(timer / duration, 0f0, 1f0)

    azimuth = Float32(atan(endpos[2] - startpos[2], endpos[1] - startpos[1]))
    if t < TiltToLineDuration
        animate_pen_tilt(
            state_ptr, timer, duration * TiltToLineDuration, midpos,
            PenStraightFloorAngle, PenDrawLineAngle, azimuth)
    elseif t < GroundLineEndTime
        tippos = animate_pen_drag(
            state_ptr, timer - duration * TiltToLineDuration, duration * GroundLineDuration,
            midpos, endpos, PenDrawLineAngle, azimuth, pencolor)

        OdinJuliaBridge.set_point_color(state_ptr, lineHostId, pencolor)
        OdinJuliaBridge.set_point_brush(state_ptr, lineHostId, penbrush)
        OdinJuliaBridge.set_point_position(state_ptr, lineJoint1Id, startpos)
        OdinJuliaBridge.set_point_position(state_ptr, lineJoint2Id, tippos)
        OdinJuliaBridge.show_point(state_ptr, lineHostId)

        OdinJuliaBridge.emit_trailing_particle(state_ptr, tippos, pencolor)

        OdinJuliaBridge.set_pen_active(state_ptr, 1, pencolor)
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

    OdinJuliaBridge.lock_compass_joint1(state_ptr, jointPoint, sweep = false)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, color)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, endPoint, sweep = false)
    OdinJuliaBridge.show_compass(state_ptr)

    OdinJuliaBridge.set_point_color(state_ptr, markerHostId, color)
    OdinJuliaBridge.set_point_brush(state_ptr, markerHostId, brush)
    OdinJuliaBridge.set_point_position(state_ptr, markerStartId, startPoint)
    OdinJuliaBridge.set_point_position(state_ptr, markerEndId, endPoint)
    OdinJuliaBridge.show_point(state_ptr, markerHostId)

    OdinJuliaBridge.emit_trailing_particle(state_ptr, endPoint, color)
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

    OdinJuliaBridge.lock_compass_joint1(state_ptr, jointPoint)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, color)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, endPoint)
    OdinJuliaBridge.show_compass(state_ptr)

    OdinJuliaBridge.set_point_color(state_ptr, markerHostId, color)
    OdinJuliaBridge.set_point_brush(state_ptr, markerHostId, brush)
    OdinJuliaBridge.set_point_position(state_ptr, markerStartId, startPoint)
    OdinJuliaBridge.set_point_position(state_ptr, markerEndId, endPoint)
    OdinJuliaBridge.show_point(state_ptr, markerHostId)

    emit_filledcircle_radius_trail(state_ptr, jointPoint, endPoint, color)
end

"""
Animate a compass-only filled arc highlight sweep without mutating marker geometry.

--------

Parameters:

- state_ptr : Pointer to the Euclid application state.
- timer : Elapsed animation time.
- duration : Total duration for the highlight sweep.
- jointPoint : Compass pivot position vector [x, y, z].
- startPoint : Sweep start point vector [x, y, z].
- angleTheta : Sweep angle in radians.
- radius : Sweep radius.
- color : Trail and compass-active color.

Returns:

- nothing
"""
function animate_compass_fill_arc_highlight(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    jointPoint::Vector{Float32}, startPoint::Vector{Float32},
    angleTheta::Float32, radius::Float32, color)

    t = clamp(timer / duration, 0f0, 1f0)
    startTheta = Float32(atan(startPoint[2] - jointPoint[2], startPoint[1] - jointPoint[1]))
    theta = startTheta + angleTheta * t

    endPoint = [
        jointPoint[1] + radius * Float32(cos(theta)),
        jointPoint[2] + radius * Float32(sin(theta)),
        0f0]

    OdinJuliaBridge.lock_compass_joint1(state_ptr, jointPoint; sweep = false)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, endPoint; sweep = false)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, color)
    OdinJuliaBridge.show_compass(state_ptr)

    emit_filledcircle_radius_trail(state_ptr, jointPoint, endPoint, color)
end

"""Animate a REPL point draw with explicit pen descend, draw, and rise phases."""
function animate_repl_draw_point(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    penpos::Vector{Float32}, penbrush::Float32, pencolor,
    pointId::Integer)

    t = clamp(timer / duration, 0f0, 1f0)

    descend_duration = duration * ReplDescendShare
    draw_duration = duration * ReplDrawShare
    draw_start = descend_duration
    draw_end = draw_start + draw_duration

    if t < ReplDescendShare
        animate_pen_descend(
            state_ptr,
            timer,
            descend_duration,
            ReplToolTravelTopZ,
            penpos[1],
            penpos[2])
        return
    end

    if t < (ReplDescendShare + ReplDrawShare)
        animate_draw_point(
            state_ptr,
            timer - draw_start,
            draw_duration,
            penpos,
            penbrush,
            pencolor,
            pointId)
        return
    end

    animate_pen_rise(
        state_ptr,
        timer - draw_end,
        duration - draw_end,
        ReplToolTravelTopZ,
        penpos[1],
        penpos[2])
end

"""Animate a REPL line draw with explicit pen descend, draw, and rise phases."""
function animate_repl_draw_line(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    startpos::Vector{Float32}, endpos::Vector{Float32},
    penbrush::Float32, pencolor,
    lineHostId::Integer, lineJoint1Id::Integer, lineJoint2Id::Integer)

    t = clamp(timer / duration, 0f0, 1f0)

    descend_duration = duration * ReplDescendShare
    draw_duration = duration * ReplDrawShare
    draw_start = descend_duration
    draw_end = draw_start + draw_duration

    if t < ReplDescendShare
        animate_pen_descend(
            state_ptr,
            timer,
            descend_duration,
            ReplToolTravelTopZ,
            startpos[1],
            startpos[2])
        return
    end

    if t < (ReplDescendShare + ReplDrawShare)
        animate_draw_line(
            state_ptr,
            timer - draw_start,
            draw_duration,
            startpos,
            endpos,
            penbrush,
            pencolor,
            lineHostId,
            lineJoint1Id,
            lineJoint2Id)
        return
    end

    animate_pen_rise(
        state_ptr,
        timer - draw_end,
        duration - draw_end,
        ReplToolTravelTopZ,
        endpos[1],
        endpos[2])
end

"""Animate a REPL circle draw with explicit compass descend, draw, and rise phases."""
function animate_repl_draw_circle(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    jointPoint::Vector{Float32}, startPoint::Vector{Float32},
    angleTheta::Float32, radius::Float32, brush::Float32, color,
    markerHostId::Integer, markerStartId::Integer, markerEndId::Integer,
    fullSweep::Bool=false)

    t = clamp(timer / duration, 0f0, 1f0)

    descend_duration = duration * ReplDescendShare
    draw_duration = duration * ReplDrawShare
    draw_start = descend_duration
    draw_end = draw_start + draw_duration

    if t < ReplDescendShare
        animate_compass_descend(
            state_ptr,
            timer,
            descend_duration,
            ReplToolTravelTopZ,
            jointPoint[1],
            jointPoint[2],
            startPoint[1],
            startPoint[2])
        return
    end

    if t < (ReplDescendShare + ReplDrawShare)
        animate_draw_circle(
            state_ptr,
            timer - draw_start,
            draw_duration,
            jointPoint,
            startPoint,
            angleTheta,
            radius,
            brush,
            color,
            markerHostId,
            markerStartId,
            markerEndId)
        return
    end

    if fullSweep
        OdinJuliaBridge.set_point_offset(state_ptr, markerHostId, angleTheta)
    else
        OdinJuliaBridge.set_point_offset(state_ptr, markerHostId, 0f0)
    end

    final_theta = Float32(atan(startPoint[2] - jointPoint[2], startPoint[1] - jointPoint[1])) + angleTheta
    endPoint = Float32[
        jointPoint[1] + radius * Float32(cos(final_theta)),
        jointPoint[2] + radius * Float32(sin(final_theta)),
        jointPoint[3],
    ]

    animate_compass_rise(
        state_ptr,
        timer - draw_end,
        duration - draw_end,
        ReplToolTravelTopZ,
        jointPoint[1],
        jointPoint[2],
        endPoint[1],
        endPoint[2])
end

"""Animate a REPL filled-circle draw with explicit compass descend, draw, and rise phases."""
function animate_repl_draw_filledcircle(
    state_ptr::Ptr{Cvoid},
    timer::Float32, duration::Float32,
    jointPoint::Vector{Float32}, startPoint::Vector{Float32},
    angleTheta::Float32, radius::Float32, brush::Float32, color,
    markerHostId::Integer, markerStartId::Integer, markerEndId::Integer,
    fullSweep::Bool=false)

    t = clamp(timer / duration, 0f0, 1f0)

    descend_duration = duration * ReplDescendShare
    draw_duration = duration * ReplDrawShare
    draw_start = descend_duration
    draw_end = draw_start + draw_duration

    if t < ReplDescendShare
        animate_compass_descend(
            state_ptr,
            timer,
            descend_duration,
            ReplToolTravelTopZ,
            jointPoint[1],
            jointPoint[2],
            startPoint[1],
            startPoint[2])
        return
    end

    if t < (ReplDescendShare + ReplDrawShare)
        animate_draw_filledcircle(
            state_ptr,
            timer - draw_start,
            draw_duration,
            jointPoint,
            startPoint,
            angleTheta,
            radius,
            brush,
            color,
            markerHostId,
            markerStartId,
            markerEndId)
        return
    end

    if fullSweep
        OdinJuliaBridge.set_point_offset(state_ptr, markerHostId, angleTheta)
    else
        OdinJuliaBridge.set_point_offset(state_ptr, markerHostId, 0f0)
    end

    final_theta = Float32(atan(startPoint[2] - jointPoint[2], startPoint[1] - jointPoint[1])) + angleTheta
    endPoint = Float32[
        jointPoint[1] + radius * Float32(cos(final_theta)),
        jointPoint[2] + radius * Float32(sin(final_theta)),
        jointPoint[3],
    ]

    animate_compass_rise(
        state_ptr,
        timer - draw_end,
        duration - draw_end,
        ReplToolTravelTopZ,
        jointPoint[1],
        jointPoint[2],
        endPoint[1],
        endPoint[2])
end

end
