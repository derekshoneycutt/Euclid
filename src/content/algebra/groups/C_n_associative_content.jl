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
\item Both paths match because function composition is associative.
\end{enumerate}

The side-by-side circles make grouping visible while the endpoint confirms equality.
Formally, the same final motion appears no matter how the three actions are grouped."""
end

"""Describe associativity through two groupings of three rotations."""
function get_search_content()
    return SearchContent(
        "Associativity means regrouping three operations does not change their result; " *
        "the same rotations agree under left and right parenthesization.",
        ("associative operation", "grouping does not matter", "bracketing invariant"))
end

end
