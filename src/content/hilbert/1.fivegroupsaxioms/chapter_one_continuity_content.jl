module HilbertChapterOneContinuityContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for §8 Group V: Axiom of Continuity."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§8 Group V. Axiom of Continuity. (Archimedean Axiom.)}

This axiom makes possible the introduction into geometry of the idea of continuity. In order to state this axiom, we must first establish a convention concerning the equality of two segments. For this purpose, we can either base our idea of equality upon the axioms relating to the congruence of segments and define as "equal" the correspondingly congruent segments, or, upon the basis of groups I and II, we may determine how, by suitable constructions (see Chap. V, Section 24), a segment is to be laid off from a point of a given straight line so that a new, definite segment is obtained "equal" to it. In conformity with such a convention, the axiom of Archimedes may be stated as follows.

The axiom of Archimedes is a linear axiom.

...

Remark. To the preceding five groups of axioms, we may add the axiom of completeness, which, although not of a purely geometrical nature, merits particular attention from a theoretical point of view."""
end

"""Describe Hilbert's Archimedean continuity axiom and completeness remark."""
function get_search_content()
    return SearchContent(
        "Hilbert's Group V introduces continuity through the linear axiom of Archimedes " *
        "and discusses adding an axiom of completeness to the five groups.",
        ("Archimedean axiom", "axiom of continuity", "axiom of completeness"))
end

end
