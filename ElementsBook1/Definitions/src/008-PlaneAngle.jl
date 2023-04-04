"""
    EuclidAngle2f

Describes an angle to be drawn and animated in Euclid diagrams
"""
mutable struct EuclidAngle2f
    point::Observable{Point2f}
    lengthA::Observable{Float32}
    extremityA::Observable{Point2f}
    lengthB::Observable{Float32}
    extremityB::Observable{Point2f}
    angle::Observable{Float32}
    draw_angle::Observable{Float32}
    plots
    current_width::Observable{Float32}
    show_width::Observable{Float32}
end

"""
    angle(point, lengthA, lengthB, theta[, draw_angle=0f0, width=1.5f0, color=:blue])

Sets up a new angle in a Euclid Diagram for drawing

# Arguments
- `point::Observable{Point2f}`: The location of the central point of the angle, where the lines meet
- `lengthA::Obervable{Float32}`: The length of side A, the base of the angle
- `lengthB::Observable{Float32}`: The length of side B, the rotated side of the angle
- `theta::Observable{Float32}`: The angle in radians to draw
- `draw_angle::Observable{Float32}`: The displacement angle to draw the angle at (both lines will be rotated)
- `width::Union{Float32, Observable{Float32}}`: The width of the line to draw
- `color`: The color to draw the line with
"""
function angle( point::Observable{Point2f},
                lengthA::Observable{Float32}, lengthB::Observable{Float32},
                theta::Observable{Float32};
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    observable_width = Observable(0f0)
    observable_show_width = width isa Observable{Float32} ? width : Observable(width)

    θ = draw_angle isa Observable{Float32} ? draw_angle : Observable(draw_angle)
    θangle = @lift($θ + $theta)

    extremityA = @lift([cos($θ) -sin($θ); sin($θ) cos($θ)] * [$lengthA, 0] + $point)
    extremityB = @lift([cos($θangle) -sin($θangle); sin($θangle) cos($θangle)] * [$lengthB, 0] + $point)

    plots = lines!(@lift([$extremityA, $point, $extremityB]),
                   color=color, linewidth=(observable_width))

    EuclidAngle2f(point, lengthA, extremityA, lengthB, extremityB, theta, θ, plots, observable_width, observable_show_width)
end
function angle( point::Observable{Point2f},
                lengthA::Observable{Float32}, lengthB::Observable{Float32},
                theta::Float32;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(point, lengthA, lengthB, Observable(theta), draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Observable{Point2f},
                lengthA::Observable{Float32}, lengthB::Float32,
                theta::Observable{Float32};
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(point, lengthA, Observable(lengthB), theta, draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Observable{Point2f},
                lengthA::Float32, lengthB::Observable{Float32},
                theta::Observable{Float32};
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(point, Observable(lengthA), lengthB, theta, draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Observable{Point2f},
                lengthA::Float32, lengthB::Float32,
                theta::Observable{Float32};
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(point, Observable(lengthA), Observable(lengthB), theta, draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Observable{Point2f},
                lengthA::Float32, lengthB::Observable{Float32},
                theta::Float32;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(point, Observable(lengthA), lengthB, Observable(theta), draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Observable{Point2f},
                lengthA::Float32, lengthB::Float32,
                theta::Float32;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(point, Observable(lengthA), Observable(lengthB), Observable(theta), draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Observable{Point2f},
                lengthA::Observable{Float32}, lengthB::Float32,
                theta::Float32;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(point, lengthA, Observable(lengthB), Observable(theta), draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Point2f,
                lengthA::Observable{Float32}, lengthB::Observable{Float32},
                theta::Float32;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(Observable(point), lengthA, lengthB, Observable(theta), draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Point2f,
                lengthA::Observable{Float32}, lengthB::Float32,
                theta::Observable{Float32};
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(Observable(point), lengthA, Observable(lengthB), theta, draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Point2f,
                lengthA::Float32, lengthB::Observable{Float32},
                theta::Observable{Float32};
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(Observable(point), Observable(lengthA), lengthB, theta, draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Point2f,
                lengthA::Float32, lengthB::Float32,
                theta::Observable{Float32};
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(Observable(point), Observable(lengthA), Observable(lengthB), theta, draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Point2f,
                lengthA::Float32, lengthB::Observable{Float32},
                theta::Float32;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(Observable(point), Observable(lengthA), lengthB, Observable(theta), draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Point2f,
                lengthA::Float32, lengthB::Float32,
                theta::Float32;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(Observable(point), Observable(lengthA), Observable(lengthB), Observable(theta), draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Point2f,
                lengthA::Observable{Float32}, lengthB::Float32,
                theta::Float32;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(Observable(point), lengthA, Observable(lengthB), Observable(theta), draw_angle=draw_angle, width=width, color=color)
end
function angle( point::Point2f,
                lengthA::Observable{Float32}, lengthB::Observable{Float32},
                theta::Observable{Float32};
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    angle(Observable(point), lengthA, lengthB, theta, draw_angle=draw_angle, width=width, color=color)
end


function angle( center::Observable{Point2f}, pointA::Observable{Point2f}, pointB::Observable{Point2f};
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)

    observable_width = Observable(0f0)
    observable_show_width = width isa Observable{Float32} ? width : Observable(width)

    vecA = @lift($pointA - $center)
    vecB = @lift($pointB - $center)
    lengthA = @lift(norm($vecA))
    lengthB = @lift(norm($B))

    theta = @lift(($vecA ⋅ $vecB) / ($lengthA * $lengthB))
    θ = @lift(min(fix_angle(vector_angle($center, $pointA)),
                  fix_angle(vector_angle($center, $pointB))))

    plots = lines!(@lift([$extremityA, $point, $extremityB]),
                   color=color, linewidth=(observable_width))

    EuclidAngle2f(center, lengthA, pointA, lengthB, pointB, theta, θ, plots, observable_width, observable_show_width)
end
function angle( center::Observable{Point2f}, pointA::Point2f, pointB::Point2f;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)
    angle(center, Observable(pointA), Observable(pointB), draw_angle=draw_angle, width=width, color=color)
end
function angle( center::Observable{Point2f}, pointA::Observable{Point2f}, pointB::Point2f;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)
    angle(center, pointA, Observable(pointB), draw_angle=draw_angle, width=width, color=color)
end
function angle( center::Observable{Point2f}, pointA::Point2f, pointB::Observable{Point2f};
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)
    angle(center, Observable(pointA), pointB, draw_angle=draw_angle, width=width, color=color)
end
function angle( center::Point2f, pointA::Observable{Point2f}, pointB::Point2f;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)
    angle(Observable(center), pointA, Observable(pointB), draw_angle=draw_angle, width=width, color=color)
end
function angle( center::Point2f, pointA::Observable{Point2f}, pointB::Observable{Point2f};
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)
    angle(Observable(center), pointA, pointB, draw_angle=draw_angle, width=width, color=color)
end
function angle( center::Point2f, pointA::Point2f, pointB::Observable{Point2f};
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)
    angle(Observable(center), Observable(pointA), pointB, draw_angle=draw_angle, width=width, color=color)
end
function angle( center::Point2f, pointA::Point2f, pointB::Point2f;
                draw_angle::Union{Float32, Observable{Float32}}=0f0,
                width::Union{Float32, Observable{Float32}}=1.5f0, color=:blue)
    angle(Observable(center), Observable(pointA), Observable(pointB), draw_angle=draw_angle, width=width, color=color)
end


"""
    show_complete(angle)

Completely show previously defined angle in a Euclid diagram

# Arguments
- `angle::EuclidAngle2f`: The angle to completely show
"""
function show_complete(angle::EuclidAngle2f)
    angle.current_width[] = angle.show_width[]
end

"""
    hide(angle)

Completely hide previously defined angle in a Euclid diagram

# Arguments
- `angle::EuclidAngle2f`: The angle to completely hide
"""
function hide(angle::EuclidAngle2f)
    angle.current_width[] = 0f0
end

"""
    animate(angle, hide_until, max_at, t[, fade_start=0f0, fade_end=0f0])

Animate drawing and perhaps then hiding angle drawn in a Euclid diagram

# Arguments
- `angle::EuclidAngle2f`: The angle to animate in the diagram
- `hide_until::AbstractFloat`: The point to hide the angle until
- `max_at::AbstractFloat`: The time to max drawing the angle at -- when it is fully drawn
- `t::AbstractFloat`: The current timeframe of the animation
- `fade_start::AbstractFloat`: When to begin fading the angle away from the diagram
- `fade_end::AbstractFloat`: When to end fading the angle awawy from the diagram -- it will be hidden entirely
"""
function animate(
    angle::EuclidAngle2f, hide_until::AbstractFloat, max_at::AbstractFloat, t::AbstractFloat;
    fade_start::AbstractFloat=0f0, fade_end::AbstractFloat=0f0)

    perform(t, hide_until, max_at, fade_start, fade_end,
        () -> angle.current_width[] = 0f0,
        () -> angle.current_width[] = angle.show_width[],
        () -> angle.current_width[] = 0f0) do i
        if i == 1
            on_t = (t-hide_until)/(max_at-hide_until)
            angle.current_width[] = angle.show_width[] * on_t
        else
            on_t = (t-fade_start)/(fade_end-fade_start)
            angle.current_width[] = angle.show_width[]- (angle.show_width[] * on_t)
        end
    end
end
