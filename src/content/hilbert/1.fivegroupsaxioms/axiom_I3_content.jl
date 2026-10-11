module HilbertChapterOneAxiomI3Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom I,3."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom I,3}

\textbf{I, 3.} Three points $A$ \euclidpoint[color=palevioletred1,size=1], $B$ \euclidpoint[color=khaki3,size=1], $C$ \euclidpoint[color=steelblue,size=1] not situated in the same straight line \euclidline[color=steelblue,length=3,thickness=4] always completely determine a plane $\alpha$. We write $ABC = \alpha$.

We employ also the expressions: $A$ \euclidpoint[color=palevioletred1,size=1], $B$ \euclidpoint[color=khaki3,size=1], $C$ \euclidpoint[color=steelblue,size=1], "lie in" $\alpha$; $A$ \euclidpoint[color=palevioletred1,size=1], $B$ \euclidpoint[color=khaki3,size=1], $C$ \euclidpoint[color=steelblue,size=1] "are points of" $\alpha$, etc."""
end

"""Describe the plane determined by three noncollinear points."""
function get_search_content()
    return SearchContent(
        "Axiom I,3 states that three points not on one straight line completely determine " *
        "a plane.",
        ("three points determine plane", "noncollinear points", "point plane incidence"))
end

end
