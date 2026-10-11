module EuclidAlgebraGroupsCnAbelianContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Abelian."""
function get_view_content()
    return tex"""\textbf{Abelian Groups / Commutativity}

An abelian group is one where order does not matter: doing one allowed rotation and then another gives the same result as doing them in the reverse order.

For cyclic rotations about one center, order never changes the outcome.

\begin{enumerate}
\item $\rho^2\rho^4 = \rho^6$.
\item $\rho^4\rho^2 = \rho^6$.
\end{enumerate}

Order does not change the result, so this is a concrete visual proof that $C_n$ is abelian.

Formally, this is the statement $\rho^2\rho^4 = \rho^4\rho^2$."""
end

"""Describe commutativity in the cyclic rotation group."""
function get_search_content()
    return SearchContent(
        "An abelian group has a commutative operation, so changing operand order does " *
        "not change the result; rotations in Cₙ commute.",
        ("abelian group", "commutative operation", "order does not matter", "commutativity"))
end

end
