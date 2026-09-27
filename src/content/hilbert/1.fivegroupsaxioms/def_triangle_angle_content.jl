module HilbertChapterOneDefTriangleAngleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definition: Triangle Angle."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Triangle Angle}

Suppose we have given a triangle $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3].
Denote by $h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4]
the two half-rays emanating from $A$ \euclidpoint[color=plum1,size=0.5] and passing respectively through
$B$ \euclidpoint[color=plum1,size=0.5] and $C$ \euclidpoint[color=plum1,size=0.5].
The angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] is then said to be the angle included
by the sides $AB$ \euclidline[color=steelblue,length=3,thickness=4] and $AC$ \euclidline[color=palevioletred1,length=3,thickness=4],
or the one opposite to the side $BC$ \euclidline[color=khaki3,length=3,thickness=4] in the
triangle $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3].
It contains all of the interior points of the triangle
$ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3]
and is represented by the symbol $\angle BAC$ \euclidangle[color=khaki3,radius=2,end=60,filled], or by $\angle A$ \euclidangle[color=khaki3,radius=2,end=60,filled]."""
end

"""Describe the included angle at a vertex of a triangle."""
function get_search_content()
    return SearchContent(
        "A triangle angle is formed by the half-rays along two sides from a vertex, is " *
        "opposite the third side, and contains the triangle's interior points.",
        ("included triangle angle", "angle at vertex", "angle opposite side"))
end

end
