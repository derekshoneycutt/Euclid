module ElementsOneDefinitionPlaneSurfaceContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Plane Surface."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Plane Surface}

A plane surface is a surface which lies evenly with the straight lines on itself."""
end

"""Describe a plane surface as lying evenly with its straight lines."""
function get_search_content()
    return SearchContent(
        "Euclid defines a plane surface as a surface lying evenly with every straight " *
        "line on itself.",
        ("flat surface", "planar surface", "lies evenly"))
end

end
