module EuclidCurvesLimaconContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Limaçon."""
function get_view_content()
    return tex"""\textbf{Limaçon}

A limaçon is traced by a point $P$ carried by a circle rolling around another circle of equal radius.

For the fixed circle with radius $R$ and the rolling circle with radius $r$, $R=r$.
When the distance $d$ between the point $P$ and the center of the rolling circle is greater than the radius $r$ of the rolling circle, $d>r$, an inner loop is produced.

$$x(\theta) = 2r\cos\theta - d\cos\left(2\theta\right)$$

$$y(\theta) = 2r\sin\theta - d\sin\left(2\theta\right)$$"""
end

"""Describe the extended tracer and inner loop of this limaçon."""
function get_search_content()
    return SearchContent(
        """Limaçon
A limaçon is traced by a point P carried by a circle rolling around another circle of equal radius.
For the fixed circle with radius R and the rolling circle with radius r, R=r.
When the distance d between the point P and the center of the rolling circle is greater than the radius r of the rolling circle, , an inner loop is produced.""",
        ("Pascal's limaçon", "limacon", "snail curve", "inner-loop curve"))
end

end
