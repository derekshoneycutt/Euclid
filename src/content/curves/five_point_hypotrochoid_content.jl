module EuclidCurvesFivePointHypotrochoidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for 5-Point Hypotrochoid."""
function get_view_content()
    return tex"""\textbf{5-Round-Point Hypotrochoid}

A 5-Round-Point Hypotrochoid is created by an inner rolling circle having a ratio of $\frac{5}{3}$ to an outer fixed circle, and the distance between the tracing point $P$ and the center of the inner rolling circle having the ratio $\frac{5}{3}$.
That is, $\frac{R}{r}=\frac{5}{3}$ and $\frac{d}{r}=\frac{5}{3}$.

This results in the point $P$ crossing in and out of the static outer circle, creating a rounded star-like pattern.

$$x(\theta) = \frac{2r}{3}\cos\theta + \frac{5r}{3}\cos\left(\frac{2}{3}\theta\right)$$

$$y(\theta) = \frac{2r}{3}\sin\theta - \frac{5r}{3}\sin\left(\frac{2}{3}\theta\right)$$"""
end

"""Describe the extended tracer and closure ratio of this five-point hypotrochoid."""
function get_search_content()
    return SearchContent(
        """5-Round-Point Hypotrochoid
A 5-Round-Point Hypotrochoid is created by an inner rolling circle having a ratio of 5/3 to an outer fixed circle, and the distance between the tracing point P and the center of the inner rolling circle having the ratio 5:3.
That is, R/r=5/3 and d/r=5/3.
This results in the point P crossing in and out of the static outer circle, creating a rounded star-like pattern.""",
        ("five-pointed spirograph", "extended internal tracer", "internal trochoid"))
end

end
