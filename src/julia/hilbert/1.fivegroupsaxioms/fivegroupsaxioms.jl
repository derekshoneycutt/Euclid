module HilbertChapterOne

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry
using ..EuclidLatex
using ..NullAnimation

include("./chapter_one_overview.jl")
include("./chapter_one_connection.jl")
include("./chapter_one_order.jl")
include("./chapter_one_consequences.jl")
include("./chapter_one_parallels.jl")
include("./chapter_one_congruence.jl")
include("./chapter_one_congruence_consequences.jl")
include("./chapter_one_continuity.jl")

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
        state_ptr, HilbertChapterOneOverview.animation_entry,
        "1. The Five Groups of Axioms, §1", root_id)
        book1_sec2_id = register_child_animation(
            state_ptr, HilbertChapterOneConnection.animation_entry,
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
            state_ptr, HilbertChapterOneOrder.animation_entry,
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
            state_ptr, HilbertChapterOneConsequences.animation_entry,
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
            state_ptr, HilbertChapterOneParallels.animation_entry,
            "§5 Group III: Axiom of Parallels", book1_id)
            book1_axiom_i_i_i1_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomIII1.animation_entry,
                "Axiom III", book1_sec5_id)
            book1_theorem8_id = register_child_animation(
                state_ptr, HilbertChapterOneTheorem8.animation_entry,
                "Theorem 8", book1_sec5_id)

        book1_sec6_id = register_child_animation(
            state_ptr, HilbertChapterOneCongruence.animation_entry,
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
            state_ptr, HilbertChapterOneCongruenceConsequences.animation_entry,
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
            state_ptr, HilbertChapterOneContinuity.animation_entry,
            "§8 Group V: Axiom of Continuity", book1_id)
            book1_axiom_v_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomV.animation_entry,
                "Axiom V", book1_sec8_id)
            book1_axiom_completeness_id = register_child_animation(
                state_ptr, HilbertChapterOneAxiomCompleteness.animation_entry,
                "Axiom of Completeness", book1_sec8_id)
end

end