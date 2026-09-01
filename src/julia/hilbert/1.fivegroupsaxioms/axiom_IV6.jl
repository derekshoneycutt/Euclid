module HilbertChapterOneAxiomIV6

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const PointA = [0.20f0, 0.66f0, 0f0]
const PointB = [0.52f0, 0.50f0, 0f0]
const PointC = [0.44f0, 0.84f0, 0f0]

const PointAPrime = [0.60f0, 0.58f0, 0f0]
const PointBPrime = [0.90f0, 0.43f0, 0f0]
const PointCPrime = [0.82f0, 0.78f0, 0f0]

const EdgeABStart = PointA
const EdgeABEnd = PointB
const EdgeACStart = PointA
const EdgeACEnd = PointC
const EdgeBCStart = PointB
const EdgeBCEnd = PointC

const EdgeAPrimeBPrimeStart = PointAPrime
const EdgeAPrimeBPrimeEnd = PointBPrime
const EdgeAPrimeCPrimeStart = PointAPrime
const EdgeAPrimeCPrimeEnd = PointCPrime
const EdgeBPrimeCPrimeStart = PointBPrime
const EdgeBPrimeCPrimeEnd = PointCPrime

const MarkerRadius = 0.09f0

const ThetaAAB = atan(PointB[2] - PointA[2], PointB[1] - PointA[1])
const ThetaAAC = atan(PointC[2] - PointA[2], PointC[1] - PointA[1])
const ThetaAPrimeAB = Float32(atan(
    PointBPrime[2] - PointAPrime[2], PointBPrime[1] - PointAPrime[1]))
const ThetaAPrimeAC = Float32(atan(
    PointCPrime[2] - PointAPrime[2], PointCPrime[1] - PointAPrime[1]))

const ThetaBBC = atan(PointC[2] - PointB[2], PointC[1] - PointB[1])
const ThetaBBA = atan(PointA[2] - PointB[2], PointA[1] - PointB[1])
const ThetaBPrimeBC = Float32(atan(
    PointCPrime[2] - PointBPrime[2], PointCPrime[1] - PointBPrime[1]))
const ThetaBPrimeBA = Float32(atan(
    PointAPrime[2] - PointBPrime[2], PointAPrime[1] - PointBPrime[1]))

const ThetaCCA = atan(PointA[2] - PointC[2], PointA[1] - PointC[1])
const ThetaCCB = atan(PointB[2] - PointC[2], PointB[1] - PointC[1])
const ThetaCPrimeCA = Float32(atan(
    PointAPrime[2] - PointCPrime[2], PointAPrime[1] - PointCPrime[1]))
const ThetaCPrimeCB = Float32(atan(
    PointBPrime[2] - PointCPrime[2], PointBPrime[1] - PointCPrime[1]))

const MarkerAStart = [
    PointA[1] + MarkerRadius * cos(ThetaAAB),
    PointA[2] + MarkerRadius * sin(ThetaAAB),
    0f0,
]
const MarkerAEnd = [
    PointA[1] + MarkerRadius * cos(ThetaAAC),
    PointA[2] + MarkerRadius * sin(ThetaAAC),
    0f0,
]
const MarkerAPrimeStart = [
    PointAPrime[1] + MarkerRadius * cos(ThetaAPrimeAB),
    PointAPrime[2] + MarkerRadius * sin(ThetaAPrimeAB),
    0f0,
]
const MarkerAPrimeEnd = [
    PointAPrime[1] + MarkerRadius * cos(ThetaAPrimeAC),
    PointAPrime[2] + MarkerRadius * sin(ThetaAPrimeAC),
    0f0,
]

const MarkerBStart = [
    PointB[1] + MarkerRadius * cos(ThetaBBC),
    PointB[2] + MarkerRadius * sin(ThetaBBC),
    0f0,
]
const MarkerBEnd = [
    PointB[1] + MarkerRadius * cos(ThetaBBA),
    PointB[2] + MarkerRadius * sin(ThetaBBA),
    0f0,
]
const MarkerBPrimeStart = [
    PointBPrime[1] + MarkerRadius * cos(ThetaBPrimeBC),
    PointBPrime[2] + MarkerRadius * sin(ThetaBPrimeBC),
    0f0,
]
const MarkerBPrimeEnd = [
    PointBPrime[1] + MarkerRadius * cos(ThetaBPrimeBA),
    PointBPrime[2] + MarkerRadius * sin(ThetaBPrimeBA),
    0f0,
]

const MarkerCStart = [
    PointC[1] + MarkerRadius * cos(ThetaCCA),
    PointC[2] + MarkerRadius * sin(ThetaCCA),
    0f0,
]
const MarkerCEnd = [
    PointC[1] + MarkerRadius * cos(ThetaCCB),
    PointC[2] + MarkerRadius * sin(ThetaCCB),
    0f0,
]
const MarkerCPrimeStart = [
    PointCPrime[1] + MarkerRadius * cos(ThetaCPrimeCA),
    PointCPrime[2] + MarkerRadius * sin(ThetaCPrimeCA),
    0f0,
]
const MarkerCPrimeEnd = [
    PointCPrime[1] + MarkerRadius * cos(ThetaCPrimeCB),
    PointCPrime[2] + MarkerRadius * sin(ThetaCPrimeCB),
    0f0,
]

const AngleATheta = ThetaAAC - ThetaAAB
const AngleAPrimeTheta = ThetaAPrimeAC - ThetaAPrimeAB
const AngleBTheta = ThetaBBA - ThetaBBC
const AngleBPrimeTheta = ThetaBPrimeBA - ThetaBPrimeBC
const AngleCTheta = ThetaCCB - ThetaCCA
const AngleCPrimeTheta = ThetaCPrimeCB - ThetaCPrimeCA

const LabelColor = :plum1
const HighlightColor = :lightgreen

const EdgeABColor = :steelblue
const EdgeACColor = :palevioletred1
const EdgeBCColor = :khaki3
const EdgeAPrimeBPrimeColor = :grey60
const EdgeAPrimeCPrimeColor = :steelblue
const EdgeBPrimeCPrimeColor = :palevioletred1
const MarkerColor = :khaki3

const EdgeBrush = 5f0
const MarkerBrush = 1f0
const ResetPenLength = 0.14f0

const LabelAPoint = PointA + [-0.04f0, -0.04f0, 0f0]
const LabelBPoint = PointB + [0.02f0, -0.03f0, 0f0]
const LabelCPoint = PointC + [-0.01f0, 0.03f0, 0f0]

const LabelAPrimePoint = PointAPrime + [-0.04f0, -0.04f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0.02f0, -0.03f0, 0f0]
const LabelCPrimePoint = PointCPrime + [-0.01f0, 0.03f0, 0f0]

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.2f0
const ArcMoveDuration = 1.4f0
const PenLiftDuration = 1.6f0
const MarkerDrawDuration = 1.2f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 1.0f0
const DragDuration = 1.5f0
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

"""Complete immutable state for one Axiom IV,6 animation generation."""
struct AnimationState
    edge_a_b::LineIds
    edge_a_c::LineIds
    edge_b_c::LineIds
    edge_a_prime_b_prime::LineIds
    edge_a_prime_c_prime::LineIds
    edge_b_prime_c_prime::LineIds
    marker_a::CircleIds
    marker_a_prime::CircleIds
    label_a::Int64
    label_b::Int64
    label_c::Int64
    label_a_prime::Int64
    label_b_prime::Int64
    label_c_prime::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescendToA = 0f0
const PhaseDrawAB = 1f0
const PhaseArcToAForAC = 2f0
const PhaseDrawAC = 3f0
const PhaseArcToBForBC = 4f0
const PhaseDrawBC = 5f0
const PhasePenLiftForMarkerA = 6f0
const PhaseDrawMarkerA = 7f0
const PhaseCompassLiftAfterMarkerA = 8f0

const PhaseDescendToAPrime = 9f0
const PhaseDrawAPrimeBPrime = 10f0
const PhaseArcToAPrimeForAC = 11f0
const PhaseDrawAPrimeCPrime = 12f0
const PhaseArcToBPrimeForBC = 13f0
const PhaseDrawBPrimeCPrime = 14f0
const PhasePenLiftForMarkerAPrime = 15f0
const PhaseDrawMarkerAPrime = 16f0
const PhaseCompassLiftAfterMarkerAPrime = 17f0

const PhaseDescendForABHighlight = 18f0
const PhaseHighlightABForward = 19f0
const PhaseHighlightABBack = 20f0
const PhaseArcToAPrimeBPrimeHighlight = 21f0
const PhaseHighlightAPrimeBPrimeForward = 22f0
const PhaseHighlightAPrimeBPrimeBack = 23f0

const PhaseArcToAForACHighlight = 24f0
const PhaseHighlightACForward = 25f0
const PhaseHighlightACBack = 26f0
const PhaseArcToAPrimeForACHighlight = 27f0
const PhaseHighlightAPrimeCPrimeForward = 28f0
const PhaseHighlightAPrimeCPrimeBack = 29f0
const PhasePenLiftBeforeCompassHighlights = 30f0

const PhaseCompassDescendAtA = 31f0
const PhaseHighlightAngleAForward = 32f0
const PhaseHighlightAngleABack = 33f0
const PhaseCompassArcAToAPrime = 34f0
const PhaseHighlightAngleAPrimeForward = 35f0
const PhaseHighlightAngleAPrimeBack = 36f0

const PhaseCompassArcAToB = 37f0
const PhaseHighlightAngleBForward = 38f0
const PhaseHighlightAngleBBack = 39f0
const PhaseCompassArcBToBPrime = 40f0
const PhaseHighlightAngleBPrimeForward = 41f0
const PhaseHighlightAngleBPrimeBack = 42f0

const PhaseCompassArcBPrimeToC = 43f0
const PhaseHighlightAngleCForward = 44f0
const PhaseHighlightAngleCBack = 45f0
const PhaseCompassArcCToCPrime = 46f0
const PhaseHighlightAngleCPrimeForward = 47f0
const PhaseHighlightAngleCPrimeBack = 48f0

const PhaseCompassLiftEnd = 49f0
const PhaseFinalHold = 50f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.edge_a_b, state.edge_a_c, state.edge_b_c,
        state.edge_a_prime_b_prime, state.edge_a_prime_c_prime,
        state.edge_b_prime_c_prime, state.marker_a, state.marker_a_prime,
        state.label_a, state.label_b, state.label_c, state.label_a_prime,
        state.label_b_prime, state.label_c_prime, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Axiom IV,6

IV, 6. If, in the two triangles ABC and A'B'C' the congruences AB ≡ A'B', AC ≡ A'C', ∠BAC ≡ ∠B'A'C' hold, then the congruences ∠ABC ≡ ∠A'B'C' and ∠ACB ≡ ∠A'C'B' also hold."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Axiom IV,6}

\textbf{IV, 6.} If, in the two triangles $ABC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3]
and $A'B'C'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=grey60,edge3_color=palevioletred1]
the congruences $AB$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv A'B'$ \euclidline[color=grey60,length=3,thickness=4],
$AC$ \euclidline[color=palevioletred1,length=3,thickness=4] $\equiv A'C'$ \euclidline[color=steelblue,length=3,thickness=4],
$\angle BAC$ \euclidangle[color=khaki3,radius=2,end=60,filled] $\equiv \angle B'A'C'$ \euclidangle[color=khaki3,radius=2,end=60,filled] hold,
then the congruences $\angle ABC$ \euclidangle[color=lightgreen,radius=2,end=60,filled] $\equiv \angle A'B'C'$ \euclidangle[color=lightgreen,radius=2,end=60,filled]
and $\angle ACB$ \euclidangle[color=lightgreen,radius=2,end=60,filled] $\equiv \angle A'C'B'$ \euclidangle[color=lightgreen,radius=2,end=60,filled] also hold."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle and transactionally publish its initial timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    edge_a_b_host_id = state.edge_a_b.host
    edge_a_b_joint2_id = state.edge_a_b.joint2
    edge_a_c_host_id = state.edge_a_c.host
    edge_a_c_joint2_id = state.edge_a_c.joint2
    edge_b_c_host_id = state.edge_b_c.host
    edge_b_c_joint2_id = state.edge_b_c.joint2

    edge_a_prime_b_prime_host_id = state.edge_a_prime_b_prime.host
    edge_a_prime_b_prime_joint2_id = state.edge_a_prime_b_prime.joint2
    edge_a_prime_c_prime_host_id = state.edge_a_prime_c_prime.host
    edge_a_prime_c_prime_joint2_id = state.edge_a_prime_c_prime.joint2
    edge_b_prime_c_prime_host_id = state.edge_b_prime_c_prime.host
    edge_b_prime_c_prime_joint2_id = state.edge_b_prime_c_prime.joint2

    marker_a_host_id = state.marker_a.host
    marker_a_end_id = state.marker_a.finish
    marker_a_prime_host_id = state.marker_a_prime.host
    marker_a_prime_end_id = state.marker_a_prime.finish

    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_a_prime_id = state.label_a_prime
    label_b_prime_id = state.label_b_prime
    label_c_prime_id = state.label_c_prime

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edge_a_b_host_id, edge_a_c_host_id, edge_b_c_host_id,
         edge_a_prime_b_prime_host_id, edge_a_prime_c_prime_host_id,
         edge_b_prime_c_prime_host_id,
         marker_a_host_id, marker_a_prime_host_id,
         label_a_id, label_b_id, label_c_id, label_a_prime_id,
        label_b_prime_id, label_c_prime_id])

    OdinJuliaBridge.set_point_position(state_ptr, edge_a_b_joint2_id, EdgeABStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_a_c_joint2_id, EdgeACStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_b_c_joint2_id, EdgeBCStart)

    OdinJuliaBridge.set_point_position(
        state_ptr, edge_a_prime_b_prime_joint2_id, EdgeAPrimeBPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_a_prime_c_prime_joint2_id, EdgeAPrimeCPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_b_prime_c_prime_joint2_id, EdgeBPrimeCPrimeStart)

    OdinJuliaBridge.set_point_position(
        state_ptr, marker_a_end_id, MarkerAStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, marker_a_prime_end_id, MarkerAPrimeStart)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescendToA, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(
        state_ptr, PointA[1], PointA[2], PenTopZ)
    OdinJuliaBridge.move_pen_joint2(
        state_ptr, PointA[1], PointA[2], PenTopZ + ResetPenLength)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, PointA[1], PointA[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, MarkerAStart[1], MarkerAStart[2], CompassTopZ, sweep = false)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    edge_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeABStart, EdgeABStart, EdgeABColor, 0f0)
    edge_a_c = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeACStart, EdgeACStart, EdgeACColor, 0f0)
    edge_b_c = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeBCStart, EdgeBCStart, EdgeBCColor, 0f0)

    edge_a_prime_b_prime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeAPrimeBPrimeStart,
        EdgeAPrimeBPrimeStart, EdgeAPrimeBPrimeColor, 0f0)
    edge_a_prime_c_prime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeAPrimeCPrimeStart,
        EdgeAPrimeCPrimeStart, EdgeAPrimeCPrimeColor, 0f0)
    edge_b_prime_c_prime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeBPrimeCPrimeStart,
        EdgeBPrimeCPrimeStart, EdgeBPrimeCPrimeColor, 0f0)

    marker_a = OdinJuliaBridge.create_new_filledcircle(state_ptr,
        PointA, MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)
    marker_a_prime = OdinJuliaBridge.create_new_filledcircle(state_ptr,
        PointAPrime, MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', LabelCPoint, LabelColor, 16f0)

    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    label_b_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    label_c_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelCPrimePoint, LabelColor, 16f0)

    state = AnimationState(
        LineIds(edge_a_b.host_id, edge_a_b.joint1_id, edge_a_b.joint2_id),
        LineIds(edge_a_c.host_id, edge_a_c.joint1_id, edge_a_c.joint2_id),
        LineIds(edge_b_c.host_id, edge_b_c.joint1_id, edge_b_c.joint2_id),
        LineIds(edge_a_prime_b_prime.host_id, edge_a_prime_b_prime.joint1_id,
            edge_a_prime_b_prime.joint2_id),
        LineIds(edge_a_prime_c_prime.host_id, edge_a_prime_c_prime.joint1_id,
            edge_a_prime_c_prime.joint2_id),
        LineIds(edge_b_prime_c_prime.host_id, edge_b_prime_c_prime.joint1_id,
            edge_b_prime_c_prime.joint2_id),
        CircleIds(marker_a.host_id, marker_a.start_id, marker_a.end_id),
        CircleIds(marker_a_prime.host_id, marker_a_prime.start_id,
            marker_a_prime.end_id),
        label_a.index, label_b.index, label_c.index, label_a_prime.index,
        label_b_prime.index, label_c_prime.index, PhaseDescendToA, 0f0)
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
    edge_a_b_host_id = state.edge_a_b.host
    edge_a_b_joint1_id = state.edge_a_b.joint1
    edge_a_b_joint2_id = state.edge_a_b.joint2
    edge_a_c_host_id = state.edge_a_c.host
    edge_a_c_joint1_id = state.edge_a_c.joint1
    edge_a_c_joint2_id = state.edge_a_c.joint2
    edge_b_c_host_id = state.edge_b_c.host
    edge_b_c_joint1_id = state.edge_b_c.joint1
    edge_b_c_joint2_id = state.edge_b_c.joint2

    edge_a_prime_b_prime_host_id = state.edge_a_prime_b_prime.host
    edge_a_prime_b_prime_joint1_id = state.edge_a_prime_b_prime.joint1
    edge_a_prime_b_prime_joint2_id = state.edge_a_prime_b_prime.joint2
    edge_a_prime_c_prime_host_id = state.edge_a_prime_c_prime.host
    edge_a_prime_c_prime_joint1_id = state.edge_a_prime_c_prime.joint1
    edge_a_prime_c_prime_joint2_id = state.edge_a_prime_c_prime.joint2
    edge_b_prime_c_prime_host_id = state.edge_b_prime_c_prime.host
    edge_b_prime_c_prime_joint1_id = state.edge_b_prime_c_prime.joint1
    edge_b_prime_c_prime_joint2_id = state.edge_b_prime_c_prime.joint2

    marker_a_host_id = state.marker_a.host
    marker_a_start_id = state.marker_a.start
    marker_a_end_id = state.marker_a.finish
    marker_a_prime_host_id = state.marker_a_prime.host
    marker_a_prime_start_id = state.marker_a_prime.start
    marker_a_prime_end_id = state.marker_a_prime.finish

    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_a_prime_id = state.label_a_prime
    label_b_prime_id = state.label_b_prime
    label_c_prime_id = state.label_c_prime

    if edge_a_b_host_id < 0 || edge_a_c_host_id < 0 || edge_b_c_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescendToA
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawAB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
        end
    elseif phase == PhaseDrawAB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeABStart, EdgeABEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeABColor,
            line_host_id=edge_a_b_host_id,
            line_joint1_id=edge_a_b_joint1_id,
            line_joint2_id=edge_a_b_joint2_id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcToAForAC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhaseArcToAForAC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeABEnd, PointA, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAC
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeACColor)
        end
    elseif phase == PhaseDrawAC
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeACStart, EdgeACEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeACColor,
            line_host_id=edge_a_c_host_id,
            line_joint1_id=edge_a_c_joint1_id,
            line_joint2_id=edge_a_c_joint2_id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcToBForBC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
        end
    elseif phase == PhaseArcToBForBC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeACEnd, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawBC
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeBCColor)
        end
    elseif phase == PhaseDrawBC
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeBCStart, EdgeBCEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeBCColor,
            line_host_id=edge_b_c_host_id,
            line_joint1_id=edge_b_c_joint1_id,
            line_joint2_id=edge_b_c_joint2_id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhasePenLiftForMarkerA
            timer = 0f0
        end
    elseif phase == PhasePenLiftForMarkerA
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, EdgeBCEnd[1], EdgeBCEnd[2])
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerAStart[1], MarkerAStart[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseDrawMarkerA
            timer = 0f0
        end
    elseif phase == PhaseDrawMarkerA
        EuclidAnimations.animate_draw_filledcircle(state_ptr,
            timer, MarkerDrawDuration, PointA,
            MarkerAStart, AngleATheta, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
            marker_host_id=marker_a_host_id,
            marker_start_id=marker_a_start_id,
            marker_end_id=marker_a_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassLiftAfterMarkerA
            timer = 0f0
        end
    elseif phase == PhaseCompassLiftAfterMarkerA
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerAEnd[1], MarkerAEnd[2])

        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            OdinJuliaBridge.show_pen(state_ptr)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeAPrimeBPrimeColor)
            phase = PhaseDescendToAPrime
            timer = 0f0
        end
    elseif phase == PhaseDescendToAPrime
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointAPrime[1], PointAPrime[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawAPrimeBPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
        end
    elseif phase == PhaseDrawAPrimeBPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeAPrimeBPrimeStart, EdgeAPrimeBPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeAPrimeBPrimeColor,
            line_host_id=edge_a_prime_b_prime_host_id,
            line_joint1_id=edge_a_prime_b_prime_joint1_id,
            line_joint2_id=edge_a_prime_b_prime_joint2_id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcToAPrimeForAC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_prime_id)
        end
    elseif phase == PhaseArcToAPrimeForAC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeAPrimeBPrimeEnd, PointAPrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAPrimeCPrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeAPrimeCPrimeColor)
        end
    elseif phase == PhaseDrawAPrimeCPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeAPrimeCPrimeStart, EdgeAPrimeCPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeAPrimeCPrimeColor,
            line_host_id=edge_a_prime_c_prime_host_id,
            line_joint1_id=edge_a_prime_c_prime_joint1_id,
            line_joint2_id=edge_a_prime_c_prime_joint2_id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcToBPrimeForBC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_c_prime_id)
        end
    elseif phase == PhaseArcToBPrimeForBC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeAPrimeCPrimeEnd, PointBPrime, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawBPrimeCPrime
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeBPrimeCPrimeColor)
        end
    elseif phase == PhaseDrawBPrimeCPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeBPrimeCPrimeStart, EdgeBPrimeCPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeBPrimeCPrimeColor,
            line_host_id=edge_b_prime_c_prime_host_id,
            line_joint1_id=edge_b_prime_c_prime_joint1_id,
            line_joint2_id=edge_b_prime_c_prime_joint2_id)

        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhasePenLiftForMarkerAPrime
            timer = 0f0
        end
    elseif phase == PhasePenLiftForMarkerAPrime
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ,
            EdgeBPrimeCPrimeEnd[1], EdgeBPrimeCPrimeEnd[2])
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            PointAPrime[1], PointAPrime[2], MarkerAPrimeStart[1], MarkerAPrimeStart[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseDrawMarkerAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawMarkerAPrime
        EuclidAnimations.animate_draw_filledcircle(state_ptr,
            timer, MarkerDrawDuration, PointAPrime,
            MarkerAPrimeStart, AngleAPrimeTheta, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
            marker_host_id=marker_a_prime_host_id,
            marker_start_id=marker_a_prime_start_id,
            marker_end_id=marker_a_prime_end_id)

        timer += dt
        if timer >= MarkerDrawDuration
            phase = PhaseCompassLiftAfterMarkerAPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassLiftAfterMarkerAPrime
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointAPrime[1], PointAPrime[2], MarkerAPrimeEnd[1], MarkerAPrimeEnd[2])

        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            OdinJuliaBridge.show_pen(state_ptr)
            phase = PhaseDescendForABHighlight
            timer = 0f0
        end

    elseif phase == PhaseDescendForABHighlight
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightABForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightABForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, EdgeABStart, EdgeABEnd, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightABBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightABBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, EdgeABEnd, EdgeABStart, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToAPrimeBPrimeHighlight
            timer = 0f0
        end
    elseif phase == PhaseArcToAPrimeBPrimeHighlight
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeABStart, EdgeAPrimeBPrimeStart, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAPrimeBPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAPrimeBPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            EdgeAPrimeBPrimeStart, EdgeAPrimeBPrimeEnd, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightAPrimeBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAPrimeBPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            EdgeAPrimeBPrimeEnd, EdgeAPrimeBPrimeStart, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToAForACHighlight
            timer = 0f0
        end
    elseif phase == PhaseArcToAForACHighlight
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeAPrimeBPrimeStart, EdgeACStart, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightACForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightACForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, EdgeACStart, EdgeACEnd, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightACBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightACBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, EdgeACEnd, EdgeACStart, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseArcToAPrimeForACHighlight
            timer = 0f0
        end
    elseif phase == PhaseArcToAPrimeForACHighlight
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EdgeACStart, EdgeAPrimeCPrimeStart, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAPrimeCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAPrimeCPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            EdgeAPrimeCPrimeStart, EdgeAPrimeCPrimeEnd, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightAPrimeCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAPrimeCPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration,
            EdgeAPrimeCPrimeEnd, EdgeAPrimeCPrimeStart, HighlightColor)

        timer += dt
        if timer >= DragDuration
            phase = PhasePenLiftBeforeCompassHighlights
            timer = 0f0
        end
    elseif phase == PhasePenLiftBeforeCompassHighlights
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ,
            EdgeAPrimeCPrimeStart[1], EdgeAPrimeCPrimeStart[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendAtA
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendAtA
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerAStart[1], MarkerAStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightAngleAForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleAForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerAStart,
            AngleATheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleABack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerAEnd,
            -AngleATheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcAToAPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcAToAPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerAStart, MarkerAPrimeStart)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleAPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleAPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerAPrimeStart,
            AngleAPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleAPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleAPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerAPrimeEnd,
            -AngleAPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcAToB
            timer = 0f0
        end

    elseif phase == PhaseCompassArcAToB
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointB,
            MarkerAPrimeStart, MarkerBStart)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleBForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerBStart,
            AngleBTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleBBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerBEnd,
            -AngleBTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBToBPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBToBPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointBPrime,
            MarkerBStart, MarkerBPrimeStart)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleBPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerBPrimeStart,
            AngleBPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerBPrimeEnd,
            -AngleBPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBPrimeToC
            timer = 0f0
        end

    elseif phase == PhaseCompassArcBPrimeToC
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointBPrime, PointC,
            MarkerBPrimeStart, MarkerCStart)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleCForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCStart,
            AngleCTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCEnd,
            -AngleCTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCToCPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCToCPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointC, PointCPrime,
            MarkerCStart, MarkerCPrimeStart)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightAngleCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointCPrime, MarkerCPrimeStart,
            AngleCPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointCPrime, MarkerCPrimeEnd,
            -AngleCPrimeTheta, MarkerRadius, HighlightColor)

        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassLiftEnd
            timer = 0f0
        end

    elseif phase == PhaseCompassLiftEnd
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointCPrime[1], PointCPrime[2], MarkerCPrimeStart[1], MarkerCPrimeStart[2])

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
