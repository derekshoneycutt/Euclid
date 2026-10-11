module ElementsOneDefinitionTrapeziaContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Trapezia."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Trapezia}

And let quadrilateral figures besides these be called trapezia \euclidbox[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=palevioletred1,edge3_color=khaki3,edge4_color=grey60]."""
end

"""Describe Euclid's residual class of quadrilaterals called trapezia."""
function get_search_content()
    return SearchContent(
        "Euclid calls quadrilateral figures other than squares, oblongs, rhombuses, and " *
        "rhomboids trapezia.",
        ("other quadrilaterals", "irregular quadrilateral", "trapezium"))
end

end
