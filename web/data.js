/*
    This describes the data that is to be displayed for Euclid's elements.

    The first part loads in the images that will eventually be displayed.
    All the following is the structure describing the views in Euclid
*/

import { Imogene as $_, ImogeneArray } from '../Imogene/Imogene';

// Elements Book I

// Definition images
import ElementsBook1_Def_001_Point from "../ElementsBook1/Definitions/gifs/001-Point.gif";
import ElementsBook1_Def_001_Point3D from "../ElementsBook1/Definitions/gifs/001-Point-3D.gif";
import ElementsBook1_Def_002_Line from "../ElementsBook1/Definitions/gifs/002-Line.gif";
import ElementsBook1_Def_002_Line3D from "../ElementsBook1/Definitions/gifs/002-Line-3D.gif";
import ElementsBook1_Def_003_LineExtremities from "../ElementsBook1/Definitions/gifs/003-LineExtremities.gif";
import ElementsBook1_Def_003_LineExtremities3D from "../ElementsBook1/Definitions/gifs/003-LineExtremities-3D.gif";
import ElementsBook1_Def_004_StraightLine from "../ElementsBook1/Definitions/gifs/004-StraightLine.gif";
import ElementsBook1_Def_004_StraightLine3D from "../ElementsBook1/Definitions/gifs/004-StraightLine-3D.gif";
import ElementsBook1_Def_005_Surface from "../ElementsBook1/Definitions/gifs/005-Surface.gif";
import ElementsBook1_Def_005_Surface3D from "../ElementsBook1/Definitions/gifs/005-Surface-3D.gif";
import ElementsBook1_Def_006_SurfaceExtremities from "../ElementsBook1/Definitions/gifs/006-SurfaceExtremities.gif";
import ElementsBook1_Def_006_SurfaceExtremities3D from "../ElementsBook1/Definitions/gifs/006-SurfaceExtremities-3D.gif";
import ElementsBook1_Def_007_PlaneSurface from "../ElementsBook1/Definitions/gifs/007-PlaneSurface.gif";
import ElementsBook1_Def_007_PlaneSurface3D from "../ElementsBook1/Definitions/gifs/007-PlaneSurface-3D.gif";
import ElementsBook1_Def_008_PlaneAngle from "../ElementsBook1/Definitions/gifs/008-PlaneAngle.gif";
import ElementsBook1_Def_008_PlaneAngle3D from "../ElementsBook1/Definitions/gifs/008-PlaneAngle-3D.gif";
import ElementsBook1_Def_009_RecitilinealAngle from "../ElementsBook1/Definitions/gifs/009-RectilinealAngle.gif";
import ElementsBook1_Def_009_RecitilinealAngle3D from "../ElementsBook1/Definitions/gifs/009-RectilinealAngle-3D.gif";
import ElementsBook1_Def_010a_RightAngle from "../ElementsBook1/Definitions/gifs/010a-RightAngle.gif";
import ElementsBook1_Def_010a_RightAngle3D from "../ElementsBook1/Definitions/gifs/010a-RightAngle-3D.gif";
import ElementsBook1_Def_010b_Perpendicular from "../ElementsBook1/Definitions/gifs/010b-Perpendicular.gif";
import ElementsBook1_Def_010b_Perpendicular3D from "../ElementsBook1/Definitions/gifs/010b-Perpendicular-3D.gif";
import ElementsBook1_Def_011_ObtuseAngle from "../ElementsBook1/Definitions/gifs/011-ObtuseAngle.gif";
import ElementsBook1_Def_011_ObtuseAngle3D from "../ElementsBook1/Definitions/gifs/011-ObtuseAngle-3D.gif";
import ElementsBook1_Def_012_AcuteAngle from "../ElementsBook1/Definitions/gifs/012-AcuteAngle.gif";
import ElementsBook1_Def_012_AcuteAngle3D from "../ElementsBook1/Definitions/gifs/012-AcuteAngle-3D.gif";
import ElementsBook1_Def_013_Boundary from "../ElementsBook1/Definitions/gifs/013-Boundary.gif";
import ElementsBook1_Def_013_Boundary3D from "../ElementsBook1/Definitions/gifs/013-Boundary-3D.gif";
import ElementsBook1_Def_014_Figure from "../ElementsBook1/Definitions/gifs/014-Figure.gif";
import ElementsBook1_Def_014_Figure3D from "../ElementsBook1/Definitions/gifs/014-Figure-3D.gif";
import ElementsBook1_Def_015_Circle from "../ElementsBook1/Definitions/gifs/015-Circle.gif";
import ElementsBook1_Def_015_Circle3D from "../ElementsBook1/Definitions/gifs/015-Circle-3D.gif";
import ElementsBook1_Def_016_Center from "../ElementsBook1/Definitions/gifs/016-Center.gif";
import ElementsBook1_Def_016_Center3D from "../ElementsBook1/Definitions/gifs/016-Center-3D.gif";
import ElementsBook1_Def_017_Diameter from "../ElementsBook1/Definitions/gifs/017-Diameter.gif";
import ElementsBook1_Def_017_Diameter3D from "../ElementsBook1/Definitions/gifs/017-Diameter-3D.gif";
import ElementsBook1_Def_018_Semicircle from "../ElementsBook1/Definitions/gifs/018-Semicircle.gif";
import ElementsBook1_Def_018_Semicircle3D from "../ElementsBook1/Definitions/gifs/018-Semicircle-3D.gif";
import ElementsBook1_Def_019a_Trilateral from "../ElementsBook1/Definitions/gifs/019a-Trilateral.gif";
import ElementsBook1_Def_019a_Trilateral3D from "../ElementsBook1/Definitions/gifs/019a-Trilateral-3D.gif";
import ElementsBook1_Def_019b_Quadrilateral from "../ElementsBook1/Definitions/gifs/019b-Quadrilateral.gif";
import ElementsBook1_Def_019b_Quadrilateral3D from "../ElementsBook1/Definitions/gifs/019b-Quadrilateral-3D.gif";
import ElementsBook1_Def_019c_Multilateral from "../ElementsBook1/Definitions/gifs/019c-Multilateral.gif";
import ElementsBook1_Def_019c_Multilateral3D from "../ElementsBook1/Definitions/gifs/019c-Multilateral-3D.gif";
import ElementsBook1_Def_020a_Equilateral from "../ElementsBook1/Definitions/gifs/020a-Equilateral.gif";
import ElementsBook1_Def_020a_Equilateral3D from "../ElementsBook1/Definitions/gifs/020a-Equilateral-3D.gif";
import ElementsBook1_Def_020b_Isosceles from "../ElementsBook1/Definitions/gifs/020b-Isosceles.gif";
import ElementsBook1_Def_020b_Isosceles3D from "../ElementsBook1/Definitions/gifs/020b-Isosceles-3D.gif";
import ElementsBook1_Def_020c_Scalene from "../ElementsBook1/Definitions/gifs/020c-Scalene.gif";
import ElementsBook1_Def_020c_Scalene3D from "../ElementsBook1/Definitions/gifs/020c-Scalene-3D.gif";
import ElementsBook1_Def_021a_RightTriangles from "../ElementsBook1/Definitions/gifs/021a-Right.gif";
import ElementsBook1_Def_021a_RightTriangles3D from "../ElementsBook1/Definitions/gifs/021a-Right-3D.gif";
import ElementsBook1_Def_021b_ObtuseTriangles from "../ElementsBook1/Definitions/gifs/021b-Obtuse.gif";
import ElementsBook1_Def_021b_ObtuseTriangles3D from "../ElementsBook1/Definitions/gifs/021b-Obtuse-3D.gif";
import ElementsBook1_Def_021c_AcuteTriangles from "../ElementsBook1/Definitions/gifs/021c-Acute.gif";
import ElementsBook1_Def_021c_AcuteTriangles3D from "../ElementsBook1/Definitions/gifs/021c-Acute-3D.gif";
import ElementsBook1_Def_022a_Square from "../ElementsBook1/Definitions/gifs/022a-Square.gif";
import ElementsBook1_Def_022a_Square3D from "../ElementsBook1/Definitions/gifs/022a-Square-3D.gif";
import ElementsBook1_Def_022b_Oblong from "../ElementsBook1/Definitions/gifs/022b-Oblong.gif";
import ElementsBook1_Def_022b_Oblong3D from "../ElementsBook1/Definitions/gifs/022b-Oblong-3D.gif";
import ElementsBook1_Def_022c_Rhombus from "../ElementsBook1/Definitions/gifs/022c-Rhombus.gif";
import ElementsBook1_Def_022c_Rhombus3D from "../ElementsBook1/Definitions/gifs/022c-Rhombus-3D.gif";
import ElementsBook1_Def_022d_Rhomboid from "../ElementsBook1/Definitions/gifs/022d-Rhomboid.gif";
import ElementsBook1_Def_022d_Rhomboid3D from "../ElementsBook1/Definitions/gifs/022d-Rhomboid-3D.gif";
import ElementsBook1_Def_022e_Trapezia from "../ElementsBook1/Definitions/gifs/022e-Trapezia.gif";
import ElementsBook1_Def_022e_Trapezia3D from "../ElementsBook1/Definitions/gifs/022e-Trapezia-3D.gif";
import ElementsBook1_Def_023_ParallelLines from "../ElementsBook1/Definitions/gifs/023-ParallelLines.gif";
import ElementsBook1_Def_023_ParallelLines3D from "../ElementsBook1/Definitions/gifs/023-ParallelLines-3D.gif";

/**
 * @typedef {Object} BookNode Node describing a book to display on Euclid
 * @property {string} title Title of the page to display for the node
 * @property {string} head Head data to display for the node
 * @property {string} page The page to display this node on
 * @property {string} animation2d Any 2D animation present for this node
 * @property {string} animation3d Any 3D animation present for this node
 * @property {ImogeneArray} link_element The built link element for this node
 * @property {ImogeneArray} listitem_element The built list item element for this node
 * @property {ImogeneArray} sublist_element The built sub-list item element for this node
 * @property {boolean} splitdef Whether any children present for the node split the current definition
 * @property {BookNode[]} children Any children nodes, if present
 */

/**
 * @typedef {Object} Book A description of a book to display on Euclid
 * @property {string} title Title of the page to display for the book
 * @property {string} head Head data to display for the book
 * @property {string} page The page to display this book on
 * @property {ImogeneArray} link_element The built link element for this book
 * @property {ImogeneArray} listitem_element The built list item element for this book
 * @property {ImogeneArray} sublist_element The built sub-list item element for this book
 * @property {BookNode} definitions Definitions to display for this book
 * @property {BookNode} postulates Postulates to display for this book
 * @property {BookNode} common_notions Common Notions to display for this book
 * @property {BookNode} propositions Propositions to display for this book
 */

/**
 * @typedef {Object} EuclidData Describes everything shown in Euclid
 * @property {string} title Title of the home page
 * @property {string} head Head data to display on home
 * @property {string} page The page to display as the home page
 * @property {ImogeneArray} link_element The built link element for the home page
 * @property {ImogeneArray} listitem_element The built list item element for home
 * @property {ImogeneArray} sublist_element The built sub-list item element for home
 * @property {Book[]} books The books to show in Euclid
 */

/**
 * All of the data to display to users in Euclid
 * @type {EuclidData}
 */
export var EUCLID_DATA = {
    title: "Euclid",
    head: "And this is Euclid book 1!",
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
                splitdef: false,
                children: [
                    {
                        title: "Point",
                        head: "A *point* is that which has no part.",
                        page: "/Euclid/ElementsBook1_Definitions_001-Point.html",
                        animation2d: ElementsBook1_Def_001_Point,
                        animation3d: ElementsBook1_Def_001_Point3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Line",
                        head: "A *line* is breadthless length.",
                        page: "/Euclid/ElementsBook1_Definitions_002-Line.html",
                        animation2d: ElementsBook1_Def_002_Line,
                        animation3d: ElementsBook1_Def_002_Line3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Line Extremities",
                        head: "The *extremities* of a line [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) are points [[Def I.1]](/Euclid/ElementsBook1_Definitions_001-Point.html).",
                        page: "/Euclid/ElementsBook1_Definitions_003-LineExtremities.html",
                        animation2d: ElementsBook1_Def_003_LineExtremities,
                        animation3d: ElementsBook1_Def_003_LineExtremities3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Straight Line",
                        head: "A *straight line* is a line [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) which lies evenly with the points [[Def I.1]](/Euclid/ElementsBook1_Definitions_001-Point.html) on itself.",
                        page: "/Euclid/ElementsBook1_Definitions_004-StraightLine.html",
                        animation2d: ElementsBook1_Def_004_StraightLine,
                        animation3d: ElementsBook1_Def_004_StraightLine3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Surface",
                        head: "A *surface* is that which has length and breadth only.",
                        page: "/Euclid/ElementsBook1_Definitions_005-Surface.html",
                        animation2d: ElementsBook1_Def_005_Surface,
                        animation3d: ElementsBook1_Def_005_Surface3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Surface Extremities",
                        head: "The *extremities* of a surface [[Def I.5]](/Euclid/ElementsBook1_Definitions_005-Surface.html) are lines [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html).",
                        page: "/Euclid/ElementsBook1_Definitions_006-SurfaceExtremities.html",
                        animation2d: ElementsBook1_Def_006_SurfaceExtremities,
                        animation3d: ElementsBook1_Def_006_SurfaceExtremities3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Plane Surface",
                        head: "A *plane surface* is a surface [[Def I.5]](/Euclid/ElementsBook1_Definitions_005-Surface.html) which lies evenly with the straight lines [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) on itself.",
                        page: "/Euclid/ElementsBook1_Definitions_007-PlaneSurface.html",
                        animation2d: ElementsBook1_Def_007_PlaneSurface,
                        animation3d: ElementsBook1_Def_007_PlaneSurface3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Plane Angle",
                        head: "A *plane angle* is the inclination to one another of two lines [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) in a plane [[Def I.7]](/Euclid/ElementsBook1_Definitions_007-PlaneSurface.html) which meet one another and do not lie in a straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html).",
                        page: "/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html",
                        animation2d: ElementsBook1_Def_008_PlaneAngle,
                        animation3d: ElementsBook1_Def_008_PlaneAngle3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Rectilineal Angle",
                        head: "And when the lines [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) containing the angle [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) are straight [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html), the angle is called *rectilineal*.",
                        page: "/Euclid/ElementsBook1_Definitions_009-RectilinealAngle.html",
                        animation2d: ElementsBook1_Def_009_RecitilinealAngle,
                        animation3d: ElementsBook1_Def_009_RecitilinealAngle3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Right Angles",
                        head: "When a straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) set up on a straight line makes the adjacent angles [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) equal to one another, each of the equal angles is *right*, and the adjacent line standing on the other is called a *perpendicular* to that on which it stands.",
                        page: "/Euclid/ElementsBook1_Definitions_010-RightPerpendicular.html",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: true,
                        children: [
                            {
                                title: "Right Angle",
                                head: "When a straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) set up on a straight line makes the adjacent angles [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) equal to one another, each of the equal angles is *right*",
                                page: "/Euclid/ElementsBook1_Definitions_010a-RightAngle.html",
                                animation2d: ElementsBook1_Def_010a_RightAngle,
                                animation3d: ElementsBook1_Def_010a_RightAngle3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                            {
                                title: "Perpendicular",
                                head: "When a straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) set up on a straight line makes the adjacent angles [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) equal to one another... the adjacent line standing on the other is called a *perpendicular* to that on which it stands.",
                                page: "/Euclid/ElementsBook1_Definitions_010b-Perpendicular.html",
                                animation2d: ElementsBook1_Def_010b_Perpendicular,
                                animation3d: ElementsBook1_Def_010b_Perpendicular3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            }
                        ]
                    },
                    {
                        title: "Obtuse Angle",
                        head: "An *obtuse angle* is an angle [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) greater than a right angle [[Def I.10]](/Euclid/ElementsBook1_Definitions_019-RightPerpendicular.html).",
                        page: "/Euclid/ElementsBook1_Definitions_011-ObtuseAngle.html",
                        animation2d: ElementsBook1_Def_011_ObtuseAngle,
                        animation3d: ElementsBook1_Def_011_ObtuseAngle3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Acute Angle",
                        head: "An *acute angle* is an angle [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) less than a right angle [[Def I.10]](/Euclid/ElementsBook1_Definitions_019-RightPerpendicular.html).",
                        page: "/Euclid/ElementsBook1_Definitions_012-AcuteAngle.html",
                        animation2d: ElementsBook1_Def_012_AcuteAngle,
                        animation3d: ElementsBook1_Def_012_AcuteAngle3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Boundary",
                        head: "A *boundary* is that which is an extremity [[Def I.3]](/Euclid/ElementsBook1_Definitions_003-LineExtremities.html) [[Def I.6]](/Euclid/ElementsBook1_Definitions_006-SurfaceExtremities.html) of anything.",
                        page: "/Euclid/ElementsBook1_Definitions_013-Boundary.html",
                        animation2d: ElementsBook1_Def_013_Boundary,
                        animation3d: ElementsBook1_Def_013_Boundary3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Figure",
                        head: "A *figure* is that which is contained by any boundary or boundaries [[Def I.13]](/Euclid/ElementsBook1_Definitions_013-Boundary.html).",
                        page: "/Euclid/ElementsBook1_Definitions_014-Figure.html",
                        animation2d: ElementsBook1_Def_014_Figure,
                        animation3d: ElementsBook1_Def_014_Figure3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Circle",
                        head: "A *circle* is a plane figure [[Def I.14]](/Euclid/ElementsBook1_Definitions_014-Figure.html) contained by one line such that all the straight lines [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.ipynb) falling upon it from one point among those lying within the figure are equal to one another;",
                        page: "/Euclid/ElementsBook1_Definitions_015-Circle.html",
                        animation2d: ElementsBook1_Def_015_Circle,
                        animation3d: ElementsBook1_Def_015_Circle3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Center",
                        head: "And the point is called the *center* of the circle.",
                        page: "/Euclid/ElementsBook1_Definitions_016-Center.html",
                        animation2d: ElementsBook1_Def_016_Center,
                        animation3d: ElementsBook1_Def_016_Center3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Diameter",
                        head: "A *diameter* of the circle [[Def I.15]](/Euclid/ElementsBook1_Definitions_015-Circle.html) is any straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) drawn through the center [[Def I.16]](/Euclid/ElementsBook1_Definitions_016-Center.html) and terminated in both directions by the circumference of the circle, and such a straight line also bisects the circle.",
                        page: "/Euclid/ElementsBook1_Definitions_017-Diameter.html",
                        animation2d: ElementsBook1_Def_017_Diameter,
                        animation3d: ElementsBook1_Def_017_Diameter3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Semicircle",
                        head: "A *semicircle* is the figure [[Def I.14]](/Euclid/ElementsBook1_Definitions_014-Figure.html) contained by the diameter [[Def I.18]](/Euclid/ElementsBook1_Definitions_017-Diameter.html) and the circumference cut off by it. And the center of the semicircle is the same as that of the circle [[Def I.16]](/Euclid/ElementsBook1_Definitions_016-Center.html).",
                        page: "/Euclid/ElementsBook1_Definitions_018-Semicircle.html",
                        animation2d: ElementsBook1_Def_018_Semicircle,
                        animation3d: ElementsBook1_Def_018_Semicircle3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
                    },
                    {
                        title: "Rectilineal Figures",
                        head: "*Rectilineal figures* are those which are contained by straight lines [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html), *trilateral* figures being those contained by three, *quadrilateral* those contained by four, and *multilateral* those contained by more than four straight lines.",
                        page: "/Euclid/ElementsBook1_Definitions_019-RectilinealFigures.html",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: true,
                        children: [
                            {
                                title: "Trilateral",
                                head: "*Rectilineal figures* are those which are contained by straight lines [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html), *trilateral* figures being those contained by three",
                                page: "/Euclid/ElementsBook1_Definitions_019a-Trilateral.html",
                                animation2d: ElementsBook1_Def_019a_Trilateral,
                                animation3d: ElementsBook1_Def_019a_Trilateral3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                            {
                                title: "Quadrilateral",
                                head: "*Rectilineal figures* are those which are contained by straight lines [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html), ... *quadrilateral* those contained by four",
                                page: "/Euclid/ElementsBook1_Definitions_019b-Quadrilateral.html",
                                animation2d: ElementsBook1_Def_019b_Quadrilateral,
                                animation3d: ElementsBook1_Def_019b_Quadrilateral3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                            {
                                title: "Multilateral",
                                head: "*Rectilineal figures* are those which are contained by straight lines [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html), ... and *multilateral* those contained by more than four straight lines.",
                                page: "/Euclid/ElementsBook1_Definitions_019c-Multilateral.html",
                                animation2d: ElementsBook1_Def_019c_Multilateral,
                                animation3d: ElementsBook1_Def_019c_Multilateral3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            }
                        ]
                    },
                    {
                        title: "Triangles by Sides",
                        head: "Of trilateral figures, an *equilateral triangle* is that which has its three sides equal, an *isosceles triangle* that which has two of its sides alone equal, and a *scalene triangle* that which has its three sides unequal.",
                        page: "/Euclid/ElementsBook1_Definitions_020-Triangles.html",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: true,
                        children: [
                            {
                                title: "Equilateral",
                                head: "Of trilateral figures, an *equilateral triangle* is that which has its three sides equal",
                                page: "/Euclid/ElementsBook1_Definitions_020a-Equilateral.html",
                                animation2d: ElementsBook1_Def_020a_Equilateral,
                                animation3d: ElementsBook1_Def_020a_Equilateral3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                            {
                                title: "Isosceles",
                                head: "Of trilateral figures, ... an *isosceles triangle* that which has two of its sides alone equal",
                                page: "/Euclid/ElementsBook1_Definitions_020b-Isosceles.html",
                                animation2d: ElementsBook1_Def_020b_Isosceles,
                                animation3d: ElementsBook1_Def_020b_Isosceles3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                            {
                                title: "Scalene",
                                head: "Of trilateral figures, ... a *scalene triangle* that which has its three sides unequal.",
                                page: "/Euclid/ElementsBook1_Definitions_020c-Scalene.html",
                                animation2d: ElementsBook1_Def_020c_Scalene,
                                animation3d: ElementsBook1_Def_020c_Scalene3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            }
                        ]
                    },
                    {
                        title: "Triangles by Angle",
                        head: "Further, of trilateral figures, a *right-angled triangle* is that which has a right angle, an *obtuse-angled triangle* that which has an obtuse angle, and an *acute-angled triangle* that which has its three angles acute.",
                        page: "/Euclid/ElementsBook1_Definitions_021-AngledTriangles.html",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: true,
                        children: [
                            {
                                title: "Right Triangle",
                                head: "Further, of trilateral figures, a *right-angled triangle* is that which has a right angle",
                                page: "/Euclid/ElementsBook1_Definitions_021a-RightTriangle.html",
                                animation2d: ElementsBook1_Def_021a_RightTriangles,
                                animation3d: ElementsBook1_Def_021a_RightTriangles3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                            {
                                title: "Obtuse Triangle",
                                head: "Further, of trilateral figures, ... an *obtuse-angled triangle* that which has an obtuse angle",
                                page: "/Euclid/ElementsBook1_Definitions_021b-ObtuseTriangle.html",
                                animation2d: ElementsBook1_Def_021b_ObtuseTriangles,
                                animation3d: ElementsBook1_Def_021b_ObtuseTriangles3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                            {
                                title: "Acute Triangle",
                                head: "Further, of trilateral figures, ... and an *acute-angled triangle* that which has its three angles acute.",
                                page: "/Euclid/ElementsBook1_Definitions_021c-AcuteTriangle.html",
                                animation2d: ElementsBook1_Def_021c_AcuteTriangles,
                                animation3d: ElementsBook1_Def_021c_AcuteTriangles3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                        ]
                    },
                    {
                        title: "Quadrilaterals",
                        head: "Of quadrilateral figures, a *square* is that which is both equilateral and right-angled, an *oblong* that which is right-angled but not equilateral, a *rhombus* that which is equilateral but not right-angled, and a *rhomboid* is that which has its opposite angles and sides equal to one another but is neither equilateral nor right-angled. And let quadrilaterals other than these be called *trapezia*.",
                        page: "/Euclid/ElementsBook1_Definitions_022-Quadrilaterals.html",
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: true,
                        children: [
                            {
                                title: "Square",
                                head: "Of quadrilateral figures, a *square* is that which is both equilateral and right-angled",
                                page: "/Euclid/ElementsBook1_Definitions_022a-Square.html",
                                animation2d: ElementsBook1_Def_022a_Square,
                                animation3d: ElementsBook1_Def_022a_Square3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                            {
                                title: "Oblong",
                                head: "Of quadrilateral figures, ... an *oblong* that which is right-angled but not equilateral",
                                page: "/Euclid/ElementsBook1_Definitions_022b-Oblong.html",
                                animation2d: ElementsBook1_Def_022b_Oblong,
                                animation3d: ElementsBook1_Def_022b_Oblong3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                            {
                                title: "Rhombus",
                                head: "Of quadrilateral figures, ... a *rhombus* that which is equilateral but not right-angled",
                                page: "/Euclid/ElementsBook1_Definitions_022c-Rhombus.html",
                                animation2d: ElementsBook1_Def_022c_Rhombus,
                                animation3d: ElementsBook1_Def_022c_Rhombus3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                            {
                                title: "Rhomboid",
                                head: "Of quadrilateral figures, ... a *rhomboid* is that which has its opposite angles and sides equal to one another but is neither equilateral nor right-angled.",
                                page: "/Euclid/ElementsBook1_Definitions_022d-Rhomboid.html",
                                animation2d: ElementsBook1_Def_022d_Rhomboid,
                                animation3d: ElementsBook1_Def_022d_Rhomboid3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            },
                            {
                                title: "Trapezia",
                                head: "And let quadrilaterals other than these be called *trapezia*.",
                                page: "/Euclid/ElementsBook1_Definitions_022e-Trapezia.html",
                                animation2d: ElementsBook1_Def_022e_Trapezia,
                                animation3d: ElementsBook1_Def_022e_Trapezia3D,
                                link_element: null,
                                listitem_element: null,
                                sublist_element: null,
                                splitdef: false,
                            }
                        ]
                    },
                    {
                        title: "Parallel Lines",
                        head: "*Parallel* straight lines are straight lines which, being in the same plane and being produced indefinitely in both directions, do not meet one another in either direction.",
                        page: "/Euclid/ElementsBook1_Definitions_023-ParallelLines.html",
                        animation2d: ElementsBook1_Def_023_ParallelLines,
                        animation3d: ElementsBook1_Def_023_ParallelLines3D,
                        link_element: null,
                        listitem_element: null,
                        sublist_element: null,
                        splitdef: false,
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
                splitdef: false,
                children: []
            },
            common_notions: {
                title: "Common Notions",
                head: "Something about common notions in Euclid Book 1",
                page: "/Euclid/ElementsBook1_CommonNotions_index.html",
                link_element: null,
                listitem_element: null,
                sublist_element: null,
                splitdef: false,
                children: []
            },
            propositions: {
                title: "Propositions",
                head: "Something about propositions in Euclid Book 1",
                page: "/Euclid/ElementsBook1_Propositions_index.html",
                link_element: null,
                listitem_element: null,
                sublist_element: null,
                splitdef: false,
                children: []
            }
        }
    ]
};
