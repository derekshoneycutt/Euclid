module EuclidAlgebraGroupsOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

const LatexDocument = raw"""\textbf{Algebra - Groups}

For this project, think of a group as a collection of actions taken on a figure. The main questions are: what motions are allowed, how do they compose or behave when you do more than one in sequence, and what happens when you repeat or undo them?

Formally, a group is a set $G$ with a binary operation $\circ: G \times G \to G$ satisfying 4 axioms:

\begin{enumerate}
\item \textbf{Closure}: if $a, b \in G$, then $a \circ b \in G$.
\item \textbf{Associativity}: $(a \circ b) \circ c = a \circ (b \circ c)$ for all $a,b,c \in G$.
\item \textbf{Identity}: there is an element $e \in G$ with $e \circ a = a \circ e = a$ for all $a \in G$.
\item \textbf{Inverses}: for each $a \in G$, there is $a^{-1} \in G$ with $a \circ a^{-1} = a^{-1} \circ a = e$.
\end{enumerate}

Some actions commute and some do not. If $a \circ b = b \circ a$ for all $a,b \in G$, then the group is \textit{commutative}, also called \textit{abelian}. Commutativity is not required."""

"""Return canonical explanatory content for Groups."""
function get_view_content()
    return EuclidLatex.TeXDocument(LatexDocument)
end

"""Describe groups through their four defining axioms and geometric actions."""
function get_search_content()
    return SearchContent(
        """Algebra - Groups
For this project, think of a group as a collection of actions taken on a figure. The main questions are: what motions are allowed, how do they compose or behave when you do more than one in sequence, and what happens when you repeat or undo them?
Formally, a group is a set with a binary operation satisfying 4 axioms:
Closure: if , then .
Associativity: for all.
Identity: there is an element  with for all .
Inverses: for each , there is with .
Some actions commute and some do not. If for all , then the group is commutative, also called abelian. Commutativity is not required.""",
        ("group axioms", "binary operations", "composition of symmetries"))
end

end
