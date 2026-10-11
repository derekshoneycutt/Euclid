module ElementsOneBookOneDefinitionsContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Definitions."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Definitions}

The twenty-three definitions name the objects used throughout Book I, beginning with
points, lines, and surfaces and continuing through angles, circles, rectilinear figures,
and parallel lines. They establish terminology rather than grant constructions or make
claims to be proved."""
end

"""Describe the twenty-three geometric terms defined at the start of Book I."""
function get_search_content()
    return SearchContent(
        "The twenty-three definitions of Book I name points, lines, surfaces, angles, " *
        "circles, rectilinear figures, and parallel lines used in later propositions.",
        ("geometric terms", "Euclid definitions", "points lines angles"))
end

end
