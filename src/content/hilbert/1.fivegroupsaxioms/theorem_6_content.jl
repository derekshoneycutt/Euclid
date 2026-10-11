module HilbertChapterOneTheorem6Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 6."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 6}

Every simple polygon, whose vertices all lie in a plane $\alpha$, divides the points of this plane,
not belonging to the broken line constituting the sides of the polygon, into two regions, an
interior and an exterior, having the following properties: If $A$ \euclidpoint[color=steelblue,size=1] is a point of the interior region
(interior point) and $B$ \euclidpoint[color=palevioletred1,size=1] a point of the exterior region (exterior point), then any broken line \euclidline[color=steelblue,length=3,thickness=4]
joining $A$ \euclidpoint[color=steelblue,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1] must have at least one point in common with the polygon. If, on the other hand,
$A$ \euclidpoint[color=steelblue,size=1], $A'$ \euclidpoint[color=khaki3,size=1] are two points of the interior and $B$ \euclidpoint[color=palevioletred1,size=1], $B'$ \euclidpoint[color=grey60,size=1] two points of the exterior region, then there
are always broken lines \euclidline[color=khaki3,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] to be found joining $A$ \euclidpoint[color=steelblue,size=1] with $A'$ \euclidpoint[color=khaki3,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1] with $B'$ \euclidpoint[color=grey60,size=1] without having a point
in common with the polygon. There exist straight lines in the plane $\alpha$ which lie entirely
outside of the given polygon, but there are none which lie entirely within it."""
end

"""Describe the interior and exterior regions of a simple polygon."""
function get_search_content()
    return SearchContent(
        "Theorem 6 states that a simple polygon divides its plane into interior and " *
        "exterior regions, and any broken line joining those regions crosses the polygon.",
        ("polygon interior exterior", "simple polygon separates plane", "cross polygon boundary"))
end

end
