module HilbertChapterOneTheorem11Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 11."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 11 (Second theorem of congruence for triangles)}

If in any two triangles one side and the two adjacent angles are respectively congruent, the triangles are congruent."""
end

"""Describe the second triangle congruence theorem using a side and two angles."""
function get_search_content()
    return SearchContent(
        "Theorem 11 states that two triangles are congruent when one corresponding side " *
        "and its two adjacent angles are congruent.",
        ("angle side angle", "ASA triangle congruence", "second congruence theorem"))
end

end
