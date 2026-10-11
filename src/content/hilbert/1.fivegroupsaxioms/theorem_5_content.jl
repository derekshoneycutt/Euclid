module HilbertChapterOneTheorem5Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 5."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 5}

Every straight line $a$ \euclidline[color=grey60,length=3,thickness=4], which lies in a plane $\alpha$, divides the remaining points of this plane into two regions having the following properties: Every point $A$ \euclidpoint[color=steelblue,size=1] of the one region determines with each point $B$ \euclidpoint[color=palevioletred1,size=1] of the other region a segment $AB$ \euclidline[color=steelblue,length=3,thickness=4] containing a point of the straight line $a$ \euclidline[color=grey60,length=3,thickness=4]. On the other hand, any two points $A$ \euclidpoint[color=steelblue,size=1], $A'$ \euclidpoint[color=khaki3,size=1] of the same region determine a segment $AA'$ \euclidline[color=khaki3,length=3,thickness=4] containing no point of $a$ \euclidline[color=grey60,length=3,thickness=4]."""
end

"""Describe how a straight line separates its plane into two regions."""
function get_search_content()
    return SearchContent(
        "Theorem 5 states that a line divides its plane into two regions: segments between " *
        "opposite regions cross the line, while segments within one region do not.",
        ("line divides plane", "same and opposite sides", "two plane regions"))
end

end
