module ElementsOneDefinitionSurfaceContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

const SurfaceView = tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Surface}

A surface is that which has length and breadth only."""

"""Return canonical explanatory content for Surface."""
function get_view_content()
    return SurfaceView
end

"""Describe Euclid's surface as length and breadth without depth."""
function get_search_content()
    return SearchContent(
    "Euclid defines a surface as an extent having length and breadth only, without " *
    "depth or thickness.",
    ("two-dimensional extent", "length and breadth", "surface without depth"))
end

end