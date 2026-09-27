module EuclidCurvesEllipseContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Ellipse."""
function get_view_content()
    return tex"""\textbf{Ellipse}

An ellipse is a closed plane curve whose distances from two fixed points have a constant sum. Here it is traced by a point carried on a circle rolling inside a larger circle."""
end

"""Describe the focal definition and internal rolling construction of an ellipse."""
function get_search_content()
    return SearchContent(
        "An ellipse is the locus whose distances from two fixed foci have a constant " *
        "sum, here traced by a circle rolling inside a larger circle.",
        ("two foci", "constant distance sum", "internal rolling", "oval"))
end

end
