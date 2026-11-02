module EuclidCurvesParabolaContent

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Explain the focus/directrix definition and simplified articulated instrument."""
function get_view_content()
    return tex"""\textbf{Parabola}

A parabola is a plane curve which is mirror-symmetrical and is approximately U-shaped.

It fits several superficially different mathematical descriptions, which can all be proved to define exactly the same curves.

One description of a parabola involves a point (the focus) and a line (the directrix). The focus does not lie on the directrix.
The parabola is the locus of points in that plane that are equidistant from the directrix and the focus.

Another description of a parabola is as a conic section, created from the intersection of a right circular conical surface and a plane parallel to another plane that is tangential to the conical surface.

The graph of a quadratic function

$$y = ax^2 + bx + c\; \text{ with }\; a \neq 0$$

is a parabola with its axis of symmetry parallel to the y-axis. Conversely, every such parabola is the graph of a quadratic function.

The line perpendicular to the directrix and passing through the focus (that is, the line that splits the parabola through the middle) is called the "axis of symmetry".
The point where the parabola intersects its axis of symmetry is called the "vertex" and is the point where the parabola is most sharply curved.
The distance between the vertex and the focus, measured along the axis of symmetry, is the "focal length".
The "latus rectum" is the chord of the parabola that is parallel to the directrix and passes through the focus.

Parabolas can open up, down, left, right, or in some other arbitrary direction.
Any parabola can be repositioned and rescaled to fit exactly on any other parabola—that is, all parabolas are geometrically similar.

A parabola is the locus of points equally distant from a fixed point, the focus, and a fixed line, the directrix."""
end

"""Provide deterministic searchable parabola text and instrument aliases."""
function get_search_content()
    return SearchContent(
        """Parabola
A parabola is a plane curve which is mirror-symmetrical and is approximately U-shaped.
It fits several superficially different mathematical descriptions, which can all be proved to define exactly the same curves.
One description of a parabola involves a point (the focus) and a line (the directrix). The focus does not lie on the directrix.
The parabola is the locus of points in that plane that are equidistant from the directrix and the focus.
Another description of a parabola is as a conic section, created from the intersection of a right circular conical surface and a plane parallel to another plane that is tangential to the conical surface.
The graph of a quadratic function
is a parabola with its axis of symmetry parallel to the y-axis. Conversely, every such parabola is the graph of a quadratic function.
The line perpendicular to the directrix and passing through the focus (that is, the line that splits the parabola through the middle) is called the "axis of symmetry".
The point where the parabola intersects its axis of symmetry is called the "vertex" and is the point where the parabola is most sharply curved.
The distance between the vertex and the focus, measured along the axis of symmetry, is the "focal length".
The "latus rectum" is the chord of the parabola that is parallel to the directrix and passes through the focus.
Parabolas can open up, down, left, right, or in some other arbitrary direction.
Any parabola can be repositioned and rescaled to fit exactly on any other parabola—that is, all parabolas are geometrically similar.
A parabola is the locus of points equally distant from a fixed point, the focus, and a fixed line, the directrix.""",
        ("conic section", "focus and directrix", "parabolagraph",
            "parabolograph", "Inwards", "articulated diamond"))
end

end
