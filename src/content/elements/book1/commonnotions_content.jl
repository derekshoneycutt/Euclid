module ElementsOneCommonNotionsContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Common Notions."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Common Notions}

\begin{enumerate}
\item Things which are equal to the same thing are also equal to one another.
\item If equals be added to equals, the wholes are equal.
\item If equals be subtracted from equals, the remainders are equal.
\item Things which coincide with one another are equal to one another.
\item The whole is greater than the part.
\end{enumerate}"""
end

"""Describe Euclid's five general principles of equality and comparison."""
function get_search_content()
    return SearchContent(
        "Euclid's five common notions govern equality and comparison: transitivity, " *
        "adding or subtracting equals, coincidence, and the whole exceeding the part.",
        ("general axioms", "whole greater than part", "transitivity of equality"))
end

end
