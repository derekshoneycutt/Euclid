module ElementsOneDefinitionStraightLineContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Straight Line."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definition}: \textit{Straight Line}

A straight line \euclidline[color=steelblue,length=3,thickness=4] is a line which lies evenly with the points \euclidpoint[color=palevioletred1,size=1] on itself."""
end

"""Describe Euclid's straight line as lying evenly with its points."""
function get_search_content()
    return SearchContent(
        "Euclid defines a straight line as a line that lies evenly with the points on " *
        "itself, without bending away from them.",
        ("lies evenly", "collinear points", "unbent line"))
end

end
