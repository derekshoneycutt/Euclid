module ElementsOnePostulatesEqualRightAnglesContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Equal Right Angles."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Postulate}: \textit{Equal Right Angles}

\textit{Let the following be postulated:}

That all right angles \euclidangle[color=grey60,radius=2,thickness=2] are equal to one another."""
end

"""Describe Euclid's fourth postulate equating all right angles."""
function get_search_content()
    return SearchContent(
        "Euclid's fourth postulate asserts that all right angles are equal to one another, " *
        "a geometric equality rather than a construction permission.",
        ("Postulate IV", "right angle equality", "equal right angles"))
end

end
