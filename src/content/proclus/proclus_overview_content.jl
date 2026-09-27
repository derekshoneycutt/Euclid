module ProclusOverviewContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Proclus's Commentary."""
function get_view_content()
    return tex"""\textbf{Proclus's Commentary}
    
Proclus provided an ancient commentary on Book I of \textit{Euclid's Elements}, including additional constructions and analyses. Some will be included here."""
end

"""Describe Proclus's historical commentary and additional constructions."""
function get_search_content()
    return SearchContent(
        "Proclus's ancient commentary on Book I of Euclid's Elements includes additional " *
        "geometric constructions and analyses of classical propositions.",
        ("ancient Greek geometry", "Euclid commentary", "Book I", "classical constructions"))
end

end
