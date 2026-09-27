module EuclidCurvesFiveHypocycloidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for 5-Hypocycloid."""
function get_view_content()
    return tex"""\textbf{5-Hypocycloid}

For $k=R/r=5$, a point on the internally rolling circle traces a five-cusped hypocycloid and closes after one revolution around the fixed center."""
end

"""Describe the five-cusped hypocycloid and its integer rolling ratio."""
function get_search_content()
    return SearchContent(
        "This five-cusped hypocycloid is traced on a circle rolling inside a fixed " *
        "circle at radius ratio R/r=5 and closes after one circuit.",
        ("five-cusped hypocycloid", "five-pointed roulette", "internal rolling curve"))
end

end
