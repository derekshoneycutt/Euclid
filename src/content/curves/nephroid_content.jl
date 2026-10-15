module EuclidCurvesNephroidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Nephroid."""
function get_view_content()
    return tex"""\textbf{Nephroid}

A Nephroid is the two-cusped epitrochoid traced by a point on a circle rolling around another fixed circle with twice its radius. That is, $R=2r$ and $d=r$.

$$x(\theta) = 3r\cos\theta - r\cos\left(3\theta\right)$$

$$y(\theta) = 3r\sin\theta - r\sin\left(3\theta\right)$$"""
end

"""Describe the two-cusped epicycloid called a nephroid."""
function get_search_content()
    return SearchContent(
        """Nephroid
A Nephroid is the two-cusped epitrochoid traced by a point on a circle rolling around another fixed circle with twice its radius. That is, R=2r and d=r.""",
        ("two-cusped epicycloid", "two-cusped epitrochoid", "kidney-shaped curve", "external rolling curve"))
end

end
