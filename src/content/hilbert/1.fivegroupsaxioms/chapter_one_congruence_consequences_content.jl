module HilbertChapterOneCongruenceConsequencesContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for §7 Consequences after Group IV."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§7 Consequences of the Axioms of Congruence}

Suppose the segment $AB$ is congruent to the segment $A'B'$. Since, according to axiom IV, 1, the segment $AB$ is congruent to itself, it follows from axiom IV, 2 that $A'B'$ is congruent to $AB$; that is to say, if $AB \equiv A'B'$, then $A'B' \equiv AB$. We say, then, that the two segments are congruent to one another.

Let $A, B, C, D, ..., K, L$ and $A', B', C', D', ..., K', L'$ be two series of points on the straight lines $a$ and $a'$, respectively, so that all the corresponding segments $AB$ and $A'B'$, $AC$ and $A'C'$, $BC$ and $B'C', ..., KL$ and $K'L'$ are respectively congruent. Then the two series of points are said to be congruent to one another. $A$ and $A'$, $B$ and $B'$, ..., $L$ and $L'$ are called corresponding points of the two congruent series of points.

From the linear axioms IV, 1-3, we can easily deduce several theorems."""
end

"""Describe consequences of congruence for segments and point series."""
function get_search_content()
    return SearchContent(
        "This section derives consequences of the congruence axioms, including symmetry " *
        "of segment congruence and corresponding points in congruent series.",
        ("congruence consequences", "corresponding points", "congruent point series"))
end

end
