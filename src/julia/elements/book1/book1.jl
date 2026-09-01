module ElementsOne

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry
using ..EuclidLatex
using ..NullAnimation

include("./def_001_point.jl")
include("./def_002_line.jl")
include("./def_003_linextrem.jl")
include("./def_004_straightline.jl")
include("./def_005_surface.jl")
include("./def_006_surfextrem.jl")
include("./def_007_planesurface.jl")
include("./def_008_angle.jl")
include("./def_010_perpendicular.jl")
include("./def_011_obtuseangle.jl")
include("./def_012_acuteangle.jl")
include("./def_013_boundary.jl")
include("./def_014_figure.jl")
include("./def_015_circle.jl")
include("./def_017_diameter.jl")
include("./def_018_semicircle.jl")
include("./def_019a_trilateral.jl")
include("./def_019b_quadrilateral.jl")
include("./def_019c_multilateral.jl")
include("./def_020a_equilateral.jl")
include("./def_020b_isosceles.jl")
include("./def_020c_scalene.jl")
include("./def_021a_righttriangle.jl")
include("./def_021b_obtusetriangle.jl")
include("./def_021c_acutetriangle.jl")
include("./def_022a_square.jl")
include("./def_022b_oblong.jl")
include("./def_022c_rhombus.jl")
include("./def_022d_rhomboid.jl")
include("./def_022d_trapezia.jl")
include("./def_023_parallel.jl")

include("./post_01_drawline.jl")
include("./post_02_finiteline.jl")
include("./post_03_drawcircle.jl")
include("./post_04_equalright.jl")
include("./post_05_nonparallel.jl")

include("./commonnotions.jl")

include("./prop_01.jl")
include("./prop_02.jl")

"""Emit the Book I root view text."""
function get_view_text_book_1(state_ptr::Ptr{Cvoid})
    latex = raw"\textbf{Euclid Elements - Book I}"
    fallback = "Euclid Elements - Book I"
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_book_1(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_book_1)
end

"""Dispatch lifecycle operations for the Book I category animation."""
function animation_entry_book_1(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book_1(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Emit the Book I Definitions section view text."""
function get_view_text_book_1_defs(state_ptr::Ptr{Cvoid})
    latex = raw"\textbf{Euclid Elements - Book I - Definitions}"
    fallback = "Euclid Elements - Book I - Definitions"
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_book_1_defs(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_book_1_defs)
end

"""Dispatch lifecycle operations for the Book I Definitions category."""
function animation_entry_book_1_defs(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book_1_defs(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Emit the Book I Postulates section view text."""
function get_view_text_book_1_posts(state_ptr::Ptr{Cvoid})
    latex = raw"\textbf{Euclid Elements - Book I - Postulates}"
    fallback = "Euclid Elements - Book I - Postulates"
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_book_1_posts(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_book_1_posts)
end

"""Dispatch lifecycle operations for the Book I Postulates category."""
function animation_entry_book_1_posts(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book_1_posts(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Emit the Book I Propositions section view text."""
function get_view_text_book_1_props(state_ptr::Ptr{Cvoid})
    latex = raw"\textbf{Euclid Elements - Book I - Propositions}"
    fallback = "Euclid Elements - Book I - Propositions"
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_book_1_props(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_book_1_props)
end

"""Dispatch lifecycle operations for the Book I Propositions category."""
function animation_entry_book_1_props(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize_view_book_1_props(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        NullAnimation.loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        NullAnimation.clean(state_ptr)
    else
        return false
    end
    return true
end

"""Return the stable animation id for a named child of a parent animation."""
function stable_child_id(parent_stable_id::AbstractString, name::AbstractString)
    OdinJuliaBridge.animation_stable_id_from_key(
        "child:" * String(parent_stable_id) * ":" * String(name))
end

"""Register a named child animation under a parent and return its stable id."""
function register_child_animation(
    state_ptr::Ptr{Cvoid}, entry, name::AbstractString,
    parent_stable_id::AbstractString)

    child_stable_id = stable_child_id(parent_stable_id, name)
    OdinJuliaBridge.add_child_animation_interface(
        state_ptr, entry, String(name),
        child_stable_id, String(parent_stable_id))

    return child_stable_id
end

"""Register the Book I animation tree under the Euclid's Elements root."""
function init_euclid_scripts(state_ptr::Ptr{Cvoid}, root_id)
    book1_id = register_child_animation(
        state_ptr, animation_entry_book_1,
        "Book I", root_id)
        book1_defs_id = register_child_animation(
            state_ptr, animation_entry_book_1_defs,
            "Definitions", book1_id)
            book1_defs1_point_id = register_child_animation(
                state_ptr, ElementsOneDefinitionPoint.animation_entry,
                "Point", book1_defs_id)
            book1_defs2_line_id = register_child_animation(
                state_ptr, ElementsOneDefinitionLine.animation_entry,
                "Line", book1_defs_id)
            book1_defs3_line_ex_id = register_child_animation(
                state_ptr, ElementsOneDefinitionLineExtremities.animation_entry,
                "Line Extremities", book1_defs_id)
            book1_defs4_straight_line_id = register_child_animation(
                state_ptr, ElementsOneDefinitionStraightLine.animation_entry,
                "Straight Line", book1_defs_id)
            book1_defs5_surface_id = register_child_animation(
                state_ptr, ElementsOneDefinitionSurface.animation_entry,
                "Surface", book1_defs_id)
            book1_defs6_surf_extrem_id = register_child_animation(
                state_ptr, ElementsOneDefinitionSurfaceExtremity.animation_entry,
                "Surface Extremities", book1_defs_id)
            book1_defs7_plane_surface_id = register_child_animation(
                state_ptr, ElementsOneDefinitionPlaneSurface.animation_entry,
                "Plane Surface", book1_defs_id)
            book1_defs8_plane_angle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionPlaneAngle.animation_entry,
                "Plane Angle", book1_defs_id)
            book1_defs10_perpendicular_id = register_child_animation(
                state_ptr, ElementsOneDefinitionPerpendicular.animation_entry,
                "Right Angles and Perpendicular", book1_defs_id)
            book1_defs11_obtuse_angle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionObtuseAngle.animation_entry,
                "Obtuse Angle", book1_defs_id)
            book1_defs12_acute_angle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionAcuteAngle.animation_entry,
                "Acute Angle", book1_defs_id)
            book1_defs13_boundary_id = register_child_animation(
                state_ptr, ElementsOneDefinitionBoundary.animation_entry,
                "Boundary", book1_defs_id)
            book1_defs14_figure_id = register_child_animation(
                state_ptr, ElementsOneDefinitionFigure.animation_entry,
                "Figure", book1_defs_id)
            book1_defs15_circle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionCircle.animation_entry,
                "Circle", book1_defs_id)
            book1_defs17_diameter_id = register_child_animation(
                state_ptr, ElementsOneDefinitionDiameter.animation_entry,
                "Diameter", book1_defs_id)
            book1_defs18_semicircle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionSemicircle.animation_entry,
                "Semicircle", book1_defs_id)
            book1_defs19_trilateral_id = register_child_animation(
                state_ptr, ElementsOneDefinitionTrilateral.animation_entry,
                "Trilateral Rectilineal Figures", book1_defs_id)
            book1_defs19_quadrilateral_id = register_child_animation(
                state_ptr, ElementsOneDefinitionQuadrilateral.animation_entry,
                "Quadrilateral Rectilineal Figures", book1_defs_id)
            book1_defs19_multilateral_id = register_child_animation(
                state_ptr, ElementsOneDefinitionMultilateral.animation_entry,
                "Multilateral Rectilineal Figures", book1_defs_id)
            book1_defs20_equilateral_id = register_child_animation(
                state_ptr, ElementsOneDefinitionEquilateral.animation_entry,
                "Equaliteral Triangle", book1_defs_id)
            book1_defs20_isosceles_id = register_child_animation(
                state_ptr, ElementsOneDefinitionIsosceles.animation_entry,
                "Isosceles Triangle", book1_defs_id)
            book1_defs20_scalene_id = register_child_animation(
                state_ptr, ElementsOneDefinitionScalene.animation_entry,
                "Scalene Triangle", book1_defs_id)
            book1_defs21_right_triangle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionRightTriangle.animation_entry,
                "Right-Angled Triangle", book1_defs_id)
            book1_defs21_obtuse_triangle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionObtuseTriangle.animation_entry,
                "Obtuse-Angled Triangle", book1_defs_id)
            book1_defs21_acute_triangle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionAcuteTriangle.animation_entry,
                "Acute-Angled Triangle", book1_defs_id)
            book1_defs22_square_id = register_child_animation(
                state_ptr, ElementsOneDefinitionSquare.animation_entry,
                "Square", book1_defs_id)
            book1_defs22_oblong_id = register_child_animation(
                state_ptr, ElementsOneDefinitionOblong.animation_entry,
                "Oblong", book1_defs_id)
            book1_defs22_rhombus_id = register_child_animation(
                state_ptr, ElementsOneDefinitionRhombus.animation_entry,
                "Rhombus", book1_defs_id)
            book1_defs22_rhomboid_id = register_child_animation(
                state_ptr, ElementsOneDefinitionRhomboid.animation_entry,
                "Rhomboid", book1_defs_id)
            book1_defs22_trapezia_id = register_child_animation(
                state_ptr, ElementsOneDefinitionTrapezia.animation_entry,
                "Trapezia", book1_defs_id)
            book1_defs23_parallel_id = register_child_animation(
                state_ptr, ElementsOneDefinitionParallel.animation_entry,
                "Parallel Straight Lines", book1_defs_id)
                
        book1_posts_id = register_child_animation(
            state_ptr, animation_entry_book_1_posts,
            "Postulates", book1_id)
            book1_posts1_draw_line_id = register_child_animation(
                state_ptr, ElementsOnePostulatesDrawLine.animation_entry,
                "Draw a Line", book1_posts_id)
            book1_posts2_finite_line_id = register_child_animation(
                state_ptr, ElementsOnePostulatesFiniteLine.animation_entry,
                "Produce a Finite Line", book1_posts_id)
            book1_posts3_draw_circle_id = register_child_animation(
                state_ptr, ElementsOnePostulatesDrawCircle.animation_entry,
                "Draw a Circle", book1_posts_id)
            book1_posts4_equal_right_angles_id = register_child_animation(
                state_ptr, ElementsOnePostulatesEqualRightAngles.animation_entry,
                "Equal Right Angles", book1_posts_id)
            book1_posts5_non_parallel_lines_id = register_child_animation(
                state_ptr, ElementsOnePostulatesNonParallelLines.animation_entry,
                "Non-Parallel Lines", book1_posts_id)
            
        book1_comm_nots_id = register_child_animation(
            state_ptr, ElementsOneCommonNotions.animation_entry,
            "Common Notions", book1_id)

        book1_props_id = register_child_animation(
            state_ptr, animation_entry_book_1_props,
            "Propositions", book1_id)
            book1_prop01_id = register_child_animation(
                state_ptr, ElementsOneProposition01.animation_entry,
                "Proposition I", book1_props_id)
            book1_prop02_id = register_child_animation(
                state_ptr, ElementsOneProposition02.animation_entry,
                "Proposition II", book1_props_id)
            book1_prop03_id = 0
            book1_prop04_id = 0
            book1_prop05_id = 0
            book1_prop06_id = 0
            book1_prop07_id = 0
            book1_prop08_id = 0
            book1_prop09_id = 0
            book1_prop10_id = 0
            book1_prop11_id = 0
            book1_prop12_id = 0
            book1_prop13_id = 0
            book1_prop14_id = 0
            book1_prop15_id = 0
            book1_prop16_id = 0
            book1_prop17_id = 0
            book1_prop18_id = 0
            book1_prop19_id = 0
            book1_prop20_id = 0
            book1_prop21_id = 0
            book1_prop22_id = 0
            book1_prop23_id = 0
            book1_prop24_id = 0
            book1_prop25_id = 0
            book1_prop26_id = 0
            book1_prop27_id = 0
            book1_prop28_id = 0
            book1_prop29_id = 0
            book1_prop30_id = 0
            book1_prop31_id = 0
            book1_prop32_id = 0
            book1_prop33_id = 0
            book1_prop34_id = 0
            book1_prop35_id = 0
            book1_prop36_id = 0
            book1_prop37_id = 0
            book1_prop38_id = 0
            book1_prop39_id = 0
            book1_prop40_id = 0
            book1_prop41_id = 0
            book1_prop42_id = 0
            book1_prop43_id = 0
            book1_prop44_id = 0
            book1_prop45_id = 0
            book1_prop46_id = 0
            book1_prop47_id = 0
            book1_prop48_id = 0

end

end
