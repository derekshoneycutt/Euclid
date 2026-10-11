module HilbertChapterOneAxiomI5Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom I,5."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom I,5}

\textbf{I, 5.} If two points $A$ \euclidpoint[color=palevioletred1,size=1], $B$ \euclidpoint[color=khaki3,size=1] of a straight line $a$ \euclidline[color=steelblue,length=3,thickness=4] lie in a plane $\alpha$, then every point of $a$ \euclidline[color=steelblue,length=3,thickness=4] lies in $\alpha$.

In this case we say: "The straight line $a$ \euclidline[color=steelblue,length=3,thickness=4] lies in the plane $\alpha$," etc."""
end

"""Describe when an entire straight line lies in a plane."""
function get_search_content()
    return SearchContent(
        "Axiom I,5 states that when two points of a straight line lie in a plane, every " *
        "point of the line lies in that plane.",
        ("line lies in plane", "two line points in plane", "line plane containment"))
end

end
