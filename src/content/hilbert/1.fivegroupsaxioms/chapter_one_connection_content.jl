module HilbertChapterOneConnectionContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for §2 Group I: Axioms of Connection."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§2 Group I: Axioms of Connection}

The axioms of this group establish a connection between the concepts indicated above; namely, points, straight lines, and planes.

...

Axioms I, 1-2 contain statements concerning points and straight lines only; that is, concerning the elements of plane geometry. We will call them, therefore, the plane axioms of group I, in order to distinguish them from the axioms I, 3-7, which we will designate briefly as the space axioms of this group.
Of the theorems which follow from the axioms I, 3-7, we shall mention only 2."""
end

"""Describe the incidence relations established by Hilbert's connection axioms."""
function get_search_content()
    return SearchContent(
        "The axioms of connection relate points, straight lines, and planes, separating " *
        "plane incidence axioms from the corresponding axioms of space.",
        ("incidence axioms", "points lines planes", "plane and space axioms"))
end

end
