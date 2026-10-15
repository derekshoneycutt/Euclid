module EuclidAlgebraOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Algebra."""
function get_view_content()
    return tex"""\textbf{Algebra}
    
Algebra, and algebraic geometry, offers a great view into the world of motions, reflecitons, rotations, and constructions.

We begin with Group Theory expressing the motions of geometric objects."""
end

"""Describe the algebraic structures used to organize geometric motions."""
function get_search_content()
    return SearchContent(
        """Algebra
Algebra, and algebraic geometry, offers a great view into the world of motions, reflecitons, rotations, and constructions.
We begin with Group Theory expressing the motions of geometric objects""",
        ("algebraic structures", "group theory", "geometric symmetries"))
end

end
