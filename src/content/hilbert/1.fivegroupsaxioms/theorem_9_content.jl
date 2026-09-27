module HilbertChapterOneTheorem9Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 9."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 9}

If the first of two congruent series of points $A, B, C, D, ..., K, L$ \euclidline[color=steelblue,length=3,thickness=4]
and $A', B', C', D', ..., K', L'$ \euclidline[color=steelblue,length=3,thickness=4] is so arranged that
$B$ \euclidpoint[color=khaki3,size=1] lies between $A$ \euclidpoint[color=palevioletred1,size=1] and $C, D, ..., K, L$, and $C$ \euclidpoint[color=palevioletred1,size=1] between
$A, B$ and $D, ..., K, L$, etc., then the points $A', B', C', D', ..., K', L'$ of the second series are arranged
in a similar way; that is to say, $B'$ \euclidpoint[color=khaki3,size=1]
lies between $A'$ \euclidpoint[color=palevioletred1,size=1] and $C', D', ..., K', L'$,
and $C'$ \euclidpoint[color=palevioletred1,size=1] lies between $A', B'$ and $D', ..., K', L'$, etc."""
end

"""Describe preservation of point order in congruent series."""
function get_search_content()
    return SearchContent(
        "Theorem 9 states that congruent series of points have the same betweenness " *
        "arrangement among their corresponding points.",
        ("congruent point series", "betweenness preserved", "corresponding point order"))
end

end
