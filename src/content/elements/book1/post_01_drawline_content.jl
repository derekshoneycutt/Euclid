module ElementsOnePostulatesDrawLineContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Draw a Line."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Postulates}: \textit{Draw a Line}

\textit{Let the following be postulated:}

To draw a straight line \euclidline[color=steelblue,length=3,thickness=4] from any point \euclidpoint[color=palevioletred1,size=1] to any point \euclidpoint[color=khaki3,size=1]."""
end

"""Describe Euclid's first postulate for joining two points."""
function get_search_content()
    return SearchContent(
        "Euclid's first postulate permits drawing a straight line from any point to any " *
        "other point, the basic joining operation of straightedge construction.",
        ("Postulate I", "join two points", "draw straight line"))
end

end
