module ElementsOneDefinitionMultilateralContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Multilateral Rectilineal Figures."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Rectilineal Figures - Multilateral}

Rectilineal figures are those which are contained by straight lines, ... and multilateral \euclidpentagon[height=2,width=2,color=steelblue,filled] those contained by more than four straight lines."""
end

"""Describe a multilateral rectilineal figure by its many bounding lines."""
function get_search_content()
    return SearchContent(
        "A multilateral rectilineal figure is a plane figure contained by more than four " *
        "straight lines.",
        ("many-sided figure", "more than four sides", "polygon"))
end

end
