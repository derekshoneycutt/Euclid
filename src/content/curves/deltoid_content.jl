module EuclidCurvesDeltoidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Deltoid."""
function get_view_content()
    return tex"""\textbf{Deltoid}

A deltoid is a hypotrochoid with $3$ cusps. Specifically, it is the curve traced by a point on a circle as it rolls inside another fixed circle with $3$ times the radius.

In terms of hypotrochoids, we can draw a deltoid such that $R=3r$. Expressed as an irreducible fraction, $\frac{R}{r}=\frac{3}{1}$, this confirms that deltoids have $3$ cusps.

$$x(\theta) = 2r\cos\theta + d\cos\left(2\theta\right)$$

$$y(\theta) = 2r\sin\theta - d\sin\left(2\theta\right)$$"""
end

"""Describe the three-cusped hypocycloid called a deltoid."""
function get_search_content()
    return SearchContent(
        """Deltoid
A deltoid is a hypotrochoid with three 3 cusps. Specifically, it is the curve traced by a point on a circle as it rolls inside another fixed circle with 3 times the radius.
In terms of hypotrochoids, we can draw a deltoid such that . Expressed as an irreducible fraction, , this confirms that deltoids have 3 cusps.""",
        ("three-cusped hypocycloid", "Steiner deltoid", "three-pointed roulette"))
end

end
