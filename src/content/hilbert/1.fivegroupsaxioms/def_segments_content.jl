module HilbertChapterOneDefSegmentsContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definition: Segments."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Segments}

We will call the system of two points $A$ \euclidpoint[color=steelblue,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1], lying upon a straight line \euclidline[color=grey60,length=3,thickness=4], a segment and denote it by $AB$ \euclidline[color=grey60,length=3,thickness=4] or $BA$ \euclidline[color=grey60,length=3,thickness=4]. The points \euclidpoint[color=steelblue,size=1] lying between $A$ \euclidpoint[color=steelblue,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1] are called the points of the segment $AB$ \euclidline[color=grey60,length=3,thickness=4] or the points lying within the segment $AB$ \euclidline[color=grey60,length=3,thickness=4]. All other points \euclidpoint[color=khaki3,size=1] of the straight line are referred to as the points lying outside the segment $AB$ \euclidline[color=grey60,length=3,thickness=4]. The points $A$ \euclidpoint[color=steelblue,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1] are called the extremities of the segment $AB$ \euclidline[color=grey60,length=3,thickness=4]."""
end

"""Describe a segment, its interior points, and its extremities."""
function get_search_content()
    return SearchContent(
        "A segment is a pair of points on a straight line together with the points between " *
        "them; the defining pair are its extremities.",
        ("segment endpoints", "points between endpoints", "inside and outside segment"))
end

end
