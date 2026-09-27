module ElementsOneDefinitionScaleneContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Scalene Triangle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Scalene Triangle}

Of trilateral figures, ... and a scalene triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=palevioletred1,edge3_color=khaki3] that which has its three sides \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] \euclidline[color=khaki3,length=3,thickness=4] unequal."""
end

"""Describe a scalene triangle through inequality of all three sides."""
function get_search_content()
    return SearchContent(
        "A scalene triangle is a trilateral figure whose three sides are unequal.",
        ("all sides unequal", "three unequal sides", "unequal-sided triangle"))
end

end
