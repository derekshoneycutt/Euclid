module ElementsOneDefinitionPointContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

const DefinitionLatexDocument = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Point}

A point \euclidpoint[color=steelblue,size=1] is that which has no part."""

"""Return canonical explanatory content for Point."""
function get_view_content()
    return EuclidLatex.TeXDocument(DefinitionLatexDocument)
end

"""Describe Euclid's partless geometric point."""
function get_search_content()
    return SearchContent(
        "Euclid defines a point as that which has no part, an indivisible geometric " *
        "position without length, breadth, or depth.",
        ("partless magnitude", "dimensionless point", "zero-dimensional"))
end

end
