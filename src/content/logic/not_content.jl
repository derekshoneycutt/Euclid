module EuclidLogicNotContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Not."""
function get_view_content()
    return tex"""\textbf{Not}

Within $A$, the condition $A \land \neg B$ holds where $A$ holds and $B$ does not. This is the Lune $A \setminus B$: the part of circle $A$ cut away from their overlap."""
end

"""Describe bounded negation as the lune formed by set difference."""
function get_search_content()
    return SearchContent(
        "Bounded negation A AND NOT B is the crescent-shaped lune where A holds and B " *
        "does not, represented by the set difference A minus B.",
        ("bounded negation", "set difference", "lune region", "A not B"))
end

end
