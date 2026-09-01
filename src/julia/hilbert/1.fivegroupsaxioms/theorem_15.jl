module HilbertChapterOneTheorem15

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop

const PointB = [0.08f0, 0.68f0, 0f0]
const PointA = [0.28f0, 0.68f0, 0f0]
const PointC = [0.50f0, 0.68f0, 0f0]
const PointD = [0.28f0, 0.92f0, 0f0]
const PointDDouble = [0.17f0, 0.82f0, 0f0]
const PointDTriple = [0.39f0, 0.82f0, 0f0]

const PointBPrime = [0.55f0, 0.22f0, 0f0]
const PointAPrime = [0.75f0, 0.22f0, 0f0]
const PointCPrime = [0.97f0, 0.22f0, 0f0]
const PointDPrime = [0.75f0, 0.46f0, 0f0]

const BaseLineStart = PointB
const BaseLineEnd = PointC
const RightRayStart = PointA
const RightRayEnd = PointD
const RightRayDoubleEnd = PointDDouble
const RightRayTripleEnd = PointDTriple

const BaseLinePrimeStart = PointBPrime
const BaseLinePrimeEnd = PointCPrime
const RightRayPrimeStart = PointAPrime
const RightRayPrimeEnd = PointDPrime

const BaseLineAMidShare = (PointA[1] - PointB[1] / (PointC[1] - PointB[1]))
const BaseLinePrimeAMidShare = Float32(
    (PointAPrime[1] - PointBPrime[1]) / (PointCPrime[1] - PointBPrime[1]))

const MarkerRadius = 0.08f0

const ThetaAB = atan(PointB[2] - PointA[2], PointB[1] - PointA[1])
const ThetaAC = atan(PointC[2] - PointA[2], PointC[1] - PointA[1])
const ThetaAD = atan(PointD[2] - PointA[2], PointD[1] - PointA[1])
const ThetaADDouble = Float32(atan(
    PointDDouble[2] - PointA[2], PointDDouble[1] - PointA[1]))
const ThetaADTriple = Float32(atan(
    PointDTriple[2] - PointA[2], PointDTriple[1] - PointA[1]))

const ThetaAPrimeB = Float32(atan(
    PointBPrime[2] - PointAPrime[2], PointBPrime[1] - PointAPrime[1]))
const ThetaAPrimeC = Float32(atan(
    PointCPrime[2] - PointAPrime[2], PointCPrime[1] - PointAPrime[1]))
const ThetaAPrimeD = Float32(atan(
    PointDPrime[2] - PointAPrime[2], PointDPrime[1] - PointAPrime[1]))

const MarkerBADStart = [
    PointA[1] + MarkerRadius * cos(ThetaAB),
    PointA[2] + MarkerRadius * sin(ThetaAB),
    0f0,
]
const MarkerBADEnd = [
    PointA[1] + MarkerRadius * cos(ThetaAD),
    PointA[2] + MarkerRadius * sin(ThetaAD),
    0f0,
]
const MarkerCADStart = [
    PointA[1] + MarkerRadius * cos(ThetaAC),
    PointA[2] + MarkerRadius * sin(ThetaAC),
    0f0,
]
const MarkerCADEnd = MarkerBADEnd

const MarkerBPrimeADPrimeStart = [
    PointAPrime[1] + MarkerRadius * cos(ThetaAPrimeB),
    PointAPrime[2] + MarkerRadius * sin(ThetaAPrimeB),
    0f0,
]
const MarkerBPrimeADPrimeEnd = [
    PointAPrime[1] + MarkerRadius * cos(ThetaAPrimeD),
    PointAPrime[2] + MarkerRadius * sin(ThetaAPrimeD),
    0f0,
]
const MarkerCPrimeADPrimeStart = [
    PointAPrime[1] + MarkerRadius * cos(ThetaAPrimeC),
    PointAPrime[2] + MarkerRadius * sin(ThetaAPrimeC),
    0f0,
]
const MarkerCPrimeADPrimeEnd = MarkerBPrimeADPrimeEnd

const MarkerBADDoubleStart = MarkerBADStart
const MarkerBADDoubleEnd = [
    PointA[1] + MarkerRadius * cos(ThetaADDouble),
    PointA[2] + MarkerRadius * sin(ThetaADDouble),
    0f0,
]
const MarkerCADDoubleStart = MarkerCADStart
const MarkerCADDoubleEnd = MarkerBADDoubleEnd

const MarkerBADTripleStart = MarkerBADStart
const MarkerBADTripleEnd = [
    PointA[1] + MarkerRadius * cos(ThetaADTriple),
    PointA[2] + MarkerRadius * sin(ThetaADTriple),
    0f0,
]
const MarkerCADTripleStart = MarkerCADStart
const MarkerCADTripleEnd = MarkerBADTripleEnd

const AngleBADTheta = ThetaAD - ThetaAB
const AngleCADTheta = ThetaAD - ThetaAC
const AngleBPrimeADPrimeTheta = ThetaAPrimeD - ThetaAPrimeB
const AngleCPrimeADPrimeTheta = ThetaAPrimeD - ThetaAPrimeC
const AngleBADDoubleTheta = ThetaADDouble - ThetaAB
const AngleCADDoubleTheta = ThetaADDouble - ThetaAC
const AngleBADTripleTheta = ThetaADTriple - ThetaAB
const AngleCADTripleTheta = ThetaADTriple - ThetaAC

const LabelColor = :plum1
const HighlightColor = :lightgreen
const ContradictionColor = :firebrick
const BaseLineColor = :steelblue
const RightRayColor = :khaki3

const EdgeBrush = 5f0
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const LabelBPoint = PointB + [-0.03f0, -0.04f0, 0f0]
const LabelAPoint = PointA + [-0.01f0, -0.05f0, 0f0]
const LabelCPoint = PointC + [0.01f0, -0.04f0, 0f0]
const LabelDPoint = PointD + [0.01f0, 0.04f0, 0f0]
const LabelDDoublePoint = PointDDouble + [-0.06f0, 0.03f0, 0f0]
const LabelDTriplePoint = PointDTriple + [0.01f0, 0.03f0, 0f0]

const LabelBPrimePoint = PointBPrime + [-0.03f0, -0.04f0, 0f0]
const LabelAPrimePoint = PointAPrime + [-0.01f0, -0.05f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0.01f0, -0.04f0, 0f0]
const LabelDPrimePoint = PointDPrime + [0.01f0, 0.04f0, 0f0]

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.2f0
const ArcMoveDuration = 1.35f0
const DragDuration = 1.25f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 0.95f0
const FinalHoldDuration = 0.35f0

"""Complete immutable state for one Theorem 15 animation generation."""
struct AnimationState
    base_line_host_id::Int64
    base_line_joint1_id::Int64
    base_line_joint2_id::Int64
    right_ray_host_id::Int64
    right_ray_joint1_id::Int64
    right_ray_joint2_id::Int64
    base_line_prime_host_id::Int64
    base_line_prime_joint1_id::Int64
    base_line_prime_joint2_id::Int64
    right_ray_prime_host_id::Int64
    right_ray_prime_joint1_id::Int64
    right_ray_prime_joint2_id::Int64
    right_ray_double_host_id::Int64
    right_ray_double_joint1_id::Int64
    right_ray_double_joint2_id::Int64
    right_ray_triple_host_id::Int64
    right_ray_triple_joint1_id::Int64
    right_ray_triple_joint2_id::Int64
    label_bid::Int64
    label_aid::Int64
    label_cid::Int64
    label_did::Int64
    label_bprime_id::Int64
    label_aprime_id::Int64
    label_cprime_id::Int64
    label_dprime_id::Int64
    label_ddouble_id::Int64
    label_dtriple_id::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescendToB = 0f0
const PhaseDrawBaseLine = 1f0
const PhaseArcCToA = 2f0
const PhaseDrawRightRay = 3f0
const PhaseArcDToBPrime = 4f0
const PhaseDrawBaseLinePrime = 5f0
const PhaseArcCPrimeToAPrime = 6f0
const PhaseDrawRightRayPrime = 7f0
const PhasePenRiseBeforeGreenAngles = 8f0

const PhaseCompassDescendBAD = 9f0
const PhaseHighlightBADForward = 10f0
const PhaseHighlightBADBack = 11f0
const PhaseCompassArcBADToCAD = 12f0
const PhaseHighlightCADForward = 13f0
const PhaseHighlightCADBack = 14f0
const PhaseCompassArcCADToPrimeBAD = 15f0
const PhaseHighlightPrimeBADForward = 16f0
const PhaseHighlightPrimeBADBack = 17f0
const PhaseCompassArcPrimeBADToPrimeCAD = 18f0
const PhaseHighlightPrimeCADForward = 19f0
const PhaseHighlightPrimeCADBack = 20f0
const PhaseCompassRiseAfterGreenAngles = 21f0

const PhasePenDescendAForDouble = 22f0
const PhaseDrawRightRayDouble = 23f0
const PhasePenRiseBeforeDoubleAngles = 24f0
const PhaseCompassDescendBADDouble = 25f0
const PhaseHighlightBADDoubleForward = 26f0
const PhaseHighlightBADDoubleBack = 27f0
const PhaseCompassArcBADDoubleToPrimeBAD = 28f0
const PhaseHighlightPrimeBADFireForward = 29f0
const PhaseHighlightPrimeBADFireBack = 30f0
const PhaseCompassArcPrimeBADToCADDouble = 31f0
const PhaseHighlightCADDoubleForward = 32f0
const PhaseHighlightCADDoubleBack = 33f0
const PhaseCompassArcCADDoubleToPrimeCAD = 34f0
const PhaseHighlightPrimeCADFireForward = 35f0
const PhaseHighlightPrimeCADFireBack = 36f0
const PhaseCompassRiseAfterDoubleAngles = 37f0

const PhasePenDescendAForTriple = 38f0
const PhaseDrawRightRayTriple = 39f0
const PhasePenRiseBeforeTripleAngles = 40f0
const PhaseCompassDescendBADTriple = 41f0
const PhaseHighlightBADTripleForward = 42f0
const PhaseHighlightBADTripleBack = 43f0
const PhaseCompassArcBADTripleToPrimeBAD = 44f0
const PhaseHighlightPrimeBADFireAgainForward = 45f0
const PhaseHighlightPrimeBADFireAgainBack = 46f0
const PhaseCompassArcPrimeBADAgainToCADTriple = 47f0
const PhaseHighlightCADTripleForward = 48f0
const PhaseHighlightCADTripleBack = 49f0
const PhaseCompassArcCADTripleToPrimeCAD = 50f0
const PhaseHighlightPrimeCADFireAgainForward = 51f0
const PhaseHighlightPrimeCADFireAgainBack = 52f0
const PhaseCompassArcPrimeCADToBAD = 53f0
const PhaseHighlightBADLightForward = 54f0
const PhaseHighlightBADLightBack = 55f0
const PhaseCompassArcBADToCADAgain = 56f0
const PhaseHighlightCADLightForward = 57f0
const PhaseHighlightCADLightBack = 58f0
const PhaseCompassArcCADToPrimeBADLight = 59f0
const PhaseHighlightPrimeBADLightForward = 60f0
const PhaseHighlightPrimeBADLightBack = 61f0
const PhaseCompassArcPrimeBADLightToPrimeCADLight = 62f0
const PhaseHighlightPrimeCADLightForward = 63f0
const PhaseHighlightPrimeCADLightBack = 64f0
const PhaseCompassRiseEnd = 65f0
const PhaseFinalHold = 66f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.base_line_host_id, state.base_line_joint1_id, state.base_line_joint2_id,
        state.right_ray_host_id, state.right_ray_joint1_id, state.right_ray_joint2_id,
        state.base_line_prime_host_id, state.base_line_prime_joint1_id,
        state.base_line_prime_joint2_id, state.right_ray_prime_host_id,
        state.right_ray_prime_joint1_id, state.right_ray_prime_joint2_id,
        state.right_ray_double_host_id, state.right_ray_double_joint1_id,
        state.right_ray_double_joint2_id, state.right_ray_triple_host_id,
        state.right_ray_triple_joint1_id, state.right_ray_triple_joint2_id,
        state.label_bid, state.label_aid, state.label_cid, state.label_did,
        state.label_bprime_id, state.label_aprime_id, state.label_cprime_id,
        state.label_dprime_id, state.label_ddouble_id, state.label_dtriple_id,
        phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 15

All right angles are congruent to one another.

Proof: Let the angle BAD be congruent to its supplementary angle CAD, and, likewise, let the angle B'A'D' be congruent to its supplementary angle C'A'D'. Hence the angles BAD, CAD, B'A'D', and C'A'D' are all right angles. We will assume that the contrary of our proposition is true, namely, that the right angle B'A'D' is not congruent to the right angle BAD, and will show that this assumption leads to a contradiction. We lay off the angle B'A'D' upon the half-ray AB in such a manner that the side AD'' arising from this operation falls either within the angle BAD or within the angle CAD. Suppose, for example, the first of these possibilities to be true. Because of the congruence of the angles B'A'D' and BAD'', it follows from theorem 12 that angle C'A'D' is congruent to angle CAD'', and, as the angles B'A'D' and C'A'D' are congruent to each other, then, by IV, 5, the angle BAD'' must be congruent to CAD''.

Furthermore, since the angle BAD is congruent to the angle CAD, it is possible, by theorem 13, to find within the angle CAD a half-ray AD''' emanating from A, so that the angle BAD'' will be congruent to the angle CAD''', and also the angle DAD'' will be congruent to the angle DAD'''. The angle BAD'' was shown to be congruent to the angle CAD'', and, hence, by axiom IV, 5, the angle CAD''' is congruent to the angle CAD''. This, however, is not possible; for, according to axiom IV, 4, an angle can be laid off in a plane upon a given side of a given half-ray in only one way. With this our proposition is demonstrated. We can now introduce, in accordance with common usage, the terms "acute angle" and "obtuse angle."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 15}

All right angles are congruent to one another.

\textbf{Proof}: Let the angle $\angle BAD$ be congruent to its supplementary angle $\angle CAD$
\euclidangle[color=lightgreen,radius=2,start=90,end=180]\euclidangle[color=lightgreen,radius=2,end=90], and, likewise,
let the angle $\angle B'A'D'$ be congruent to its supplementary angle $\angle C'A'D'$
\euclidangle[color=lightgreen,radius=2,start=90,end=180]\euclidangle[color=lightgreen,radius=2,end=90].
Hence the angles $\angle BAD$ \euclidangle[color=lightgreen,radius=2,start=90,end=180], $\angle CAD$ \euclidangle[color=lightgreen,radius=2,end=90],
$\angle B'A'D'$ \euclidangle[color=lightgreen,radius=2,start=90,end=180], and $\angle C'A'D'$ \euclidangle[color=lightgreen,radius=2,end=90] are all right angles.
We will assume that the contrary of our proposition is true, namely, that the right angle
$\angle B'A'D'$ \euclidangle[color=lightgreen,radius=2,start=90,end=180] is not congruent to the right angle
$\angle BAD$ \euclidangle[color=lightgreen,radius=2,end=90], and will show that this assumption leads to a contradiction.
We lay off the angle $\angle B'A'D'$ upon the half-ray $AB$ \euclidline[color=steelblue,length=3,thickness=4] in such a
manner that the side $AD''$ \euclidline[color=firebrick,length=3,thickness=4] arising from this operation falls either
within the angle $\angle BAD$ or within the angle $\angle CAD$. Suppose, for example, the first of these possibilities
to be true. Because of the congruence of the angles $\angle B'A'D'$ and $\angle BAD''$, it follows from
\textit{theorem 12} that angle $\angle C'A'D'$ is congruent to angle $\angle CAD''$, and, as the angles
$\angle B'A'D'$ and $\angle C'A'D'$ are congruent to each other, then, by \textit{IV, 5}, the angle $\angle BAD''$
must be congruent to $\angle CAD''$.

Furthermore, since the angle $\angle BAD$ is congruent to the angle $\angle CAD$, it is possible, by \textit{theorem 13},
to find within the angle $\angle CAD$ a half-ray $AD'''$ \euclidline[color=firebrick,length=3,thickness=4] emanating
from $A$ \euclidpoint[color=plum1,size=0.5], so that the angle $\angle BAD''$ will be congruent to the angle
$\angle CAD'''$, and also the angle $\angle DAD''$ will be congruent to the angle $\angle DAD'''$. The angle
$\angle BAD''$ was shown to be congruent to the angle $\angle CAD''$, and, hence, by \textit{axiom IV, 5}, the angle
$\angle CAD'''$ is congruent to the angle $\angle CAD''$. This, however, is not possible; for, according to
\textit{axiom IV, 4}, an angle can be laid off in a plane upon a given side of a given half-ray in only one way. With
this our proposition is demonstrated. We can now introduce, in accordance with common usage, the terms "acute angle" and "obtuse angle."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    base_line_host_id = state.base_line_host_id
    base_line_joint2_id = state.base_line_joint2_id
    right_ray_host_id = state.right_ray_host_id
    right_ray_joint2_id = state.right_ray_joint2_id
    base_line_prime_host_id = state.base_line_prime_host_id
    base_line_prime_joint2_id = state.base_line_prime_joint2_id
    right_ray_prime_host_id = state.right_ray_prime_host_id
    right_ray_prime_joint2_id = state.right_ray_prime_joint2_id
    right_ray_double_host_id = state.right_ray_double_host_id
    right_ray_double_joint2_id = state.right_ray_double_joint2_id
    right_ray_triple_host_id = state.right_ray_triple_host_id
    right_ray_triple_joint2_id = state.right_ray_triple_joint2_id

    label_b_id = state.label_bid
    label_a_id = state.label_aid
    label_c_id = state.label_cid
    label_d_id = state.label_did
    label_b_prime_id = state.label_bprime_id
    label_a_prime_id = state.label_aprime_id
    label_c_prime_id = state.label_cprime_id
    label_d_prime_id = state.label_dprime_id
    label_d_double_id = state.label_ddouble_id
    label_d_triple_id = state.label_dtriple_id

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [base_line_host_id, right_ray_host_id,
         base_line_prime_host_id, right_ray_prime_host_id,
         right_ray_double_host_id, right_ray_triple_host_id,
         label_b_id, label_a_id, label_c_id, label_d_id,
         label_b_prime_id, label_a_prime_id, label_c_prime_id, label_d_prime_id,
         label_d_double_id, label_d_triple_id])

    OdinJuliaBridge.set_point_position(
        state_ptr, base_line_joint2_id, BaseLineStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, right_ray_joint2_id, RightRayStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, base_line_prime_joint2_id, BaseLinePrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, right_ray_prime_joint2_id, RightRayPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, right_ray_double_joint2_id, RightRayStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, right_ray_triple_joint2_id, RightRayStart)


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

    OdinJuliaBridge.set_pen_active(state_ptr, 0, BaseLineColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, 0f0, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    base_line = OdinJuliaBridge.create_new_line(
        state_ptr, BaseLineStart, BaseLineStart,
        BaseLineColor, 0f0)
    right_ray = OdinJuliaBridge.create_new_line(
        state_ptr, RightRayStart, RightRayStart,
        RightRayColor, 0f0)
    base_line_prime = OdinJuliaBridge.create_new_line(
        state_ptr, BaseLinePrimeStart, BaseLinePrimeStart,
        BaseLineColor, 0f0)
    right_ray_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RightRayPrimeStart, RightRayPrimeStart,
        RightRayColor, 0f0)
    right_ray_double = OdinJuliaBridge.create_new_line(
        state_ptr, RightRayStart, RightRayStart,
        ContradictionColor, 0f0)
    right_ray_triple = OdinJuliaBridge.create_new_line(
        state_ptr, RightRayStart, RightRayStart,
        ContradictionColor, 0f0)

    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    label_d = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', LabelDPoint, LabelColor, 16f0)
    label_b_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    label_c_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelCPrimePoint, LabelColor, 16f0)
    label_d_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'D', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelDPrimePoint, LabelColor, 16f0)
    label_d_double = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'D', OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME,
        LabelDDoublePoint, LabelColor, 16f0)
    label_d_triple = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'D', OdinJuliaBridge.LABEL_DECORATION_TRIPLEPRIME,
        LabelDTriplePoint, LabelColor, 16f0)



    state = AnimationState(
        base_line.host_id, base_line.joint1_id, base_line.joint2_id, right_ray.host_id,
        right_ray.joint1_id, right_ray.joint2_id, base_line_prime.host_id,
        base_line_prime.joint1_id, base_line_prime.joint2_id, right_ray_prime.host_id,
        right_ray_prime.joint1_id, right_ray_prime.joint2_id, right_ray_double.host_id,
        right_ray_double.joint1_id, right_ray_double.joint2_id, right_ray_triple.host_id,
        right_ray_triple.joint1_id, right_ray_triple.joint2_id, label_b.index,
        label_a.index, label_c.index, label_d.index, label_b_prime.index,
        label_a_prime.index, label_c_prime.index, label_d_prime.index,
        label_d_double.index, label_d_triple.index,
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
    base_line_host_id = state.base_line_host_id
    base_line_joint1_id = state.base_line_joint1_id
    base_line_joint2_id = state.base_line_joint2_id
    right_ray_host_id = state.right_ray_host_id
    right_ray_joint1_id = state.right_ray_joint1_id
    right_ray_joint2_id = state.right_ray_joint2_id
    base_line_prime_host_id = state.base_line_prime_host_id
    base_line_prime_joint1_id = state.base_line_prime_joint1_id
    base_line_prime_joint2_id = state.base_line_prime_joint2_id
    right_ray_prime_host_id = state.right_ray_prime_host_id
    right_ray_prime_joint1_id = state.right_ray_prime_joint1_id
    right_ray_prime_joint2_id = state.right_ray_prime_joint2_id
    right_ray_double_host_id = state.right_ray_double_host_id
    right_ray_double_joint1_id = state.right_ray_double_joint1_id
    right_ray_double_joint2_id = state.right_ray_double_joint2_id
    right_ray_triple_host_id = state.right_ray_triple_host_id
    right_ray_triple_joint1_id = state.right_ray_triple_joint1_id
    right_ray_triple_joint2_id = state.right_ray_triple_joint2_id

    label_b_id = state.label_bid
    label_a_id = state.label_aid
    label_c_id = state.label_cid
    label_d_id = state.label_did
    label_b_prime_id = state.label_bprime_id
    label_a_prime_id = state.label_aprime_id
    label_c_prime_id = state.label_cprime_id
    label_d_prime_id = state.label_dprime_id
    label_d_double_id = state.label_ddouble_id
    label_d_triple_id = state.label_dtriple_id

    if base_line_host_id < 0 || right_ray_host_id < 0 || base_line_prime_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescendToB
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointB[1], PointB[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, BaseLineColor)
            phase = PhaseDrawBaseLine
            timer = 0f0
        end
    elseif phase == PhaseDrawBaseLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            BaseLineStart, BaseLineEnd;
            penbrush=EdgeBrush,
            pencolor=BaseLineColor,
            line_host_id=base_line_host_id,
            line_joint1_id=base_line_joint1_id,
            line_joint2_id=base_line_joint2_id)
        if timer >= DrawEdgeDuration * BaseLineAMidShare
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
            phase = PhaseArcCToA
            timer = 0f0
        end
    elseif phase == PhaseArcCToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointC, PointA, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RightRayColor)
            phase = PhaseDrawRightRay
            timer = 0f0
        end
    elseif phase == PhaseDrawRightRay
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            RightRayStart, RightRayEnd;
            penbrush=EdgeBrush,
            pencolor=RightRayColor,
            line_host_id=right_ray_host_id,
            line_joint1_id=right_ray_joint1_id,
            line_joint2_id=right_ray_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_d_id)
            phase = PhaseArcDToBPrime
            timer = 0f0
        end
    elseif phase == PhaseArcDToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointD, PointBPrime, 0.28f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, BaseLineColor)
            phase = PhaseDrawBaseLinePrime
            timer = 0f0
        end
    elseif phase == PhaseDrawBaseLinePrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            BaseLinePrimeStart, BaseLinePrimeEnd;
            penbrush=EdgeBrush,
            pencolor=BaseLineColor,
            line_host_id=base_line_prime_host_id,
            line_joint1_id=base_line_prime_joint1_id,
            line_joint2_id=base_line_prime_joint2_id)
        if timer >= DrawEdgeDuration * BaseLinePrimeAMidShare
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
        end
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_c_prime_id)
            phase = PhaseArcCPrimeToAPrime
            timer = 0f0
        end
    elseif phase == PhaseArcCPrimeToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointCPrime,
            PointAPrime, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RightRayColor)
            phase = PhaseDrawRightRayPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawRightRayPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            RightRayPrimeStart, RightRayPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=RightRayColor,
            line_host_id=right_ray_prime_host_id,
            line_joint1_id=right_ray_prime_joint1_id,
            line_joint2_id=right_ray_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_d_prime_id)
            phase = PhasePenRiseBeforeGreenAngles
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeGreenAngles
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointDPrime[1], PointDPrime[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendBAD
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendBAD
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerBADStart[1], MarkerBADStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightBADForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADStart, AngleBADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBADBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADEnd, -AngleBADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBADToCAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBADToCAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointA,
            MarkerBADStart, MarkerCADStart; height=0.18f0)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightCADForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADStart, AngleCADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightCADBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADEnd, -AngleCADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCADToPrimeBAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCADToPrimeBAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerCADStart, MarkerBPrimeADPrimeStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeBADForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeStart,
            AngleBPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeBADBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeEnd,
            -AngleBPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeBADToPrimeCAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeBADToPrimeCAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointAPrime,
            MarkerBPrimeADPrimeStart, MarkerCPrimeADPrimeStart; height=0.18f0)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeCADForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeStart,
            AngleCPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeCADBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeEnd,
            -AngleCPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRiseAfterGreenAngles
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseAfterGreenAngles
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointAPrime[1], PointAPrime[2],
            MarkerCPrimeADPrimeStart[1], MarkerCPrimeADPrimeStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendAForDouble
            timer = 0f0
        end

    elseif phase == PhasePenDescendAForDouble
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ContradictionColor)
            phase = PhaseDrawRightRayDouble
            timer = 0f0
        end
    elseif phase == PhaseDrawRightRayDouble
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            RightRayStart, RightRayDoubleEnd;
            penbrush=EdgeBrush,
            pencolor=ContradictionColor,
            line_host_id=right_ray_double_host_id,
            line_joint1_id=right_ray_double_joint1_id,
            line_joint2_id=right_ray_double_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_d_double_id)
            phase = PhasePenRiseBeforeDoubleAngles
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeDoubleAngles
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointDDouble[1], PointDDouble[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendBADDouble
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendBADDouble
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerBADDoubleStart[1], MarkerBADDoubleStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightBADDoubleForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADDoubleForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADDoubleStart,
            AngleBADDoubleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBADDoubleBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADDoubleBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADDoubleEnd,
            -AngleBADDoubleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBADDoubleToPrimeBAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBADDoubleToPrimeBAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerBADDoubleStart, MarkerBPrimeADPrimeStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeBADFireForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADFireForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeStart,
            AngleBPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeBADFireBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADFireBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeEnd,
            -AngleBPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeBADToCADDouble
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeBADToCADDouble
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointA,
            MarkerBPrimeADPrimeStart, MarkerCADDoubleStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightCADDoubleForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADDoubleForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADDoubleStart,
            AngleCADDoubleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightCADDoubleBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADDoubleBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADDoubleEnd,
            -AngleCADDoubleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCADDoubleToPrimeCAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCADDoubleToPrimeCAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerCADDoubleStart, MarkerCPrimeADPrimeStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeCADFireForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADFireForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeStart,
            AngleCPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeCADFireBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADFireBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeEnd,
            -AngleCPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            OdinJuliaBridge.hide_point_batch(state_ptr, [
                right_ray_double_host_id, label_d_double_id])
            phase = PhaseCompassRiseAfterDoubleAngles
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseAfterDoubleAngles
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointAPrime[1], PointAPrime[2],
            MarkerCPrimeADPrimeStart[1], MarkerCPrimeADPrimeStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendAForTriple
            timer = 0f0
        end

    elseif phase == PhasePenDescendAForTriple
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ContradictionColor)
            phase = PhaseDrawRightRayTriple
            timer = 0f0
        end
    elseif phase == PhaseDrawRightRayTriple
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            RightRayStart, RightRayTripleEnd;
            penbrush=EdgeBrush,
            pencolor=ContradictionColor,
            line_host_id=right_ray_triple_host_id,
            line_joint1_id=right_ray_triple_joint1_id,
            line_joint2_id=right_ray_triple_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_d_triple_id)
            phase = PhasePenRiseBeforeTripleAngles
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeTripleAngles
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ,
            PointDTriple[1], PointDTriple[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendBADTriple
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendBADTriple
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerBADTripleStart[1], MarkerBADTripleStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightBADTripleForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADTripleForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADTripleStart,
            AngleBADTripleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBADTripleBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADTripleBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADTripleEnd,
            -AngleBADTripleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBADTripleToPrimeBAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBADTripleToPrimeBAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerBADTripleStart, MarkerBPrimeADPrimeStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeBADFireAgainForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADFireAgainForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeStart,
            AngleBPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeBADFireAgainBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADFireAgainBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeEnd,
            -AngleBPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeBADAgainToCADTriple
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeBADAgainToCADTriple
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointA,
            MarkerBPrimeADPrimeStart, MarkerCADTripleStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightCADTripleForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADTripleForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADTripleStart,
            AngleCADTripleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightCADTripleBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADTripleBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADTripleEnd,
            -AngleCADTripleTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCADTripleToPrimeCAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCADTripleToPrimeCAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerCADTripleStart, MarkerCPrimeADPrimeStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeCADFireAgainForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADFireAgainForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeStart,
            AngleCPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeCADFireAgainBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADFireAgainBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeEnd,
            -AngleCPrimeADPrimeTheta, MarkerRadius, ContradictionColor)
        timer += dt
        if timer >= CompassSweepDuration
            OdinJuliaBridge.hide_point_batch(state_ptr, [
                right_ray_triple_host_id, label_d_triple_id])
            phase = PhaseCompassArcPrimeCADToBAD
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeCADToBAD
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointA,
            MarkerCPrimeADPrimeStart, MarkerBADStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightBADLightForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADLightForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADStart, AngleBADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightBADLightBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightBADLightBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerBADEnd, -AngleBADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcBADToCADAgain
            timer = 0f0
        end
    elseif phase == PhaseCompassArcBADToCADAgain
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointA,
            MarkerBADStart, MarkerCADStart; height=0.18f0)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightCADLightForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADLightForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADStart, AngleCADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightCADLightBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightCADLightBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerCADEnd, -AngleCADTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcCADToPrimeBADLight
            timer = 0f0
        end
    elseif phase == PhaseCompassArcCADToPrimeBADLight
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerCADStart, MarkerBPrimeADPrimeStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeBADLightForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADLightForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeStart,
            AngleBPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeBADLightBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeBADLightBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerBPrimeADPrimeEnd,
            -AngleBPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeBADLightToPrimeCADLight
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeBADLightToPrimeCADLight
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointAPrime,
            MarkerBPrimeADPrimeStart, MarkerCPrimeADPrimeStart; height=0.18f0)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPrimeCADLightForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADLightForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeStart,
            AngleCPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightPrimeCADLightBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPrimeCADLightBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerCPrimeADPrimeEnd,
            -AngleCPrimeADPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRiseEnd
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseEnd
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointAPrime[1], PointAPrime[2],
            MarkerCPrimeADPrimeStart[1], MarkerCPrimeADPrimeStart[2])
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