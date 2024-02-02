/*
    This describes the data that is to be displayed for Euclid's elements.

    The first part loads in the images that will eventually be displayed.
    All the following is the structure describing the views in Euclid
*/

import { EUCLID_DATA_PAGES } from './data_pages';

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


const merge_gifs = [
    {
        definitions: {
            children: [
                {
                    animation2d: ElementsBook1_Def_001_Point,
                    animation3d: ElementsBook1_Def_001_Point3D
                },
                {
                    animation2d: ElementsBook1_Def_002_Line,
                    animation3d: ElementsBook1_Def_002_Line3D
                },
                {
                    animation2d: ElementsBook1_Def_003_LineExtremities,
                    animation3d: ElementsBook1_Def_003_LineExtremities3D
                },
                {
                    animation2d: ElementsBook1_Def_004_StraightLine,
                    animation3d: ElementsBook1_Def_004_StraightLine3D
                },
                {
                    animation2d: ElementsBook1_Def_005_Surface,
                    animation3d: ElementsBook1_Def_005_Surface3D,
                },
                {
                    animation2d: ElementsBook1_Def_006_SurfaceExtremities,
                    animation3d: ElementsBook1_Def_006_SurfaceExtremities3D
                },
                {
                    animation2d: ElementsBook1_Def_007_PlaneSurface,
                    animation3d: ElementsBook1_Def_007_PlaneSurface3D
                },
                {
                    animation2d: ElementsBook1_Def_008_PlaneAngle,
                    animation3d: ElementsBook1_Def_008_PlaneAngle3D
                },
                {
                    animation2d: ElementsBook1_Def_009_RecitilinealAngle,
                    animation3d: ElementsBook1_Def_009_RecitilinealAngle3D
                },
                {
                    children: [
                        {
                            animation2d: ElementsBook1_Def_010a_RightAngle,
                            animation3d: ElementsBook1_Def_010a_RightAngle3D
                        },
                        {
                            animation2d: ElementsBook1_Def_010b_Perpendicular,
                            animation3d: ElementsBook1_Def_010b_Perpendicular3D
                        },
                    ]
                },
                {
                    animation2d: ElementsBook1_Def_011_ObtuseAngle,
                    animation3d: ElementsBook1_Def_011_ObtuseAngle3D
                },
                {
                    animation2d: ElementsBook1_Def_012_AcuteAngle,
                    animation3d: ElementsBook1_Def_012_AcuteAngle3D
                },
                {
                    animation2d: ElementsBook1_Def_013_Boundary,
                    animation3d: ElementsBook1_Def_013_Boundary3D
                },
                {
                    animation2d: ElementsBook1_Def_014_Figure,
                    animation3d: ElementsBook1_Def_014_Figure3D
                },
                {
                    animation2d: ElementsBook1_Def_015_Circle,
                    animation3d: ElementsBook1_Def_015_Circle3D
                },
                {
                    animation2d: ElementsBook1_Def_016_Center,
                    animation3d: ElementsBook1_Def_016_Center3D
                },
                {
                    animation2d: ElementsBook1_Def_017_Diameter,
                    animation3d: ElementsBook1_Def_017_Diameter3D
                },
                {
                    animation2d: ElementsBook1_Def_018_Semicircle,
                    animation3d: ElementsBook1_Def_018_Semicircle3D
                },
                {
                    children: [
                        {
                            animation2d: ElementsBook1_Def_019a_Trilateral,
                            animation3d: ElementsBook1_Def_019a_Trilateral3D
                        },
                        {
                            animation2d: ElementsBook1_Def_019b_Quadrilateral,
                            animation3d: ElementsBook1_Def_019b_Quadrilateral3D
                        },
                        {
                            animation2d: ElementsBook1_Def_019c_Multilateral,
                            animation3d: ElementsBook1_Def_019c_Multilateral3D
                        },
                    ]
                },
                {
                    children: [
                        {
                            animation2d: ElementsBook1_Def_020a_Equilateral,
                            animation3d: ElementsBook1_Def_020a_Equilateral3D
                        },
                        {
                            animation2d: ElementsBook1_Def_020b_Isosceles,
                            animation3d: ElementsBook1_Def_020b_Isosceles3D
                        },
                        {
                            animation2d: ElementsBook1_Def_020c_Scalene,
                            animation3d: ElementsBook1_Def_020c_Scalene3D
                        }
                    ]
                },
                {
                    children: [
                        {
                            animation2d: ElementsBook1_Def_021a_RightTriangles,
                            animation3d: ElementsBook1_Def_021a_RightTriangles3D
                        },
                        {
                            animation2d: ElementsBook1_Def_021b_ObtuseTriangles,
                            animation3d: ElementsBook1_Def_021b_ObtuseTriangles3D
                        },
                        {
                            animation2d: ElementsBook1_Def_021c_AcuteTriangles,
                            animation3d: ElementsBook1_Def_021c_AcuteTriangles3D
                        },
                    ]
                },
                {
                    children: [
                        {
                            animation2d: ElementsBook1_Def_022a_Square,
                            animation3d: ElementsBook1_Def_022a_Square3D
                        },
                        {
                            animation2d: ElementsBook1_Def_022b_Oblong,
                            animation3d: ElementsBook1_Def_022b_Oblong3D
                        },
                        {
                            animation2d: ElementsBook1_Def_022c_Rhombus,
                            animation3d: ElementsBook1_Def_022c_Rhombus3D
                        },
                        {
                            animation2d: ElementsBook1_Def_022d_Rhomboid,
                            animation3d: ElementsBook1_Def_022d_Rhomboid3D
                        },
                        {
                            animation2d: ElementsBook1_Def_022e_Trapezia,
                            animation3d: ElementsBook1_Def_022e_Trapezia3D
                        }
                    ]
                }
            ]
        }
    }
];

function subOjectToExport(subobj, bookIndex, merge) {
    let retObj = {
        title: subobj.title,
        head: subobj.head,
        page: subobj.page,
        animation2d: merge && merge.animation2d ? merge.animation2d : undefined,
        animation3d: merge && merge.animation3d ? merge.animation3d : undefined,
        link_element: null,
        listitem_element: null,
        sublist_element: null,
        splitdef: false
    };

    if ('children' in subobj) {
        retObj.children = [
            ...(subobj.children.map((child, index) =>
                subOjectToExport(child, bookIndex, merge.children[index])))
        ];
        if ('splitdef' in subobj) {
            retObj.splitdef = !!subobj.splitdef;
        }
    }

    return retObj;
}

function bookToExport(book, index) {
    let retObj = {
        title: book.title,
        head: book.head,
        page: book.page,
        link_element: null,
        listitem_element: null,
        sublist_element: null,
        definitions: subOjectToExport(book.definitions, index, merge_gifs[index].definitions),
        postulates: subOjectToExport(book.postulates, index, merge_gifs[index].postulates),
        common_notions: subOjectToExport(book.common_notions, index, merge_gifs[index].common_notions),
        propositions: subOjectToExport(book.propositions, index, merge_gifs[index].propositions)
    };

    return retObj;
}


export var EUCLID_DATA = {
    title: EUCLID_DATA_PAGES.title,
    head: EUCLID_DATA_PAGES.head,
    page: EUCLID_DATA_PAGES.page,
    link_element: null,
    listitem_element: null,
    sublist_element: null,
    books: [...(EUCLID_DATA_PAGES.books.map((book, index) => bookToExport(book, index)))]
}
