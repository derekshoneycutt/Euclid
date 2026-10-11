module HilbertChapterOneAxiomI4Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom I,4."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom I,4}

\textbf{I, 4.} Any three points $A$ \euclidpoint[color=palevioletred1,size=1], $B$ \euclidpoint[color=khaki3,size=1], $C$ \euclidpoint[color=steelblue,size=1] of a plane $\alpha$, which do not lie in the same straight line \euclidline[color=steelblue,length=3,thickness=4], completely determine that plane."""
end

"""Describe how three noncollinear plane points determine that plane."""
function get_search_content()
    return SearchContent(
        "Axiom I,4 states that any three noncollinear points of a plane completely " *
        "determine that plane.",
        ("three points of a plane", "same plane", "plane uniqueness"))
end

end
