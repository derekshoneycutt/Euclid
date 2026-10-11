module HilbertChapterOneAxiomIV1Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom IV,1."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom IV,1}

\textbf{IV, I.} If $A$ \euclidpoint[color=palevioletred1,size=1], $B$ \euclidpoint[color=khaki3,size=1] are two points on a straight line $a$ \euclidline[color=steelblue,length=3,thickness=4], and if $A'$ \euclidpoint[color=palevioletred1,size=1] is a point upon the same or another straight line $a'$ \euclidline[color=khaki3,length=3,thickness=4], then, upon a given side of $A'$ \euclidpoint[color=palevioletred1,size=1] on the straight line $a'$ \euclidline[color=khaki3,length=3,thickness=4], we can always find one and only one point $B'$ \euclidpoint[color=steelblue,size=1] so that the segment $AB$ (or $BA$) \euclidline[color=steelblue,length=3,thickness=4] is congruent to the segment $A'B'$ \euclidline[color=khaki3,length=3,thickness=4]. We indicate this relation by writing

    $AB$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A'B'$ \euclidline[color=khaki3,length=3,thickness=4].

Every segment is congruent to itself; that is, we always have

    $AB \equiv AB$ \euclidline[color=steelblue,length=3,thickness=4].

We can state the above axiom briefly by saying that every segment can be laid off upon a given side of a given point of a given straight line in one and only one way."""
end

"""Describe unique placement of a congruent segment on a chosen side."""
function get_search_content()
    return SearchContent(
        "Axiom IV,1 states that a segment can be laid off congruently in exactly one way " *
        "on a chosen side of a point on a straight line.",
        ("lay off segment", "unique segment transfer", "segment congruent to itself"))
end

end
