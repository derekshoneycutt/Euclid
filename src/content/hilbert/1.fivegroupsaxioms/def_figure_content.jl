module HilbertChapterOneDefinitionFigureContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definition: Figure."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Figure}

Any finite number of points is called a figure \euclidtriangle[color=steelblue,height=2,width=3,filled]. If all the points lie in a plane, the figure is called a plane figure.

Two figures are said to be congruent if their points can be arranged in a one-to-one correspondence so that the corresponding segments and the corresponding angles of the two figures are in every case congruent to each other.

Congruent figures have, as may be seen from \textit{theorems 9} and \textit{12}, the following properties. Three points of a figure lying in a straight line are likewise in a straight line in every figure congruent to it. In congruent figures, the arrangement of the points in corresponding planes with respect to corresponding lines is always the same. The same is true of the sequence of corresponding points situated on corresponding lines."""
end

"""Describe Hilbert's finite point figures and their congruence."""
function get_search_content()
    return SearchContent(
        "Hilbert calls any finite set of points a figure and defines congruent figures by " *
        "a one-to-one correspondence preserving segments and angles.",
        ("finite point figure", "plane figure", "one-to-one congruent figures"))
end

end
