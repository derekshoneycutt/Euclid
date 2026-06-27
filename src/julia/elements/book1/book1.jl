module ElementsOne

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry
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

function get_view_text_BookI(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I"
end

function get_view_text_BookI_defs(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I - Definitions"
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
        "Book I", rootId)
        book1DefsId = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, get_view_text_BookI_defs, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "Definitions", book1Id)
            book1Defs1PointId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionPoint.get_view_text,
                ElementsOneDefinitionPoint.initialize,
                ElementsOneDefinitionPoint.loop, ElementsOneDefinitionPoint.clean,
                "Point", book1DefsId)
            book1Defs2LineId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionLine.get_view_text,
                ElementsOneDefinitionLine.initialize,
                ElementsOneDefinitionLine.loop, ElementsOneDefinitionLine.clean,
                "Line", book1DefsId)
            book1Defs3LineExId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionLineExtremities.get_view_text,
                ElementsOneDefinitionLineExtremities.initialize,
                ElementsOneDefinitionLineExtremities.loop,
                ElementsOneDefinitionLineExtremities.clean,
                "Line Extremities", book1DefsId)
            book1Defs4StraightLineId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionStraightLine.get_view_text,
                ElementsOneDefinitionStraightLine.initialize,
                ElementsOneDefinitionStraightLine.loop,
                ElementsOneDefinitionStraightLine.clean,
                "Straight Line", book1DefsId)
            book1Defs5SurfaceId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionSurface.get_view_text,
                ElementsOneDefinitionSurface.initialize,
                ElementsOneDefinitionSurface.loop,
                ElementsOneDefinitionSurface.clean,
                "Surface", book1DefsId)
            book1Defs6SurfExtremId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionSurfaceExtremity.get_view_text,
                ElementsOneDefinitionSurfaceExtremity.initialize,
                ElementsOneDefinitionSurfaceExtremity.loop,
                ElementsOneDefinitionSurfaceExtremity.clean,
                "Surface Extremities", book1DefsId)
            book1Defs7PlaneSurfaceId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionPlaneSurface.get_view_text,
                ElementsOneDefinitionPlaneSurface.initialize,
                ElementsOneDefinitionPlaneSurface.loop,
                ElementsOneDefinitionPlaneSurface.clean,
                "Plane Surface", book1DefsId)
            book1Defs8PlaneAngleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionPlaneAngle.get_view_text,
                ElementsOneDefinitionPlaneAngle.initialize,
                ElementsOneDefinitionPlaneAngle.loop,
                ElementsOneDefinitionPlaneAngle.clean,
                "Plane Angle", book1DefsId)
            book1Defs10PerpendicularId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionPerpendicular.get_view_text,
                ElementsOneDefinitionPerpendicular.initialize,
                ElementsOneDefinitionPerpendicular.loop,
                ElementsOneDefinitionPerpendicular.clean,
                "Right Angles and Perpendicular", book1DefsId)
            book1Defs11ObtuseAngleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionObtuseAngle.get_view_text,
                ElementsOneDefinitionObtuseAngle.initialize,
                ElementsOneDefinitionObtuseAngle.loop,
                ElementsOneDefinitionObtuseAngle.clean,
                "Obtuse Angle", book1DefsId)
            book1Defs12AcuteAngleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionAcuteAngle.get_view_text,
                ElementsOneDefinitionAcuteAngle.initialize,
                ElementsOneDefinitionAcuteAngle.loop,
                ElementsOneDefinitionAcuteAngle.clean,
                "Acute Angle", book1DefsId)
            book1Defs13BoundaryId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionBoundary.get_view_text,
                ElementsOneDefinitionBoundary.initialize,
                ElementsOneDefinitionBoundary.loop,
                ElementsOneDefinitionBoundary.clean,
                "Boundary", book1DefsId)
            book1Defs14FigureId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionFigure.get_view_text,
                ElementsOneDefinitionFigure.initialize,
                ElementsOneDefinitionFigure.loop,
                ElementsOneDefinitionFigure.clean,
                "Figure", book1DefsId)
            book1Defs15CircleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionCircle.get_view_text,
                ElementsOneDefinitionCircle.initialize,
                ElementsOneDefinitionCircle.loop,
                ElementsOneDefinitionCircle.clean,
                "Circle", book1DefsId)
            book1Defs17DiameterId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionDiameter.get_view_text,
                ElementsOneDefinitionDiameter.initialize,
                ElementsOneDefinitionDiameter.loop,
                ElementsOneDefinitionDiameter.clean,
                "Diameter", book1DefsId)
            book1Defs18SemicircleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionSemicircle.get_view_text,
                ElementsOneDefinitionSemicircle.initialize,
                ElementsOneDefinitionSemicircle.loop,
                ElementsOneDefinitionSemicircle.clean,
                "Semicircle", book1DefsId)
            book1Defs19TrilateralId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionTrilateral.get_view_text,
                ElementsOneDefinitionTrilateral.initialize,
                ElementsOneDefinitionTrilateral.loop,
                ElementsOneDefinitionTrilateral.clean,
                "Trilateral Rectilineal Figures", book1DefsId)
            book1Defs19QuadrilateralId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionQuadrilateral.get_view_text,
                ElementsOneDefinitionQuadrilateral.initialize,
                ElementsOneDefinitionQuadrilateral.loop,
                ElementsOneDefinitionQuadrilateral.clean,
                "Quadrilateral Rectilineal Figures", book1DefsId)
            book1Defs19MultilateralId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionMultilateral.get_view_text,
                ElementsOneDefinitionMultilateral.initialize,
                ElementsOneDefinitionMultilateral.loop,
                ElementsOneDefinitionMultilateral.clean,
                "Multilateral Rectilineal Figures", book1DefsId)
            book1Defs20EquilateralId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionEquilateral.get_view_text,
                ElementsOneDefinitionEquilateral.initialize,
                ElementsOneDefinitionEquilateral.loop,
                ElementsOneDefinitionEquilateral.clean,
                "Equaliteral Triangle", book1DefsId)
            book1Defs20IsoscelesId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionIsosceles.get_view_text,
                ElementsOneDefinitionIsosceles.initialize,
                ElementsOneDefinitionIsosceles.loop,
                ElementsOneDefinitionIsosceles.clean,
                "Isosceles Triangle", book1DefsId)
            book1Defs20ScaleneId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionScalene.get_view_text,
                ElementsOneDefinitionScalene.initialize,
                ElementsOneDefinitionScalene.loop,
                ElementsOneDefinitionScalene.clean,
                "Scalene Triangle", book1DefsId)
            book1Defs21RightTriangleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionRightTriangle.get_view_text,
                ElementsOneDefinitionRightTriangle.initialize,
                ElementsOneDefinitionRightTriangle.loop,
                ElementsOneDefinitionRightTriangle.clean,
                "Right-Angled Triangle", book1DefsId)
            book1Defs21ObtuseTriangleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionObtuseTriangle.get_view_text,
                ElementsOneDefinitionObtuseTriangle.initialize,
                ElementsOneDefinitionObtuseTriangle.loop,
                ElementsOneDefinitionObtuseTriangle.clean,
                "Obtuse-Angled Triangle", book1DefsId)
            book1Defs21AcuteTriangleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionAcuteTriangle.get_view_text,
                ElementsOneDefinitionAcuteTriangle.initialize,
                ElementsOneDefinitionAcuteTriangle.loop,
                ElementsOneDefinitionAcuteTriangle.clean,
                "Acute-Angled Triangle", book1DefsId)
            book1Defs22SquareId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionSquare.get_view_text,
                ElementsOneDefinitionSquare.initialize,
                ElementsOneDefinitionSquare.loop,
                ElementsOneDefinitionSquare.clean,
                "Square", book1DefsId)
            book1Defs22OblongId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionOblong.get_view_text,
                ElementsOneDefinitionOblong.initialize,
                ElementsOneDefinitionOblong.loop,
                ElementsOneDefinitionOblong.clean,
                "Oblong", book1DefsId)
            book1Defs22RhombusId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionRhombus.get_view_text,
                ElementsOneDefinitionRhombus.initialize,
                ElementsOneDefinitionRhombus.loop,
                ElementsOneDefinitionRhombus.clean,
                "Rhombus", book1DefsId)
            book1Defs22RhomboidId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionRhomboid.get_view_text,
                ElementsOneDefinitionRhomboid.initialize,
                ElementsOneDefinitionRhomboid.loop,
                ElementsOneDefinitionRhomboid.clean,
                "Rhomboid", book1DefsId)
            book1Defs22TrapeziaId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionTrapezia.get_view_text,
                ElementsOneDefinitionTrapezia.initialize,
                ElementsOneDefinitionTrapezia.loop,
                ElementsOneDefinitionTrapezia.clean,
                "Trapezia", book1DefsId)
            book1Defs23ParallelId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneDefinitionParallel.get_view_text,
                ElementsOneDefinitionParallel.initialize,
                ElementsOneDefinitionParallel.loop,
                ElementsOneDefinitionParallel.clean,
                "Parallel Straight Lines", book1DefsId)
                
        book1PostsId = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, get_view_text_BookI_posts, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "Postulates", book1Id)
            book1Posts1DrawLineId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOnePostulatesDrawLine.get_view_text,
                ElementsOnePostulatesDrawLine.initialize,
                ElementsOnePostulatesDrawLine.loop, ElementsOnePostulatesDrawLine.clean,
                "Draw a Line", book1PostsId)
            book1Posts2FiniteLineId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOnePostulatesFiniteLine.get_view_text,
                ElementsOnePostulatesFiniteLine.initialize,
                ElementsOnePostulatesFiniteLine.loop, ElementsOnePostulatesFiniteLine.clean,
                "Produce a Finite Line", book1PostsId)
            book1Posts3DrawCircleId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOnePostulatesDrawCircle.get_view_text,
                ElementsOnePostulatesDrawCircle.initialize,
                ElementsOnePostulatesDrawCircle.loop, ElementsOnePostulatesDrawCircle.clean,
                "Draw a Circle", book1PostsId)
            book1Posts4EqualRightAnglesId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOnePostulatesEqualRightAngles.get_view_text,
                ElementsOnePostulatesEqualRightAngles.initialize,
                ElementsOnePostulatesEqualRightAngles.loop, ElementsOnePostulatesEqualRightAngles.clean,
                "Equal Right Angles", book1PostsId)
            book1Posts5NonParallelLinesId = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOnePostulatesNonParallelLines.get_view_text,
                ElementsOnePostulatesNonParallelLines.initialize,
                ElementsOnePostulatesNonParallelLines.loop, ElementsOnePostulatesNonParallelLines.clean,
                "Non-Parallel Lines", book1PostsId)
            
        book1CommNotsId = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, ElementsOneCommonNotions.get_view_text, ElementsOneCommonNotions.initialize,
            ElementsOneCommonNotions.loop, ElementsOneCommonNotions.clean,
            "Common Notions", book1Id)

        book1PropsId = OdinJuliaBridge.add_child_animation_interface(
            state_ptr, get_view_text_BookI_props, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "Propositions", book1Id)
            book1Prop01Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneProposition01.get_view_text,
                ElementsOneProposition01.initialize,
                ElementsOneProposition01.loop, ElementsOneProposition01.clean,
                "Proposition I", book1PropsId)
            book1Prop02Id = OdinJuliaBridge.add_child_animation_interface(
                state_ptr, ElementsOneProposition02.get_view_text,
                ElementsOneProposition02.initialize,
                ElementsOneProposition02.loop, ElementsOneProposition02.clean,
                "Proposition II", book1PropsId)
            book1Prop03Id = 0
            book1Prop04Id = 0
            book1Prop05Id = 0
            book1Prop06Id = 0
            book1Prop07Id = 0
            book1Prop08Id = 0
            book1Prop09Id = 0
            book1Prop10Id = 0
            book1Prop11Id = 0
            book1Prop12Id = 0
            book1Prop13Id = 0
            book1Prop14Id = 0
            book1Prop15Id = 0
            book1Prop16Id = 0
            book1Prop17Id = 0
            book1Prop18Id = 0
            book1Prop19Id = 0
            book1Prop20Id = 0
            book1Prop21Id = 0
            book1Prop22Id = 0
            book1Prop23Id = 0
            book1Prop24Id = 0
            book1Prop25Id = 0
            book1Prop26Id = 0
            book1Prop27Id = 0
            book1Prop28Id = 0
            book1Prop29Id = 0
            book1Prop30Id = 0
            book1Prop31Id = 0
            book1Prop32Id = 0
            book1Prop33Id = 0
            book1Prop34Id = 0
            book1Prop35Id = 0
            book1Prop36Id = 0
            book1Prop37Id = 0
            book1Prop38Id = 0
            book1Prop39Id = 0
            book1Prop40Id = 0
            book1Prop41Id = 0
            book1Prop42Id = 0
            book1Prop43Id = 0
            book1Prop44Id = 0
            book1Prop45Id = 0
            book1Prop46Id = 0
            book1Prop47Id = 0
            book1Prop48Id = 0

end

end
