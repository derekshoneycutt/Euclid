module HilbertChapterOneDefinitionSideOfLineContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definition: Side of Line."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Side of Line}

Making use of the notation of \textit{theorem 5}, we say: The points $A$ \euclidpoint[color=steelblue,size=1],
$A'$ \euclidpoint[color=khaki3,size=1] lie in the plane $\alpha$ upon one and the same side of the straight line
$a$ \euclidline[color=grey60,length=3,thickness=4], and the points $A$ \euclidpoint[color=steelblue,size=1],
$B$ \euclidpoint[color=palevioletred1,size=1] lie in the plane $\alpha$ upon different sides of the
straight line $a$ \euclidline[color=grey60,length=3,thickness=4]."""
end

"""Describe points lying on the same or different sides of a line."""
function get_search_content()
    return SearchContent(
        "This definition distinguishes points in a plane that lie on the same side or on " *
        "different sides of a straight line.",
        ("same side of line", "different sides of line", "plane divided by line"))
end

end
