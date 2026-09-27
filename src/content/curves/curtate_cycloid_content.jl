module EuclidCurvesCurtateCycloidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Curtate Cycloid."""
function get_view_content()
    return tex"""\textbf{Curtate Cycloid}

When the tracing point lies inside the rolling circle, $d<r$, it traces a curtate cycloid. The curve remains above the fixed line through two wheel revolutions."""
end

"""Describe the smooth path traced inside a rolling circle."""
function get_search_content()
    return SearchContent(
        "A curtate cycloid is traced by a point inside a circle rolling along a " *
        "straight line, producing a smooth curve that never reaches the rail.",
        ("shortened cycloid", "tracer inside rolling circle", "smooth cycloid"))
end

end
