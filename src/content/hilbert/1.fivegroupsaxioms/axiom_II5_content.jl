module HilbertChapterOneAxiomII5Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom II,5."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom II,5}

\textbf{II, 5.} Let $A$ \euclidpoint[color=steelblue,size=1], $B$ \euclidpoint[color=palevioletred1,size=1], $C$ \euclidpoint[color=khaki3,size=1] be three points not lying in the same straight line \euclidline[color=khaki3,length=3,thickness=4] and let $a$ \euclidline[color=steelblue,length=3,thickness=4] be a straight line lying in the plane $ABC$ and not passing through any of the points $A$ \euclidpoint[color=steelblue,size=1], $B$ \euclidpoint[color=palevioletred1,size=1], $C$ \euclidpoint[color=khaki3,size=1]. Then, if the straight line a passes through a point of the segment $AB$ \euclidline[color=khaki3,length=3,thickness=4], it will also pass through either a point of the segment $BC$ \euclidline[color=grey60,length=3,thickness=4] or a point of the segment $AC$ \euclidline[color=grey60,length=3,thickness=4]."""
end

"""Describe the triangle-crossing property of Hilbert's plane order axiom."""
function get_search_content()
    return SearchContent(
        "Axiom II,5 states that a coplanar line crossing one side of a triangle without " *
        "passing through a vertex must cross one of the other two sides.",
        ("Pasch axiom", "line crosses triangle", "plane order axiom"))
end

end
