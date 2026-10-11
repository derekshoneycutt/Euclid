module HilbertChapterOneTheorem12Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 12."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 12}

If two angles $\angle ABC$ \euclidangle[color=palevioletred1,radius=2,end=60,filled] and
$\angle A'B'C'$ \euclidangle[color=palevioletred1,radius=2,end=60,filled] are congruent to each other,
their supplementary angles $\angle CBD$ \euclidangle[color=steelblue,radius=2,end=60,filled]
and $\angle C'B'D'$ \euclidangle[color=steelblue,radius=2,end=60,filled] are also congruent.

\textbf{Proof}: Take the points $A'$ \euclidpoint[color=plum1,size=0.5], $C'$ \euclidpoint[color=plum1,size=0.5], $D'$ \euclidpoint[color=plum1,size=0.5] upon the sides passing through $B'$ \euclidpoint[color=plum1,size=0.5] in such a way that

    $A'B'$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv AB$ \euclidline[color=steelblue,length=3,thickness=4], $C'B'$ \euclidline[color=grey60,length=3,thickness=4] $\equiv CB$ \euclidline[color=grey60,length=3,thickness=4], $D'B'$ \euclidline[color=khaki3,length=3,thickness=4] $\equiv DB$ \euclidline[color=khaki3,length=3,thickness=4].

Then, in the two triangles $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=steelblue,edge3_color=grey60]
and $A'B'C'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=steelblue,edge3_color=grey60],
the sides $AB$ \euclidline[color=steelblue,length=3,thickness=4] and $BC$ \euclidline[color=grey60,length=3,thickness=4]
are respectively congruent to $A'B'$ \euclidline[color=steelblue,length=3,thickness=4] and $C'B'$ \euclidline[color=grey60,length=3,thickness=4].
Moreover, since the angles included by these sides are congruent to each other by hypothesis, it follows from \textit{theorem 10} that these triangles are congruent; that is to say, we have the congruences

    $AC$ \euclidline[color=grey60,length=3,thickness=4] $\equiv A'C'$ \euclidline[color=grey60,length=3,thickness=4], $\angle BAC$ \euclidangle[color=palevioletred1,radius=2,end=60,filled] $\equiv \angle B'A'C'$ \euclidangle[color=palevioletred1,radius=2,end=60,filled].

On the other hand, since by \textit{axiom IV}, 3 the segments $AD$ \euclidline[color=khaki3,length=3,thickness=4] and $A'D'$ \euclidline[color=khaki3,length=3,thickness=4]
are congruent to each other, it follows again from \textit{theorem 10} that the triangles
$CAD$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=steelblue,edge3_color=palevioletred1]
and $C'A'D'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=steelblue,edge3_color=palevioletred1] are congruent, and, consequently, we have the congruences:

    $CD$ \euclidline[color=palevioletred1,length=3,thickness=4] $\equiv C'D'$ \euclidline[color=palevioletred1,length=3,thickness=4], $\angle ADC$ \euclidangle[color=lightgreen,radius=2,end=60,filled] $\equiv \angle A'D'C'$ \euclidangle[color=lightgreen,radius=2,end=60,filled].

From these congruences and the consideration of the triangles
$BCD$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=grey60,edge3_color=palevioletred1]
and $B'C'D'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=grey60,edge3_color=palevioletred1],
it follows by virtue of \textit{axiom IV, 6} that the angles
$\angle CBD$ \euclidangle[color=steelblue,radius=2,end=60,filled] and $\angle C'B'D'$ \euclidangle[color=steelblue,radius=2,end=60,filled] are congruent."""
end

"""Describe congruence of supplements to congruent angles."""
function get_search_content()
    return SearchContent(
        "Theorem 12 states that the supplementary angles of two congruent angles are " *
        "themselves congruent.",
        ("congruent supplementary angles", "angle supplements", "supplements preserve congruence"))
end

end
