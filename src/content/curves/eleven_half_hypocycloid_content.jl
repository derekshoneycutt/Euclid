module EuclidCurvesElevenHalfHypocycloidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for 11⁄2 Hypocycloid."""
function get_view_content()
    return tex"""\textbf{11⁄2 Hypocycloid}

An 11⁄2 hypotrochoid is the curve traced by a point on a circle as it rolls inside another fixed circle with radius of ratio $\frac{11}{2}$ outer/fixed over inner/rolling.

We can draw this such that $R/r=\frac{11}{2}$. This gives $11$ cusps, requiring $2$ cycles of the inner circle rolling within the fixed outer circle.

$$x(\theta) = 9\cos\theta + 2\cos\left(\frac{9}{2}\theta\right)$$

$$y(\theta) = 9\sin\theta - 2\sin\left(\frac{9}{2}\theta\right)$$"""
end

"""Describe the eleven cusps and two-circuit closure of this hypocycloid."""
function get_search_content()
    return SearchContent(
        """rational 11/2 Hypocycloid
An 11⁄2 hypotrochoid is the curve traced by a point on a circle as it rolls inside another fixed circle with radius of ratio outer/fixed over inner/rolling.
We can draw this such that R/r=11/2. This gives 11 cusps, requiring 2 cycles of the inner circle rolling within the fixed outer circle.""",
        ("11/2 hypocycloid", "eleven-cusped hypocycloid", "rational hypocycloid"))
end

end
