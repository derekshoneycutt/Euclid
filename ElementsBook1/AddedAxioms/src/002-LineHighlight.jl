"""
    EuclidLine2fHighlight

Describes highlighting a line in a Euclid diagram
"""
mutable struct EuclidLine2fHighlight
    baseOn::EuclidLine2f
    current_width::Observable{Float32}
    max_width::Float32
end

"""
    highlight(line[, width=2f0, color=:red])

Set up highlighting a single line in a Euclid diagram

# Arguments
- `line::EuclidLine2f`: The line to highlight in the diagram
- `width::AbstractFloat`: The width of the circle to draw the highlight
- `color`: The color to use in highlighting the line
"""
function highlight(line::EuclidLine2f; width::AbstractFloat=2f0, color=:red)

    observable_highlight = Observable(0f0)

    use_color = get_color(color)
    lines!(@lift([$(line.extremityA), $(line.extremityB)]),
           color=RGBA(use_color.r, use_color.g, use_color.b, 0.6),
           linewidth=observable_highlight)

    EuclidLine2fHighlight(line, observable_highlight, width)
end

"""
    show_complete(line)

Complete a previously defined highlight operation for a line in a Euclid diagram. It will be fully highlighted.

# Arguments
- `line::EuclidLine2fHighlight`: The description of the highlight to finish
"""
function show_complete(line::EuclidLine2fHighlight)
    line.current_width[] = line.max_width
end

"""
    hide(line)

Hide highlights of a line in a Euclid diagram

# Arguments
- `line::EuclidLine2fHighlight`: The description of the highlight to completely hide
"""
function hide(line::EuclidLine2fHighlight)
    line.current_width[] = 0f0
end

"""
    animate(line, hide_until, max_at, min_at, t)

Animate highlighting a line in a Euclid diagram

# Arguments
- `line::EuclidLine2fHighlight`: The line to animate in the diagram
- `hide_until::AbstractFloat`: The time point to begin highlighting the line at
- `max_at::AbstractFloat`: The time point to have maximum highlight at
- `min_at::AbstractFloat`: The time point to finish going back to no more highlighting
- `t::AbstractFloat`: The current timeframe of the animation
"""
function animate(
    line::EuclidLine2fHighlight, hide_until::AbstractFloat, max_at::AbstractFloat, min_at::AbstractFloat, t::AbstractFloat)

    perform(t, hide_until, max_at, max_at + 0.00001, min_at,
        () -> line.current_width[] = 0f0,
        () -> line.current_width[] = line.max_width,
        () -> line.current_width[] = 0f0) do i
        if i == 1
            on_t = (t-hide_until)/(max_at-hide_until)
            line.current_width[] = line.max_width * on_t
        else
            on_t = (t-max_at)/(min_at-max_at)
            line.current_width[] = line.max_width- (line.max_width * on_t)
        end
    end
end
