module ElementsOneDefinitionParallelContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Parallel Straight Lines."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Parallel Straight Lines}

Parallel straight lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=khaki3,length=3,thickness=4] are straight lines which, being in the same plane and being produced indefinitely in both directions, do not meet one another in either direction."""
end

"""Describe parallel straight lines through coplanarity and nonintersection."""
function get_search_content()
    return SearchContent(
        "Parallel straight lines lie in the same plane and, when produced indefinitely " *
        "in both directions, do not meet in either direction.",
        ("coplanar lines never meet", "nonintersecting straight lines", "parallel lines"))
end

end
