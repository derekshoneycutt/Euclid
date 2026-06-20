include("./euclidbridge.jl")
include("./animations.jl")

include("./nullanimation.jl")

include("./elements/book1/def_001_point.jl")
include("./elements/book1/def_002_line.jl")
include("./elements/book1/def_003_linextrem.jl")
include("./elements/book1/def_004_straightline.jl")
include("./elements/book1/def_005_surface.jl")
include("./elements/book1/def_006_surfextrem.jl")
include("./elements/book1/def_007_planesurface.jl")
include("./elements/book1/def_008_angle.jl")
include("./elements/book1/def_010_perpendicular.jl")
include("./elements/book1/def_011_obtuseangle.jl")
include("./elements/book1/def_012_acuteangle.jl")
include("./elements/book1/def_013_boundary.jl")
include("./elements/book1/def_014_figure.jl")
include("./elements/book1/def_015_circle.jl")
include("./elements/book1/def_017_diameter.jl")
include("./elements/book1/def_018_semicircle.jl")
include("./elements/book1/def_019a_trilateral.jl")
include("./elements/book1/def_019b_quadrilateral.jl")
include("./elements/book1/def_019c_multilateral.jl")
include("./elements/book1/def_020a_equilateral.jl")
include("./elements/book1/def_020b_isosceles.jl")
include("./elements/book1/def_020c_scalene.jl")
include("./elements/book1/def_021a_righttriangle.jl")
include("./elements/book1/def_021b_obtusetriangle.jl")
include("./elements/book1/def_021c_acutetriangle.jl")
include("./elements/book1/def_022a_square.jl")
include("./elements/book1/def_022b_oblong.jl")
include("./elements/book1/def_022c_rhombus.jl")
include("./elements/book1/def_022d_rhomboid.jl")
include("./elements/book1/def_022d_trapezia.jl")

include("./elements/book1/post_01_drawline.jl")
include("./elements/book1/post_02_finiteline.jl")
include("./elements/book1/post_03_drawcircle.jl")


function get_view_text_root(state_ptr::Ptr{Cvoid})
    "Welcome to Euclid's Elements!"
end

function get_view_text_BookI(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I"
end

function get_view_text_BookI_defs(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I - Definitions"
end

function get_view_text_BookI_posts(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I - Postulates"
end

function get_view_text_BookI_common(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I - Common Notions"
end

function get_view_text_BookI_props(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I - Propositions"
end



function init_euclid_scripts(state_ptr::Ptr{Cvoid})
    EuclidBridge.set_null_animations(
        state_ptr, NullAnimation.get_view_text, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean)


    rootId = EuclidBridge.add_root_animation_interface(
        state_ptr, get_view_text_root, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean,
        "Euclid's Elements")
        book1Id = EuclidBridge.add_child_animation_interface(
            state_ptr, get_view_text_BookI, NullAnimation.initialize,
            NullAnimation.loop, NullAnimation.clean,
            "Book I", rootId)
            book1DefsId = EuclidBridge.add_child_animation_interface(
                state_ptr, get_view_text_BookI_defs, NullAnimation.initialize,
                NullAnimation.loop, NullAnimation.clean,
                "Definitions", book1Id)
                book1Defs1PointId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionPoint.get_view_text,
                    ElementsOneDefinitionPoint.initialize,
                    ElementsOneDefinitionPoint.loop, ElementsOneDefinitionPoint.clean,
                    "Point", book1DefsId)
                book1Defs2LineId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionLine.get_view_text,
                    ElementsOneDefinitionLine.initialize,
                    ElementsOneDefinitionLine.loop, ElementsOneDefinitionLine.clean,
                    "Line", book1DefsId)
                book1Defs3LineExId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionLineExtremities.get_view_text,
                    ElementsOneDefinitionLineExtremities.initialize,
                    ElementsOneDefinitionLineExtremities.loop,
                    ElementsOneDefinitionLineExtremities.clean,
                    "Line Extremities", book1DefsId)
                book1Defs4StraightLineId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionStraightLine.get_view_text,
                    ElementsOneDefinitionStraightLine.initialize,
                    ElementsOneDefinitionStraightLine.loop,
                    ElementsOneDefinitionStraightLine.clean,
                    "Straight Line", book1DefsId)
                book1Defs5SurfaceId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionSurface.get_view_text,
                    ElementsOneDefinitionSurface.initialize,
                    ElementsOneDefinitionSurface.loop,
                    ElementsOneDefinitionSurface.clean,
                    "Surface", book1DefsId)
                book1Defs6SurfExtremId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionSurfaceExtremity.get_view_text,
                    ElementsOneDefinitionSurfaceExtremity.initialize,
                    ElementsOneDefinitionSurfaceExtremity.loop,
                    ElementsOneDefinitionSurfaceExtremity.clean,
                    "Surface Extremities", book1DefsId)
                book1Defs7PlaneSurfaceId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionPlaneSurface.get_view_text,
                    ElementsOneDefinitionPlaneSurface.initialize,
                    ElementsOneDefinitionPlaneSurface.loop,
                    ElementsOneDefinitionPlaneSurface.clean,
                    "Plane Surface", book1DefsId)
                book1Defs8PlaneAngleId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionPlaneAngle.get_view_text,
                    ElementsOneDefinitionPlaneAngle.initialize,
                    ElementsOneDefinitionPlaneAngle.loop,
                    ElementsOneDefinitionPlaneAngle.clean,
                    "Plane Angle", book1DefsId)
                book1Defs10PerpendicularId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionPerpendicular.get_view_text,
                    ElementsOneDefinitionPerpendicular.initialize,
                    ElementsOneDefinitionPerpendicular.loop,
                    ElementsOneDefinitionPerpendicular.clean,
                    "Right Angles and Perpendicular", book1DefsId)
                book1Defs11ObtuseAngleId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionObtuseAngle.get_view_text,
                    ElementsOneDefinitionObtuseAngle.initialize,
                    ElementsOneDefinitionObtuseAngle.loop,
                    ElementsOneDefinitionObtuseAngle.clean,
                    "Obtuse Angle", book1DefsId)
                book1Defs12AcuteAngleId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionAcuteAngle.get_view_text,
                    ElementsOneDefinitionAcuteAngle.initialize,
                    ElementsOneDefinitionAcuteAngle.loop,
                    ElementsOneDefinitionAcuteAngle.clean,
                    "Acute Angle", book1DefsId)
                book1Defs13BoundaryId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionBoundary.get_view_text,
                    ElementsOneDefinitionBoundary.initialize,
                    ElementsOneDefinitionBoundary.loop,
                    ElementsOneDefinitionBoundary.clean,
                    "Boundary", book1DefsId)
                book1Defs14FigureId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionFigure.get_view_text,
                    ElementsOneDefinitionFigure.initialize,
                    ElementsOneDefinitionFigure.loop,
                    ElementsOneDefinitionFigure.clean,
                    "Figure", book1DefsId)
                book1Defs15CircleId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionCircle.get_view_text,
                    ElementsOneDefinitionCircle.initialize,
                    ElementsOneDefinitionCircle.loop,
                    ElementsOneDefinitionCircle.clean,
                    "Circle", book1DefsId)
                book1Defs17DiameterId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionDiameter.get_view_text,
                    ElementsOneDefinitionDiameter.initialize,
                    ElementsOneDefinitionDiameter.loop,
                    ElementsOneDefinitionDiameter.clean,
                    "Diameter", book1DefsId)
                book1Defs18SemicircleId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionSemicircle.get_view_text,
                    ElementsOneDefinitionSemicircle.initialize,
                    ElementsOneDefinitionSemicircle.loop,
                    ElementsOneDefinitionSemicircle.clean,
                    "Semicircle", book1DefsId)
                book1Defs19TrilateralId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionTrilateral.get_view_text,
                    ElementsOneDefinitionTrilateral.initialize,
                    ElementsOneDefinitionTrilateral.loop,
                    ElementsOneDefinitionTrilateral.clean,
                    "Trilateral Rectilineal Figures", book1DefsId)
                book1Defs19QuadrilateralId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionQuadrilateral.get_view_text,
                    ElementsOneDefinitionQuadrilateral.initialize,
                    ElementsOneDefinitionQuadrilateral.loop,
                    ElementsOneDefinitionQuadrilateral.clean,
                    "Quadrilateral Rectilineal Figures", book1DefsId)
                book1Defs19MultilateralId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionMultilateral.get_view_text,
                    ElementsOneDefinitionMultilateral.initialize,
                    ElementsOneDefinitionMultilateral.loop,
                    ElementsOneDefinitionMultilateral.clean,
                    "Multilateral Rectilineal Figures", book1DefsId)
                book1Defs20EquilateralId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionEquilateral.get_view_text,
                    ElementsOneDefinitionEquilateral.initialize,
                    ElementsOneDefinitionEquilateral.loop,
                    ElementsOneDefinitionEquilateral.clean,
                    "Equaliteral Triangle", book1DefsId)
                book1Defs20IsoscelesId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionIsosceles.get_view_text,
                    ElementsOneDefinitionIsosceles.initialize,
                    ElementsOneDefinitionIsosceles.loop,
                    ElementsOneDefinitionIsosceles.clean,
                    "Isosceles Triangle", book1DefsId)
                book1Defs20ScaleneId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionScalene.get_view_text,
                    ElementsOneDefinitionScalene.initialize,
                    ElementsOneDefinitionScalene.loop,
                    ElementsOneDefinitionScalene.clean,
                    "Scalene Triangle", book1DefsId)
                book1Defs21RightTriangleId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionRightTriangle.get_view_text,
                    ElementsOneDefinitionRightTriangle.initialize,
                    ElementsOneDefinitionRightTriangle.loop,
                    ElementsOneDefinitionRightTriangle.clean,
                    "Right-Angled Triangle", book1DefsId)
                book1Defs21ObtuseTriangleId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionObtuseTriangle.get_view_text,
                    ElementsOneDefinitionObtuseTriangle.initialize,
                    ElementsOneDefinitionObtuseTriangle.loop,
                    ElementsOneDefinitionObtuseTriangle.clean,
                    "Obtuse-Angled Triangle", book1DefsId)
                book1Defs21AcuteTriangleId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionAcuteTriangle.get_view_text,
                    ElementsOneDefinitionAcuteTriangle.initialize,
                    ElementsOneDefinitionAcuteTriangle.loop,
                    ElementsOneDefinitionAcuteTriangle.clean,
                    "Acute-Angled Triangle", book1DefsId)
                book1Defs22SquareId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionSquare.get_view_text,
                    ElementsOneDefinitionSquare.initialize,
                    ElementsOneDefinitionSquare.loop,
                    ElementsOneDefinitionSquare.clean,
                    "Square", book1DefsId)
                book1Defs22OblongId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionOblong.get_view_text,
                    ElementsOneDefinitionOblong.initialize,
                    ElementsOneDefinitionOblong.loop,
                    ElementsOneDefinitionOblong.clean,
                    "Oblong", book1DefsId)
                book1Defs22RhombusId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionRhombus.get_view_text,
                    ElementsOneDefinitionRhombus.initialize,
                    ElementsOneDefinitionRhombus.loop,
                    ElementsOneDefinitionRhombus.clean,
                    "Rhombus", book1DefsId)
                book1Defs22RhomboidId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionRhomboid.get_view_text,
                    ElementsOneDefinitionRhomboid.initialize,
                    ElementsOneDefinitionRhomboid.loop,
                    ElementsOneDefinitionRhomboid.clean,
                    "Rhomboid", book1DefsId)
                book1Defs22TrapeziaId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOneDefinitionTrapezia.get_view_text,
                    ElementsOneDefinitionTrapezia.initialize,
                    ElementsOneDefinitionTrapezia.loop,
                    ElementsOneDefinitionTrapezia.clean,
                    "Trapezia", book1DefsId)
                    
            book1PostsId = EuclidBridge.add_child_animation_interface(
                state_ptr, get_view_text_BookI_posts, NullAnimation.initialize,
                NullAnimation.loop, NullAnimation.clean,
                "Postulates", book1Id)
                book1Posts1DrawLineId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOnePostulatesDrawLine.get_view_text,
                    ElementsOnePostulatesDrawLine.initialize,
                    ElementsOnePostulatesDrawLine.loop, ElementsOnePostulatesDrawLine.clean,
                    "Draw a Line", book1PostsId)
                book1Posts2FiniteLineId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOnePostulatesFiniteLine.get_view_text,
                    ElementsOnePostulatesFiniteLine.initialize,
                    ElementsOnePostulatesFiniteLine.loop, ElementsOnePostulatesFiniteLine.clean,
                    "Produce a Finite Line", book1PostsId)
                book1Posts3DrawCircleId = EuclidBridge.add_child_animation_interface(
                    state_ptr, ElementsOnePostulatesDrawCircle.get_view_text,
                    ElementsOnePostulatesDrawCircle.initialize,
                    ElementsOnePostulatesDrawCircle.loop, ElementsOnePostulatesDrawCircle.clean,
                    "Draw a Circle", book1PostsId)
                    
            book1CommNotsId = EuclidBridge.add_child_animation_interface(
                state_ptr, get_view_text_BookI_common, NullAnimation.initialize,
                NullAnimation.loop, NullAnimation.clean,
                "Common Notions", book1Id)

            book1PropsId = EuclidBridge.add_child_animation_interface(
                state_ptr, get_view_text_BookI_props, NullAnimation.initialize,
                NullAnimation.loop, NullAnimation.clean,
                "Propositions", book1Id)

end

function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    # Nothing to do here, but is required
end
