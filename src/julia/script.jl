using Colors
using LinearAlgebra

const StartRotation = π / 4f0
const CircleRadius = 0.25f0
const Anchor = [0.5f0, 0.5f0, 0f0]
const PenRotation = π / 4f0
const Color1 = :steelblue
const Color2 = :khaki3
const Color3 = :palevioletred1
const CompassDrawColor = Color1
const PenDrawColor1 = Color2
const PenDrawColor2 = Color3

function init_euclid_scripts(state_ptr::Ptr{Cvoid})
    outPos = Anchor +
        [ CircleRadius * cos(StartRotation), CircleRadius * sin(StartRotation), 0]
    
    useRotation = π - PenRotation

    euclid_set_animation_meta(state_ptr, 1, StartRotation)
    euclid_set_animation_meta(state_ptr, 2, -1f0)
    euclid_set_animation_meta(state_ptr, 3, useRotation)
    
    euclid_show_pen(state_ptr)
    euclid_set_pen_active(state_ptr, 1, PenDrawColor1)
    euclid_lock_pen_joint1(state_ptr, 0.9f0, 0.9f0, 0f0)
    euclid_move_pen_joint2(state_ptr, 0.9f0, 0.9f0 + cos(useRotation), sin(useRotation))

    euclid_show_compass(state_ptr)
    euclid_set_compass_active(state_ptr, 3, CompassDrawColor)
    euclid_lock_compass_joint1(state_ptr, 0.5f0, 0.5f0, 0f0)
    euclid_lock_compass_joint2(state_ptr, outPos[1], outPos[2], outPos[3])
end

function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    penDirection = euclid_get_animation_meta(state_ptr, 2)
    penRotationCurr = euclid_get_animation_meta(state_ptr, 3)
    (penx1, peny1, penz1) = euclid_get_pen_joint1_position(state_ptr)
    (penx2, peny2, penz2) = euclid_get_pen_joint2_position(state_ptr)
    vec = [penx2, peny2, penz2] - [penx1, peny1, penz1]
    len = norm(vec)
    if penDirection < 1
        penDrawColor = PenDrawColor1
        peny1 = peny1 - (dt * 0.4f0)
        peny2 = peny2 - (dt * 0.4f0)
        if peny1 <= 0.1
            peny1 = 0.1f0
            penRotationCurr = penRotationCurr - (dt * 3f0π/4f0)
            if penRotationCurr <= PenRotation
                penRotationCurr = PenRotation
                euclid_set_animation_meta(state_ptr, 2, 1f0)
            end
            peny2 = 0.1f0 + cos(penRotationCurr) * len
            penz2 = sin(penRotationCurr) * len
            euclid_set_animation_meta(state_ptr, 3, penRotationCurr)
        end
    else
        penDrawColor = PenDrawColor2
        peny1 = peny1 + (dt * 0.4f0)
        peny2 = peny2 + (dt * 0.4f0)
        if peny1 >= 0.9
            peny1 = 0.9f0
            penRotationCurr = penRotationCurr + (dt * 3f0π/4f0)
            if  penRotationCurr >= π - PenRotation
                penRotationCurr = 1f0π - PenRotation
                euclid_set_animation_meta(state_ptr, 2, -1f0)
            end
            peny2 = 0.9f0 + cos(penRotationCurr) * len
            penz2 = sin(penRotationCurr) * len
            euclid_set_animation_meta(state_ptr, 3, penRotationCurr)
        end
    end
    euclid_lock_pen_joint1(state_ptr, penx1, peny1, penz1)
    euclid_move_pen_joint2(state_ptr, penx2, peny2, penz2)
    euclid_set_pen_active(state_ptr, 1, penDrawColor)
    euclid_emit_trailing_particle(state_ptr, penx1, peny1, penDrawColor)

    currRotation = euclid_get_animation_meta(state_ptr, 1)
    currRotation = currRotation - (dt * π/2)
    if currRotation < 0
        currRotation = Float32(currRotation + 2π)
    end
    
    outPos = Anchor +
        [ CircleRadius * cos(currRotation), CircleRadius * sin(currRotation), 0]

    euclid_set_animation_meta(state_ptr, 1, currRotation)
    euclid_lock_compass_joint2(state_ptr, outPos[1], outPos[2], outPos[3])
    euclid_emit_trailing_particle(state_ptr, outPos[1], outPos[2], CompassDrawColor)
end
