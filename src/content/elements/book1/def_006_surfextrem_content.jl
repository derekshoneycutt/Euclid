module ElementsOneDefinitionSurfaceExtremityContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Surface Extremities."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Surface Extremities}

The extremities of a surface are lines \euclidline[color=steelblue,length=3,thickness=4]."""
end

"""Describe lines as the extremities that bound a surface."""
function get_search_content()
    return SearchContent(
        "The extremities of a surface are lines that form its boundary or terminating " *
        "edges.",
        ("surface boundary", "boundary lines", "edges of a surface"))
end

end
