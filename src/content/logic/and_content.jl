module EuclidLogicAndContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for And."""
function get_view_content()
    return tex"""\textbf{And}

The And operation describes when two conditions are both true. That is, A and B is True only if A and B are both True.

This is formally written as $A\land B$.

In the Venn Diagram, we highlight the space composing all points where $A\land B$ is True, assuming that presence within the circle is the condition for being True.

In sets, we may write $\{ x \mid x\in A \land x\in B \}$ or $A\cap B$.

$$\begin{array}{c|c|c}
P & Q & P \land Q \\
\hline
\text{T} & \text{T} & \text{T} \\
\text{T} & \text{F} & \text{F} \\
\text{F} & \text{T} & \text{F} \\
\text{F} & \text{F} & \text{F} \\
\end{array}$$"""
end

"""Describe conjunction as the lens-shaped intersection of two circles."""
function get_search_content()
    return SearchContent(
        """And
The "And" operation describes when two conditions are both true. That is, A and B is True only if A and B are both True.
This is formally written as A and B.
In the Venn Diagram, we highlight the space composing all points where A and B is True, assuming that presence within the circle is the condition for being True.
In sets, we may write x x in A and x in B or A intersect B.""",
        ("conjunction", "set intersection", "lens region", "both conditions"))
end

end
