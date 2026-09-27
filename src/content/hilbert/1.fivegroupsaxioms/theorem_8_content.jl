module HilbertChapterOneTheorem8Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 8."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 8}

If two straight lines $a$ \euclidline[color=steelblue,length=3,thickness=4], $b$ \euclidline[color=palevioletred1,length=3,thickness=4] of a plane do not meet a third straight line $c$ \euclidline[color=khaki3,length=3,thickness=4] of the same plane, then they do not meet each other.

For, if $a$ \euclidline[color=steelblue,length=3,thickness=4], $b$ \euclidline[color=palevioletred1,length=3,thickness=4] had a point $A$ \euclidpoint[color=plum1,size=0.5] in common, there would then exist in the same plane with $c$ \euclidline[color=khaki3,length=3,thickness=4] two straight lines $a$ \euclidline[color=steelblue,length=3,thickness=4] and $b$ \euclidline[color=palevioletred1,length=3,thickness=4] each passing through the point $A$ \euclidpoint[color=plum1,size=0.5] and not meeting the straight line $c$ \euclidline[color=khaki3,length=3,thickness=4]. This condition of affairs is, however, contradictory to the second assertion contained in the axiom of parallels as originally stated. Conversely, the second part of the axiom of parallels, in its original form, follows as a consequence of \textit{theorem 8}."""
end

"""Describe the mutual nonintersection of two lines parallel to a third."""
function get_search_content()
    return SearchContent(
        "Theorem 8 states that two coplanar straight lines that each do not meet a third " *
        "line also do not meet one another.",
        ("lines parallel to same line", "parallel transitivity", "three nonintersecting lines"))
end

end
