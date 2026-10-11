module EuclidCurvesLimaconContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Limaçon."""
function get_view_content()
    return tex"""\textbf{Limaçon}

A limaçon is traced by a point carried by a circle rolling around a circle of equal radius. Placing the tracer beyond the rolling rim produces an inner loop."""
end

"""Describe the extended tracer and inner loop of this limaçon."""
function get_search_content()
    return SearchContent(
        "This limaçon is an epitrochoid traced beyond the rim of a circle rolling " *
        "around an equal fixed circle, producing a pronounced inner loop.",
        ("Pascal's limaçon", "limacon", "snail curve", "inner-loop curve"))
end

end
