module EuclidCurvesThreeDimpleEpitrochoidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for 3-Dimple Epitrochoid."""
function get_view_content()
    return tex"""\textbf{3-Dimple Epitrochoid}

A 3-dimpled epitrochoid is created by tracing a point $P$ inside a circle that is rolling around the outside of a static circle,
where the outer rolling circle is $\frac{1}{3}$ the size of the static circle, and the distance
between the point $P$ and the center of the rolling circle is $\frac{1}{2}$ the radius of the
rolling circle.

That is, $R = 3r$ and $r = 2d$.

$$x(\theta) = 4r\cos\theta - \frac{r}{2}\cos\left(4\theta\right)$$

$$y(\theta) = 4r\sin\theta - \frac{r}{2}\sin\left(4\theta\right)$$"""
end

"""Describe the external rolling construction of this three-dimple epitrochoid."""
function get_search_content()
    return SearchContent(
        """3-Dimple Epitrochoid
A 3-dimpled epitrochoid is created by tracing a point P inside a circle that is rolling around the outside of a static circle,
where the outer rolling circle is 1/3 the size of the static circle, and the distance
between the point P and the center of the rolling circle is 1/2 the radius of the
rolling circle.
That is, R = 3r and r = 2d.""",
        ("three-lobed epitrochoid", "three-dimple roulette", "external trochoid"))
end

end
