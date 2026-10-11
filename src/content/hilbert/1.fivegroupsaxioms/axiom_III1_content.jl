module HilbertChapterOneAxiomIII1Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom III."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom III}

\textbf{III.} In a plane $\alpha$ there can be drawn through any point $A$ \euclidpoint[color=palevioletred1,size=1], lying outside of a straight line $a$ \euclidline[color=steelblue,length=3,thickness=4], one and only one straight line \euclidline[color=khaki3,length=3,thickness=4] which does not intersect the line $a$ \euclidline[color=steelblue,length=3,thickness=4]. This straight line \euclidline[color=khaki3,length=3,thickness=4] is called the parallel to $a$ \euclidline[color=steelblue,length=3,thickness=4] through the given point $A$ \euclidpoint[color=palevioletred1,size=1].

This statement of the axiom of parallels contains two assertions. The first of these is that, in the plane $\alpha$, there is always a straight line \euclidline[color=khaki3,length=3,thickness=4] passing through $A$ \euclidpoint[color=palevioletred1,size=1] which does not intersect the given line $a$ \euclidline[color=steelblue,length=3,thickness=4]. The second states that only one such line is possible. The latter of these statements is the essential one, and it may also be expressed as \textit{Theorem 8}."""
end

"""Describe Hilbert's existence-and-uniqueness axiom for parallels."""
function get_search_content()
    return SearchContent(
        "Axiom III states that through a point outside a line there is exactly one " *
        "coplanar straight line that does not intersect the given line.",
        ("unique parallel through point", "Euclidean parallel axiom", "one nonintersecting line"))
end

end
