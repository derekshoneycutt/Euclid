module HilbertChapterOneTheorem4Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 4."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 4}

If we have given any finite number of points situated upon a straight line \euclidline[color=grey60,length=3,thickness=4], we can always arrange them in a sequence $A, B, C, D, E, ... , K$ so that $B$ \euclidpoint[color=palevioletred1,size=1] shall lie between $A$ and $C, D, E, ... , K$; $C$ \euclidpoint[color=khaki3,size=1] between $A, B$ and $D, E, ... , K$; $D$ between $A, B, C$ and $E, ... , K$, etc. Aside from this order of sequence, there exists but one other possessing this property, namely, the reverse order $K, ... , E, D, C, B, A$."""
end

"""Describe the two reverse orders of finitely many collinear points."""
function get_search_content()
    return SearchContent(
        "Theorem 4 states that finitely many points on a line can be sequenced according " *
        "to betweenness in exactly two orders, one the reverse of the other.",
        ("order collinear points", "reverse linear sequence", "finite point arrangement"))
end

end
