module EuclidCurvesEllipseContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Ellipse."""
function get_view_content()
    return tex"""\textbf{Ellipse}

An ellipse \euclidcircle[color=steelblue,size=1,thickness=2] is a plane curve surrounding two focal points, such that for all points on the curve, the sum of both distances to the two focal points is a constant.

The ellipse is a special case of the hypotrochoid when $R = 2r$, drawn as such here. If $d=0$, the ellipse becomes the circle of radius $R$. If $d=r$ the ellipse becomes a straight line length $2R$.

$$x(\theta) = (2r - r)\cos\theta + d\cos\left(\frac{2r-r}{r}\theta\right) = (r+d)\cos\theta$$

$$y(\theta) = (2r - r)\sin\theta - d\sin\left(\frac{2r-r}{r}\theta\right) = (r-d)\sin\theta$$"""
end

"""Describe the focal definition and internal rolling construction of an ellipse."""
function get_search_content()
    return SearchContent(
        """Ellipse
An ellipse is a plane curve surrounding two focal points, such that for all points on the curve, the sum of both distances to the two focal points is a constant.
The ellipse is a special case of the hypotrochoid when drawn as such here. If zero the ellipse becomes the circle of radius. If equal the ellipse becomes a straight line length diameter.""",
        ("two foci", "constant distance sum", "internal rolling", "oval", "hypotrochoid"))
end

end
