module ElementsOneDefinitionBoundaryContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Boundary."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Boundary}

A boundary is that which is an extremity \euclidline[color=steelblue,length=3,thickness=4] of anything."""
end

"""Describe a boundary as the extremity of a geometric object."""
function get_search_content()
    return SearchContent(
        "Euclid defines a boundary as the extremity that marks the limit of a geometric " *
        "object.",
        ("geometric boundary", "extremity", "outer limit"))
end

end
