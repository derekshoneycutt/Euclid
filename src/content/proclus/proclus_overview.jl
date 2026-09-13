module ProclusOverview

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("1c6b94cb-0ecb-5f34-8ea5-30833bcc77fb")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_content, initialize, clean, loop, animation_entry

"""Emit the Proclus's Commentary overview content."""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return tex"""\textbf{Proclus's Commentary}
    
Proclus provided an ancient commentary on Book I of \textit{Euclid's Elements}, including additional constructions and analyses. Some will be included here."""
end

"""Initialize the null animation and publish the Proclus overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Advance the shared null animation for the Proclus overview."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the Proclus overview."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the Proclus overview."""
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
    ProclusOverview.AnimationId, ProclusOverview.animation_entry)
