module EuclidCurvesCurtateCycloidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Curtate Cycloid."""
function get_view_content()
    return tex"""\textbf{Curtate Cycloid}

The curtate cycloid is produced by tracing a point $P$ that lies inside a circle, such that its distance $d<r$ where $r$ is the radius of the circle, as it rolls along a straight line without slipping.

$P$ will not make contact with the straight line, leaving round, dimples but no cusps.

$$x(\theta) = r\theta - d\sin\theta$$

$$y(\theta) = r - d\cos\theta$$"""
end

"""Describe the smooth path traced inside a rolling circle."""
function get_search_content()
    return SearchContent(
        """Curtate Cycloid
The curtate cycloid is produced by tracing a point P that lies inside a circle, such that its distance  where r is the radius of the circle, as it rolls along a straight line without slipping.
P will not make contact with the straight line, leaving round, dimples but no cusps.""",
        ("shortened cycloid", "tracer inside rolling circle", "smooth cycloid"))
end

end
