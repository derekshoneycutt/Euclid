module HilbertChapterOneAxiomIV4Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Axiom IV,4."""
function get_view_content()
    return tex"""\textbf{David Hilbert - Foundations of Geometry - Axiom IV,4}

\textbf{IV, 4.} Let an angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] be given in the plane $\alpha$ and let a straight line $a'$ \euclidline[color=steelblue,length=3,thickness=4] be given in a plane $\alpha'$. Suppose also that, in the plane $\alpha$, a definite side of the straight line $a'$ \euclidline[color=steelblue,length=3,thickness=4] be assigned. Denote by $h'$ \euclidline[color=steelblue,length=3,thickness=4] a half-ray of the straight line $a'$ \euclidline[color=steelblue,length=3,thickness=4] emanating from a point $O'$ \euclidpoint[color=plum1,size=0.5] of this line. Then in the plane $\alpha'$ there is one and only one half-ray $k'$ \euclidline[color=grey60,length=3,thickness=4] such that the angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled], or $(k, h)$ \euclidangle[color=khaki3,radius=2,end=60,filled], is congruent to the angle $(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] and that at the same time all interior points of the angle $(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] lie upon the given side of $a'$ \euclidline[color=steelblue,length=3,thickness=4]. We express this relation by means of the notation

$\angle(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] $\equiv \angle(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled]

Every angle is congruent to itself; that is,

$\angle(h, k) \equiv \angle(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled]

or

$\angle(h, k) \equiv \angle(k, h)$ \euclidangle[color=khaki3,radius=2,end=60,filled]

We say, briefly, that every angle in a given plane can be laid off upon a given side of a given half-ray in one and only one way."""
end

"""Describe unique placement of a congruent angle on a half-ray."""
function get_search_content()
    return SearchContent(
        "Axiom IV,4 states that an angle can be laid off congruently in exactly one way " *
        "on a chosen side of a given half-ray in a plane.",
        ("lay off angle", "unique angle transfer", "angle congruent to itself"))
end

end
