module EuclidAlgebraGroupsZ2

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex
using ..EuclidGeometry

export get_view_text, initialize, clean, loop

const VertexA = Float32[0.32f0, 0.34f0, 0f0]
const VertexB = Float32[0.68f0, 0.34f0, 0f0]
const VertexC = Float32[0.50f0, 0.65176916f0, 0f0]

const SideStarts = (VertexA, VertexB, VertexC)
const SideEnds = (VertexB, VertexC, VertexA)
const SideColors = (:steelblue, :palevioletred1, :khaki3)

const ReflectionLinePointA = Float32[0.5f0, 0.18f0, 0f0]
const ReflectionLinePointB = Float32[0.5f0, 0.88f0, 0f0]

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0
const ToolResetOffscreenJoint1 = Float32[0.5f0, 0.5f0, PenTopZ]
const ToolResetOffscreenJoint2 = Float32[0.5f0, 0.5f0, PenTopZ + 0.14f0]

const TriangleBrush = 5f0
const PenDescendDuration = 1.6f0
const SideDrawDuration = 1.9f0
const PenRiseDuration = 1.6f0
const PauseDuration = 1.0f0
const ReflectionDuration = 2.4f0

const MetaLineHostIds = (1, 4, 7)
const MetaLineJoint1Ids = (2, 5, 8)
const MetaLineJoint2Ids = (3, 6, 9)
const MetaPhase = 10
const MetaTimer = 11

const PhasePenDescend = 0f0
const PhaseDrawAB = 1f0
const PhaseDrawBC = 2f0
const PhaseDrawCA = 3f0
const PhasePenRise = 4f0
const PhasePauseBeforeReflection = 5f0
const PhaseReflectOnce = 6f0
const PhasePauseAfterOnce = 7f0
const PhaseReflectTwiceFirst = 8f0
const PhaseReflectTwiceSecond = 9f0
const PhasePauseAfterTwice = 10f0

const Z2FallbackText = raw"""The two-element symmetry group

Start with the simplest nontrivial geometry: given an equilateral triangle, either do nothing to the triangle, or reflect it across one fixed axis.

The two motions composed result in an action inside the same collection, the do-nothing motion acts as identity, and each reflection motion undoes itself.

Z_2 = {0,1}

This is the group under addition mod 2. Let r be reflection across the fixed axis and e the identity motion.

e o e = e, e o r = r, r o e = r, and r o r = e.

Brief proof it is a group:

1. Closure: composing e and r always gives e or r.
2. Associativity: composition of reflections is associative.
3. Identity: e does nothing.
4. Inverses: e^{-1} = e and r^{-1} = r.

So this is the 2-element symmetry group of the triangle, and the two motions commute."""

const Z2LatexDocument = raw"""\textbf{The two-element symmetry group}

Start with the simplest nontrivial geometry: given an equilateral triangle \euclidtriangle[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=palevioletred1,edge3_color=khaki3], either \textit{do nothing} to the triangle, or \textit{reflect} it across one fixed axis.

The two motions composed result in an action inside the same collection, the do-nothing motion acts as identity, and each reflection motion undoes itself.

$\mathbb{Z}_2 = \{0,1\}$

This is the group under addition \textit{mod 2}. Let $r$ be reflection across the fixed axis and $e$ the identity motion.

$e \circ e = e, \; e \circ r = r, \; r \circ e = r, \; r \circ r = e$

\textbf{Brief proof it is a group:}

\textbf{1. Closure}: composing $e$ and $r$ always gives $e$ or $r$.\\
\textbf{2. Associativity}: composition of reflections is associative.\\
\textbf{3. Identity}: $e$ does nothing.\\
\textbf{4. Inverses}: $e$ and $r$ are their own inverses.

So this is the 2-element symmetry group of the triangle, and the two motions commute."""

const RefVertexA = EuclidGeometry.reflect_about_axis_x_half(VertexA)
const RefVertexB = EuclidGeometry.reflect_about_axis_x_half(VertexB)
const RefVertexC = EuclidGeometry.reflect_about_axis_x_half(VertexC)

const ReflectLineStartBase = (
    VertexA,
    VertexB,
    VertexB,
    VertexC,
    VertexC,
    VertexA)

const ReflectLineStartMirrored = (
    RefVertexA,
    RefVertexB,
    RefVertexB,
    RefVertexC,
    RefVertexC,
    RefVertexA)

const ReflectLineEndBase = ReflectLineStartMirrored
const ReflectLineEndMirrored = ReflectLineStartBase

function get_view_text(state_ptr::Ptr{Cvoid})
    EuclidLatex.emit_latex_view_text!(state_ptr, Z2LatexDocument, Z2FallbackText)
end

function set_reflection_pose!(
    state_ptr::Ptr{Cvoid},
    point_ids::NTuple{6,Int64},
    poses::NTuple{6,Vector{Float32}})

    for i in 1:6
        OdinJuliaBridge.set_point_position(state_ptr, point_ids[i], poses[i])
    end
end

function animate_reflection_step!(
    state_ptr::Ptr{Cvoid},
    timer::Float32,
    duration::Float32,
    point_ids::NTuple{6,Int64},
    starts::NTuple{6,Vector{Float32}})

    axis_x = ReflectionLinePointA[1]

    for i in 1:6
        point_start = starts[i]
        if point_start[1] < axis_x
            EuclidAnimations.transform_reflect2d_point_negative(
                state_ptr,
                point_ids[i],
                point_start,
                ReflectionLinePointA,
                ReflectionLinePointB,
                timer,
                duration)
        else
            EuclidAnimations.transform_reflect2d_point(
                state_ptr,
                point_ids[i],
                point_start,
                ReflectionLinePointA,
                ReflectionLinePointB,
                timer,
                duration)
        end
    end
end

function reset_line_colors!(
    state_ptr::Ptr{Cvoid},
    line_host_id1::Int,
    line_host_id2::Int,
    line_host_id3::Int)

    OdinJuliaBridge.set_point_color(state_ptr, line_host_id1, SideColors[1])
    OdinJuliaBridge.set_point_color(state_ptr, line_host_id2, SideColors[2])
    OdinJuliaBridge.set_point_color(state_ptr, line_host_id3, SideColors[3])
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line_host_id1 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostIds[1])))
    line_host_id2 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostIds[2])))
    line_host_id3 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostIds[3])))
    line_joint1_id1 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint1Ids[1])))
    line_joint1_id2 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint1Ids[2])))
    line_joint1_id3 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint1Ids[3])))
    line_joint2_id1 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Ids[1])))
    line_joint2_id2 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Ids[2])))
    line_joint2_id3 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Ids[3])))

    if line_host_id1 < 0 || line_host_id2 < 0 || line_host_id3 < 0
        return
    end

    OdinJuliaBridge.hide_point_batch(
        state_ptr,
        [line_host_id1, line_host_id2, line_host_id3])

    OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id1, SideStarts[1])
    OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id1, SideStarts[1])
    OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id2, SideStarts[2])
    OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id2, SideStarts[2])
    OdinJuliaBridge.set_point_position(state_ptr, line_joint1_id3, SideStarts[3])
    OdinJuliaBridge.set_point_position(state_ptr, line_joint2_id3, SideStarts[3])
    reset_line_colors!(state_ptr, line_host_id1, line_host_id2, line_host_id3)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.lock_pen_joint1(
        state_ptr,
        ToolResetOffscreenJoint1[1],
        ToolResetOffscreenJoint1[2],
        ToolResetOffscreenJoint1[3])
    OdinJuliaBridge.move_pen_joint2(
        state_ptr,
        ToolResetOffscreenJoint2[1],
        ToolResetOffscreenJoint2[2],
        ToolResetOffscreenJoint2[3])

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    for i in 1:3
        line = OdinJuliaBridge.create_new_line(
            state_ptr,
            SideStarts[i],
            SideStarts[i],
            SideColors[i],
            0f0)

        OdinJuliaBridge.set_animation_meta(
            state_ptr, MetaLineHostIds[i], Float32(line.host_id))
        OdinJuliaBridge.set_animation_meta(
            state_ptr, MetaLineJoint1Ids[i], Float32(line.joint1_id))
        OdinJuliaBridge.set_animation_meta(
            state_ptr, MetaLineJoint2Ids[i], Float32(line.joint2_id))
    end

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line_host_id1 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostIds[1])))
    line_host_id2 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostIds[2])))
    line_host_id3 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostIds[3])))
    if line_host_id1 < 0
        return
    end

    line_joint1_id1 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint1Ids[1])))
    line_joint1_id2 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint1Ids[2])))
    line_joint1_id3 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint1Ids[3])))
    line_joint2_id1 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Ids[1])))
    line_joint2_id2 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Ids[2])))
    line_joint2_id3 = Int(round(Int, OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Ids[3])))

    line_reflection_point_ids = (
        Int64(line_joint1_id1),
        Int64(line_joint2_id1),
        Int64(line_joint1_id2),
        Int64(line_joint2_id2),
        Int64(line_joint1_id3),
        Int64(line_joint2_id3))

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    reset_line_colors!(state_ptr, line_host_id1, line_host_id2, line_host_id3)

    if phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration, PenTopZ, VertexA[1], VertexA[2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawAB
            timer = 0f0
        end
    elseif phase == PhaseDrawAB || phase == PhaseDrawBC || phase == PhaseDrawCA
        side_index = Int(phase)
        line_host_id = side_index == 1 ? line_host_id1 :
            (side_index == 2 ? line_host_id2 : line_host_id3)
        line_joint1_id = side_index == 1 ? line_joint1_id1 :
            (side_index == 2 ? line_joint1_id2 : line_joint1_id3)
        line_joint2_id = side_index == 1 ? line_joint2_id1 :
            (side_index == 2 ? line_joint2_id2 : line_joint2_id3)

        EuclidAnimations.animate_draw_line(
            state_ptr,
            timer,
            SideDrawDuration,
            SideStarts[side_index],
            SideEnds[side_index],
            TriangleBrush,
            SideColors[side_index],
            line_host_id,
            line_joint1_id,
            line_joint2_id)

        timer += dt
        if timer >= SideDrawDuration
            if phase == PhaseDrawCA
                phase = PhasePenRise
            else
                phase += 1f0
            end
            timer = 0f0
        end
    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration, PenTopZ, VertexA[1], VertexA[2])

        timer += dt
        if timer >= PenRiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhasePauseBeforeReflection
            timer = 0f0
        end
    elseif phase == PhasePauseBeforeReflection ||
        phase == PhasePauseAfterOnce ||
        phase == PhasePauseAfterTwice

        timer += dt
        if timer >= PauseDuration
            if phase == PhasePauseBeforeReflection
                phase = PhaseReflectOnce
            elseif phase == PhasePauseAfterOnce
                phase = PhaseReflectTwiceFirst
            else
                reset_cycle_state(state_ptr)
                return
            end
            timer = 0f0
        end
    elseif phase == PhaseReflectOnce
        animate_reflection_step!(
            state_ptr,
            timer,
            ReflectionDuration,
            line_reflection_point_ids,
            ReflectLineStartBase)

        timer += dt
        if timer >= ReflectionDuration
            set_reflection_pose!(state_ptr, line_reflection_point_ids, ReflectLineEndBase)
            phase = PhasePauseAfterOnce
            timer = 0f0
        end
    elseif phase == PhaseReflectTwiceFirst
        animate_reflection_step!(
            state_ptr,
            timer,
            ReflectionDuration,
            line_reflection_point_ids,
            ReflectLineStartMirrored)

        timer += dt
        if timer >= ReflectionDuration
            set_reflection_pose!(state_ptr, line_reflection_point_ids, ReflectLineEndMirrored)
            phase = PhaseReflectTwiceSecond
            timer = 0f0
        end
    elseif phase == PhaseReflectTwiceSecond
        animate_reflection_step!(
            state_ptr,
            timer,
            ReflectionDuration,
            line_reflection_point_ids,
            ReflectLineStartBase)

        timer += dt
        if timer >= ReflectionDuration
            set_reflection_pose!(state_ptr, line_reflection_point_ids, ReflectLineEndBase)
            phase = PhasePauseAfterTwice
            timer = 0f0
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end