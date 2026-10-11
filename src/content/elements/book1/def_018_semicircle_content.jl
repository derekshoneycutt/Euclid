module ElementsOneDefinitionSemicircleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Semicircle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Semicircle}

A semicircle \euclidsemicircle[color=steelblue,radius=2,thickness=2] is the figure contained by the diameter and the circumference cut off by it. And the center \euclidpoint[color=palevioletred1,size=1] of the semicircle is the same as that of the circle."""
end

"""Describe the half-circle bounded by a diameter and circumference."""
function get_search_content()
    return SearchContent(
        "A semicircle is the figure bounded by a diameter and the half of the " *
        "circumference it cuts off, sharing the circle's center.",
        ("half circle", "diameter and arc", "half circumference"))
end

end
