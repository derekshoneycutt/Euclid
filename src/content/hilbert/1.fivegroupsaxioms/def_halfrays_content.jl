module HilbertChapterOneDefHalfRaysContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definition: Half-rays."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Half-rays}

If $A$ \euclidpoint[color=steelblue,size=1], $A'$ \euclidpoint[color=steelblue,size=1], $O$ \euclidpoint[color=khaki3,size=1], $B$ \euclidpoint[color=palevioletred1,size=1] are four points of a straight line $a$ \euclidline[color=grey60,length=3,thickness=4], where $O$ \euclidpoint[color=khaki3,size=1] lies between $A$ \euclidpoint[color=steelblue,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1] but not between $A$ \euclidpoint[color=steelblue,size=1] and $A'$ \euclidpoint[color=steelblue,size=1], then points $A$ \euclidpoint[color=steelblue,size=1] and $A'$ \euclidpoint[color=steelblue,size=1] are on the same side of $O$ \euclidpoint[color=khaki3,size=1], and points $A$ \euclidpoint[color=steelblue,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1] are on different sides of $O$ \euclidpoint[color=grey60,size=1].

All points of a that lie on the same side of $O$ \euclidpoint[color=khaki3,size=1], taken together, are called a half-ray emanating from $O$ \euclidpoint[color=khaki3,size=1]."""
end

"""Describe a half-ray using points on one side of its origin."""
function get_search_content()
    return SearchContent(
        "A half-ray emanating from a point consists of all points of a straight line on " *
        "the same side of that point.",
        ("ray from origin", "same side of point", "half-line"))
end

end
