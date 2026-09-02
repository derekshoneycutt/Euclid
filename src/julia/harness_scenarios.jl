module EuclidHarnessScenarios

using ..OdinJuliaBridge

export scenario_point_after_eight_steps

const ExpectedPoint = Float32[0.5f0, 0.5f0, 0f0]

"""
Check that the animated point matches the expected position after eight steps.
"""
function scenario_point_after_eight_steps(
    generation, state_ptr::Ptr{Cvoid}, step_count::Integer)

    step_count == 8 || return false

    point_module = getfield(
        generation.content, :ElementsOneDefinitionPoint)
    point_state, status = OdinJuliaBridge.get_animation_value(
        state_ptr, point_module.StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false
    point_id = point_state.point_id
    point_id >= 0 || return false

    point = OdinJuliaBridge.get_point(state_ptr, point_id)
    point.valid != 0 || return false
    point.has_position != 0 || return false
    point.do_draw in (0, 1) || return false

    position = collect(point.pos)
    all(isapprox.(position, ExpectedPoint; atol=1f-4, rtol=0f0)) || return false

    return true
end

end
