module ElementsOneDefinitionTrilateral

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..EuclidLatex

using LinearAlgebra

export get_view_text, initialize, clean, loop

const VertexA = [0.31f0, 0.70f0, 0f0]
const VertexB = [0.50f0, 0.34f0, 0f0]
const VertexC = [0.69f0, 0.70f0, 0f0]
const PenTopZ = 1.4f0

const TriangleColor = :steelblue
const TriangleMaxBrush = 5f0
const TriangleBaseColor = OdinJuliaBridge.bridge_color(TriangleColor)
const FlickerColor = :white
const FlickerSamplesPerFrame = 8

const DescendDuration = 1.8f0
const DrawDuration = 3.1f0
const RiseDuration = 1.8f0
const FlickerDuration = 1f0

"""Stable native handles for one line owned by the animation."""
struct LineIds
    host::Int64
    joint1::Int64
    joint2::Int64
end

"""Stable native handles for the filled triangle owned by the animation."""
struct TriangleIds
    host::Int64
    joint1::Int64
    joint2::Int64
    joint3::Int64
end

"""Complete immutable state for one trilateral animation generation."""
struct AnimationState
    lines::NTuple{3,LineIds}
    triangle::TriangleIds
    phase::Float32
    timer::Float32
end

const StateKey = OdinJuliaBridge.AnimationKey{AnimationState}(0x01)

const PhaseDescend = 0f0
const PhaseDrawSide1 = 1f0
const PhaseDrawSide2 = 2f0
const PhaseDrawSide3 = 3f0
const PhaseRise = 4f0

"""Return state with updated cycle timing and unchanged native handles."""
function with_timing(state::AnimationState, phase::Float32, timer::Float32)
    return AnimationState(state.lines, state.triangle, phase, timer)
end

"""Pick a random interior point of the triangle with vertices a, b, and c."""
function random_triangle_point(
    a::Vector{Float32}, b::Vector{Float32}, c::Vector{Float32})
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

"""Set the triangle's fill alpha from a normalized [0, 1] opacity."""
function set_triangle_alpha(state_ptr::Ptr{Cvoid}, triangle_host_id, alpha01)
    t = clamp(alpha01, 0f0, 1f0)
    alpha = UInt8(round(Int, Float32(TriangleBaseColor.a) * t))
    color = OdinJuliaBridge.BridgeColor(
        TriangleBaseColor.r,
        TriangleBaseColor.g,
        TriangleBaseColor.b,
        alpha)
    OdinJuliaBridge.set_point_color(state_ptr, triangle_host_id, color)
end

"""Get the view text for this animation"""
function get_view_text(state_ptr::Ptr{Cvoid})
    fallback = """Euclid Elements - Book I - Definition: Rectilineal Figures - Trilateral

Rectilineal figures are those which are contained by straight lines, trilateral figures being those contained by three..."""
    latex = raw"""\textbf{Euclid Elements - Book I - Definition}: \textit{Rectilineal Figures - Trilateral}

Rectilineal figures are those which are contained by straight lines, trilateral figures \euclidtriangle[height=2,width=3,color=steelblue,filled] being those contained by three..."""
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
    triangle_host_id = state.triangle.host

    OdinJuliaBridge.hide_point_batch(state_ptr, [
        line1_host_id, line2_host_id, line3_host_id, triangle_host_id])
    set_triangle_alpha(state_ptr, triangle_host_id, 0f0)

    OdinJuliaBridge.set_point_position(
        state_ptr, line1_joint2_id, VertexA[1], VertexA[2], VertexA[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line2_joint2_id, VertexB[1], VertexB[2], VertexB[3])
    OdinJuliaBridge.set_point_position(
        state_ptr, line3_joint2_id, VertexC[1], VertexC[2], VertexC[3])

    OdinJuliaBridge.hide_pen(state_ptr)
    OdinJuliaBridge.show_pen(state_ptr)
    OdinJuliaBridge.set_pen_active(state_ptr, 0, TriangleColor)

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
        TriangleColor, 0f0)
    line2 = OdinJuliaBridge.create_new_line(
        state_ptr, VertexB, VertexB,
        TriangleColor, 0f0)
    line3 = OdinJuliaBridge.create_new_line(
        state_ptr, VertexC, VertexC,
        TriangleColor, 0f0)
    triangle = OdinJuliaBridge.create_new_triangle(state_ptr,
        VertexA, VertexB, VertexC, TriangleColor)

    state = AnimationState((
        LineIds(line1.host_id, line1.joint1_id, line1.joint2_id),
        LineIds(line2.host_id, line2.joint1_id, line2.joint2_id),
        LineIds(line3.host_id, line3.joint1_id, line3.joint2_id)),
        TriangleIds(triangle.host_id, triangle.joint1_id, triangle.joint2_id,
            triangle.joint3_id), PhaseDescend, 0f0)
    reset_cycle_state(state_ptr, state)
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
    triangle_host_id = state.triangle.host

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
            penbrush=TriangleMaxBrush,
            pencolor=TriangleColor,
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
            penbrush=TriangleMaxBrush,
            pencolor=TriangleColor,
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
            VertexC, VertexA;
            penbrush=TriangleMaxBrush,
            pencolor=TriangleColor,
            line_host_id=line3_host_id,
            line_joint1_id=line3_joint1_id,
            line_joint2_id=line3_joint2_id)

        timer += dt
        if timer >= DrawDuration
            phase = PhaseRise
            timer = 0f0
        end
    elseif phase == PhaseRise
        set_triangle_alpha(state_ptr, triangle_host_id, timer / FlickerDuration)
        OdinJuliaBridge.show_point(state_ptr, triangle_host_id)

        if timer <= FlickerDuration
            for _ in 1:FlickerSamplesPerFrame
                sample_pos = random_triangle_point(VertexA, VertexB, VertexC)
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

end
