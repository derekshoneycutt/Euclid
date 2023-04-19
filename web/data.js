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
import ElementsBook1_Def_006_SurfaceExtremities from "../ElementsBook1/Definitions/gifs/006-SurfaceExtremities.gif";
import ElementsBook1_Def_007_PlaneSurface from "../ElementsBook1/Definitions/gifs/007-PlaneSurface.gif";
import ElementsBook1_Def_008_PlaneAngle from "../ElementsBook1/Definitions/gifs/008-PlaneAngle.gif";
import ElementsBook1_Def_009_RecitilinealAngle from "../ElementsBook1/Definitions/gifs/009-RectilinealAngle.gif";

// Added Axioms Images
import ElementsBook1_AddAxiom_001_PointHighlight from "../ElementsBook1/AddedAxioms/gifs/001-PointHighlight.gif";
import ElementsBook1_AddAxiom_001_PointHighlight3D from "../ElementsBook1/AddedAxioms/gifs/001-PointHighlight-3D.gif";
import ElementsBook1_AddAxiom_002_PointMove from "../ElementsBook1/AddedAxioms/gifs/002-PointMove.gif";
import ElementsBook1_AddAxiom_002_PointMove3D from "../ElementsBook1/AddedAxioms/gifs/002-PointMove-3D.gif";
import ElementsBook1_AddAxiom_003_LineHighlight from "../ElementsBook1/AddedAxioms/gifs/003-LineHighlight.gif";
import ElementsBook1_AddAxiom_003_LineHighlight3D from "../ElementsBook1/AddedAxioms/gifs/003-LineHighlight-3D.gif";
import ElementsBook1_AddAxiom_004_LineMove from "../ElementsBook1/AddedAxioms/gifs/004-LineMove.gif";
import ElementsBook1_AddAxiom_004_LineMove3D from "../ElementsBook1/AddedAxioms/gifs/004-LineMove-3D.gif";
import ElementsBook1_AddAxiom_005_LineRotate from "../ElementsBook1/AddedAxioms/gifs/005-LineRotate.gif";
import ElementsBook1_AddAxiom_005_LineRotate3D from "../ElementsBook1/AddedAxioms/gifs/005-LineRotate-3D.gif";
import ElementsBook1_AddAxiom_006_LineReflect from "../ElementsBook1/AddedAxioms/gifs/006-LineReflect.gif";
import ElementsBook1_AddAxiom_006_LineReflect3D from "../ElementsBook1/AddedAxioms/gifs/006-LineReflect-3D.gif";
import ElementsBook1_AddAxiom_007_IntersectingLines from "../ElementsBook1/AddedAxioms/gifs/007-IntersectingLines.gif";
import ElementsBook1_AddAxiom_007_IntersectingLines3D from "../ElementsBook1/AddedAxioms/gifs/007-IntersectingLines-3D.gif";
import ElementsBook1_AddAxiom_008_SurfaceMove from "../ElementsBook1/AddedAxioms/gifs/008-SurfaceMove.gif";
import ElementsBook1_AddAxiom_009_SurfaceRotate from "../ElementsBook1/AddedAxioms/gifs/009-SurfaceRotate.gif";
import ElementsBook1_AddAxiom_010_SurfaceReflect from "../ElementsBook1/AddedAxioms/gifs/010-SurfaceReflect.gif";
import ElementsBook1_AddAxiom_011_AngleHighlight from "../ElementsBook1/AddedAxioms/gifs/011-AngleHighlight.gif";
import ElementsBook1_AddAxiom_012_AngleMove from "../ElementsBook1/AddedAxioms/gifs/012-AngleMove.gif";
import ElementsBook1_AddAxiom_013_AngleRotate from "../ElementsBook1/AddedAxioms/gifs/013-AngleRotate.gif";
import ElementsBook1_AddAxiom_014_AngleReflect from "../ElementsBook1/AddedAxioms/gifs/014-AngleReflect.gif";


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
                },
                {
                    animation2d: ElementsBook1_Def_006_SurfaceExtremities,
                },
                {
                    animation2d: ElementsBook1_Def_007_PlaneSurface
                },
                {
                    animation2d: ElementsBook1_Def_008_PlaneAngle,
                },
                {
                    animation2d: ElementsBook1_Def_009_RecitilinealAngle,
                },
            ]
        },
        added_axioms: {
            children: [
                {
                    animation2d: ElementsBook1_AddAxiom_001_PointHighlight,
                    animation3d: ElementsBook1_AddAxiom_001_PointHighlight3D
                },
                {
                    animation2d: ElementsBook1_AddAxiom_002_PointMove,
                    animation3d: ElementsBook1_AddAxiom_002_PointMove3D
                },
                {
                    animation2d: ElementsBook1_AddAxiom_003_LineHighlight,
                    animation3d: ElementsBook1_AddAxiom_003_LineHighlight3D
                },
                {
                    animation2d: ElementsBook1_AddAxiom_004_LineMove,
                    animation3d: ElementsBook1_AddAxiom_004_LineMove3D
                },
                {
                    animation2d: ElementsBook1_AddAxiom_005_LineRotate,
                    animation3d: ElementsBook1_AddAxiom_005_LineRotate3D
                },
                {
                    animation2d: ElementsBook1_AddAxiom_006_LineReflect,
                    animation3d: ElementsBook1_AddAxiom_006_LineReflect3D
                },
                {
                    animation2d: ElementsBook1_AddAxiom_007_IntersectingLines,
                    animation3d: ElementsBook1_AddAxiom_007_IntersectingLines3D
                },
                {
                    animation2d: ElementsBook1_AddAxiom_008_SurfaceMove,
                },
                {
                    animation2d: ElementsBook1_AddAxiom_009_SurfaceRotate,
                },
                {
                    animation2d: ElementsBook1_AddAxiom_010_SurfaceReflect,
                },
                {
                    animation2d: ElementsBook1_AddAxiom_011_AngleHighlight,
                },
                {
                    animation2d: ElementsBook1_AddAxiom_012_AngleMove,
                },
                {
                    animation2d: ElementsBook1_AddAxiom_013_AngleRotate,
                },
                {
                    animation2d: ElementsBook1_AddAxiom_014_AngleReflect,
                },
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
    };

    if ('children' in subobj) {
        retObj.children = [...(subobj.children.map((child, index) => subOjectToExport(child, bookIndex, merge.children[index])))];
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
        propositions: subOjectToExport(book.propositions, index, merge_gifs[index].propositions),
        added_axioms: subOjectToExport(book.added_axioms, index, merge_gifs[index].added_axioms),
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
