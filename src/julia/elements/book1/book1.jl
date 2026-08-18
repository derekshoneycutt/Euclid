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

function get_view_text_book_1(state_ptr::Ptr{Cvoid})
    latex = raw"\textbf{Euclid Elements - Book I}"
    fallback = "Euclid Elements - Book I"
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function get_view_text_book_1_defs(state_ptr::Ptr{Cvoid})
    latex = raw"\textbf{Euclid Elements - Book I - Definitions}"
    fallback = "Euclid Elements - Book I - Definitions"
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function get_view_text_book_1_posts(state_ptr::Ptr{Cvoid})
    latex = raw"\textbf{Euclid Elements - Book I - Postulates}"
    fallback = "Euclid Elements - Book I - Postulates"
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function get_view_text_book_1_props(state_ptr::Ptr{Cvoid})
    latex = raw"\textbf{Euclid Elements - Book I - Propositions}"
    fallback = "Euclid Elements - Book I - Propositions"
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function stable_child_id(parent_stable_id::AbstractString, name::AbstractString)
    OdinJuliaBridge.animation_stable_id_from_key(
        "child:" * String(parent_stable_id) * ":" * String(name))
end

function register_child_animation(
    state_ptr::Ptr{Cvoid}, get_view_text, init, loop, clean, name::AbstractString,
    parent_stable_id::AbstractString)

    child_stable_id = stable_child_id(parent_stable_id, name)

    OdinJuliaBridge.add_child_animation_interface(
        state_ptr, get_view_text, init, loop, clean, String(name),
        child_stable_id, String(parent_stable_id))

    return child_stable_id
end

function init_euclid_scripts(state_ptr::Ptr{Cvoid}, root_id)
    book1_id = register_child_animation(
        state_ptr, get_view_text_book_1, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean,
        "Book I", root_id)
        book1_defs_id = register_child_animation(
            state_ptr, get_view_text_book_1_defs, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "Definitions", book1_id)
            book1_defs1_point_id = register_child_animation(
                state_ptr, ElementsOneDefinitionPoint.get_view_text,
                ElementsOneDefinitionPoint.initialize,
                ElementsOneDefinitionPoint.loop, ElementsOneDefinitionPoint.clean,
                "Point", book1_defs_id)
            book1_defs2_line_id = register_child_animation(
                state_ptr, ElementsOneDefinitionLine.get_view_text,
                ElementsOneDefinitionLine.initialize,
                ElementsOneDefinitionLine.loop, ElementsOneDefinitionLine.clean,
                "Line", book1_defs_id)
            book1_defs3_line_ex_id = register_child_animation(
                state_ptr, ElementsOneDefinitionLineExtremities.get_view_text,
                ElementsOneDefinitionLineExtremities.initialize,
                ElementsOneDefinitionLineExtremities.loop,
                ElementsOneDefinitionLineExtremities.clean,
                "Line Extremities", book1_defs_id)
            book1_defs4_straight_line_id = register_child_animation(
                state_ptr, ElementsOneDefinitionStraightLine.get_view_text,
                ElementsOneDefinitionStraightLine.initialize,
                ElementsOneDefinitionStraightLine.loop,
                ElementsOneDefinitionStraightLine.clean,
                "Straight Line", book1_defs_id)
            book1_defs5_surface_id = register_child_animation(
                state_ptr, ElementsOneDefinitionSurface.get_view_text,
                ElementsOneDefinitionSurface.initialize,
                ElementsOneDefinitionSurface.loop,
                ElementsOneDefinitionSurface.clean,
                "Surface", book1_defs_id)
            book1_defs6_surf_extrem_id = register_child_animation(
                state_ptr, ElementsOneDefinitionSurfaceExtremity.get_view_text,
                ElementsOneDefinitionSurfaceExtremity.initialize,
                ElementsOneDefinitionSurfaceExtremity.loop,
                ElementsOneDefinitionSurfaceExtremity.clean,
                "Surface Extremities", book1_defs_id)
            book1_defs7_plane_surface_id = register_child_animation(
                state_ptr, ElementsOneDefinitionPlaneSurface.get_view_text,
                ElementsOneDefinitionPlaneSurface.initialize,
                ElementsOneDefinitionPlaneSurface.loop,
                ElementsOneDefinitionPlaneSurface.clean,
                "Plane Surface", book1_defs_id)
            book1_defs8_plane_angle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionPlaneAngle.get_view_text,
                ElementsOneDefinitionPlaneAngle.initialize,
                ElementsOneDefinitionPlaneAngle.loop,
                ElementsOneDefinitionPlaneAngle.clean,
                "Plane Angle", book1_defs_id)
            book1_defs10_perpendicular_id = register_child_animation(
                state_ptr, ElementsOneDefinitionPerpendicular.get_view_text,
                ElementsOneDefinitionPerpendicular.initialize,
                ElementsOneDefinitionPerpendicular.loop,
                ElementsOneDefinitionPerpendicular.clean,
                "Right Angles and Perpendicular", book1_defs_id)
            book1_defs11_obtuse_angle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionObtuseAngle.get_view_text,
                ElementsOneDefinitionObtuseAngle.initialize,
                ElementsOneDefinitionObtuseAngle.loop,
                ElementsOneDefinitionObtuseAngle.clean,
                "Obtuse Angle", book1_defs_id)
            book1_defs12_acute_angle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionAcuteAngle.get_view_text,
                ElementsOneDefinitionAcuteAngle.initialize,
                ElementsOneDefinitionAcuteAngle.loop,
                ElementsOneDefinitionAcuteAngle.clean,
                "Acute Angle", book1_defs_id)
            book1_defs13_boundary_id = register_child_animation(
                state_ptr, ElementsOneDefinitionBoundary.get_view_text,
                ElementsOneDefinitionBoundary.initialize,
                ElementsOneDefinitionBoundary.loop,
                ElementsOneDefinitionBoundary.clean,
                "Boundary", book1_defs_id)
            book1_defs14_figure_id = register_child_animation(
                state_ptr, ElementsOneDefinitionFigure.get_view_text,
                ElementsOneDefinitionFigure.initialize,
                ElementsOneDefinitionFigure.loop,
                ElementsOneDefinitionFigure.clean,
                "Figure", book1_defs_id)
            book1_defs15_circle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionCircle.get_view_text,
                ElementsOneDefinitionCircle.initialize,
                ElementsOneDefinitionCircle.loop,
                ElementsOneDefinitionCircle.clean,
                "Circle", book1_defs_id)
            book1_defs17_diameter_id = register_child_animation(
                state_ptr, ElementsOneDefinitionDiameter.get_view_text,
                ElementsOneDefinitionDiameter.initialize,
                ElementsOneDefinitionDiameter.loop,
                ElementsOneDefinitionDiameter.clean,
                "Diameter", book1_defs_id)
            book1_defs18_semicircle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionSemicircle.get_view_text,
                ElementsOneDefinitionSemicircle.initialize,
                ElementsOneDefinitionSemicircle.loop,
                ElementsOneDefinitionSemicircle.clean,
                "Semicircle", book1_defs_id)
            book1_defs19_trilateral_id = register_child_animation(
                state_ptr, ElementsOneDefinitionTrilateral.get_view_text,
                ElementsOneDefinitionTrilateral.initialize,
                ElementsOneDefinitionTrilateral.loop,
                ElementsOneDefinitionTrilateral.clean,
                "Trilateral Rectilineal Figures", book1_defs_id)
            book1_defs19_quadrilateral_id = register_child_animation(
                state_ptr, ElementsOneDefinitionQuadrilateral.get_view_text,
                ElementsOneDefinitionQuadrilateral.initialize,
                ElementsOneDefinitionQuadrilateral.loop,
                ElementsOneDefinitionQuadrilateral.clean,
                "Quadrilateral Rectilineal Figures", book1_defs_id)
            book1_defs19_multilateral_id = register_child_animation(
                state_ptr, ElementsOneDefinitionMultilateral.get_view_text,
                ElementsOneDefinitionMultilateral.initialize,
                ElementsOneDefinitionMultilateral.loop,
                ElementsOneDefinitionMultilateral.clean,
                "Multilateral Rectilineal Figures", book1_defs_id)
            book1_defs20_equilateral_id = register_child_animation(
                state_ptr, ElementsOneDefinitionEquilateral.get_view_text,
                ElementsOneDefinitionEquilateral.initialize,
                ElementsOneDefinitionEquilateral.loop,
                ElementsOneDefinitionEquilateral.clean,
                "Equaliteral Triangle", book1_defs_id)
            book1_defs20_isosceles_id = register_child_animation(
                state_ptr, ElementsOneDefinitionIsosceles.get_view_text,
                ElementsOneDefinitionIsosceles.initialize,
                ElementsOneDefinitionIsosceles.loop,
                ElementsOneDefinitionIsosceles.clean,
                "Isosceles Triangle", book1_defs_id)
            book1_defs20_scalene_id = register_child_animation(
                state_ptr, ElementsOneDefinitionScalene.get_view_text,
                ElementsOneDefinitionScalene.initialize,
                ElementsOneDefinitionScalene.loop,
                ElementsOneDefinitionScalene.clean,
                "Scalene Triangle", book1_defs_id)
            book1_defs21_right_triangle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionRightTriangle.get_view_text,
                ElementsOneDefinitionRightTriangle.initialize,
                ElementsOneDefinitionRightTriangle.loop,
                ElementsOneDefinitionRightTriangle.clean,
                "Right-Angled Triangle", book1_defs_id)
            book1_defs21_obtuse_triangle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionObtuseTriangle.get_view_text,
                ElementsOneDefinitionObtuseTriangle.initialize,
                ElementsOneDefinitionObtuseTriangle.loop,
                ElementsOneDefinitionObtuseTriangle.clean,
                "Obtuse-Angled Triangle", book1_defs_id)
            book1_defs21_acute_triangle_id = register_child_animation(
                state_ptr, ElementsOneDefinitionAcuteTriangle.get_view_text,
                ElementsOneDefinitionAcuteTriangle.initialize,
                ElementsOneDefinitionAcuteTriangle.loop,
                ElementsOneDefinitionAcuteTriangle.clean,
                "Acute-Angled Triangle", book1_defs_id)
            book1_defs22_square_id = register_child_animation(
                state_ptr, ElementsOneDefinitionSquare.get_view_text,
                ElementsOneDefinitionSquare.initialize,
                ElementsOneDefinitionSquare.loop,
                ElementsOneDefinitionSquare.clean,
                "Square", book1_defs_id)
            book1_defs22_oblong_id = register_child_animation(
                state_ptr, ElementsOneDefinitionOblong.get_view_text,
                ElementsOneDefinitionOblong.initialize,
                ElementsOneDefinitionOblong.loop,
                ElementsOneDefinitionOblong.clean,
                "Oblong", book1_defs_id)
            book1_defs22_rhombus_id = register_child_animation(
                state_ptr, ElementsOneDefinitionRhombus.get_view_text,
                ElementsOneDefinitionRhombus.initialize,
                ElementsOneDefinitionRhombus.loop,
                ElementsOneDefinitionRhombus.clean,
                "Rhombus", book1_defs_id)
            book1_defs22_rhomboid_id = register_child_animation(
                state_ptr, ElementsOneDefinitionRhomboid.get_view_text,
                ElementsOneDefinitionRhomboid.initialize,
                ElementsOneDefinitionRhomboid.loop,
                ElementsOneDefinitionRhomboid.clean,
                "Rhomboid", book1_defs_id)
            book1_defs22_trapezia_id = register_child_animation(
                state_ptr, ElementsOneDefinitionTrapezia.get_view_text,
                ElementsOneDefinitionTrapezia.initialize,
                ElementsOneDefinitionTrapezia.loop,
                ElementsOneDefinitionTrapezia.clean,
                "Trapezia", book1_defs_id)
            book1_defs23_parallel_id = register_child_animation(
                state_ptr, ElementsOneDefinitionParallel.get_view_text,
                ElementsOneDefinitionParallel.initialize,
                ElementsOneDefinitionParallel.loop,
                ElementsOneDefinitionParallel.clean,
                "Parallel Straight Lines", book1_defs_id)
                
        book1_posts_id = register_child_animation(
            state_ptr, get_view_text_book_1_posts, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "Postulates", book1_id)
            book1_posts1_draw_line_id = register_child_animation(
                state_ptr, ElementsOnePostulatesDrawLine.get_view_text,
                ElementsOnePostulatesDrawLine.initialize,
                ElementsOnePostulatesDrawLine.loop, ElementsOnePostulatesDrawLine.clean,
                "Draw a Line", book1_posts_id)
            book1_posts2_finite_line_id = register_child_animation(
                state_ptr, ElementsOnePostulatesFiniteLine.get_view_text,
                ElementsOnePostulatesFiniteLine.initialize,
                ElementsOnePostulatesFiniteLine.loop,
                ElementsOnePostulatesFiniteLine.clean,
                "Produce a Finite Line", book1_posts_id)
            book1_posts3_draw_circle_id = register_child_animation(
                state_ptr, ElementsOnePostulatesDrawCircle.get_view_text,
                ElementsOnePostulatesDrawCircle.initialize,
                ElementsOnePostulatesDrawCircle.loop,
                ElementsOnePostulatesDrawCircle.clean,
                "Draw a Circle", book1_posts_id)
            book1_posts4_equal_right_angles_id = register_child_animation(
                state_ptr, ElementsOnePostulatesEqualRightAngles.get_view_text,
                ElementsOnePostulatesEqualRightAngles.initialize,
                ElementsOnePostulatesEqualRightAngles.loop,
                ElementsOnePostulatesEqualRightAngles.clean,
                "Equal Right Angles", book1_posts_id)
            book1_posts5_non_parallel_lines_id = register_child_animation(
                state_ptr, ElementsOnePostulatesNonParallelLines.get_view_text,
                ElementsOnePostulatesNonParallelLines.initialize,
                ElementsOnePostulatesNonParallelLines.loop,
                ElementsOnePostulatesNonParallelLines.clean,
                "Non-Parallel Lines", book1_posts_id)
            
        book1_comm_nots_id = register_child_animation(
            state_ptr, ElementsOneCommonNotions.get_view_text,
            ElementsOneCommonNotions.initialize,
            ElementsOneCommonNotions.loop, ElementsOneCommonNotions.clean,
            "Common Notions", book1_id)

        book1_props_id = register_child_animation(
            state_ptr, get_view_text_book_1_props, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "Propositions", book1_id)
            book1_prop01_id = register_child_animation(
                state_ptr, ElementsOneProposition01.get_view_text,
                ElementsOneProposition01.initialize,
                ElementsOneProposition01.loop, ElementsOneProposition01.clean,
                "Proposition I", book1_props_id)
            book1_prop02_id = register_child_animation(
                state_ptr, ElementsOneProposition02.get_view_text,
                ElementsOneProposition02.initialize,
                ElementsOneProposition02.loop, ElementsOneProposition02.clean,
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
