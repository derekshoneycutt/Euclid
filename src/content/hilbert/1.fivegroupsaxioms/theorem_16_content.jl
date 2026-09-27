module HilbertChapterOneTheorem16Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 16."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 16 (Third theorem of congruence for triangles)}

If two triangles \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=steelblue,edge3_color=palevioletred1]
\euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=steelblue,edge3_color=palevioletred1] have
the three sides of one congruent respectively to the corresponding three sides of the other, the triangles are congruent
\euclidtriangle[height=2,width=3,thickness=1,edge1_color=lightgreen,edge2_color=lightgreen,edge3_color=lightgreen]."""
end

"""Describe the third triangle congruence theorem using three sides."""
function get_search_content()
    return SearchContent(
        "Theorem 16 states that triangles with all three corresponding sides congruent " *
        "are congruent to one another.",
        ("side side side", "SSS triangle congruence", "third congruence theorem"))
end

end
