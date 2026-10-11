module ElementsOneBookOneOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Book I."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I}

Book I begins with twenty-three definitions, five postulates, and five common notions.
Its forty-eight propositions use those foundations to construct figures and prove
properties of triangles, angles, parallels, and areas."""
end

"""Describe the foundations and forty-eight propositions of Book I."""
function get_search_content()
    return SearchContent(
        "Book I develops plane geometry from twenty-three definitions, five postulates, " *
        "and five common notions through forty-eight constructions and theorems.",
        ("Euclid Book One", "plane geometry", "forty-eight propositions"))
end

end
