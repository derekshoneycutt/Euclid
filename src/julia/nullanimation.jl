module NullAnimation

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartRotation = π / 4f0
const CircleRadius = 0.25f0
const Anchor = [0.5f0, 0.5f0, 0f0]
const StartRotationPos = Anchor + [ CircleRadius * cos(StartRotation), CircleRadius * sin(StartRotation), 0]
const PenRotation = π / 4f0
const Color1 = :steelblue
const Color2 = :khaki3
const Color3 = :palevioletred1
const CompassDrawColor = Color1
const PenDrawColor1 = Color2
const PenDrawColor2 = Color3

function get_view_text(state_ptr::Ptr{Cvoid})
    "Welcome to Euclid"
end

function initialize(state_ptr::Ptr{Cvoid})
    useRotation = π - PenRotation

    OdinJuliaBridge.set_animation_meta(state_ptr, 1, StartRotation)
    OdinJuliaBridge.set_animation_meta(state_ptr, 2, -1f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, 3, useRotation)
    
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 1, PenDrawColor1)
    OdinJuliaBridge.lock_pen_joint1(state_ptr, 0.9f0, 0.9f0, 0f0)
    OdinJuliaBridge.move_pen_joint2(state_ptr, 0.9f0, 0.9f0 + cos(useRotation), sin(useRotation))

    OdinJuliaBridge.show_compass(state_ptr)
    OdinJuliaBridge.set_compass_active(state_ptr, 3, CompassDrawColor)
    OdinJuliaBridge.lock_compass_joint1(state_ptr, 0.5f0, 0.5f0, 0f0)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, StartRotationPos[1], StartRotationPos[2], StartRotationPos[3])

    line1 = OdinJuliaBridge.create_new_line(state_ptr,
        0f0, 0f0, 0f0,
        0f0, 0f0, 0f0,
        PenDrawColor1, 5f0)
    line2 = OdinJuliaBridge.create_new_line(state_ptr,
        0f0, 0f0, 0f0,
        0f0, 0f0, 0f0,
        PenDrawColor2, 5f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, 4, Float32(line1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, 5, Float32(line1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, 6, Float32(line1.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, 7, Float32(line2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, 8, Float32(line2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, 9, Float32(line2.joint2Id))

    circle = OdinJuliaBridge.create_new_circle(state_ptr,
        0.5f0, 0.5f0, 0f0,
        CircleRadius, StartRotation, StartRotation, CompassDrawColor, 5f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, 10, Float32(circle.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, 11, Float32(circle.startId))
    OdinJuliaBridge.set_animation_meta(state_ptr, 12, Float32(circle.endId))

    OdinJuliaBridge.set_animation_meta(state_ptr, 100, 0f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, 101, 0f0)
end

function clean(state_ptr::Ptr{Cvoid})
    # nothing special on the julia side; our data is auto-cleared in Odin side
end

function draw_line(state_ptr::Ptr{Cvoid}, dt::Float32)
    drawLineFlag = OdinJuliaBridge.get_animation_meta(state_ptr, 100)
    line1Host = OdinJuliaBridge.get_animation_meta(state_ptr, 4)
    line1Point1 = OdinJuliaBridge.get_animation_meta(state_ptr, 5)
    line1Point2 = OdinJuliaBridge.get_animation_meta(state_ptr, 6)
    line2Host = OdinJuliaBridge.get_animation_meta(state_ptr, 7)
    line2Point1 = OdinJuliaBridge.get_animation_meta(state_ptr, 8)
    line2Point2 = OdinJuliaBridge.get_animation_meta(state_ptr, 9)

    line1HostDesc = OdinJuliaBridge.get_point(state_ptr, Integer(line1Host))
    line2HostDesc = OdinJuliaBridge.get_point(state_ptr, Integer(line2Host))

    penDirection = OdinJuliaBridge.get_animation_meta(state_ptr, 2)
    penRotationCurr = OdinJuliaBridge.get_animation_meta(state_ptr, 3)
    (penx1, peny1, penz1) = OdinJuliaBridge.get_pen_joint1_position(state_ptr)
    (penx2, peny2, penz2) = OdinJuliaBridge.get_pen_joint2_position(state_ptr)
    vec = [penx2, peny2, penz2] - [penx1, peny1, penz1]
    len = norm(vec)
    if penDirection < 1
        penDrawColor = PenDrawColor1
        peny1 = peny1 - (dt * 0.4f0)
        peny2 = peny2 - (dt * 0.4f0)

        OdinJuliaBridge.hide_point(state_ptr, Integer(line2Host))
        OdinJuliaBridge.set_point_position(state_ptr, Integer(line2Point1), 0.9f0, 0.1f0, 0f0)
        OdinJuliaBridge.set_point_position(state_ptr, Integer(line2Point2), 0.9f0, 0.1f0, 0f0)
        if drawLineFlag > 0
            OdinJuliaBridge.set_point_position(state_ptr, Integer(line1Point1), 0.9f0, 0.9f0, 0f0)
            OdinJuliaBridge.set_point_position(state_ptr, Integer(line1Point2), penx1, peny1, 0f0)
            OdinJuliaBridge.set_point_brush(state_ptr, Integer(line1Host), 5f0)
            OdinJuliaBridge.show_point(state_ptr, Integer(line1Host))
        end

        if peny1 <= 0.1
            peny1 = 0.1f0
            penRotationCurr = penRotationCurr - (dt * 3f0π/4f0)
            if penRotationCurr <= PenRotation
                penRotationCurr = PenRotation
                OdinJuliaBridge.set_animation_meta(state_ptr, 2, 1f0)
                drawLineFlag = Float32((Integer(drawLineFlag) + 1) % 2)
                OdinJuliaBridge.set_animation_meta(state_ptr, 100, drawLineFlag)
            end
            peny2 = 0.1f0 + cos(penRotationCurr) * len
            penz2 = sin(penRotationCurr) * len
            OdinJuliaBridge.set_animation_meta(state_ptr, 3, penRotationCurr)
        end
    else
        penDrawColor = PenDrawColor2
        peny1 = peny1 + (dt * 0.4f0)
        peny2 = peny2 + (dt * 0.4f0)

        OdinJuliaBridge.hide_point(state_ptr, Integer(line1Host))
        OdinJuliaBridge.set_point_position(state_ptr, Integer(line1Point1), 0.9f0, 0.1f0, 0f0)
        OdinJuliaBridge.set_point_position(state_ptr, Integer(line1Point2), 0.9f0, 0.1f0, 0f0)
        if drawLineFlag > 0
            OdinJuliaBridge.set_point_position(state_ptr, Integer(line2Point1), 0.9f0, 0.1f0, 0f0)
            OdinJuliaBridge.set_point_position(state_ptr, Integer(line2Point2), penx1, peny1, 0f0)
            OdinJuliaBridge.set_point_brush(state_ptr, Integer(line2Host), 5f0)
            OdinJuliaBridge.show_point(state_ptr, Integer(line2Host))
        end

        if peny1 >= 0.9
            peny1 = 0.9f0
            penRotationCurr = penRotationCurr + (dt * 3f0π/4f0)
            if  penRotationCurr >= π - PenRotation
                penRotationCurr = 1f0π - PenRotation
                OdinJuliaBridge.set_animation_meta(state_ptr, 2, -1f0)
            end
            peny2 = 0.9f0 + cos(penRotationCurr) * len
            penz2 = sin(penRotationCurr) * len
            OdinJuliaBridge.set_animation_meta(state_ptr, 3, penRotationCurr)
        end
    end
    OdinJuliaBridge.lock_pen_joint1(state_ptr, penx1, peny1, penz1)
    OdinJuliaBridge.move_pen_joint2(state_ptr, penx2, peny2, penz2)
    OdinJuliaBridge.set_pen_active(state_ptr, 1, penDrawColor)
    OdinJuliaBridge.emit_trailing_particle(state_ptr, penx1, peny1, penDrawColor)
end

function draw_circle(state_ptr::Ptr{Cvoid}, dt::Float32)
    currRotation = OdinJuliaBridge.get_animation_meta(state_ptr, 1)
    currRotation = currRotation - (dt * π/2)
    if currRotation < 0
        currRotation = Float32(currRotation + 2π)
    end
    
    outPos = Anchor +
        [ CircleRadius * cos(currRotation), CircleRadius * sin(currRotation), 0]

    drawCircleFlag = OdinJuliaBridge.get_animation_meta(state_ptr, 101)
    circleHost = OdinJuliaBridge.get_animation_meta(state_ptr, 10)
    circleStart = OdinJuliaBridge.get_animation_meta(state_ptr, 11)
    circleEnd = OdinJuliaBridge.get_animation_meta(state_ptr, 12)

    circleHostDesc = OdinJuliaBridge.get_point(state_ptr, Integer(circleHost))

    if abs(currRotation - StartRotation) < dt * π/2 && currRotation <= StartRotation
        drawCircleFlag = Float32((Integer(drawCircleFlag) + 1) % 2)
        OdinJuliaBridge.set_animation_meta(state_ptr, 101, drawCircleFlag)
    end

    if drawCircleFlag > 0
        OdinJuliaBridge.set_point_position(state_ptr, Integer(circleEnd),
            StartRotationPos[1], StartRotationPos[2], StartRotationPos[3])
        OdinJuliaBridge.set_point_position(state_ptr, Integer(circleStart),
            outPos[1], outPos[2], outPos[3])
        OdinJuliaBridge.set_point_brush(state_ptr, Integer(circleHost), 5f0)
        OdinJuliaBridge.show_point(state_ptr, Integer(circleHost))
    else
        OdinJuliaBridge.hide_point(state_ptr, Integer(circleHost))
        OdinJuliaBridge.set_point_position(state_ptr, Integer(circleStart),
            StartRotationPos[1], StartRotationPos[2], StartRotationPos[3])
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, 1, currRotation)
    OdinJuliaBridge.lock_compass_joint2(state_ptr, outPos[1], outPos[2], outPos[3])
    OdinJuliaBridge.emit_trailing_particle(state_ptr, outPos[1], outPos[2], CompassDrawColor)
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    draw_line(state_ptr, dt)
    draw_circle(state_ptr, dt)
end

end

