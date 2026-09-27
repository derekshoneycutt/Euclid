module ElementsOneDefinitionRhombusContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Rhombus."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Rhombus}

Of quadrilateral figures, ... a rhombus \euclidbox[height=2,width=2,thickness=2,edge1_color=palevioletred1,edge2_color=palevioletred1,edge3_color=palevioletred1,edge4_color=palevioletred1] that which is equilateral \euclidline[color=palevioletred1,length=3,thickness=4] but not right angled \euclidangle[color=steelblue,radius=2,end=60,filled] \euclidangle[color=khaki3,radius=2,end=120,filled]; ..."""
end

"""Describe Euclid's rhombus as equilateral but not right-angled."""
function get_search_content()
    return SearchContent(
        "A rhombus is a quadrilateral that is equilateral but not right-angled.",
        ("four equal sides", "non-right angles", "equilateral quadrilateral"))
end

end
