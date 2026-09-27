module ElementsOneDefinitionOblongContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Oblong."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Oblong}

Of quadrilateral figures, ... an oblong \euclidbox[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=palevioletred1,edge3_color=khaki3,edge4_color=palevioletred1] that which is right-angled \euclidangle[color=steelblue,radius=2,thickness=2] but not equilateral \euclidline[color=palevioletred1,length=3,thickness=4] \euclidline[color=khaki3,length=3,thickness=4]; ..."""
end

"""Describe Euclid's oblong as right-angled but not equilateral."""
function get_search_content()
    return SearchContent(
        "An oblong is a quadrilateral that is right-angled but not equilateral.",
        ("rectangle", "right-angled quadrilateral", "unequal adjacent sides"))
end

end
