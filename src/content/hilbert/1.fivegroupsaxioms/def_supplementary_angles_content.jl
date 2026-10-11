module HilbertChapterOneDefSupplementaryAnglesContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definition: Supplementary Angles."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Supplementary Angles}

Two angles \euclidangle[color=khaki3,radius=2,thickness=2,start=90,end=180]\euclidangle[color=khaki3,radius=2,thickness=2] having the same vertex and one side in common, while the sides not common form a straight line, are called supplementary angles.
Two angles \euclidangle[color=khaki3,radius=2,thickness=2,start=90,end=180]\euclidangle[color=khaki3,radius=2,thickness=2] having a common vertex and whose sides form straight lines are called vertical angles.
An angle which is congruent to its supplementary angle is called a right angle \euclidangle[color=khaki3,radius=2,thickness=2,start=90,end=180]\euclidangle[color=khaki3,radius=2,thickness=2]."""
end

"""Describe supplementary, vertical, and right angles."""
function get_search_content()
    return SearchContent(
        "Supplementary angles share a vertex and side while their other sides form a " *
        "straight line; the definition also identifies vertical and right angles.",
        ("adjacent supplementary angles", "vertical angles", "angle equal to its supplement"))
end

end
