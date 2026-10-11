module HilbertChapterOneTheorem1Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 1."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 1}

Two straight lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] of a plane have either one point \euclidpoint[color=khaki3,size=1] or no point in common; two planes have no point in common or a straight line in common; a plane and a straight line not lying in it have no point or one point in common."""
end

"""Describe the possible intersections of lines and planes."""
function get_search_content()
    return SearchContent(
        "Theorem 1 limits intersections: two coplanar lines share one point or none, two " *
        "planes share a line or none, and a line not in a plane shares at most one point.",
        ("line plane intersections", "planes share straight line", "at most one common point"))
end

end
