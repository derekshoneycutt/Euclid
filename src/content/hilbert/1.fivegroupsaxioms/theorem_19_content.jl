module HilbertChapterOneTheorem19Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 19."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 19}

If two parallel lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=khaki3,length=3,thickness=4]
are cut by a third straight line \euclidline[color=palevioletred1,length=3,thickness=4], the alternate-interior angles
and also the exterior-interior angles are congruent. Conversely, if the alternate-interior or the exterior-interior angles are congruent, the given lines are parallel."""
end

"""Describe angle criteria for parallel lines cut by a transversal."""
function get_search_content()
    return SearchContent(
        "Theorem 19 relates parallel lines cut by a transversal to congruent alternate-" *
        "interior and exterior-interior angles, including the converse criterion.",
        ("parallel transversal angles", "alternate interior angles", "exterior interior angles"))
end

end
