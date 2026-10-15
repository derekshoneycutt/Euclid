module EuclidCurvesCardioidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Cardioid."""
function get_view_content()
    return tex"""\textbf{Cardioid}

A cardioid (from Greek καρδιά (kardiá) 'heart') is an epithrochoid traced by a point $P$ on the perimeter of a circle that is rolling around another fixed circle of the same radius.

A cardioid is also a limaçon such that the distance between the point $P$ and the radius of the rolling circle are equal.

For the fixed circle with radius $R$ and the rolling circle with radius $r$, $R=r$.
Likewise, the distance between the center of the rolling circle and the point $P$, $d=r=R$.

$$x(\theta) = r\left(2\cos\theta - \cos\left(2\theta\right)\right)$$

$$y(\theta) = r\left(2\sin\theta - \sin\left(2\theta\right)\right)$$"""
end

"""Describe the equal-circle construction and single cusp of a cardioid."""
function get_search_content()
    return SearchContent(
        """Cardioid
A cardioid (from Greek καρδιά (kardiá) 'heart') is an epithrochoid traced by a point P on the perimeter of a circle that is rolling around another fixed circle of the same radius.
A cardioid is also a limaçon such that the distance between the point P and the radius of the rolling circle are equal.
For the fixed circle with radius R and the rolling circle with radius r, .
Likewise, the distance between the center of the rolling circle and the point P,.""",
        ("heart-shaped curve", "one-cusped epicycloid", "equal rolling circles"))
end

end
