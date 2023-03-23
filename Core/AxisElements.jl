
"""
    euclid_axis(f[, title=""])

Setup an axis for drawing Euclid diagrams

# Arguments
- `f`: The figure to draw the axis on. (Consider using a specific scene.)
- `title`: The title of the axis to draw. Default is empty string.
"""
function euclid_axis(f; title="")
    Axis(f,
        aspect=DataAspect(),
        title=title,
        xticklabelsvisible=false, yticklabelsvisible=false,
        yticksvisible=false, xticksvisible=false,
        xgridvisible=false, ygridvisible=false,
        topspinevisible=false, bottomspinevisible=false,
        leftspinevisible=false, rightspinevisible=false)
end

"""
    circle_legend([width=0.1f0, color=:blue, center=Point2f0(0.5,0.5)])

Create a circle legend element for displaying on Euclid diagrams

# Arguments
- `width::AbstractFloat`: The width, as a radius, of the circle to draw
- `color`: The color of circle to draw
- `center::Point2f`: Where to draw the center of the circle at, defaults to center position
"""
function circle_legend(; width::AbstractFloat=0.1f0, color=:blue, center::Point2f=Point2f0(0.5,0.5))
    axis_element_points = [Point2f0(center[1] + cos(t) * width, center[2] + sin(t) * width) for t in 1:360]
    PolyElement(points=axis_element_points, color=color, strokecolor=color, strokewidth=1)
end

"""
    circle_legend([width=0.1f0, color=:blue, center=Point2f0(0.5,0.5)])

Create a circle legend element for displaying on Euclid diagrams

# Arguments
- `width::AbstractFloat`: The width, as a radius, of the circle to draw
- `color`: The color of circle to draw
- `center::Point2f`: Where to draw the center of the circle at, defaults to center position
"""
function square_legend(; width::AbstractFloat=1f0, color=:blue, center::Point2f=Point2f0(0.5,0.5))
    from_center = width / 2f0
    do_box = [Point2f0(center .- from_center),  Point2f0(center - [from_center, -from_center]),
              Point2f0(center .+ from_center), Point2f0(center - [-from_center, from_center])]
    PolyElement(points=do_box, color=color, strokecolor=color, strokewidth=1)
end

"""
    line_legend([width=0.1f0, color=:blue, linestyle=:solid, linewidth=1.5f0, start_y=0.5f0, end_y=0.5f0])

Create a line legend element for displaying on Euclid diagrams

# Arguments
- `width::AbstractFloat`: The width of the line to draw. Is centered horizontally.
- `color`: The color of line to draw
- `linestyle`: The style of line to draw
- `linewidth::AbstractFloat`: The width of the line to draw
- `start_y::AbstractFloat`: The starting y-position to draw the line at. Defaults in the middle.
- `end_y::AbstractFloat`: The ending y-position to draw the line at. Defaults in the middle.
"""
function line_legend(; width::AbstractFloat=0.1f0, color=:blue,
                       linestyle=:solid, linewidth::AbstractFloat=1.5f0,
                       start_y::AbstractFloat=0.5f0, end_y::AbstractFloat=0.5f0)
    start_line = width >= 1 ? 0 : width / 2f0
    end_line = width >= 1 ? 1 : 1 - (width / 2f0)
    axis_element_points = [Point2f0(start_line, start_y), Point2f0(end_line, end_y)]
    LineElement(points=axis_element_points, color=color, linestyle=linestyle, linewidth=linewidth)
end
