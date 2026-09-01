module HilbertChapterOneTheorem6

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop, animation_entry

const PolygonV1 = [0.22f0, 0.66f0, 0f0]
const PolygonV2 = [0.39f0, 0.78f0, 0f0]
const PolygonV3 = [0.72f0, 0.68f0, 0f0]
const PolygonV4 = [0.76f0, 0.46f0, 0f0]
const PolygonV5 = [0.55f0, 0.51f0, 0f0]
const PolygonV6 = [0.42f0, 0.16f0, 0f0]

const PointA = [0.45f0, 0.34f0, 0f0]
const PointB = [0.05f0, 0.35f0, 0f0]
const PointAPrime = [0.65f0, 0.56f0, 0f0]
const PointBPrime = [0.82f0, 0.73f0, 0f0]
const BrokenInsideMid = [0.40f0, 0.64f0, 0f0]
const BrokenOutsideMid1 = [0.16f0, 0.78f0, 0f0]
const BrokenOutsideMid2 = [0.41f0, 0.89f0, 0f0]
const PenTopZ = 1.4f0

const ALabelPoint = PointA + [0.012f0, -0.028f0, 0f0]
const BLabelPoint = PointB + [-0.002f0, -0.03f0, 0f0]
const APrimeLabelPoint = PointAPrime + [0.025f0, -0.018f0, 0f0]
const BPrimeLabelPoint = PointBPrime + [0.02f0, -0.028f0, 0f0]

const LabelColor = :plum1
const OutlineColor = :grey60
const PointAColor = :steelblue
const PointBColor = :palevioletred1
const PointAPrimeColor = :khaki3
const PointBPrimeColor = :grey60
const SegmentABColor = :steelblue
const BrokenInsideColor = PointAPrimeColor
const BrokenOutsideColor = PointBColor

const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const DrawPolygonDuration = 2.2f0
const ArcMoveDuration = 1.8f0
const DrawPointDuration = 1.7f0
const DrawSegmentDuration = 2.0f0
const EndLiftDuration = 1.8f0
const FinalHoldDuration = 0.9f0

"""Complete immutable state for one Theorem 6 animation generation."""
struct AnimationState
    poly1_host_id::Int64
    poly1_joint1_id::Int64
    poly1_joint2_id::Int64
    poly2_host_id::Int64
    poly2_joint1_id::Int64
    poly2_joint2_id::Int64
    poly3_host_id::Int64
    poly3_joint1_id::Int64
    poly3_joint2_id::Int64
    poly4_host_id::Int64
    poly4_joint1_id::Int64
    poly4_joint2_id::Int64
    poly5_host_id::Int64
    poly5_joint1_id::Int64
    poly5_joint2_id::Int64
    poly6_host_id::Int64
    poly6_joint1_id::Int64
    poly6_joint2_id::Int64
    point_aid::Int64
    point_bid::Int64
    point_aprime_id::Int64
    point_bprime_id::Int64
    segment_abhost_id::Int64
    segment_abjoint1_id::Int64
    segment_abjoint2_id::Int64
    inside1_host_id::Int64
    inside1_joint1_id::Int64
    inside1_joint2_id::Int64
    inside2_host_id::Int64
    inside2_joint1_id::Int64
    inside2_joint2_id::Int64
    outside1_host_id::Int64
    outside1_joint1_id::Int64
    outside1_joint2_id::Int64
    outside2_host_id::Int64
    outside2_joint1_id::Int64
    outside2_joint2_id::Int64
    outside3_host_id::Int64
    outside3_joint1_id::Int64
    outside3_joint2_id::Int64
    label_aid::Int64
    label_bid::Int64
    label_aprime_id::Int64
    label_bprime_id::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawPoly1 = 1f0
const PhaseDrawPoly2 = 2f0
const PhaseDrawPoly3 = 3f0
const PhaseDrawPoly4 = 4f0
const PhaseDrawPoly5 = 5f0
const PhaseDrawPoly6 = 6f0
const PhaseMoveToA = 7f0
const PhasePutA = 8f0
const PhaseMoveToB = 9f0
const PhasePutB = 10f0
const PhaseDrawAB = 11f0
const PhaseMoveToAPrime = 12f0
const PhasePutAPrime = 13f0
const PhaseMoveToAForBroken = 14f0
const PhaseDrawInside1 = 15f0
const PhaseDrawInside2 = 16f0
const PhaseMoveToBPrime = 17f0
const PhasePutBPrime = 18f0
const PhaseMoveToBForBroken = 19f0
const PhaseDrawOutside1 = 20f0
const PhaseDrawOutside2 = 21f0
const PhaseDrawOutside3 = 22f0
const PhaseEndLift = 23f0
const PhaseFinalHold = 24f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.poly1_host_id, state.poly1_joint1_id, state.poly1_joint2_id,
        state.poly2_host_id, state.poly2_joint1_id, state.poly2_joint2_id,
        state.poly3_host_id, state.poly3_joint1_id, state.poly3_joint2_id,
        state.poly4_host_id, state.poly4_joint1_id, state.poly4_joint2_id,
        state.poly5_host_id, state.poly5_joint1_id, state.poly5_joint2_id,
        state.poly6_host_id, state.poly6_joint1_id, state.poly6_joint2_id,
        state.point_aid, state.point_bid, state.point_aprime_id, state.point_bprime_id,
        state.segment_abhost_id, state.segment_abjoint1_id, state.segment_abjoint2_id,
        state.inside1_host_id, state.inside1_joint1_id, state.inside1_joint2_id,
        state.inside2_host_id, state.inside2_joint1_id, state.inside2_joint2_id,
        state.outside1_host_id, state.outside1_joint1_id, state.outside1_joint2_id,
        state.outside2_host_id, state.outside2_joint1_id, state.outside2_joint2_id,
        state.outside3_host_id, state.outside3_joint1_id, state.outside3_joint2_id,
        state.label_aid, state.label_bid, state.label_aprime_id, state.label_bprime_id,
        phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Theorem 6

Every simple polygon, whose vertices all lie in a plane α, divides the points of this plane, not belonging to the broken line constituting the sides of the polygon, into two regions, an interior and an exterior, having the following properties: If A is a point of the interior region (interior point) and B a point of the exterior region (exterior point), then any broken line joining A and B must have at least one point in common with the polygon. If, on the other hand, A, A' are two points of the interior and B, B' two points of the exterior region, then there are always broken lines to be found joining A with A' and B with B' without having a point in common with the polygon. There exist straight lines in the plane α which lie entirely outside of the given polygon, but there are none which lie entirely within it."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Theorem 6}

Every simple polygon, whose vertices all lie in a plane $\alpha$, divides the points of this plane,
not belonging to the broken line constituting the sides of the polygon, into two regions, an
interior and an exterior, having the following properties: If $A$ \euclidpoint[color=steelblue,size=1] is a point of the interior region
(interior point) and $B$ \euclidpoint[color=palevioletred1,size=1] a point of the exterior region (exterior point), then any broken line \euclidline[color=steelblue,length=3,thickness=4]
joining $A$ \euclidpoint[color=steelblue,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1] must have at least one point in common with the polygon. If, on the other hand,
$A$ \euclidpoint[color=steelblue,size=1], $A'$ \euclidpoint[color=khaki3,size=1] are two points of the interior and $B$ \euclidpoint[color=palevioletred1,size=1], $B'$ \euclidpoint[color=grey60,size=1] two points of the exterior region, then there
are always broken lines \euclidline[color=khaki3,length=3,thickness=4] \euclidline[color=palevioletred1,length=3,thickness=4] to be found joining $A$ \euclidpoint[color=steelblue,size=1] with $A'$ \euclidpoint[color=khaki3,size=1] and $B$ \euclidpoint[color=palevioletred1,size=1] with $B'$ \euclidpoint[color=grey60,size=1] without having a point
in common with the polygon. There exist straight lines in the plane $\alpha$ which lie entirely
outside of the given polygon, but there are none which lie entirely within it."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the animation cycle while preserving its native handles."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    poly1_host_id = state.poly1_host_id
    poly1_joint2_id = state.poly1_joint2_id
    poly2_host_id = state.poly2_host_id
    poly2_joint2_id = state.poly2_joint2_id
    poly3_host_id = state.poly3_host_id
    poly3_joint2_id = state.poly3_joint2_id
    poly4_host_id = state.poly4_host_id
    poly4_joint2_id = state.poly4_joint2_id
    poly5_host_id = state.poly5_host_id
    poly5_joint2_id = state.poly5_joint2_id
    poly6_host_id = state.poly6_host_id
    poly6_joint2_id = state.poly6_joint2_id
    point_a_id = state.point_aid
    point_b_id = state.point_bid
    point_a_prime_id = state.point_aprime_id
    point_b_prime_id = state.point_bprime_id
    segment_a_b_host_id = state.segment_abhost_id
    segment_a_b_joint2_id = state.segment_abjoint2_id
    inside1_host_id = state.inside1_host_id
    inside1_joint2_id = state.inside1_joint2_id
    inside2_host_id = state.inside2_host_id
    inside2_joint2_id = state.inside2_joint2_id
    outside1_host_id = state.outside1_host_id
    outside1_joint2_id = state.outside1_joint2_id
    outside2_host_id = state.outside2_host_id
    outside2_joint2_id = state.outside2_joint2_id
    outside3_host_id = state.outside3_host_id
    outside3_joint2_id = state.outside3_joint2_id
    label_a_id = state.label_aid
    label_b_id = state.label_bid
    label_a_prime_id = state.label_aprime_id
    label_b_prime_id = state.label_bprime_id

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [poly1_host_id, poly2_host_id, poly3_host_id,
         poly4_host_id, poly5_host_id, poly6_host_id,
         point_a_id, point_b_id, point_a_prime_id, point_b_prime_id,
         segment_a_b_host_id, inside1_host_id, inside2_host_id,
         outside1_host_id, outside2_host_id, outside3_host_id,
         label_a_id, label_b_id, label_a_prime_id, label_b_prime_id])


    OdinJuliaBridge.set_point_position(state_ptr, poly1_joint2_id, PolygonV1)
    OdinJuliaBridge.set_point_position(state_ptr, poly2_joint2_id, PolygonV2)
    OdinJuliaBridge.set_point_position(state_ptr, poly3_joint2_id, PolygonV3)
    OdinJuliaBridge.set_point_position(state_ptr, poly4_joint2_id, PolygonV4)
    OdinJuliaBridge.set_point_position(state_ptr, poly5_joint2_id, PolygonV5)
    OdinJuliaBridge.set_point_position(state_ptr, poly6_joint2_id, PolygonV6)
    OdinJuliaBridge.set_point_position(state_ptr, segment_a_b_joint2_id, PointB)
    OdinJuliaBridge.set_point_position(state_ptr, inside1_joint2_id, PointA)
    OdinJuliaBridge.set_point_position(state_ptr, inside2_joint2_id, BrokenInsideMid)
    OdinJuliaBridge.set_point_position(state_ptr, outside1_joint2_id, PointB)
    OdinJuliaBridge.set_point_position(state_ptr, outside2_joint2_id, BrokenOutsideMid1)
    OdinJuliaBridge.set_point_position(state_ptr, outside3_joint2_id, BrokenOutsideMid2)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, OutlineColor)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, 0f0, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    poly1 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV1, PolygonV1,
        OutlineColor, 0f0)
    poly2 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV2, PolygonV2,
        OutlineColor, 0f0)
    poly3 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV3, PolygonV3,
        OutlineColor, 0f0)
    poly4 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV4, PolygonV4,
        OutlineColor, 0f0)
    poly5 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV5, PolygonV5,
        OutlineColor, 0f0)
    poly6 = OdinJuliaBridge.create_new_line(
        state_ptr, PolygonV6, PolygonV6,
        OutlineColor, 0f0)

    point_a = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)
    point_a_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointAPrime, PointAPrimeColor, 0f0)
    point_b_prime = OdinJuliaBridge.create_new_point(
        state_ptr, PointBPrime, PointBPrimeColor, 0f0)

    segment_a_b = OdinJuliaBridge.create_new_line(
        state_ptr, PointB, PointB,
        SegmentABColor, 0f0)
    inside1 = OdinJuliaBridge.create_new_line(
        state_ptr, PointA, PointA,
        BrokenInsideColor, 0f0)
    inside2 = OdinJuliaBridge.create_new_line(
        state_ptr, BrokenInsideMid, BrokenInsideMid,
        BrokenInsideColor, 0f0)
    outside1 = OdinJuliaBridge.create_new_line(
        state_ptr, PointB, PointB,
        BrokenOutsideColor, 0f0)
    outside2 = OdinJuliaBridge.create_new_line(
        state_ptr, BrokenOutsideMid1, BrokenOutsideMid1,
        BrokenOutsideColor, 0f0)
    outside3 = OdinJuliaBridge.create_new_line(
        state_ptr, BrokenOutsideMid2, BrokenOutsideMid2,
        BrokenOutsideColor, 0f0)

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    label_a_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        APrimeLabelPoint, LabelColor, 16f0)
    label_b_prime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'B', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        BPrimeLabelPoint, LabelColor, 16f0)


    state = AnimationState(
        poly1.host_id, poly1.joint1_id, poly1.joint2_id, poly2.host_id,
        poly2.joint1_id, poly2.joint2_id, poly3.host_id, poly3.joint1_id,
        poly3.joint2_id, poly4.host_id, poly4.joint1_id, poly4.joint2_id,
        poly5.host_id, poly5.joint1_id, poly5.joint2_id, poly6.host_id,
        poly6.joint1_id, poly6.joint2_id, point_a.index, point_b.index,
        point_a_prime.index, point_b_prime.index, segment_a_b.host_id,
        segment_a_b.joint1_id, segment_a_b.joint2_id, inside1.host_id, inside1.joint1_id,
        inside1.joint2_id, inside2.host_id, inside2.joint1_id, inside2.joint2_id,
        outside1.host_id, outside1.joint1_id, outside1.joint2_id, outside2.host_id,
        outside2.joint1_id, outside2.joint2_id, outside3.host_id, outside3.joint1_id,
        outside3.joint2_id, label_a.index, label_b.index, label_a_prime.index,
        label_b_prime.index,
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
    poly1_host_id = state.poly1_host_id
    poly1_joint1_id = state.poly1_joint1_id
    poly1_joint2_id = state.poly1_joint2_id
    poly2_host_id = state.poly2_host_id
    poly2_joint1_id = state.poly2_joint1_id
    poly2_joint2_id = state.poly2_joint2_id
    poly3_host_id = state.poly3_host_id
    poly3_joint1_id = state.poly3_joint1_id
    poly3_joint2_id = state.poly3_joint2_id
    poly4_host_id = state.poly4_host_id
    poly4_joint1_id = state.poly4_joint1_id
    poly4_joint2_id = state.poly4_joint2_id
    poly5_host_id = state.poly5_host_id
    poly5_joint1_id = state.poly5_joint1_id
    poly5_joint2_id = state.poly5_joint2_id
    poly6_host_id = state.poly6_host_id
    poly6_joint1_id = state.poly6_joint1_id
    poly6_joint2_id = state.poly6_joint2_id
    point_a_id = state.point_aid
    point_b_id = state.point_bid
    point_a_prime_id = state.point_aprime_id
    point_b_prime_id = state.point_bprime_id
    segment_a_b_host_id = state.segment_abhost_id
    segment_a_b_joint1_id = state.segment_abjoint1_id
    segment_a_b_joint2_id = state.segment_abjoint2_id
    inside1_host_id = state.inside1_host_id
    inside1_joint1_id = state.inside1_joint1_id
    inside1_joint2_id = state.inside1_joint2_id
    inside2_host_id = state.inside2_host_id
    inside2_joint1_id = state.inside2_joint1_id
    inside2_joint2_id = state.inside2_joint2_id
    outside1_host_id = state.outside1_host_id
    outside1_joint1_id = state.outside1_joint1_id
    outside1_joint2_id = state.outside1_joint2_id
    outside2_host_id = state.outside2_host_id
    outside2_joint1_id = state.outside2_joint1_id
    outside2_joint2_id = state.outside2_joint2_id
    outside3_host_id = state.outside3_host_id
    outside3_joint1_id = state.outside3_joint1_id
    outside3_joint2_id = state.outside3_joint2_id
    label_a_id = state.label_aid
    label_b_id = state.label_bid
    label_a_prime_id = state.label_aprime_id
    label_b_prime_id = state.label_bprime_id

    if poly1_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PolygonV1[1], PolygonV1[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawPoly1
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly1
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawPolygonDuration,
            PolygonV1, PolygonV2;
            penbrush=LineMaxBrush,
            pencolor=OutlineColor,
            line_host_id=poly1_host_id,
            line_joint1_id=poly1_joint1_id,
            line_joint2_id=poly1_joint2_id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseDrawPoly2
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly2
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawPolygonDuration,
            PolygonV2, PolygonV3;
            penbrush=LineMaxBrush,
            pencolor=OutlineColor,
            line_host_id=poly2_host_id,
            line_joint1_id=poly2_joint1_id,
            line_joint2_id=poly2_joint2_id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseDrawPoly3
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly3
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawPolygonDuration,
            PolygonV3, PolygonV4;
            penbrush=LineMaxBrush,
            pencolor=OutlineColor,
            line_host_id=poly3_host_id,
            line_joint1_id=poly3_joint1_id,
            line_joint2_id=poly3_joint2_id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseDrawPoly4
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly4
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawPolygonDuration,
            PolygonV4, PolygonV5;
            penbrush=LineMaxBrush,
            pencolor=OutlineColor,
            line_host_id=poly4_host_id,
            line_joint1_id=poly4_joint1_id,
            line_joint2_id=poly4_joint2_id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseDrawPoly5
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly5
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawPolygonDuration,
            PolygonV5, PolygonV6;
            penbrush=LineMaxBrush,
            pencolor=OutlineColor,
            line_host_id=poly5_host_id,
            line_joint1_id=poly5_joint1_id,
            line_joint2_id=poly5_joint2_id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseDrawPoly6
            timer = 0f0
        end
    elseif phase == PhaseDrawPoly6
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawPolygonDuration,
            PolygonV6, PolygonV1;
            penbrush=LineMaxBrush,
            pencolor=OutlineColor,
            line_host_id=poly6_host_id,
            line_joint1_id=poly6_joint1_id,
            line_joint2_id=poly6_joint2_id)

        timer += dt
        if timer >= DrawPolygonDuration
            phase = PhaseMoveToA
            timer = 0f0
        end
    elseif phase == PhaseMoveToA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PolygonV1, PointA, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
    elseif phase == PhasePutA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointA,
            PointMaxBrush, PointAColor, point_a_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToB
            timer = 0f0
        end
    elseif phase == PhaseMoveToB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointB, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhasePutB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointB,
            PointMaxBrush, PointBColor, point_b_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseDrawAB
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, SegmentABColor)
        end
    elseif phase == PhaseDrawAB
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
            phase = PhaseMoveToAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToAPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_a_prime_id)
        end
    elseif phase == PhasePutAPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointAPrime,
            PointMaxBrush, PointAPrimeColor, point_a_prime_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToAForBroken
            timer = 0f0
        end
    elseif phase == PhaseMoveToAForBroken
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointA, 0.18f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawInside1
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, BrokenInsideColor)
        end
    elseif phase == PhaseDrawInside1
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawSegmentDuration,
            PointA, BrokenInsideMid;
            penbrush=LineMaxBrush,
            pencolor=BrokenInsideColor,
            line_host_id=inside1_host_id,
            line_joint1_id=inside1_joint1_id,
            line_joint2_id=inside1_joint2_id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseDrawInside2
            timer = 0f0
        end
    elseif phase == PhaseDrawInside2
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawSegmentDuration,
            BrokenInsideMid, PointAPrime;
            penbrush=LineMaxBrush,
            pencolor=BrokenInsideColor,
            line_host_id=inside2_host_id,
            line_joint1_id=inside2_joint1_id,
            line_joint2_id=inside2_joint2_id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseMoveToBPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToBPrime
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointAPrime, PointBPrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutBPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_b_prime_id)
        end
    elseif phase == PhasePutBPrime
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointBPrime,
            PointMaxBrush, PointBPrimeColor, point_b_prime_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToBForBroken
            timer = 0f0
        end
    elseif phase == PhaseMoveToBForBroken
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointBPrime, PointB, 0.28f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawOutside1
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, BrokenOutsideColor)
        end
    elseif phase == PhaseDrawOutside1
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawSegmentDuration,
            PointB, BrokenOutsideMid1;
            penbrush=LineMaxBrush,
            pencolor=BrokenOutsideColor,
            line_host_id=outside1_host_id,
            line_joint1_id=outside1_joint1_id,
            line_joint2_id=outside1_joint2_id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseDrawOutside2
            timer = 0f0
        end
    elseif phase == PhaseDrawOutside2
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawSegmentDuration,
            BrokenOutsideMid1, BrokenOutsideMid2;
            penbrush=LineMaxBrush,
            pencolor=BrokenOutsideColor,
            line_host_id=outside2_host_id,
            line_joint1_id=outside2_joint1_id,
            line_joint2_id=outside2_joint2_id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseDrawOutside3
            timer = 0f0
        end
    elseif phase == PhaseDrawOutside3
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawSegmentDuration,
            BrokenOutsideMid2, PointBPrime;
            penbrush=LineMaxBrush,
            pencolor=BrokenOutsideColor,
            line_host_id=outside3_host_id,
            line_joint1_id=outside3_joint1_id,
            line_joint2_id=outside3_joint2_id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointBPrime[1], PointBPrime[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
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
