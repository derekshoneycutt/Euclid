module EuclidAlgebraGroupsZ2ClosureContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

const ClosureLatexDocument = raw"""\textbf{Closure}

Closure means that when you perform one allowed motion after another, that is composing the motions, the result of the two together represents one of the allowed motions in the group.

In this example, composing reflections still produces one of the same allowed motions:

\begin{enumerate}
\item One reflection maps the figure to its mirror image, still in the same state space.
\item Two reflections across the same axis return to the original state.
\item Any allowed composition remains one of the 2 allowed motions: $e$ or $r$.
\end{enumerate}

So the geometry never leaves the symmetry you started with; the formal closure axiom just records that fact."""

"""Return canonical explanatory content for Closure."""
function get_view_content()
    return EuclidLatex.TeXDocument(ClosureLatexDocument)
end

"""Describe closure under composition in the two-element symmetry group."""
function get_search_content()
    return SearchContent(
        "Closure requires the composition of any two group elements to remain in the " *
        "group; composing identity and reflection always yields identity or reflection.",
        ("closure axiom", "closed binary operation", "composition stays in group"))
end

end
