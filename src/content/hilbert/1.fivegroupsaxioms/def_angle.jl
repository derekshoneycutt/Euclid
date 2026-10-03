module HilbertChapterOneDefAngle

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("046525bc-cbdb-5b6b-96c4-49dd105e9b9e")

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

include("def_angle_content.jl")

export get_view_content, initialize, clean, loop, animation_entry

const PointO = [0.36f0, 0.40f0, 0f0]
const HalfRayLength = 0.44f0
const AngleTheta = π / 3f0

const HalfRayHStart = PointO
const HalfRayHEnd = [PointO[1] + HalfRayLength, PointO[2], 0f0]
const HalfRayKStart = PointO
const HalfRayKEnd = [
    PointO[1] + HalfRayLength * cos(AngleTheta),
    PointO[2] + HalfRayLength * sin(AngleTheta),
    0f0,
]

const MarkerRadius = 0.16f0
const MarkerStart = [PointO[1] + MarkerRadius, PointO[2], 0f0]
const MarkerEnd = [
    PointO[1] + MarkerRadius * cos(AngleTheta),
    PointO[2] + MarkerRadius * sin(AngleTheta),
    0f0,
]

const OLabelPoint = PointO + [-0.014f0, 0.075f0, 0f0]
const HLabelPoint = HalfRayHEnd + [0.01f0, 0.055f0, 0f0]
const KLabelPoint = HalfRayKEnd + [0.02f0, 0.05f0, 0f0]

const LabelColor = :plum1
const PointOColor = :khaki3
const HalfRayHColor = :steelblue
const HalfRayKColor = :palevioletred1
const MarkerColor = :khaki3
const LineMaxBrush = 5f0
const PointMaxBrush = 5f0
const MarkerBrush = 1f0

const PenTopZ = 1.4f0
const CompassTopZ = 1.4f0

const DescendDuration = 1.8f0
const DrawPointDuration = 1.6f0
const DrawRayDuration = 2.8f0
const ArcMoveDuration = 1.5f0
const PenLiftDuration = 1.6f0
const CompassDrawDuration = 1.25f0
const CompassLiftDuration = 2.2f0
const FinalHoldDuration = 0.9f0

struct AnimationState
    half_ray_h_host::Int64
    half_ray_h_joint1::Int64
    half_ray_h_joint2::Int64
    half_ray_k_host::Int64
    half_ray_k_joint1::Int64
    half_ray_k_joint2::Int64
    marker_host::Int64
    point_o::Int64
    label_o::Int64
    label_h::Int64
    label_k::Int64
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescendToO = 0f0
const PhaseDrawPointO = 1f0
const PhaseDrawHalfRayH = 2f0
const PhaseArcToOForK = 3f0
const PhaseDrawHalfRayK = 4f0
const PhasePenLiftForMarker = 5f0
const PhaseCompassDrawMarker = 6f0
const PhaseCompassLift = 7f0
const PhaseFinalHold = 8f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(
        state.half_ray_h_host, state.half_ray_h_joint1, state.half_ray_h_joint2,
        state.half_ray_k_host, state.half_ray_k_joint1, state.half_ray_k_joint2,
        state.marker_host, state.point_o,
        state.label_o, state.label_h, state.label_k, phase, timer)
end

"""Get the view content for this animation"""
function get_view_content(_state_ptr::Ptr{Cvoid})
    return HilbertChapterOneDefAngleContent.get_view_content()
end

"""Reset the animation objects and transactionally restart cycle timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    half_ray_h_host_id = state.half_ray_h_host
    half_ray_h_joint2_id = state.half_ray_h_joint2
    half_ray_k_host_id = state.half_ray_k_host
    half_ray_k_joint2_id = state.half_ray_k_joint2
    marker_host_id = state.marker_host
    point_o_id = state.point_o
    label_o_id = state.label_o
    label_h_id = state.label_h
    label_k_id = state.label_k

    OdinJuliaBridge.hide_point_batch(state_ptr,
        [half_ray_h_host_id, half_ray_k_host_id, marker_host_id,
         point_o_id, label_o_id, label_h_id, label_k_id])

    OdinJuliaBridge.set_point_position(state_ptr, half_ray_h_joint2_id, HalfRayHStart)
    OdinJuliaBridge.set_point_position(state_ptr, half_ray_k_joint2_id, HalfRayKStart)
    OdinJuliaBridge.set_arc_geometry(
        state_ptr, marker_host_id, MarkerRadius, 0f0, 0f0)

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescendToO, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.hide_compass(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, PointOColor)
    OdinJuliaBridge.set_compass_active(state_ptr, 0, MarkerColor)
    OdinJuliaBridge.lock_compass_joint1(
        state_ptr, PointO[1], PointO[2], CompassTopZ)
    OdinJuliaBridge.lock_compass_joint2(
        state_ptr, MarkerStart[1], MarkerStart[2], CompassTopZ)

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    half_ray_h = OdinJuliaBridge.create_new_line(
        state_ptr, HalfRayHStart, HalfRayHStart, HalfRayHColor, 0f0)
    half_ray_k = OdinJuliaBridge.create_new_line(
        state_ptr, HalfRayKStart, HalfRayKStart, HalfRayKColor, 0f0)
    marker = OdinJuliaBridge.create_new_filledcircle(state_ptr,
        PointO, MarkerRadius, 0f0, 0f0,
        MarkerColor, 0f0)
    point_o = OdinJuliaBridge.create_new_point(state_ptr, PointO, PointOColor, 0f0)

    label_o = OdinJuliaBridge.create_new_label(
        state_ptr, 'O', OLabelPoint, LabelColor, 16f0)
    label_h = OdinJuliaBridge.create_new_label(
        state_ptr, 'h', HLabelPoint, LabelColor, 16f0)
    label_k = OdinJuliaBridge.create_new_label(
        state_ptr, 'k', KLabelPoint, LabelColor, 16f0)

    state = AnimationState(
        half_ray_h.host_id, half_ray_h.joint1_id, half_ray_h.joint2_id,
        half_ray_k.host_id, half_ray_k.joint1_id, half_ray_k.joint2_id,
        marker.host_id, point_o.index,
        label_o.index, label_h.index, label_k.index, PhaseDescendToO, 0f0)
    reset_cycle_state(state_ptr, state)
    OdinJuliaBridge.publish_view_content(state_ptr, get_view_content)
end

"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
end

"""Perform an iteration of the animation loop for this animation"""
function loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    state, status = OdinJuliaBridge.get_animation_value(state_ptr, StateKey)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return
    half_ray_h_host_id = state.half_ray_h_host
    half_ray_h_joint1_id = state.half_ray_h_joint1
    half_ray_h_joint2_id = state.half_ray_h_joint2
    half_ray_k_host_id = state.half_ray_k_host
    half_ray_k_joint1_id = state.half_ray_k_joint1
    half_ray_k_joint2_id = state.half_ray_k_joint2
    marker_host_id = state.marker_host
    point_o_id = state.point_o
    label_o_id = state.label_o
    label_h_id = state.label_h
    label_k_id = state.label_k

    if half_ray_h_host_id < 0 || half_ray_k_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescendToO
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, DescendDuration, PenTopZ, PointO[1], PointO[2])

        timer += dt
        if timer >= DescendDuration
            phase = PhaseDrawPointO
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_o_id)
        end
    elseif phase == PhaseDrawPointO
        EuclidAnimations.animate_draw_point(
            state_ptr, timer, DrawPointDuration, PointO,
            PointMaxBrush, PointOColor, point_o_id)

        timer += dt
        if timer >= DrawPointDuration
            phase = PhaseDrawHalfRayH
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, HalfRayHColor)
        end
    elseif phase == PhaseDrawHalfRayH
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawRayDuration,
            HalfRayHStart, HalfRayHEnd;
            penbrush=LineMaxBrush,
            pencolor=HalfRayHColor,
            line_host_id=half_ray_h_host_id,
            line_joint1_id=half_ray_h_joint1_id,
            line_joint2_id=half_ray_h_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhaseArcToOForK
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_h_id)
        end
    elseif phase == PhaseArcToOForK
        EuclidAnimations.animate_pen_arcmove(
            state_ptr, timer, ArcMoveDuration,
            HalfRayHEnd, PointO, 0.24f0, 1, :none)

        timer += dt
        if timer >= ArcMoveDuration
            phase = PhaseDrawHalfRayK
            timer = 0f0
            OdinJuliaBridge.set_pen_active(state_ptr, 0, HalfRayKColor)
        end
    elseif phase == PhaseDrawHalfRayK
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawRayDuration,
            HalfRayKStart, HalfRayKEnd;
            penbrush=LineMaxBrush,
            pencolor=HalfRayKColor,
            line_host_id=half_ray_k_host_id,
            line_joint1_id=half_ray_k_joint1_id,
            line_joint2_id=half_ray_k_joint2_id)

        timer += dt
        if timer >= DrawRayDuration
            phase = PhasePenLiftForMarker
            timer = 0f0
            OdinJuliaBridge.show_point(state_ptr, label_k_id)
        end
    elseif phase == PhasePenLiftForMarker
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenLiftDuration, PenTopZ, HalfRayKEnd[1], HalfRayKEnd[2])

        EuclidAnimations.animate_compass_descend(
            state_ptr, timer, PenLiftDuration, CompassTopZ,
            PointO[1], PointO[2], MarkerStart[1], MarkerStart[2])

        timer += dt
        if timer >= PenLiftDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseCompassDrawMarker
            timer = 0f0
        end
    elseif phase == PhaseCompassDrawMarker
        EuclidAnimations.animate_draw_filledcircle(state_ptr,
            timer, CompassDrawDuration, PointO,
            MarkerStart, AngleTheta, MarkerRadius;
            brush=MarkerBrush,
            color=MarkerColor,
            marker_host_id=marker_host_id)

        timer += dt
        if timer >= CompassDrawDuration
            phase = PhaseCompassLift
            timer = 0f0
        end
    elseif phase == PhaseCompassLift
        EuclidAnimations.animate_compass_rise(
            state_ptr, timer, CompassLiftDuration, CompassTopZ,
            PointO[1], PointO[2], MarkerEnd[1], MarkerEnd[2])

        timer += dt
        if timer >= CompassLiftDuration
            OdinJuliaBridge.hide_compass(state_ptr)
            phase = PhaseFinalHold
            timer = 0f0
        end
    elseif phase == PhaseFinalHold
        timer += dt
        if timer >= FinalHoldDuration
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

    if operation == OdinJuliaBridge.ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED
        return true
    elseif operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER
        OdinJuliaBridge.animation_content_specification(state_ptr)
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

AnimationCatalog.animation(
    HilbertChapterOneDefAngle.AnimationId, HilbertChapterOneDefAngle.animation_entry)
