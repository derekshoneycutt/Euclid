module ElementsOneCommonNotions

using ..OdinJuliaBridge
using ..EuclidAnimations

using LinearAlgebra

export get_view_text, initialize, clean, loop

const LineLength = 0.35f0

const StartPoint1 = [0.1f0, 0.1f0, 0f0]
const EndPoint1 = StartPoint1 + [0f0, LineLength, 0f0]

const StartPoint2 = [0.5f0, 0.5f0, 0f0]
const EndPoint2 = StartPoint2 + [0f0, LineLength, 0f0]

const StartPoint3 = [0.9f0, 0.1f0, 0f0]
const EndPoint3 = StartPoint3 + [0f0, LineLength, 0f0]

const PenTopZ = 1.4f0

const Line1Color = :steelblue
const Line2Color = :palevioletred1
const Line3Color = :khaki3
const LineMaxBrush = 5f0

const DescendDuration = 1.8f0
const LineDrawDuration = 3.1f0
const ArcMoveDuration = 1.25f0
const ArcMoveHeight = 0.25f0
const EndLiftDuration = 1.8f0
const MoveLineDuration = 2.0f0
const HidePauseDuration = 1.5f0

const MetaLine1HostId = 1
const MetaLine1Joint1Id = 2
const MetaLine1Joint2Id = 3
const MetaLine2HostId = 11
const MetaLine2Joint1Id = 12
const MetaLine2Joint2Id = 13
const MetaLine3HostId = 21
const MetaLine3Joint1Id = 22
const MetaLine3Joint2Id = 23
const MetaPhase = 200
const MetaTimer = 201

const PhaseDescend = 0f0
const PhaseDrawLine1 = 1f0
const PhasePenArcToLine2 = 11f0
const PhaseDrawLine2 = 12f0
const PhasePenArcToLine3 = 21f0
const PhaseDrawLine3 = 22f0
const PhaseEndLift = 100f0
const PhaseMoveLine2 = 200f0
const PhaseReturnLine2 = 201f0
const PhaseMoveLine3 = 210f0
const PhaseReturnLine3 = 211f0
const PhaseMoveLine1 = 220f0
const PhaseReturnLine1 = 221f0
const PhaseHideAll = 500f0


function get_view_text(state_ptr::Ptr{Cvoid})
    """Euclid Elements - Book I - Common Notions

Things which are equal to the same thing are also equal to one another.
If equals be added to equals, the wholes are equal.
If equals be subtracted from equals, the remainders are equal.
Things which coincide with one another are equal to one another.
The whole is greater than the part."""
end

function reset_cycle_state(state_ptr::Ptr{Cvoid})
    line1HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1HostId))
    line1Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine1Joint2Id))

    line2HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2HostId))
    line2Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine2Joint2Id))

    line3HostId = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3HostId))
    line3Joint2Id = Integer(OdinJuliaBridge.get_animation_meta(state_ptr, MetaLine3Joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_point_batch(
        state_ptr, [line1HostId, line2HostId, line3HostId])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.set_point_position(
        state_ptr, line1Joint2Id, StartPoint1)
    OdinJuliaBridge.set_point_position(
        state_ptr, line2Joint2Id, StartPoint2)
    OdinJuliaBridge.set_point_position(
        state_ptr, line3Joint2Id, StartPoint3)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

function initialize(state_ptr::Ptr{Cvoid})
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint2, StartPoint2, Line2Color, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint3, StartPoint3, Line3Color, 0f0)
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint1, StartPoint1, Line1Color, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1HostId, Float32(line1.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, Float32(line1.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, Float32(line1.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2HostId, Float32(line2.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, Float32(line2.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, Float32(line2.joint2Id))

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3HostId, Float32(line3.hostId))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint1Id, Float32(line3.joint1Id))
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint2Id, Float32(line3.joint2Id))

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

    if line1HostId < 0 || line2HostId < 0 || line3HostId < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, StartPoint1[1], StartPoint1[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawLine1
            timer = 0f0
        end
    elseif phase == PhaseDrawLine1
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, StartPoint1, EndPoint1,
            LineMaxBrush, Line1Color, line1HostId, line1Joint1Id, line1Joint2Id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToLine2
            timer = 0f0
        end
    elseif phase == PhasePenArcToLine2
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint1, StartPoint2, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine2
            timer = 0f0
        end
    elseif phase == PhaseDrawLine2
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, StartPoint2, EndPoint2,
            LineMaxBrush, Line2Color, line2HostId, line2Joint1Id, line2Joint2Id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhasePenArcToLine3
            timer = 0f0
        end
    elseif phase == PhasePenArcToLine3
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            EndPoint2, StartPoint3, ArcMoveHeight, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawLine3
            timer = 0f0
        end
    elseif phase == PhaseDrawLine3
        EuclidAnimations.animate_draw_line(
            state_ptr, timer, LineDrawDuration, StartPoint3, EndPoint3,
            LineMaxBrush, Line3Color, line3HostId, line3Joint1Id, line3Joint2Id)

        timer += dt
        if timer >= LineDrawDuration
            phase = PhaseEndLift
            timer = 0f0
        end
    elseif phase == PhaseEndLift
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, EndLiftDuration, PenTopZ, EndPoint3[1], EndPoint3[2])

        timer += dt
        if timer >= EndLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseMoveLine2
            timer = 0f0
        end
    elseif phase == PhaseMoveLine2
        t = clamp(timer / MoveLineDuration, 0f0, 1f0)
        
        movvec = StartPoint2 - StartPoint1
        newLine2Start = StartPoint1 + movvec * t
        newLine2End = newLine2Start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line1Joint1Id, newLine2Start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line1Joint2Id, newLine2End)
        
        timer += dt
        if timer >= MoveLineDuration
            phase = PhaseReturnLine2
            timer = 0f0
        end
    elseif phase == PhaseReturnLine2
        t = clamp(timer / MoveLineDuration, 0f0, 1f0)
        
        movvec = StartPoint1 - StartPoint2
        newLine2Start = StartPoint2 + movvec * t
        newLine2End = newLine2Start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line1Joint1Id, newLine2Start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line1Joint2Id, newLine2End)
        
        timer += dt
        if timer >= MoveLineDuration
            phase = PhaseMoveLine3
            timer = 0f0
        end
    elseif phase == PhaseMoveLine3
        t = clamp(timer / MoveLineDuration, 0f0, 1f0)
        
        movvec = StartPoint2 - StartPoint3
        newLine3Start = StartPoint3 + movvec * t
        newLine3End = newLine3Start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line3Joint1Id, newLine3Start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line3Joint2Id, newLine3End)
        
        timer += dt
        if timer >= MoveLineDuration
            phase = PhaseReturnLine3
            timer = 0f0
        end
    elseif phase == PhaseReturnLine3
        t = clamp(timer / MoveLineDuration, 0f0, 1f0)
        
        movvec = StartPoint3 - StartPoint2
        newLine3Start = StartPoint2 + movvec * t
        newLine3End = newLine3Start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line3Joint1Id, newLine3Start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line3Joint2Id, newLine3End)
        
        timer += dt
        if timer >= MoveLineDuration
            phase = PhaseMoveLine1
            timer = 0f0
        end
    elseif phase == PhaseMoveLine1
        t = clamp(timer / MoveLineDuration, 0f0, 1f0)
        
        movvec = StartPoint3 - StartPoint1
        newLine1Start = StartPoint1 + movvec * t
        newLine1End = newLine1Start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line1Joint1Id, newLine1Start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line1Joint2Id, newLine1End)
        
        timer += dt
        if timer >= MoveLineDuration
            phase = PhaseReturnLine1
            timer = 0f0
        end
    elseif phase == PhaseReturnLine1
        t = clamp(timer / MoveLineDuration, 0f0, 1f0)
        
        movvec = StartPoint1 - StartPoint3
        newLine1Start = StartPoint3 + movvec * t
        newLine1End = newLine1Start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line1Joint1Id, newLine1Start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line1Joint2Id, newLine1End)
        
        timer += dt
        if timer >= MoveLineDuration
            phase = PhaseHideAll
            timer = 0f0
        end
    elseif phase == PhaseHideAll
        timer += dt
        if timer >= HidePauseDuration
            reset_cycle_state(state_ptr)
            return
        end
    end

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, phase)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, timer)
end

end
