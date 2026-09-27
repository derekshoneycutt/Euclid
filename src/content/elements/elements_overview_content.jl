module EuclidElementsOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Euclid's Elements."""
function get_view_content()
    return tex"""\textbf{Welcome to Euclid's Elements!}

Euclid's Elements develops geometry from definitions, postulates, and common notions
through propositions and constructions."""
end

"""Describe the axiomatic structure and scope of Euclid's Elements."""
function get_search_content()
    return SearchContent(
        "Euclid's Elements is a thirteen-book mathematical work that develops geometry " *
        "from definitions, postulates, and common notions through proofs and constructions.",
        ("axiomatic geometry", "classical geometry", "Euclidean geometry"))
end

end
