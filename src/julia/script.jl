using Colors
using LinearAlgebra

include("./nullanimation.jl")

function init_euclid_scripts(state_ptr::Ptr{Cvoid})
    euclid_set_null_animations(
        state_ptr, init_null_animation, loop_null_animation, clean_null_animation)
end

function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    # Nothing to do here, but is required
end
