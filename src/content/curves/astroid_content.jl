module EuclidCurvesAstroidContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Astroid."""
function get_view_content()
    return tex"""\textbf{Astroid}

An astroid is the four-cusped hypocycloid with $k=R/r=4$. Its tracing point lies on a circle whose radius is one quarter of the fixed circle's radius."""
end

"""Describe the four-cusped hypocycloid called an astroid."""
function get_search_content()
    return SearchContent(
        "An astroid is a four-cusped hypocycloid traced on a circle rolling inside " *
        "a fixed circle four times its radius.",
        ("four-cusped hypocycloid", "tetracuspid", "four-pointed roulette"))
end

end
