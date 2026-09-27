module HilbertChapterOneAxiomIV2Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom IV,2."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom IV,2}

\textbf{IV, 2.} If a segment $AB$ \euclidline[color=steelblue,length=3,thickness=4] is
congruent to the segment $A'B'$ \euclidline[color=palevioletred1,length=3,thickness=4] and
also to the segment $A''B''$ \euclidline[color=khaki3,length=3,thickness=4], then the
segment $A'B'$ \euclidline[color=palevioletred1,length=3,thickness=4] is congruent to the
segment $A''B''$ \euclidline[color=khaki3,length=3,thickness=4]; that is, if
$AB$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A'B'$ \euclidline[color=palevioletred1,length=3,thickness=4]
and $AB$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A''B''$ \euclidline[color=khaki3,length=3,thickness=4],
then $A'B'$ \euclidline[color=palevioletred1,length=3,thickness=4] $\equiv A''B''$ \euclidline[color=khaki3,length=3,thickness=4]."""
end

"""Describe transitivity among segments congruent to one segment."""
function get_search_content()
    return SearchContent(
        "Axiom IV,2 states that two segments congruent to the same segment are congruent " *
        "to one another.",
        ("segment congruence transitivity", "same segment equality", "congruent lengths"))
end

end
