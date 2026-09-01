module HilbertChapterOneDefinitionPolygon

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop, animation_entry

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

struct AnimationState
    line1_host::Int64
    line1_joint1::Int64
    line1_joint2::Int64
    line2_host::Int64
    line2_joint1::Int64
    line2_joint2::Int64
    line3_host::Int64
    line3_joint1::Int64
    line3_joint2::Int64
    line4_host::Int64
    line4_joint1::Int64
    line4_joint2::Int64
    line5_host::Int64
    line5_joint1::Int64
    line5_joint2::Int64
    shape_host::Int64
    shape_joint1::Int64
    shape_joint2::Int64
    shape_joint3::Int64
    shape_joint4::Int64
    shape_joint5::Int64
    point_a::Int64
    point_b::Int64
    point_c::Int64
    point_d::Int64
    point_k::Int64
    label_a::Int64
    label_b::Int64
    label_c::Int64
    label_d::Int64
    label_k::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

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

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.line1_host, state.line1_joint1, state.line1_joint2,
        state.line2_host, state.line2_joint1, state.line2_joint2,
        state.line3_host, state.line3_joint1, state.line3_joint2,
        state.line4_host, state.line4_joint1, state.line4_joint2,
        state.line5_host, state.line5_joint1, state.line5_joint2,
        state.shape_host, state.shape_joint1, state.shape_joint2,
        state.shape_joint3, state.shape_joint4, state.shape_joint5,
        state.point_a, state.point_b, state.point_c, state.point_d, state.point_k,
        state.label_a, state.label_b, state.label_c, state.label_d, state.label_k,
        phase, timer)
end


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

"""Reset the animation objects and transactionally restart cycle timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line1_host_id = state.line1_host
    line1_joint2_id = state.line1_joint2
    line2_host_id = state.line2_host
    line2_joint2_id = state.line2_joint2
    line3_host_id = state.line3_host
    line3_joint2_id = state.line3_joint2
    line4_host_id = state.line4_host
    line4_joint2_id = state.line4_joint2
    line5_host_id = state.line5_host
    line5_joint2_id = state.line5_joint2
    shape_host_id = state.shape_host
    point_a_id = state.point_a
    point_b_id = state.point_b
    point_c_id = state.point_c
    point_d_id = state.point_d
    point_k_id = state.point_k
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_d_id = state.label_d
    label_k_id = state.label_k

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

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    point_a = OdinJuliaBridge.create_new_point(state_ptr, VertexA, PointAColor, 0f0)
    point_b = OdinJuliaBridge.create_new_point(state_ptr, VertexB, PointBColor, 0f0)
    point_c = OdinJuliaBridge.create_new_point(state_ptr, VertexC, PointCColor, 0f0)
    point_d = OdinJuliaBridge.create_new_point(state_ptr, VertexD, PointDColor, 0f0)
    point_k = OdinJuliaBridge.create_new_point(state_ptr, VertexK, PointKColor, 0f0)

    line1 = OdinJuliaBridge.create_new_line(
        state_ptr, VertexA, VertexA,
        PentagonColor, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr, VertexB, VertexB,
        PentagonColor, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr, VertexC, VertexC,
        PentagonColor, 0f0)
    line4 = OdinJuliaBridge.create_new_line(
        state_ptr, VertexD, VertexD,
        PentagonColor, 0f0)
    line5 = OdinJuliaBridge.create_new_line(
        state_ptr, VertexK, VertexK,
        PentagonColor, 0f0)
    pentagon = OdinJuliaBridge.create_new_pentagon(state_ptr,
        VertexA, VertexK, VertexD, VertexC, VertexB, PentagonColor)

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

    state = AnimationState(
        line1.host_id, line1.joint1_id, line1.joint2_id,
        line2.host_id, line2.joint1_id, line2.joint2_id,
        line3.host_id, line3.joint1_id, line3.joint2_id,
        line4.host_id, line4.joint1_id, line4.joint2_id,
        line5.host_id, line5.joint1_id, line5.joint2_id,
        pentagon.host_id, pentagon.joint1_id, pentagon.joint2_id,
        pentagon.joint3_id, pentagon.joint4_id, pentagon.joint5_id,
        point_a.index, point_b.index, point_c.index, point_d.index, point_k.index,
        label_a.index, label_b.index, label_c.index, label_d.index, label_k.index,
        PhaseDescend, 0f0)
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
    line1_host_id = state.line1_host
    line1_joint1_id = state.line1_joint1
    line1_joint2_id = state.line1_joint2
    line2_host_id = state.line2_host
    line2_joint1_id = state.line2_joint1
    line2_joint2_id = state.line2_joint2
    line3_host_id = state.line3_host
    line3_joint1_id = state.line3_joint1
    line3_joint2_id = state.line3_joint2
    line4_host_id = state.line4_host
    line4_joint1_id = state.line4_joint1
    line4_joint2_id = state.line4_joint2
    line5_host_id = state.line5_host
    line5_joint1_id = state.line5_joint1
    line5_joint2_id = state.line5_joint2
    shape_host_id = state.shape_host
    point_a_id = state.point_a
    point_b_id = state.point_b
    point_c_id = state.point_c
    point_d_id = state.point_d
    point_k_id = state.point_k
    label_a_id = state.label_a
    label_b_id = state.label_b
    label_c_id = state.label_c
    label_d_id = state.label_d
    label_k_id = state.label_k

    if line1_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

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
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            VertexA, VertexB;
            penbrush=PentagonMaxBrush,
            pencolor=PentagonColor,
            line_host_id=line1_host_id,
            line_joint1_id=line1_joint1_id,
            line_joint2_id=line1_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawBC
            timer = 0f0
        end
    elseif phase == PhaseDrawBC
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            VertexB, VertexC;
            penbrush=PentagonMaxBrush,
            pencolor=PentagonColor,
            line_host_id=line2_host_id,
            line_joint1_id=line2_joint1_id,
            line_joint2_id=line2_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawCD
            timer = 0f0
        end
    elseif phase == PhaseDrawCD
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            VertexC, VertexD;
            penbrush=PentagonMaxBrush,
            pencolor=PentagonColor,
            line_host_id=line3_host_id,
            line_joint1_id=line3_joint1_id,
            line_joint2_id=line3_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawDK
            timer = 0f0
        end
    elseif phase == PhaseDrawDK
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            VertexD, VertexK;
            penbrush=PentagonMaxBrush,
            pencolor=PentagonColor,
            line_host_id=line4_host_id,
            line_joint1_id=line4_joint1_id,
            line_joint2_id=line4_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseDrawKA
            timer = 0f0
        end
    elseif phase == PhaseDrawKA
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            VertexK, VertexA;
            penbrush=PentagonMaxBrush,
            pencolor=PentagonColor,
            line_host_id=line5_host_id,
            line_joint1_id=line5_joint1_id,
            line_joint2_id=line5_joint2_id)

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
