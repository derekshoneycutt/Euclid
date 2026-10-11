module HilbertChapterOneAxiomI1Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom I,1."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom I,1}

\textbf{I, 1.} Two distinct points $A$ \euclidpoint[color=palevioletred1,size=1] and $B$ \euclidpoint[color=khaki3,size=1] always completely determine a straight line $a$ \euclidline[color=steelblue,length=3,thickness=4].\\
We write $AB = a$ or $BA = a$.

Instead of "determine," we may also employ other forms of expression; for example, we may say $A$ \euclidpoint[color=palevioletred1,size=1] "lies upon" $a$ \euclidline[color=steelblue,length=3,thickness=4], $A$ \euclidpoint[color=palevioletred1,size=1] "is a point of" $a$ \euclidline[color=steelblue,length=3,thickness=4], $a$ \euclidline[color=steelblue,length=3,thickness=4] "goes through" $A$ \euclidpoint[color=palevioletred1,size=1] "and through" $B$ \euclidpoint[color=khaki3,size=1], a "joins" $A$ \euclidpoint[color=palevioletred1,size=1] "and" or "with" $B$ \euclidpoint[color=khaki3,size=1], etc. If $A$ \euclidpoint[color=palevioletred1,size=1] lies upon $a$ \euclidline[color=steelblue,length=3,thickness=4] and at the same time upon another straight line $b$ \euclidline[color=grey60,length=3,thickness=2], we make use also of the expression: "The straight lines" $a$ \euclidline[color=steelblue,length=3,thickness=4] "and" $b$ \euclidline[color=grey60,length=3,thickness=2] "have the point $A$ \euclidpoint[color=palevioletred1,size=1] in common," etc."""
end

"""Describe the unique straight line determined by two distinct points."""
function get_search_content()
    return SearchContent(
        "Axiom I,1 states that two distinct points completely determine a straight line.",
        ("two points determine line", "line through two points", "point line incidence"))
end

end
