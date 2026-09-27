module EuclidCurvesElevenHalfHypocycloidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for 11⁄2-Hypocycloid."""
function get_view_content()
    return tex"""\textbf{11⁄2-Hypocycloid}

For $k=R/r=11/2$, the hypocycloid has eleven cusps. The denominator requires two revolutions around the fixed center before the tracing point returns to its start."""
end

"""Describe the eleven cusps and two-circuit closure of this hypocycloid."""
function get_search_content()
    return SearchContent(
        "This rational hypocycloid has radius ratio R/r=11/2, forms eleven cusps, " *
        "and closes after two circuits around the fixed center.",
        ("11/2 hypocycloid", "eleven-cusped hypocycloid", "rational hypocycloid"))
end

end
