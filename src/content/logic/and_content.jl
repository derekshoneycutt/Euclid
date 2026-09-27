module EuclidLogicAndContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for And."""
function get_view_content()
    return tex"""\textbf{And}

The conjunction $A \land B$ holds where both conditions hold. In the diagram, that is the Lens $A \cap B$: the overlap of the two circles."""
end

"""Describe conjunction as the lens-shaped intersection of two circles."""
function get_search_content()
    return SearchContent(
        "The conjunction A AND B is the lens-shaped intersection where both conditions " *
        "hold, shown by the overlapping region of two circles.",
        ("conjunction", "set intersection", "lens region", "both conditions"))
end

end
