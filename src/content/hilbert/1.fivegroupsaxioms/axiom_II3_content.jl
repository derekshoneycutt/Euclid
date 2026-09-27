module HilbertChapterOneAxiomII3Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom II,3."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom II,3}

\textbf{II, 3.} Of any three points \euclidpoint[color=palevioletred1,size=1] \euclidpoint[color=steelblue,size=1] \euclidpoint[color=khaki3,size=1] situated on a straight line \euclidline[color=grey60,length=3,thickness=4], there is always one and only one \euclidpoint[color=steelblue,size=1] which lies between the other two \euclidpoint[color=palevioletred1,size=1] \euclidpoint[color=khaki3,size=1]."""
end

"""Describe the unique middle point among three collinear points."""
function get_search_content()
    return SearchContent(
        "Axiom II,3 states that among any three points on a straight line, exactly one " *
        "lies between the other two.",
        ("one point between other two", "three collinear points", "unique middle point"))
end

end
