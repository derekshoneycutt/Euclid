module HilbertOverview

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("65a8489e-e0bd-535f-bf47-3c5e9c9d70e6")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_text, initialize, clean, loop, animation_entry

"""Emit the Hilbert Foundations of Geometry overview text."""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry ; Translated by E. J. Townsend
    
"All human knowledge begins with intuitions, thence passes to concepts and ends with ideas."
Kant, Critique of Pure Reason

Geometry, like arithmetic, requires for its logical development only a small number of simple, fundamental principles. These fundamental principles are called the axioms of geometry. The choice of the axioms and the investigation of their relations to one another is a problem which, since the time of Euclid, has been discussed in numerous excellent memoirs to be found in the mathematical literature. This problem is tantamount to the logical analysis of our intuition of space.
The following investigation is a new attempt to choose for geometry a simple and complete set of independent axioms and to deduce from these the most important geometrical theorems in such a manner as to bring out as clearly as possible the significance of the different groups of axioms and the scope of the conclusions to be derived from the individual axioms."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry} ; Translated by E. J. Townsend
    
\textit{"All human knowledge begins with intuitions, thence passes to concepts and ends with ideas."}\\
\textit{Kant, Critique of Pure Reason}

Geometry, like arithmetic, requires for its logical development only a small number of simple, fundamental principles. These fundamental principles are called the axioms of geometry. The choice of the axioms and the investigation of their relations to one another is a problem which, since the time of Euclid, has been discussed in numerous excellent memoirs to be found in the mathematical literature. This problem is tantamount to the logical analysis of our intuition of space.
The following investigation is a new attempt to choose for geometry a simple and complete set of independent axioms and to deduce from these the most important geometrical theorems in such a manner as to bring out as clearly as possible the significance of the different groups of axioms and the scope of the conclusions to be derived from the individual axioms."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Initialize the null animation and publish the Hilbert overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Advance the shared null animation for the Hilbert overview."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the Hilbert overview."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the Hilbert overview."""
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
    HilbertOverview.AnimationId, HilbertOverview.animation_entry)
