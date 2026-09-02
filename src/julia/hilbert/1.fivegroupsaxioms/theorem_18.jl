module HilbertChapterOneTheorem18

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("db80657d-3c76-554e-9bec-b193cc6dcdbf")

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop, animation_entry

const PointA = [0.18f0, 0.82f0, 0f0]
const PointB = [0.46f0, 0.82f0, 0f0]
const PointC = [0.46f0, 0.50f0, 0f0]
const PointD = [0.18f0, 0.50f0, 0f0]
const PointP = [0.07f0, 0.30f0, 0f0]

const PointAPrime = [0.65f0, 0.82f0, 0f0]
const PointBPrime = [0.93f0, 0.82f0, 0f0]
const PointCPrime = [0.93f0, 0.50f0, 0f0]
const PointDPrime = [0.65f0, 0.50f0, 0f0]
const PointPPrime = [0.54f0, 0.30f0, 0f0]

const EdgeBrush = 5f0
const PointBrush = 6f0
const LabelColor = :plum1
const HighlightColor = :lightgreen

const ColorAB = :steelblue
const ColorBC = :palevioletred1
const ColorCD = :khaki3
const ColorDA = :grey60
const ColorAux = :khaki3
const ColorPointP = :grey60

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = [0.50f0, 1.25f0, 1.55f0]
const ToolResetOffscreenJoint2 = [0.57f0, 1.25f0, 1.55f0]

const DescendDuration = 1.8f0
const DrawDuration = 2.1f0
const DrawPointDuration = 1.4f0
const ArcMoveDuration = 1.35f0
const DragDuration = 1.1f0
const PenLiftDuration = 1.6f0
const CompassLiftDuration = 1.8f0
const FinalHoldDuration = 0.35f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one Theorem 18 animation generation."""
struct AnimationState
    edge_a_b::LineIds
    edge_b_c::LineIds
    edge_c_d::LineIds
    edge_d_a::LineIds
    edge_a_prime_b_prime::LineIds
    edge_b_prime_c_prime::LineIds
    edge_c_prime_d_prime::LineIds
    edge_d_prime_a_prime::LineIds
    edge_a_p::LineIds
    edge_p_c::LineIds
    edge_a_prime_p_prime::LineIds
    edge_p_prime_c_prime::LineIds
    point_p::Int64
    point_p_prime::Int64
    label_a::Int64
    label_b::Int64
    label_c::Int64
    label_d::Int64
    label_p::Int64
    label_a_prime::Int64
    label_b_prime::Int64
    label_c_prime::Int64
    label_d_prime::Int64
    label_p_prime::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const LabelAPoint = PointA + [-0.03f0, 0.03f0, 0f0]
const LabelBPoint = PointB + [0.05f0, 0.06f0, 0f0]
const LabelCPoint = PointC + [0.02f0, -0.04f0, 0f0]
const LabelDPoint = PointD + [-0.03f0, -0.04f0, 0f0]
const LabelPPoint = PointP + [-0.04f0, -0.03f0, 0f0]

const LabelAPrimePoint = PointAPrime + [-0.03f0, 0.03f0, 0f0]
const LabelBPrimePoint = PointBPrime + [0.05f0, 0.06f0, 0f0]
const LabelCPrimePoint = PointCPrime + [0.02f0, -0.04f0, 0f0]
const LabelDPrimePoint = PointDPrime + [-0.03f0, -0.04f0, 0f0]
const LabelPPrimePoint = PointPPrime + [-0.04f0, -0.03f0, 0f0]

const PhaseDescendA = 0f0
const PhaseDrawAB = 1f0
const PhaseDrawBC = 2f0
const PhaseDrawCD = 3f0
const PhaseDrawDA = 4f0
const PhaseArcToAPrime = 5f0
const PhaseDrawAPrimeBPrime = 6f0
const PhaseDrawBPrimeCPrime = 7f0
const PhaseDrawCPrimeDPrime = 8f0
const PhaseDrawDPrimeAPrime = 9f0
const PhaseArcToP = 10f0
const PhaseDrawP = 11f0
const PhaseArcToPPrime = 12f0
const PhaseDrawPPrime = 13f0
const PhaseArcToAForAP = 14f0
const PhaseDrawAP = 15f0
const PhaseArcToPForPC = 16f0
const PhaseDrawPC = 17f0
const PhaseArcToAPrimeForAPrimePPrime = 18f0
const PhaseDrawAPrimePPrime = 19f0
const PhaseArcToPPrimeForPPrimeCPrime = 20f0
const PhaseDrawPPrimeCPrime = 21f0
const PhasePenRiseBeforeHighlights = 22f0

const PhaseCompassDescendAB = 23f0
const PhaseHighlightPath1ABForward = 24f0
const PhaseHighlightPath1BCForward = 25f0
const PhaseHighlightPath1CPForward = 26f0
const PhaseHighlightPath1PAForward = 27f0
const PhaseHighlightPath1APBack = 28f0
const PhaseHighlightPath1PCBack = 29f0
const PhaseHighlightPath1CBBack = 30f0
const PhaseHighlightPath1BABack = 31f0

const PhaseCompassArcToPrime = 32f0
const PhaseHighlightPath2ABForward = 33f0
const PhaseHighlightPath2BCForward = 34f0
const PhaseHighlightPath2CPForward = 35f0
const PhaseHighlightPath2PAForward = 36f0
const PhaseHighlightPath2APBack = 37f0
const PhaseHighlightPath2PCBack = 38f0
const PhaseHighlightPath2CBBack = 39f0
const PhaseHighlightPath2BABack = 40f0
const PhaseCompassRiseEnd = 41f0
const PhaseFinalHold = 42f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.edge_a_b, state.edge_b_c, state.edge_c_d, state.edge_d_a,
        state.edge_a_prime_b_prime, state.edge_b_prime_c_prime,
        state.edge_c_prime_d_prime, state.edge_d_prime_a_prime,
        state.edge_a_p, state.edge_p_c, state.edge_a_prime_p_prime,
        state.edge_p_prime_c_prime, state.point_p, state.point_p_prime,
        state.label_a, state.label_b, state.label_c, state.label_d, state.label_p,
        state.label_a_prime, state.label_b_prime, state.label_c_prime,
        state.label_d_prime, state.label_p_prime, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 18

If (A, B, C, ...) and (A', B', C', ...) are congruent figures and P represents any arbitrary point, then there can always be found a point P' so that the two figures (A, B, C, ..., P) and (A', B', C', ..., P') shall likewise be congruent. If the figure (A, B, C, ..., P) contains at least four points not lying in the same plane, then the determination of P' can be made in but one way.

This theorem contains an important result; namely, that all the facts concerning space which have reference to congruence, that is to say, to displacements in space, are (by the addition of the axioms of groups I and II) exclusively the consequences of the six linear and plane axioms mentioned above. Hence, it is not necessary to assume the axiom of parallels in order to establish these facts."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 18}

If $(A, B, C, ...)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=palevioletred1,edge4_color=steelblue]
and $(A', B', C', ...)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=grey60,edge2_color=khaki3,edge3_color=palevioletred1,edge4_color=steelblue]
are congruent figures and $P$ \euclidpoint[color=grey60,size=1] represents any arbitrary point, then there can always
be found a point $P'$ \euclidpoint[color=grey60,size=1] so that the two figures
$(A, B, C, ..., P)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=khaki3,edge2_color=khaki3,edge3_color=khaki3,edge4_color=grey60]
and $(A', B', C', ..., P')$ \euclidbox[height=2,width=2,thickness=2,edge1_color=khaki3,edge2_color=khaki3,edge3_color=khaki3,edge4_color=grey60]
shall likewise be congruent. If the figure
$(A, B, C, ..., P)$ \euclidbox[height=2,width=2,thickness=2,edge1_color=khaki3,edge2_color=khaki3,edge3_color=khaki3,edge4_color=grey60]
contains at least four points not lying in the same plane, then the determination of $P'$ \euclidpoint[color=grey60,size=1] can be made in but one way.

This theorem contains an important result; namely, that all the facts concerning space which have reference to congruence, that is to say, to displacements in space, are (by the addition of the axioms of \textit{groups I and II}) exclusively the consequences of the six linear and plane axioms mentioned above. Hence, it is not necessary to assume the axiom of parallels in order to establish these facts."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the state of the animation cycle back to the start of the animation."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    edge_a_b_host_id = state.edge_a_b.host
    edge_a_b_joint2_id = state.edge_a_b.joint2
    edge_b_c_host_id = state.edge_b_c.host
    edge_b_c_joint2_id = state.edge_b_c.joint2
    edge_c_d_host_id = state.edge_c_d.host
    edge_c_d_joint2_id = state.edge_c_d.joint2
    edge_d_a_host_id = state.edge_d_a.host
    edge_d_a_joint2_id = state.edge_d_a.joint2
    edge_a_prime_b_prime_host_id = state.edge_a_prime_b_prime.host
    edge_a_prime_b_prime_joint2_id = state.edge_a_prime_b_prime.joint2
    edge_b_prime_c_prime_host_id = state.edge_b_prime_c_prime.host
    edge_b_prime_c_prime_joint2_id = state.edge_b_prime_c_prime.joint2
    edge_c_prime_d_prime_host_id = state.edge_c_prime_d_prime.host
    edge_c_prime_d_prime_joint2_id = state.edge_c_prime_d_prime.joint2
    edge_d_prime_a_prime_host_id = state.edge_d_prime_a_prime.host
    edge_d_prime_a_prime_joint2_id = state.edge_d_prime_a_prime.joint2
    edge_a_p_host_id = state.edge_a_p.host
    edge_a_p_joint2_id = state.edge_a_p.joint2
    edge_p_c_host_id = state.edge_p_c.host
    edge_p_c_joint2_id = state.edge_p_c.joint2
    edge_a_prime_p_prime_host_id = state.edge_a_prime_p_prime.host
    edge_a_prime_p_prime_joint2_id = state.edge_a_prime_p_prime.joint2
    edge_p_prime_c_prime_host_id = state.edge_p_prime_c_prime.host
    edge_p_prime_c_prime_joint2_id = state.edge_p_prime_c_prime.joint2
    point_p_id = state.point_p
    point_p_prime_id = state.point_p_prime
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_d_id = state.label_d
    label_p_id = state.label_p
    label_a_prime_id = state.label_a_prime
    label_b_prime_id = state.label_b_prime
    label_c_prime_id = state.label_c_prime
    label_d_prime_id = state.label_d_prime
    label_p_prime_id = state.label_p_prime

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [edge_a_b_host_id, edge_b_c_host_id, edge_c_d_host_id, edge_d_a_host_id,
         edge_a_prime_b_prime_host_id, edge_b_prime_c_prime_host_id,
         edge_c_prime_d_prime_host_id, edge_d_prime_a_prime_host_id,
         edge_a_p_host_id, edge_p_c_host_id,
         edge_a_prime_p_prime_host_id, edge_p_prime_c_prime_host_id,
         point_p_id, point_p_prime_id,
         label_a_id, label_b_id, label_c_id, label_d_id, label_p_id,
         label_a_prime_id, label_b_prime_id, label_c_prime_id,
         label_d_prime_id, label_p_prime_id])

    OdinJuliaBridge.set_point_position(state_ptr, edge_a_b_joint2_id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, edge_b_c_joint2_id, PointB)
    OdinJuliaBridge.set_point_position(state_ptr, edge_c_d_joint2_id, PointC)
    OdinJuliaBridge.set_point_position(state_ptr, edge_d_a_joint2_id, PointD)

    OdinJuliaBridge.set_point_position(
        state_ptr, edge_a_prime_b_prime_joint2_id, PointAPrime)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_b_prime_c_prime_joint2_id, PointBPrime)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_c_prime_d_prime_joint2_id, PointCPrime)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_d_prime_a_prime_joint2_id, PointDPrime)

    OdinJuliaBridge.set_point_position(
        state_ptr, edge_a_p_joint2_id, PointA)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_p_c_joint2_id, PointP)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_a_prime_p_prime_joint2_id, PointAPrime)
    OdinJuliaBridge.set_point_position(
        state_ptr, edge_p_prime_c_prime_joint2_id, PointPPrime)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescendA, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

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

    OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorAB)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, HighlightColor)
    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    edge_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, PointA, PointA,
        ColorAB, 0f0)
    edge_b_c = OdinJuliaBridge.create_new_line(
        state_ptr, PointB, PointB,
        ColorBC, 0f0)
    edge_c_d = OdinJuliaBridge.create_new_line(
        state_ptr, PointC, PointC,
        ColorCD, 0f0)
    edge_d_a = OdinJuliaBridge.create_new_line(
        state_ptr, PointD, PointD,
        ColorDA, 0f0)

    edge_a_prime_b_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointAPrime, PointAPrime, ColorAB, 0f0)
    edge_b_prime_c_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointBPrime, PointBPrime, ColorBC, 0f0)
    edge_c_prime_d_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointCPrime, PointCPrime, ColorCD, 0f0)
    edge_d_prime_a_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointDPrime, PointDPrime, ColorDA, 0f0)

    edge_a_p = OdinJuliaBridge.create_new_line(
        state_ptr, PointA, PointA,
        ColorAux, 0f0)
    edge_p_c = OdinJuliaBridge.create_new_line(
        state_ptr, PointP, PointP,
        ColorAux, 0f0)
    edge_a_prime_p_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointAPrime, PointAPrime,
        ColorAux, 0f0)
    edge_p_prime_c_prime = OdinJuliaBridge.create_new_line(
        state_ptr, PointPPrime, PointPPrime,
        ColorAux, 0f0)

    point_p = OdinJuliaBridge.create_new_point(state_ptr, PointP, ColorPointP, 0f0)
    point_p_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointPPrime, ColorPointP, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', LabelAPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', LabelBPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', LabelCPoint, LabelColor, 16f0)
    label_d = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', LabelDPoint, LabelColor, 16f0)
    label_p = OdinJuliaBridge.create_new_label(
        state_ptr, 'P', LabelPPoint, LabelColor, 16f0)

    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelAPrimePoint, LabelColor, 16f0)
    label_b_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelBPrimePoint, LabelColor, 16f0)
    label_c_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'C', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelCPrimePoint, LabelColor, 16f0)
    label_d_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'D', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelDPrimePoint, LabelColor, 16f0)
    label_p_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'P', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        LabelPPrimePoint, LabelColor, 16f0)

    state = AnimationState(
        LineIds(edge_a_b.host_id, edge_a_b.joint1_id, edge_a_b.joint2_id),
        LineIds(edge_b_c.host_id, edge_b_c.joint1_id, edge_b_c.joint2_id),
        LineIds(edge_c_d.host_id, edge_c_d.joint1_id, edge_c_d.joint2_id),
        LineIds(edge_d_a.host_id, edge_d_a.joint1_id, edge_d_a.joint2_id),
        LineIds(edge_a_prime_b_prime.host_id, edge_a_prime_b_prime.joint1_id,
            edge_a_prime_b_prime.joint2_id),
        LineIds(edge_b_prime_c_prime.host_id, edge_b_prime_c_prime.joint1_id,
            edge_b_prime_c_prime.joint2_id),
        LineIds(edge_c_prime_d_prime.host_id, edge_c_prime_d_prime.joint1_id,
            edge_c_prime_d_prime.joint2_id),
        LineIds(edge_d_prime_a_prime.host_id, edge_d_prime_a_prime.joint1_id,
            edge_d_prime_a_prime.joint2_id),
        LineIds(edge_a_p.host_id, edge_a_p.joint1_id, edge_a_p.joint2_id),
        LineIds(edge_p_c.host_id, edge_p_c.joint1_id, edge_p_c.joint2_id),
        LineIds(edge_a_prime_p_prime.host_id, edge_a_prime_p_prime.joint1_id,
            edge_a_prime_p_prime.joint2_id),
        LineIds(edge_p_prime_c_prime.host_id, edge_p_prime_c_prime.joint1_id,
            edge_p_prime_c_prime.joint2_id),
        point_p.index, point_p_prime.index,
        label_a.index, label_b.index, label_c.index, label_d.index, label_p.index,
        label_a_prime.index, label_b_prime.index, label_c_prime.index,
        label_d_prime.index, label_p_prime.index, PhaseDescendA, 0f0)
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
    edge_b_c_host_id = state.edge_b_c.host
    edge_b_c_joint1_id = state.edge_b_c.joint1
    edge_b_c_joint2_id = state.edge_b_c.joint2
    edge_c_d_host_id = state.edge_c_d.host
    edge_c_d_joint1_id = state.edge_c_d.joint1
    edge_c_d_joint2_id = state.edge_c_d.joint2
    edge_d_a_host_id = state.edge_d_a.host
    edge_d_a_joint1_id = state.edge_d_a.joint1
    edge_d_a_joint2_id = state.edge_d_a.joint2
    edge_a_prime_b_prime_host_id = state.edge_a_prime_b_prime.host
    edge_a_prime_b_prime_joint1_id = state.edge_a_prime_b_prime.joint1
    edge_a_prime_b_prime_joint2_id = state.edge_a_prime_b_prime.joint2
    edge_b_prime_c_prime_host_id = state.edge_b_prime_c_prime.host
    edge_b_prime_c_prime_joint1_id = state.edge_b_prime_c_prime.joint1
    edge_b_prime_c_prime_joint2_id = state.edge_b_prime_c_prime.joint2
    edge_c_prime_d_prime_host_id = state.edge_c_prime_d_prime.host
    edge_c_prime_d_prime_joint1_id = state.edge_c_prime_d_prime.joint1
    edge_c_prime_d_prime_joint2_id = state.edge_c_prime_d_prime.joint2
    edge_d_prime_a_prime_host_id = state.edge_d_prime_a_prime.host
    edge_d_prime_a_prime_joint1_id = state.edge_d_prime_a_prime.joint1
    edge_d_prime_a_prime_joint2_id = state.edge_d_prime_a_prime.joint2
    edge_a_p_host_id = state.edge_a_p.host
    edge_a_p_joint1_id = state.edge_a_p.joint1
    edge_a_p_joint2_id = state.edge_a_p.joint2
    edge_p_c_host_id = state.edge_p_c.host
    edge_p_c_joint1_id = state.edge_p_c.joint1
    edge_p_c_joint2_id = state.edge_p_c.joint2
    edge_a_prime_p_prime_host_id = state.edge_a_prime_p_prime.host
    edge_a_prime_p_prime_joint1_id = state.edge_a_prime_p_prime.joint1
    edge_a_prime_p_prime_joint2_id = state.edge_a_prime_p_prime.joint2
    edge_p_prime_c_prime_host_id = state.edge_p_prime_c_prime.host
    edge_p_prime_c_prime_joint1_id = state.edge_p_prime_c_prime.joint1
    edge_p_prime_c_prime_joint2_id = state.edge_p_prime_c_prime.joint2
    point_p_id = state.point_p
    point_p_prime_id = state.point_p_prime
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_d_id = state.label_d
    label_p_id = state.label_p
    label_a_prime_id = state.label_a_prime
    label_b_prime_id = state.label_b_prime
    label_c_prime_id = state.label_c_prime
    label_d_prime_id = state.label_d_prime
    label_p_prime_id = state.label_p_prime

    if edge_a_b_host_id < 0 || edge_a_prime_b_prime_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescendA
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorAB)
            phase = PhaseDrawAB
            timer = 0f0
        end
    elseif phase == PhaseDrawAB
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointA, PointB;
            penbrush=EdgeBrush,
            pencolor=ColorAB,
            line_host_id=edge_a_b_host_id,
            line_joint1_id=edge_a_b_joint1_id,
            line_joint2_id=edge_a_b_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorBC)
            phase = PhaseDrawBC
            timer = 0f0
        end
    elseif phase == PhaseDrawBC
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointB, PointC;
            penbrush=EdgeBrush,
            pencolor=ColorBC,
            line_host_id=edge_b_c_host_id,
            line_joint1_id=edge_b_c_joint1_id,
            line_joint2_id=edge_b_c_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorCD)
            phase = PhaseDrawCD
            timer = 0f0
        end
    elseif phase == PhaseDrawCD
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointC, PointD;
            penbrush=EdgeBrush,
            pencolor=ColorCD,
            line_host_id=edge_c_d_host_id,
            line_joint1_id=edge_c_d_joint1_id,
            line_joint2_id=edge_c_d_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_d_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorDA)
            phase = PhaseDrawDA
            timer = 0f0
        end
    elseif phase == PhaseDrawDA
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointD, PointA;
            penbrush=EdgeBrush,
            pencolor=ColorDA,
            line_host_id=edge_d_a_host_id,
            line_joint1_id=edge_d_a_joint1_id,
            line_joint2_id=edge_d_a_joint2_id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseArcToAPrime
            timer = 0f0
        end

    elseif phase == PhaseArcToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorAB)
            phase = PhaseDrawAPrimeBPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawAPrimeBPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointAPrime, PointBPrime;
            penbrush=EdgeBrush,
            pencolor=ColorAB,
            line_host_id=edge_a_prime_b_prime_host_id,
            line_joint1_id=edge_a_prime_b_prime_joint1_id,
            line_joint2_id=edge_a_prime_b_prime_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_b_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorBC)
            phase = PhaseDrawBPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawBPrimeCPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointBPrime, PointCPrime;
            penbrush=EdgeBrush,
            pencolor=ColorBC,
            line_host_id=edge_b_prime_c_prime_host_id,
            line_joint1_id=edge_b_prime_c_prime_joint1_id,
            line_joint2_id=edge_b_prime_c_prime_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_c_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorCD)
            phase = PhaseDrawCPrimeDPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawCPrimeDPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointCPrime, PointDPrime;
            penbrush=EdgeBrush,
            pencolor=ColorCD,
            line_host_id=edge_c_prime_d_prime_host_id,
            line_joint1_id=edge_c_prime_d_prime_joint1_id,
            line_joint2_id=edge_c_prime_d_prime_joint2_id)
        timer += dt
        if timer >= DrawDuration
            OdinJuliaBridge.show_point(state_ptr, label_d_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorDA)
            phase = PhaseDrawDPrimeAPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawDPrimeAPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointDPrime, PointAPrime;
            penbrush=EdgeBrush,
            pencolor=ColorDA,
            line_host_id=edge_d_prime_a_prime_host_id,
            line_joint1_id=edge_d_prime_a_prime_joint1_id,
            line_joint2_id=edge_d_prime_a_prime_joint2_id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseArcToP
            timer = 0f0
        end

    elseif phase == PhaseArcToP
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointAPrime, PointP, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawP
            timer = 0f0
        end
    elseif phase == PhaseDrawP
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointP,
            PointBrush, ColorPointP, point_p_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_p_id)
            phase = PhaseArcToPPrime
            timer = 0f0
        end
    elseif phase == PhaseArcToPPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointP, PointPPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawPPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawPPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointPPrime,
            PointBrush, ColorPointP, point_p_prime_id)
        timer += dt
        if timer >= DrawPointDuration
            OdinJuliaBridge.show_point(state_ptr, label_p_prime_id)
            OdinJuliaBridge.set_pen_active(state_ptr, 0, ColorAux)
            phase = PhaseArcToAForAP
            timer = 0f0
        end

    elseif phase == PhaseArcToAForAP
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointPPrime, PointA, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAP
            timer = 0f0
        end
    elseif phase == PhaseDrawAP
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointA, PointP;
            penbrush=EdgeBrush,
            pencolor=ColorAux,
            line_host_id=edge_a_p_host_id,
            line_joint1_id=edge_a_p_joint1_id,
            line_joint2_id=edge_a_p_joint2_id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawPC
            timer = 0f0
        end
    elseif phase == PhaseDrawPC
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointP, PointC;
            penbrush=EdgeBrush,
            pencolor=ColorAux,
            line_host_id=edge_p_c_host_id,
            line_joint1_id=edge_p_c_joint1_id,
            line_joint2_id=edge_p_c_joint2_id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseArcToAPrimeForAPrimePPrime
            timer = 0f0
        end
    elseif phase == PhaseArcToAPrimeForAPrimePPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointC, PointAPrime, 0.24f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAPrimePPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawAPrimePPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointAPrime, PointPPrime;
            penbrush=EdgeBrush,
            pencolor=ColorAux,
            line_host_id=edge_a_prime_p_prime_host_id,
            line_joint1_id=edge_a_prime_p_prime_joint1_id,
            line_joint2_id=edge_a_prime_p_prime_joint2_id)
        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawPPrimeCPrime
            timer = 0f0
        end
    elseif phase == PhaseDrawPPrimeCPrime
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            PointPPrime, PointCPrime;
            penbrush=EdgeBrush,
            pencolor=ColorAux,
            line_host_id=edge_p_prime_c_prime_host_id,
            line_joint1_id=edge_p_prime_c_prime_joint1_id,
            line_joint2_id=edge_p_prime_c_prime_joint2_id)
        timer += dt
        if timer >= DrawDuration
            phase = PhasePenRiseBeforeHighlights
            timer = 0f0
        end
    elseif phase == PhasePenRiseBeforeHighlights
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointCPrime[1], PointCPrime[2])
        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescendAB
            timer = 0f0
        end

    elseif phase == PhaseCompassDescendAB
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointA[1], PointA[2])
        timer += dt
        if timer >= DescendDuration
            phase = PhaseHighlightPath1ABForward
            timer = 0f0
        end

    elseif phase == PhaseHighlightPath1ABForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1BCForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1BCForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1CPForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1CPForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointP, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1PAForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1PAForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointP, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1APBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1APBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointA, PointP, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1PCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1PCBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointP, PointC, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1CBBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1CBBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointC, PointB, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath1BABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath1BABack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointB, PointA, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseCompassArcToPrime
            timer = 0f0
        end

    elseif phase == PhaseCompassArcToPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration, PointA, PointAPrime, 0.22f0, 1, :none)
        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseHighlightPath2ABForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2ABForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2BCForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2BCForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2CPForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2CPForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointPPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2PAForward
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2PAForward
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointPPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2APBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2APBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointAPrime, PointPPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2PCBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2PCBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointPPrime, PointCPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2CBBack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2CBBack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointCPrime, PointBPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseHighlightPath2BABack
            timer = 0f0
        end
    elseif phase == PhaseHighlightPath2BABack
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr, timer, DragDuration, PointBPrime, PointAPrime, HighlightColor)
        timer += dt
        if timer >= DragDuration
            phase = PhaseCompassRiseEnd
            timer = 0f0
        end

    elseif phase == PhaseCompassRiseEnd
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, PointAPrime[1], PointAPrime[2])
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

AnimationCatalog.animation(
    HilbertChapterOneTheorem18.AnimationId, HilbertChapterOneTheorem18.animation_entry)
