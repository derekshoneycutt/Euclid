module ElementsOneDefinitionAcuteTriangleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Acute-Angled Triangle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Acute-Angled Triangle}

Further, of trilateral figures, ... an acute-angled triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=palevioletred1,edge3_color=palevioletred1] that which has its three angles acute \euclidangle[color=steelblue,radius=2,end=60,filled]."""
end

"""Describe an acute-angled triangle through its three acute angles."""
function get_search_content()
    return SearchContent(
        "An acute-angled triangle is a trilateral figure whose three angles are acute.",
        ("all angles acute", "acute triangle", "three acute angles"))
end

end
