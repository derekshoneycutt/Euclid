module ElementsOneDefinitionDiameterContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Diameter."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Diameter}

A diameter \euclidline[color=steelblue,length=3,thickness=4] of the circle \euclidcircle[color=khaki3,size=1,thickness=2] is any straight line drawn through the center \euclidpoint[color=palevioletred1,size=1] and terminated in both directions by the circumference of the circle, and such a straight line also bisects the circle."""
end

"""Describe a diameter through the center and its bisection of a circle."""
function get_search_content()
    return SearchContent(
        "A diameter is a straight line through the center with both ends on the " *
        "circumference, dividing the circle into two equal parts.",
        ("chord through center", "bisects circle", "two equal halves"))
end

end
