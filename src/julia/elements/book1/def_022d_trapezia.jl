module ElementsOneDefinitionTrapezia

using UUIDs
using ..AnimationCatalog

const AnimationId = UUID("4b1c5b61-6f42-55f6-ab98-00a9d84ab36c")

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

export get_view_text, initialize, clean, loop, animation_entry

const VertexA = [0.14f0, 0.76f0, 0f0]
const VertexB = [0.86f0, 0.76f0, 0f0]
const VertexC = [0.72f0, 0.42f0, 0f0]
const VertexD = [0.28f0, 0.42f0, 0f0]

const SideStarts = (VertexA, VertexB, VertexC, VertexD)
const SideEnds = (VertexB, VertexC, VertexD, VertexA)
const SideColors = (:steelblue, :palevioletred1, :khaki3, :grey60)

const PenTopZ = 1.4f0
const QuadMaxBrush = 5f0

const PenDescendDuration = 1.8f0
const DrawDuration = 2.6f0
const PenRiseDuration = 1.8f0
const HidePauseDuration = 1.5f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Complete immutable state for one trapezia animation generation."""
struct AnimationState
    lines::NTuple{4,LineIds}
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhaseDrawSide4 = 4f0
const PhaseRise = 5f0
const PhaseHideAll = 6f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, phase, timer)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Trapezia

And let quadrilateral figures besides these be called trapezia."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Trapezia}

And let quadrilateral figures besides these be called trapezia \euclidbox[height=2,width=3,thickness=2,edge1_color=steelblue,edge2_color=palevioletred1,edge3_color=khaki3,edge4_color=grey60]."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset visible objects and transactionally publish initial cycle timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line_host_ids = ntuple(i -> state.lines[i].host, 4)
    line_joint2_ids = ntuple(i -> state.lines[i].joint2, 4)

    OdinJuliaBridge.hide_point_batch(state_ptr, line_host_ids)

    for i in 1:4
        OdinJuliaBridge.set_point_position(
            state_ptr, line_joint2_ids[i],
            SideStarts[i][1], SideStarts[i][2], SideStarts[i][3])
    end

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, SideColors[1])

    status = OdinJuliaBridge.set_animation_value!(
        state_ptr, StateKey, with_timing(state, PhaseDescend, 0f0))
    status == OdinJuliaBridge.BRIDGE_STATUS_OK || return false

    OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)
    return true
end

"""Initialize all objects for this animation"""
function initialize(state_ptr::Ptr{Cvoid})
    lines = ntuple(4) do i
        line = OdinJuliaBridge.create_new_line(
            state_ptr, SideStarts[i], SideStarts[i],
            SideColors[i], 0f0)
        LineIds(line.host_id, line.joint1_id, line.joint2_id)
    end

    state = AnimationState(lines, PhaseDescend, 0f0)
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
    line1_host_id = state.lines[1].host
    line_host_ids = ntuple(i -> state.lines[i].host, 4)
    line_joint1_ids = ntuple(i -> state.lines[i].joint1, 4)
    line_joint2_ids = ntuple(i -> state.lines[i].joint2, 4)

    if line1_host_id < 0
        return
    end

    phase = state.phase
    timer = state.timer

    if phase == PhaseDescend
        EuclidAnimations.animate_pen_descend(
            state_ptr, timer, PenDescendDuration, PenTopZ,
            SideStarts[1][1], SideStarts[1][2])

        timer += dt
        if timer >= PenDescendDuration
            phase = PhaseDrawSide1
            timer = 0f0
        end
    elseif phase == PhaseDrawSide1 || phase == PhaseDrawSide2 ||
           phase == PhaseDrawSide3 || phase == PhaseDrawSide4
        side_index = Int(phase)
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            SideStarts[side_index], SideEnds[side_index];
            penbrush=QuadMaxBrush,
            pencolor=SideColors[side_index],
            line_host_id=line_host_ids[side_index],
            line_joint1_id=line_joint1_ids[side_index],
            line_joint2_id=line_joint2_ids[side_index])

        timer += dt
        if timer >= DrawDuration
            if phase == PhaseDrawSide4
                phase = PhaseRise
            else
                phase += 1f0
            end
            timer = 0f0
        end
    elseif phase == PhaseRise
        EuclidAnimations.animate_pen_rise(
            state_ptr, timer, PenRiseDuration, PenTopZ,
            SideStarts[1][1], SideStarts[1][2])

        timer += dt
        if timer >= PenRiseDuration
            OdinJuliaBridge.hide_pen(state_ptr)
            phase = PhaseHideAll
            timer = 0f0
        end
    elseif phase == PhaseHideAll
        timer += dt
        if timer >= HidePauseDuration
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

AnimationCatalog.animation(
    ElementsOneDefinitionTrapezia.AnimationId,
    ElementsOneDefinitionTrapezia.animation_entry)
