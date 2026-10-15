module EuclidAlgebraGroupsZ2Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

const Z2LatexDocument = raw"""\textbf{The two-element symmetry group}

Given an equilateral triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=palevioletred1,edge3_color=khaki3], either \textit{do nothing} to the triangle, or \textit{reflect} it across one fixed axis.

This visually represents the two-element symmetry group, consisting of the identity (do-nothing) motion, and the reflection motion.
This is also the group under addition \textit{mod 2}. Formally:

$$\mathbb{Z}_2 = \{0,1\}$$

Let $r$ be the reflection motion and $e$ the identity motion. Then we can describe this group by its results as:

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
        """The two-element symmetry group ℤ₂
Given an equilateral triangle, either do nothing to the triangle, or reflect it across one fixed axis.
This visually represents the two-element symmetry group, consisting of the identity (do-nothing) motion, and the reflection motion.
This is also the group under addition mod 2. Formally:
Let r be the reflection motion and e the identity motion. Then we can describe this group by its results as:
Brief proof it is a group:
Closure: composing e and r always gives e or r.
Associativity: composition of reflections is associative.
Identity: e does nothing.
Inverses: e and r are their own inverses.
So this is the 2-element symmetry group of the triangle, and the two motions commute.""",
        ("two-element group", "reflection symmetry", "Z mod 2", "involution"))
end

end
