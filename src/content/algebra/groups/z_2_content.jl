module EuclidAlgebraGroupsZ2Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

const Z2LatexDocument = raw"""\textbf{The two-element symmetry group}

Start with the simplest nontrivial geometry: given an equilateral triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=palevioletred1,edge3_color=khaki3], either \textit{do nothing} to the triangle, or \textit{reflect} it across one fixed axis.

The two motions composed result in an action inside the same collection, the do-nothing motion acts as identity, and each reflection motion undoes itself.

$$\mathbb{Z}_2 = \{0,1\}$$

This is the group under addition \textit{mod 2}. Let $r$ be reflection across the fixed axis and $e$ the identity motion.

$$e \circ e = e, \; e \circ r = r, \; r \circ e = r, \; r \circ r = e$$


Brief proof it is a group:

\begin{enumerate}
\item \textbf{Closure}: composing $e$ and $r$ always gives $e$ or $r$.
\item \textbf{Associativity}: composition of reflections is associative.
\item \textbf{Identity}: $e$ does nothing.
\item \textbf{Inverses}: $e$ and $r$ are their own inverses.
\end{enumerate}

So this is the 2-element symmetry group of the triangle, and the two motions commute."""

"""Return canonical explanatory content for ℤ₂."""
function get_view_content()
    return EuclidLatex.TeXDocument(Z2LatexDocument)
end

"""Describe the two-element reflection symmetry group."""
function get_search_content()
    return SearchContent(
        "The two-element group ℤ₂ models identity and reflection across a fixed axis; " *
        "each motion is self-inverse and their composition is abelian.",
        ("two-element group", "reflection symmetry", "Z mod 2", "involution"))
end

end
