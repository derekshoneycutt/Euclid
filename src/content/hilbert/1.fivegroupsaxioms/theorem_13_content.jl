module HilbertChapterOneTheorem13Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

const TheoremView = tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 13}

Let the angle $\angle(h, k)$ \euclidangle[color=lightgreen,radius=2,end=60,filled] of the plane $\alpha$ be congruent
to the angle $\angle(h', k')$ \euclidangle[color=lightgreen,radius=2,end=60,filled] of the plane $\alpha'$,
and, furthermore, let $l$ \euclidline[color=grey60,length=3,thickness=4] be a half-ray in the plane $\alpha$ emanating
from the vertex of the angle $\angle(h, k)$ \euclidangle[color=lightgreen,radius=2,end=60,filled]
and lying within this angle. Then there always exists in the plane $\alpha'$ a half-ray
$l'$ \euclidline[color=grey60,length=3,thickness=4] emanating from the
vertex of the angle $\angle(h', k')$ \euclidangle[color=lightgreen,radius=2,end=60,filled] and lying within this angle so that we have

    $\angle(h, l) \equiv \angle(h', l')$ \euclidangle[color=lightgreen,radius=2,end=60,filled],   $\angle(k, l) \equiv \angle(k', l')$ \euclidangle[color=lightgreen,radius=2,end=60,filled].

\textbf{Proof}: We will represent the vertices of the angles
$\angle(h, k)$ \euclidangle[color=lightgreen,radius=2,end=60,filled] and
$\angle(h', k')$ \euclidangle[color=lightgreen,radius=2,end=60,filled] by
$O$ \euclidpoint[color=plum1,size=0.5] and $O'$ \euclidpoint[color=plum1,size=0.5],
respectively, and so select upon the sides
$h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4],
$h'$ \euclidline[color=steelblue,length=3,thickness=4], $k'$ \euclidline[color=palevioletred1,length=3,thickness=4]
the points $A$ \euclidpoint[color=grey60,size=1], $B$ \euclidpoint[color=grey60,size=1],
$A'$ \euclidpoint[color=grey60,size=1], $B'$ \euclidpoint[color=grey60,size=1] so that the congruences

    $OA$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv O'A'$ \euclidline[color=steelblue,length=3,thickness=4],   $OB$ \euclidline[color=palevioletred1,length=3,thickness=4] $\equiv O'B'$ \euclidline[color=palevioletred1,length=3,thickness=4]

are fulfilled. Because of the congruence of the triangles
$OAB$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3]
and $O'A'B'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3], we have at once

    $AB$ \euclidline[color=khaki3,length=3,thickness=4] $\equiv A'B'$ \euclidline[color=khaki3,length=3,thickness=4],   $\angle OAB \equiv \angle O'A'B'$ \euclidangle[color=lightgreen,radius=2,end=60,filled],   $\angle OBA \equiv \angle O'B'A'$ \euclidangle[color=lightgreen,radius=2,end=60,filled].

Let the straight line $AB$ \euclidline[color=khaki3,length=3,thickness=4] intersect
$l$ \euclidline[color=grey60,length=3,thickness=4] in $C$ \euclidpoint[color=steelblue,size=1]. Take the point
$C'$ \euclidpoint[color=steelblue,size=1] upon the segment
$A'B'$ \euclidline[color=khaki3,length=3,thickness=4] so that
$A'C'$ \euclidline[color=khaki3,length=3,thickness=4] $\equiv AC$ \euclidline[color=khaki3,length=3,thickness=4].
Then $O'C'$ \euclidline[color=grey60,length=3,thickness=4] is the required half-ray. In fact, it follows directly from these congruences, by aid of
\textit{axiom IV, 3}, that $BC$ \euclidline[color=khaki3,length=3,thickness=4] $\equiv B'C'$ \euclidline[color=khaki3,length=3,thickness=4].
Furthermore, the triangles $OAC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=grey60,edge2_color=steelblue,edge3_color=khaki3] and
$O'A'C'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=grey60,edge2_color=steelblue,edge3_color=khaki3] are congruent to each other,
and the same is true also of the triangles
$OCB$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=grey60,edge3_color=khaki3] and
$O'B'C'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=grey60,edge3_color=khaki3].
With this our proposition is demonstrated."""

"""Return canonical explanatory content for Theorem 13."""
function get_view_content()
    return TheoremView
end

"""Describe transfer of an interior half-ray between congruent angles."""
function get_search_content()
    return SearchContent(
        "Theorem 13 transfers a half-ray inside one angle to a half-ray inside a congruent " *
        "angle so that both corresponding subangles are congruent.",
        ("interior half-ray transfer", "congruent angle subdivision", "matching subangles"))
end

end
