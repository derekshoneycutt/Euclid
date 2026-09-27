module HilbertChapterOneAxiomI7Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom I,7."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom I,7}

\textbf{I, 7.} Upon every straight line \euclidline[color=steelblue,length=3,thickness=4] there exists at least two points \euclidpoint[color=palevioletred1,size=1] \euclidpoint[color=khaki3,size=1], in every plane at least three points \euclidpoint[color=steelblue,size=1] not lying in the same straight line, and in space there exist at least four points \euclidpoint[color=grey60,size=1] not lying in a plane."""
end

"""Describe Hilbert's minimum point-existence requirements."""
function get_search_content()
    return SearchContent(
        "Axiom I,7 requires at least two points on every line, three noncollinear points " *
        "in every plane, and four noncoplanar points in space.",
        ("point existence", "four points not in a plane", "minimum points line plane space"))
end

end
