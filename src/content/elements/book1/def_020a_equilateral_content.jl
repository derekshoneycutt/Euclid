module ElementsOneDefinitionEquilateralContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Equaliteral Triangle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Equilateral Triangle}

Of trilateral figures, an equilateral triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=steelblue,edge3_color=steelblue]  is that which has its three sides equal \euclidline[color=steelblue,length=3,thickness=4], ..."""
end

"""Describe an equilateral triangle through equality of all three sides."""
function get_search_content()
    return SearchContent(
        "An equilateral triangle is a trilateral figure whose three sides are equal.",
        ("all three sides equal", "equal-sided triangle", "equilateral"))
end

end
