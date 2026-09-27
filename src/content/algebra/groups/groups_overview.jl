module EuclidAlgebraGroupsOverview

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("1c54c525-f85a-55a9-931b-8cfaafabec03")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

include("groups_overview_content.jl")

export get_view_content, initialize, clean, loop, animation_entry

"""Emit the root view content for the group-theory animation sequence."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return EuclidAlgebraGroupsOverviewContent.get_view_content()
end

"""Initialize the null animation and publish the Groups overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Advance the shared null animation for the Groups overview."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the Groups overview."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the Groups overview."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        clean(state_ptr)
    else
        return false
    end
    return true
end

end

AnimationCatalog.animation(
    EuclidAlgebraGroupsOverview.AnimationId, EuclidAlgebraGroupsOverview.animation_entry)
