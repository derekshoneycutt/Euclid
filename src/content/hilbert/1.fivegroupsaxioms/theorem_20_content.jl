module HilbertChapterOneTheorem20Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 20."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 20}

The sum of the angles of a triangle is two right angles."""
end

"""Describe the sum of a triangle's angles as two right angles."""
function get_search_content()
    return SearchContent(
        "Theorem 20 states that the three angles of a triangle sum to two right angles.",
        ("triangle angle sum", "two right angles", "180 degrees"))
end

end
