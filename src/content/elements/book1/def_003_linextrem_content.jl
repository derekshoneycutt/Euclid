module ElementsOneDefinitionLineExtremitiesContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Line Extremities."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Line Extremities}

The extremities of a line \euclidline[color=steelblue,length=3,thickness=4] are points \euclidpoint[color=palevioletred1,size=1] \euclidpoint[color=palevioletred1,size=1]."""
end

"""Describe points as the extremities that bound a line."""
function get_search_content()
    return SearchContent(
        "The extremities of a line are points: its terminating boundaries or endpoints.",
        ("line endpoints", "terminal points", "ends of a line"))
end

end
