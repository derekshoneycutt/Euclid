module ElementsOneProposition02Content

using ...EuclidLatex
using ...EuclidSearchContent: SearchContent

export get_search_content, get_view_content

"""Return canonical explanatory content for Proposition II."""
function get_view_content()
    return tex"""\textbf{Euclid Elements - Book I - Proposition II}

\textit{To place at a given point (as an extremity) a straight line equal to a given straight line.}

Let A be the given point, and BC the given straight line. Thus it is required to place at the point A (as an extremity) a straight line equal to the given straight line BC.

From the point A to the point B let the straight line AB be joined;
and on it let the equilateral triangle DAB be constructed.

Let the straight lines AE, BF be produced in a straight line with DA, DB with center B and distance BC let the circle CGH be described;
and again, with center D and distance DG let the circle GKL be described.

Then, since the point B is the center of the circle CGH, BC is equal to BG.
Again, since the point D is the center of the circle GKL, DL is equal to DG. And in these DA is equal to DB;
therefore the remainder AL is equal to the remainder BG.

But BC was also proved equal to BG; therefore each of the straight lines AL, BC is equal to BG.
And things which are equal to the same thing are also equal to one another; therefore AL is also equal to BC.
Therefore at the given point A the straight line AL is placed equal to the given straight line BC.

(Being) what it was required to do."""
end

"""Describe Proposition II's construction for transferring a length."""
function get_search_content()
    return SearchContent(
        "Proposition II places at a given point a straight line equal to a given straight " *
        "line, using an equilateral triangle and circles to transfer the length.",
        ("copy line segment", "transfer a length", "equal line at given point"))
end

end
