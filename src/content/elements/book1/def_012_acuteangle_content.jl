module ElementsOneDefinitionAcuteAngleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Acute Angle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Acute Angle}

An acute angle \euclidangle[color=khaki3,radius=2,end=60,filled] is an angle less than a right angle."""
end

"""Describe an acute angle by comparison with a right angle."""
function get_search_content()
    return SearchContent(
        "An acute angle is less than a right angle, opening more narrowly than the angle " *
        "formed by perpendicular lines.",
        ("less than right angle", "narrow angle", "less than 90 degrees"))
end

end
