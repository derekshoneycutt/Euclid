module EuclidAlgebraOverview

using UUIDs
using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation
using ..AnimationCatalog

export get_view_content, initialize, clean, loop, animation_entry

const AnimationId = UUID("a8bd259b-0c7b-5b60-b21f-84095e2eb903")

"""Emit the welcome view content for Algebra."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Welcome to Euclid!}
    
Here we explore Algebra for ways that are helpful for understanding geometry and animation."""
end

"""Initialize the null animation and publish the Algebra overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Advance the shared null animation for the Algebra overview."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the Algebra overview."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the Algebra overview."""
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
    EuclidAlgebraOverview.AnimationId, EuclidAlgebraOverview.animation_entry)
