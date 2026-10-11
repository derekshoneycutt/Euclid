module HilbertChapterOneDefinitionCircleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definition: Circle."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Circle}

If $M$ \euclidpoint[color=palevioletred1,size=1] is an arbitrary point in the plane $\alpha$, the totality of all points
$A$ \euclidpoint[color=steelblue,size=0.5], for which the segments $MA$ \euclidline[color=plum1,length=3,thickness=1] are congruent to one another, is called a circle
\euclidcircle[color=steelblue,size=1,thickness=2]. $M$ \euclidpoint[color=palevioletred1,size=1] is called the centre of the circle.

From this definition can be easily deduced, with the help of the axioms of \textit{groups III and IV},
the known properties of the circle; in particular, the possibility of constructing a circle through any three points not
lying in a straight line, as also the congruence of all angles inscribed in the same segment of a circle, and the theorem relating to the angles of an inscribed quadrilateral."""
end

"""Describe Hilbert's circle as points at congruent distances from a center."""
function get_search_content()
    return SearchContent(
        "A circle is the totality of points in a plane whose segments from one center are " *
        "congruent to one another.",
        ("equidistant points from center", "circle centre", "congruent radii"))
end

end
