module ElementsOneBookOnePostulatesContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Postulates."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Postulates}

Book I asks that five geometric statements be granted. The first three permit drawing
a line, extending a finite line, and describing a circle. The fourth equates all right
angles, while the famous fifth has to deal with parallel lines."""
end

"""Describe the five geometric assumptions underlying Book I."""
function get_search_content()
    return SearchContent(
        "Euclid's five postulates grant line and circle constructions and assert the " *
        "equality of right angles and the meeting condition for non-parallel lines.",
        ("geometric axioms", "Euclid postulates", "straightedge and compass"))
end

end
