module EuclidCurvesDimpledLimaconContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Dimpled Limaçon."""
function get_view_content()
    return tex"""\textbf{Dimpled Limaçon}

A dimpled limaçon is traced when the carried point lies inside the rolling circle, but far enough from its center to bend the curve inward without forming a cusp."""
end

"""Describe the inward bend formed by this dimpled limaçon."""
function get_search_content()
    return SearchContent(
        "A dimpled limaçon is traced inside an externally rolling circle, far enough " *
        "from its center to bend inward without forming a cusp or inner loop.",
        ("dimpled limacon", "indented limaçon", "loopless limaçon"))
end

end
