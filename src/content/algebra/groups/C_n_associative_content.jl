module EuclidAlgebraGroupsCnAssociativeContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Associative."""
function get_view_content()
    return tex"""\textbf{Associativity}

Associativity means the grouping of the operation does not matter:

$$(a \circ b) \circ c = a \circ (b \circ c)\; \text{for all}\; a,b,c$$

Here, compare the two ways of grouping the same three rotations.

\begin{enumerate}
\item Left grouping: $(\rho^1\rho^2)\rho^3 = \rho^6$.
\item Right grouping: $\rho^1(\rho^2\rho^3) = \rho^6$.
\end{enumerate}

Both paths match because function composition is associative."""
end

"""Describe associativity through two groupings of three rotations."""
function get_search_content()
    return SearchContent(
        """Associativity

Associativity means the grouping of the operation does not matter:

Here, compare the two ways of grouping the same three rotations.

Left grouping
Right grouping

Both paths match because function composition is associative.""",
        ("associative operation", "grouping does not matter", "bracketing invariant"))
end

end
