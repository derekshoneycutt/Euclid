module HilbertOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Hilbert's Foundations of Geometry."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry} ; Translated by E. J. Townsend
    
\textit{"All human knowledge begins with intuitions, thence passes to concepts and ends with ideas."}\\
\textit{Kant, Critique of Pure Reason}

Geometry, like arithmetic, requires for its logical development only a small number of simple, fundamental principles. These fundamental principles are called the axioms of geometry. The choice of the axioms and the investigation of their relations to one another is a problem which, since the time of Euclid, has been discussed in numerous excellent memoirs to be found in the mathematical literature. This problem is tantamount to the logical analysis of our intuition of space.
The following investigation is a new attempt to choose for geometry a simple and complete set of independent axioms and to deduce from these the most important geometrical theorems in such a manner as to bring out as clearly as possible the significance of the different groups of axioms and the scope of the conclusions to be derived from the individual axioms."""
end

"""Describe Hilbert's axiomatic analysis of geometry and spatial intuition."""
function get_search_content()
    return SearchContent(
        "Hilbert's Foundations of Geometry develops geometry from a simple, complete, " *
        "and independent set of axioms while examining the relations among axiom groups.",
        ("axiomatic geometry", "logical analysis of space", "independent axioms"))
end

end
