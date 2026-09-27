module HilbertChapterOneAxiomII4Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom II,4."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom II,4}

\textbf{II, 4.} Any four points $A$ \euclidpoint[color=palevioletred1,size=1],
$B$ \euclidpoint[color=steelblue,size=1], $C$ \euclidpoint[color=khaki3,size=1],
$D$ \euclidpoint[color=palevioletred1,size=1] of a straight line
\euclidline[color=grey60,length=3,thickness=4] can always be so arranged that
$B$ \euclidpoint[color=steelblue,size=1] shall lie between
$A$ \euclidpoint[color=palevioletred1,size=1] and $C$ \euclidpoint[color=khaki3,size=1]
and also between $A$ \euclidpoint[color=palevioletred1,size=1] and
$D$ \euclidpoint[color=palevioletred1,size=1], and, furthermore, that
$C$ \euclidpoint[color=khaki3,size=1] shall lie between
$A$ \euclidpoint[color=palevioletred1,size=1] and
$D$ \euclidpoint[color=palevioletred1,size=1] and also between
$B$ \euclidpoint[color=steelblue,size=1] and $D$ \euclidpoint[color=palevioletred1,size=1]."""
end

"""Describe the consistent arrangement of four collinear points."""
function get_search_content()
    return SearchContent(
        "Axiom II,4 states that four points on a straight line can be arranged in a " *
        "consistent order satisfying their pairwise betweenness relations.",
        ("arrange four points", "four collinear points", "consistent betweenness"))
end

end
