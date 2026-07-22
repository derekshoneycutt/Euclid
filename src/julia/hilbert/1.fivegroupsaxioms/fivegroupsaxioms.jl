module HilbertChapterOne

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry
using ..NullAnimation

include("./axiom_I1.jl")
include("./axiom_I2.jl")
include("./axiom_I3.jl")
include("./axiom_I4.jl")
include("./axiom_IV5.jl")
include("./axiom_I5.jl")
include("./axiom_IV6.jl")
include("./axiom_I6.jl")
include("./axiom_I7.jl")
include("./axiom_II1.jl")
include("./axiom_II2.jl")
include("./axiom_II3.jl")
include("./axiom_II4.jl")
include("./axiom_II5.jl")
include("./axiom_III1.jl")
include("./axiom_IV1.jl")
include("./axiom_IV2.jl")
include("./axiom_IV3.jl")
include("./axiom_IV4.jl")
include("./def_angle.jl")
include("./def_triangle_angle.jl")
include("./def_segments.jl")
include("./theorem_1.jl")
include("./theorem_2.jl")
include("./theorem_3.jl")
include("./theorem_4.jl")
include("./theorem_5.jl")
include("./theorem_6.jl")
include("./theorem_7.jl")
include("./theorem_8.jl")
include("./theorem_9.jl")
include("./def_halfrays.jl")
include("./def_sideofline.jl")
include("./def_polygon.jl")
include("./def_congruent_angles.jl")
include("./def_supplementary_angles.jl")
include("./def_congruent_triangles.jl")
include("./theorem_10.jl")
include("./theorem_11.jl")
include("./theorem_12.jl")
include("./theorem_13.jl")
include("./theorem_14.jl")
include("./theorem_15.jl")
include("./theorem_16.jl")
include("./def_figure.jl")
include("./theorem_17.jl")
include("./theorem_18.jl")
include("./theorem_19.jl")
include("./theorem_20.jl")
include("./def_circle.jl")
include("./axiom_V.jl")
include("./axiom_completeness.jl")


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

function get_view_text_BookI_parallels(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §5 Group III: Axiom of Parallels (Euclid's Axiom)

The introduction of this axiom simplifies greatly the fundamental principles of geometry and facilitates in no small degree its development.

...

The axiom of parallels is a plane axiom."""
end

function get_view_text_BookI_congruence(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §5 Group IV: Axioms of Congruence

The axioms of this group define the idea of congruence or displacement.

Segments stand in a certain relation to one another which is described by the word "congruent."

...

Axioms IV, 1-3 contain statements concerning the congruence of segments of a straight line only. They may, therefore, be called the linear axioms of group IV. Axioms IV, 4, 5 contain statements relating to the congruence of angles. Axiom IV, 6 gives the connection between the congruence of segments and the congruence of angles. Axioms IV, 4-6 contain statements regarding the elements of plane geometry and may be called the plane axioms of group IV."""
end

function get_view_text_BookI_consequences_congruence(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §7 Consequences of the Axioms of Congruence

Suppose the segment AB is congruent to the segment A'B'. Since, according to axiom IV, 1, the segment AB is congruent to itself, it follows from axiom IV, 2 that A'B' is congruent to AB; that is to say, if AB ≡ A'B', then A'B' ≡ AB. We say, then, that the two segments are congruent to one another.

Let A, B, C, D, ..., K, L and A', B', C', D', ..., K', L' be two series of points on the straight lines a and a', respectively, so that all the corresponding segments AB and A'B', AC and A'C', BC and B'C', ..., KL and K'L' are respectively congruent. Then the two series of points are said to be congruent to one another. A and A', B and B', ..., L and L' are called corresponding points of the two congruent series of points.

From the linear axioms IV, 1-3, we can easily deduce several theorems."""
end

function get_view_text_BookI_continuity(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §8 Group V. Axiom of Continuity. (Archimedean Axiom.)

This axiom makes possible the introduction into geometry of the idea of continuity. In order to state this axiom, we must first establish a convention concerning the equality of two segments. For this purpose, we can either base our idea of equality upon the axioms relating to the congruence of segments and define as "equal" the correspondingly congruent segments, or, upon the basis of groups I and II, we may determine how, by suitable constructions (see Chap. V, Section 24), a segment is to be laid off from a point of a given straight line so that a new, definite segment is obtained "equal" to it. In conformity with such a convention, the axiom of Archimedes may be stated as follows.

The axiom of Archimedes is a linear axiom.

...

Remark. To the preceding five groups of axioms, we may add the axiom of completeness, which, although not of a purely geometrical nature, merits particular attention from a theoretical point of view."""
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

        book1Sec5Id = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, get_view_text_BookI_parallels, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "§5 Group III: Axiom of Parallels", book1Id)
            book1AxiomIII1Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomIII1.get_view_text,
                HilbertChapterOneAxiomIII1.initialize,
                HilbertChapterOneAxiomIII1.loop,
                HilbertChapterOneAxiomIII1.clean,
                "Axiom III", book1Sec5Id)
            book1Theorem8Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem8.get_view_text,
                HilbertChapterOneTheorem8.initialize,
                HilbertChapterOneTheorem8.loop,
                HilbertChapterOneTheorem8.clean,
                "Theorem 8", book1Sec5Id)

        book1Sec6Id = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, get_view_text_BookI_congruence, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "§6 Group IV: Axioms of Congruence", book1Id)
            book1AxiomIV1Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomIV1.get_view_text,
                HilbertChapterOneAxiomIV1.initialize,
                HilbertChapterOneAxiomIV1.loop,
                HilbertChapterOneAxiomIV1.clean,
                "Axiom IV,1", book1Sec6Id)
            book1AxiomIV2Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomIV2.get_view_text,
                HilbertChapterOneAxiomIV2.initialize,
                HilbertChapterOneAxiomIV2.loop,
                HilbertChapterOneAxiomIV2.clean,
                "Axiom IV,2", book1Sec6Id)
            book1AxiomIV3Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomIV3.get_view_text,
                HilbertChapterOneAxiomIV3.initialize,
                HilbertChapterOneAxiomIV3.loop,
                HilbertChapterOneAxiomIV3.clean,
                "Axiom IV,3", book1Sec6Id)
            book1DefAngleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneDefAngle.get_view_text,
                HilbertChapterOneDefAngle.initialize,
                HilbertChapterOneDefAngle.loop,
                HilbertChapterOneDefAngle.clean,
                "Definition: Angle", book1Sec6Id)
            book1AxiomIV4Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomIV4.get_view_text,
                HilbertChapterOneAxiomIV4.initialize,
                HilbertChapterOneAxiomIV4.loop,
                HilbertChapterOneAxiomIV4.clean,
                "Axiom IV,4", book1Sec6Id)
            book1AxiomIV5Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomIV5.get_view_text,
                HilbertChapterOneAxiomIV5.initialize,
                HilbertChapterOneAxiomIV5.loop,
                HilbertChapterOneAxiomIV5.clean,
                "Axiom IV,5", book1Sec6Id)
            book1DefTriangleAngleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneDefTriangleAngle.get_view_text,
                HilbertChapterOneDefTriangleAngle.initialize,
                HilbertChapterOneDefTriangleAngle.loop,
                HilbertChapterOneDefTriangleAngle.clean,
                "Definition: Triangle Angle", book1Sec6Id)
            book1AxiomIV6Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomIV6.get_view_text,
                HilbertChapterOneAxiomIV6.initialize,
                HilbertChapterOneAxiomIV6.loop,
                HilbertChapterOneAxiomIV6.clean,
                "Axiom IV,6", book1Sec6Id)

        book1Sec7Id = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, get_view_text_BookI_consequences_congruence,
            NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "§7 Consequences after Group IV", book1Id)
            book1Theorem9Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem9.get_view_text,
                HilbertChapterOneTheorem9.initialize,
                HilbertChapterOneTheorem9.loop,
                HilbertChapterOneTheorem9.clean,
                "Theorem 9", book1Sec7Id)
            book1DefCongruentAnglesId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneDefCongruentAngles.get_view_text,
                HilbertChapterOneDefCongruentAngles.initialize,
                HilbertChapterOneDefCongruentAngles.loop,
                HilbertChapterOneDefCongruentAngles.clean,
                "Definition: Congruent Angles", book1Sec7Id)
            book1DefSupplementaryAnglesId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneDefSupplementaryAngles.get_view_text,
                HilbertChapterOneDefSupplementaryAngles.initialize,
                HilbertChapterOneDefSupplementaryAngles.loop,
                HilbertChapterOneDefSupplementaryAngles.clean,
                "Definition: Supplementary Angles", book1Sec7Id)
            book1DefCongruentTrianglesId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneDefCongruentTriangles.get_view_text,
                HilbertChapterOneDefCongruentTriangles.initialize,
                HilbertChapterOneDefCongruentTriangles.loop,
                HilbertChapterOneDefCongruentTriangles.clean,
                "Definition: Congruent Triangles", book1Sec7Id)
            book1Theorem10Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem10.get_view_text,
                HilbertChapterOneTheorem10.initialize,
                HilbertChapterOneTheorem10.loop,
                HilbertChapterOneTheorem10.clean,
                "Theorem 10", book1Sec7Id)
            book1Theorem11Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem11.get_view_text,
                HilbertChapterOneTheorem11.initialize,
                HilbertChapterOneTheorem11.loop,
                HilbertChapterOneTheorem11.clean,
                "Theorem 11", book1Sec7Id)
            book1Theorem12Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem12.get_view_text,
                HilbertChapterOneTheorem12.initialize,
                HilbertChapterOneTheorem12.loop,
                HilbertChapterOneTheorem12.clean,
                "Theorem 12", book1Sec7Id)
            book1Theorem13Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem13.get_view_text,
                HilbertChapterOneTheorem13.initialize,
                HilbertChapterOneTheorem13.loop,
                HilbertChapterOneTheorem13.clean,
                "Theorem 13", book1Sec7Id)
            book1Theorem14Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem14.get_view_text,
                HilbertChapterOneTheorem14.initialize,
                HilbertChapterOneTheorem14.loop,
                HilbertChapterOneTheorem14.clean,
                "Theorem 14", book1Sec7Id)
            book1Theorem15Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem15.get_view_text,
                HilbertChapterOneTheorem15.initialize,
                HilbertChapterOneTheorem15.loop,
                HilbertChapterOneTheorem15.clean,
                "Theorem 15", book1Sec7Id)
            book1Theorem16Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem16.get_view_text,
                HilbertChapterOneTheorem16.initialize,
                HilbertChapterOneTheorem16.loop,
                HilbertChapterOneTheorem16.clean,
                "Theorem 16", book1Sec7Id)
            book1DefinitionFigureId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneDefinitionFigure.get_view_text,
                HilbertChapterOneDefinitionFigure.initialize,
                HilbertChapterOneDefinitionFigure.loop,
                HilbertChapterOneDefinitionFigure.clean,
                "Definition: Figure", book1Sec7Id)
            book1Theorem17Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem17.get_view_text,
                HilbertChapterOneTheorem17.initialize,
                HilbertChapterOneTheorem17.loop,
                HilbertChapterOneTheorem17.clean,
                "Theorem 17", book1Sec7Id)
            book1Theorem18Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem18.get_view_text,
                HilbertChapterOneTheorem18.initialize,
                HilbertChapterOneTheorem18.loop,
                HilbertChapterOneTheorem18.clean,
                "Theorem 18", book1Sec7Id)
            book1Theorem19Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem19.get_view_text,
                HilbertChapterOneTheorem19.initialize,
                HilbertChapterOneTheorem19.loop,
                HilbertChapterOneTheorem19.clean,
                "Theorem 19", book1Sec7Id)
            book1Theorem20Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneTheorem20.get_view_text,
                HilbertChapterOneTheorem20.initialize,
                HilbertChapterOneTheorem20.loop,
                HilbertChapterOneTheorem20.clean,
                "Theorem 20", book1Sec7Id)
            book1DefinitionCircleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneDefinitionCircle.get_view_text,
                HilbertChapterOneDefinitionCircle.initialize,
                HilbertChapterOneDefinitionCircle.loop,
                HilbertChapterOneDefinitionCircle.clean,
                "Definition: Circle", book1Sec7Id)

        book1Sec8Id = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, get_view_text_BookI_continuity, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "§8 Group V: Axiom of Continuity", book1Id)
            book1AxiomVId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomV.get_view_text,
                HilbertChapterOneAxiomV.initialize,
                HilbertChapterOneAxiomV.loop, HilbertChapterOneAxiomV.clean,
                "Axiom V", book1Sec8Id)
            book1AxiomCompletenessId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, HilbertChapterOneAxiomCompleteness.get_view_text,
                HilbertChapterOneAxiomCompleteness.initialize,
                HilbertChapterOneAxiomCompleteness.loop,
                HilbertChapterOneAxiomCompleteness.clean,
                "Axiom of Completeness", book1Sec8Id)
end

end