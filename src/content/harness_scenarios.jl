module EuclidHarnessScenarios

using ..OdinJuliaBridge
using Random

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
    point_id != 0 || return false

    point = OdinJuliaBridge.get_point(state_ptr, point_id)
    point.status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false
    point.has_position != 0 || return false
    point.do_draw in (0, 1) || return false

    position = collect(point.pos)
    all(isapprox.(position, ExpectedPoint; atol=1f-4, rtol=0f0)) || return false

    return scenario_content_notice_noop(generation, state_ptr)
end

"""Copy exact native test observations without borrowing owner storage."""
function content_notice_observation(state_ptr::Ptr{Cvoid})
    capacity = @ccall copy_animation_notice_observation(
        state_ptr::Ptr{Cvoid}, C_NULL::Ptr{UInt8}, Int64(0)::Int64)::Int64
    capacity > 0 || error("native notice observation sizing failed")
    bytes = Vector{UInt8}(undef, capacity)
    count = GC.@preserve bytes begin
        @ccall copy_animation_notice_observation(
            state_ptr::Ptr{Cvoid}, bytes::Ptr{UInt8}, capacity::Int64)::Int64
    end
    count == capacity || error("native notice observation copy failed")
    return bytes
end

"""Offer every authored entry a notice and compare native state and Julia RNG."""
function scenario_content_notice_noop(generation, state_ptr::Ptr{Cvoid})::Bool
    catalog = getfield(generation.content, :AnimationCatalogGeneration)
    descriptors = getfield(catalog, :AnimationDescriptors)
    entries = [
        Main.load_generation_animation(
            generation, descriptor.id, descriptor.implementation_path).entry
        for descriptor in descriptors if descriptor.implementation_path !== nothing]
    push!(entries, getfield(generation.null_animation, :animation_entry))
    before = content_notice_observation(state_ptr)
    rng = copy(Random.default_rng())
    for entry in entries
        Base.invokelatest(entry, state_ptr,
            OdinJuliaBridge.ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED, 91.0f0) ||
            error("authored entry rejected presentation selection notice")
        !Base.invokelatest(entry, state_ptr, Int32(99), 91.0f0) ||
            error("authored entry accepted unknown operation")
    end
    Main.terminal_animation_entry(state_ptr, state_ptr,
        OdinJuliaBridge.ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED, 91.0f0) ||
        error("Terminal adapter rejected presentation selection notice")
    !Main.terminal_animation_entry(state_ptr, state_ptr, Int32(99), 91.0f0) ||
        error("Terminal adapter accepted unknown operation")
    before == content_notice_observation(state_ptr) ||
        error("presentation selection notice mutated native state")
    rng == copy(Random.default_rng()) ||
        error("presentation selection notice advanced Julia RNG")
    return true
end

end
