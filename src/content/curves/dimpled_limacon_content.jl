module EuclidCurvesDimpledLimaconContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Dimpled Limaçon."""
function get_view_content()
    return tex"""\textbf{Dimpled Limaçon}

A limaçon is traced by a point $P$ carried by a circle rolling around another circle of equal radius.

For the fixed circle with radius $R$ and the rolling circle with radius $r$, $R=r$.
When the distance $d$ between the point $P$ and the center of the rolling circle is less than the radius $r$ of the rolling circle, $d<r$, only a dimple is produced, with no loop or cusp.

$$x(\theta) = 2r\cos\theta - d\cos\left(2\theta\right)$$

$$y(\theta) = 2r\sin\theta - d\sin\left(2\theta\right)$$"""
end

"""Describe the inward bend formed by this dimpled limaçon."""
function get_search_content()
    return SearchContent(
        """Dimpled Limaçon
A limaçon is traced by a point P carried by a circle rolling around another circle of equal radius.
For the fixed circle with radius R and the rolling circle with radius r,.
When the distance d between the point P and the center of the rolling circle is less than the radius r of the rolling circle, , only a dimple is produced, with no loop or cusp.""",
        ("dimpled limacon", "indented limaçon", "loopless limaçon"))
end

end
