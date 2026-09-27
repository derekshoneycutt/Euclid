module ElementsOnePostulatesDrawCircleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Draw a Circle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Postulates}: \textit{Draw a Circle}

\textit{Let the following be postulated:}

To describe a circle \euclidcircle[color=steelblue,size=1,thickness=2] with any center \euclidpoint[color=palevioletred1,size=1] and distance."""
end

"""Describe Euclid's third postulate for constructing a circle."""
function get_search_content()
    return SearchContent(
        "Euclid's third postulate permits describing a circle with any chosen center and " *
        "distance, supplying the compass operation for geometric construction.",
        ("Postulate III", "compass construction", "center and radius"))
end

end
