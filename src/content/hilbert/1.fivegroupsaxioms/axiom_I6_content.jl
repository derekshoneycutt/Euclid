module HilbertChapterOneAxiomI6Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom I,6."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom I,6}

\textbf{I, 6.} If two planes $\alpha$, $\beta$ have a point $A$ \euclidpoint[color=steelblue,size=1] in common, then they have at least a second point $B$ \euclidpoint[color=palevioletred1,size=1] in common."""
end

"""Describe the common points of two intersecting planes."""
function get_search_content()
    return SearchContent(
        "Axiom I,6 states that two planes sharing one point have at least a second point " *
        "in common.",
        ("two planes common points", "plane intersection", "second common point"))
end

end
