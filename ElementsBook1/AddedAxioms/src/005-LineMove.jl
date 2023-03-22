"""
    EuclidLine2fMove

Describes moving a line in a Euclid diagram
"""
mutable struct EuclidLine2fMove
    baseOn::EuclidLine2f
    begin_at::Point2f
    move_to::Point2f
    vector::Point2f
    movingA::Bool
end

"""
    move(line, new_spot[, begin_at, move_extremityA=true])

Set up a movement of a line on the Euclid diagram

# Arguments
- `line::EuclidLine2f`: The line to move in the diagram
- `new_spot::Point2f`: The new spot to move the line in the diagram to
- `move_extremityA::Bool`: Whether to move the line by dragging extremity A. Will move by extremity B if false.
- `begin_at::Point2f`: The point to start the movements at (defaults to current location at time of definition)
"""
function move(line::EuclidLine2f, new_spot::Point2f;
    move_extremityA::Bool=true, begin_at::Point2f=line.extremityA[])

    move_extremity = move_extremityA ? line.extremityA[] : line.extremityB[]
    alt_extremity = move_extremityA ? line.extremityB[] : line.extremityA[]
    v = alt_extremity - move_extremity
    EuclidLine2fMove(line, begin_at, new_spot, v, move_extremityA)
end

"""
    reset(move[, begin_at, move_to, move_extremityA=true])

Reset a movement animation for a line in a Euclid Diagram to new positions

# Arguments
- `move::EuclidLine2fMove`: The description of the move to reset
- `begin_at::Point2f`: The point to begin movements at in the diagram
- `move_to::Point2f`: The point to end movements to in the diagram
- `move_extremityA::Bool`: Whether to move the line by dragging extremity A. Will move by extremity B if false.
"""
function reset(move::EuclidLine2fMove;
    begin_at::Point2f=move.baseOn.extremityA[], move_to::Point2f=move.move_to, move_extremityA::Bool=true)

    move.begin_at = begin_at
    move.move_to = move_to
    move_extremity = move_extremityA ? line.extremityA[] : line.extremityB[]
    alt_extremity = move_extremityA ? line.extremityB[] : line.extremityA[]
    v = alt_extremity - move_extremity
    move.vector = v
    move.movingA = move_extremityA
end

"""
    show_complete(move)

Complete a previously defined move operation for a line in a Euclid diagram

# Arguments
- `move::EuclidLine2fMove`: The description of the move to finish moving
"""
function show_complete(move::EuclidLine2fMove)
    if move.movingA
        move.baseOn.extremityA[] = move.move_to
        move.baseOn.extremityB[] = move.move_to + move.vector
    else
        move.baseOn.extremityB[] = move.move_to
        move.baseOn.extremityA[] = move.move_to + move.vector
    end
end

"""
    hide(move)

Move a line in a Euclid diagram back to its starting position

# Arguments
- `move::EuclidLine2fMove`: The description of the move to "undo"
"""
function hide(move::EuclidLine2fMove)
    if move.movingA
        move.baseOn.extremityA[] = move.begin_at
        move.baseOn.extremityB[] = move.begin_at + move.vector
    else
        move.baseOn.extremityB[] = move.begin_at
        move.baseOn.extremityA[] = move.begin_at + move.vector
    end
end

"""
    animate(move, begin_move, end_move, t)

Animate moving a line drawn in a Euclid diagram

# Arguments
- `move::EuclidLine2fMove`: The line to animate in the diagram
- `begin_move::AbstractFloat`: The time point to begin moving the line at
- `end_move::AbstractFloat`: The time point to finish moving the line at
- `t::AbstractFloat`: The current timeframe of the animation
"""
function animate(
    move::EuclidLine2fMove,
    begin_move::AbstractFloat, end_move::AbstractFloat, t::AbstractFloat)

    begin_at = move.begin_at
    move_to = move.move_to
    v = move_to - begin_at
    norm_v = norm(v)
    u = v / norm_v

    perform(t, begin_move, end_move,
         () -> nothing,
         () -> nothing) do
        on_t = ((t-begin_move)/(end_move-begin_move)) * norm_v
        if on_t > 0
            x,y = begin_at + on_t * u
            if move.movingA
                move.baseOn.extremityA[] = Point2f0(x, y)
                move.baseOn.extremityB[] = Point2f0(x, y) + move.vector
            else
                move.baseOn.extremityB[] = Point2f0(x, y)
                move.baseOn.extremityA[] = Point2f0(x, y) + move.vector
            end
        else
            if move.movingA
                move.baseOn.extremityA[] = move_to
                move.baseOn.extremityB[] = move_to + move.vector
            else
                move.baseOn.extremityB[] = move_to
                move.baseOn.extremityA[] = move_to + move.vector
            end
        end
    end
end
