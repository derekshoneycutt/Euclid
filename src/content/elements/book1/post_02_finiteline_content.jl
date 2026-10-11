module ElementsOnePostulatesFiniteLineContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Produce a Finite Line."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Postulates}: \textit{Produce a Finite Line}

\textit{Let the following be postulated:}

To produce a finite straight line \euclidline[color=steelblue,length=3,thickness=4] continuously in a straight line."""
end

"""Describe Euclid's second postulate for extending a finite line."""
function get_search_content()
    return SearchContent(
        "Euclid's second postulate permits extending a finite straight line continuously " *
        "in the same direction beyond its endpoint.",
        ("Postulate II", "extend a line", "produce straight line"))
end

end
