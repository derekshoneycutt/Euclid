module ElementsOneProclusScaleneContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Scalene Triangle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Proclus - Scalene Triangle}

On a given finite straight line to construct a scalene triangle.

\textit{This follows Euclid's Elements Book I, Proposition I, with modifications.}

Suppose $AC$ \euclidline[color=palevioletred1,length=3,thickness=4] to be a radius of one of the
two circles \euclidcircle[color=steelblue,size=1,thickness=2], and
$D$ \euclidpoint[color=palevioletred1,size=0.5] a point on $AC$ \euclidline[color=palevioletred1,length=3,thickness=4]
lying in that portion of the circle with center $A$ \euclidpoint[color=grey60,size=0.5] which is outside the
circle \euclidcircle[color=palevioletred1,size=1,thickness=2] with
center $B$ \euclidpoint[color=grey,size=0.5]. Then, joining
$BD$ \euclidline[color=khaki3,length=3,thickness=4] as in the figure, we have a triangle which obviously has all its sides unequal, that is,
a scalene triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=grey60,edge3_color=khaki3]."""
end

"""Describe Proclus's circle construction of a scalene triangle."""
function get_search_content()
    return SearchContent(
        "Proclus constructs a scalene triangle with all three sides unequal by choosing " *
        "a point within one circle and outside another.",
        ("unequal sides", "three different sides", "Proclus construction", "modified Proposition I"))
end

end
