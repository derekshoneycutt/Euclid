module EuclidCurvesFiveHypocycloidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for 5-Hypocycloid."""
function get_view_content()
    return tex"""\textbf{5-Cusped Hypocycloid}

An five-cusped hypocycloid is a hypotrochoid with $5$ cusps, as its name suggests. Specifically, it is the curve traced by a point on a circle as it rolls inside another fixed circle with $5$ times the radius.

We can draw this such that $R=5r$. Expressed as an irreducible fraction, $\frac{R}{r}=\frac{5}{1}$, this also describes $5$ cusps.

$$x(\theta) = 4r\cos\theta + d\cos\left(4\theta\right)$$

$$y(\theta) = 4r\sin\theta - d\sin\left(4\theta\right)$$"""
end

"""Describe the five-cusped hypocycloid and its integer rolling ratio."""
function get_search_content()
    return SearchContent(
        """5-Cusped Hypocycloid
An five-cusped hypocycloid is a hypotrochoid with five 5 cusps, as its name suggests. Specifically, it is the curve traced by a point on a circle as it rolls inside another fixed circle with 5 times the radius.
We can draw this such that . Expressed as an irreducible fraction, , this also describes 5 cusps.""",
        ("five-cusped hypocycloid", "five-pointed roulette", "internal rolling curve"))
end

end
