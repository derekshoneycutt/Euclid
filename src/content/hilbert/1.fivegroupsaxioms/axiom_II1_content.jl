module HilbertChapterOneAxiomII1Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom II,1."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom II,1}

\textbf{II, 1.} If $A$ \euclidpoint[color=palevioletred1,size=1], $B$ \euclidpoint[color=steelblue,size=1], $C$ \euclidpoint[color=khaki3,size=1] are points of a straight line \euclidline[color=grey60,length=3,thickness=4] and $B$ \euclidpoint[color=steelblue,size=1] lies between $A$ \euclidpoint[color=palevioletred1,size=1] and $C$ \euclidpoint[color=khaki3,size=1], then $B$ \euclidpoint[color=steelblue,size=1] lies also between $C$ \euclidpoint[color=khaki3,size=1] and $A$ \euclidpoint[color=palevioletred1,size=1]."""
end

"""Describe the reversal symmetry of the betweenness relation."""
function get_search_content()
    return SearchContent(
        "Axiom II,1 states that if one point lies between two others, it remains between " *
        "them when their order is reversed.",
        ("symmetric betweenness", "between either direction", "reverse endpoint order"))
end

end
