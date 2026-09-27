module ElementsOneDefinitionPerpendicularContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for perpendicular lines."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Right Angles and Perpendicular}

When a straight line set up on a straight line \euclidperpendicular[thickness=2,line1_color=steelblue,line2_color=palevioletred1,height=2,width=3] makes the adjacent angles \euclidangle[color=khaki3,radius=2,thickness=2] equal to one another, each of the equal angles is right, and the straight line standing on the other is called a perpendicular to that on which it stands."""
end

"""Return semantic prose and aliases for perpendicular-line discovery."""
function get_search_content()
    return SearchContent(
        "A straight line is perpendicular to another when it forms equal adjacent " *
        "right angles with that line.",
        ("perpendicular lines", "right angle", "normal line"))
end

end