module ElementsOneDefinitionMultilateral

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop, animation_entry

const VertexA = [0.50f0, 0.76f0, 0f0]
const VertexB = [0.70f0, 0.62f0, 0f0]
const VertexC = [0.62f0, 0.36f0, 0f0]
const VertexD = [0.38f0, 0.36f0, 0f0]
const VertexE = [0.30f0, 0.62f0, 0f0]
const PenTopZ = 1.4f0

const PentagonColor = :steelblue
const PentagonMaxBrush = 5f0
const PentagonBaseColor = OdinJuliaBridge.bridge_color(PentagonColor)
const FlickerColor = :white
const FlickerSamplesPerFrame = 8

const DescendDuration = 1.8f0
const DrawDuration = 2.25f0
const RiseDuration = 1.8f0
const FlickerDuration = 1f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Stable native handles for the filled pentagon owned by the animation."""
struct PentagonIds
    host::Int64
    joint1::Int64
    joint2::Int64
    joint3::Int64
    joint4::Int64
    joint5::Int64
end

"""Complete immutable state for one multilateral animation generation."""
struct AnimationState
    lines::NTuple{5,LineIds}
    pentagon::PentagonIds
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhaseDrawSide4 = 4f0
const PhaseDrawSide5 = 5f0
const PhaseRise = 6f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, state.pentagon, phase, timer)
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
    random_triangle_point(VertexA, VertexD, VertexE)
end

"""Set the pentagon's fill alpha from a normalized [0, 1] opacity."""
function set_pentagon_alpha(state_ptr::Ptr{Cvoid}, shape_host_id, alpha01)
    t = clamp(alpha01, 0f0, 1f0)
    alpha = UInt8(round(Int, Float32(PentagonBaseColor.a) * t))
    color = OdinJuliaBridge.BridgeColor(
        PentagonBaseColor.r,
        PentagonBaseColor.g,
        PentagonBaseColor.b,
        alpha)
    OdinJuliaBridge.set_point_color(state_ptr, shape_host_id, color)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Rectilineal Figures - Multilateral

Rectilineal figures are those which are contained by straight lines, ... and multilateral those contained by more than four straight lines."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Rectilineal Figures - Multilateral}

Rectilineal figures are those which are contained by straight lines, ... and multilateral \euclidpentagon[height=2,width=2,color=steelblue,filled] those contained by more than four straight lines."""
    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Reset visible objects and transactionally publish initial cycle timing."""
function reset_cycle_state(state_ptr::Ptr{Cvoid}, state::AnimationState)
    line1_host_id = state.lines[1].host
    line1_joint2_id = state.lines[1].joint2
    line2_host_id = state.lines[2].host
    line2_joint2_id = state.lines[2].joint2
    line3_host_id = state.lines[3].host
    line3_joint2_id = state.lines[3].joint2
    line4_host_id = state.lines[4].host
    line4_joint2_id = state.lines[4].joint2
    line5_host_id = state.lines[5].host
    line5_joint2_id = state.lines[5].joint2
    shape_host_id = state.pentagon.host

    OdinJuliaBridge.hide_point_batch(state_ptr, [
        line1_host_id, line2_host_id, line3_host_id,
        line4_host_id, line5_host_id, shape_host_id])
    set_pentagon_alpha(state_ptr, shape_host_id, 0f0)

    OdinJuliaBridge.set_point_position(
        state_ptr, line1_joint2_id, VertexA[1], VertexA[2], VertexA[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line2_joint2_id, VertexB[1], VertexB[2], VertexB[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line3_joint2_id, VertexC[1], VertexC[2], VertexC[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line4_joint2_id, VertexD[1], VertexD[2], VertexD[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line5_joint2_id, VertexE[1], VertexE[2], VertexE[3])

    OdinJuliaBridge.hide_pen(state_ptr)
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
        state_ptr, VertexE, VertexE,
        PentagonColor, 0f0)
    pentagon = OdinJuliaBridge.create_new_pentagon(state_ptr,
        VertexA, VertexE, VertexD, VertexC, VertexB, PentagonColor)

    state = AnimationState((
        LineIds(line1.host_id, line1.joint1_id, line1.joint2_id),
        LineIds(line2.host_id, line2.joint1_id, line2.joint2_id),
        LineIds(line3.host_id, line3.joint1_id, line3.joint2_id),
        LineIds(line4.host_id, line4.joint1_id, line4.joint2_id),
        LineIds(line5.host_id, line5.joint1_id, line5.joint2_id)),
        PentagonIds(pentagon.host_id, pentagon.joint1_id, pentagon.joint2_id,
            pentagon.joint3_id, pentagon.joint4_id, pentagon.joint5_id),
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
    line1_host_id = state.lines[1].host
    line1_joint1_id = state.lines[1].joint1
    line1_joint2_id = state.lines[1].joint2
    line2_host_id = state.lines[2].host
    line2_joint1_id = state.lines[2].joint1
    line2_joint2_id = state.lines[2].joint2
    line3_host_id = state.lines[3].host
    line3_joint1_id = state.lines[3].joint1
    line3_joint2_id = state.lines[3].joint2
    line4_host_id = state.lines[4].host
    line4_joint1_id = state.lines[4].joint1
    line4_joint2_id = state.lines[4].joint2
    line5_host_id = state.lines[5].host
    line5_joint1_id = state.lines[5].joint1
    line5_joint2_id = state.lines[5].joint2
    shape_host_id = state.pentagon.host

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
            phase = PhaseDrawSide1
            timer = 0f0
        end
    elseif phase == PhaseDrawSide1
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            VertexA, VertexB;
            penbrush=PentagonMaxBrush,
            pencolor=PentagonColor,
            line_host_id=line1_host_id,
            line_joint1_id=line1_joint1_id,
            line_joint2_id=line1_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide2
            timer = 0f0
        end
    elseif phase == PhaseDrawSide2
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            VertexB, VertexC;
            penbrush=PentagonMaxBrush,
            pencolor=PentagonColor,
            line_host_id=line2_host_id,
            line_joint1_id=line2_joint1_id,
            line_joint2_id=line2_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide3
            timer = 0f0
        end
    elseif phase == PhaseDrawSide3
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            VertexC, VertexD;
            penbrush=PentagonMaxBrush,
            pencolor=PentagonColor,
            line_host_id=line3_host_id,
            line_joint1_id=line3_joint1_id,
            line_joint2_id=line3_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide4
            timer = 0f0
        end
    elseif phase == PhaseDrawSide4
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            VertexD, VertexE;
            penbrush=PentagonMaxBrush,
            pencolor=PentagonColor,
            line_host_id=line4_host_id,
            line_joint1_id=line4_joint1_id,
            line_joint2_id=line4_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseDrawSide5
            timer = 0f0
        end
    elseif phase == PhaseDrawSide5
        EuclidAnimations.animate_draw_line(state_ptr,
            timer, DrawDuration,
            VertexE, VertexA;
            penbrush=PentagonMaxBrush,
            pencolor=PentagonColor,
            line_host_id=line5_host_id,
            line_joint1_id=line5_joint1_id,
            line_joint2_id=line5_joint2_id)

        timer += dt
        if timer >= DrawDuration
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
