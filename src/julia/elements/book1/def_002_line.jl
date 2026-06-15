module ElementsOneDefinitionLine

using ..EuclidBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const StartPoint = [0.25f0, 0.75f0, 0f0]
const EndPoint = [0.75f0, 0.25f0, 0f0]
const PenTopZ = 1.4f0

const LineColor = :steelblue
const LineMaxBrush = 5f0

const DescendDuration = 1.8f0
const LineDrawDuration = 4.2f0
const EndLiftDuration = 1.8f0

const MetaLineHostId = 1
const MetaLineJoint1Id = 2
const MetaLineJoint2Id = 3
const MetaPhase = 4
const MetaTimer = 5

const PhaseDescend = 0f0
const PhaseDrawLine = 1f0
const PhaseEndLift = 2f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Definition: Line:

A line is breadthless length."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    lineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    EuclidBridge.hide_pen(state_ptr)
    EuclidBridge.hide_point(state_ptr, lineHostId)
    EuclidBridge.set_point_position(
        state_ptr, lineJoint2Id, StartPoint[1], StartPoint[2], StartPoint[3])
end

function initialize(state_ptr::Ptr{Cvoid})
    line = EuclidBridge.create_new_line(
        state_ptr,
        StartPoint[1], StartPoint[2], StartPoint[3],
        StartPoint[1], StartPoint[2], StartPoint[3],
        LineColor, 0f0)

    EuclidBridge.set_animation_meta(state_ptr, MetaLineHostId, Float32(line.hostId))
    EuclidBridge.set_animation_meta(state_ptr, MetaLineJoint1Id, Float32(line.joint1Id))
    EuclidBridge.set_animation_meta(state_ptr, MetaLineJoint2Id, Float32(line.joint2Id))

    reset_cycle_state(state_ptr)
end

function clean(state_ptr::Ptr{Cvoid})
end

function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    lineHostId = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineHostId))
    lineJoint1Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint1Id))
    lineJoint2Id = Integer(EuclidBridge.get_animation_meta(state_ptr, MetaLineJoint2Id))

    if lineHostId < 0
        return
    end

    phase = EuclidBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = EuclidBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, StartPoint[1], StartPoint[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine
            timer = 0f0
        end
    elseif phase == PhaseDrawLine
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, StartPoint, EndPoint,
            LineMaxBrush, LineColor, lineHostId, lineJoint1Id, lineJoint2Id)

        timer += dt
        if timer >= LineDrawDuration
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

    EuclidBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    EuclidBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
