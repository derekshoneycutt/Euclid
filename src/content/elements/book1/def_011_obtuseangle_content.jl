module ElementsOneDefinitionObtuseAngleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Obtuse Angle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Obtuse Angle}

An obtuse angle \euclidangle[color=khaki3,radius=2,end=120,filled] is an angle greater than a right angle."""
end

"""Describe an obtuse angle by comparison with a right angle."""
function get_search_content()
    return SearchContent(
        "An obtuse angle is greater than a right angle, opening wider than the angle " *
        "formed by perpendicular lines.",
        ("greater than right angle", "wide angle", "more than 90 degrees"))
end

end
