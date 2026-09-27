module HilbertChapterOneTheorem15Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 15."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 15}

All right angles are congruent to one another.

\textbf{Proof}: Let the angle $\angle BAD$ be congruent to its supplementary angle $\angle CAD$
\euclidangle[color=lightgreen,radius=2,start=90,end=180]\euclidangle[color=lightgreen,radius=2,end=90], and, likewise,
let the angle $\angle B'A'D'$ be congruent to its supplementary angle $\angle C'A'D'$
\euclidangle[color=lightgreen,radius=2,start=90,end=180]\euclidangle[color=lightgreen,radius=2,end=90].
Hence the angles $\angle BAD$ \euclidangle[color=lightgreen,radius=2,start=90,end=180], $\angle CAD$ \euclidangle[color=lightgreen,radius=2,end=90],
$\angle B'A'D'$ \euclidangle[color=lightgreen,radius=2,start=90,end=180], and $\angle C'A'D'$ \euclidangle[color=lightgreen,radius=2,end=90] are all right angles.
We will assume that the contrary of our proposition is true, namely, that the right angle
$\angle B'A'D'$ \euclidangle[color=lightgreen,radius=2,start=90,end=180] is not congruent to the right angle
$\angle BAD$ \euclidangle[color=lightgreen,radius=2,end=90], and will show that this assumption leads to a contradiction.
We lay off the angle $\angle B'A'D'$ upon the half-ray $AB$ \euclidline[color=steelblue,length=3,thickness=4] in such a
manner that the side $AD''$ \euclidline[color=firebrick,length=3,thickness=4] arising from this operation falls either
within the angle $\angle BAD$ or within the angle $\angle CAD$. Suppose, for example, the first of these possibilities
to be true. Because of the congruence of the angles $\angle B'A'D'$ and $\angle BAD''$, it follows from
\textit{theorem 12} that angle $\angle C'A'D'$ is congruent to angle $\angle CAD''$, and, as the angles
$\angle B'A'D'$ and $\angle C'A'D'$ are congruent to each other, then, by \textit{IV, 5}, the angle $\angle BAD''$
must be congruent to $\angle CAD''$.

Furthermore, since the angle $\angle BAD$ is congruent to the angle $\angle CAD$, it is possible, by \textit{theorem 13},
to find within the angle $\angle CAD$ a half-ray $AD'''$ \euclidline[color=firebrick,length=3,thickness=4] emanating
from $A$ \euclidpoint[color=plum1,size=0.5], so that the angle $\angle BAD''$ will be congruent to the angle
$\angle CAD'''$, and also the angle $\angle DAD''$ will be congruent to the angle $\angle DAD'''$. The angle
$\angle BAD''$ was shown to be congruent to the angle $\angle CAD''$, and, hence, by \textit{axiom IV, 5}, the angle
$\angle CAD'''$ is congruent to the angle $\angle CAD''$. This, however, is not possible; for, according to
\textit{axiom IV, 4}, an angle can be laid off in a plane upon a given side of a given half-ray in only one way. With
this our proposition is demonstrated. We can now introduce, in accordance with common usage, the terms "acute angle" and "obtuse angle."""
end

"""Describe the congruence of all right angles."""
function get_search_content()
    return SearchContent(
        "Theorem 15 proves that all right angles, each congruent to its own supplement, " *
        "are congruent to one another.",
        ("all right angles congruent", "right angle equality", "angle and supplement"))
end

end
