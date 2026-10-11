module HilbertChapterOneAxiomII2Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom II,2."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom II,2}

\textbf{II, 2.} If $A$ \euclidpoint[color=palevioletred1,size=1] and $C$ \euclidpoint[color=khaki3,size=1] are two points of a straight line \euclidline[color=grey60,length=3,thickness=4], then there exists at least one point $B$ \euclidpoint[color=steelblue,size=1] lying between $A$ \euclidpoint[color=palevioletred1,size=1] and $C$ \euclidpoint[color=khaki3,size=1] and at least one point $D$ \euclidpoint[color=steelblue,size=1] so situated that $C$ \euclidpoint[color=khaki3,size=1] lies between $A$ \euclidpoint[color=palevioletred1,size=1] and $D$ \euclidpoint[color=steelblue,size=1]."""
end

"""Describe points lying between and beyond two points of a line."""
function get_search_content()
    return SearchContent(
        "Axiom II,2 states that two points of a line have another point between them and " *
        "a further point beyond one endpoint.",
        ("point between two points", "point beyond endpoint", "extend straight line"))
end

end
