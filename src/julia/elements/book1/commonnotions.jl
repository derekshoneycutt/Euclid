module ElementsOneCommonNotions

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

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


"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Common Notions

1. Things which are equal to the same thing are also equal to one another.
2. If equals be added to equals, the wholes are equal.
3. If equals be subtracted from equals, the remainders are equal.
4. Things which coincide with one another are equal to one another.
5. The whole is greater than the part."""
    latex = raw"""\textbf{Euclid Elements - Book I - Common Notions}

\textbf{1.} Things which are equal to the same thing are also equal to one another.\\
\textbf{2.} If equals be added to equals, the wholes are equal.\\
\textbf{3.} If equals be subtracted from equals, the remainders are equal.\\
\textbf{4.} Things which coincide with one another are equal to one another.\\
\textbf{5.} The whole is greater than the part."""
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

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhaseDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.hide_point_batch(
        state_ptr, [line1_host_id, line2_host_id, line3_host_id])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.set_point_position(
        state_ptr, line1_joint2_id, StartPoint1)
    OdinJuliaBridge.set_point_position(
        state_ptr, line2_joint2_id, StartPoint2)
    OdinJuliaBridge.set_point_position(
        state_ptr, line3_joint2_id, StartPoint3)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint2, StartPoint2,
        Line2Color, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint3, StartPoint3,
        Line3Color, 0f0)
    line1 = OdinJuliaBridge.create_new_line(
        state_ptr, StartPoint1, StartPoint1,
        Line1Color, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1HostId, line1.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint1Id, line1.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine1Joint2Id, line1.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2HostId, line2.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint1Id, line2.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine2Joint2Id, line2.joint2_id)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3HostId, line3.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint1Id, line3.joint1_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaLine3Joint2Id, line3.joint2_id)

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

    if line1_host_id < 0 || line2_host_id < 0 || line3_host_id < 0
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
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            StartPoint1, EndPoint1;
            penbrush=LineMaxBrush,
            pencolor=Line1Color,
            line_host_id=line1_host_id,
            line_joint1_id=line1_joint1_id,
            line_joint2_id=line1_joint2_id)

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
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            StartPoint2, EndPoint2;
            penbrush=LineMaxBrush,
            pencolor=Line2Color,
            line_host_id=line2_host_id,
            line_joint1_id=line2_joint1_id,
            line_joint2_id=line2_joint2_id)

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
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, LineDrawDuration,
            StartPoint3, EndPoint3;
            penbrush=LineMaxBrush,
            pencolor=Line3Color,
            line_host_id=line3_host_id,
            line_joint1_id=line3_joint1_id,
            line_joint2_id=line3_joint2_id)

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
        new_line2_start = StartPoint1 + movvec * t
        new_line2_end = new_line2_start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line1_joint1_id, new_line2_start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line1_joint2_id, new_line2_end)
        
        timer += dt
        if timer >= MoveLineDuration
            phase = PhaseReturnLine2
            timer = 0f0
        end
    elseif phase == PhaseReturnLine2
        t = clamp(timer / MoveLineDuration, 0f0, 1f0)
        
        movvec = StartPoint1 - StartPoint2
        new_line2_start = StartPoint2 + movvec * t
        new_line2_end = new_line2_start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line1_joint1_id, new_line2_start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line1_joint2_id, new_line2_end)
        
        timer += dt
        if timer >= MoveLineDuration
            phase = PhaseMoveLine3
            timer = 0f0
        end
    elseif phase == PhaseMoveLine3
        t = clamp(timer / MoveLineDuration, 0f0, 1f0)
        
        movvec = StartPoint2 - StartPoint3
        new_line3_start = StartPoint3 + movvec * t
        new_line3_end = new_line3_start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line3_joint1_id, new_line3_start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line3_joint2_id, new_line3_end)
        
        timer += dt
        if timer >= MoveLineDuration
            phase = PhaseReturnLine3
            timer = 0f0
        end
    elseif phase == PhaseReturnLine3
        t = clamp(timer / MoveLineDuration, 0f0, 1f0)
        
        movvec = StartPoint3 - StartPoint2
        new_line3_start = StartPoint2 + movvec * t
        new_line3_end = new_line3_start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line3_joint1_id, new_line3_start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line3_joint2_id, new_line3_end)
        
        timer += dt
        if timer >= MoveLineDuration
            phase = PhaseMoveLine1
            timer = 0f0
        end
    elseif phase == PhaseMoveLine1
        t = clamp(timer / MoveLineDuration, 0f0, 1f0)
        
        movvec = StartPoint3 - StartPoint1
        new_line1_start = StartPoint1 + movvec * t
        new_line1_end = new_line1_start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line1_joint1_id, new_line1_start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line1_joint2_id, new_line1_end)
        
        timer += dt
        if timer >= MoveLineDuration
            phase = PhaseReturnLine1
            timer = 0f0
        end
    elseif phase == PhaseReturnLine1
        t = clamp(timer / MoveLineDuration, 0f0, 1f0)
        
        movvec = StartPoint1 - StartPoint3
        new_line1_start = StartPoint3 + movvec * t
        new_line1_end = new_line1_start + [0f0, LineLength, 0f0]

        OdinJuliaBridge.set_point_position(
            state_ptr, line1_joint1_id, new_line1_start)
        OdinJuliaBridge.set_point_position(
            state_ptr, line1_joint2_id, new_line1_end)
        
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
