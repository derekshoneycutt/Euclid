module EuclidCurvesCircleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Circle."""
function get_view_content()
    return tex"""\textbf{Circle}

A circle \euclidcircle[color=steelblue,size=1,thickness=2] is a plane figure contained by one line such that all the straight lines falling upon it from one point among those lying within the figure equal one another.

With radius $r$, and center $(h, k)$, we draw the circle with a compass.

$$x(\theta) = h + r\cos\theta$$

$$y(\theta) = k + r\cos\theta$$"""
end

"""Describe the constant-radius locus and compass construction of a circle."""
function get_search_content()
    return SearchContent(
        """Circle
A circle is a plane figure contained by one line such that all the straight lines falling upon it from one point among those lying within the figure equal one another.
With radius r, and center , we draw the circle with a compass.""",
        ("compass construction", "constant radius", "equidistant points"))
end

end
