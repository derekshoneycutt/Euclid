module HilbertChapterOneTheorem2Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 2."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 2}

Through a straight line \euclidline[color=steelblue,length=3,thickness=4] and a point \euclidpoint[color=palevioletred1,size=1] not lying in it, or through two distinct straight lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] having a common point \euclidpoint[color=grey60,size=1], one and only one plane may be made to pass."""
end

"""Describe the unique plane through a line and point or two intersecting lines."""
function get_search_content()
    return SearchContent(
        "Theorem 2 states that exactly one plane passes through a line and an outside " *
        "point, or through two distinct lines having a common point.",
        ("unique plane", "line and point determine plane", "intersecting lines determine plane"))
end

end
