using Colors
using LinearAlgebra

include("./nullanimation.jl")

function init_euclid_scripts(state_ptr::Ptr{Cvoid})
    init_null_animation(state_ptr)
end

function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    loop_null_animation(state_ptr, dt)
end
