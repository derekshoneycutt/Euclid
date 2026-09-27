module EuclidCurvesThreeDimpleEpitrochoidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for 3-Dimple Epitrochoid."""
function get_view_content()
    return tex"""\textbf{3-Dimple Epitrochoid}

With $R:r:d=3:1:1/2$, a point halfway from the rolling circle's center to its rim traces three smooth inward dimples."""
end

"""Describe the external rolling construction of this three-dimple epitrochoid."""
function get_search_content()
    return SearchContent(
        "This epitrochoid uses radius and tracer ratio R:r:d=3:1:1/2 to form three " *
        "smooth inward dimples as its circle rolls outside the fixed circle.",
        ("three-lobed epitrochoid", "three-dimple roulette", "external trochoid"))
end

end
