module ElementsOneDefinitionObtuseTriangleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Obtuse-Angled Triangle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Obtuse-Angled Triangle}

Further, of trilateral figures, ... an obtuse-angled triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=palevioletred1,edge3_color=khaki3] that which has an obtuse angle \euclidangle[color=steelblue,radius=2,end=120,filled], ..."""
end

"""Describe an obtuse-angled triangle through its obtuse angle."""
function get_search_content()
    return SearchContent(
        "An obtuse-angled triangle is a trilateral figure that has one obtuse angle.",
        ("triangle with obtuse angle", "obtuse triangle", "one wide angle"))
end

end
