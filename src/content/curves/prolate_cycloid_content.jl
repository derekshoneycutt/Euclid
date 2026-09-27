module EuclidCurvesProlateCycloidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Prolate Cycloid."""
function get_view_content()
    return tex"""\textbf{Prolate Cycloid}

When the tracing point lies outside the rolling circle, $d>r$, it traces a prolate cycloid with a loop during each wheel revolution."""
end

"""Describe the looped path traced outside a rolling circle."""
function get_search_content()
    return SearchContent(
        "A prolate cycloid is traced by a point outside a circle rolling along a " *
        "straight line, producing a loop during each revolution.",
        ("extended cycloid", "tracer outside rolling circle", "looped cycloid"))
end

end
