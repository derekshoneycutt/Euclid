module EuclidCurvesOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Curves."""
function get_view_content()
    return tex"""\textbf{Curves}

Here, we explore various kinds of curves in geometry.

Many curves are drawn as roulette curves, with one shape rolling along another. Many of these are types of trochoids. A trochoid is formed by a circle rolling along a line, which may itself be curved or straight.

A cycloid is the curve traced by a point relative to a circle as it rolls along a straight line without slipping.
Assume the line is the x-axis and we have a circle with radius $r$.
Let $d$ be the distance from the center of the circle to a point $P$ that rolls with the circle,
and we trace $P$ as it rolls with the circle. This gives us the formulas for the cycloid.

$$x(\theta) = r\theta - d\sin\theta$$

$$y(\theta) = r - d\cos\theta$$

Hypotrochoids and epitrochoids are formed by tracing a point relative to a circle as it rolls along another circle.

A hypotrochoid is traced by a point attached to a circle of radius $r$ rolling around the inside of a fixed circle of radius $R$, where the point is a distance $d$ from the center of the interior circle.

$$x(\theta) = (R - r)\cos\theta + d\cos\left(\frac{R-r}{r}\theta\right)$$

$$y(\theta) = (R - r)\sin\theta - d\sin\left(\frac{R-r}{r}\theta\right)$$

An epitrochoid is traced by a point attached to a circle of radius $r$ rolling around the outside of a fixed circle of radius $R$, where the point is a distance $d$ from the center of the exterior circle.

$$x(\theta) = (R + r)\cos\theta - d\cos\left(\frac{R+r}{r}\theta\right)$$

$$y(\theta) = (R + r)\sin\theta - d\sin\left(\frac{R+r}{r}\theta\right)$$"""
end

"""Describe the classical curve families and constructions in this collection."""
function get_search_content()
    return SearchContent(
        """Curves
Here, we explore various kinds of curves in geometry.
Many curves are drawn as roulette curves, with one shape rolling along another. Many of these are types of trochoids. A trochoid is formed by a circle rolling along a line, which may itself be curved or straight.
A cycloid is the curve traced by a point relative to a circle as it rolls along a straight line without slipping.
Assume the line is the x-axis and we have a circle with radius r.
Let d be the distance from the center of the circle to a point P that rolls with the circle,
and we trace P as it rolls with the circle. This gives us the formulas for the cycloid.
Hypotrochoids and epitrochoids are formed by tracing a point relative to a circle as it rolls along another circle.
A hypotrochoid is traced by a point attached to a circle of radius r rolling around the inside of a fixed circle of radius R, where the point is a distance d from the center of the interior circle.
An epitrochoid is traced by a point attached to a circle of radius r rolling around the outside of a fixed circle of radius R, where the point is a distance d from the center of the exterior circle.""",
        ("plane curves", "roulette curves", "rolling curves"))
end

end
