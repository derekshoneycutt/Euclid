module HilbertChapterOneTheorem13

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop, animation_entry

const PointO = [0.16f0, 0.70f0, 0f0]
const PointA = [0.38f0, 0.62f0, 0f0]
const PointB = [0.34f0, 0.88f0, 0f0]

const RayHEnd = [0.50f0, 0.58f0, 0f0]
const RayKEnd = [0.42f0, 0.96f0, 0f0]

const PointOPrime = [0.61f0, 0.30f0, 0f0]
const PointAPrime = [0.83f0, 0.22f0, 0f0]
const PointBPrime = [0.79f0, 0.48f0, 0f0]

const RayHPrimeEnd = [0.95f0, 0.18f0, 0f0]
const RayKPrimeEnd = [0.87f0, 0.56f0, 0f0]

const CParameter = 0.55f0
const PointC = [
    PointA[1] + CParameter * (PointB[1] - PointA[1]),
    PointA[2] + CParameter * (PointB[2] - PointA[2]),
    0f0,
]
const PointCPrime = [
    PointAPrime[1] + CParameter * (PointBPrime[1] - PointAPrime[1]),
    PointAPrime[2] + CParameter * (PointBPrime[2] - PointAPrime[2]),
    0f0,
]

const LRayScale = 2.0f0
const LPrimeRayScale = 1.85f0
const RayLEnd = [
    PointO[1] + LRayScale * (PointC[1] - PointO[1]),
    PointO[2] + LRayScale * (PointC[2] - PointO[2]),
    0f0,
]
const RayLPrimeEnd = [
    PointOPrime[1] + LPrimeRayScale * (PointCPrime[1] - PointOPrime[1]),
    PointOPrime[2] + LPrimeRayScale * (PointCPrime[2] - PointOPrime[2]),
    0f0,
]

const RayHStart = PointO
const RayKStart = PointO
const RayHPrimeStart = PointOPrime
const RayKPrimeStart = PointOPrime
const RayLStart = PointO
const RayLPrimeStart = PointOPrime

const SegmentABStart = PointA
const SegmentABEnd = PointB
const SegmentAPrimeBPrimeStart = PointAPrime
const SegmentAPrimeBPrimeEnd = PointBPrime

const MarkerRadius = 0.08f0

const ThetaOH = atan(RayHEnd[2] - PointO[2], RayHEnd[1] - PointO[1])
const ThetaOK = atan(RayKEnd[2] - PointO[2], RayKEnd[1] - PointO[1])
const ThetaOPrimeH = Float32(atan(
    RayHPrimeEnd[2] - PointOPrime[2], RayHPrimeEnd[1] - PointOPrime[1]))
const ThetaOPrimeK = Float32(atan(
    RayKPrimeEnd[2] - PointOPrime[2], RayKPrimeEnd[1] - PointOPrime[1]))

const ThetaAAO = atan(PointO[2] - PointA[2], PointO[1] - PointA[1])
const ThetaAAB = atan(PointB[2] - PointA[2], PointB[1] - PointA[1])
const ThetaAPrimeAO = Float32(atan(
    PointOPrime[2] - PointAPrime[2], PointOPrime[1] - PointAPrime[1]))
const ThetaAPrimeAB = Float32(atan(
    PointBPrime[2] - PointAPrime[2], PointBPrime[1] - PointAPrime[1]))

const ThetaBBO = atan(PointO[2] - PointB[2], PointO[1] - PointB[1])
const ThetaBBA = atan(PointA[2] - PointB[2], PointA[1] - PointB[1])
const ThetaBPrimeBO = Float32(atan(
    PointOPrime[2] - PointBPrime[2], PointOPrime[1] - PointBPrime[1]))
const ThetaBPrimeBA = Float32(atan(
    PointAPrime[2] - PointBPrime[2], PointAPrime[1] - PointBPrime[1]))

const MarkerOHStart = [
    PointO[1] + MarkerRadius * cos(ThetaOH),
    PointO[2] + MarkerRadius * sin(ThetaOH),
    0f0,
]
const MarkerOHEnd = [
    PointO[1] + MarkerRadius * cos(ThetaOK),
    PointO[2] + MarkerRadius * sin(ThetaOK),
    0f0,
]
const MarkerOPrimeHStart = [
    PointOPrime[1] + MarkerRadius * cos(ThetaOPrimeH),
    PointOPrime[2] + MarkerRadius * sin(ThetaOPrimeH),
    0f0,
]
const MarkerOPrimeHEnd = [
    PointOPrime[1] + MarkerRadius * cos(ThetaOPrimeK),
    PointOPrime[2] + MarkerRadius * sin(ThetaOPrimeK),
    0f0,
]

const MarkerOABStart = [
    PointA[1] + MarkerRadius * cos(ThetaAAO),
    PointA[2] + MarkerRadius * sin(ThetaAAO),
    0f0,
]
const MarkerOABEnd = [
    PointA[1] + MarkerRadius * cos(ThetaAAB),
    PointA[2] + MarkerRadius * sin(ThetaAAB),
    0f0,
]
const MarkerOPrimeAPrimeBPrimeStart = [
    PointAPrime[1] + MarkerRadius * cos(ThetaAPrimeAO),
    PointAPrime[2] + MarkerRadius * sin(ThetaAPrimeAO),
    0f0,
]
const MarkerOPrimeAPrimeBPrimeEnd = [
    PointAPrime[1] + MarkerRadius * cos(ThetaAPrimeAB),
    PointAPrime[2] + MarkerRadius * sin(ThetaAPrimeAB),
    0f0,
]

const MarkerOBAStart = [
    PointB[1] + MarkerRadius * cos(ThetaBBO),
    PointB[2] + MarkerRadius * sin(ThetaBBO),
    0f0,
]
const MarkerOBAEnd = [
    PointB[1] + MarkerRadius * cos(ThetaBBA),
    PointB[2] + MarkerRadius * sin(ThetaBBA),
    0f0,
]
const MarkerOPrimeBPrimeAPrimeStart = [
    PointBPrime[1] + MarkerRadius * cos(ThetaBPrimeBO),
    PointBPrime[2] + MarkerRadius * sin(ThetaBPrimeBO),
    0f0,
]
const MarkerOPrimeBPrimeAPrimeEnd = [
    PointBPrime[1] + MarkerRadius * cos(ThetaBPrimeBA),
    PointBPrime[2] + MarkerRadius * sin(ThetaBPrimeBA),
    0f0,
]

const AngleOHKTheta = ThetaOK - ThetaOH
const AngleOPrimeHKTheta = ThetaOPrimeK - ThetaOPrimeH
const AngleOABTheta = ThetaAAB - ThetaAAO
const AngleOPrimeAPrimeBPrimeTheta = ThetaAPrimeAB - ThetaAPrimeAO
const AngleOBATheta = ThetaBBA - ThetaBBO
const AngleOPrimeBPrimeAPrimeTheta = ThetaBPrimeBA - ThetaBPrimeBO

const LabelColor = :plum1
const HighlightColor = :lightgreen

const RayHColor = :steelblue
const RayKColor = :palevioletred1
const RayLColor = :grey60
const SegmentABColor = :khaki3

const PointAuxColor = :grey60
const PointCColor = :steelblue

const EdgeBrush = 5f0
const PointBrush = 6f0
const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const LabelOPoint = PointO + [-0.04f0, -0.04f0, 0f0]
const LabelOPrimePoint = PointOPrime + [-0.04f0, -0.04f0, 0f0]
const LabelAPoint = PointA + [0.01f0, -0.04f0, 0f0]
const LabelBPoint = PointB + [0.01f0, 0.04f0, 0f0]
const LabelAPrimePoint = PointAPrime + [0.01f0, -0.04f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0.01f0, 0.04f0, 0f0]
const LabelCPoint = PointC + [0.05f0, 0.00f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0.05f0, 0.00f0, 0f0]
const LabelHPoint = RayHEnd + [0.03f0, -0.01f0, 0f0]
const LabelKPoint = RayKEnd + [0.01f0, 0.03f0, 0f0]
const LabelHPrimePoint = RayHPrimeEnd + [0.03f0, -0.01f0, 0f0]
const LabelKPrimePoint = RayKPrimeEnd + [0.01f0, 0.03f0, 0f0]
const LabelLPoint = RayLEnd + [0.02f0, 0.03f0, 0f0]
const LabelLPrimePoint = RayLPrimeEnd + [0.02f0, 0.03f0, 0f0]

const DescendDuration = 1.8f0
const DrawEdgeDuration = 2.2f0
const DrawPointDuration = 1.5f0
const ArcMoveDuration = 1.35f0
const DragDuration = 1.25f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const CompassSweepDuration = 0.95f0
const FinalHoldDuration = 0.35f0

"""Complete immutable state for one Theorem 13 animation generation."""
struct AnimationState
    ray_hhost_id::Int64
    ray_hjoint1_id::Int64
    ray_hjoint2_id::Int64
    ray_khost_id::Int64
    ray_kjoint1_id::Int64
    ray_kjoint2_id::Int64
    ray_hprime_host_id::Int64
    ray_hprime_joint1_id::Int64
    ray_hprime_joint2_id::Int64
    ray_kprime_host_id::Int64
    ray_kprime_joint1_id::Int64
    ray_kprime_joint2_id::Int64
    ray_lhost_id::Int64
    ray_ljoint1_id::Int64
    ray_ljoint2_id::Int64
    ray_lprime_host_id::Int64
    ray_lprime_joint1_id::Int64
    ray_lprime_joint2_id::Int64
    segment_abhost_id::Int64
    segment_abjoint1_id::Int64
    segment_abjoint2_id::Int64
    segment_aprime_bprime_host_id::Int64
    segment_aprime_bprime_joint1_id::Int64
    segment_aprime_bprime_joint2_id::Int64
    point_aid::Int64
    point_bid::Int64
    point_aprime_id::Int64
    point_bprime_id::Int64
    point_cid::Int64
    point_cprime_id::Int64
    label_oid::Int64
    label_oprime_id::Int64
    label_aid::Int64
    label_bid::Int64
    label_aprime_id::Int64
    label_bprime_id::Int64
    label_cid::Int64
    label_cprime_id::Int64
    label_hid::Int64
    label_kid::Int64
    label_hprime_id::Int64
    label_kprime_id::Int64
    label_lid::Int64
    label_lprime_id::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescendToO = 0f0
const PhaseDrawRayH = 1f0
const PhaseArcHToO = 2f0
const PhaseDrawRayK = 3f0
const PhaseArcOToOPrime = 4f0
const PhaseDrawRayHPrime = 5f0
const PhaseArcHPrimeToOPrime = 6f0
const PhaseDrawRayKPrime = 7f0
const PhasePenRiseBeforeAngleHK = 8f0

const PhaseCompassDescendHK = 9f0
const PhaseHighlightHKForward = 10f0
const PhaseHighlightHKBack = 11f0
const PhaseCompassArcHKToPrime = 12f0
const PhaseHighlightHPrimeKPrimeForward = 13f0
const PhaseHighlightHPrimeKPrimeBack = 14f0
const PhaseCompassRiseAfterHK = 15f0

const PhasePenDescendOForL = 16f0
const PhaseDrawRayL = 17f0
const PhaseArcOToA = 18f0
const PhaseDrawPointA = 19f0
const PhaseArcAToB = 20f0
const PhaseDrawPointB = 21f0
const PhaseArcBToOPrime = 22f0
const PhaseArcOPrimeToAPrime = 23f0
const PhaseDrawPointAPrime = 24f0
const PhaseArcAPrimeToBPrime = 25f0
const PhaseDrawPointBPrime = 26f0

const PhaseArcBPrimeToOForOA = 27f0
const PhaseDragOAForward = 28f0
const PhaseDragOABack = 29f0
const PhaseArcOToOPrimeForPrimeOA = 30f0
const PhaseDragOPrimeAForward = 31f0
const PhaseDragOPrimeABack = 32f0
const PhaseArcOPrimeToOForOB = 33f0
const PhaseDragOBForward = 34f0
const PhaseDragOBBack = 35f0
const PhaseArcOToOPrimeForPrimeOB = 36f0
const PhaseDragOPrimeBForward = 37f0
const PhaseDragOPrimeBBack = 38f0

const PhaseArcOPrimeToAForAB = 39f0
const PhaseDrawSegmentAB = 40f0
const PhaseArcBToAPrimeForPrimeAB = 41f0
const PhaseDrawSegmentAPrimeBPrime = 42f0
const PhaseArcBPrimeToAForABHighlight = 43f0
const PhaseDragABForward = 44f0
const PhaseDragABBack = 45f0
const PhaseArcAToAPrimeForPrimeABHighlight = 46f0
const PhaseDragAPrimeBPrimeForward = 47f0
const PhaseDragAPrimeBPrimeBack = 48f0
const PhasePenRiseBeforeAngleOAB = 49f0

const PhaseCompassDescendOAB = 50f0
const PhaseHighlightOABForward = 51f0
const PhaseHighlightOABBack = 52f0
const PhaseCompassArcOABToPrime = 53f0
const PhaseHighlightOPrimeAPrimeBPrimeForward = 54f0
const PhaseHighlightOPrimeAPrimeBPrimeBack = 55f0
const PhaseCompassArcPrimeToOBA = 56f0
const PhaseHighlightOBAForward = 57f0
const PhaseHighlightOBABack = 58f0
const PhaseCompassArcOBAToPrime = 59f0
const PhaseHighlightOPrimeBPrimeAPrimeForward = 60f0
const PhaseHighlightOPrimeBPrimeAPrimeBack = 61f0
const PhaseCompassRiseAfterAngleOAB = 62f0

const PhasePenDescendC = 63f0
const PhaseDrawPointC = 64f0
const PhaseArcCToCPrime = 65f0
const PhaseDrawPointCPrime = 66f0
const PhaseArcCPrimeToAForAC = 67f0
const PhaseDragACForward = 68f0
const PhaseDragACBack = 69f0
const PhaseArcAToAPrimeForPrimeAC = 70f0
const PhaseDragAPrimeCPrimeForward = 71f0
const PhaseDragAPrimeCPrimeBack = 72f0
const PhaseArcAPrimeToBForBC = 73f0
const PhaseDragBCForward = 74f0
const PhaseDragBCBack = 75f0
const PhaseArcBToBPrimeForPrimeBC = 76f0
const PhaseDragBPrimeCPrimeForward = 77f0
const PhaseDragBPrimeCPrimeBack = 78f0
const PhaseArcBPrimeToOPrimeForLPrime = 79f0
const PhaseDrawRayLPrime = 80f0
const PhasePenRiseEnd = 81f0
const PhaseFinalHold = 82f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.ray_hhost_id, state.ray_hjoint1_id, state.ray_hjoint2_id,
        state.ray_khost_id, state.ray_kjoint1_id, state.ray_kjoint2_id,
        state.ray_hprime_host_id, state.ray_hprime_joint1_id, state.ray_hprime_joint2_id,
        state.ray_kprime_host_id, state.ray_kprime_joint1_id, state.ray_kprime_joint2_id,
        state.ray_lhost_id, state.ray_ljoint1_id, state.ray_ljoint2_id,
        state.ray_lprime_host_id, state.ray_lprime_joint1_id, state.ray_lprime_joint2_id,
        state.segment_abhost_id, state.segment_abjoint1_id,
        state.segment_abjoint2_id, state.segment_aprime_bprime_host_id,
        state.segment_aprime_bprime_joint1_id, state.segment_aprime_bprime_joint2_id,
        state.point_aid, state.point_bid, state.point_aprime_id, state.point_bprime_id,
        state.point_cid, state.point_cprime_id, state.label_oid, state.label_oprime_id,
        state.label_aid, state.label_bid, state.label_aprime_id, state.label_bprime_id,
        state.label_cid, state.label_cprime_id, state.label_hid, state.label_kid,
        state.label_hprime_id, state.label_kprime_id, state.label_lid,
        state.label_lprime_id,
        phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 13

Let the angle (h, k) of the plane α be congruent to the angle (h', k') of the plane α', and, furthermore, let l be a half-ray in the plane α emanating from the vertex of the angle (h, k) and lying within this angle. Then there always exists in the plane α' a half-ray l' emanating from the vertex of the angle (h', k') and lying within this angle so that we have

    ∠(h, l) ≡ ∠(h', l'),   ∠(k, l) ≡ ∠(k', l').

Proof: We will represent the vertices of the angles (h, k) and (h', k') by O and O', respectively, and so select upon the sides h, k, h', k' the points A, B, A', B' so that the congruences

    OA ≡ O'A',   OB ≡ O'B'

are fulfilled. Because of the congruence of the triangles OAB and O'A'B', we have at once

    AB ≡ A'B',   ∠OAB ≡ ∠O'A'B',   ∠OBA ≡ ∠O'B'A'.

Let the straight line AB intersect l in C. Take the point C' upon the segment A'B' so that A'C' ≡ AC. Then O'C' is the required half-ray. In fact, it follows directly from these congruences, by aid of axiom IV, 3, that BC ≡ B'C'. Furthermore, the triangles OAC and O'A'C' are congruent to each other, and the same is true also of the triangles OCB and O'B'C'. With this our proposition is demonstrated."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 13}

Let the angle $\angle(h, k)$ \euclidangle[color=lightgreen,radius=2,end=60,filled] of the plane $\alpha$ be congruent
to the angle $\angle(h', k')$ \euclidangle[color=lightgreen,radius=2,end=60,filled] of the plane $\alpha'$,
and, furthermore, let $l$ \euclidline[color=grey60,length=3,thickness=4] be a half-ray in the plane $\alpha$ emanating
from the vertex of the angle $\angle(h, k)$ \euclidangle[color=lightgreen,radius=2,end=60,filled]
and lying within this angle. Then there always exists in the plane $\alpha'$ a half-ray
$l'$ \euclidline[color=grey60,length=3,thickness=4] emanating from the
vertex of the angle $\angle(h', k')$ \euclidangle[color=lightgreen,radius=2,end=60,filled] and lying within this angle so that we have

    $\angle(h, l) \equiv \angle(h', l')$ \euclidangle[color=lightgreen,radius=2,end=60,filled],   $\angle(k, l) \equiv \angle(k', l')$ \euclidangle[color=lightgreen,radius=2,end=60,filled].

\textbf{Proof}: We will represent the vertices of the angles
$\angle(h, k)$ \euclidangle[color=lightgreen,radius=2,end=60,filled] and
$\angle(h', k')$ \euclidangle[color=lightgreen,radius=2,end=60,filled] by
$O$ \euclidpoint[color=plum1,size=0.5] and $O'$ \euclidpoint[color=plum1,size=0.5],
respectively, and so select upon the sides
$h$ \euclidline[color=steelblue,length=3,thickness=4], $k$ \euclidline[color=palevioletred1,length=3,thickness=4],
$h'$ \euclidline[color=steelblue,length=3,thickness=4], $k'$ \euclidline[color=palevioletred1,length=3,thickness=4]
the points $A$ \euclidpoint[color=grey60,size=1], $B$ \euclidpoint[color=grey60,size=1],
$A'$ \euclidpoint[color=grey60,size=1], $B'$ \euclidpoint[color=grey60,size=1] so that the congruences

    $OA$ \euclidline[color=steelblue,length=3,thickness=4] $\equiv O'A'$ \euclidline[color=steelblue,length=3,thickness=4],   $OB$ \euclidline[color=palevioletred1,length=3,thickness=4] $\equiv O'B'$ \euclidline[color=palevioletred1,length=3,thickness=4]

are fulfilled. Because of the congruence of the triangles
$OAB$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3]
and $O'A'B'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=steelblue,edge3_color=khaki3], we have at once

    $AB$ \euclidline[color=khaki3,length=3,thickness=4] $\equiv A'B'$ \euclidline[color=khaki3,length=3,thickness=4],   $\angle OAB \equiv \angle O'A'B'$ \euclidangle[color=lightgreen,radius=2,end=60,filled],   $\angle OBA \equiv \angle O'B'A'$ \euclidangle[color=lightgreen,radius=2,end=60,filled].

Let the straight line $AB$ \euclidline[color=khaki3,length=3,thickness=4] intersect
$l$ \euclidline[color=grey60,length=3,thickness=4] in $C$ \euclidpoint[color=steelblue,size=1]. Take the point
$C'$ \euclidpoint[color=steelblue,size=1] upon the segment
$A'B'$ \euclidline[color=khaki3,length=3,thickness=4] so that
$A'C'$ \euclidline[color=khaki3,length=3,thickness=4] $\equiv AC$ \euclidline[color=khaki3,length=3,thickness=4].
Then $O'C'$ \euclidline[color=grey60,length=3,thickness=4] is the required half-ray. In fact, it follows directly from these congruences, by aid of
\textit{axiom IV, 3}, that $BC$ \euclidline[color=khaki3,length=3,thickness=4] $\equiv B'C'$ \euclidline[color=khaki3,length=3,thickness=4].
Furthermore, the triangles $OAC$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=grey60,edge2_color=steelblue,edge3_color=khaki3] and
$O'A'C'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=grey60,edge2_color=steelblue,edge3_color=khaki3] are congruent to each other,
and the same is true also of the triangles
$OCB$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=grey60,edge3_color=khaki3] and
$O'B'C'$ \euclidtriangle[height=2,width=3,thickness=2,edge1_color=palevioletred1,edge2_color=grey60,edge3_color=khaki3].
With this our proposition is demonstrated."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    ray_h_host_id = state.ray_hhost_id
    ray_h_joint2_id = state.ray_hjoint2_id
    ray_k_host_id = state.ray_khost_id
    ray_k_joint2_id = state.ray_kjoint2_id
    ray_h_prime_host_id = state.ray_hprime_host_id
    ray_h_prime_joint2_id = state.ray_hprime_joint2_id
    ray_k_prime_host_id = state.ray_kprime_host_id
    ray_k_prime_joint2_id = state.ray_kprime_joint2_id
    ray_l_host_id = state.ray_lhost_id
    ray_l_joint2_id = state.ray_ljoint2_id
    ray_l_prime_host_id = state.ray_lprime_host_id
    ray_l_prime_joint2_id = state.ray_lprime_joint2_id

    segment_a_b_host_id = state.segment_abhost_id
    segment_a_b_joint2_id = state.segment_abjoint2_id
    segment_a_prime_b_prime_host_id = state.segment_aprime_bprime_host_id
    segment_a_prime_b_prime_joint2_id = state.segment_aprime_bprime_joint2_id

    point_a_id = state.point_aid
    point_b_id = state.point_bid
    point_a_prime_id = state.point_aprime_id
    point_b_prime_id = state.point_bprime_id
    point_c_id = state.point_cid
    point_c_prime_id = state.point_cprime_id

    label_o_id = state.label_oid
    label_o_prime_id = state.label_oprime_id
    label_a_id = state.label_aid
    label_b_id = state.label_bid
    label_a_prime_id = state.label_aprime_id
    label_b_prime_id = state.label_bprime_id
    label_c_id = state.label_cid
    label_c_prime_id = state.label_cprime_id
    label_h_id = state.label_hid
    label_k_id = state.label_kid
    label_h_prime_id = state.label_hprime_id
    label_k_prime_id = state.label_kprime_id
    label_l_id = state.label_lid
    label_l_prime_id = state.label_lprime_id

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [ray_h_host_id, ray_k_host_id, ray_h_prime_host_id, ray_k_prime_host_id,
         ray_l_host_id, ray_l_prime_host_id,
         segment_a_b_host_id, segment_a_prime_b_prime_host_id,
         point_a_id, point_b_id, point_a_prime_id, point_b_prime_id,
         point_c_id, point_c_prime_id,
         label_o_id, label_o_prime_id, label_a_id, label_b_id,
         label_a_prime_id, label_b_prime_id, label_c_id, label_c_prime_id,
         label_h_id, label_k_id, label_h_prime_id, label_k_prime_id,
         label_l_id, label_l_prime_id])

    OdinJuliaBridge.set_point_position(
        state_ptr, ray_h_joint2_id, RayHStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, ray_k_joint2_id, RayKStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, ray_h_prime_joint2_id, RayHPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, ray_k_prime_joint2_id, RayKPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, ray_l_joint2_id, RayLStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, ray_l_prime_joint2_id, RayLPrimeStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, segment_a_b_joint2_id, SegmentABStart)
    OdinJuliaBridge.set_point_position(
        state_ptr, segment_a_prime_b_prime_joint2_id, SegmentAPrimeBPrimeStart)


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

    OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, 0f0, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    ray_h = OdinJuliaBridge.create_new_line(
        state_ptr, RayHStart, RayHStart, RayHColor, 0f0)
    ray_k = OdinJuliaBridge.create_new_line(
        state_ptr, RayKStart, RayKStart, RayKColor, 0f0)
    ray_h_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RayHPrimeStart, RayHPrimeStart, RayHColor, 0f0)
    ray_k_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RayKPrimeStart, RayKPrimeStart, RayKColor, 0f0)
    ray_l = OdinJuliaBridge.create_new_line(
        state_ptr, RayLStart, RayLStart, RayLColor, 0f0)
    ray_l_prime = OdinJuliaBridge.create_new_line(
        state_ptr, RayLPrimeStart, RayLPrimeStart, RayLColor, 0f0)

    segment_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, SegmentABStart, SegmentABStart, SegmentABColor, 0f0)
    segment_a_prime_b_prime = OdinJuliaBridge.create_new_line(
        state_ptr, SegmentAPrimeBPrimeStart,
        SegmentAPrimeBPrimeStart, SegmentABColor, 0f0)

    point_a = OdinJuliaBridge.create_new_point(state_ptr, PointA, PointAuxColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(state_ptr, PointB, PointAuxColor, 0f0)
    point_a_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointAPrime, PointAuxColor, 0f0)
    point_b_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointBPrime, PointAuxColor, 0f0)
    point_c = OdinJuliaBridge.create_new_point(state_ptr, PointC, PointCColor, 0f0)
    point_c_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointCPrime, PointCColor, 0f0)

    label_o = OdinJuliaBridge.create_new_label(
        state_ptr, 'O', LabelOPoint, LabelColor, 16f0)
    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', LabelCPoint, LabelColor, 16f0)

    label_o_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'O', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelOPrimePoint, LabelColor, 16f0)
    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    label_b_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    label_c_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelCPrimePoint, LabelColor, 16f0)
    label_h = OdinJuliaBridge.create_new_label(
        state_ptr, 'h', LabelHPoint, LabelColor, 16f0)
    label_k = OdinJuliaBridge.create_new_label(
        state_ptr, 'k', LabelKPoint, LabelColor, 16f0)
    label_l = OdinJuliaBridge.create_new_label(
        state_ptr, 'l', LabelLPoint, LabelColor, 16f0)
    label_h_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'h', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelHPrimePoint, LabelColor, 16f0)
    label_k_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'k', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelKPrimePoint, LabelColor, 16f0)
    label_l_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'l', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelLPrimePoint, LabelColor, 16f0)





    state = AnimationState(
        ray_h.host_id, ray_h.joint1_id, ray_h.joint2_id, ray_k.host_id,
        ray_k.joint1_id, ray_k.joint2_id, ray_h_prime.host_id, ray_h_prime.joint1_id,
        ray_h_prime.joint2_id, ray_k_prime.host_id, ray_k_prime.joint1_id,
        ray_k_prime.joint2_id, ray_l.host_id, ray_l.joint1_id, ray_l.joint2_id,
        ray_l_prime.host_id, ray_l_prime.joint1_id, ray_l_prime.joint2_id,
        segment_a_b.host_id, segment_a_b.joint1_id,
        segment_a_b.joint2_id, segment_a_prime_b_prime.host_id,
        segment_a_prime_b_prime.joint1_id, segment_a_prime_b_prime.joint2_id,
        point_a.index, point_b.index, point_a_prime.index, point_b_prime.index,
        point_c.index, point_c_prime.index, label_o.index, label_o_prime.index,
        label_a.index, label_b.index, label_a_prime.index, label_b_prime.index,
        label_c.index, label_c_prime.index, label_h.index, label_k.index,
        label_h_prime.index, label_k_prime.index, label_l.index, label_l_prime.index,
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
    ray_h_host_id = state.ray_hhost_id
    ray_h_joint1_id = state.ray_hjoint1_id
    ray_h_joint2_id = state.ray_hjoint2_id
    ray_k_host_id = state.ray_khost_id
    ray_k_joint1_id = state.ray_kjoint1_id
    ray_k_joint2_id = state.ray_kjoint2_id
    ray_h_prime_host_id = state.ray_hprime_host_id
    ray_h_prime_joint1_id = state.ray_hprime_joint1_id
    ray_h_prime_joint2_id = state.ray_hprime_joint2_id
    ray_k_prime_host_id = state.ray_kprime_host_id
    ray_k_prime_joint1_id = state.ray_kprime_joint1_id
    ray_k_prime_joint2_id = state.ray_kprime_joint2_id
    ray_l_host_id = state.ray_lhost_id
    ray_l_joint1_id = state.ray_ljoint1_id
    ray_l_joint2_id = state.ray_ljoint2_id
    ray_l_prime_host_id = state.ray_lprime_host_id
    ray_l_prime_joint1_id = state.ray_lprime_joint1_id
    ray_l_prime_joint2_id = state.ray_lprime_joint2_id

    segment_a_b_host_id = state.segment_abhost_id
    segment_a_b_joint1_id = state.segment_abjoint1_id
    segment_a_b_joint2_id = state.segment_abjoint2_id
    segment_a_prime_b_prime_host_id = state.segment_aprime_bprime_host_id
    segment_a_prime_b_prime_joint1_id = state.segment_aprime_bprime_joint1_id
    segment_a_prime_b_prime_joint2_id = state.segment_aprime_bprime_joint2_id

    point_a_id = state.point_aid
    point_b_id = state.point_bid
    point_a_prime_id = state.point_aprime_id
    point_b_prime_id = state.point_bprime_id
    point_c_id = state.point_cid
    point_c_prime_id = state.point_cprime_id

    label_o_id = state.label_oid
    label_o_prime_id = state.label_oprime_id
    label_a_id = state.label_aid
    label_b_id = state.label_bid
    label_a_prime_id = state.label_aprime_id
    label_b_prime_id = state.label_bprime_id
    label_c_id = state.label_cid
    label_c_prime_id = state.label_cprime_id
    label_h_id = state.label_hid
    label_k_id = state.label_kid
    label_h_prime_id = state.label_hprime_id
    label_k_prime_id = state.label_kprime_id
    label_l_id = state.label_lid
    label_l_prime_id = state.label_lprime_id

    if ray_h_host_id < 0 || ray_k_host_id < 0 ||
       ray_h_prime_host_id < 0 || ray_k_prime_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescendToO
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointO[1], PointO[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, label_o_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
            phase = PhaseDrawRayH
            timer = 0f0
        end
    elseif phase == PhaseDrawRayH
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            RayHStart, RayHEnd;
            penbrush=EdgeBrush,
            pencolor=RayHColor,
            line_host_id=ray_h_host_id,
            line_joint1_id=ray_h_joint1_id,
            line_joint2_id=ray_h_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_h_id)
            phase = PhaseArcHToO
            timer = 0f0
        end
    elseif phase == PhaseArcHToO
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayHEnd, PointO, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKColor)
            phase = PhaseDrawRayK
            timer = 0f0
        end
    elseif phase == PhaseDrawRayK
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            RayKStart, RayKEnd;
            penbrush=EdgeBrush,
            pencolor=RayKColor,
            line_host_id=ray_k_host_id,
            line_joint1_id=ray_k_joint1_id,
            line_joint2_id=ray_k_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_k_id)
            phase = PhaseArcOToOPrime
            timer = 0f0
        end
    elseif phase == PhaseArcOToOPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayKEnd, PointOPrime, 0.28f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, label_o_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayHColor)
            phase = PhaseDrawRayHPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawRayHPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            RayHPrimeStart, RayHPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=RayHColor,
            line_host_id=ray_h_prime_host_id,
            line_joint1_id=ray_h_prime_joint1_id,
            line_joint2_id=ray_h_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_h_prime_id)
            phase = PhaseArcHPrimeToOPrime
            timer = 0f0
        end
    elseif phase == PhaseArcHPrimeToOPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            RayHPrimeEnd, PointOPrime, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayKColor)
            phase = PhaseDrawRayKPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawRayKPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            RayKPrimeStart, RayKPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=RayKColor,
            line_host_id=ray_k_prime_host_id,
            line_joint1_id=ray_k_prime_joint1_id,
            line_joint2_id=ray_k_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_k_prime_id)
            phase = PhasePenRiseBeforeAngleHK
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeAngleHK
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ,
            RayKPrimeEnd[1], RayKPrimeEnd[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendHK
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendHK
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointO[1], PointO[2], MarkerOHStart[1], MarkerOHStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightHKForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightHKForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointO, MarkerOHStart, AngleOHKTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightHKBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightHKBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointO, MarkerOHEnd, -AngleOHKTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcHKToPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcHKToPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointO, PointOPrime,
            MarkerOHStart, MarkerOPrimeHStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightHPrimeKPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightHPrimeKPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointOPrime, MarkerOPrimeHStart,
            AngleOPrimeHKTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightHPrimeKPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightHPrimeKPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointOPrime, MarkerOPrimeHEnd,
            -AngleOPrimeHKTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRiseAfterHK
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseAfterHK
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointOPrime[1], PointOPrime[2],
            MarkerOPrimeHStart[1], MarkerOPrimeHStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendOForL
            timer = 0f0
        end

    elseif phase == PhasePenDescendOForL
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointO[1], PointO[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayLColor)
            phase = PhaseDrawRayL
            timer = 0f0
        end
    elseif phase == PhaseDrawRayL
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            RayLStart, RayLEnd;
            penbrush=EdgeBrush,
            pencolor=RayLColor,
            line_host_id=ray_l_host_id,
            line_joint1_id=ray_l_joint1_id,
            line_joint2_id=ray_l_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_l_id)
            phase = PhaseArcOToA
            timer = 0f0
        end
    elseif phase == PhaseArcOToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, RayLEnd, PointA, 0.20f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
            phase = PhaseDrawPointA
            timer = 0f0
        end
    elseif phase == PhaseDrawPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointA, PointBrush, PointAuxColor, point_a_id)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcAToB
            timer = 0f0
        end
    elseif phase == PhaseArcAToB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointB, 0.20f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
            phase = PhaseDrawPointB
            timer = 0f0
        end
    elseif phase == PhaseDrawPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointB, PointBrush, PointAuxColor, point_b_id)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcBToOPrime
            timer = 0f0
        end
    elseif phase == PhaseArcBToOPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointAPrime, 0.30f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
            phase = PhaseDrawPointAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawPointAPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointAPrime, PointBrush, PointAuxColor, point_a_prime_id)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcAPrimeToBPrime
            timer = 0f0
        end
    elseif phase == PhaseArcAPrimeToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointBPrime, 0.20f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_prime_id)
            phase = PhaseDrawPointBPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawPointBPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointBPrime, PointBrush, PointAuxColor, point_b_prime_id)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcBPrimeToOForOA
            timer = 0f0
        end

    elseif phase == PhaseArcBPrimeToOForOA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointBPrime, PointO, 0.30f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragOAForward
            timer = 0f0
        end
    elseif phase == PhaseDragOAForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointO, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragOABack
            timer = 0f0
        end
    elseif phase == PhaseDragOABack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointO, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcOToOPrimeForPrimeOA
            timer = 0f0
        end
    elseif phase == PhaseArcOToOPrimeForPrimeOA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointO, PointOPrime, 0.28f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragOPrimeAForward
            timer = 0f0
        end
    elseif phase == PhaseDragOPrimeAForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointOPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragOPrimeABack
            timer = 0f0
        end
    elseif phase == PhaseDragOPrimeABack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointOPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcOPrimeToOForOB
            timer = 0f0
        end
    elseif phase == PhaseArcOPrimeToOForOB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointOPrime, PointO, 0.28f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragOBForward
            timer = 0f0
        end
    elseif phase == PhaseDragOBForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointO, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragOBBack
            timer = 0f0
        end
    elseif phase == PhaseDragOBBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointO, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcOToOPrimeForPrimeOB
            timer = 0f0
        end
    elseif phase == PhaseArcOToOPrimeForPrimeOB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointO, PointOPrime, 0.28f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDragOPrimeBForward
            timer = 0f0
        end
    elseif phase == PhaseDragOPrimeBForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointOPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseDragOPrimeBBack
            timer = 0f0
        end
    elseif phase == PhaseDragOPrimeBBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointOPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseArcOPrimeToAForAB
            timer = 0f0
        end

    elseif phase == PhaseArcOPrimeToAForAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointOPrime, PointA, 0.32f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, SegmentABColor)
            phase = PhaseDrawSegmentAB
            timer = 0f0
        end
    elseif phase == PhaseDrawSegmentAB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            SegmentABStart, SegmentABEnd;
            penbrush=EdgeBrush,
            pencolor=SegmentABColor,
            line_host_id=segment_a_b_host_id,
            line_joint1_id=segment_a_b_joint1_id,
            line_joint2_id=segment_a_b_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcBToAPrimeForPrimeAB
            timer = 0f0
        end
    elseif phase == PhaseArcBToAPrimeForPrimeAB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointB, PointAPrime, 0.32f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawSegmentAPrimeBPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawSegmentAPrimeBPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            SegmentAPrimeBPrimeStart, SegmentAPrimeBPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=SegmentABColor,
            line_host_id=segment_a_prime_b_prime_host_id,
            line_joint1_id=segment_a_prime_b_prime_joint1_id,
            line_joint2_id=segment_a_prime_b_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            phase = PhaseArcBPrimeToAForABHighlight
            timer = 0f0
        end
    elseif phase == PhaseArcBPrimeToAForABHighlight
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointBPrime, PointA, 0.32f0, 1, :none)
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
            phase = PhaseArcAToAPrimeForPrimeABHighlight
            timer = 0f0
        end
    elseif phase == PhaseArcAToAPrimeForPrimeABHighlight
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.28f0, 1, :none)
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
            phase = PhasePenRiseBeforeAngleOAB
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeAngleOAB
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointAPrime[1], PointAPrime[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendOAB
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendOAB
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, DescendDuration, CompassTopZ,
            PointA[1], PointA[2], MarkerOABStart[1], MarkerOABStart[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightOABForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightOABForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerOABStart, AngleOABTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightOABBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightOABBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointA, MarkerOABEnd, -AngleOABTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcOABToPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcOABToPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime,
            MarkerOABStart, MarkerOPrimeAPrimeBPrimeStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightOPrimeAPrimeBPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightOPrimeAPrimeBPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerOPrimeAPrimeBPrimeStart,
            AngleOPrimeAPrimeBPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightOPrimeAPrimeBPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightOPrimeAPrimeBPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointAPrime, MarkerOPrimeAPrimeBPrimeEnd,
            -AngleOPrimeAPrimeBPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcPrimeToOBA
            timer = 0f0
        end
    elseif phase == PhaseCompassArcPrimeToOBA
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointB,
            MarkerOPrimeAPrimeBPrimeStart, MarkerOBAStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightOBAForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightOBAForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerOBAStart, AngleOBATheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightOBABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightOBABack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointB, MarkerOBAEnd, -AngleOBATheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassArcOBAToPrime
            timer = 0f0
        end
    elseif phase == PhaseCompassArcOBAToPrime
        EuclidAnimations.animate_compass_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointB, PointBPrime,
            MarkerOBAStart, MarkerOPrimeBPrimeAPrimeStart)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightOPrimeBPrimeAPrimeForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightOPrimeBPrimeAPrimeForward
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerOPrimeBPrimeAPrimeStart,
            AngleOPrimeBPrimeAPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseHighlightOPrimeBPrimeAPrimeBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightOPrimeBPrimeAPrimeBack
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr, timer, CompassSweepDuration,
            PointBPrime, MarkerOPrimeBPrimeAPrimeEnd,
            -AngleOPrimeBPrimeAPrimeTheta, MarkerRadius, HighlightColor)
        timer += dt
        if timer >= CompassSweepDuration
            phase = PhaseCompassRiseAfterAngleOAB
            timer = 0f0
        end
    elseif phase == PhaseCompassRiseAfterAngleOAB
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointBPrime[1], PointBPrime[2],
            MarkerOPrimeBPrimeAPrimeStart[1], MarkerOPrimeBPrimeAPrimeStart[2])
        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhasePenDescendC
            timer = 0f0
        end

    elseif phase == PhasePenDescendC
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointC[1], PointC[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
            phase = PhaseDrawPointC
            timer = 0f0
        end
    elseif phase == PhaseDrawPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointC, PointBrush, PointCColor, point_c_id)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcCToCPrime
            timer = 0f0
        end
    elseif phase == PhaseArcCToCPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointC, PointCPrime, 0.26f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, label_c_prime_id)
            phase = PhaseDrawPointCPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawPointCPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration,
            PointCPrime, PointBrush, PointCColor, point_c_prime_id)
        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseArcCPrimeToAForAC
            timer = 0f0
        end

    elseif phase == PhaseArcCPrimeToAForAC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointCPrime, PointA, 0.30f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
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
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.26f0, 1, :none)
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
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointB, 0.30f0, 1, :none)
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
            state_ptr, timer, ArcMoveDuration, PointB, PointBPrime, 0.26f0, 1, :none)
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
            phase = PhaseArcBPrimeToOPrimeForLPrime
            timer = 0f0
        end
    elseif phase == PhaseArcBPrimeToOPrimeForLPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointBPrime, PointOPrime, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.set_pen_active(state_ptr, 0, RayLColor)
            phase = PhaseDrawRayLPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawRayLPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawEdgeDuration,
            RayLPrimeStart, RayLPrimeEnd;
            penbrush=EdgeBrush,
            pencolor=RayLColor,
            line_host_id=ray_l_prime_host_id,
            line_joint1_id=ray_l_prime_joint1_id,
            line_joint2_id=ray_l_prime_joint2_id)
        timer += dt
        if timer >= DrawEdgeDuration
            OdinJuliaBridge.show_point(state_ptr, label_l_prime_id)
            phase = PhasePenRiseEnd
            timer = 0f0
        end
    elseif phase == PhasePenRiseEnd
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ,
            RayLPrimeEnd[1], RayLPrimeEnd[2])
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
