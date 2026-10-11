module EuclidCurvesCycloidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Cycloid."""
function get_view_content()
    return tex"""\textbf{Cycloid}

A point at distance $d=r$ from the center of a circle rolling without slipping along a fixed line traces a cycloid. This construction follows two complete wheel revolutions."""
end

"""Describe the rim-traced cusps of an ordinary cycloid."""
function get_search_content()
    return SearchContent(
        "A cycloid is traced by a point on the rim of a circle rolling without " *
        "slipping along a straight line, forming one cusp per revolution.",
        ("rolling circle", "wheel curve", "cusped roulette"))
end

end
