module ElementsOneBookOnePropositionsContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Propositions."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Propositions}

Book I contains forty-eight propositions: constructive problems and deductive theorems
built from its definitions, postulates, common notions, and earlier results. They develop
the geometry of triangles, angles, parallels, parallelograms, and area."""
end

"""Describe the constructive problems and theorems proved in Book I."""
function get_search_content()
    return SearchContent(
        "The forty-eight propositions of Book I combine geometric constructions and " *
        "deductive theorems about triangles, angles, parallels, parallelograms, and area.",
        ("Euclid theorems", "geometric proofs", "construction problems"))
end

end
