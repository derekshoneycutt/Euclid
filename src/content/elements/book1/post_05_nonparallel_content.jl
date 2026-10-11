module ElementsOnePostulatesNonParallelLinesContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Non-Parallel Lines."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Postulate}: \textit{Non-Parallel Lines}

\textit{Let the following be postulated:}

That, if a straight line \euclidline[color=grey60,length=3,thickness=4] falling on two straight lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] make the interior angles on the same side less than two right angles, the two straight lines, if produced indefinitely, meet on the side on which are the angles less than the two right angles."""
end

"""Describe Euclid's parallel postulate using interior angles and a transversal."""
function get_search_content()
    return SearchContent(
        "Euclid's fifth or parallel postulate states that two lines cut by a transversal " *
        "meet on the side where the interior angles total less than two right angles.",
        ("Postulate V", "parallel postulate", "transversal interior angles"))
end

end
