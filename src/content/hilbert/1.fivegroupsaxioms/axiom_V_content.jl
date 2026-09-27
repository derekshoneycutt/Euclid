module HilbertChapterOneAxiomVContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom V."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom V}

Let $A_1$ \euclidpoint[color=grey60,size=1] be any point upon a straight line \euclidline[color=khaki3,length=3,thickness=4] between the arbitrarily chosen points
$A$ \euclidpoint[color=steelblue,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1]. Take the points
$A_2$ \euclidpoint[color=grey60,size=1], $A_3$ \euclidpoint[color=grey60,size=1], $A_4$ \euclidpoint[color=grey60,size=1],
... so that $A_1$ \euclidpoint[color=grey60,size=1] lies between $A$ \euclidpoint[color=steelblue,size=1] and
$A_2$ \euclidpoint[color=grey60,size=1], $A_2$ \euclidpoint[color=grey60,size=1] between $A_1$ \euclidpoint[color=grey60,size=1]
and $A_3$ \euclidpoint[color=grey60,size=1], $A_3$ \euclidpoint[color=grey60,size=1] between $A_2$ \euclidpoint[color=grey60,size=1]
and $A_4$ \euclidpoint[color=grey60,size=1], etc. Moreover, let the segments

    $AA_1$ \euclidline[color=khaki3,length=3,thickness=4], $A_1A_2$ \euclidline[color=khaki3,length=3,thickness=4], $A_2A_3$ \euclidline[color=khaki3,length=3,thickness=4], $A_3A_4$ \euclidline[color=khaki3,length=3,thickness=4], ...

be equal to one another. Then, among this series of points, there always exists a certain point
$A_n$ \euclidpoint[color=grey60,size=1] such that $B$ \euclidpoint[color=palevioletred1,size=1] lies between
$A$ \euclidpoint[color=steelblue,size=1] and $A_n$ \euclidpoint[color=grey60,size=1]."""
end

"""Describe Hilbert's Archimedean axiom using repeated equal segments."""
function get_search_content()
    return SearchContent(
        "Axiom V states that repeated equal segments laid along a line eventually pass " *
        "any chosen point, placing it between the start and some later endpoint.",
        ("Archimedean axiom", "repeated equal segments", "eventually pass point"))
end

end
