module ElementsOneDefinitionSquareContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Square."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Square}

Of quadrilateral figures, a square \euclidbox[height=2,width=2,thickness=2,edge1_color=palevioletred1,edge2_color=palevioletred1,edge3_color=palevioletred1,edge4_color=palevioletred1] is that which is both equilateral \euclidline[color=palevioletred1,length=3,thickness=4] and right-angled \euclidangle[color=steelblue,radius=2,thickness=2]; ..."""
end

"""Describe Euclid's square by equal sides and right angles."""
function get_search_content()
    return SearchContent(
        "A square is a quadrilateral that is both equilateral and right-angled.",
        ("four equal sides", "four right angles", "equilateral right-angled quadrilateral"))
end

end
