module ElementsOneDefinitionPlaneAngleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Plane Angle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Plane Angle}

A plane angle \euclidangle[color=khaki3,radius=2,end=60,filled] is the inclination to one another of two lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] in a plane which meet one another and do not lie in a straight line.

And when the lines containing the angle are straight, the angle is called rectilinear."""
end

"""Describe plane and rectilinear angles from Euclid's Definitions 8 and 9."""
function get_search_content()
    return SearchContent(
        "A plane angle is the inclination of two meeting lines that do not lie in one " *
        "straight line; straight containing lines make the angle rectilinear.",
        ("inclination of lines", "rectilinear angle", "two lines meeting"))
end

end
