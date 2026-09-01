module HilbertChapterOneTheorem11

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop, animation_entry

const PointA = [0.20f0, 0.66f0, 0f0]
const PointB = [0.50f0, 0.54f0, 0f0]
const PointC = [0.42f0, 0.82f0, 0f0]

const PointAPrime = [0.61f0, 0.20f0, 0f0]
const PointBPrime = [0.88f0, 0.09f0, 0f0]
const PointCPrime = [0.80f0, 0.37f0, 0f0]

const EdgeABStart = PointA
const EdgeABEnd = PointB
const EdgeBCStart = PointB
const EdgeBCEnd = PointC
const EdgeCAStart = PointC
const EdgeCAEnd = PointA

const EdgeAPrimeBPrimeStart = PointAPrime
const EdgeAPrimeBPrimeEnd = PointBPrime
const EdgeBPrimeCPrimeStart = PointBPrime
const EdgeBPrimeCPrimeEnd = PointCPrime
const EdgeCPrimeAPrimeStart = PointCPrime
const EdgeCPrimeAPrimeEnd = PointAPrime

const MarkerRadius = 0.08f0

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
const EdgeBCColor = :palevioletred1
const EdgeCAColor = :khaki3
const EdgeAPrimeBPrimeColor = :steelblue
const EdgeBPrimeCPrimeColor = :palevioletred1
const EdgeCPrimeAPrimeColor = :khaki3

const EdgeBrush = 5f0
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const LabelAPoint = PointA + [-0.04f0, -0.04f0, 0f0]
const LabelBPoint = PointB + [0.03f0, -0.01f0, 0f0]
const LabelCPoint = PointC + [0.01f0, 0.05f0, 0f0]
const LabelAPrimePoint = PointAPrime + [-0.04f0, -0.04f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0.03f0, -0.01f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0.01f0, 0.05f0, 0f0]

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.2f0
const ArcMoveDuration = 1.35f0
const DragDuration = 1.25f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 0.95f0
const FinalHoldDuration = 0.35f0

"""Complete immutable state for one Theorem 11 animation generation."""
struct AnimationState
    edge_abhost_id::Int64
    edge_abjoint1_id::Int64
    edge_abjoint2_id::Int64
    edge_bchost_id::Int64
    edge_bcjoint1_id::Int64
    edge_bcjoint2_id::Int64
    edge_cahost_id::Int64
    edge_cajoint1_id::Int64
    edge_cajoint2_id::Int64
    edge_aprime_bprime_host_id::Int64
    edge_aprime_bprime_joint1_id::Int64
    edge_aprime_bprime_joint2_id::Int64
    edge_bprime_cprime_host_id::Int64
    edge_bprime_cprime_joint1_id::Int64
    edge_bprime_cprime_joint2_id::Int64
    edge_cprime_aprime_host_id::Int64
    edge_cprime_aprime_joint1_id::Int64
    edge_cprime_aprime_joint2_id::Int64
    label_aid::Int64
    label_bid::Int64
    label_cid::Int64
    label_aprime_id::Int64
    label_bprime_id::Int64
    label_cprime_id::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescendToA = 0f0
const PhaseDrawAB = 1f0
const PhaseDrawBC = 2f0
const PhaseDrawCA = 3f0
const PhaseArcAToAPrime = 4f0
const PhaseDrawAPrimeBPrime = 5f0
const PhaseDrawBPrimeCPrime = 6f0
const PhaseDrawCPrimeAPrime = 7f0

const PhaseArcAPrimeToAForAB = 8f0
const PhaseDragABForward = 9f0
const PhaseDragABBack = 10f0
const PhaseArcAToAPrimeForPrimeAB = 11f0
const PhaseDragAPrimeBPrimeForward = 12f0
const PhaseDragAPrimeBPrimeBack = 13f0

const PhasePenRiseBeforeCompass = 14f0
const PhaseCompassDescendAtA = 15f0
const PhaseHighlightAngleAForward = 16f0
const PhaseHighlightAngleABack = 17f0
const PhaseCompassArcAToAPrime = 18f0
const PhaseHighlightAngleAPrimeForward = 19f0
const PhaseHighlightAngleAPrimeBack = 20f0
const PhaseCompassArcAPrimeToB = 21f0
const PhaseHighlightAngleBForward = 22f0
const PhaseHighlightAngleBBack = 23f0
const PhaseCompassArcBToBPrime = 24f0
const PhaseHighlightAngleBPrimeForward = 25f0
const PhaseHighlightAngleBPrimeBack = 26f0
const PhaseCompassArcBPrimeToC = 27f0
const PhaseHighlightAngleCForward = 28f0
const PhaseHighlightAngleCBack = 29f0
const PhaseCompassArcCToCPrime = 30f0
const PhaseHighlightAngleCPrimeForward = 31f0
const PhaseHighlightAngleCPrimeBack = 32f0
const PhaseCompassRise = 33f0

const PhasePenDescendAtAForAC = 34f0
const PhaseDragACForward = 35f0
const PhaseDragACBack = 36f0
const PhaseArcAToAPrimeForPrimeAC = 37f0
const PhaseDragAPrimeCPrimeForward = 38f0
const PhaseDragAPrimeCPrimeBack = 39f0
const PhaseArcAPrimeToBForBC = 40f0
const PhaseDragBCForward = 41f0
const PhaseDragBCBack = 42f0
const PhaseArcBToBPrimeForPrimeBC = 43f0
const PhaseDragBPrimeCPrimeForward = 44f0
const PhaseDragBPrimeCPrimeBack = 45f0
const PhasePenRiseEnd = 46f0
const PhaseFinalHold = 47f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
    state.edge_abhost_id,
    state.edge_abjoint1_id,
    state.edge_abjoint2_id,
    state.edge_bchost_id,
    state.edge_bcjoint1_id,
    state.edge_bcjoint2_id,
    state.edge_cahost_id,
    state.edge_cajoint1_id,
    state.edge_cajoint2_id,
    state.edge_aprime_bprime_host_id,
    state.edge_aprime_bprime_joint1_id,
    state.edge_aprime_bprime_joint2_id,
    state.edge_bprime_cprime_host_id,
    state.edge_bprime_cprime_joint1_id,
    state.edge_bprime_cprime_joint2_id,
    state.edge_cprime_aprime_host_id,
    state.edge_cprime_aprime_joint1_id,
    state.edge_cprime_aprime_joint2_id,
    state.label_aid,
    state.label_bid,
    state.label_cid,
    state.label_aprime_id,
    state.label_bprime_id,
    state.label_cprime_id,
        phase, timer)
end


"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 11 (Second theorem of congruence for triangles)

If in any two triangles one side and the two adjacent angles are respectively congruent, the triangles are congruent."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 11 (Second theorem of congruence for triangles)}

If in any two triangles one side and the two adjacent angles are respectively congruent, the triangles are congruent."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    edge_a_b_host_id = state.edge_abhost_id
    edge_a_b_joint2_id = state.edge_abjoint2_id
    edge_b_c_host_id = state.edge_bchost_id
    edge_b_c_joint2_id = state.edge_bcjoint2_id
    edge_c_a_host_id = state.edge_cahost_id
    edge_c_a_joint2_id = state.edge_cajoint2_id

    edge_a_prime_b_prime_host_id = state.edge_aprime_bprime_host_id
    edge_a_prime_b_prime_joint2_id = state.edge_aprime_bprime_joint2_id
    edge_b_prime_c_prime_host_id = state.edge_bprime_cprime_host_id
    edge_b_prime_c_prime_joint2_id = state.edge_bprime_cprime_joint2_id
    edge_c_prime_a_prime_host_id = state.edge_cprime_aprime_host_id
    edge_c_prime_a_prime_joint2_id = state.edge_cprime_aprime_joint2_id

    label_a_id = state.label_aid
    label_b_id = state.label_bid
    label_c_id = state.label_cid
    label_a_prime_id = state.label_aprime_id
    label_b_prime_id = state.label_bprime_id
    label_c_prime_id = state.label_cprime_id

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edge_a_b_host_id, edge_b_c_host_id, edge_c_a_host_id,
         edge_a_prime_b_prime_host_id, edge_b_prime_c_prime_host_id,
         edge_c_prime_a_prime_host_id,
         label_a_id, label_b_id, label_c_id,
         label_a_prime_id, label_b_prime_id, label_c_prime_id])

    OdinJuliaBridge.set_point_position(state_ptr, edge_a_b_joint2_id, EdgeABStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_b_c_joint2_id, EdgeBCStart)
    OdinJuliaBridge.set_point_position(state_ptr, edge_c_a_joint2_id, EdgeCAStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_a_prime_b_prime_joint2_id, EdgeAPrimeBPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_b_prime_c_prime_joint2_id, EdgeBPrimeCPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_c_prime_a_prime_joint2_id, EdgeCPrimeAPrimeStart)


    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(
        state_ptr, ToolResetOffscreenJoint1[1], ToolResetOffscreenJoint1[2],
        ToolResetOffscreenJoint1[3])
    OdinJuliaBridge.move_pen_joint2(
        state_ptr, ToolResetOffscreenJoint2[1], ToolResetOffscreenJoint2[2],
        ToolResetOffscreenJoint2[3])
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, ToolResetOffscreenJoint1[1], ToolResetOffscreenJoint1[2],
        ToolResetOffscreenJoint1[3], sweep = false)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, ToolResetOffscreenJoint2[1], ToolResetOffscreenJoint2[2],
        ToolResetOffscreenJoint2[3], sweep = false)

    OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, 0f0, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    edge_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeABStart, EdgeABStart, EdgeABColor, 0f0)
    edge_b_c = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeBCStart, EdgeBCStart, EdgeBCColor, 0f0)
    edge_c_a = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeCAStart, EdgeCAStart, EdgeCAColor, 0f0)

    edge_a_prime_b_prime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeAPrimeBPrimeStart, EdgeAPrimeBPrimeStart,
        EdgeAPrimeBPrimeColor, 0f0)
    edge_b_prime_c_prime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeBPrimeCPrimeStart, EdgeBPrimeCPrimeStart,
        EdgeBPrimeCPrimeColor, 0f0)
    edge_c_prime_a_prime = OdinJuliaBridge.create_new_line(
        state_ptr, EdgeCPrimeAPrimeStart, EdgeCPrimeAPrimeStart,
        EdgeCPrimeAPrimeColor, 0f0)

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
        edge_a_b.host_id,
        edge_a_b.joint1_id,
        edge_a_b.joint2_id,
        edge_b_c.host_id,
        edge_b_c.joint1_id,
        edge_b_c.joint2_id,
        edge_c_a.host_id,
        edge_c_a.joint1_id,
        edge_c_a.joint2_id,
        edge_a_prime_b_prime.host_id,
        edge_a_prime_b_prime.joint1_id,
        edge_a_prime_b_prime.joint2_id,
        edge_b_prime_c_prime.host_id,
        edge_b_prime_c_prime.joint1_id,
        edge_b_prime_c_prime.joint2_id,
        edge_c_prime_a_prime.host_id,
        edge_c_prime_a_prime.joint1_id,
        edge_c_prime_a_prime.joint2_id,
        label_a.index,
        label_b.index,
        label_c.index,
        label_a_prime.index,
        label_b_prime.index,
        label_c_prime.index,
        0f0, 0f0)
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
    edge_a_b_host_id = state.edge_abhost_id
    edge_a_b_joint1_id = state.edge_abjoint1_id
    edge_a_b_joint2_id = state.edge_abjoint2_id
    edge_b_c_host_id = state.edge_bchost_id
    edge_b_c_joint1_id = state.edge_bcjoint1_id
    edge_b_c_joint2_id = state.edge_bcjoint2_id
    edge_c_a_host_id = state.edge_cahost_id
    edge_c_a_joint1_id = state.edge_cajoint1_id
    edge_c_a_joint2_id = state.edge_cajoint2_id

    edge_a_prime_b_prime_host_id = state.edge_aprime_bprime_host_id
    edge_a_prime_b_prime_joint1_id = state.edge_aprime_bprime_joint1_id
    edge_a_prime_b_prime_joint2_id = state.edge_aprime_bprime_joint2_id
    edge_b_prime_c_prime_host_id = state.edge_bprime_cprime_host_id
    edge_b_prime_c_prime_joint1_id = state.edge_bprime_cprime_joint1_id
    edge_b_prime_c_prime_joint2_id = state.edge_bprime_cprime_joint2_id
    edge_c_prime_a_prime_host_id = state.edge_cprime_aprime_host_id
    edge_c_prime_a_prime_joint1_id = state.edge_cprime_aprime_joint1_id
    edge_c_prime_a_prime_joint2_id = state.edge_cprime_aprime_joint2_id

    label_a_id = state.label_aid
    label_b_id = state.label_bid
    label_c_id = state.label_cid
    label_a_prime_id = state.label_aprime_id
    label_b_prime_id = state.label_bprime_id
    label_c_prime_id = state.label_cprime_id

    if edge_a_b_host_id < 0 || edge_b_c_host_id < 0 || edge_c_a_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescendToA
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeABColor)
            phase = PhaseDrawAB
            timer = 0f0
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
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeBCColor)
            phase = PhaseDrawBC
            timer = 0f0
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
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCAColor)
            phase = PhaseDrawCA
            timer = 0f0
        end
    elseif phase == PhaseDrawCA
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeCAStart, EdgeCAEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeCAColor,
            line_host_id=edge_c_a_host_id,
            line_joint1_id=edge_c_a_joint1_id,
            line_joint2_id=edge_c_a_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcAToAPrime
            timer = 0f0
        end
    elseif phase == PhaseArcAToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.27f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeAPrimeBPrimeColor)
            phase = PhaseDrawAPrimeBPrime
            timer = 0f0
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
            OdinJuliaBridge.show_point(state_ptr, label_b_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeBPrimeCPrimeColor)
            phase = PhaseDrawBPrimeCPrime
            timer = 0f0
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
            OdinJuliaBridge.show_point(state_ptr, label_c_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, EdgeCPrimeAPrimeColor)
            phase = PhaseDrawCPrimeAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawCPrimeAPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            EdgeCPrimeAPrimeStart, EdgeCPrimeAPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=EdgeCPrimeAPrimeColor,
            line_host_id=edge_c_prime_a_prime_host_id,
            line_joint1_id=edge_c_prime_a_prime_joint1_id,
            line_joint2_id=edge_c_prime_a_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcAPrimeToAForAB
            timer = 0f0
        end

    elseif phase == PhaseArcAPrimeToAForAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointA, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragABForward
            timer = 0f0
        end
    elseif phase == PhaseDragABForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragABBack
            timer = 0f0
        end
    elseif phase == PhaseDragABBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAToAPrimeForPrimeAB
            timer = 0f0
        end
    elseif phase == PhaseArcAToAPrimeForPrimeAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeBPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeBPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragAPrimeBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeBPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhasePenRiseBeforeCompass
            timer = 0f0
        end

    elseif phase == PhasePenRiseBeforeCompass
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointAPrime[1], PointAPrime[2])
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
            PointA, MarkerAStart, AngleATheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleABack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerAEnd, -AngleATheta, MarkerRadius, HighlightColor)
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
            PointAPrime, MarkerAPrimeStart, AngleAPrimeTheta,
            MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleAPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleAPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerAPrimeEnd, -AngleAPrimeTheta,
            MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcAPrimeToB
            timer = 0f0
        end

    elseif phase == PhaseCompassArcAPrimeToB
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
            PointB, MarkerBStart, AngleBTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleBBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerBEnd, -AngleBTheta, MarkerRadius, HighlightColor)
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
            PointBPrime, MarkerBPrimeStart, AngleBPrimeTheta,
            MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleBPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerBPrimeEnd, -AngleBPrimeTheta,
            MarkerRadius, HighlightColor)
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
            PointC, MarkerCStart, AngleCTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointC, MarkerCEnd, -AngleCTheta, MarkerRadius, HighlightColor)
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
            PointCPrime, MarkerCPrimeStart, AngleCPrimeTheta,
            MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightAngleCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightAngleCPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointCPrime, MarkerCPrimeEnd, -AngleCPrimeTheta,
            MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRise
            timer = 0f0
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointCPrime[1], PointCPrime[2], MarkerCPrimeStart[1], MarkerCPrimeStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendAtAForAC
            timer = 0f0
        end

    elseif phase == PhasePenDescendAtAForAC
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseDragACForward
            timer = 0f0
        end
    elseif phase == PhaseDragACForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragACBack
            timer = 0f0
        end
    elseif phase == PhaseDragACBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAToAPrimeForPrimeAC
            timer = 0f0
        end
    elseif phase == PhaseArcAToAPrimeForPrimeAC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragAPrimeCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeCPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragAPrimeCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragAPrimeCPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcAPrimeToBForBC
            timer = 0f0
        end
    elseif phase == PhaseArcAPrimeToBForBC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointB, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBCForward
            timer = 0f0
        end
    elseif phase == PhaseDragBCForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBCBack
            timer = 0f0
        end
    elseif phase == PhaseDragBCBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcBToBPrimeForPrimeBC
            timer = 0f0
        end
    elseif phase == PhaseArcBToBPrimeForPrimeBC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointBPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragBPrimeCPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeCPrimeForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragBPrimeCPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseDragBPrimeCPrimeBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhasePenRiseEnd
            timer = 0f0
        end
    elseif phase == PhasePenRiseEnd
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointBPrime[1], PointBPrime[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
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
