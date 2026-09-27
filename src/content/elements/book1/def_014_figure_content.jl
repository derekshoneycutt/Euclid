module ElementsOneDefinitionFigureContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Figure."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Figure}

A figure \euclidtriangle[color=steelblue,height=2,width=3,filled] is that which is contained by any boundary or boundaries \euclidline[color=steelblue,length=3,thickness=4]."""
end

"""Describe a figure through containment by one or more boundaries."""
function get_search_content()
    return SearchContent(
        "Euclid defines a figure as that which is contained by one boundary or by several " *
        "boundaries.",
        ("bounded figure", "geometric shape", "contained by boundaries"))
end

end
