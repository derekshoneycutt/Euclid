module EuclidCurvesNephroidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Nephroid."""
function get_view_content()
    return tex"""\textbf{Nephroid}

A Nephroid is the two-cusped epicycloid traced by a point on a circle rolling around a fixed circle twice its radius."""
end

"""Describe the two-cusped epicycloid called a nephroid."""
function get_search_content()
    return SearchContent(
        "A nephroid is a kidney-shaped, two-cusped epicycloid traced by a circle " *
        "rolling outside a fixed circle twice its radius.",
        ("two-cusped epicycloid", "kidney-shaped curve", "external rolling curve"))
end

end
