module HilbertChapterOneTheorem14Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Theorem 14."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Theorem 14}

Let $h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4],
$l$ \euclidline[color=grey60,length=3,thickness=4] and
$h'$ \euclidline[color=steelblue,length=3,thickness=4], $k'$ \euclidline[color=palevioletred1,length=3,thickness=4],
$l'$ \euclidline[color=grey60,length=3,thickness=4] be two sets of three half-rays, where those of each set emanate
from the same point and lie in the same plane. Then, if the congruences

    $\angle(h, l) \equiv \angle(h', l')$ \euclidangle[color=lightgreen,radius=2,end=60,filled],   $\angle(k, l) \equiv \angle(k', l')$ \euclidangle[color=lightgreen,radius=2,end=60,filled]

are fulfilled, the following congruence is also valid; viz.:

    $\angle(h, k) \equiv \angle(h', k')$ \euclidangle[color=lightgreen,radius=2,end=60,filled]."""
end

"""Describe congruence of whole angles from two corresponding subangles."""
function get_search_content()
    return SearchContent(
        "Theorem 14 states that when two pairs of corresponding subangles are congruent, " *
        "the whole angles formed by their outer half-rays are congruent.",
        ("angle addition", "congruent angle sums", "subangles determine whole angle"))
end

end
