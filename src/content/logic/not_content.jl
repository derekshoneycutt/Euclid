module EuclidLogicNotContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Not."""
function get_view_content()
    return tex"""\textbf{Not}

The Not operation describes the opposite of a True/False value. When applied to a True value, we get False. When applied to a False value, we get True.

This is formally written as $\neg T$.

In the Venn Diagram, we highlight the space composing all points within $A$ where $B$ is Not True; that is, $\neg B$. In this case, we are technically representing $A\land\neg B$.

In sets, we may write $\{ x \mid x\notin B \}$, or specifically for the shown case, $\{ x \mid x\in A\land x\notin B\}$.

$$\begin{array}{c|c}
P & \neg P \\
\hline
\text{T} & \text{F} \\
\text{F} & \text{T} \\
\end{array}$$"""
end

"""Describe bounded negation as the lune formed by set difference."""
function get_search_content()
    return SearchContent(
        """Not
The "Not" operation describes the opposite of a True/False value. When applied to a True value, we get False. When applied to a False value, we get True.
This is formally written as .
In the Venn Diagram, we highlight the space composing all points within A where B is Not True; that is, . In this case, we are technically representing .
In sets, we may write , or specifically for the shown case, .""",
        ("bounded negation", "set difference", "lune region", "A not B"))
end

end
