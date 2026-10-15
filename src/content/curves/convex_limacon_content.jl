module EuclidCurvesConvexLimaconContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Convex Limaçon."""
function get_view_content()
    return tex"""\textbf{Convex Limaçon}

A limaçon is traced by a point $P$, not equal to the center, carried by a circle rolling around another circle of equal radius.

For the fixed circle with radius $R$ and the rolling circle with radius $r$, $R=r$.
When twice the distance $d$ between the point $P$ and the center of the rolling circle is less than or equal to the radius of the circles, $2d\leq r$, only a slightly flattened curve is created, without a dimple, loop, or cusp.

$$x(\theta) = 2r\cos\theta - d\cos\left(2\theta\right)$$

$$y(\theta) = 2r\sin\theta - d\sin\left(2\theta\right)$$"""
end

"""Describe the near-center tracer that produces a convex limaçon."""
function get_search_content()
    return SearchContent(
        """Convex Limaçon
A limaçon is traced by a point P, not equal to the center, carried by a circle rolling around another circle of equal radius.
For the fixed circle with radius R and the rolling circle with radius r, .
When twice the distance d between the point P and the center of the rolling circle is less than or equal to the radius of the circles, , only a slightly flattened curve is created, without a dimple, loop, or cusp.""",
        ("convex limacon", "unindented limaçon", "outward-bending curve"))
end

end
