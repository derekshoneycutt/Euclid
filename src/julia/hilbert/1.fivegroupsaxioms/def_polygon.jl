module HilbertChapterOneDefinitionPolygon

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

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


"""Pick a random interior point of the triangle with vertices a, b, and c."""
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

"""Pick a random interior point of the pentagon built from the current vertices."""
function random_pentagon_point()
    t = rand(Float32)
    if t < 1f0 / 3f0
        return random_triangle_point(VertexA, VertexB, VertexC)
    elseif t < 2f0 / 3f0
        return random_triangle_point(VertexA, VertexC, VertexD)
    end
    random_triangle_point(VertexA, VertexD, VertexK)
end

"""Set the pentagon's fill alpha from a normalized [0, 1] opacity."""
function set_pentagon_alpha(state_ptr::Ptr{Cvoid}, shape_host_id, alpha01)
    t = clamp(alpha01, 0f0, 1f0)
    alpha = UInt8(round(Int, PentagonBaseColor.a * t))
    color = OdinJuliaBridge.BridgeColor(
        PentagonBaseColor.r,
        PentagonBaseColor.g,
        PentagonBaseColor.b,
        alpha)
    OdinJuliaBridge.set_point_color(state_ptr, shape_host_id, color)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry - Definition: Polygon

A system of segments AB, BC, CD, ..., KL is called a broken line joining A with L and is designated, briefly, as the broken line ABCDE ... MKL. The points lying within the segments AB, BC, CD, ..., KL, as also the points A, B, C, D, ..., K, L, are called the points of the broken line. In particular, if the point A coincides with L, the broken line is called a polygon and is designated as the polygon ABCD ... KL. The segments AB, BC, CD, ..., KA are called the sides of the polygon and the points A, B, C, D, ..., K, are the vertices. Polygons having 3, 4, 5, ..., n vertices are called, respectively, triangles, quadrangles, pentagons, ..., n-gons. If the vertices of a polygon are all distinct and none of them lie within the segments composing the sides of the polygon, and, furthermore, if no two sides have a point in common, then the polygon is called a simple polygon."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry - Definition}: \textit{Polygon}

A system of segments $AB, BC, CD, ..., KL$ \euclidline[color=steelblue,length=3,thickness=4] is called a broken line joining
$A$ \euclidpoint[color=khaki3,size=1] with $L$ \euclidpoint[color=palevioletred1,size=1] and is
designated, briefly, as the broken line $ABCDE ... MKL$ \euclidline[color=steelblue,length=3,thickness=4]. The points lying within the
segments $AB, BC, CD, ..., KL$ \euclidline[color=steelblue,length=3,thickness=4], as also
the points $A, B, C, D, ..., K, L$, are called the points of the broken line.
In particular, if the point $A$ \euclidpoint[color=khaki3,size=1] coincides with
$L$ \euclidpoint[color=palevioletred1,size=1], the broken line is called a polygon and is
designated as the polygon $ABCD ... KL$. The segments $AB, BC, CD, ..., KA$ \euclidline[color=steelblue,length=3,thickness=4]
are called the sides of the polygon and the points $A, B, C, D, ..., K$, are the vertices.
Polygons having $3, 4, 5, ..., n$ vertices are called, respectively, triangles, quadrangles,
pentagons, ..., n-gons. If the vertices of a polygon are all distinct and none of them lie
within the segments composing the sides of the polygon, and, furthermore, if no two sides
have a point in common, then the polygon is called a simple polygon."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the state of the animation cycle back to the start of the animation"""
function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1HostId))
    line1_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1Joint2Id))
    line2_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2HostId))
    line2_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2Joint2Id))
    line3_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine3HostId))
    line3_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine3Joint2Id))
    line4_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine4HostId))
    line4_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine4Joint2Id))
    line5_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine5HostId))
    line5_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine5Joint2Id))
    shape_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaShapeHostId))
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    point_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    point_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointKId))
    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    label_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [line1_host_id, line2_host_id, line3_host_id,
         line4_host_id, line5_host_id, shape_host_id,
         point_a_id, point_b_id, point_c_id, point_d_id, point_k_id,
         label_a_id, label_b_id, label_c_id, label_d_id, label_k_id])
    set_pentagon_alpha(state_ptr, shape_host_id, 0f0)

    OdinJuliaBridge.set_point_position(state_ptr, line1_joint2_id, VertexA)
    OdinJuliaBridge.set_point_position(state_ptr, line2_joint2_id, VertexB)
    OdinJuliaBridge.set_point_position(state_ptr, line3_joint2_id, VertexC)
    OdinJuliaBridge.set_point_position(state_ptr, line4_joint2_id, VertexD)
    OdinJuliaBridge.set_point_position(state_ptr, line5_joint2_id, VertexK)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PentagonColor)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    point_a = OdinJuliaBridge.create_new_point(state_ptr, VertexA, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(state_ptr, VertexB, PointBColor, 0f0)
    point_c = OdinJuliaBridge.create_new_point(state_ptr, VertexC, PointCColor, 0f0)
    point_d = OdinJuliaBridge.create_new_point(state_ptr, VertexD, PointDColor, 0f0)
    point_k = OdinJuliaBridge.create_new_point(state_ptr, VertexK, PointKColor, 0f0)

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

    label_a = OdinJuliaBridge.create_new_label(
        state_ptr, 'A', ALabelPoint, LabelColor, 16f0)
    label_b = OdinJuliaBridge.create_new_label(
        state_ptr, 'B', BLabelPoint, LabelColor, 16f0)
    label_c = OdinJuliaBridge.create_new_label(
        state_ptr, 'C', CLabelPoint, LabelColor, 16f0)
    label_d = OdinJuliaBridge.create_new_label(
        state_ptr, 'D', DLabelPoint, LabelColor, 16f0)
    label_k = OdinJuliaBridge.create_new_label(
        state_ptr, 'K', KLabelPoint, LabelColor, 16f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1HostId, line1.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, line1.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, line1.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2HostId, line2.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, line2.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, line2.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3HostId, line3.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint1Id, line3.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint2Id, line3.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine4HostId, line4.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine4Joint1Id, line4.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine4Joint2Id, line4.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine5HostId, line5.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine5Joint1Id, line5.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine5Joint2Id, line5.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeHostId, pentagon.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint1Id, pentagon.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint2Id, pentagon.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint3Id, pentagon.joint3_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint4Id, pentagon.joint4_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaShapeJoint5Id, pentagon.joint5_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointAId, point_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointBId, point_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointCId, point_c.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointDId, point_d.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPointKId, point_k.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelAId, label_a.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelBId, label_b.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelCId, label_c.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelDId, label_d.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLabelKId, label_k.index)

    reset_cycle_state(state_ptr)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line1_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1HostId))
    line1_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1Joint1Id))
    line1_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine1Joint2Id))
    line2_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2HostId))
    line2_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2Joint1Id))
    line2_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine2Joint2Id))
    line3_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine3HostId))
    line3_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine3Joint1Id))
    line3_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine3Joint2Id))
    line4_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine4HostId))
    line4_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine4Joint1Id))
    line4_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine4Joint2Id))
    line5_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine5HostId))
    line5_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine5Joint1Id))
    line5_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLine5Joint2Id))
    shape_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaShapeHostId))
    point_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointAId))
    point_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointBId))
    point_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointCId))
    point_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointDId))
    point_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPointKId))
    label_a_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelAId))
    label_b_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelBId))
    label_c_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelCId))
    label_d_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelDId))
    label_k_id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLabelKId))

    if line1_host_id < 0
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
            OdinJuliaBridge.show_point(state_ptr, label_a_id)
        end
    elseif phase == PhasePutPointA
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, VertexA,
            PentagonMaxBrush, PointAColor, point_a_id)

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
            OdinJuliaBridge.show_point(state_ptr, label_b_id)
        end
    elseif phase == PhasePutPointB
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, VertexB,
            PentagonMaxBrush, PointBColor, point_b_id)

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
            OdinJuliaBridge.show_point(state_ptr, label_c_id)
        end
    elseif phase == PhasePutPointC
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, VertexC,
            PentagonMaxBrush, PointCColor, point_c_id)

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
            OdinJuliaBridge.show_point(state_ptr, label_d_id)
        end
    elseif phase == PhasePutPointD
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, VertexD,
            PentagonMaxBrush, PointDColor, point_d_id)

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
            OdinJuliaBridge.show_point(state_ptr, label_k_id)
        end
    elseif phase == PhasePutPointK
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, VertexK,
            PentagonMaxBrush, PointKColor, point_k_id)

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
            line1_host_id, line1_joint1_id, line1_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawBC
            timer = 0f0
        end
    elseif phase == PhaseDrawBC
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, VertexB, VertexC,
            PentagonMaxBrush, PentagonColor,
            line2_host_id, line2_joint1_id, line2_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawCD
            timer = 0f0
        end
    elseif phase == PhaseDrawCD
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, VertexC, VertexD,
            PentagonMaxBrush, PentagonColor,
            line3_host_id, line3_joint1_id, line3_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawDK
            timer = 0f0
        end
    elseif phase == PhaseDrawDK
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, VertexD, VertexK,
            PentagonMaxBrush, PentagonColor,
            line4_host_id, line4_joint1_id, line4_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawKA
            timer = 0f0
        end
    elseif phase == PhaseDrawKA
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, VertexK, VertexA,
            PentagonMaxBrush, PentagonColor,
            line5_host_id, line5_joint1_id, line5_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseRise
            timer = 0f0
        end
    elseif phase == PhaseRise
        set_pentagon_alpha(state_ptr, shape_host_id, timer / FlickerDuration)
        OdinJuliaBridge.show_point(state_ptr, shape_host_id)

        if timer <= FlickerDuration
            for _ in 1:FlickerSamplesPerFrame
                sample_pos = random_pentagon_point()
                OdinJuliaBridge.emit_flicker_particle(state_ptr, sample_pos, FlickerColor)
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
