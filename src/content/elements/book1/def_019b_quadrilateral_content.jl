module ElementsOneDefinitionQuadrilateralContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Quadrilateral Rectilineal Figures."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Rectilineal Figures - Quadrilateral}

Rectilineal figures are those which are contained by straight lines, ... quadrilateral \euclidbox[height=2,width=2,color=steelblue,filled] those contained by four, ..."""
end

"""Describe a quadrilateral rectilineal figure by its four bounding lines."""
function get_search_content()
    return SearchContent(
        "A quadrilateral rectilineal figure is a plane figure contained by four straight " *
        "lines.",
        ("four-sided figure", "four straight sides", "quadrangle"))
end

end
