/*
    This describes the data that is to be displayed for Euclid's elements.

    The first part loads in the images that will eventually be displayed.
    All the following is the structure describing the views in Euclid
*/

// Elements Book I

// Definition images
import ElementsBook1_Def_001_Point from "../build/ElementsBook1/Definitions/gifs/001-Point.gif";
import ElementsBook1_Def_001_Point3D from "../build/ElementsBook1/Definitions/gifs/001-Point-3D.gif";
import ElementsBook1_Def_002_Line from "../build/ElementsBook1/Definitions/gifs/002-Line.gif";
import ElementsBook1_Def_002_Line3D from "../build/ElementsBook1/Definitions/gifs/002-Line-3D.gif";
import ElementsBook1_Def_003_LineExtremities from "../build/ElementsBook1/Definitions/gifs/003-LineExtremities.gif";
import ElementsBook1_Def_003_LineExtremities3D from "../build/ElementsBook1/Definitions/gifs/003-LineExtremities-3D.gif";
import ElementsBook1_Def_004_StraightLine from "../build/ElementsBook1/Definitions/gifs/004-StraightLine.gif";
import ElementsBook1_Def_004_StraightLine3D from "../build/ElementsBook1/Definitions/gifs/004-StraightLine-3D.gif";
import ElementsBook1_Def_005_Surface from "../build/ElementsBook1/Definitions/gifs/005-Surface.gif";
import ElementsBook1_Def_006_SurfaceExtremities from "../build/ElementsBook1/Definitions/gifs/006-SurfaceExtremities.gif";
import ElementsBook1_Def_007_PlaneSurface from "../build/ElementsBook1/Definitions/gifs/007-PlaneSurface.gif";
import ElementsBook1_Def_008_PlaneAngle from "../build/ElementsBook1/Definitions/gifs/008-PlaneAngle.gif";
import ElementsBook1_Def_009_RecitilinealAngle from "../build/ElementsBook1/Definitions/gifs/009-RectilinealAngle.gif";

// Added Axioms Images
import ElementsBook1_AddAxiom_001_PointHighlight from "../build/ElementsBook1/AddedAxioms/gifs/001-PointHighlight.gif";
import ElementsBook1_AddAxiom_001_PointHighlight3D from "../build/ElementsBook1/AddedAxioms/gifs/001-PointHighlight-3D.gif";
import ElementsBook1_AddAxiom_002_PointMove from "../build/ElementsBook1/AddedAxioms/gifs/002-PointMove.gif";
import ElementsBook1_AddAxiom_002_PointMove3D from "../build/ElementsBook1/AddedAxioms/gifs/002-PointMove-3D.gif";
import ElementsBook1_AddAxiom_003_LineHighlight from "../build/ElementsBook1/AddedAxioms/gifs/003-LineHighlight.gif";
import ElementsBook1_AddAxiom_003_LineHighlight3D from "../build/ElementsBook1/AddedAxioms/gifs/003-LineHighlight-3D.gif";
import ElementsBook1_AddAxiom_004_LineMove from "../build/ElementsBook1/AddedAxioms/gifs/004-LineMove.gif";
import ElementsBook1_AddAxiom_004_LineMove3D from "../build/ElementsBook1/AddedAxioms/gifs/004-LineMove-3D.gif";
import ElementsBook1_AddAxiom_005_LineRotate from "../build/ElementsBook1/AddedAxioms/gifs/005-LineRotate.gif";
import ElementsBook1_AddAxiom_005_LineRotate3D from "../build/ElementsBook1/AddedAxioms/gifs/005-LineRotate-3D.gif";
import ElementsBook1_AddAxiom_006_LineReflect from "../build/ElementsBook1/AddedAxioms/gifs/006-LineReflect.gif";
import ElementsBook1_AddAxiom_006_LineReflect3D from "../build/ElementsBook1/AddedAxioms/gifs/006-LineReflect-3D.gif";
import ElementsBook1_AddAxiom_007_IntersectingLines from "../build/ElementsBook1/AddedAxioms/gifs/007-IntersectingLines.gif";
import ElementsBook1_AddAxiom_007_IntersectingLines3D from "../build/ElementsBook1/AddedAxioms/gifs/007-IntersectingLines-3D.gif";
import ElementsBook1_AddAxiom_008_SurfaceMove from "../build/ElementsBook1/AddedAxioms/gifs/008-SurfaceMove.gif";
import ElementsBook1_AddAxiom_009_SurfaceRotate from "../build/ElementsBook1/AddedAxioms/gifs/009-SurfaceRotate.gif";
import ElementsBook1_AddAxiom_010_SurfaceReflect from "../build/ElementsBook1/AddedAxioms/gifs/010-SurfaceReflect.gif";
import ElementsBook1_AddAxiom_011_AngleHighlight from "../build/ElementsBook1/AddedAxioms/gifs/011-AngleHighlight.gif";
import ElementsBook1_AddAxiom_012_AngleMove from "../build/ElementsBook1/AddedAxioms/gifs/012-AngleMove.gif";
import ElementsBook1_AddAxiom_013_AngleRotate from "../build/ElementsBook1/AddedAxioms/gifs/013-AngleRotate.gif";
import ElementsBook1_AddAxiom_014_AngleReflect from "../build/ElementsBook1/AddedAxioms/gifs/014-AngleReflect.gif";


export var EUCLID_DATA = {
    title: "Euclid",
    head: "Something something index",
    page: "/Euclid/index.html",
    link_element: null,
    listitem_element: null,
    sublist_element: null,
    books: [
        {
            title: "Euclid's Elements, Book 1",
            head: "And this is Euclid book 1!",
            page: "/Euclid/ElementsBook1_index.html",
            link_element: null,
            listitem_element: null,
            sublist_element: null,
            definitions: {
                title: "Definitions",
                head: "Something about definitions in Euclid Book 1",
                page: "/Euclid/ElementsBook1_Definitions_index.html",
                link_element: null,
                listitem_element: null,
                sublist_element: null,
                children: [
                    {
                        title: "Point",
                        head: "A *point* is that which has no part.",
                        animation2d: ElementsBook1_Def_001_Point,
                        animation3d: ElementsBook1_Def_001_Point3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_Definitions_001-Point.html"
                    },
                    {
                        title: "Line",
                        head: "A *line* is breadthless length.",
                        animation2d: ElementsBook1_Def_002_Line,
                        animation3d: ElementsBook1_Def_002_Line3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_Definitions_002-Line.html"
                    },
                    {
                        title: "Line Extremities",
                        head: "The *extremities* of a line [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) are points [[Def I.1]](/Euclid/ElementsBook1_Definitions_001-Point.html).",
                        animation2d: ElementsBook1_Def_003_LineExtremities,
                        animation3d: ElementsBook1_Def_003_LineExtremities3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_Definitions_003-LineExtremities.html"
                    },
                    {
                        title: "Straight Line",
                        head: "A *straight line* is a line [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) which lies evenly with the points [[Def I.1]](/Euclid/ElementsBook1_Definitions_001-Point.html) on itself.",
                        animation2d: ElementsBook1_Def_004_StraightLine,
                        animation3d: ElementsBook1_Def_004_StraightLine3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_Definitions_004-StraightLine.html"
                    },
                    {
                        title: "Surface",
                        head: "A *surface* is that which has length and breadth only.",
                        animation2d: ElementsBook1_Def_005_Surface,
                        animation3d: "/Euclid/ElementsBook1_Definitions/gifs/005-Surface-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_Definitions_005-Surface.html"
                    },
                    {
                        title: "Surface Extremities",
                        head: "The *extremities* of a surface [[Def I.5]](/Euclid/ElementsBook1_Definitions_005-Surface.html) are lines [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html).",
                        animation2d: ElementsBook1_Def_006_SurfaceExtremities,
                        animation3d: "/Euclid/ElementsBook1_Definitions/gifs/006-SurfaceExtremities-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_Definitions_006-SurfaceExtremities.html"
                    },
                    {
                        title: "Plane Surface",
                        head: "A *plane surface* is a surface [[Def I.5]](/Euclid/ElementsBook1_Definitions_005-Surface.html) which lies evenly with the straight lines [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) on itself.",
                        animation2d: ElementsBook1_Def_007_PlaneSurface,
                        animation3d: "/Euclid/ElementsBook1_Definitions/gifs/007-PlaneSurface-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_Definitions_007-PlaneSurface.html"
                    },
                    {
                        title: "Plane Angle",
                        head: "A *plane angle* is the inclination to one another of two lines [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) in a plane [[Def I.7]](/Euclid/ElementsBook1_Definitions_007-PlaneSurface.html) which meet one another and do not lie in a straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html).",
                        animation2d: ElementsBook1_Def_008_PlaneAngle,
                        animation3d: "/Euclid/ElementsBook1_Definitions/gifs/008-PlaneAngle-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html"
                    },
                    {
                        title: "Rectilineal Angle",
                        head: "And when the lines [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) containing the angle [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) are straight [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html), the angle is called *rectilineal*.",
                        animation2d: ElementsBook1_Def_009_RecitilinealAngle,
                        animation3d: "/Euclid/ElementsBook1_Definitions/gifs/009-RectilinealAngle-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_Definitions_009-RectilinealAngle.html"
                    }
                ]
            },
            postulates: {
                title: "Postulates",
                head: "Something about postulates in Euclid Book 1",
                page: "/Euclid/ElementsBook1_Postulates_index.html",
                link_element: null,
                listitem_element: null,
                sublist_element: null,
                children: []
            },
            common_notions: {
                title: "Common Notions",
                head: "Something about common notions in Euclid Book 1",
                page: "/Euclid/ElementsBook1_CommonNotions_index.html",
                link_element: null,
                listitem_element: null,
                sublist_element: null,
                children: []
            },
            propositions: {
                title: "Propositions",
                head: "Something about propositions in Euclid Book 1",
                page: "/Euclid/ElementsBook1_Propositions_index.html",
                link_element: null,
                listitem_element: null,
                sublist_element: null,
                children: []
            },
            added_axioms: {
                title: "Additional Axioms",
                head: "Something about additional axioms in Euclid Book 1",
                page: "/Euclid/ElementsBook1_AddedAxioms_index.html",
                link_element: null,
                listitem_element: null,
                sublist_element: null,
                children: [
                    {
                        title: "Highlighting Points",
                        head: "A point [[Def I.1]](/Euclid/ElementsBook1_Definitions_001-Point.html) may be *highlighted* in its location in space.",
                        animation2d: ElementsBook1_AddAxiom_001_PointHighlight,
                        animation3d: ElementsBook1_AddAxiom_001_PointHighlight3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_001-HighlightingPoints.html"
                    },
                    {
                        title: "Moving Points",
                        head: "A point [[Def I.1]](/Euclid/ElementsBook1_Definitions_001-Point.html) may be *moved* to any other location in space. A point that is not *moving* is said to be *fixed*.",
                        animation2d: ElementsBook1_AddAxiom_002_PointMove,
                        animation3d: ElementsBook1_AddAxiom_002_PointMove3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_002-MovingPoints.html"
                    },
                    {
                        title: "Highlighting Lines",
                        head: "A line [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) may be *highlighted* in its location in space.",
                        animation2d: ElementsBook1_AddAxiom_003_LineHighlight,
                        animation3d: ElementsBook1_AddAxiom_003_LineHighlight3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_003-HighlightingLines.html"
                    },
                    {
                        title: "Moving Lines",
                        head: "A line [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) may be *moved* by moving its extremities [[Def I.3]](/Euclid/ElementsBook1_Definitions_003-LineExtremities.html) [[AddAxiom I.2]](/Euclid/ElementsBook1_AddedAxioms_002-MovingPoints.html) and ensuring the line remains the same between them. A line that is not *moving* is said to be *fixed*.",
                        animation2d: ElementsBook1_AddAxiom_004_LineMove,
                        animation3d: ElementsBook1_AddAxiom_004_LineMove3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_004-MovingLines.html"
                    },
                    {
                        title: "Rotating Lines",
                        head: "A line [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) may be *rotated* by moving the line [[AddAxiom I.4]](/Euclid/ElementsBook1_AddedAxioms_004-MovingLines.html) such that both extremities are moved an equal radians around a fixed point [[AddAxiom I.2]](/Euclid/ElementsBook1_AddedAxioms_002-MovingPoints.html), which may or may not be an extremity. A line that is not *rotating* is said to have *fixed rotation*. Rotation is said to be *clockwise* or *counter-clockwise* in direction.",
                        animation2d: ElementsBook1_AddAxiom_005_LineRotate,
                        animation3d: ElementsBook1_AddAxiom_005_LineRotate3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_005-RotatingLines.html"
                    },
                    {
                        title: "Reflecting Lines",
                        head: "A line [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) may be *reflected* by moving it [[AddAxiom I.4]](/Euclid/ElementsBook1_AddedAxioms_004-MovingLines.html) such that both extremities [[Def I.3]](/Euclid/ElementsBook1_Definitions_003-LineExtremities.html) are exactly opposite to their beginning position across a straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) called the *axis of reflection*.",
                        animation2d: ElementsBook1_AddAxiom_006_LineReflect,
                        animation3d: ElementsBook1_AddAxiom_006_LineReflect3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_006-ReflectingLines.html"
                    },
                    {
                        title: "Intersecting Lines",
                        head: "When two straight lines [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) overlap, they overlap in exactly one point [[Def I.1]](/Euclid/ElementsBook1_Definitions_001-Point.html), called *intersection*.",
                        animation2d: ElementsBook1_AddAxiom_007_IntersectingLines,
                        animation3d: ElementsBook1_AddAxiom_007_IntersectingLines3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_007-IntersectingLines.html"
                    },
                    {
                        title: "Moving Surfaces",
                        head: "A surface [[Def I.5]](/Euclid/ElementsBook1_Definitions_005-Surface.html) may be *moved* by moving its extremities [[Def I.6]](/Euclid/ElementsBook1_Definitions_006-SurfaceExtremities.html) [[AddAxiom I.4]](/Euclid/ElementsBook1_AddedAxioms_004-MovingLines.html) and ensuring the surface remains the same. A surface that is not *moving* is said to be *fixed*.",
                        animation2d: ElementsBook1_AddAxiom_008_SurfaceMove,
                        animation3d: "/Euclid/ElementsBook1_AddedAxioms/gifs/008-SurfaceMove-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_008-MovingSurfaces.html"
                    },
                    {
                        title: "Rotating Surfaces",
                        head: "A surface [[Def I.5]](/Euclid/ElementsBook1_Definitions_005-Surface.html) may be *rotated* by moving the surface [[AddAxiom I.8]](/Euclid/ElementsBook1_AddedAxioms_008-MovingSurfaces.html) such that all extremities are moved an equal radians around a fixed point [[AddAxiom I.2]](/Euclid/ElementsBook1_AddedAxioms_002-MovingPoints.html), which may or may not be in the surface. A surface that is not *rotating* is said to have *fixed rotation*. Rotation is said to be *clockwise* or *counter-clockwise* in direction.",
                        animation2d: ElementsBook1_AddAxiom_009_SurfaceRotate,
                        animation3d: "/Euclid/ElementsBook1_AddedAxioms/gifs/009-SurfaceRotate-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_009-RotatingSurfaces.html"
                    },
                    {
                        title: "Reflecting Surfaces",
                        head: "A surface [[Def I.5]](/Euclid/ElementsBook1_Definitions_005-Surface.html) may be *reflected* by moving it [[AddAxiom I.8]](/Euclid/ElementsBook1_AddedAxioms_008-MovingSurfaces.html) such that all extremities [[Def I.6]](/Euclid/ElementsBook1_Definitions_006-SurfaceExtremities.html) are exactly opposite to their beginning position across a straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) called the *axis of reflection*.",
                        animation2d: ElementsBook1_AddAxiom_010_SurfaceReflect,
                        animation3d: "/Euclid/ElementsBook1_AddedAxioms/gifs/010-SurfaceReflect-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_010-ReflectingSurfaces.html"
                    },
                    {
                        title: "Highlighting Angles",
                        head: "A plane angle [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) may be *highlighted* in its location in space.",
                        animation2d: ElementsBook1_AddAxiom_011_AngleHighlight,
                        animation3d: "/Euclid/ElementsBook1_AddedAxioms/gifs/011-AngleHighlight-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_011-HighlightingAngles.html"
                    },
                    {
                        title: "Moving Angles",
                        head: "A plane angle [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) may be *moved* by moving its lines [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) [[AddAxiom I.4]](/Euclid/ElementsBook1_AddedAxioms_004-MovingLines.ipynb) and ensuring the angle degree remains the same between them. An angle that is not *moving* is said to be *fixed*.",
                        animation2d: ElementsBook1_AddAxiom_012_AngleMove,
                        animation3d: "/Euclid/ElementsBook1_AddedAxioms/gifs/012-AngleMove-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_012-MovingAngles.html"
                    },
                    {
                        title: "Rotating Angles",
                        head: "A plane angle [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) may be *rotated* by moving its lines [[AddAxiom I.4]](/Euclid/ElementsBook1_AddedAxioms_004-MovingLines.html) such that both are moved an equal radians around a fixed point [[AddAxiom I.2]](/Euclid/ElementsBook1_AddedAxioms_002-MovingPoints.html), which may or may not be a point in the angle. A line that is not *rotating* is said to have *fixed rotation*. Rotation is said to be *clockwise* or *counter-clockwise* in direction.",
                        animation2d: ElementsBook1_AddAxiom_013_AngleRotate,
                        animation3d: "/Euclid/ElementsBook1_AddedAxioms/gifs/013-AngleRotate-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_013-RotatingAngles.html"
                    },
                    {
                        title: "Reflecting Angles",
                        head: "A plane angle [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) may be *reflected* by moving it [[AddAxiom I.12]](/Euclid/ElementsBook1_AddedAxioms_012-MovingAngles.html) such that both lines are exactly opposite to their beginning position across a straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) called the *axis of reflection*.",
                        animation2d: ElementsBook1_AddAxiom_014_AngleReflect,
                        animation3d: "/Euclid/ElementsBook1_AddedAxioms/gifs/014-AngleReflect-3D.gif",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        page: "/Euclid/ElementsBook1_AddedAxioms_014-ReflectingAngles.html"
                    }
                ]
            }
        }
    ]
}
