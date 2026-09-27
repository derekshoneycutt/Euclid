module ElementsOneDefinitionCircleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Circle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Circle and Center}

A circle \euclidcircle[color=steelblue,size=1,thickness=2] is a plane figure contained by one line such that all the straight lines falling upon it from one point \euclidpoint[color=palevioletred1,size=1] among those lying within the figure equal one another; and the point \euclidpoint[color=palevioletred1,size=1] is called the center of the circle."""
end

"""Describe Euclid's circle and its equidistant center."""
function get_search_content()
    return SearchContent(
        "A circle is a plane figure bounded by one circumference whose straight lines " *
        "from one interior center point are all equal.",
        ("circle and center", "equal radii", "equidistant circumference"))
end

end
