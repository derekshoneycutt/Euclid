module ElementsOneProposition01Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Proposition I."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Proposition I}

\textit{On a given finite straight line to construct an equilateral triangle.}

Let $AB$ \euclidline[color=grey60,length=3,thickness=4] be the given finite straight line.

Thus it is required to construct an equilateral triangle on the straight line $AB$.\\
With center $A$ and distance $AB$ let the circle $BCD$ \euclidcircle[color=steelblue,size=1,thickness=2] be described;\\
again, with center $B$ and distance $BA$ let the circle $ACE$ \euclidcircle[color=palevioletred1,size=1,thickness=2] be described;\\
and from the point $C$, in which the circles cut one another, to the points $A$, $B$ let the straight lines $CA$ \euclidline[color=khaki3,length=3,thickness=4], $CB$ \euclidline[color=palevioletred1,length=3,thickness=4] be joined.

Now, since the point $A$ is the center of the circle $CDB$ \euclidcircle[color=steelblue,size=1,thickness=2], $AC$ \euclidline[color=khaki3,length=3,thickness=4] is equal to $AB$ \euclidline[color=grey60,length=3,thickness=4].\\
Again, since the point B is the center of the circle $CAE$ \euclidcircle[color=palevioletred1,size=1,thickness=2], $BC$ \euclidline[color=palevioletred1,length=3,thickness=4] is equal to $BA$ \euclidline[color=grey60,length=3,thickness=4].\\
But $CA$ \euclidline[color=khaki3,length=3,thickness=4] was also proved equal to $AB$ \euclidline[color=grey60,length=3,thickness=4]; therefore each of the straight lines $CA$ \euclidline[color=khaki3,length=3,thickness=4], $CB$ \euclidline[color=palevioletred1,length=3,thickness=4] is equal to $AB$ \euclidline[color=grey60,length=3,thickness=4].\\
And things which are equal to the same thing are also equal to one another; therefore $CA$ \euclidline[color=khaki3,length=3,thickness=4] is also equal to $CB$ \euclidline[color=palevioletred1,length=3,thickness=4].\\
Therefore the three straight lines $CA$ \euclidline[color=khaki3,length=3,thickness=4], $AB$ \euclidline[color=grey60,length=3,thickness=4], $BC$ \euclidline[color=palevioletred1,length=3,thickness=4] are equal to one another.\\
Therefore the triangle $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=khaki3,edge2_color=grey60,edge3_color=palevioletred1] is equilateral; and it has been constructed on the given finite straight line $AB$ \euclidline[color=grey60,length=3,thickness=4].

Being what it was required to do."""
end

"""Describe Proposition I's equilateral-triangle construction."""
function get_search_content()
    return SearchContent(
        "Proposition I constructs an equilateral triangle on a given finite straight " *
        "line using two circles centered at its endpoints and their intersection.",
        ("construct equilateral triangle", "two intersecting circles", "triangle on given line"))
end

end
