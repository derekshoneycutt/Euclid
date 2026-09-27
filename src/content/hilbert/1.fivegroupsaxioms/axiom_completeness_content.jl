module HilbertChapterOneAxiomCompletenessContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom of Completeness."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom of Completeness (Vollständigkeit)}

To a system of points, straight lines, and planes, it is impossible to add other elements in such a manner that the system thus generalized shall form a new geometry obeying all of the five groups of axioms. In other words, the elements of geometry form a system which is not susceptible of extension, if we regard the five groups of axioms as valid.

This axiom gives us nothing directly concerning the existence of limiting points, or of the idea of convergence. Nevertheless, it enables us to demonstrate Bolzano's theorem by virtue of which, for all sets of points situated upon a straight line between two definite points of the same line, there exists necessarily a point of condensation, that is to say, a limiting point. From a theoretical point of view, the value of this axiom is that it leads indirectly to the introduction of limiting points, and, hence, renders it possible to establish a one-to-one correspondence between the points of a segment and the system of real numbers. However, in what is to follow, no use will be made of the "axiom of completeness."
"""
end

"""Describe the non-extendability required by Hilbert's completeness axiom."""
function get_search_content()
    return SearchContent(
        "The axiom of completeness says that no points, lines, or planes can be added " *
        "while preserving all five axiom groups; the geometric system is not extendable.",
        ("nonextendable geometry", "maximal axiom system", "Vollständigkeit"))
end

end
