module HilbertChapterOneTheorem18Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 18."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 18}

If $(A, B, C, ...)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=palevioletred1,edge4_color=steelblue]
and $(A', B', C', ...)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=palevioletred1,edge4_color=steelblue]
are congruent figures and $P$ \euclidpoint[color=grey60,size=1] represents any arbitrary point, then there can always
be found a point $P'$ \euclidpoint[color=grey60,size=1] so that the two figures
$(A, B, C, ..., P)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=khaki3,edge2_color=khaki3,edge3_color=khaki3,edge4_color=grey60]
and $(A', B', C', ..., P')$ \euclidbox[height=2,width=2,thickness=2,edge1_color=khaki3,edge2_color=khaki3,edge3_color=khaki3,edge4_color=grey60]
shall likewise be congruent. If the figure
$(A, B, C, ..., P)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=khaki3,edge2_color=khaki3,edge3_color=khaki3,edge4_color=grey60]
contains at least four points not lying in the same plane, then the determination of $P'$ \euclidpoint[color=grey60,size=1] can be made in but one way.

This theorem contains an important result; namely, that all the facts concerning space which have reference to congruence, that is to say, to displacements in space, are (by the addition of the axioms of \textit{groups I and II}) exclusively the consequences of the six linear and plane axioms mentioned above. Hence, it is not necessary to assume the axiom of parallels in order to establish these facts."""
end

"""Describe extension of congruent spatial figures by a corresponding point."""
function get_search_content()
    return SearchContent(
        "Theorem 18 extends congruent figures in space by corresponding points, uniquely " *
        "when four points are noncoplanar, without requiring the parallel axiom.",
        ("extend congruent space figures", "four noncoplanar anchors", "congruence without parallels"))
end

end
