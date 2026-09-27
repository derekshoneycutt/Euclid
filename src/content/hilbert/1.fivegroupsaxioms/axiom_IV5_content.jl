module HilbertChapterOneAxiomIV5Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom IV,5."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom IV,5}

\textbf{IV, 5.} If the angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] is
congruent to the angle $(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] and to
the angle $(h'', k'')$ \euclidangle[color=khaki3,radius=2,end=60,filled], then the angle
$(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] is congruent to the angle
$(h'', k'')$ \euclidangle[color=khaki3,radius=2,end=60,filled]; that is to say, if
$\angle(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] $\equiv \angle(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled]
and $\angle(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] $\equiv \angle(h'', k'')$ \euclidangle[color=khaki3,radius=2,end=60,filled],
then $\angle(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] $\equiv \angle(h'', k'')$ \euclidangle[color=khaki3,radius=2,end=60,filled]."""
end

"""Describe transitivity among angles congruent to one angle."""
function get_search_content()
    return SearchContent(
        "Axiom IV,5 states that two angles congruent to the same angle are congruent to " *
        "one another.",
        ("angle congruence transitivity", "same angle equality", "congruent angles"))
end

end
