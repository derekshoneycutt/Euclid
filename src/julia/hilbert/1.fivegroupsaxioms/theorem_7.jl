module HilbertChapterOneTheorem7

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const PlaneEdgeLeft = [0f0, 0.58f0, 0f0]
const PlaneEdgeRight = [1f0, 0.58f0, 0f0]
const PlaneTopRight = [1f0, 0.58f0, 0.45f0]
const PlaneTopLeft = [0f0, 0.58f0, 0.45f0]

const LineStart = PlaneEdgeLeft
const LineEnd = PlaneEdgeRight
const PointA = [0.34f0, 0.33f0, 0f0]
const PointB = [0.56f0, 0.78f0, 0f0]
const PointAPrime = [0.63f0, 0.24f0, 0f0]
const PenTopZ = 1.4f0

const AlphaLabelPoint = [0.16f0, 0.58f0, 0.22f0]
const ALabelPoint = PointA + [0.024f0, -0.044f0, 0f0]
const BLabelPoint = PointB + [0.055f0, 0.075f0, 0f0]
const APrimeLabelPoint = PointAPrime + [0.03f0, -0.036f0, 0f0]

const LabelColor = :plum1
const PlaneColor = :steelblue
const PlaneBaseColor = OdinJuliaBridge.bridge_color(PlaneColor)
const PlaneMaxAlpha01 = 0.50f0
const PointAColor = :steelblue
const PointBColor = :palevioletred1
const PointAPrimeColor = :khaki3
const DividerLineColor = PlaneColor
const SegmentABColor = :khaki3
const SegmentAAPrimeColor = :palevioletred1
const FlickerColor = :white
const FlickerSamplesPerFrame = 6
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const StartDelayDuration = 0.30f0
const FadeInDuration = 2.2f0
const DescendDuration = 1.8f0
const DrawLineDuration = 3.8f0
const ArcMoveDuration = 1.9f0
const DrawPointDuration = 1.8f0
const DrawSegmentDuration = 2.3f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

"""Complete immutable state for one Theorem 7 animation generation."""
struct AnimationState
    plane_host_id::Int64
    divider_host_id::Int64
    divider_joint1_id::Int64
    divider_joint2_id::Int64
    point_aid::Int64
    point_bid::Int64
    point_aprime_id::Int64
    segment_abhost_id::Int64
    segment_abjoint1_id::Int64
    segment_abjoint2_id::Int64
    segment_aaprime_host_id::Int64
    segment_aaprime_joint1_id::Int64
    segment_aaprime_joint2_id::Int64
    alpha_label_id::Int64
    alabel_id::Int64
    blabel_id::Int64
    aprime_label_id::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseStartDelay = 0f0
const PhaseFadeInPlane = 1f0
const PhaseDescendToLine = 2f0
const PhaseDrawDividerLine = 3f0
const PhaseMoveToPointA = 4f0
const PhasePutPointA = 5f0
const PhaseMoveToPointB = 6f0
const PhasePutPointB = 7f0
const PhaseDrawSegmentAB = 8f0
const PhaseMoveToPointAPrime = 9f0
const PhasePutPointAPrime = 10f0
const PhaseMoveToPointAForAAPrime = 11f0
const PhaseDrawSegmentAAPrime = 12f0
const PhaseEndLift = 13f0
const PhaseFinalHold = 14f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.plane_host_id,
        state.divider_host_id,
        state.divider_joint1_id,
        state.divider_joint2_id,
        state.point_aid,
        state.point_bid,
        state.point_aprime_id,
        state.segment_abhost_id,
        state.segment_abjoint1_id,
        state.segment_abjoint2_id,
        state.segment_aaprime_host_id,
        state.segment_aaprime_joint1_id,
        state.segment_aaprime_joint2_id,
        state.alpha_label_id,
        state.alabel_id,
        state.blabel_id,
        state.aprime_label_id,
        phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 7

Every plane α divides the remaining points of space into two regions having the following properties: Every point A of the one region determines with each point B of the other region a segment AB, within which lies a point of α. On the other hand, any two points A, A' lying within the same region determine a segment AA' containing no point of α.

...

Making use of the notation of theorem 7, we may now say: The points A, A' are situated in space upon one and the same side of the plane α, and the points A, B are situated in space upon different sides of the plane α.

Theorem 7 gives us the most important facts relating to the order of sequence of the elements of space. These facts are the results, exclusively, of the axioms already considered, and, hence, no new space axioms are required in group II."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 7}

Every plane $\alpha$ divides the remaining points of space into two regions having the following properties: Every point $A$ \euclidpoint[color=steelblue,size=1] of the one region determines with each point $B$ \euclidpoint[color=palevioletred1,size=1] of the other region a segment $AB$ \euclidline[color=khaki3,length=3,thickness=4], within which lies a point of $\alpha$. On the other hand, any two points $A$ \euclidpoint[color=steelblue,size=1], $A'$ \euclidpoint[color=khaki3,size=1] lying within the same region determine a segment $AA'$ \euclidline[color=palevioletred1,length=3,thickness=4] containing no point of $\alpha$.

...

Making use of the notation of \textit{theorem 7}, we may now say: The points $A$ \euclidpoint[color=steelblue,size=1], $A'$ \euclidpoint[color=khaki3,size=1] are situated in space upon one and the same side of the plane $\alpha$, and the points $A$ \euclidpoint[color=steelblue,size=1], $B$ \euclidpoint[color=palevioletred1,size=1] are situated in space upon different sides of the plane $\alpha$.

\textit{Theorem 7} gives us the most important facts relating to the order of sequence of the elements of space. These facts are the results, exclusively, of the axioms already considered, and, hence, no new space axioms are required in \textit{group II}."""
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

"""Pick a random interior point of the plane built from the current vertices."""
function random_plane_point()
    if rand(Float32) < 0.5f0
        return random_triangle_point(PlaneEdgeLeft, PlaneTopLeft, PlaneTopRight)
    end

    random_triangle_point(PlaneEdgeLeft, PlaneTopRight, PlaneEdgeRight)
end

"""Show the plane host point."""
function show_plane(state_ptr::Ptr{Cvoid}, plane_host_id)
    set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
    OdinJuliaBridge.show_point(state_ptr, plane_host_id)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    plane_host_id = state.plane_host_id
    divider_host_id = state.divider_host_id
    divider_joint1_id = state.divider_joint1_id
    divider_joint2_id = state.divider_joint2_id
    point_a_id = state.point_aid
    point_b_id = state.point_bid
    point_a_prime_id = state.point_aprime_id
    segment_a_b_host_id = state.segment_abhost_id
    segment_a_b_joint2_id = state.segment_abjoint2_id
    segment_a_a_prime_host_id = state.segment_aaprime_host_id
    segment_a_a_prime_joint2_id = state.segment_aaprime_joint2_id
    alpha_label_id = state.alpha_label_id
    label_a_id = state.alabel_id
    label_b_id = state.blabel_id
    label_a_prime_id = state.aprime_label_id

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [plane_host_id, divider_host_id,
         point_a_id, point_b_id, point_a_prime_id,
         segment_a_b_host_id, segment_a_a_prime_host_id,
         alpha_label_id, label_a_id, label_b_id, label_a_prime_id])

    set_plane_alpha(state_ptr, plane_host_id, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, divider_joint1_id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, divider_joint2_id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, segment_a_b_joint2_id, PointB)
    OdinJuliaBridge.set_point_position(state_ptr, segment_a_a_prime_joint2_id, PointA)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, DividerLineColor)
    OdinJuliaBridge.lock_pen_joint1(
        state_ptr, LineStart[1], LineStart[2], PenTopZ)
    OdinJuliaBridge.move_pen_joint2(
        state_ptr, LineStart[1], LineStart[2], PenTopZ + 0.14f0)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, 0f0, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})

    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)
    point_a_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointAPrime, PointAPrimeColor, 0f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        APrimeLabelPoint, LabelColor, 16f0)

    divider_line = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, DividerLineColor, 0f0)
    segment_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, PointB, PointB, SegmentABColor, 0f0)
    segment_a_a_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointA, PointA, SegmentAAPrimeColor, 0f0)

    plane_alpha = OdinJuliaBridge.create_new_square(state_ptr,
        PlaneEdgeLeft, PlaneEdgeRight, PlaneTopRight, PlaneTopLeft, PlaneColor)
    alpha_label = OdinJuliaBridge.create_new_label(
        state_ptr, 'α', AlphaLabelPoint, LabelColor, 16f0)


    state = AnimationState(
        plane_alpha.host_id,
        divider_line.host_id,
        divider_line.joint1_id,
        divider_line.joint2_id,
        point_a.index,
        point_b.index,
        point_a_prime.index,
        segment_a_b.host_id,
        segment_a_b.joint1_id,
        segment_a_b.joint2_id,
        segment_a_a_prime.host_id,
        segment_a_a_prime.joint1_id,
        segment_a_a_prime.joint2_id,
        alpha_label.index,
        label_a.index,
        label_b.index,
        label_a_prime.index,
        0f0, 0f0)
    reset_cycle_state(state_ptr, state)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    plane_host_id = state.plane_host_id
    divider_host_id = state.divider_host_id
    divider_joint1_id = state.divider_joint1_id
    divider_joint2_id = state.divider_joint2_id
    point_a_id = state.point_aid
    point_b_id = state.point_bid
    point_a_prime_id = state.point_aprime_id
    segment_a_b_host_id = state.segment_abhost_id
    segment_a_b_joint1_id = state.segment_abjoint1_id
    segment_a_b_joint2_id = state.segment_abjoint2_id
    segment_a_a_prime_host_id = state.segment_aaprime_host_id
    segment_a_a_prime_joint1_id = state.segment_aaprime_joint1_id
    segment_a_a_prime_joint2_id = state.segment_aaprime_joint2_id
    alpha_label_id = state.alpha_label_id
    label_a_id = state.alabel_id
    label_b_id = state.blabel_id
    label_a_prime_id = state.aprime_label_id

    if plane_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseStartDelay
        timer += dt
        if timer >= StartDelayDuration
            phase = PhaseFadeInPlane
            timer = 0f0
        end
    elseif phase == PhaseFadeInPlane
        set_plane_alpha(state_ptr, plane_host_id,
            (timer / FadeInDuration) * PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)

        for _ in 1:FlickerSamplesPerFrame
            sample_pos = random_plane_point()
            OdinJuliaBridge.emit_flicker_particle(state_ptr, sample_pos, FlickerColor)
        end

        if timer >= FadeInDuration * 0.35f0
            OdinJuliaBridge.show_point(state_ptr, alpha_label_id)
        end

        timer += dt
        if timer >= FadeInDuration
            phase = PhaseDescendToLine
            timer = 0f0
        end
    elseif phase == PhaseDescendToLine
        show_plane(state_ptr, plane_host_id)
        OdinJuliaBridge.show_point(state_ptr, alpha_label_id)
        OdinJuliaBridge.show_pen(state_ptr)

        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineStart[1], LineStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawDividerLine
            timer = 0f0
        end
    elseif phase == PhaseDrawDividerLine
        show_plane(state_ptr, plane_host_id)
        OdinJuliaBridge.show_point(state_ptr, alpha_label_id)

        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            LineStart, LineEnd;
            penbrush=LineMaxBrush,
            pencolor=DividerLineColor,
            line_host_id=divider_host_id,
            line_joint1_id=divider_joint1_id,
            line_joint2_id=divider_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)
        OdinJuliaBridge.show_point(state_ptr, alpha_label_id)

        OdinJuliaBridge.show_point(state_ptr, divider_host_id)

        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineEnd, PointA, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
    elseif phase == PhasePutPointA
        OdinJuliaBridge.show_point(state_ptr, divider_host_id)

        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointA,
            PointMaxBrush, PointAColor, point_a_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        OdinJuliaBridge.show_point(state_ptr, divider_host_id)

        fade = (1f0 - (timer / ArcMoveDuration)) * PlaneMaxAlpha01
        set_plane_alpha(state_ptr, plane_host_id, fade)
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            set_plane_alpha(state_ptr, plane_host_id, 0f0)
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhasePutPointB
        OdinJuliaBridge.show_point(state_ptr, divider_host_id)

        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointB,
            PointMaxBrush, PointBColor, point_b_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseDrawSegmentAB
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, SegmentABColor)
        end
    elseif phase == PhaseDrawSegmentAB
        OdinJuliaBridge.show_point(state_ptr, divider_host_id)
        OdinJuliaBridge.show_point(state_ptr, plane_host_id)
        OdinJuliaBridge.show_point(state_ptr, alpha_label_id)

        fade = (timer / DrawSegmentDuration) * PlaneMaxAlpha01
        set_plane_alpha(state_ptr, plane_host_id, fade)

        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawSegmentDuration,
            PointB, PointA;
            penbrush=LineMaxBrush,
            pencolor=SegmentABColor,
            line_host_id=segment_a_b_host_id,
            line_joint1_id=segment_a_b_joint1_id,
            line_joint2_id=segment_a_b_joint2_id)

        timer += dt
        if timer >= DrawSegmentDuration
            set_plane_alpha(state_ptr, plane_host_id, PlaneMaxAlpha01)
            phase = PhaseMoveToPointAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAPrime
        OdinJuliaBridge.show_point(state_ptr, divider_host_id)

        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
        end
    elseif phase == PhasePutPointAPrime
        OdinJuliaBridge.show_point(state_ptr, divider_host_id)

        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointAPrime,
            PointMaxBrush, PointAPrimeColor, point_a_prime_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointAForAAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAForAAPrime
        OdinJuliaBridge.show_point(state_ptr, divider_host_id)

        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointA, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawSegmentAAPrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, SegmentAAPrimeColor)
        end
    elseif phase == PhaseDrawSegmentAAPrime
        OdinJuliaBridge.show_point(state_ptr, divider_host_id)

        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawSegmentDuration,
            PointA, PointAPrime;
            penbrush=LineMaxBrush,
            pencolor=SegmentAAPrimeColor,
            line_host_id=segment_a_a_prime_host_id,
            line_joint1_id=segment_a_a_prime_joint1_id,
            line_joint2_id=segment_a_a_prime_joint2_id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        OdinJuliaBridge.show_point(state_ptr, divider_host_id)

        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointAPrime[1], PointAPrime[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
        OdinJuliaBridge.show_point(state_ptr, divider_host_id)

        timer += dt
        if timer >= FinalHoldDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            reset_cycle_state(state_ptr, state)
            return
        end
    end

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, phase, timer))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
end

end