module EuclidLogicOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Logic."""
function get_view_content()
    return tex"""\textbf{Logic}

Logical operations describe how conditions and sets combine. The diagrams here use bounded regions to make those relationships visible."""
end

"""Describe logical connectives through bounded geometric regions."""
function get_search_content()
    return SearchContent(
        "Logic visualizes conjunction and bounded negation with overlapping circles, " *
        "using a lens for intersection and a lune for set difference.",
        ("logical connectives", "set operations", "geometric logic", "Venn diagram"))
end

end
