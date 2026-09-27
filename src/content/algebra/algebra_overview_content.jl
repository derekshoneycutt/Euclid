module EuclidAlgebraOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Algebra."""
function get_view_content()
    return tex"""\textbf{Algebra}
    
Algebraic structures organize motions and the laws for composing them. Here we use groups to study reflection and rotation symmetries through closure, associativity, identity, inverses, and commutativity."""
end

"""Describe the algebraic structures used to organize geometric motions."""
function get_search_content()
    return SearchContent(
        "Algebra introduces structures and operations that organize geometric motions, " *
        "with groups providing laws for composing reflections and rotations.",
        ("algebraic structures", "group theory", "geometric symmetries"))
end

end
