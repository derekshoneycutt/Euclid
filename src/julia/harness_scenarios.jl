module EuclidHarnessScenarios

using ..OdinJuliaBridge

export scenario_point_after_eight_steps

const ExpectedPoint = Float32[0.5f0, 0.5f0, 0f0]

function scenario_point_after_eight_steps(state_ptr::Ptr{Cvoid}, step_count::Integer)
    step_count == 8 || return false

    point_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, 1))
    point_id >= 0 || return false

    point = OdinJuliaBridge.get_point(state_ptr, point_id)
    point.valid != 0 || return false
    point.hasPosition != 0 || return false
    point.doDraw in (0, 1) || return false

    position = collect(point.pos)
    all(isapprox.(position, ExpectedPoint; atol=1f-4, rtol=0f0)) || return false

    return true
end

end
