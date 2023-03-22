"""
    intersection(line1, line2)

Get the point of intersection of 2 lines, if present

# Arguments
- `line1::EuclidLine2f`: The first line to find intersection with
- `line2::EuclidLine2f`: The second line to find intersection with
"""
function intersection(line1::EuclidLine2f, line2::EuclidLine2f;
    point_width::AbstractFloat=0.01f0, point_color=:blue,
    text_color=:blue, text_opacity::AbstractFloat=1f0, label="A")

    extremity_1A = line1.extremityA[]
    extremity_1B = line1.extremityB[]
    extremity_2A = line2.extremityA[]
    extremity_2B = line2.extremityB[]

    # Get formulas for line1 and line2
    m_1 = (extremity_1B[1] - extremity_1A[1] != 0) ?
        (extremity_1B[2] - extremity_1A[2]) / (extremity_1B[1] - extremity_1A[1]) :
        nothing
    b_1 = m_1 !== nothing ?
        extremity_1A[2] - m_1 * extremity_1A[1] :
        nothing
    m_2 = (extremity_2B[1] - extremity_2A[1] != 0) ?
        (extremity_2B[2] - extremity_2A[2]) / (extremity_2B[1] - extremity_2A[1]) :
        nothing
    b_2 = m_2 !== nothing ?
        extremity_2A[2] - m_2 * extremity_2A[1] :
        nothing

    # check if we have parallels or an y = # and x = # intersection first
    if (m_1 === nothing && m_2 === nothing) || m_1 == m_2
        return nothing
    elseif abs(m_1) == 0 && m_2 === nothing
        return point(Observable(Point2f0(extremity_2A[1], b_1)),
                     point_width=point_width, point_color=point_color,
                     text_color=text_color, text_opacity=text_opacity, label=label)
    elseif abs(m_2) == 0 && m_1 === nothing
        return point(Observable(Point2f0(extremity_1A[1], b_2)),
                     point_width=point_width, point_color=point_color,
                     text_color=text_color, text_opacity=text_opacity, label=label)
    end

    # solve x and y
    x = 0
    y = 0
    if m_1 === nothing
        # If line1 is vertical, then extremity_1A[1] is the x Axis
        x = extremity_1A[1]
        y = m_2 * x + b_2
    elseif m_2 === nothing
        # If line2 is vertical, then extremity_2A[1] is the x Axis
        x = extremity_2A[1]
        y = m_1 * x + b_1
    else
        # normal times are happy times
        x = (b_1 - b_2) / (m_2 - m_1)
        y = m_2 * x + b_2
    end

    # return nothing or the intersection point if it exists
    min_x = min(extremity_1A[1], extremity_1B[1], extremity_2A[1], extremity_2B[1])
    max_x = max(extremity_1A[1], extremity_1B[1], extremity_2A[1], extremity_2B[1])
    min_y = min(extremity_1A[2], extremity_1B[2], extremity_2A[2], extremity_2B[2])
    max_y = max(extremity_1A[2], extremity_1B[2], extremity_2A[2], extremity_2B[2])
    if x !== nothing && y !== nothing && x >= min_x && x <= max_x && y >= min_y && y <= max_y
        return point(Observable(Point2f0(x, y)),
                     point_width=point_width, point_color=point_color,
                     text_color=text_color, text_opacity=text_opacity, label=label)
    end
    nothing
end

#=

""" Get the point of intersection of a line and circle, if present """
function intersection(line::EuclidLine, circle::EuclidCircle)
    # Get formulas for line
    m = (line.B[1] - line.A[1] != 0) ? (line.B[2] - line.A[2]) / (line.B[1] - line.A[1]) : nothing
    b = m !== nothing ? line.A[2] - m * line.A[1] : nothing

    # Set up quadratic formula
    quad_a = m^2 + 1
    quad_b = 2*(b*m - circle.A[1] - circle.A[2]*m)
    quad_c = circle.A[1]^2 + circle.A[2]^2 - circle.r^2 + b^2 - 2 * b * circle.A[2]

    # check square root and division are going to be valid, then do them
    x_sqrtprt = quad_b^2 - 4 * quad_a * quad_c
    x_denomprt = 2 * quad_a
    x_1 = x_sqrtprt >= 0 && x_denomprt != 0 ? (-quad_b + √(x_sqrtprt)) / x_denomprt : nothing
    x_2 = x_sqrtprt >= 0 && x_denomprt != 0 ? (-quad_b - √(x_sqrtprt)) / x_denomprt : nothing
    y_1 = x_1 !== nothing ? m * x_1 + b : nothing
    y_2 = x_2 !== nothing ? m * x_2 + b : nothing

    # return the 2 points or empty list
    if x_1 !== nothing && x_2 !== nothing
        return [Point2f(x_1, y_1), Point2f(x_2, y_2)]
    elseif x_1 !== nothing
        return [Point2f(x_1, y_1)]
    elseif x_2 !== nothing
        return [Point2f(x_2, y_2)]
    else
        return []
    end
end

""" Get the point of intersection of a circle and line, if present """
function intersection(circle::EuclidCircle, line::EuclidLine)
    intersection(line, circle)
end

""" Get the point of intersection of 2 circles, if present """
function intersection(circle1::EuclidCircle, circle2::EuclidCircle)
    d = norm(circle2.A - circle1.A)
    a = (circle1.r^2 - circle2.r^2 +d^2) / (2*d)
    #b = (circle2.r^2 - circle1.r^2 +d^2) / (2*d)

    r_sum = circle1.r + circle2.r
    if d <= r_sum
        h = √((circle1.r)^2 - a^2)
        c = Point2f(circle1.A + ((a/d) .* (circle2.A - circle1.A)))

        if d == r_sum
            return [c]
        else
            center_vec = (circle2.A - circle1.A)
            clockwise = [0 1; -1 0] * center_vec
            counterclockwise = [0 -1; 1 0] * center_vec

            clockwise_int = Point2f(c - (h/d) * clockwise)
            counterclockwise_int = Point2f(c - (h/d) * counterclockwise)

            return [clockwise_int, counterclockwise_int]
        end
    end
    []
end
=#