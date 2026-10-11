module HilbertChapterOneTheorem3Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 3."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 3}

Between any two points \euclidpoint[color=steelblue,size=1] \euclidpoint[color=palevioletred1,size=1] of a straight line \euclidline[color=grey60,length=3,thickness=4], there always exists an unlimited number of points \euclidpoint[color=khaki3,size=1]."""
end

"""Describe the unlimited points between two points of a line."""
function get_search_content()
    return SearchContent(
        "Theorem 3 states that between any two points of a straight line there are an " *
        "unlimited number of points.",
        ("infinitely many points between", "unlimited intermediate points", "points dense on line"))
end

end
