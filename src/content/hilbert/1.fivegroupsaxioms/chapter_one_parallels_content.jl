module HilbertChapterOneParallelsContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for §5 Group III: Axiom of Parallels."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - 1. The Five Groups of Axioms} \textit{§5 Group III: Axiom of Parallels (Euclid's Axiom)}

The introduction of this axiom simplifies greatly the fundamental principles of geometry and facilitates in no small degree its development.

...

The axiom of parallels is a plane axiom."""
end

"""Describe Hilbert's plane axiom of parallels inherited from Euclid."""
function get_search_content()
    return SearchContent(
        "Hilbert's Group III introduces Euclid's axiom of parallels as a plane axiom " *
        "that simplifies the foundations and development of geometry.",
        ("parallel postulate", "Euclid's axiom", "plane axiom of parallels"))
end

end
