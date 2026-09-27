module HilbertChapterOneConsequencesContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for §4 Consequences after Group II."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§4 Consequences of the Axioms of Connection and Order}

By the aid of the four linear axioms II, 1-4, we can easily deduce several theorems."""
end

"""Describe the theorems following Hilbert's connection and order axioms."""
function get_search_content()
    return SearchContent(
        "This section develops consequences of the axioms of connection and order, " *
        "especially the four linear axioms governing points on a straight line.",
        ("consequences of order", "linear axiom theorems", "connection and order"))
end

end
