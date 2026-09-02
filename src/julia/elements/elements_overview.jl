module EuclidElementsOverview

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("4a3a9e1f-6448-554a-8e37-52f579b7476b")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_text, initialize, clean, loop, animation_entry

"""Emit the welcome view text for Euclid's Elements."""
function get_view_text(state_ptr::Ptr{Cvoid})
    latex = raw"""\textbf{Welcome to Euclid's Elements!}"""
    fallback = "Welcome to Euclid's Elements!"
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Initialize the null animation and publish the Elements overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Advance the shared null animation for the Elements overview."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the Elements overview."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the Elements overview."""
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
    EuclidElementsOverview.AnimationId, EuclidElementsOverview.animation_entry)
