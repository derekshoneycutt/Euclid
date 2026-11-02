module EuclidCurvesHyperbolaContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Explain the two branches and the simplified symmetric tracing apparatus."""
function get_view_content()
    return tex"""\textbf{Hyperbola}

A hyperbola has two pieces, called connected components or branches, that are mirror images of each other and resemble two infinite bows.
The hyperbola is one of the three kinds of conic section, formed by the intersection of a plane and a double cone.
If the plane intersects both halves of the double cone but does not pass through the apex of the cones, then the conic is a hyperbola.

Besides being a conic section, a hyperbola can arise as the locus of points whose difference of distances
to two fixed foci is constant, as a curve for each point of which the rays to two fixed foci are reflections
across the tangent line at that point, or as the solution of certain bivariate quadratic equations such as the
reciprocal relationship $xy = 1$.

In practical applications, a hyperbola can arise as the path followed by the shadow of the
tip of a sundial's gnomon, the shape of an open orbit such as that of a celestial object
exceeding the escape velocity of the nearest gravitational body, or the scattering trajectory
of a subatomic particle, among others.

Each branch of the hyperbola has two arms which become straighter (lower curvature) further out from
the center of the hyperbola. Diagonally opposite arms, one from each branch, tend in the limit to a
common line, called the asymptote of those two arms. So there are two asymptotes, whose intersection
is at the center of symmetry of the hyperbola, which can be thought of as the mirror point about
which each branch reflects to form the other branch. In the case of the curve $y(x) = 1/x$
the asymptotes are the two coordinate axes.

For positive semiaxes $a$ and $b$, a centered left/right hyperbola has equation

$$\frac{x^2}{a^2}-\frac{y^2}{b^2}=1.$$

Its two branches are central reflections of one another:

$$P_+(t)=(a\;\text{cosh} t,b\;\text{sinh} t),\qquad P_-(t)=-P_+(t).$$"""
end

"""Provide deterministic searchable hyperbola text and guide aliases."""
function get_search_content()
    return SearchContent(
        """Hyperbola
A hyperbola has two pieces, called connected components or branches, that are mirror images of each other and resemble two infinite bows.
The hyperbola is one of the three kinds of conic section, formed by the intersection of a plane and a double cone.
If the plane intersects both halves of the double cone but does not pass through the apex of the cones, then the conic is a hyperbola.
Besides being a conic section, a hyperbola can arise as the locus of points whose difference of distances
to two fixed foci is constant, as a curve for each point of which the rays to two fixed foci are reflections
across the tangent line at that point, or as the solution of certain bivariate quadratic equations such as the
reciprocal relationship xy = 1.
In practical applications, a hyperbola can arise as the path followed by the shadow of the
tip of a sundial's gnomon, the shape of an open orbit such as that of a celestial object
exceeding the escape velocity of the nearest gravitational body, or the scattering trajectory
of a subatomic particle, among others.
Each branch of the hyperbola has two arms which become straighter (lower curvature) further out from
the center of the hyperbola. Diagonally opposite arms, one from each branch, tend in the limit to a
common line, called the asymptote of those two arms. So there are two asymptotes, whose intersection
is at the center of symmetry of the hyperbola, which can be thought of as the mirror point about
which each branch reflects to form the other branch. In the case of the curve y(x) = 1/x
the asymptotes are the two coordinate axes.
For positive semiaxes a and b, a centered left/right hyperbola has equation
frac
Its two branches are central reflections of one another:
cosh sinh quad""",
        ("conic section", "two branches", "asymptotes", "hyperbolagraph",
            "hyperbolic curve", "constant distance difference"))
end

end
