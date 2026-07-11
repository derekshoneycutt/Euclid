module HilbertChapterOne

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry
using ..NullAnimation

include("./axiom_I1.jl")
include("./axiom_I2.jl")
include("./axiom_I3.jl")
include("./axiom_I4.jl")
include("./axiom_I5.jl")
include("./axiom_I6.jl")
include("./axiom_I7.jl")


function get_view_text_BookI(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §1 The Elements of Geometry and the Five Groups of Axioms
    
Let us consider three distinct systems of things. The things composing the first system, we will call points and designate them by the letters A, B, C,. . . ; those of the second, we will call straight lines and designate them by the letters a, b, c,. . . ; and those of the third system, we will call planes and designate them by the Greek letters α, β, γ,. . . The points are called the elements of linear geometry; the points and straight lines, the elements of plane geometry; and the points, lines, and planes, the elements of the geometry of space or the elements of space.

We think of these points, straight lines, and planes as having certain mutual relations, which we indicate by means of such words as "are situated," "between," "parallel," "congruent," "continuous," etc. The complete and exact description of these relations follows as a consequence of the axioms of geometry. These axioms may be arranged in five groups. Each of these groups expresses, by itself, certain related fundamental facts of our intuition. We will name these groups as follows:

I, 1-7. Axioms of connection.
II, 1-5. Axioms of order.
III. Axiom of parallels (Euclid's axiom).
IV, 1-6. Axioms of congruence.
V. Axiom of continuity (Archimedes's axiom)."""
end

function get_view_text_BookI_connection(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §2 Group I: Axioms of Connection

The axioms of this group establish a connection between the concepts indicated above; namely, points, straight lines, and planes.

...

Axioms I, 1-2 contain statements concerning points and straight lines only; that is, concerning the elements of plane geometry. We will call them, therefore, the plane axioms of group I, in order to distinguish them from the axioms I, 3-7, which we will designate briefly as the space axioms of this group.
Of the theorems which follow from the axioms I, 3-7, we shall mention only 2."""
end

function get_view_text_BookI_posts(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I - Postulates"
end

function get_view_text_BookI_props(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I - Propositions"
end

function init_euclid_scripts(state_ptr::Ptr{Cvoid}, rootId)
    book1Id = OdinJuliaBridge.add_child_animation_interface(
        state_ptr, get_view_text_BookI, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean,
        "1. The Five Groups of Axioms, §1", rootId)
        book1Sec2Id = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, get_view_text_BookI_connection, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "§2 Group I: Axioms of Connection", book1Id)
            book1AxiomI1Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomI1.get_view_text,
                HilbertChapterOneAxiomI1.initialize,
                HilbertChapterOneAxiomI1.loop, HilbertChapterOneAxiomI1.clean,
                "Axiom I,1", book1Sec2Id)
            book1AxiomI2Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomI2.get_view_text,
                HilbertChapterOneAxiomI2.initialize,
                HilbertChapterOneAxiomI2.loop, HilbertChapterOneAxiomI2.clean,
                "Axiom I,2", book1Sec2Id)
            book1AxiomI3Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomI3.get_view_text,
                HilbertChapterOneAxiomI3.initialize,
                HilbertChapterOneAxiomI3.loop, HilbertChapterOneAxiomI3.clean,
                "Axiom I,3", book1Sec2Id)
            book1AxiomI4Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomI4.get_view_text,
                HilbertChapterOneAxiomI4.initialize,
                HilbertChapterOneAxiomI4.loop, HilbertChapterOneAxiomI4.clean,
                "Axiom I,4", book1Sec2Id)
            book1AxiomI5Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomI5.get_view_text,
                HilbertChapterOneAxiomI5.initialize,
                HilbertChapterOneAxiomI5.loop, HilbertChapterOneAxiomI5.clean,
                "Axiom I,5", book1Sec2Id)
            book1AxiomI6Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomI6.get_view_text,
                HilbertChapterOneAxiomI6.initialize,
                HilbertChapterOneAxiomI6.loop, HilbertChapterOneAxiomI6.clean,
                "Axiom I,6", book1Sec2Id)
            book1AxiomI7Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomI7.get_view_text,
                HilbertChapterOneAxiomI7.initialize,
                HilbertChapterOneAxiomI7.loop, HilbertChapterOneAxiomI7.clean,
                "Axiom I,7", book1Sec2Id)
end

end