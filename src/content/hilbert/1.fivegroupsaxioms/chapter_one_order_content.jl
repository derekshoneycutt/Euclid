module HilbertChapterOneOrderContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for §3 Group II: Axioms of Order."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§3 Group II: Axioms of Order}

The axioms of this group define the idea expressed by the word "between," and make possible, upon the basis of this idea, an order of sequence of the points upon a straight line, in a plane, and in space. The points of a straight line have a certain relation to one another which the word "between" serves to describe.

...

Axioms II, 1-4 contain statements concerning the points of a straight line only, and, hence, we will call them the linear axioms of group II. Axiom II, 5 relates to the elements of plane geometry and, consequently, shall be called the plane axiom of group II."""
end

"""Describe Hilbert's betweenness relation and ordering of points."""
function get_search_content()
    return SearchContent(
        "The axioms of order define betweenness and the sequence of points on a straight " *
        "line, distinguishing linear axioms from the plane axiom of order.",
        ("betweenness", "sequence of points", "linear order axioms"))
end

end
