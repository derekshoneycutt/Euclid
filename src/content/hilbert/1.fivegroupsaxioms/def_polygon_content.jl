module HilbertChapterOneDefinitionPolygonContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definition: Polygon."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Polygon}

A system of segments $AB, BC, CD, ..., KL$ \euclidline[color=steelblue,length=3,thickness=4] is called a broken line joining
$A$ \euclidpoint[color=khaki3,size=1] with $L$ \euclidpoint[color=palevioletred1,size=1] and is
designated, briefly, as the broken line $ABCDE ... MKL$ \euclidline[color=steelblue,length=3,thickness=4]. The points lying within the
segments $AB, BC, CD, ..., KL$ \euclidline[color=steelblue,length=3,thickness=4], as also
the points $A, B, C, D, ..., K, L$, are called the points of the broken line.
In particular, if the point $A$ \euclidpoint[color=khaki3,size=1] coincides with
$L$ \euclidpoint[color=palevioletred1,size=1], the broken line is called a polygon and is
designated as the polygon $ABCD ... KL$. The segments $AB, BC, CD, ..., KA$ \euclidline[color=steelblue,length=3,thickness=4]
are called the sides of the polygon and the points $A, B, C, D, ..., K$, are the vertices.
Polygons having $3, 4, 5, ..., n$ vertices are called, respectively, triangles, quadrangles,
pentagons, ..., n-gons. If the vertices of a polygon are all distinct and none of them lie
within the segments composing the sides of the polygon, and, furthermore, if no two sides
have a point in common, then the polygon is called a simple polygon."""
end

"""Describe broken lines, polygons, vertices, sides, and simple polygons."""
function get_search_content()
    return SearchContent(
        "A polygon is a closed broken line whose component segments are its sides and " *
        "whose joining points are its vertices; additional conditions define a simple polygon.",
        ("closed broken line", "polygon sides vertices", "triangle quadrangle pentagon n-gon"))
end

end
