module HilbertChapterOneDefCongruentAnglesContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definition: Congruent Angles."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Congruent Angles}

Let the angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] be congruent to the angle $(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled].
Since, according to \textit{axiom IV, 4}, the angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled]
is congruent to itself, it follows from \textit{axiom IV, 5} that the angle
$(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] is congruent to the angle
$(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled]. We say, then, that the angles
$(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] and $(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] are congruent to one another."""
end

"""Describe mutual congruence between a pair of angles."""
function get_search_content()
    return SearchContent(
        "Two angles are congruent to one another when their congruence relation holds in " *
        "both directions, following the angle congruence axioms.",
        ("mutually congruent angles", "symmetric angle congruence", "equal angles"))
end

end
