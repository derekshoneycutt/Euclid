module EuclidCurvesOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Curves."""
function get_view_content()
    return tex"""\textbf{Curves}

Here, we explore various kinds of curves in geometry."""
end

"""Describe the classical curve families and constructions in this collection."""
function get_search_content()
    return SearchContent(
        "A collection of classical plane curves traced by compass, rolling-circle, " *
        "and rolling-line constructions.",
        ("plane curves", "roulette curves", "rolling curves"))
end

end
