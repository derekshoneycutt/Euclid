module HilbertChapterOneCongruenceContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for §6 Group IV: Axioms of Congruence."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§6 Group IV: Axioms of Congruence}

The axioms of this group define the idea of congruence or displacement.

Segments stand in a certain relation to one another which is described by the word "congruent."

...

Axioms IV, 1-3 contain statements concerning the congruence of segments of a straight line only. They may, therefore, be called the linear axioms of group IV. Axioms IV, 4, 5 contain statements relating to the congruence of angles. Axiom IV, 6 gives the connection between the congruence of segments and the congruence of angles. Axioms IV, 4-6 contain statements regarding the elements of plane geometry and may be called the plane axioms of group IV."""
end

"""Describe Hilbert's segment and angle congruence axioms."""
function get_search_content()
    return SearchContent(
        "The axioms of congruence define congruent segments and angles, with linear " *
        "axioms for segments and plane axioms connecting segment and angle congruence.",
        ("congruent segments and angles", "displacement", "linear and plane congruence"))
end

end
