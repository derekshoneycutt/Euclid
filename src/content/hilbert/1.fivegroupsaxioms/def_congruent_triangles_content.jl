module HilbertChapterOneDefCongruentTrianglesContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definition: Congruent Triangles."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Congruent Triangles}

Two triangles $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3]
and $A'B'C'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=grey60,edge3_color=khaki3] are said to be congruent to one another when all of the following congruences are fulfilled:

    $AB$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A'B'$ \euclidline[color=grey60,length=3,thickness=4],    $AC$ \euclidline[color=palevioletred1,length=3,thickness=4] $\equiv A'C'$ \euclidline[color=steelblue,length=3,thickness=4],    $BC$ \euclidline[color=khaki3,length=3,thickness=4] $\equiv B'C'$ \euclidline[color=palevioletred1,length=3,thickness=4],\\
    $\angle A$ \euclidangle[color=lightgreen,radius=2,end=60,filled] $\equiv \angle A'$ \euclidangle[color=lightgreen,radius=2,end=60,filled],    $\angle B$ \euclidangle[color=lightgreen,radius=2,end=60,filled] $\equiv \angle B'$ \euclidangle[color=lightgreen,radius=2,end=60,filled],    $\angle C$ \euclidangle[color=lightgreen,radius=2,end=60,filled] $\equiv \angle C'$ \euclidangle[color=lightgreen,radius=2,end=60,filled]."""
end

"""Describe congruent triangles through all corresponding sides and angles."""
function get_search_content()
    return SearchContent(
        "Two triangles are congruent when all three pairs of corresponding sides and all " *
        "three pairs of corresponding angles are congruent.",
        ("six triangle congruences", "corresponding sides angles", "matching triangles"))
end

end
