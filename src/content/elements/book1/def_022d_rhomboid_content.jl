module ElementsOneDefinitionRhomboidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Rhomboid."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Rhomboid}

Of quadrilateral figures, ... and a rhomboid \euclidbox[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=palevioletred1,edge3_color=khaki3,edge4_color=palevioletred1] that which has its opposite sides \euclidline[color=palevioletred1,length=3,thickness=4] \euclidline[color=khaki3,length=3,thickness=4] and angles \euclidangle[color=steelblue,radius=2,end=60,filled] \euclidangle[color=grey60,radius=2,end=120,filled] equal to one another but is neither equilateral nor right-angled."""
end

"""Describe a rhomboid through its opposite sides and angles."""
function get_search_content()
    return SearchContent(
        "A rhomboid has opposite sides and opposite angles equal, but is neither " *
        "equilateral nor right-angled.",
        ("opposite sides equal", "opposite angles equal", "oblique parallelogram"))
end

end
