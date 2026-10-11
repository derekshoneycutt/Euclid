module HilbertChapterOneDefAngleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definition: Angle."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Angle}

Let $\alpha$ be any arbitrary plane and $h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4]
any two distinct half-rays lying in $\alpha$ and emanating from the point $O$ \euclidpoint[color=khaki3,size=1] so as to form a part of two different straight lines.
We call the system formed by these two half-rays $h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4] an \textit{angle} and represent it by the symbol
$\angle(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] or $\angle(k, h)$ \euclidangle[color=khaki3,radius=2,end=60,filled].
From \textit{axioms II, 1–5}, it follows readily that the half-rays $h$ \euclidline[color=steelblue,length=3,thickness=4] and $k$ \euclidline[color=palevioletred1,length=3,thickness=4],
taken together with the point $O$ \euclidpoint[color=khaki3,size=1], divide the remaining points of the plane $\alpha$
into two regions having the following property: If $A$ \euclidpoint[color=plum1,size=0.5] is a point
of one region and $B$ \euclidpoint[color=plum1,size=0.5] a point of the other, then every broken line
joining $A$ \euclidpoint[color=plum1,size=0.5] and $B$ \euclidpoint[color=plum1,size=0.5] either passes
through $O$ \euclidpoint[color=khaki3,size=1] or has a point in common with one of the half-rays
$h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4].
If, however, $A$ \euclidpoint[color=plum1,size=0.5], $B$ \euclidpoint[color=plum1,size=0.5] both lie
within the same region, then it is always possible to join these two points by a broken line which
neither passes through $O$ \euclidpoint[color=khaki3,size=1] nor has a point in common with either of
the half-rays $h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4].
One of these two regions is distinguished from the other in that the segment joining any two points of this region lies
entirely within the region. The region so characterised is called the interior of the
angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled]. To distinguish the other region
from this, we call it the exterior of the angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled].
The half rays $h$ \euclidline[color=steelblue,length=3,thickness=4] and $k$ \euclidline[color=palevioletred1,length=3,thickness=4]
are called the sides of the angle, and the point $O$ \euclidpoint[color=khaki3,size=1] is called the vertex of the angle."""
end

"""Describe an angle, its vertex and sides, and its two plane regions."""
function get_search_content()
    return SearchContent(
        "An angle is formed by two distinct half-rays from one vertex; its sides divide " *
        "the plane into an interior and an exterior region.",
        ("angle vertex sides", "two half-rays", "angle interior exterior"))
end

end
