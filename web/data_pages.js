export var EUCLID_DATA_PAGES = ({
    title: "Euclid",
    head: "And this is Euclid book 1!",
    page: "/Euclid/index.html",
    books: [
        {
            title: "Euclid's Elements, Book 1",
            head: "And this is Euclid book 1!",
            page: "/Euclid/ElementsBook1_index.html",
            definitions: {
                title: "Definitions",
                head: "Something about definitions in Euclid Book 1",
                page: "/Euclid/ElementsBook1_Definitions_index.html",
                children: [
                    {
                        title: "Point",
                        head: "A *point* is that which has no part.",
                        page: "/Euclid/ElementsBook1_Definitions_001-Point.html"
                    },
                    {
                        title: "Line",
                        head: "A *line* is breadthless length.",
                        page: "/Euclid/ElementsBook1_Definitions_002-Line.html"
                    },
                    {
                        title: "Line Extremities",
                        head: "The *extremities* of a line [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) are points [[Def I.1]](/Euclid/ElementsBook1_Definitions_001-Point.html).",
                        page: "/Euclid/ElementsBook1_Definitions_003-LineExtremities.html"
                    },
                    {
                        title: "Straight Line",
                        head: "A *straight line* is a line [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) which lies evenly with the points [[Def I.1]](/Euclid/ElementsBook1_Definitions_001-Point.html) on itself.",
                        page: "/Euclid/ElementsBook1_Definitions_004-StraightLine.html"
                    },
                    {
                        title: "Surface",
                        head: "A *surface* is that which has length and breadth only.",
                        page: "/Euclid/ElementsBook1_Definitions_005-Surface.html"
                    },
                    {
                        title: "Surface Extremities",
                        head: "The *extremities* of a surface [[Def I.5]](/Euclid/ElementsBook1_Definitions_005-Surface.html) are lines [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html).",
                        page: "/Euclid/ElementsBook1_Definitions_006-SurfaceExtremities.html"
                    },
                    {
                        title: "Plane Surface",
                        head: "A *plane surface* is a surface [[Def I.5]](/Euclid/ElementsBook1_Definitions_005-Surface.html) which lies evenly with the straight lines [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) on itself.",
                        page: "/Euclid/ElementsBook1_Definitions_007-PlaneSurface.html"
                    },
                    {
                        title: "Plane Angle",
                        head: "A *plane angle* is the inclination to one another of two lines [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) in a plane [[Def I.7]](/Euclid/ElementsBook1_Definitions_007-PlaneSurface.html) which meet one another and do not lie in a straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html).",
                        page: "/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html"
                    },
                    {
                        title: "Rectilineal Angle",
                        head: "And when the lines [[Def I.2]](/Euclid/ElementsBook1_Definitions_002-Line.html) containing the angle [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) are straight [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html), the angle is called *rectilineal*.",
                        page: "/Euclid/ElementsBook1_Definitions_009-RectilinealAngle.html"
                    },
                    {
                        title: "Right Angle and Perpendiculars",
                        head: "When a straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) set up on a straight line makes the adjacent angles [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) equal to one another, each of the equal angles is *right*, and the adjacent line standing on the other is called a *perpendicular* to that on which it stands.",
                        page: "/Euclid/ElementsBook1_Definitions_010-RightPerpendicular.html"
                    },
                    {
                        title: "Obtuse Angle",
                        head: "An *obtuse angle* is an angle [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) greater than a right angle [[Def I.10]](/Euclid/ElementsBook1_Definitions_019-RightPerpendicular.html).",
                        page: "/Euclid/ElementsBook1_Definitions_011-ObtuseAngle.html"
                    },
                    {
                        title: "Acute Angle",
                        head: "An *acute angle* is an angle [[Def I.8]](/Euclid/ElementsBook1_Definitions_008-PlaneAngle.html) less than a right angle [[Def I.10]](/Euclid/ElementsBook1_Definitions_019-RightPerpendicular.html).",
                        page: "/Euclid/ElementsBook1_Definitions_012-AcuteAngle.html"
                    },
                    {
                        title: "Boundary",
                        head: "A *boundary* is that which is an extremity [[Def I.3]](/Euclid/ElementsBook1_Definitions_003-LineExtremities.html) [[Def I.6]](/Euclid/ElementsBook1_Definitions_006-SurfaceExtremities.html) of anything.",
                        page: "/Euclid/ElementsBook1_Definitions_013-Boundary.html"
                    },
                    {
                        title: "Figure",
                        head: "A *figure* is that which is contained by any boundary or boundaries [[Def I.13]](/Euclid/ElementsBook1_Definitions_013-Boundary.html).",
                        page: "/Euclid/ElementsBook1_Definitions_014-Figure.html"
                    },
                    {
                        title: "Circle",
                        head: "A *circle* is a plane figure [[Def I.14]](/Euclid/ElementsBook1_Definitions_014-Figure.html) contained by one line such that all the straight lines [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.ipynb) falling upon it from one point among those lying within the figure are equal to one another;",
                        page: "/Euclid/ElementsBook1_Definitions_015-Circle.html"
                    },
                    {
                        title: "Center",
                        head: "And the point is called the *center* of the circle.",
                        page: "/Euclid/ElementsBook1_Definitions_016-Center.html"
                    },
                    {
                        title: "Diameter",
                        head: "A *diameter* of the circle [[Def I.15]](/Euclid/ElementsBook1_Definitions_015-Circle.html) is any straight line [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html) drawn through the center [[Def I.16]](/Euclid/ElementsBook1_Definitions_016-Center.html) and terminated in both directions by the circumference of the circle, and such a straight line also bisects the circle.",
                        page: "/Euclid/ElementsBook1_Definitions_017-Diameter.html"
                    },
                    {
                        title: "Semicircle",
                        head: "A *semicircle* is the figure [[Def I.14]](/Euclid/ElementsBook1_Definitions_014-Figure.html) contained by the diameter [[Def I.18]](/Euclid/ElementsBook1_Definitions_017-Diameter.html) and the circumference cut off by it. And the center of the semicircle is the same as that of the circle [[Def I.16]](/Euclid/ElementsBook1_Definitions_016-Center.html).",
                        page: "/Euclid/ElementsBook1_Definitions_018-Semicircle.html"
                    },
                    {
                        title: "Rectilineal Figures",
                        head: "*Rectilineal figures* are those which are contained by straight lines [[Def I.4]](/Euclid/ElementsBook1_Definitions_004-StraightLine.html), *trilateral* figures being those contained by three, *quadrilateral* those contained by four, and *multilateral* those contained by more than four straight lines.",
                        page: "/Euclid/ElementsBook1_Definitions_019-RectilinealFigures.html"
                    },
                ]
            },
            postulates: {
                title: "Postulates",
                head: "Something about postulates in Euclid Book 1",
                page: "/Euclid/ElementsBook1_Postulates_index.html",
                children: []
            },
            common_notions: {
                title: "Common Notions",
                head: "Something about common notions in Euclid Book 1",
                page: "/Euclid/ElementsBook1_CommonNotions_index.html",
                children: []
            },
            propositions: {
                title: "Propositions",
                head: "Something about propositions in Euclid Book 1",
                page: "/Euclid/ElementsBook1_Propositions_index.html",
                children: []
            }
        }
    ]
})