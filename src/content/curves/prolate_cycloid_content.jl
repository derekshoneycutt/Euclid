module EuclidCurvesProlateCycloidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Prolate Cycloid."""
function get_view_content()
    return tex"""\textbf{Prolate Cycloid}

The prolate cycloid is produced by tracing a point $P$ that lies outside a circle, such that its distance $d>r$ where $r$ is the radius of the circle, as it rolls along a straight line without slipping.

$P$ will cross over the straight line, producing loops over the line, but no cusps.

$$x(\theta) = r\theta - d\sin\theta$$

$$y(\theta) = r - d\cos\theta$$"""
end

"""Describe the looped path traced outside a rolling circle."""
function get_search_content()
    return SearchContent(
        """Prolate Cycloid
The prolate cycloid is produced by tracing a point P that lies outside a circle, such that its distance d>r where r is the radius of the circle, as it rolls along a straight line without slipping.
P will cross over the straight line, producing loops over the line, but no cusps.""",
        ("extended cycloid", "tracer outside rolling circle", "looped cycloid"))
end

end
