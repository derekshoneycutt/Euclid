module HilbertChapterOne

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry
using ..EuclidLatex
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


"""Emit the Book I overview view text for the five-groups-of-axioms sequence."""
function get_view_text_book1(state_ptr::Ptr{Cvoid})
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

"""Publish this category view when its animation node is selected."""
function initialize_view_book1(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_book1)
end

"""Dispatch lifecycle operations for the Hilbert Book I category."""
function animation_entry_book1(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book1(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Emit the Book I connection-axioms view text."""
function get_view_text_book1_connection(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §2 Group I: Axioms of Connection

The axioms of this group establish a connection between the concepts indicated above; namely, points, straight lines, and planes.

...

Axioms I, 1-2 contain statements concerning points and straight lines only; that is, concerning the elements of plane geometry. We will call them, therefore, the plane axioms of group I, in order to distinguish them from the axioms I, 3-7, which we will designate briefly as the space axioms of this group.
Of the theorems which follow from the axioms I, 3-7, we shall mention only 2."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§2 Group I: Axioms of Connection}

The axioms of this group establish a connection between the concepts indicated above; namely, points, straight lines, and planes.

...

Axioms I, 1-2 contain statements concerning points and straight lines only; that is, concerning the elements of plane geometry. We will call them, therefore, the plane axioms of group I, in order to distinguish them from the axioms I, 3-7, which we will designate briefly as the space axioms of this group.
Of the theorems which follow from the axioms I, 3-7, we shall mention only 2."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_book1_connection(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_book1_connection)
end

"""Dispatch lifecycle operations for the Hilbert connection category."""
function animation_entry_book1_connection(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book1_connection(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Emit the Book I order-axioms view text."""
function get_view_text_book1_order(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §3 Group II: Axioms of Order

The axioms of this group define the idea expressed by the word "between," and make possible, upon the basis of this idea, an order of sequence of the points upon a straight line, in a plane, and in space. The points of a straight line have a certain relation to one another which the word "between" serves to describe.

...

Axioms II, 1-4 contain statements concerning the points of a straight line only, and, hence, we will call them the linear axioms of group II. Axiom II, 5 relates to the elements of plane geometry and, consequently, shall be called the plane axiom of group II."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§3 Group II: Axioms of Order}

The axioms of this group define the idea expressed by the word "between," and make possible, upon the basis of this idea, an order of sequence of the points upon a straight line, in a plane, and in space. The points of a straight line have a certain relation to one another which the word "between" serves to describe.

...

Axioms II, 1-4 contain statements concerning the points of a straight line only, and, hence, we will call them the linear axioms of group II. Axiom II, 5 relates to the elements of plane geometry and, consequently, shall be called the plane axiom of group II."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_book1_order(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_book1_order)
end

"""Dispatch lifecycle operations for the Hilbert order category."""
function animation_entry_book1_order(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book1_order(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Emit the Book I consequences view text."""
function get_view_text_book1_consequences(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §4 Consequences of the Axioms of Connection and Order

By the aid of the four linear axioms II, 1-4, we can easily deduce several theorems."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§4 Consequences of the Axioms of Connection and Order}

By the aid of the four linear axioms II, 1-4, we can easily deduce several theorems."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_book1_consequences(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_book1_consequences)
end

"""Dispatch lifecycle operations for the Hilbert consequences category."""
function animation_entry_book1_consequences(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book1_consequences(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Emit the Book I parallels view text."""
function get_view_text_book1_parallels(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §5 Group III: Axiom of Parallels (Euclid's Axiom)

The introduction of this axiom simplifies greatly the fundamental principles of geometry and facilitates in no small degree its development.

...

The axiom of parallels is a plane axiom."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§5 Group III: Axiom of Parallels (Euclid's Axiom)}

The introduction of this axiom simplifies greatly the fundamental principles of geometry and facilitates in no small degree its development.

...

The axiom of parallels is a plane axiom."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_book1_parallels(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_book1_parallels)
end

"""Dispatch lifecycle operations for the Hilbert parallels category."""
function animation_entry_book1_parallels(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book1_parallels(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Emit the Book I congruence-axioms view text."""
function get_view_text_book1_congruence(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §5 Group IV: Axioms of Congruence

The axioms of this group define the idea of congruence or displacement.

Segments stand in a certain relation to one another which is described by the word "congruent."

...

Axioms IV, 1-3 contain statements concerning the congruence of segments of a straight line only. They may, therefore, be called the linear axioms of group IV. Axioms IV, 4, 5 contain statements relating to the congruence of angles. Axiom IV, 6 gives the connection between the congruence of segments and the congruence of angles. Axioms IV, 4-6 contain statements regarding the elements of plane geometry and may be called the plane axioms of group IV."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§5 Group IV: Axioms of Congruence}

The axioms of this group define the idea of congruence or displacement.

Segments stand in a certain relation to one another which is described by the word "congruent."

...

Axioms IV, 1-3 contain statements concerning the congruence of segments of a straight line only. They may, therefore, be called the linear axioms of group IV. Axioms IV, 4, 5 contain statements relating to the congruence of angles. Axiom IV, 6 gives the connection between the congruence of segments and the congruence of angles. Axioms IV, 4-6 contain statements regarding the elements of plane geometry and may be called the plane axioms of group IV."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_book1_congruence(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_book1_congruence)
end

"""Dispatch lifecycle operations for the Hilbert congruence category."""
function animation_entry_book1_congruence(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book1_congruence(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Emit the Book I consequences-of-congruence view text."""
function get_view_text_book1_consequences_congruence(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §7 Consequences of the Axioms of Congruence

Suppose the segment AB is congruent to the segment A'B'. Since, according to axiom IV, 1, the segment AB is congruent to itself, it follows from axiom IV, 2 that A'B' is congruent to AB; that is to say, if AB ≡ A'B', then A'B' ≡ AB. We say, then, that the two segments are congruent to one another.

Let A, B, C, D, ..., K, L and A', B', C', D', ..., K', L' be two series of points on the straight lines a and a', respectively, so that all the corresponding segments AB and A'B', AC and A'C', BC and B'C', ..., KL and K'L' are respectively congruent. Then the two series of points are said to be congruent to one another. A and A', B and B', ..., L and L' are called corresponding points of the two congruent series of points.

From the linear axioms IV, 1-3, we can easily deduce several theorems."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§7 Consequences of the Axioms of Congruence}

Suppose the segment $AB$ is congruent to the segment $A'B'$. Since, according to axiom IV, 1, the segment $AB$ is congruent to itself, it follows from axiom IV, 2 that $A'B'$ is congruent to $AB$; that is to say, if $AB \equiv A'B'$, then $A'B' \equiv AB$. We say, then, that the two segments are congruent to one another.

Let $A, B, C, D, ..., K, L$ and $A', B', C', D', ..., K', L'$ be two series of points on the straight lines $a$ and $a'$, respectively, so that all the corresponding segments $AB$ and $A'B'$, $AC$ and $A'C'$, $BC$ and $B'C', ..., KL$ and $K'L'$ are respectively congruent. Then the two series of points are said to be congruent to one another. $A$ and $A', B and B', ..., L and L'$ are called corresponding points of the two congruent series of points.

From the linear axioms IV, 1-3, we can easily deduce several theorems."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_book1_consequences_congruence(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(
        state_ptr, get_view_text_book1_consequences_congruence)
end

"""Dispatch lifecycle operations for the congruence consequences category."""
function animation_entry_book1_consequences_congruence(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book1_consequences_congruence(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Emit the Book I continuity-axioms view text."""
function get_view_text_book1_continuity(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms §8 Group V. Axiom of Continuity. (Archimedean Axiom.)

This axiom makes possible the introduction into geometry of the idea of continuity. In order to state this axiom, we must first establish a convention concerning the equality of two segments. For this purpose, we can either base our idea of equality upon the axioms relating to the congruence of segments and define as "equal" the correspondingly congruent segments, or, upon the basis of groups I and II, we may determine how, by suitable constructions (see Chap. V, Section 24), a segment is to be laid off from a point of a given straight line so that a new, definite segment is obtained "equal" to it. In conformity with such a convention, the axiom of Archimedes may be stated as follows.

The axiom of Archimedes is a linear axiom.

...

Remark. To the preceding five groups of axioms, we may add the axiom of completeness, which, although not of a purely geometrical nature, merits particular attention from a theoretical point of view."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§8 Group V. Axiom of Continuity. (Archimedean Axiom.)}

This axiom makes possible the introduction into geometry of the idea of continuity. In order to state this axiom, we must first establish a convention concerning the equality of two segments. For this purpose, we can either base our idea of equality upon the axioms relating to the congruence of segments and define as "equal" the correspondingly congruent segments, or, upon the basis of groups I and II, we may determine how, by suitable constructions (see Chap. V, Section 24), a segment is to be laid off from a point of a given straight line so that a new, definite segment is obtained "equal" to it. In conformity with such a convention, the axiom of Archimedes may be stated as follows.

The axiom of Archimedes is a linear axiom.

...

Remark. To the preceding five groups of axioms, we may add the axiom of completeness, which, although not of a purely geometrical nature, merits particular attention from a theoretical point of view."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_book1_continuity(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_book1_continuity)
end

"""Dispatch lifecycle operations for the Hilbert continuity category."""
function animation_entry_book1_continuity(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book1_continuity(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Derive a stable child animation id from a parent id and child name."""
function stable_child_id(parent_stable_id::AbstractString, name::AbstractString)
    OdinJuliaBridge.animation_stable_id_from_key(
        "child:" * String(parent_stable_id) * ":" * String(name))
end

"""Register a child animation interface under a parent stable id, returning its id."""
function register_child_animation(
    state_ptr::Ptr{Cvoid}, entry, name::AbstractString,
    parent_stable_id::AbstractString)

    child_stable_id = stable_child_id(parent_stable_id, name)
    OdinJuliaBridge.add_child_animation_interface(
        state_ptr, entry, String(name),
        child_stable_id, String(parent_stable_id))

    return child_stable_id
end

"""Register the five-groups-of-axioms animation interfaces under the root id."""
function init_euclid_scripts(state_ptr::Ptr{Cvoid}, root_id)
    book1_id = register_child_animation(
        state_ptr, animation_entry_book1,
        "1. The Five Groups of Axioms, §1", root_id)
        book1_sec2_id = register_child_animation(
            state_ptr, animation_entry_book1_connection,
            "§2 Group I: Axioms of Connection", book1_id)
            book1_axiom_i1_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomI1.animation_entry,
                "Axiom I,1", book1_sec2_id)
            book1_axiom_i2_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomI2.animation_entry,
                "Axiom I,2", book1_sec2_id)
            book1_axiom_i3_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomI3.animation_entry,
                "Axiom I,3", book1_sec2_id)
            book1_axiom_i4_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomI4.animation_entry,
                "Axiom I,4", book1_sec2_id)
            book1_axiom_i5_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomI5.animation_entry,
                "Axiom I,5", book1_sec2_id)
            book1_axiom_i6_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomI6.animation_entry,
                "Axiom I,6", book1_sec2_id)
            book1_axiom_i7_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomI7.animation_entry,
                "Axiom I,7", book1_sec2_id)
            book1_theorem1_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem1.animation_entry,
                "Theorem 1", book1_sec2_id)
            book1_theorem2_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem2.animation_entry,
                "Theorem 2", book1_sec2_id)

        book1_sec3_id = register_child_animation(
            state_ptr, animation_entry_book1_order,
            "§3 Group II: Axioms of Order", book1_id)
            book1_axiom_i_i1_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomII1.animation_entry,
                "Axiom II,1", book1_sec3_id)
            book1_axiom_i_i2_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomII2.animation_entry,
                "Axiom II,2", book1_sec3_id)
            book1_axiom_i_i3_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomII3.animation_entry,
                "Axiom II,3", book1_sec3_id)
            book1_axiom_i_i4_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomII4.animation_entry,
                "Axiom II,4", book1_sec3_id)
            book1_def_segments_id = register_child_animation(
                state_ptr, HilbertChapterOneDefSegments.animation_entry,
                "Definition: Segments", book1_sec3_id)
            book1_axiom_i_i5_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomII5.animation_entry,
                "Axiom II,5", book1_sec3_id)

        book1_sec4_id = register_child_animation(
            state_ptr, animation_entry_book1_consequences,
            "§4 Consequences after Group II", book1_id)
            book1_theorem3_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem3.animation_entry,
                "Theorem 3", book1_sec4_id)
            book1_theorem4_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem4.animation_entry,
                "Theorem 4", book1_sec4_id)
            book1_theorem5_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem5.animation_entry,
                "Theorem 5", book1_sec4_id)
            book1_def_half_rays_id = register_child_animation(
                state_ptr, HilbertChapterOneDefHalfRays.animation_entry,
                "Definition: Half-rays", book1_sec4_id)
            book1_def_side_of_line_id = register_child_animation(
                state_ptr, HilbertChapterOneDefinitionSideOfLine.animation_entry,
                "Definition: Side of Line", book1_sec4_id)
            book1_def_polygon_id = register_child_animation(
                state_ptr, HilbertChapterOneDefinitionPolygon.animation_entry,
                "Definition: Polygon", book1_sec4_id)
            book1_theorem6_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem6.animation_entry,
                "Theorem 6", book1_sec4_id)
            book1_theorem7_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem7.animation_entry,
                "Theorem 7", book1_sec4_id)

        book1_sec5_id = register_child_animation(
            state_ptr, animation_entry_book1_parallels,
            "§5 Group III: Axiom of Parallels", book1_id)
            book1_axiom_i_i_i1_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomIII1.animation_entry,
                "Axiom III", book1_sec5_id)
            book1_theorem8_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem8.animation_entry,
                "Theorem 8", book1_sec5_id)

        book1_sec6_id = register_child_animation(
            state_ptr, animation_entry_book1_congruence,
            "§6 Group IV: Axioms of Congruence", book1_id)
            book1_axiom_i_v1_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomIV1.animation_entry,
                "Axiom IV,1", book1_sec6_id)
            book1_axiom_i_v2_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomIV2.animation_entry,
                "Axiom IV,2", book1_sec6_id)
            book1_axiom_i_v3_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomIV3.animation_entry,
                "Axiom IV,3", book1_sec6_id)
            book1_def_angle_id = register_child_animation(
                state_ptr, HilbertChapterOneDefAngle.animation_entry,
                "Definition: Angle", book1_sec6_id)
            book1_axiom_i_v4_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomIV4.animation_entry,
                "Axiom IV,4", book1_sec6_id)
            book1_axiom_i_v5_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomIV5.animation_entry,
                "Axiom IV,5", book1_sec6_id)
            book1_def_triangle_angle_id = register_child_animation(
                state_ptr, HilbertChapterOneDefTriangleAngle.animation_entry,
                "Definition: Triangle Angle", book1_sec6_id)
            book1_axiom_i_v6_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomIV6.animation_entry,
                "Axiom IV,6", book1_sec6_id)

        book1_sec7_id = register_child_animation(
            state_ptr, animation_entry_book1_consequences_congruence,
            "§7 Consequences after Group IV", book1_id)
            book1_theorem9_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem9.animation_entry,
                "Theorem 9", book1_sec7_id)
            book1_def_congruent_angles_id = register_child_animation(
                state_ptr, HilbertChapterOneDefCongruentAngles.animation_entry,
                "Definition: Congruent Angles", book1_sec7_id)
            book1_def_supplementary_angles_id = register_child_animation(
                state_ptr, HilbertChapterOneDefSupplementaryAngles.animation_entry,
                "Definition: Supplementary Angles", book1_sec7_id)
            book1_def_congruent_triangles_id = register_child_animation(
                state_ptr, HilbertChapterOneDefCongruentTriangles.animation_entry,
                "Definition: Congruent Triangles", book1_sec7_id)
            book1_theorem10_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem10.animation_entry,
                "Theorem 10", book1_sec7_id)
            book1_theorem11_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem11.animation_entry,
                "Theorem 11", book1_sec7_id)
            book1_theorem12_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem12.animation_entry,
                "Theorem 12", book1_sec7_id)
            book1_theorem13_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem13.animation_entry,
                "Theorem 13", book1_sec7_id)
            book1_theorem14_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem14.animation_entry,
                "Theorem 14", book1_sec7_id)
            book1_theorem15_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem15.animation_entry,
                "Theorem 15", book1_sec7_id)
            book1_theorem16_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem16.animation_entry,
                "Theorem 16", book1_sec7_id)
            book1_definition_figure_id = register_child_animation(
                state_ptr, HilbertChapterOneDefinitionFigure.animation_entry,
                "Definition: Figure", book1_sec7_id)
            book1_theorem17_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem17.animation_entry,
                "Theorem 17", book1_sec7_id)
            book1_theorem18_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem18.animation_entry,
                "Theorem 18", book1_sec7_id)
            book1_theorem19_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem19.animation_entry,
                "Theorem 19", book1_sec7_id)
            book1_theorem20_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem20.animation_entry,
                "Theorem 20", book1_sec7_id)
            book1_definition_circle_id = register_child_animation(
                state_ptr, HilbertChapterOneDefinitionCircle.animation_entry,
                "Definition: Circle", book1_sec7_id)

        book1_sec8_id = register_child_animation(
            state_ptr, animation_entry_book1_continuity,
            "§8 Group V: Axiom of Continuity", book1_id)
            book1_axiom_v_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomV.animation_entry,
                "Axiom V", book1_sec8_id)
            book1_axiom_completeness_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomCompleteness.animation_entry,
                "Axiom of Completeness", book1_sec8_id)
end

end