module ElementsOneDefinitionTrilateralContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Trilateral Rectilineal Figures."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Rectilineal Figures - Trilateral}

Rectilineal figures are those which are contained by straight lines, trilateral figures \euclidtriangle[height=2,width=3,color=steelblue,filled] being those contained by three..."""
end

"""Describe a trilateral rectilineal figure by its three bounding lines."""
function get_search_content()
    return SearchContent(
        "A trilateral rectilineal figure is a plane figure contained by three straight " *
        "lines.",
        ("three-sided figure", "three straight sides", "triangle"))
end

end
