module HilbertChapterOneAxiomIV6Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom IV,6."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom IV,6}

\textbf{IV, 6.} If, in the two triangles $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3]
and $A'B'C'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=grey60,edge3_color=palevioletred1]
the congruences $AB$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A'B'$ \euclidline[color=grey60,length=3,thickness=4],
$AC$ \euclidline[color=palevioletred1,length=3,thickness=4] $\equiv A'C'$ \euclidline[color=steelblue,length=3,thickness=4],
$\angle BAC$ \euclidangle[color=khaki3,radius=2,end=60,filled] $\equiv \angle B'A'C'$ \euclidangle[color=khaki3,radius=2,end=60,filled] hold,
then the congruences $\angle ABC$ \euclidangle[color=lightgreen,radius=2,end=60,filled] $\equiv \angle A'B'C'$ \euclidangle[color=lightgreen,radius=2,end=60,filled]
and $\angle ACB$ \euclidangle[color=lightgreen,radius=2,end=60,filled] $\equiv \angle A'C'B'$ \euclidangle[color=lightgreen,radius=2,end=60,filled] also hold."""
end

"""Describe the angle consequences of two congruent sides and included angle."""
function get_search_content()
    return SearchContent(
        "Axiom IV,6 states that triangles with two corresponding sides and their " *
        "included angles congruent also have their remaining corresponding angles congruent.",
        ("side angle side", "SAS congruence", "remaining triangle angles"))
end

end
