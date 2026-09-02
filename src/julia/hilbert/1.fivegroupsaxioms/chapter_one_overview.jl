module HilbertChapterOneOverview

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("df6fe312-a86c-5489-96b5-39729053df0d")

using ..OdinJuliaBridge
using ..EuclidLatex
using ..NullAnimation

export get_view_text, initialize, clean, loop, animation_entry

"""Emit the overview text for the five-groups-of-axioms sequence."""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §1 The Elements of Geometry and the Five Groups of Axioms
    
Let us consider three distinct systems of things. The things composing the first system, we will call points and designate them by the letters A, B, C,. . . ; those of the second, we will call straight lines and designate them by the letters a, b, c,. . . ; and those of the third system, we will call planes and designate them by the Greek letters α, β, γ,. . . The points are called the elements of linear geometry; the points and straight lines, the elements of plane geometry; and the points, lines, and planes, the elements of the geometry of space or the elements of space.

We think of these points, straight lines, and planes as having certain mutual relations, which we indicate by means of such words as "are situated," "between," "parallel," "congruent," "continuous," etc. The complete and exact description of these relations follows as a consequence of the axioms of geometry. These axioms may be arranged in five groups. Each of these groups expresses, by itself, certain related fundamental facts of our intuition. We will name these groups as follows:

I, 1-7. Axioms of connection.
II, 1-5. Axioms of order.
III. Axiom of parallels (Euclid's axiom).
IV, 1-6. Axioms of congruence.
V. Axiom of continuity (Archimedes's axiom)."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§1 The Elements of Geometry and the Five Groups of Axioms}
    
Let us consider three distinct systems of things. The things composing the first system, we will call points and designate them by the letters $A, B, C, ...$ ; those of the second, we will call straight lines and designate them by the letters $a, b, c, ...$; and those of the third system, we will call planes and designate them by the Greek letters $\alpha, \beta, \gamma, ...$ The points are called the elements of linear geometry; the points and straight lines, the elements of plane geometry; and the points, lines, and planes, the elements of the geometry of space or the elements of space.

We think of these points, straight lines, and planes as having certain mutual relations, which we indicate by means of such words as "are situated," "between," "parallel," "congruent," "continuous," etc. The complete and exact description of these relations follows as a consequence of the axioms of geometry. These axioms may be arranged in five groups. Each of these groups expresses, by itself, certain related fundamental facts of our intuition. We will name these groups as follows:

\textbf{I, 1-7.} Axioms of \textit{connection}.\\
\textbf{II, 1-5.} Axioms of \textit{order}.\\
\textbf{III.} Axiom of \textit{parallels (Euclid's axiom)}.\\
\textbf{IV, 1-6.} Axioms of \textit{congruence}.\\
\textbf{V.} Axiom of \textit{continuity (Archimedes's axiom)}."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Initialize the null animation and publish the chapter overview."""
function initialize(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Advance the shared null animation for the chapter overview."""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    NullAnimation.loop(state_ptr, dt)
end

"""Clean the shared null animation for the chapter overview."""
function clean(state_ptr::Ptr{Cvoid})
    NullAnimation.clean(state_ptr)
end

"""Dispatch one lifecycle operation for the chapter overview."""
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
    HilbertChapterOneOverview.AnimationId, HilbertChapterOneOverview.animation_entry)
