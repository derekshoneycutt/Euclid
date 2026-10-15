module EuclidCurvesAstroidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Astroid."""
function get_view_content()
    return tex"""\textbf{Astroid}

An astroid is a hypotrochoid with $4$ cusps. Specifically, it is the curve traced by a point on a circle as it rolls inside another fixed circle with $4$ times the radius.

In terms of hypotrochoids, we can draw an astroid such that $R=4r$. Expressed as an irreducible fraction, $\frac{R}{r}=\frac{4}{1}$, this confirms that astroids have $4$ cusps.

$$x(\theta) = 3r\cos\theta + d\cos\left(3\theta\right)$$

$$y(\theta) = 3r\sin\theta - d\sin\left(3\theta\right)$$"""
end

"""Describe the four-cusped hypocycloid called an astroid."""
function get_search_content()
    return SearchContent(
        """Astroid
An astroid is a hypotrochoid with four 4 cusps. Specifically, it is the curve traced by a point on a circle as it rolls inside another fixed circle with 4 times the radius.
In terms of hypotrochoids, we can draw an astroid such that . Expressed as an irreducible fraction, , this confirms that astroids have 4 cusps.""",
        ("four-cusped hypocycloid", "tetracuspid", "four-pointed roulette"))
end

end
