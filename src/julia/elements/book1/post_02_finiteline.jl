module ElementsOnePostulatesFiniteLine

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const MidPoint = [0.3f0, 0.7f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]
const PenTopZ = 1.4f0

const LineColor = :steelblue
const Point1Color = :palevioletred1
const Point2Color = :khaki3
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const MoveToJoint1Duration = 1f0
const MoveToJoint2Duration = 1f0
const ExtremityTrailDuration = 2f0
const DrawInitLineDuration = 1.5f0
const DrawLineDuration = 4.2f0
const EndLiftDuration = 1.8f0

const MetaInitLineHostId = 1
const MetaInitLineJoint1Id = 2
const MetaInitLineJoint2Id = 3
const MetaLineHostId = 4
const MetaLineJoint1Id = 5
const MetaLineJoint2Id = 6
const MetaPoint1Id = 7
const MetaPoint2Id = 8
const MetaPhase = 9
const MetaTimer = 10

const PhaseDescend = 0f0
const PhasePutJoint1 = 1f0
const PhaseMoveToJoint2 = 2f0
const PhasePutJoint2 = 3f0
const PhaseMoveToJoint1 = 4f0
const PhaseDrawInitLine = 5f0
const PhaseMoveToJoint1Again = 6f0
const PhaseDrawLine = 7f0
const PhaseEndLift = 8f0


function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Postulates: Produce a Finite Line

Let the following be postulated:

To produce a finite straight line continuously in a straight line."""
    latex = raw"""\textbf{Euclid Elements - Book I - Postulates}: \textit{Produce a Finite Line}

\textit{Let the following be postulated:}

To produce a finite straight line \euclidline[color=steelblue,length=3,thickness=4] continuously in a straight line."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    point1id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPoint1Id))
    point2id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPoint2Id))
    init_line_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaInitLineHostId))
    init_line_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaInitLineJoint1Id))
    init_line_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaInitLineJoint2Id))
    line_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostId))
    line_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint1Id))
    line_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_point(state_ptr, init_line_host_id)
    OdinJuliaBridge.set_point_position(
        state_ptr, init_line_joint1_id, StartPoint[1], StartPoint[2], StartPoint[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, init_line_joint2_id, StartPoint[1], StartPoint[2], StartPoint[3])

    OdinJuliaBridge.hide_point(state_ptr, line_host_id)
    OdinJuliaBridge.set_point_position(
        state_ptr, line_joint1_id, StartPoint[1], StartPoint[2], StartPoint[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line_joint2_id, StartPoint[1], StartPoint[2], StartPoint[3])

    OdinJuliaBridge.hide_point_batch(state_ptr, [point1id, point2id])

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, LineColor)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    point1 = OdinJuliaBridge.create_new_point(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        Point1Color,
        0f0)
    point2 = OdinJuliaBridge.create_new_point(
        state_ptr,
        EndPoint[1], EndPoint[2], EndPoint[3],
        Point2Color,
        0f0)

    init_line = OdinJuliaBridge.create_new_line(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        MidPoint[1], MidPoint[2], MidPoint[3],
        LineColor, 5f0)
    OdinJuliaBridge.show_point(state_ptr, init_line.host_id)

    line = OdinJuliaBridge.create_new_line(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        StartPoint[1], StartPoint[2], StartPoint[3],
        LineColor, 0f0)

    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaPoint1Id, point1.index)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaPoint2Id, point2.index)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaInitLineHostId, init_line.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaInitLineJoint1Id, init_line.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaInitLineJoint2Id, init_line.joint2_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineHostId, line.host_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineJoint1Id, line.joint1_id)
    OdinJuliaBridge.set_animation_meta(
        state_ptr, MetaLineJoint2Id, line.joint2_id)

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    point1id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPoint1Id))
    point2id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaPoint2Id))
    init_line_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaInitLineHostId))
    init_line_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaInitLineJoint1Id))
    init_line_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaInitLineJoint2Id))
    line_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostId))
    line_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint1Id))
    line_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Id))

    if line_host_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, StartPoint[1], StartPoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhasePutJoint1
            timer = 0f0
        end
    elseif phase == PhasePutJoint1
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, StartPoint,
            PointMaxBrush, Point1Color, point1id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToJoint2
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToJoint2Duration,
            StartPoint, MidPoint, 0.15f0, 1, :none)

        timer += dt
        if timer >= MoveToJoint2Duration
            phase = PhasePutJoint2
            timer = 0f0
        end
    elseif phase == PhasePutJoint2
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, MidPoint,
            PointMaxBrush, Point2Color, point2id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToJoint1
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint1
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToJoint1Duration,
            MidPoint, StartPoint, 0.15f0, 1, :none)

        timer += dt
        if timer >= MoveToJoint1Duration
            phase = PhaseDrawInitLine
            timer = 0f0
        end
    elseif phase == PhaseDrawInitLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawInitLineDuration, StartPoint, MidPoint,
            LineMaxBrush, LineColor, init_line_host_id,
            init_line_joint1_id, init_line_joint2_id)

        timer += dt
        if timer >= DrawInitLineDuration
            phase = PhaseMoveToJoint1Again
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint1Again
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, MoveToJoint1Duration,
            MidPoint, StartPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= MoveToJoint1Duration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, DrawLineDuration, StartPoint, EndPoint,
            LineMaxBrush, LineColor, line_host_id, line_joint1_id, line_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, EndPoint[1], EndPoint[2])

        timer += dt
        if timer >= EndLiftDuration
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
