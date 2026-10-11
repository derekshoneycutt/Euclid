module ElementsOneDefinitionIsoscelesContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Isosceles Triangle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Isosceles Triangle}

Of trilateral figures, ... an isosceles triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=palevioletred1,edge3_color=steelblue] is that which has two of its sides \euclidline[color=steelblue,length=3,thickness=4] alone equal, ..."""
end

"""Describe an isosceles triangle through equality of two sides alone."""
function get_search_content()
    return SearchContent(
        "An isosceles triangle is a trilateral figure with two of its sides alone equal.",
        ("two equal sides", "equal-legged triangle", "isosceles"))
end

end
