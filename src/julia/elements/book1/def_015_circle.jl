module ElementsOneDefinitionCircle

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const CenterPoint = [0.50f0, 0.50f0, 0f0]
const Radius = 0.24f0
const CircleStartPoint = [CenterPoint[1] + Radius, CenterPoint[2], 0f0]
const CircleSweepTheta = 2f0 * π

const CenterColor = :palevioletred1
const CircleColor = :steelblue
const CenterMaxBrush = 5f0
const CircleBrush = 5f0

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const PenDescendDuration = 1.8f0
const PointDrawDuration = 2.8f0
const PenRiseDuration = 1.8f0
const CompassDescendDuration = 1.8f0
const CircleDrawDuration = 4.4f0
const CompassRiseDuration = 2.8f0
const HidePauseDuration = 1.5f0

const MetaCenterPointId = 1
const MetaCircleHostId = 2
const MetaCircleStartId = 3
const MetaCircleEndId = 4
const MetaPhase = 5
const MetaTimer = 6

const PhasePenDescend = 0f0
const PhaseDrawCenter = 1f0
const PhasePenRise = 2f0
const PhaseCompassDescend = 3f0
const PhaseDrawCircle = 4f0
const PhaseCompassRise = 5f0
const PhaseHideAll = 6f0


"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Circle and Center

A circle is a plane figure contained by one line such that all the straight lines falling upon it from one point among those lying within the figure equal one another; and the point is called the center of the circle."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Circle and Center}

A circle \euclidcircle[color=steelblue,size=1,thickness=2] is a plane figure contained by one line such that all the straight lines falling upon it from one point \euclidpoint[color=palevioletred1,size=1] among those lying within the figure equal one another; and the point \euclidpoint[color=palevioletred1,size=1] is called the center of the circle."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset the state of the animation cycle back to the start of the animation"""
function reset_cycle_state(state_ptr::Ptr{Cvoid})
    center_point_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCenterPointId))
    circle_hostid = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircleHostId))
    circle_endid = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircleEndId))

    OdinJuliaBridge.hide_point_batch(state_ptr, [center_point_id, circle_hostid])
    OdinJuliaBridge.set_point_position(
        state_ptr, circle_endid, CircleStartPoint)
    OdinJuliaBridge.set_point_offset(
        state_ptr, circle_hostid, 0f0)

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.hide_compass(state_ptr)

    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, CenterColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, CircleColor)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, CenterPoint[1], CenterPoint[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, CircleStartPoint[1], CircleStartPoint[2], CompassTopZ)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaPhase, PhasePenDescend)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaTimer, 0f0)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    center_point = OdinJuliaBridge.create_new_point(
        state_ptr, CenterPoint, CenterColor, 0f0)
    circle = OdinJuliaBridge.create_new_circle(
        state_ptr, CenterPoint, Radius, 0f0, 0f0, CircleColor, 0f0)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCenterPointId, center_point.index)

    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleHostId, circle.host_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleStartId, circle.start_id)
    OdinJuliaBridge.set_animation_meta(state_ptr, MetaCircleEndId, circle.end_id)

    reset_cycle_state(state_ptr)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    center_point_id = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCenterPointId))
    circle_hostid = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircleHostId))
    circle_startid = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircleStartId))
    circle_endid = Integer(OdinJuliaBridge.get_animation_meta(
        state_ptr, MetaCircleEndId))

    if center_point_id < 0
        return
    end

    phase = OdinJuliaBridge.get_animation_meta(state_ptr, MetaPhase)
    timer = OdinJuliaBridge.get_animation_meta(state_ptr, MetaTimer)

    if phase == PhasePenDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration, PenTopZ,
            CenterPoint[1], CenterPoint[2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawCenter
            timer = 0f0
        end
    elseif phase == PhaseDrawCenter
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, PointDrawDuration, CenterPoint,
            CenterMaxBrush, CenterColor, center_point_id)

        timer += dt
        if timer >= PointDrawDuration
            phase = PhasePenRise
            timer = 0f0
        end
    elseif phase == PhasePenRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration, PenTopZ, CenterPoint[1], CenterPoint[2])

        timer += dt
        if timer >= PenRiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDescend
            timer = 0f0
        end
    elseif phase == PhaseCompassDescend
        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, CompassDescendDuration, CompassTopZ,
            CenterPoint[1], CenterPoint[2], CircleStartPoint[1], CircleStartPoint[2])

        timer += dt
        if timer >= CompassDescendDuration
            phase = PhaseDrawCircle
            timer = 0f0
        end
    elseif phase == PhaseDrawCircle
        EuclidAnimations.animate_draw_circle(state_ptr,
            timer, CircleDrawDuration, CenterPoint,
            CircleStartPoint, CircleSweepTheta, Radius;
            brush=CircleBrush,
            color=CircleColor,
            marker_host_id=circle_hostid,
            marker_start_id=circle_startid,
            marker_end_id=circle_endid)

        timer += dt
        if timer >= CircleDrawDuration
            phase = PhaseCompassRise
            timer = 0f0
            OdinJuliaBridge.set_point_position(
                state_ptr, circle_endid, CircleStartPoint)
            OdinJuliaBridge.set_point_offset(
                state_ptr, circle_hostid, 2f0π)
        end
    elseif phase == PhaseCompassRise
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassRiseDuration, CompassTopZ,
            CenterPoint[1], CenterPoint[2], CircleStartPoint[1], CircleStartPoint[2])

        timer += dt
        if timer >= CompassRiseDuration
            OdinJuliaBridge.hide_compass(state_ptr)
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
