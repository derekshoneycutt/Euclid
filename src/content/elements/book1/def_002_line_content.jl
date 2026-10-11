module ElementsOneDefinitionLineContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

const DefinitionLatexDocument = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Line}

A line \euclidline[color=steelblue,length=3,thickness=4] is breadthless length."""

"""Return canonical explanatory content for Line."""
function get_view_content()
    return EuclidLatex.TeXDocument(DefinitionLatexDocument)
end

"""Describe Euclid's line as breadthless length."""
function get_search_content()
    return SearchContent(
        "Euclid defines a line as breadthless length: a one-dimensional geometric extent " *
        "with length but no width.",
        ("breadthless length", "one-dimensional extent", "line without width"))
end

end
