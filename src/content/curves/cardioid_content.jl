module EuclidCurvesCardioidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Cardioid."""
function get_view_content()
    return tex"""\textbf{Cardioid}

A cardioid (from Greek καρδιά (kardiá) 'heart') is a plane curve traced by a point on the perimeter of a circle that is rolling around a fixed circle of the same radius."""
end

"""Describe the equal-circle construction and single cusp of a cardioid."""
function get_search_content()
    return SearchContent(
        "A cardioid is a heart-shaped, one-cusped epicycloid traced by a point on " *
        "a circle rolling around an equal fixed circle.",
        ("heart-shaped curve", "one-cusped epicycloid", "equal rolling circles"))
end

end
