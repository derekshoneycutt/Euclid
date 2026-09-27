module EuclidCurvesFivePointHypotrochoidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for 5-Point Hypotrochoid."""
function get_view_content()
    return tex"""\textbf{5-Point Hypotrochoid}

With $R:r:d=5:3:5$, the tracer extends beyond the internally rolling circle. The reduced ratio $R/r=5/3$ closes after three revolutions around the fixed center."""
end

"""Describe the extended tracer and closure ratio of this five-point hypotrochoid."""
function get_search_content()
    return SearchContent(
        "This five-pointed hypotrochoid uses ratio R:r:d=5:3:5, extending its tracer " *
        "beyond the internally rolling circle and closing after three circuits.",
        ("five-pointed spirograph", "extended internal tracer", "internal trochoid"))
end

end
