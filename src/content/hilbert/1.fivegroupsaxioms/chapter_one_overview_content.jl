module HilbertChapterOneOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for 1. The Five Groups of Axioms, §1."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§1 The Elements of Geometry and the Five Groups of Axioms}
    
Let us consider three distinct systems of things. The things composing the first system, we will call points and designate them by the letters $A, B, C, ...$ ; those of the second, we will call straight lines and designate them by the letters $a, b, c, ...$; and those of the third system, we will call planes and designate them by the Greek letters $\alpha, \beta, \gamma, ...$ The points are called the elements of linear geometry; the points and straight lines, the elements of plane geometry; and the points, lines, and planes, the elements of the geometry of space or the elements of space.

We think of these points, straight lines, and planes as having certain mutual relations, which we indicate by means of such words as "are situated," "between," "parallel," "congruent," "continuous," etc. The complete and exact description of these relations follows as a consequence of the axioms of geometry. These axioms may be arranged in five groups. Each of these groups expresses, by itself, certain related fundamental facts of our intuition. We will name these groups as follows:

\textbf{I, 1-7.} Axioms of \textit{connection}.\\
\textbf{II, 1-5.} Axioms of \textit{order}.\\
\textbf{III.} Axiom of \textit{parallels (Euclid's axiom)}.\\
\textbf{IV, 1-6.} Axioms of \textit{congruence}.\\
\textbf{V.} Axiom of \textit{continuity (Archimedes's axiom)}."""
end

"""Describe Hilbert's geometric elements and five groups of axioms."""
function get_search_content()
    return SearchContent(
        "Hilbert begins with points, straight lines, and planes, then groups their mutual " *
        "relations into connection, order, parallels, congruence, and continuity.",
        ("five groups of axioms", "elements of geometry", "points lines planes"))
end

end
