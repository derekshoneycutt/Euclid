module HilbertChapterOneTheorem7Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 7."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 7}

Every plane $\alpha$ divides the remaining points of space into two regions having the following properties: Every point $A$ \euclidpoint[color=steelblue,size=1] of the one region determines with each point $B$ \euclidpoint[color=palevioletred1,size=1] of the other region a segment $AB$ \euclidline[color=khaki3,length=3,thickness=4], within which lies a point of $\alpha$. On the other hand, any two points $A$ \euclidpoint[color=steelblue,size=1], $A'$ \euclidpoint[color=khaki3,size=1] lying within the same region determine a segment $AA'$ \euclidline[color=palevioletred1,length=3,thickness=4] containing no point of $\alpha$.

...

Making use of the notation of \textit{theorem 7}, we may now say: The points $A$ \euclidpoint[color=steelblue,size=1], $A'$ \euclidpoint[color=khaki3,size=1] are situated in space upon one and the same side of the plane $\alpha$, and the points $A$ \euclidpoint[color=steelblue,size=1], $B$ \euclidpoint[color=palevioletred1,size=1] are situated in space upon different sides of the plane $\alpha$.

\textit{Theorem 7} gives us the most important facts relating to the order of sequence of the elements of space. These facts are the results, exclusively, of the axioms already considered, and, hence, no new space axioms are required in \textit{group II}."""
end

"""Describe how a plane separates space into two regions."""
function get_search_content()
    return SearchContent(
        "Theorem 7 states that a plane divides space into two regions: segments between " *
        "opposite sides cross the plane, while segments on one side do not.",
        ("plane divides space", "same side of plane", "opposite sides of plane"))
end

end
