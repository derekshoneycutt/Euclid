module HilbertChapterOneAxiomIV5

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const VertexO = [0.18f0, 0.68f0, 0f0]
const VertexOPrime = [0.42f0, 0.50f0, 0f0]
const VertexODoublePrime = [0.66f0, 0.30f0, 0f0]
const RayLength = 0.32f0
const AngleTheta = 0.98f0

const RayHStart = VertexO
const RayHEnd = [VertexO[1] + RayLength, VertexO[2], 0f0]
const RayKStart = VertexO
const RayKEnd = [
    VertexO[1] + RayLength * cos(AngleTheta),
    VertexO[2] + RayLength * sin(AngleTheta),
    0f0,
]

const RayHPrimeStart = VertexOPrime
const RayHPrimeEnd = [VertexOPrime[1] + RayLength, VertexOPrime[2], 0f0]
const RayKPrimeStart = VertexOPrime
const RayKPrimeEnd = [
    VertexOPrime[1] + RayLength * cos(AngleTheta),
    VertexOPrime[2] + RayLength * sin(AngleTheta),
    0f0,
]

const RayHDoublePrimeStart = VertexODoublePrime
const RayHDoublePrimeEnd = [VertexODoublePrime[1] + RayLength, VertexODoublePrime[2], 0f0]
const RayKDoublePrimeStart = VertexODoublePrime
const RayKDoublePrimeEnd = [
    VertexODoublePrime[1] + RayLength * cos(AngleTheta),
    VertexODoublePrime[2] + RayLength * sin(AngleTheta),
    0f0,
]

const MarkerRadius = 0.11f0
const Marker1Start = [VertexO[1] + MarkerRadius, VertexO[2], 0f0]
const Marker1End = [
    VertexO[1] + MarkerRadius * cos(AngleTheta),
    VertexO[2] + MarkerRadius * sin(AngleTheta),
    0f0,
]
const Marker2Start = [VertexOPrime[1] + MarkerRadius, VertexOPrime[2], 0f0]
const Marker2End = [
    VertexOPrime[1] + MarkerRadius * cos(AngleTheta),
    VertexOPrime[2] + MarkerRadius * sin(AngleTheta),
    0f0,
]
const Marker3Start = [VertexODoublePrime[1] + MarkerRadius, VertexODoublePrime[2], 0f0]
const Marker3End = [
    VertexODoublePrime[1] + MarkerRadius * cos(AngleTheta),
    VertexODoublePrime[2] + MarkerRadius * sin(AngleTheta),
    0f0,
]

const LabelColor = :plum1
const HighlightColor = :lightgreen
const RayHColor = :steelblue
const RayKColor = :palevioletred1
const RayHPrimeColor = :grey60
const RayKPrimeColor = :steelblue
const RayHDoublePrimeColor = :palevioletred1
const RayKDoublePrimeColor = :steelblue
const MarkerColor = :khaki3

const RayBrush = 5f0
const MarkerBrush = 1f0
const ResetPenLength = 0.14f0

const LabelOPoint = VertexO + [-0.02f0, 0.07f0, 0f0]
const LabelHPoint = RayHEnd + [0.02f0, 0.055f0, 0f0]
const LabelKPoint = RayKEnd + [0.02f0, 0.055f0, 0f0]
const LabelOPrimePoint = VertexOPrime + [-0.02f0, 0.07f0, 0f0]
const LabelHPrimePoint = RayHPrimeEnd + [0.02f0, 0.055f0, 0f0]
const LabelKPrimePoint = RayKPrimeEnd + [0.02f0, 0.055f0, 0f0]
const LabelODoublePrimePoint = VertexODoublePrime + [-0.02f0, 0.07f0, 0f0]
const LabelHDoublePrimePoint = RayHDoublePrimeEnd + [0.02f0, 0.055f0, 0f0]
const LabelKDoublePrimePoint = RayKDoublePrimeEnd + [0.02f0, 0.055f0, 0f0]

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const DescendDuration = 1.8f0
const DrawRayDuration = 2.4f0
const ArcMoveDuration = 1.4f0
const PenLiftDuration = 1.6f0
const MarkerDrawDuration = 1.2f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 1.0f0
const FinalHoldDuration = 0.9f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Stable native handles for one filled-circle marker."""
struct CircleIds
    host::Int64
    start::Int64
    finish::Int64
end

"""Complete immutable state for one Axiom IV,5 animation generation."""
struct AnimationState
    ray_h::LineIds
    ray_k::LineIds
    ray_h_prime::LineIds
    ray_k_prime::LineIds
    ray_h_double_prime::LineIds
    ray_k_double_prime::LineIds
    marker1::CircleIds
    marker2::CircleIds
    marker3::CircleIds
    label_o::Int64
    label_h::Int64
    label_k::Int64
    label_o_prime::Int64
    label_h_prime::Int64
    label_k_prime::Int64
    label_o_double_prime::Int64
    label_h_double_prime::Int64
    label_k_double_prime::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescendToO = 0f0
const PhaseDrawRayH = 1f0
const PhaseArcToOForK = 2f0
const PhaseDrawRayK = 3f0
const PhasePenLiftForMarker1 = 4f0
const PhaseDrawMarker1 = 5f0
const PhaseCompassLiftAfterMarker1 = 6f0
const PhaseDescendToOPrime = 7f0
const PhaseDrawRayHPrime = 8f0
const PhaseArcToOPrimeForKPrime = 9f0
const PhaseDrawRayKPrime = 10f0
const PhasePenLiftForMarker2 = 11f0
const PhaseDrawMarker2 = 12f0
const PhaseCompassLiftAfterMarker2 = 13f0
const PhaseDescendToODoublePrime = 14f0
const PhaseDrawRayHDoublePrime = 15f0
const PhaseArcToODoublePrimeForKDoublePrime = 16f0
const PhaseDrawRayKDoublePrime = 17f0
const PhasePenLiftForMarker3 = 18f0
const PhaseDrawMarker3 = 19f0
const PhaseCompassArc3To1 = 20f0
const PhaseHighlightA1Forward = 21f0
const PhaseHighlightA1Back = 22f0
const PhaseCompassArc1To2 = 23f0
const PhaseHighlightB1Forward = 24f0
const PhaseHighlightB1Back = 25f0
const PhaseCompassArc2To1 = 26f0
const PhaseHighlightA2Forward = 27f0
const PhaseHighlightA2Back = 28f0
const PhaseCompassArc1To3 = 29f0
const PhaseHighlightC1Forward = 30f0
const PhaseHighlightC1Back = 31f0
const PhaseCompassArc3To2 = 32f0
const PhaseHighlightB2Forward = 33f0
const PhaseHighlightB2Back = 34f0
const PhaseCompassArc2To3 = 35f0
const PhaseHighlightC2Forward = 36f0
const PhaseHighlightC2Back = 37f0
const PhaseCompassLiftEnd = 38f0
const PhaseFinalHold = 39f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.ray_h, state.ray_k, state.ray_h_prime, state.ray_k_prime,
        state.ray_h_double_prime, state.ray_k_double_prime, state.marker1,
        state.marker2, state.marker3, state.label_o, state.label_h, state.label_k,
        state.label_o_prime, state.label_h_prime, state.label_k_prime,
        state.label_o_double_prime, state.label_h_double_prime,
        state.label_k_double_prime, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom IV,5

IV, 5. If the angle (h, k) is congruent to the angle (h', k') and to the angle (h'', k''), then the angle (h', k') is congruent to the angle (h'', k''); that is to say, if ∠(h, k) ≡ ∠(h', k') and ∠(h, k) ≡ ∠(h'', k''), then ∠(h', k') ≡ ∠(h'', k'')."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom IV,5}

\textbf{IV, 5.} If the angle $(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] is
congruent to the angle $(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] and to
the angle $(h'', k'')$ \euclidangle[color=khaki3,radius=2,end=60,filled], then the angle
$(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] is congruent to the angle
$(h'', k'')$ \euclidangle[color=khaki3,radius=2,end=60,filled]; that is to say, if
$\angle(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] $\equiv \angle(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled]
and $\angle(h, k)$ \euclidangle[color=khaki3,radius=2,end=60,filled] $\equiv \angle(h'', k'')$ \euclidangle[color=khaki3,radius=2,end=60,filled],
then $\angle(h', k')$ \euclidangle[color=khaki3,radius=2,end=60,filled] $\equiv \angle(h'', k'')$ \euclidangle[color=khaki3,radius=2,end=60,filled]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle and transactionally publish its initial timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    ray_h_host_id = state.ray_h.host
    ray_h_joint2_id = state.ray_h.joint2
    ray_k_host_id = state.ray_k.host
    ray_k_joint2_id = state.ray_k.joint2
    ray_h_prime_host_id = state.ray_h_prime.host
    ray_h_prime_joint2_id = state.ray_h_prime.joint2
    ray_k_prime_host_id = state.ray_k_prime.host
    ray_k_prime_joint2_id = state.ray_k_prime.joint2
    ray_h_double_prime_host_id = state.ray_h_double_prime.host
    ray_h_double_prime_joint2_id = state.ray_h_double_prime.joint2
    ray_k_double_prime_host_id = state.ray_k_double_prime.host
    ray_k_double_prime_joint2_id = state.ray_k_double_prime.joint2

    marker1_host_id = state.marker1.host
    marker1_end_id = state.marker1.finish
    marker2_host_id = state.marker2.host
    marker2_end_id = state.marker2.finish
    marker3_host_id = state.marker3.host
    marker3_end_id = state.marker3.finish

    label_o_id = state.label_o
    label_h_id = state.label_h
    label_k_id = state.label_k
    label_o_prime_id = state.label_o_prime
    label_h_prime_id = state.label_h_prime
    label_k_prime_id = state.label_k_prime
    label_o_double_prime_id = state.label_o_double_prime
    label_h_double_prime_id = state.label_h_double_prime
    label_k_double_prime_id = state.label_k_double_prime

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [ray_h_host_id, ray_k_host_id, ray_h_prime_host_id, ray_k_prime_host_id,
         ray_h_double_prime_host_id, ray_k_double_prime_host_id,
         marker1_host_id, marker2_host_id, marker3_host_id,
         label_o_id, label_h_id, label_k_id,
         label_o_prime_id, label_h_prime_id, label_k_prime_id,
         label_o_double_prime_id, label_h_double_prime_id, label_k_double_prime_id])

    OdinJuliaBridge.set_point_position(state_ptr, ray_h_joint2_id, RayHStart)
    OdinJuliaBridge.set_point_position(state_ptr, ray_k_joint2_id, RayKStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, ray_h_prime_joint2_id, RayHPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, ray_k_prime_joint2_id, RayKPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, ray_h_double_prime_joint2_id, RayHDoublePrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, ray_k_double_prime_joint2_id, RayKDoublePrimeStart)

    OdinJuliaBridge.set_point_position(state_ptr, marker1_end_id, Marker1Start)
    OdinJuliaBridge.set_point_position(state_ptr, marker2_end_id, Marker2Start)
    OdinJuliaBridge.set_point_position(state_ptr, marker3_end_id, Marker3Start)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescendToO, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(state_ptr, VertexO[1], VertexO[2], PenTopZ)
    OdinJuliaBridge.move_pen_joint2(
        state_ptr, VertexO[1], VertexO[2], PenTopZ + ResetPenLength)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, VertexO[1], VertexO[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, Marker1Start[1], Marker1Start[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    ray_h = OdinJuliaBridge.create_new_line(
        state_ptr, RayHStart, RayHStart,
        RayHColor, 0f0)
    ray_k = OdinJuliaBridge.create_new_line(
        state_ptr, RayKStart, RayKStart,
        RayKColor, 0f0)
    ray_h_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RayHPrimeStart, RayHPrimeStart,
        RayHPrimeColor, 0f0)
    ray_k_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RayKPrimeStart, RayKPrimeStart,
        RayKPrimeColor, 0f0)
    ray_h_double_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RayHDoublePrimeStart, RayHDoublePrimeStart,
        RayHDoublePrimeColor, 0f0)
    ray_k_double_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RayKDoublePrimeStart, RayKDoublePrimeStart,
        RayKDoublePrimeColor, 0f0)

    marker1 = OdinJuliaBridge.create_new_filledcircle(state_ptr,
        VertexO, MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)
    marker2 = OdinJuliaBridge.create_new_filledcircle(state_ptr,
        VertexOPrime, MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)
    marker3 = OdinJuliaBridge.create_new_filledcircle(state_ptr,
        VertexODoublePrime, MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)

    label_o = OdinJuliaBridge.create_new_label(
        state_ptr, 'O', LabelOPoint, LabelColor, 16f0)
    label_h = OdinJuliaBridge.create_new_label(
        state_ptr, 'h', LabelHPoint, LabelColor, 16f0)
    label_k = OdinJuliaBridge.create_new_label(
        state_ptr, 'k', LabelKPoint, LabelColor, 16f0)

    label_o_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'O', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelOPrimePoint, LabelColor, 16f0)
    label_h_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'h', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelHPrimePoint, LabelColor, 16f0)
    label_k_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'k', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelKPrimePoint, LabelColor, 16f0)

    label_o_double_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'O', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelODoublePrimePoint, LabelColor, 16f0)
    label_h_double_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'h', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelHDoublePrimePoint, LabelColor, 16f0)
    label_k_double_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'k', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelKDoublePrimePoint, LabelColor, 16f0)

    state = AnimationState(
        LineIds(ray_h.host_id, ray_h.joint1_id, ray_h.joint2_id),
        LineIds(ray_k.host_id, ray_k.joint1_id, ray_k.joint2_id),
        LineIds(ray_h_prime.host_id, ray_h_prime.joint1_id, ray_h_prime.joint2_id),
        LineIds(ray_k_prime.host_id, ray_k_prime.joint1_id, ray_k_prime.joint2_id),
        LineIds(ray_h_double_prime.host_id, ray_h_double_prime.joint1_id,
            ray_h_double_prime.joint2_id),
        LineIds(ray_k_double_prime.host_id, ray_k_double_prime.joint1_id,
            ray_k_double_prime.joint2_id),
        CircleIds(marker1.host_id, marker1.start_id, marker1.end_id),
        CircleIds(marker2.host_id, marker2.start_id, marker2.end_id),
        CircleIds(marker3.host_id, marker3.start_id, marker3.end_id),
        label_o.index, label_h.index, label_k.index, label_o_prime.index,
        label_h_prime.index, label_k_prime.index, label_o_double_prime.index,
        label_h_double_prime.index, label_k_double_prime.index, PhaseDescendToO, 0f0)
    reset_cycle_state(state_ptr, state)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    ray_h_host_id = state.ray_h.host
    ray_h_joint1_id = state.ray_h.joint1
    ray_h_joint2_id = state.ray_h.joint2
    ray_k_host_id = state.ray_k.host
    ray_k_joint1_id = state.ray_k.joint1
    ray_k_joint2_id = state.ray_k.joint2
    ray_h_prime_host_id = state.ray_h_prime.host
    ray_h_prime_joint1_id = state.ray_h_prime.joint1
    ray_h_prime_joint2_id = state.ray_h_prime.joint2
    ray_k_prime_host_id = state.ray_k_prime.host
    ray_k_prime_joint1_id = state.ray_k_prime.joint1
    ray_k_prime_joint2_id = state.ray_k_prime.joint2
    ray_h_double_prime_host_id = state.ray_h_double_prime.host
    ray_h_double_prime_joint1_id = state.ray_h_double_prime.joint1
    ray_h_double_prime_joint2_id = state.ray_h_double_prime.joint2
    ray_k_double_prime_host_id = state.ray_k_double_prime.host
    ray_k_double_prime_joint1_id = state.ray_k_double_prime.joint1
    ray_k_double_prime_joint2_id = state.ray_k_double_prime.joint2

    marker1_host_id = state.marker1.host
    marker1_start_id = state.marker1.start
    marker1_end_id = state.marker1.finish
    marker2_host_id = state.marker2.host
    marker2_start_id = state.marker2.start
    marker2_end_id = state.marker2.finish
    marker3_host_id = state.marker3.host
    marker3_start_id = state.marker3.start
    marker3_end_id = state.marker3.finish

    label_o_id = state.label_o
    label_h_id = state.label_h
    label_k_id = state.label_k
    label_o_prime_id = state.label_o_prime
    label_h_prime_id = state.label_h_prime
    label_k_prime_id = state.label_k_prime
    label_o_double_prime_id = state.label_o_double_prime
    label_h_double_prime_id = state.label_h_double_prime
    label_k_double_prime_id = state.label_k_double_prime

    if ray_h_host_id < 0 || ray_k_host_id < 0 ||
       ray_h_prime_host_id < 0 || ray_k_prime_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescendToO
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, VertexO[1], VertexO[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawRayH
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_o_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
        end
    elseif phase == PhaseDrawRayH
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawRayDuration,
            RayHStart, RayHEnd;
            penbrush=RayBrush,
            pencolor=RayHColor,
            line_host_id=ray_h_host_id,
            line_joint1_id=ray_h_joint1_id,
            line_joint2_id=ray_h_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhaseArcToOForK
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_h_id)
        end
    elseif phase == PhaseArcToOForK
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            RayHEnd, VertexO, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawRayK
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKColor)
        end
    elseif phase == PhaseDrawRayK
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawRayDuration,
            RayKStart, RayKEnd;
            penbrush=RayBrush,
            pencolor=RayKColor,
            line_host_id=ray_k_host_id,
            line_joint1_id=ray_k_joint1_id,
            line_joint2_id=ray_k_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhasePenLiftForMarker1
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_k_id)
        end
    elseif phase == PhasePenLiftForMarker1
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, RayKEnd[1], RayKEnd[2])
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            VertexO[1], VertexO[2], Marker1Start[1], Marker1Start[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseDrawMarker1
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker1
        EuclidAnimations.animate_draw_filledcircle(state_ptr,
            timer, MarkerDrawDuration, VertexO,
            Marker1Start, AngleTheta, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
            marker_host_id=marker1_host_id,
            marker_start_id=marker1_start_id,
            marker_end_id=marker1_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassLiftAfterMarker1
            timer = 0f0
        end
    elseif phase == PhaseCompassLiftAfterMarker1
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            VertexO[1], VertexO[2], Marker1End[1], Marker1End[2])

        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            OdinJuliaBridge.show_pen(state_ptr)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHPrimeColor)
            phase = PhaseDescendToOPrime
            timer = 0f0
        end
    elseif phase == PhaseDescendToOPrime
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, VertexOPrime[1], VertexOPrime[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawRayHPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_o_prime_id)
        end
    elseif phase == PhaseDrawRayHPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawRayDuration,
            RayHPrimeStart, RayHPrimeEnd;
            penbrush=RayBrush,
            pencolor=RayHPrimeColor,
            line_host_id=ray_h_prime_host_id,
            line_joint1_id=ray_h_prime_joint1_id,
            line_joint2_id=ray_h_prime_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhaseArcToOPrimeForKPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_h_prime_id)
        end
    elseif phase == PhaseArcToOPrimeForKPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            RayHPrimeEnd, VertexOPrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawRayKPrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKPrimeColor)
        end
    elseif phase == PhaseDrawRayKPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawRayDuration,
            RayKPrimeStart, RayKPrimeEnd;
            penbrush=RayBrush,
            pencolor=RayKPrimeColor,
            line_host_id=ray_k_prime_host_id,
            line_joint1_id=ray_k_prime_joint1_id,
            line_joint2_id=ray_k_prime_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhasePenLiftForMarker2
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_k_prime_id)
        end
    elseif phase == PhasePenLiftForMarker2
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, RayKPrimeEnd[1], RayKPrimeEnd[2])
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            VertexOPrime[1], VertexOPrime[2], Marker2Start[1], Marker2Start[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseDrawMarker2
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker2
        EuclidAnimations.animate_draw_filledcircle(state_ptr,
            timer, MarkerDrawDuration, VertexOPrime,
            Marker2Start, AngleTheta, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
            marker_host_id=marker2_host_id,
            marker_start_id=marker2_start_id,
            marker_end_id=marker2_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassLiftAfterMarker2
            timer = 0f0
        end
    elseif phase == PhaseCompassLiftAfterMarker2
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            VertexOPrime[1], VertexOPrime[2], Marker2End[1], Marker2End[2])

        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            OdinJuliaBridge.show_pen(state_ptr)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHDoublePrimeColor)
            phase = PhaseDescendToODoublePrime
            timer = 0f0
        end
    elseif phase == PhaseDescendToODoublePrime
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ,
            VertexODoublePrime[1], VertexODoublePrime[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawRayHDoublePrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_o_double_prime_id)
        end
    elseif phase == PhaseDrawRayHDoublePrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawRayDuration,
            RayHDoublePrimeStart, RayHDoublePrimeEnd;
            penbrush=RayBrush,
            pencolor=RayHDoublePrimeColor,
            line_host_id=ray_h_double_prime_host_id,
            line_joint1_id=ray_h_double_prime_joint1_id,
            line_joint2_id=ray_h_double_prime_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhaseArcToODoublePrimeForKDoublePrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_h_double_prime_id)
        end
    elseif phase == PhaseArcToODoublePrimeForKDoublePrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            RayHDoublePrimeEnd, VertexODoublePrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawRayKDoublePrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKDoublePrimeColor)
        end
    elseif phase == PhaseDrawRayKDoublePrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawRayDuration,
            RayKDoublePrimeStart, RayKDoublePrimeEnd;
            penbrush=RayBrush,
            pencolor=RayKDoublePrimeColor,
            line_host_id=ray_k_double_prime_host_id,
            line_joint1_id=ray_k_double_prime_joint1_id,
            line_joint2_id=ray_k_double_prime_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhasePenLiftForMarker3
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_k_double_prime_id)
        end
    elseif phase == PhasePenLiftForMarker3
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ,
            RayKDoublePrimeEnd[1], RayKDoublePrimeEnd[2])
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            VertexODoublePrime[1], VertexODoublePrime[2],
            Marker3Start[1], Marker3Start[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseDrawMarker3
            timer = 0f0
        end
    elseif phase == PhaseDrawMarker3
        EuclidAnimations.animate_draw_filledcircle(state_ptr,
            timer, MarkerDrawDuration, VertexODoublePrime,
            Marker3Start, AngleTheta, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
            marker_host_id=marker3_host_id,
            marker_start_id=marker3_start_id,
            marker_end_id=marker3_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassArc3To1
            timer = 0f0
        end
    elseif phase == PhaseCompassArc3To1
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexODoublePrime, VertexO,
            Marker3End, Marker1Start)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightA1Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightA1Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightA1Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightA1Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArc1To2
            timer = 0f0
        end
    elseif phase == PhaseCompassArc1To2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexO, VertexOPrime,
            Marker1Start, Marker2Start)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightB1Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightB1Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexOPrime, Marker2Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightB1Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightB1Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexOPrime, Marker2End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArc2To1
            timer = 0f0
        end
    elseif phase == PhaseCompassArc2To1
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexOPrime, VertexO,
            Marker2Start, Marker1Start)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightA2Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightA2Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightA2Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightA2Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexO, Marker1End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArc1To3
            timer = 0f0
        end
    elseif phase == PhaseCompassArc1To3
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexO, VertexODoublePrime,
            Marker1Start, Marker3Start)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightC1Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightC1Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexODoublePrime, Marker3Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightC1Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightC1Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexODoublePrime, Marker3End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArc3To2
            timer = 0f0
        end
    elseif phase == PhaseCompassArc3To2
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexODoublePrime, VertexOPrime,
            Marker3Start, Marker2Start)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightB2Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightB2Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexOPrime, Marker2Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightB2Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightB2Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexOPrime, Marker2End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArc2To3
            timer = 0f0
        end
    elseif phase == PhaseCompassArc2To3
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexOPrime, VertexODoublePrime,
            Marker2Start, Marker3Start)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightC2Forward
            timer = 0f0
        end
    elseif phase == PhaseHighlightC2Forward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexODoublePrime, Marker3Start,
            AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightC2Back
            timer = 0f0
        end
    elseif phase == PhaseHighlightC2Back
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            VertexODoublePrime, Marker3End,
            -AngleTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassLiftEnd
            timer = 0f0
        end
    elseif phase == PhaseCompassLiftEnd
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            VertexODoublePrime[1], VertexODoublePrime[2],
            Marker3Start[1], Marker3Start[2])

        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
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

end
