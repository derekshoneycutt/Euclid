module EuclidAlgebraGroupsZ2InverseContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

const InverseLatexDocument = raw"""\textbf{Inverse}

An inverse is the motion that undoes a given motion. In $\mathbb{Z}_2$, every element is its own inverse. That means each motion undoes itself when applied again. This is common for reflections across a stable line.

For an element $a$ in a group, an inverse $a^{-1}$ is an element such that
$a \circ a^{-1} = a^{-1} \circ a = e$, where $e$ is the identity.

\begin{enumerate}
\item $e^{-1} = e$: doing nothing undoes itself.
\item $r^{-1} = r$: one reflection undoes itself because reflecting twice gives back the original figure.
\end{enumerate}"""

"""Return canonical explanatory content for Inverse."""
function get_view_content()
    return EuclidLatex.TeXDocument(InverseLatexDocument)
end

"""Describe inverse elements through self-inverse reflections."""
function get_search_content()
    return SearchContent(
        "An inverse undoes a group element so their composition is the identity; in ℤ₂, " *
        "identity and reflection are each self-inverse.",
        ("inverse element", "undo motion", "self-inverse reflection", "involution"))
end

end
