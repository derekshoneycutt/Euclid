module HilbertChapterOneTheorem17Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 17."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 17}

If $(A, B, C, ...)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=palevioletred1,edge4_color=steelblue] and
$(A', B', C', ...)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=palevioletred1,edge4_color=steelblue] are
congruent plane figures and $P$ \euclidpoint[color=grey60,size=1] is a point in the plane of the first, then it is always possible to find a point
$P'$ \euclidpoint[color=grey60,size=1] in the plane of the second figure so that
$(A, B, C, ..., P)$ \euclidbox[height=2,width=3,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=khaki3,edge4_color=khaki3] and
$(A', B', C', ..., P')$ \euclidbox[height=2,width=3,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=khaki3,edge4_color=khaki3]
shall likewise be congruent figures. If the two figures have at least three points not lying in a straight line, then the selection of
$P'$ \euclidpoint[color=grey60,size=1] can be made in only one way."""
end

"""Describe extension of congruent plane figures by a corresponding point."""
function get_search_content()
    return SearchContent(
        "Theorem 17 extends congruent plane figures by corresponding points, with a " *
        "unique corresponding point when three original points are noncollinear.",
        ("extend congruent plane figures", "unique corresponding point", "three noncollinear anchors"))
end

end
