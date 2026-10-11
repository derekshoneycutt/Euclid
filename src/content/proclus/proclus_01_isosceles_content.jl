module ElementsOneProclusIsoscelesContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Isosceles Triangle."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Proclus - Isosceles Triangle}

On a given finite straight line to construct an isosceles triangle.

\textit{This follows Euclid's Elements Book I, Proposition I, with modifications.}

To make an isosceles triangle he produces $AB$ \euclidline[color=grey60,length=3,thickness=4] in both
directions to meet the respective circles in $D$ \euclidcircle[color=khaki3,size=1,thickness=2],
$E$ \euclidcircle[color=steelblue,size=1,thickness=2] and then describes circles with
$A$ \euclidcircle[color=palevioletred1,size=1,thickness=2],
$B$ \euclidcircle[color=grey60,size=1,thickness=2] as centers and
$AE$ \euclidline[color=grey60,length=3,thickness=4],
$BD$ \euclidline[color=grey60,length=3,thickness=4] as radii respectively.
The result is an isosceles triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=grey60,edge3_color=steelblue] with each of two sides double of the third side."""
end

"""Describe Proclus's construction of an isosceles triangle with doubled sides."""
function get_search_content()
    return SearchContent(
        "Proclus constructs an isosceles triangle on a given segment using circles, " *
        "with two equal sides each twice the length of the third side.",
        ("two equal sides", "twice the base", "Proclus construction", "modified Proposition I"))
end

end
