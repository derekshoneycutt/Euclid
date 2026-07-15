module HilbertChapterOneDefinitionPolygon

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.50f0, 0.76f0, 0f0]
const VertexB = [0.69f0, 0.62f0, 0f0]
const VertexC = [0.62f0, 0.36f0, 0f0]
const VertexD = [0.38f0, 0.36f0, 0f0]
const VertexK = [0.31f0, 0.62f0, 0f0]
const PenTopZ = 1.4f0

const PentagonColor = :steelblue
const PentagonMaxBrush = 5f0
const PentagonBaseColor = OdinJuliaBridge.bridge_color(PentagonColor)
const FlickerColor = :white
const FlickerSamplesPerFrame = 8

const DescendDuration = 1.8f0
const ArcMoveDuration = 1.9f0
const DrawPointDuration = 1.8f0
const DrawLineDuration = 2.25f0
const RiseDuration = 1.8f0
const FlickerDuration = 1f0
const FinalHoldDuration = 0.8f0

const PointAColor = :khaki3
const PointBColor = :palevioletred1
const PointCColor = :khaki3
const PointDColor = :grey60
const PointKColor = :palevioletred1
const LabelColor = :plum1

const ALabelPoint = VertexA + [-0.025f0, 0.03f0, 0f0]
const BLabelPoint = VertexB + [0.045f0, 0.055f0, 0f0]
const CLabelPoint = VertexC + [0.01f0, -0.02f0, 0f0]
const DLabelPoint = VertexD + [-0.03f0, -0.02f0, 0f0]
const KLabelPoint = VertexK + [-0.03f0, 0.01f0, 0f0]

const MetaLine1HostId = 1
const MetaLine1Joint1Id = 2
const MetaLine1Joint2Id = 3
const MetaLine2HostId = 4
const MetaLine2Joint1Id = 5
const MetaLine2Joint2Id = 6
const MetaLine3HostId = 7
const MetaLine3Joint1Id = 8
const MetaLine3Joint2Id = 9
const MetaLine4HostId = 10
const MetaLine4Joint1Id = 11
const MetaLine4Joint2Id = 12
const MetaLine5HostId = 13
const MetaLine5Joint1Id = 14
const MetaLine5Joint2Id = 15
const MetaShapeHostId = 16
const MetaShapeJoint1Id = 17
const MetaShapeJoint2Id = 18
const MetaShapeJoint3Id = 19
const MetaShapeJoint4Id = 20
const MetaShapeJoint5Id = 21
const MetaPointAId = 31
const MetaPointBId = 32
const MetaPointCId = 33
const MetaPointDId = 34
const MetaPointKId = 35
const MetaLabelAId = 41
const MetaLabelBId = 42
const MetaLabelCId = 43
const MetaLabelDId = 44
const MetaLabelKId = 45
const MetaPhase = 101
const MetaTimer = 102

const PhaseDescend = 0f0
const PhasePutPointA = 1f0
const PhaseMoveToPointB = 2f0
const PhasePutPointB = 3f0
const PhaseMoveToPointC = 4f0
const PhasePutPointC = 5f0
const PhaseMoveToPointD = 6f0
const PhasePutPointD = 7f0
const PhaseMoveToPointK = 8f0
const PhasePutPointK = 9f0
const PhaseMoveToPointA = 10f0
const PhaseDrawAB = 11f0
const PhaseDrawBC = 12f0
const PhaseDrawCD = 13f0
const PhaseDrawDK = 14f0
const PhaseDrawKA = 15f0
const PhaseRise = 16f0
const PhaseFinalHold = 17f0


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
        0f0,
    ]
end

function random_pentagon_point()
    t = rand(Float32)
    if t < 1f0 / 3f0
        return random_triangle_point(VertexA, VertexB, VertexC)
    elseif t < 2f0 / 3f0
        return random_triangle_point(VertexA, VertexC, VertexD)
    end
    random_triangle_point(VertexA, VertexD, VertexK)
end

function set_pentagon_alpha(state_ptr::Ptr{Cvoid}, shapeHostId, alpha01)
    t = clamp(alpha01, 0f0, 1f0)
    alpha = UInt8(round(Int, Float32(PentagonBaseColor.a) * t))
    color = OdinJuliaBridge.BridgeColor(
        PentagonBaseColor.r,
        PentagonBaseColor.g,
        PentagonBaseColor.b,
        alpha)
    OdinJuliaBridge.set_point_color(state_ptr, shapeHostId, color)
end


function get_view_text(state_ptr::Ptr{Cvoid})
    """David Hilbert - Foundations of Geometry - Definition: Polygon

A system of segments AB, BC, CD, ..., KL is called a broken line joining A with L and is designated, briefly, as the broken line ABCDE ... MKL. The points lying within the segments AB, BC, CD, ..., KL, as also the points A, B, C, D, ..., K, L, are called the points of the broken line. In particular, if the point A coincides with L, the broken line is called a polygon and is designated as the polygon ABCD ... KL. The segments AB, BC, CD, ..., KA are called the sides of the polygon and the points A, B, C, D, ..., K, are the vertices. Polygons having 3, 4, 5, ..., n vertices are called, respectively, triangles, quadrangles, pentagons, ..., n-gons. If the vertices of a polygon are all distinct and none of them lie within the segments composing the sides of the polygon, and, furthermore, if no two sides have a point in common, then the polygon is called a simple polygon."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))
    line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))
    line3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))
    line4HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine4HostId))
    line4Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine4Joint2Id))
    line5HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine5HostId))
    line5Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine5Joint2Id))
    shapeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaShapeHostId))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    pointDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    pointKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointKId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line1HostId, line2HostId, line3HostId, line4HostId, line5HostId, shapeHostId,
         pointAId, pointBId, pointCId, pointDId, pointKId,
         labelAId, labelBId, labelCId, labelDId, labelKId])
    set_pentagon_alpha(state_ptr, shapeHostId, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, line1Joint2Id, VertexA)
    OdinJuliaBridge.set_point_position(state_ptr, line2Joint2Id, VertexB)
    OdinJuliaBridge.set_point_position(state_ptr, line3Joint2Id, VertexC)
    OdinJuliaBridge.set_point_position(state_ptr, line4Joint2Id, VertexD)
    OdinJuliaBridge.set_point_position(state_ptr, line5Joint2Id, VertexK)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PentagonColor)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    pointA = OdinJuliaBridge.create_new_point(state_ptr, VertexA, PointAColor, 0f0)
    pointB = OdinJuliaBridge.create_new_point(state_ptr, VertexB, PointBColor, 0f0)
    pointC = OdinJuliaBridge.create_new_point(state_ptr, VertexC, PointCColor, 0f0)
    pointD = OdinJuliaBridge.create_new_point(state_ptr, VertexD, PointDColor, 0f0)
    pointK = OdinJuliaBridge.create_new_point(state_ptr, VertexK, PointKColor, 0f0)

    line1 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexA[1], VertexA[2], VertexA[3],
        PentagonColor, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexB[1], VertexB[2], VertexB[3],
        VertexB[1], VertexB[2], VertexB[3],
        PentagonColor, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexC[1], VertexC[2], VertexC[3],
        VertexC[1], VertexC[2], VertexC[3],
        PentagonColor, 0f0)
    line4 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexD[1], VertexD[2], VertexD[3],
        VertexD[1], VertexD[2], VertexD[3],
        PentagonColor, 0f0)
    line5 = OdinJuliaBridge.create_new_line(
        state_ptr,
        VertexK[1], VertexK[2], VertexK[3],
        VertexK[1], VertexK[2], VertexK[3],
        PentagonColor, 0f0)
    pentagon = OdinJuliaBridge.create_new_pentagon(
        state_ptr,
        VertexA[1], VertexA[2], VertexA[3],
        VertexK[1], VertexK[2], VertexK[3],
        VertexD[1], VertexD[2], VertexD[3],
        VertexC[1], VertexC[2], VertexC[3],
        VertexB[1], VertexB[2], VertexB[3],
        PentagonColor)

    labelA = OdinJuliaBridge.create_new_label(state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    labelB = OdinJuliaBridge.create_new_label(state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    labelC = OdinJuliaBridge.create_new_label(state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    labelD = OdinJuliaBridge.create_new_label(state_ptr, 'D', DLabelPoint, LabelColor, 16f0)
    labelK = OdinJuliaBridge.create_new_label(state_ptr, 'K', KLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1HostId, Float32(line1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, Float32(line1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, Float32(line1.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2HostId, Float32(line2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, Float32(line2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, Float32(line2.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3HostId, Float32(line3.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint1Id, Float32(line3.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint2Id, Float32(line3.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine4HostId, Float32(line4.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine4Joint1Id, Float32(line4.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine4Joint2Id, Float32(line4.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine5HostId, Float32(line5.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine5Joint1Id, Float32(line5.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine5Joint2Id, Float32(line5.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeHostId, Float32(pentagon.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint1Id, Float32(pentagon.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint2Id, Float32(pentagon.joint2Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint3Id, Float32(pentagon.joint3Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint4Id, Float32(pentagon.joint4Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint5Id, Float32(pentagon.joint5Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, Float32(pointA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, Float32(pointB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, Float32(pointC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointDId, Float32(pointD.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointKId, Float32(pointK.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, Float32(labelA.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, Float32(labelB.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, Float32(labelC.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, Float32(labelD.index))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, Float32(labelK.index))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint1Id))
    line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))
    line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint1Id))
    line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))
    line3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint1Id))
    line3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))
    line4HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine4HostId))
    line4Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine4Joint1Id))
    line4Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine4Joint2Id))
    line5HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine5HostId))
    line5Joint1Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine5Joint1Id))
    line5Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine5Joint2Id))
    shapeHostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaShapeHostId))
    pointAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    pointBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    pointCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    pointDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    pointKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointKId))
    labelAId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    labelBId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    labelCId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    labelDId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    labelKId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

    if line1HostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, VertexA[1], VertexA[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhasePutPointA
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelAId)
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, VertexA,
            PentagonMaxBrush, PointAColor, pointAId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointB
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointB
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexA, VertexB, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointB
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelBId)
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, VertexB,
            PentagonMaxBrush, PointBColor, pointBId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointC
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointC
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexB, VertexC, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointC
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelCId)
        end
    elseif phase == PhasePutPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, VertexC,
            PentagonMaxBrush, PointCColor, pointCId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointD
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointD
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexC, VertexD, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointD
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelDId)
        end
    elseif phase == PhasePutPointD
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, VertexD,
            PentagonMaxBrush, PointDColor, pointDId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointK
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointK
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexD, VertexK, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhasePutPointK
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, labelKId)
        end
    elseif phase == PhasePutPointK
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, VertexK,
            PentagonMaxBrush, PointKColor, pointKId)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseMoveToPointA
            timer = 0f0
        end
    elseif phase == PhaseMoveToPointA
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            VertexK, VertexA, 0.25f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawAB
            timer = 0f0
        end
    elseif phase == PhaseDrawAB
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, VertexA, VertexB,
            PentagonMaxBrush, PentagonColor,
            line1HostId, line1Joint1Id, line1Joint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawBC
            timer = 0f0
        end
    elseif phase == PhaseDrawBC
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, VertexB, VertexC,
            PentagonMaxBrush, PentagonColor,
            line2HostId, line2Joint1Id, line2Joint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawCD
            timer = 0f0
        end
    elseif phase == PhaseDrawCD
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, VertexC, VertexD,
            PentagonMaxBrush, PentagonColor,
            line3HostId, line3Joint1Id, line3Joint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawDK
            timer = 0f0
        end
    elseif phase == PhaseDrawDK
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, VertexD, VertexK,
            PentagonMaxBrush, PentagonColor,
            line4HostId, line4Joint1Id, line4Joint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawKA
            timer = 0f0
        end
    elseif phase == PhaseDrawKA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, VertexK, VertexA,
            PentagonMaxBrush, PentagonColor,
            line5HostId, line5Joint1Id, line5Joint2Id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseRise
            timer = 0f0
        end
    elseif phase == PhaseRise
        set_pentagon_alpha(state_ptr, shapeHostId, timer / FlickerDuration)
        OdinJuliaBridge.show_point(state_ptr, shapeHostId)

        if timer <= FlickerDuration
            for _ in 1:FlickerSamplesPerFrame
                samplePos = random_pentagon_point()
                OdinJuliaBridge.emit_flicker_particle(state_ptr, samplePos, FlickerColor)
            end
        end

        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, RiseDuration, PenTopZ, VertexA[1], VertexA[2])

        timer += dt
        if timer >= RiseDuration
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
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
