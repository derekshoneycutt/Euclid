module EuclidCurvesConvexLimaconContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Convex Limaçon."""
function get_view_content()
    return tex"""\textbf{Convex Limaçon}

A convex limaçon is traced when the carried point remains close enough to the rolling circle's center that the curve bends outward everywhere."""
end

"""Describe the near-center tracer that produces a convex limaçon."""
function get_search_content()
    return SearchContent(
        "A convex limaçon is traced near the center of an externally rolling circle, " *
        "so its smooth outline bends outward everywhere without a dimple or loop.",
        ("convex limacon", "unindented limaçon", "outward-bending curve"))
end

end
