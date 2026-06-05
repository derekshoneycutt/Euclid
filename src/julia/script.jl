using Colors

const StartRotation = π / 4.0f0
const CircleRadius = 0.25f0

function init_euclid_scripts(state_ptr::Ptr{Cvoid})
    outPos = [ 0.5f0 + CircleRadius * cos(StartRotation),
        0.5f0 + CircleRadius * sin(StartRotation),
        0f0]

    euclid_set_compass_active(state_ptr, 3, :steelblue)
    euclid_set_animation_meta(state_ptr, 1, StartRotation)
    euclid_lock_compass_joint1(state_ptr, 0.5f0, 0.5f0, 0f0)
    euclid_lock_compass_joint2(state_ptr, outPos[1], outPos[2], outPos[3])
end

function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    currRotation = euclid_get_animation_meta(state_ptr, 1)
    currRotation = currRotation - (dt * π/2f0)
    if currRotation < 0
        currRotation = currRotation + 2f0π
    end
    
    outPos = [ 0.5f0 + CircleRadius * cos(currRotation),
        0.5f0 + CircleRadius * sin(currRotation),
        0f0]

    euclid_set_animation_meta(state_ptr, 1, currRotation)
    euclid_lock_compass_joint2(state_ptr, outPos[1], outPos[2], outPos[3])
end
