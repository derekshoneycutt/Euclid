module EuclidAlgebraGroupsZ2IdentityContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

const IdentityLatexDocument = raw"""\textbf{Identity}

Identity means there is a motion that changes nothing at all.

In this model, that is the \textit{do-nothing} motion $e$.

\begin{enumerate}
\item $e \circ r = r$: doing nothing before reflection changes nothing.
\item $r \circ e = r$: doing nothing after reflection changes nothing.
\item The visual cue $r \circ r = e$ also reinforces that returning to start is a valid identity outcome.
\end{enumerate}

Formally, this means $e \circ a = a \circ e = a$ for every allowed motion $a$."""

"""Return canonical explanatory content for Identity."""
function get_view_content()
    return EuclidLatex.TeXDocument(IdentityLatexDocument)
end

"""Describe the do-nothing identity motion in the reflection group."""
function get_search_content()
    return SearchContent(
        "The identity is the unique group element that leaves every motion unchanged " *
        "when composed on either side, represented here by doing nothing.",
        ("identity element", "neutral element", "do-nothing motion", "no-op"))
end

end
