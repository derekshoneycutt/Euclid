module ElementsOneDefinitionRightTriangleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Right-Angled Triangle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Right-Angled Triangle}

Further, of trilateral figures, a right-angled triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=palevioletred1,edge3_color=khaki3] is that which has a right angle \euclidangle[color=steelblue,radius=2,thickness=2], ..."""
end

"""Describe a right-angled triangle through its right angle."""
function get_search_content()
    return SearchContent(
        "A right-angled triangle is a trilateral figure that has one right angle.",
        ("triangle with right angle", "right triangle", "one right angle"))
end

end
