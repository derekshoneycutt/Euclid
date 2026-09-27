module HilbertChapterOneTheorem10Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 10."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 10 (First theorem of congruence for triangles)}

If, for the two triangles $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=steelblue,edge3_color=palevioletred1]
and $A'B'C'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=steelblue,edge3_color=palevioletred1], the congruences

    $AB$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A'B'$ \euclidline[color=steelblue,length=3,thickness=4], $AC$ \euclidline[color=khaki3,length=3,thickness=4] $\equiv A'C'$ \euclidline[color=khaki3,length=3,thickness=4], $\angle A$ \euclidangle[color=lightgreen,radius=2,end=60,filled] $\equiv \angle A'$ \euclidangle[color=lightgreen,radius=2,end=60,filled]

hold, then the two triangles are congruent to each other.

\textbf{Proof}: From \textit{axiom IV, 6}, it follows that the two congruences

    $\angle B$ \euclidangle[color=lightgreen,radius=2,end=60,filled] $\equiv \angle B'$ \euclidangle[color=lightgreen,radius=2,end=60,filled] and $\angle C$ \euclidangle[color=lightgreen,radius=2,end=60,filled] $\equiv \angle C'$ \euclidangle[color=lightgreen,radius=2,end=60,filled]

are fulfilled, and it is, therefore, sufficient to show that the two sides
$BC$ \euclidline[color=palevioletred1,length=3,thickness=4] and $B'C'$ \euclidline[color=palevioletred1,length=3,thickness=4]
are congruent. We will assume the contrary to be true, namely, that
$BC$ \euclidline[color=palevioletred1,length=3,thickness=4] and $B'C'$ \euclidline[color=palevioletred1,length=3,thickness=4]
are not congruent, and show that this leads to a contradiction. We take upon
$B'C'$ \euclidline[color=palevioletred1,length=3,thickness=4] a point $D'$ \euclidpoint[color=plum1,size=0.5] such that
$BC$ \euclidline[color=palevioletred1,length=3,thickness=4] $\equiv B'D'$ \euclidline[color=firebrick,length=3,thickness=4].
The two triangles $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=steelblue,edge3_color=palevioletred1] and
$A'B'D'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=firebrick,edge2_color=steelblue,edge3_color=palevioletred1]
have, then, two sides and the included angle of the one agreeing, respectively, to two sides and the included angle of the other.
It follows from \textit{axiom IV, 6} that the two angles
$\angle BAC$ \euclidangle[color=lightgreen,radius=2,end=60,filled] and $\angle B'A'D'$ \euclidangle[color=firebrick,radius=2,end=60,filled]
are also congruent to each other. Consequently, by aid of \textit{axiom IV, 5}, the two angles
$\angle B'A'C'$ \euclidangle[color=lightgreen,radius=2,end=60,filled] and $\angle B'A'D'$ \euclidangle[color=firebrick,radius=2,end=60,filled] must be congruent.

This, however, is impossible, since, by \textit{axiom IV, 4}, an angle can be laid off in one and only one way on a given side of a given half-ray of a plane. From this contradiction the theorem follows."""
end

"""Describe the first triangle congruence theorem using two sides and an angle."""
function get_search_content()
    return SearchContent(
        "Theorem 10 states that two triangles are congruent when two corresponding sides " *
        "and their included angles are congruent.",
        ("side angle side", "SAS triangle congruence", "first congruence theorem"))
end

end
