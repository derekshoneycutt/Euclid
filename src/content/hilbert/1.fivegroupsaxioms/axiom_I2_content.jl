module HilbertChapterOneAxiomI2Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom I,2."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom I,2}

\textbf{I, 2.} Any two distinct points of a straight line completely determine that line; that is, if $AB = a$ \euclidline[color=steelblue,length=3,thickness=4] and $AC = a$ \euclidline[color=steelblue,length=3,thickness=4], where $B$ \euclidpoint[color=khaki3,size=1] $\neq C$ \euclidpoint[color=grey60,size=1], then is also $BC = a$ \euclidline[color=steelblue,length=3,thickness=4]."""
end

"""Describe how two points on a line determine that same line."""
function get_search_content()
    return SearchContent(
        "Axiom I,2 states that any two distinct points of a straight line completely " *
        "determine that line.",
        ("two points of a line", "same straight line", "line uniqueness"))
end

end
