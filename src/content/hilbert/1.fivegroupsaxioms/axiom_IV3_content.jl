module HilbertChapterOneAxiomIV3Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom IV,3."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom IV,3}

\textbf{IV, 3.} Let $AB$ \euclidline[color=steelblue,length=3,thickness=4] and $BC$ \euclidline[color=steelblue,length=3,thickness=4] be two segments
of a straight line $a$ \euclidline[color=steelblue,length=3,thickness=4] which have no points in common aside from the point $B$ \euclidpoint[color=khaki3,size=1],
and, furthermore, let $A'B'$ \euclidline[color=khaki3,length=3,thickness=4] and $B'C'$ \euclidline[color=khaki3,length=3,thickness=4] be two segments of the same
or of another straight line $a'$ \euclidline[color=khaki3,length=3,thickness=4] having, likewise, no point other than $B'$ \euclidpoint[color=steelblue,size=1] in common.
Then, if $AB$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A'B'$ \euclidline[color=khaki3,length=3,thickness=4] and
$BC$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv B'C'$ \euclidline[color=khaki3,length=3,thickness=4],
we have $AC$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A'C'$ \euclidline[color=khaki3,length=3,thickness=4]."""
end

"""Describe addition of adjacent congruent segments."""
function get_search_content()
    return SearchContent(
        "Axiom IV,3 states that pairs of congruent adjacent segments combine to form " *
        "congruent whole segments.",
        ("segment addition", "congruent adjacent segments", "equal segment sums"))
end

end
