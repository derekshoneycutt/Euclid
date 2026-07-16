module HilbertChapterOneTheorem7

using ..OdinJuliaBridge
using ..EuclidAnimations

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

const MetaPlaneHostId = 1
const MetaDividerHostId = 2
const MetaDividerJoint1Id = 3
const MetaDividerJoint2Id = 4
const MetaPointAId = 11
const MetaPointBId = 12
const MetaPointAPrimeId = 13
const MetaSegmentABHostId = 21
const MetaSegmentABJoint1Id = 22
const MetaSegmentABJoint2Id = 23
const MetaSegmentAAPrimeHostId = 24
const MetaSegmentAAPrimeJoint1Id = 25
const MetaSegmentAAPrimeJoint2Id = 26
const MetaAlphaLabelId = 41
const MetaALabelId = 42
const MetaBLabelId = 43
const MetaAPrimeLabelId = 44
const MetaPhase = 101
const MetaTimer = 102

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


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Theorem 7

Every plane α divides the remaining points of space into two regions having the following properties: Every point A of the one region determines with each point B of the other region a segment AB, within which lies a point of α. On the other hand, any two points A, A' lying within the same region determine a segment AA' containing no point of α.

...

Making use of the notation of theorem 7, we may now say: The points A, A' are situated in space upon one and the same side of the plane α, and the points A, B are situated in space upon different sides of the plane α.

Theorem 7 gives us the most important facts relating to the order of sequence of the elements of space. These facts are the results, exclusively, of the axioms already considered, and, hence, no new space axioms are required in group II."""
end

function set_plane_alpha(state_ptr::Ptr{Cvoid}, hostId, alpha01)
    t = clamp(alpha01, 0f0, PlaneMaxAlpha01)
    alpha = UInt8(round(Int, Float32(PlaneBaseColor.a) * t))
    color = OdinJuliaBridge.BridgeColor(
        PlaneBaseColor.r,
        PlaneBaseColor.g,
        PlaneBaseColor.b,
        alpha)
    OdinJuliaBridge.set_point_color(state_ptr, hostId, color)
end

function random_triangle_point(a::Vector{Float32}, b::Vector{Float32}, c::Vector{Float32})
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

function random_plane_point()
    if rand(Float32) < 0.5f0
        return random_triangle_point(PlaneEdgeLeft, PlaneTopLeft, PlaneTopRight)
    end

    random_triangle_point(PlaneEdgeLeft, PlaneTopRight, PlaneEdgeRight)
end

function show_plane(state_ptr::Ptr{Cvoid}, planeHostId)
    set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
    OdinJuliaBridge.show_point(state_ptr, planeHostId)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    planeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPlaneHostId))
    dividerHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaDividerHostId))
    dividerJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaDividerJoint1Id))
    dividerJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaDividerJoint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    segmentABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABHostId))
    segmentABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint2Id))
    segmentAAPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAAPrimeHostId))
    segmentAAPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAAPrimeJoint2Id))
    alphaLabelId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAlphaLabelId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaALabelId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBLabelId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAPrimeLabelId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [planeHostId, dividerHostId,
         pointAId, pointBId, pointAPrimeId,
         segmentABHostId, segmentAAPrimeHostId,
         alphaLabelId, labelAId, labelBId, labelAPrimeId])

    set_plane_alpha(state_ptr, planeHostId, 0f0)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseStartDelay)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, dividerJoint1Id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, dividerJoint2Id, LineStart)
    OdinJuliaBridge.set_point_position(state_ptr, segmentABJoint2Id, PointB)
    OdinJuliaBridge.set_point_position(state_ptr, segmentAAPrimeJoint2Id, PointA)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, DividerLineColor)
    OdinJuliaBridge.lock_pen_joint1(state_ptr, LineStart[1], LineStart[2], PenTopZ)
    OdinJuliaBridge.move_pen_joint2(state_ptr, LineStart[1], LineStart[2], PenTopZ + 0.14f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})

    pointA = OdinJuliaBridge.create_new_point(
        state_ptr, PointA, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(
        state_ptr, PointB, PointBColor, 0f0)
    pointAPrime = OdinJuliaBridge.create_new_point(
        state_ptr, PointAPrime, PointAPrimeColor, 0f0)
    labelA = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labelAPrime = OdinJuliaBridge.create_new_label_decorated(
        state_ptr, 'A', OdinJuliaBridge.LABEL_DECORATION_PRIME,
        APrimeLabelPoint, LabelColor, 16f0)

    dividerLine = OdinJuliaBridge.create_new_line(
        state_ptr, LineStart, LineStart, DividerLineColor, 0f0)
    segmentAB = OdinJuliaBridge.create_new_line(
        state_ptr, PointB, PointB, SegmentABColor, 0f0)
    segmentAAPrime = OdinJuliaBridge.create_new_line(
        state_ptr, PointA, PointA, SegmentAAPrimeColor, 0f0)

    planeAlpha = OdinJuliaBridge.create_new_square(
        state_ptr,
        PlaneEdgeLeft,
        PlaneEdgeRight,
        PlaneTopRight,
        PlaneTopLeft,
        PlaneColor)
    alphaLabel = OdinJuliaBridge.create_new_label(
        state_ptr, 'α', AlphaLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPlaneHostId, Float32(planeAlpha.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaDividerHostId, Float32(dividerLine.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaDividerJoint1Id, Float32(dividerLine.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaDividerJoint2Id, Float32(dividerLine.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAPrimeId, Float32(pointAPrime.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABHostId, Float32(segmentAB.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABJoint1Id, Float32(segmentAB.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentABJoint2Id, Float32(segmentAB.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentAAPrimeHostId, Float32(segmentAAPrime.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentAAPrimeJoint1Id, Float32(segmentAAPrime.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaSegmentAAPrimeJoint2Id, Float32(segmentAAPrime.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAlphaLabelId, Float32(alphaLabel.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaALabelId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaBLabelId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaAPrimeLabelId, Float32(labelAPrime.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    planeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPlaneHostId))
    dividerHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaDividerHostId))
    dividerJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaDividerJoint1Id))
    dividerJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaDividerJoint2Id))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAPrimeId))
    segmentABHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABHostId))
    segmentABJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint1Id))
    segmentABJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentABJoint2Id))
    segmentAAPrimeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAAPrimeHostId))
    segmentAAPrimeJoint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAAPrimeJoint1Id))
    segmentAAPrimeJoint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaSegmentAAPrimeJoint2Id))
    alphaLabelId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAlphaLabelId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaALabelId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaBLabelId))
    labelAPrimeId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaAPrimeLabelId))

    if planeHostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseStartDelay
        timer += dt
        if timer >= StartDelayDuration
            phase = PhaseFadeInPlane
            timer = 0f0
        end
    elseif phase == PhaseFadeInPlane
        set_plane_alpha(state_ptr, planeHostId, (timer / FadeInDuration) * PlaneMaxAlpha01)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)

        for _ in 1:FlickerSamplesPerFrame
            samplePos = random_plane_point()
            OdinJuliaBridge.emit_flicker_particle(state_ptr, samplePos, FlickerColor)
        end

        if timer >= FadeInDuration * 0.35f0
            OdinJuliaBridge.show_point(state_ptr, alphaLabelId)
        end

        timer += dt
        if timer >= FadeInDuration
            phase = PhaseDescendToLine
            timer = 0f0
        end
    elseif phase == PhaseDescendToLine
        show_plane(state_ptr, planeHostId)
        OdinJuliaBridge.show_point(state_ptr, alphaLabelId)
        OdinJuliaBridge.show_pen(state_ptr)

        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, LineStart[1], LineStart[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawDividerLine
            timer = 0f0
        end
    elseif phase == PhaseDrawDividerLine
        show_plane(state_ptr, planeHostId)
        OdinJuliaBridge.show_point(state_ptr, alphaLabelId)

        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, LineStart, LineEnd,
            LineMaxBrush, DividerLineColor,
            dividerHostId, dividerJoint1Id, dividerJoint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        OdinJuliaBridge.show_point(state_ptr, planeHostId)
        OdinJuliaBridge.show_point(state_ptr, alphaLabelId)

        OdinJuliaBridge.show_point(state_ptr, dividerHostId)

        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            LineEnd, PointA, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhasePutPointA
        OdinJuliaBridge.show_point(state_ptr, dividerHostId)

        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointA,
            PointMaxBrush, PointAColor, pointAId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        OdinJuliaBridge.show_point(state_ptr, dividerHostId)

        fade = (1f0 - (timer / ArcMoveDuration)) * PlaneMaxAlpha01
        set_plane_alpha(state_ptr, planeHostId, fade)
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointB, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            set_plane_alpha(state_ptr, planeHostId, 0f0)
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhasePutPointB
        OdinJuliaBridge.show_point(state_ptr, dividerHostId)

        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointB,
            PointMaxBrush, PointBColor, pointBId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseDrawSegmentAB
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, SegmentABColor)
        end
    elseif phase == PhaseDrawSegmentAB
        OdinJuliaBridge.show_point(state_ptr, dividerHostId)
        OdinJuliaBridge.show_point(state_ptr, planeHostId)
        OdinJuliaBridge.show_point(state_ptr, alphaLabelId)

        fade = (timer / DrawSegmentDuration) * PlaneMaxAlpha01
        set_plane_alpha(state_ptr, planeHostId, fade)

        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawSegmentDuration, PointB, PointA,
            LineMaxBrush, SegmentABColor,
            segmentABHostId, segmentABJoint1Id, segmentABJoint2Id)

        timer += dt
        if timer >= DrawSegmentDuration
            set_plane_alpha(state_ptr, planeHostId, PlaneMaxAlpha01)
            phase = PhaseMoveToPointAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAPrime
        OdinJuliaBridge.show_point(state_ptr, dividerHostId)

        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            PointA, PointAPrime, 0.22f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointAPrime
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAPrimeId)
        end
    elseif phase == PhasePutPointAPrime
        OdinJuliaBridge.show_point(state_ptr, dividerHostId)

        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointAPrime,
            PointMaxBrush, PointAPrimeColor, pointAPrimeId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointAForAAPrime
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointAForAAPrime
        OdinJuliaBridge.show_point(state_ptr, dividerHostId)

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
        OdinJuliaBridge.show_point(state_ptr, dividerHostId)

        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawSegmentDuration, PointA, PointAPrime,
            LineMaxBrush, SegmentAAPrimeColor,
            segmentAAPrimeHostId, segmentAAPrimeJoint1Id, segmentAAPrimeJoint2Id)

        timer += dt
        if timer >= DrawSegmentDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        OdinJuliaBridge.show_point(state_ptr, dividerHostId)

        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, PointAPrime[1], PointAPrime[2])

        timer += dt
        if timer >= EndLiftDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
        OdinJuliaBridge.show_point(state_ptr, dividerHostId)

        timer += dt
        if timer >= FinalHoldDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end