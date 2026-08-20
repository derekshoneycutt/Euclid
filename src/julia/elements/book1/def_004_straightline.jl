module ElementsOneDefinitionStraightLine

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]
const PenTopZ = 1.4f0

const LineColor = :steelblue
const PointColor = :palevioletred1
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0

const DescendDuration = 1.8f0
const EndMoveToPutJoint2Duration = 2f0
const ExtremityTrailDuration = 2f0
const EndMoveToStartDuration = 2f0
const DrawLineDuration = 4.2f0
const EndMoveToJoint1Duration = 5f0
const EndMoveToJoint2Duration = 5f0
const EndLiftDuration = 1.8f0

const MetaLineHostId = 1
const MetaLineJoint1Id = 2
const MetaLineJoint2Id = 3
const MetaPhase = 4
const MetaTimer = 5
const MetaPoint1Id = 6
const MetaPoint2Id = 7

const PhaseDescend = 0f0
const PhasePutJoint1 = 1f0
const PhaseMoveToPutJoint2 = 2f0
const PhasePutJoint2 = 3f0
const PhaseMoveToStart = 4f0
const PhaseDrawLine = 5f0
const PhaseMoveToJoint1 = 6f0
const PhaseMoveToJoint2 = 7f0
const PhaseEndLift = 8f0


"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Straight Line

A straight line is a line which lies evenly with the points on itself."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Straight Line}

A straight line \euclidline[color=steelblue,length=3,thickness=4] is a line which lies evenly with the points \euclidpoint[color=palevioletred1,size=1] on itself."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the state of the animation cycle back to the start of the animation"""
function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostId))
    line_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint1Id))
    line_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Id))
    point1id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoint1Id))
    point2id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

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

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    point1 = OdinJuliaBridge.create_new_point(
        state_ptr, StartPoint, PointColor, 0f0)
    point2 = OdinJuliaBridge.create_new_point(
        state_ptr, EndPoint, PointColor, 0f0)
    line = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint, StartPoint,
        LineColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineHostId, line.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, line.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, line.joint2_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoint1Id, point1.index)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPoint2Id, point2.index)

    reset_cycle_state(state_ptr)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    line_host_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineHostId))
    line_joint1_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint1Id))
    line_joint2_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaLineJoint2Id))
    point1id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoint1Id))
    point2id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaPoint2Id))

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
            PointMaxBrush, PointColor, point1id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToPutJoint2
            timer = 0f0
        end
    elseif phase == PhaseMoveToPutJoint2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToPutJoint2Duration,
            StartPoint, EndPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToPutJoint2Duration
            phase = PhasePutJoint2
            timer = 0f0
        end
    elseif phase == PhasePutJoint2
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, ExtremityTrailDuration, EndPoint,
            PointMaxBrush, PointColor, point2id)

        timer += dt
        if timer >= ExtremityTrailDuration
            phase = PhaseMoveToStart
            timer = 0f0
        end
    elseif phase == PhaseMoveToStart
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToStartDuration,
            EndPoint, StartPoint, 0.25f0, 1, :none)

        timer += dt
        if timer >= EndMoveToStartDuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawLineDuration,
            StartPoint, EndPoint;
            penbrush=LineMaxBrush,
            pencolor=LineColor,
            line_host_id=line_host_id,
            line_joint1_id=line_joint1_id,
            line_joint2_id=line_joint2_id)

        timer += dt
        if timer >= DrawLineDuration
            phase = PhaseMoveToJoint1
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint1
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToJoint1Duration,
            EndPoint, StartPoint, 0.15f0, 10, PointColor)

        timer += dt
        if timer >= EndMoveToJoint1Duration
            phase = PhaseMoveToJoint2
            timer = 0f0
        end
    elseif phase == PhaseMoveToJoint2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, EndMoveToJoint1Duration,
            StartPoint, EndPoint, 0.15f0, 10, PointColor)

        timer += dt
        if timer >= EndMoveToJoint2Duration
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
