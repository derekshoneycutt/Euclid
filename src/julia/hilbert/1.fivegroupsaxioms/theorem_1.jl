module HilbertChapterOneTheorem1

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidGeometry
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop, animation_entry

const PlaneEdgeLeft = [0.18f0, 0.58f0, 0f0]
const PlaneEdgeRight = [0.82f0, 0.58f0, 0f0]
const PlaneTopRight = [0.82f0, 0.58f0, 0.45f0]
const PlaneTopLeft = [0.18f0, 0.58f0, 0.45f0]

const LineAStart = [0.18f0, 0.58f0, 0f0]
const LineAEnd = [0.82f0, 0.58f0, 0f0]
const LineBStart = [0.34f0, 0.78f0, 0f0]
const LineBEnd = [0.56f0, 0.36f0, 0f0]
const IntersectionPoint =
    line_intersection_3d(LineAStart, LineAEnd, LineBStart, LineBEnd)
const PenTopZ = 1.4f0

const PlaneColor = :palevioletred1
const PlaneBaseColor = OdinJuliaBridge.bridge_color(PlaneColor)
const PlaneMaxAlpha01 = 0.45f0
const FlickerColor = :palevioletred1
const FlickerSamplesPerFrame = 8

const LineAColor = :steelblue
const LineBColor = :palevioletred1
const IntersectionColor = :khaki3
const HighlightColor = :grey60
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const FadeInDuration = 2.5f0
const DescendDuration = 1.8f0
const LineDrawDuration = 4.2f0
const MoveToLineBDuration = 2.0f0
const PointTrailDuration = 2.0f0
const PlaneRevealDuration = 2.5f0
const PlaneHoldDuration = 0.8f0
const SurfaceSweepDuration = 3.6f0
const SurfaceHoverDuration = 1.8f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 1.2f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one Theorem 1 animation generation."""
struct AnimationState
    plane::Int64
    line_a::LineIds
    line_b::LineIds
    intersection_point::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawLineA = 1f0
const PhaseMoveToLineB = 2f0
const PhaseDrawLineB = 3f0
const PhaseMoveToIntersection = 4f0
const PhaseDrawIntersection = 5f0
const PhasePlaneReveal = 6f0
const PhaseSweepSurface = 8f0
const PhaseMoveToIntersectionHover = 9f0
const PhaseHoverIntersection = 10f0
const PhaseEndLift = 11f0
const PhaseFinalHold = 12f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.plane, state.line_a, state.line_b, state.intersection_point,
        phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 1

Two straight lines of a plane have either one point or no point in common; two planes have no point in common or a straight line in common; a plane and a straight line not lying in it have no point or one point in common."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 1}

Two straight lines \euclidline[color=steelblue,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] of a plane have either one point \euclidpoint[color=khaki3,size=1] or no point in common; two planes have no point in common or a straight line in common; a plane and a straight line not lying in it have no point or one point in common."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Set the plane's fill alpha from a normalized [0, 1] opacity."""
function set_plane_alpha(state_ptr::Ptr{Cvoid}, host_id, alpha01)
    t = clamp(alpha01, 0f0, PlaneMaxAlpha01)
    alpha = UInt8(round(Int, PlaneBaseColor.a * t))
    color = OdinJuliaBridge.BridgeColor(
        PlaneBaseColor.r,
        PlaneBaseColor.g,
        PlaneBaseColor.b,
        alpha)
    OdinJuliaBridge.set_point_color(state_ptr, host_id, color)
end

"""Pick a random interior point of the triangle with vertices a, b, and c."""
function random_triangle_point(
    a::Vector{Float32}, b::Vector{Float32}, c::Vector{Float32})
    u = rand(Float32)
    v = rand(Float32)

    if u + v > 1f0
        u = 1f0 - u
        v = 1f0 - v
    end

    [
        a[1] + u * (b[1] - a[1]) + v * (c[1] - a[1]),
        a[2] + u * (b[2] - a[2]) + v * (c[2] - a[2]),
        a[3] + u * (b[3] - a[3]) + v * (c[3] - a[3]),
    ]
end

"""Pick a random interior point of the vertical plane built from the current vertices."""
function random_vertical_plane_point()
    if rand(Float32) < 0.5f0
        return random_triangle_point(PlaneEdgeLeft, PlaneTopLeft, PlaneTopRight)
    end

    random_triangle_point(PlaneEdgeLeft, PlaneTopRight, PlaneEdgeRight)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    plane_host_id = state.plane
    line_a_host_id = state.line_a.host
    line_a_joint1_id = state.line_a.joint1
    line_a_joint2_id = state.line_a.joint2
    line_b_host_id = state.line_b.host
    line_b_joint1_id = state.line_b.joint1
    line_b_joint2_id = state.line_b.joint2
    intersection_point_id = state.intersection_point

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [plane_host_id, line_a_host_id, line_b_host_id, intersection_point_id])

    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_joint1_id, LineAStart[1], LineAStart[2], LineAStart[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line_a_joint2_id, LineAStart[1], LineAStart[2], LineAStart[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line_b_joint1_id, LineBStart[1], LineBStart[2], LineBStart[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line_b_joint2_id, LineBStart[1], LineBStart[2], LineBStart[3])

    set_plane_alpha(state_ptr, plane_host_id, 0f0)
    OdinJuliaBridge.hide_point(state_ptr, plane_host_id)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line_a = OdinJuliaBridge.create_new_line(
        state_ptr, LineAStart, LineAStart, LineAColor, 0f0)
    line_b = OdinJuliaBridge.create_new_line(
        state_ptr, LineBStart, LineBStart, LineBColor, 0f0)
    intersection_point = OdinJuliaBridge.create_new_point(
        state_ptr, IntersectionPoint, IntersectionColor, 0f0)
    plane_beta = OdinJuliaBridge.create_new_square(state_ptr,
        PlaneEdgeLeft, PlaneEdgeRight, PlaneTopRight, PlaneTopLeft, PlaneColor)

    state = AnimationState(
        plane_beta.host_id,
        LineIds(line_a.host_id, line_a.joint1_id, line_a.joint2_id),
        LineIds(line_b.host_id, line_b.joint1_id, line_b.joint2_id),
        intersection_point.index, PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    plane_host_id = state.plane
    line_a_host_id = state.line_a.host
    line_a_joint1_id = state.line_a.joint1
    line_a_joint2_id = state.line_a.joint2
    line_b_host_id = state.line_b.host
    line_b_joint1_id = state.line_b.joint1
    line_b_joint2_id = state.line_b.joint2
    intersection_point_id = state.intersection_point

    if plane_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineAStart[1], LineAStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLineA
            timer = 0f0
        end
    elseif phase == PhaseDrawLineA
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            LineAStart, LineAEnd;
            penbrush=LineMaxBrush,
            pencolor=LineAColor,
            line_host_id=line_a_host_id,
            line_joint1_id=line_a_joint1_id,
            line_joint2_id=line_a_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseMoveToLineB
            timer = 0f0
        end
    elseif phase == PhaseMoveToLineB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToLineBDuration,
            LineAEnd, LineBStart, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToLineBDuration
            phase = PhaseDrawLineB
            timer = 0f0
        end
    elseif phase == PhaseDrawLineB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            LineBStart, LineBEnd;
            penbrush=LineMaxBrush,
            pencolor=LineBColor,
            line_host_id=line_b_host_id,
            line_joint1_id=line_b_joint1_id,
            line_joint2_id=line_b_joint2_id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseMoveToIntersection
            timer = 0f0
        end
    elseif phase == PhaseMoveToIntersection
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToLineBDuration,
            LineBEnd, IntersectionPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToLineBDuration
            phase = PhaseDrawIntersection
            timer = 0f0
        end
    elseif phase == PhaseDrawIntersection
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointTrailDuration, IntersectionPoint,
            PointMaxBrush, IntersectionColor, intersection_point_id)

        timer += dt
        if timer >= PointTrailDuration
            phase = PhasePlaneReveal
            timer = 0f0
        end
    elseif phase == PhasePlaneReveal
        set_plane_alpha(state_ptr, plane_host_id,
            (timer / PlaneRevealDuration) * PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)

        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, PlaneRevealDuration,
            IntersectionPoint, LineAStart, 0.25f0, 1, :none)

        for _ in 1:FlickerSamplesPerFrame
            sample_pos = random_vertical_plane_point()
            OdinJuliaBridge.emit_flicker_particle(state_ptr, sample_pos, FlickerColor)
        end

        timer += dt
        if timer >= PlaneRevealDuration
            phase = PhaseSweepSurface
            timer = 0f0
            set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        end
    elseif phase == PhaseSweepSurface
        set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)

        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, SurfaceSweepDuration,
            LineAStart, LineAEnd, HighlightColor)

        timer += dt
        if timer >= SurfaceSweepDuration
            phase = PhaseMoveToIntersectionHover
            timer = 0f0
        end
    elseif phase == PhaseMoveToIntersectionHover
        set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)

        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToLineBDuration,
            LineAEnd, IntersectionPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToLineBDuration
            phase = PhaseHoverIntersection
            timer = 0f0
        end
    elseif phase == PhaseHoverIntersection
        set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)

        EuclidAnimations.animate_highlight_point(state_ptr, timer, SurfaceHoverDuration,
            IntersectionPoint, HighlightColor)

        timer += dt
        if timer >= SurfaceHoverDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)

        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ,
            IntersectionPoint[1], IntersectionPoint[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
        set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)
        OdinJuliaBridge.show_pen(state_ptr)
        OdinJuliaBridge.set_pen_active(state_ptr, 0, LineAColor)

        timer += dt
        if timer >= FinalHoldDuration
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
end


"""Dispatch one bridge-stable lifecycle operation for this animation."""
function animation_entry(
    state_ptr::Ptr{Cvoid}, operation::Int32, dt::Float32)::Bool

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        initialize(state_ptr)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK
        loop(state_ptr, dt)
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
        clean(state_ptr)
    else
        return false
    end
    return true
end

end
