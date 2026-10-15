module EuclidCurvesCycloidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Cycloid."""
function get_view_content()
    return tex"""\textbf{Cycloid}

The standard cycloid is produced by tracing a point $P$ on a circle as it rolls along a straight line without slipping.

Each point where $P$ contacts the straight line forms a cusp.

Where $r$ is the radius of the circle and $d$ is the distance of $P$ from the center of the circle, then $r=d$.

$$x(\theta) = r(\theta - \sin\theta)$$

$$y(\theta) = r(1 - \cos\theta)$$"""
end

"""Describe the rim-traced cusps of an ordinary cycloid."""
function get_search_content()
    return SearchContent(
        """Cycloid
The standard cycloid is produced by tracing a point P on a circle as it rolls along a straight line without slipping.
Each point where P contacts the straight line forms a cusp.
Where r is the radius of the circle and d is the distance of P from the center of the circle, then .""",
        ("rolling circle", "wheel curve", "cusped roulette"))
end

end
