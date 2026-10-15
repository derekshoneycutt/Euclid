module EuclidLogicOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Logic."""
function get_view_content()
    return tex"""\textbf{Logic}

Logic and set operations are frequently used in many mathematics, and they have even been
employed to describe geometric properties by mathematicians like Tarski. Basic operations are
shown here in visual forms that may help understand geometric reasoning utilizing them."""
end

"""Describe logical connectives through bounded geometric regions."""
function get_search_content()
    return SearchContent(
        """Logic
Logic and set operations are frequently used in many mathematics, and they have even been
employed to describe geometric properties by mathematicians like Tarski. Basic operations are
shown here in visual forms that may help understand geometric reasoning utilizing them.""",
        ("logical connectives", "set operations", "geometric logic", "Venn diagram"))
end

end
