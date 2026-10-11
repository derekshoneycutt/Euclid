module EuclidCurvesDeltoidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Deltoid."""
function get_view_content()
    return tex"""\textbf{Deltoid}

A deltoid is the three-cusped hypocycloid with $k=R/r=3$. A point on the rolling circle traces one closed curve while that circle rolls inside the fixed circle."""
end

"""Describe the three-cusped hypocycloid called a deltoid."""
function get_search_content()
    return SearchContent(
        "A deltoid is a three-cusped hypocycloid traced on a circle rolling inside " *
        "a fixed circle three times its radius.",
        ("three-cusped hypocycloid", "Steiner deltoid", "three-pointed roulette"))
end

end
