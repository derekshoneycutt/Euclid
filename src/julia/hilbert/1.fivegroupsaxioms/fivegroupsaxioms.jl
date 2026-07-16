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
include("./axiom_II1.jl")
include("./axiom_II2.jl")
include("./axiom_II3.jl")
include("./axiom_II4.jl")
include("./axiom_II5.jl")
include("./def_segments.jl")
include("./theorem_1.jl")
include("./theorem_2.jl")
include("./theorem_3.jl")
include("./theorem_4.jl")
include("./theorem_5.jl")
include("./theorem_6.jl")
include("./theorem_7.jl")
include("./def_halfrays.jl")
include("./def_sideofline.jl")
include("./def_polygon.jl")


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

function get_view_text_BookI_order(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §3 Group II: Axioms of Order

The axioms of this group define the idea expressed by the word "between," and make possible, upon the basis of this idea, an order of sequence of the points upon a straight line, in a plane, and in space. The points of a straight line have a certain relation to one another which the word "between" serves to describe.

...

Axioms II, 1-4 contain statements concerning the points of a straight line only, and, hence, we will call them the linear axioms of group II. Axiom II, 5 relates to the elements of plane geometry and, consequently, shall be called the plane axiom of group II."""
end

function get_view_text_BookI_consequences(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §4 Consequences of the Axioms of Connection and Order

By the aid of the four linear axioms II, 1-4, we can easily deduce several theorems."""
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
            book1Theorem1Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem1.get_view_text,
                HilbertChapterOneTheorem1.initialize,
                HilbertChapterOneTheorem1.loop, HilbertChapterOneTheorem1.clean,
                "Theorem 1", book1Sec2Id)
            book1Theorem2Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem2.get_view_text,
                HilbertChapterOneTheorem2.initialize,
                HilbertChapterOneTheorem2.loop, HilbertChapterOneTheorem2.clean,
                "Theorem 2", book1Sec2Id)

        book1Sec3Id = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, get_view_text_BookI_order, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "§3 Group II: Axioms of Order", book1Id)
            book1AxiomII1Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomII1.get_view_text,
                HilbertChapterOneAxiomII1.initialize,
                HilbertChapterOneAxiomII1.loop, HilbertChapterOneAxiomII1.clean,
                "Axiom II,1", book1Sec3Id)
            book1AxiomII2Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomII2.get_view_text,
                HilbertChapterOneAxiomII2.initialize,
                HilbertChapterOneAxiomII2.loop, HilbertChapterOneAxiomII2.clean,
                "Axiom II,2", book1Sec3Id)
            book1AxiomII3Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomII3.get_view_text,
                HilbertChapterOneAxiomII3.initialize,
                HilbertChapterOneAxiomII3.loop, HilbertChapterOneAxiomII3.clean,
                "Axiom II,3", book1Sec3Id)
            book1AxiomII4Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomII4.get_view_text,
                HilbertChapterOneAxiomII4.initialize,
                HilbertChapterOneAxiomII4.loop, HilbertChapterOneAxiomII4.clean,
                "Axiom II,4", book1Sec3Id)
            book1DefSegmentsId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneDefSegments.get_view_text,
                HilbertChapterOneDefSegments.initialize,
                HilbertChapterOneDefSegments.loop,
                HilbertChapterOneDefSegments.clean,
                "Definition: Segments", book1Sec3Id)
            book1AxiomII5Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomII5.get_view_text,
                HilbertChapterOneAxiomII5.initialize,
                HilbertChapterOneAxiomII5.loop, HilbertChapterOneAxiomII5.clean,
                "Axiom II,5", book1Sec3Id)

        book1Sec4Id = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, get_view_text_BookI_consequences, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "§4 Consequences after Group II", book1Id)
            book1Theorem3Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem3.get_view_text,
                HilbertChapterOneTheorem3.initialize,
                HilbertChapterOneTheorem3.loop, HilbertChapterOneTheorem3.clean,
                "Theorem 3", book1Sec4Id)
            book1Theorem4Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem4.get_view_text,
                HilbertChapterOneTheorem4.initialize,
                HilbertChapterOneTheorem4.loop, HilbertChapterOneTheorem4.clean,
                "Theorem 4", book1Sec4Id)
            book1Theorem5Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem5.get_view_text,
                HilbertChapterOneTheorem5.initialize,
                HilbertChapterOneTheorem5.loop, HilbertChapterOneTheorem5.clean,
                "Theorem 5", book1Sec4Id)
            book1DefHalfRaysId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneDefHalfRays.get_view_text,
                HilbertChapterOneDefHalfRays.initialize,
                HilbertChapterOneDefHalfRays.loop, HilbertChapterOneDefHalfRays.clean,
                "Definition: Half-rays", book1Sec4Id)
            book1DefSideOfLineId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneDefinitionSideOfLine.get_view_text,
                HilbertChapterOneDefinitionSideOfLine.initialize,
                HilbertChapterOneDefinitionSideOfLine.loop,
                HilbertChapterOneDefinitionSideOfLine.clean,
                "Definition: Side of Line", book1Sec4Id)
            book1DefPolygonId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneDefinitionPolygon.get_view_text,
                HilbertChapterOneDefinitionPolygon.initialize,
                HilbertChapterOneDefinitionPolygon.loop,
                HilbertChapterOneDefinitionPolygon.clean,
                "Definition: Polygon", book1Sec4Id)
            book1Theorem6Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem6.get_view_text,
                HilbertChapterOneTheorem6.initialize,
                HilbertChapterOneTheorem6.loop,
                HilbertChapterOneTheorem6.clean,
                "Theorem 6", book1Sec4Id)
            book1Theorem7Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem7.get_view_text,
                HilbertChapterOneTheorem7.initialize,
                HilbertChapterOneTheorem7.loop,
                HilbertChapterOneTheorem7.clean,
                "Theorem 7", book1Sec4Id)
end

end