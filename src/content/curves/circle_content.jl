module EuclidCurvesCircleContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Circle."""
function get_view_content()
    return tex"""\textbf{Circle}

A circle is the plane curve traced by a point kept at a constant distance from a fixed center."""
end

"""Describe the constant-radius locus and compass construction of a circle."""
function get_search_content()
    return SearchContent(
        "A circle is the locus of points equidistant from a fixed center, constructed " *
        "by rotating a compass at constant radius.",
        ("compass construction", "constant radius", "equidistant points"))
end

end
