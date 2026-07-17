"""
EuclidRepl

REPL-first geometry helpers for interactive point, line, and circle drawing
with tool animation.

Key behavior:
- one active draw job at a time,
- new draws preempt active draw and finalize interrupted shape visibility,
- drawn geometry persists until scratchpad session reset/restart.

Use `?EuclidRepl.point!`, `?EuclidRepl.line!`, and `?EuclidRepl.circle!`
for API details.
"""
module EuclidRepl

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..Scratchpad

export DEFAULT_POINT_DURATION, DEFAULT_LINE_DURATION, DEFAULT_CIRCLE_DURATION,
    DEFAULT_COLOR, DEFAULT_BRUSH,
    point!, line!, circle!, stop!, clear!, status

const DEFAULT_POINT_DURATION = 5.5f0
const DEFAULT_LINE_DURATION = 7.5f0
const DEFAULT_CIRCLE_DURATION = 8.0f0
const DEFAULT_COLOR = :steelblue
const DEFAULT_BRUSH = 5f0

const TWO_PI_F32 = Float32(2π)

abstract type ReplDrawPayload end

struct PointPayload <: ReplDrawPayload
    point_id::Int
    pos::Vector{Float32}
    color
    brush::Float32
end

struct LinePayload <: ReplDrawPayload
    host_id::Int
    start_id::Int
    end_id::Int
    start_pos::Vector{Float32}
    end_pos::Vector{Float32}
    color
    brush::Float32
end

struct CirclePayload <: ReplDrawPayload
    filled::Bool
    full_sweep::Bool
    host_id::Int
    start_id::Int
    end_id::Int
    center::Vector{Float32}
    start_pos::Vector{Float32}
    end_pos::Vector{Float32}
    radius::Float32
    angle_theta::Float32
    color
    brush::Float32
end

mutable struct ReplDrawJob
    kind::Symbol
    duration::Float32
    elapsed::Float32
    hook_id::Union{Nothing, Int}
    payload::ReplDrawPayload
end

mutable struct ReplDrawSession
    active_job::Union{Nothing, ReplDrawJob}
    managed_host_ids::Vector{Int}
end

const session_ref = Ref{Union{Nothing, ReplDrawSession}}(nothing)

"""Return the singleton EuclidRepl session, creating it when missing."""
function ensure_session!()
    session = session_ref[]
    if session === nothing
        session = ReplDrawSession(nothing, Int[])
        session_ref[] = session
    end

    return session
end

"""Return `value` as `Float32` and fail when duration is non-positive or non-finite."""
function validated_duration(value)::Float32
    duration = Float32(value)
    if !isfinite(duration) || duration <= 0f0
        throw(ArgumentError("duration must be finite and > 0f0"))
    end

    return duration
end

"""Return `value` as `Float32` and fail when brush is non-positive or non-finite."""
function validated_brush(value)::Float32
    brush = Float32(value)
    if !isfinite(brush) || brush <= 0f0
        throw(ArgumentError("brush must be finite and > 0f0"))
    end

    return brush
end

"""Validate that start theta is finite and return it as `Float32`."""
function validated_start_theta(value)::Float32
    theta = Float32(value)
    if !isfinite(theta)
        throw(ArgumentError("start_theta must be finite"))
    end

    return theta
end

"""Validate end theta and return it as `Float32`, allowing `Inf` sentinel."""
function validated_end_theta(value)::Float32
    theta = Float32(value)
    if isnan(theta)
        throw(ArgumentError("end_theta must not be NaN"))
    end

    return theta
end

"""Return a copied 3D Float32 vector, failing when length is below 3."""
function vec3(name::AbstractString, value::Vector{Float32})
    if length(value) < 3
        throw(ArgumentError("$(name) must have at least 3 Float32 components"))
    end

    if !isfinite(value[1]) || !isfinite(value[2]) || !isfinite(value[3])
        throw(ArgumentError("$(name) components must be finite"))
    end

    return Float32[value[1], value[2], value[3]]
end

"""Compute final end theta for REPL circle semantics."""
function effective_end_theta(start_theta::Float32, end_theta::Float32)
    if !isfinite(end_theta)
        return start_theta + TWO_PI_F32
    end

    if end_theta - start_theta >= TWO_PI_F32
        return start_theta + TWO_PI_F32
    end

    return end_theta
end

"""Return true when REPL semantics should treat the requested arc as full sweep."""
function is_full_sweep_request(start_theta::Float32, end_theta::Float32)::Bool
    if !isfinite(end_theta)
        return true
    end

    return (end_theta - start_theta) >= TWO_PI_F32
end

"""Compute a point on the XY circle at `theta`, keeping center z."""
function point_on_circle(center::Vector{Float32}, radius::Float32, theta::Float32)
    return Float32[
        center[1] + radius * Float32(cos(theta)),
        center[2] + radius * Float32(sin(theta)),
        center[3],
    ]
end

"""Apply final visible state for a point payload."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::PointPayload)
    OdinJuliaBridge.set_point_color(state_ptr, payload.point_id, payload.color)
    OdinJuliaBridge.set_point_brush(state_ptr, payload.point_id, payload.brush)
    OdinJuliaBridge.set_point_position(state_ptr, payload.point_id, payload.pos)
    OdinJuliaBridge.show_point(state_ptr, payload.point_id)
end

"""Apply final visible state for a line payload."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::LinePayload)
    OdinJuliaBridge.set_point_color(state_ptr, payload.host_id, payload.color)
    OdinJuliaBridge.set_point_brush(state_ptr, payload.host_id, payload.brush)
    OdinJuliaBridge.set_point_position(state_ptr, payload.start_id, payload.start_pos)
    OdinJuliaBridge.set_point_position(state_ptr, payload.end_id, payload.end_pos)
    OdinJuliaBridge.show_point(state_ptr, payload.host_id)
end

"""Apply final visible state for a circle payload."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::CirclePayload)
    OdinJuliaBridge.set_point_color(state_ptr, payload.host_id, payload.color)
    OdinJuliaBridge.set_point_brush(state_ptr, payload.host_id, payload.brush)
    OdinJuliaBridge.set_point_position(state_ptr, payload.start_id, payload.start_pos)
    OdinJuliaBridge.set_point_position(state_ptr, payload.end_id, payload.end_pos)
    if payload.full_sweep
        OdinJuliaBridge.set_point_offset(state_ptr, payload.host_id, TWO_PI_F32)
    else
        OdinJuliaBridge.set_point_offset(state_ptr, payload.host_id, 0f0)
    end
    OdinJuliaBridge.show_point(state_ptr, payload.host_id)
end

"""Render one frame of the active payload animation at elapsed draw time."""
function render_payload!(state_ptr::Ptr{Cvoid}, elapsed::Float32, duration::Float32, payload::PointPayload)
    EuclidAnimations.animate_repl_draw_point(
        state_ptr,
        elapsed,
        duration,
        payload.pos,
        payload.brush,
        payload.color,
        payload.point_id)
end

"""Render one frame of the active payload animation at elapsed draw time."""
function render_payload!(state_ptr::Ptr{Cvoid}, elapsed::Float32, duration::Float32, payload::LinePayload)
    EuclidAnimations.animate_repl_draw_line(
        state_ptr,
        elapsed,
        duration,
        payload.start_pos,
        payload.end_pos,
        payload.brush,
        payload.color,
        payload.host_id,
        payload.start_id,
        payload.end_id)
end

"""Render one frame of the active payload animation at elapsed draw time."""
function render_payload!(state_ptr::Ptr{Cvoid}, elapsed::Float32, duration::Float32, payload::CirclePayload)
    if payload.filled
        EuclidAnimations.animate_repl_draw_filledcircle(
            state_ptr,
            elapsed,
            duration,
            payload.center,
            payload.start_pos,
            payload.angle_theta,
            payload.radius,
            payload.brush,
            payload.color,
            payload.host_id,
            payload.start_id,
            payload.end_id)
    else
        EuclidAnimations.animate_repl_draw_circle(
            state_ptr,
            elapsed,
            duration,
            payload.center,
            payload.start_pos,
            payload.angle_theta,
            payload.radius,
            payload.brush,
            payload.color,
            payload.host_id,
            payload.start_id,
            payload.end_id)
    end
end

"""Finalize active job visibility and hide the tool used for that job."""
function finalize_job!(state_ptr::Ptr{Cvoid}, job::ReplDrawJob)
    if state_ptr == Ptr{Cvoid}(0)
        return
    end

    finalize_payload!(state_ptr, job.payload)
    if job.kind == :point || job.kind == :line
        OdinJuliaBridge.hide_pen(state_ptr)
    else
        OdinJuliaBridge.hide_compass(state_ptr)
    end
end

"""Remove active hook and clear active job state for the current session."""
function clear_active_job!(state_ptr::Ptr{Cvoid}, session::ReplDrawSession)
    job = session.active_job
    if job === nothing
        return
    end

    if job.hook_id !== nothing
        Scratchpad.remove_frame_hook_silent(state_ptr, job.hook_id)
        job.hook_id = nothing
    end

    session.active_job = nothing
end

"""Track a host point id as managed EuclidRepl geometry."""
function track_managed_host!(session::ReplDrawSession, host_id::Int)
    if !(host_id in session.managed_host_ids)
        push!(session.managed_host_ids, host_id)
    end
end

"""Hide all EuclidRepl-managed geometry and clear the host-id registry."""
function clear_managed_geometry!(state_ptr::Ptr{Cvoid}, session::ReplDrawSession)
    if state_ptr != Ptr{Cvoid}(0)
        for host_id in session.managed_host_ids
            OdinJuliaBridge.hide_point(state_ptr, host_id)
        end
    end

    empty!(session.managed_host_ids)
end

"""Advance the current active EuclidRepl draw job by one frame."""
function run_active_job_frame!(state_ptr::Ptr{Cvoid}, dt::Float32)
    session = ensure_session!()
    job = session.active_job
    if job === nothing
        return
    end

    dt_clamped = max(0f0, Float32(dt))
    job.elapsed = min(job.duration, job.elapsed + dt_clamped)
    render_payload!(state_ptr, job.elapsed, job.duration, job.payload)

    if job.elapsed >= job.duration
        finalize_job!(state_ptr, job)
        clear_active_job!(state_ptr, session)
    end
end

"""Preempt active draw (if any), then register and start a replacement draw job."""
function start_job!(state_ptr::Ptr{Cvoid}, job::ReplDrawJob)
    session = ensure_session!()

    if session.active_job !== nothing
        finalize_job!(state_ptr, session.active_job)
        clear_active_job!(state_ptr, session)
    end

    hook_id = Scratchpad.register_frame_hook_silent(
        state_ptr,
        (hook_state_ptr, dt) -> run_active_job_frame!(hook_state_ptr, dt),
        label="EuclidRepl active draw")

    job.hook_id = hook_id
    # Scratchpad may initialize lazily during hook registration; re-read session
    # reference to avoid writing active state into a stale session object.
    ensure_session!().active_job = job
end

"""Reset EuclidRepl session state for scratchpad lifecycle transitions."""
function reset_scratchpad_session!()
    session_ref[] = nothing
    return nothing
end

"""
Stop the active draw animation hook without deleting geometry.

Returns `true` when an active draw was stopped, otherwise `false`.
"""
function stop!(state_ptr::Ptr{Cvoid})
    session = ensure_session!()
    job = session.active_job
    if job === nothing
        return false
    end

    finalize_job!(state_ptr, job)
    clear_active_job!(state_ptr, session)
    return true
end

"""
Clear EuclidRepl-managed geometry and reset active draw state.

Returns `true` when clear completes.
"""
function clear!(state_ptr::Ptr{Cvoid})
    session = ensure_session!()
    clear_active_job!(state_ptr, session)
    clear_managed_geometry!(state_ptr, session)
    return true
end

"""Return compact EuclidRepl runtime status for REPL inspection."""
function status(state_ptr::Ptr{Cvoid})
    session = ensure_session!()
    job = session.active_job

    if job === nothing
        return (
            active = false,
            kind = nothing,
            elapsed = nothing,
            duration = nothing,
            hook_id = nothing,
            managed_shape_count = length(session.managed_host_ids),
        )
    end

    return (
        active = true,
        kind = job.kind,
        elapsed = job.elapsed,
        duration = job.duration,
        hook_id = job.hook_id,
        managed_shape_count = length(session.managed_host_ids),
    )
end

"""
Draw a point with pen animation and return a `BridgePointView` handle.

Keywords:
- `color=:steelblue`
- `brush=5f0`
- `duration=DEFAULT_POINT_DURATION` (draw animation duration only)
"""
function point!(state_ptr::Ptr{Cvoid}, pos::Vector{Float32};
    color=DEFAULT_COLOR, brush::Float32=DEFAULT_BRUSH,
    duration::Float32=DEFAULT_POINT_DURATION)
    pos3 = vec3("pos", pos)
    brush_value = validated_brush(brush)
    draw_duration = validated_duration(duration)

    point = OdinJuliaBridge.create_new_point(state_ptr, pos3, color, brush_value)
    payload = PointPayload(Int(point.index), pos3, color, brush_value)
    job = ReplDrawJob(:point, draw_duration, Float32(0f0), nothing, payload)

    start_job!(state_ptr, job)
    track_managed_host!(ensure_session!(), Int(point.index))
    return point
end

"""
Draw a line with pen animation and return a `BridgeShapeLine` handle.

Keywords:
- `color=:steelblue`
- `brush=5f0`
- `duration=DEFAULT_LINE_DURATION` (draw animation duration only)
"""
function line!(state_ptr::Ptr{Cvoid}, start_pos::Vector{Float32}, end_pos::Vector{Float32};
    color=DEFAULT_COLOR, brush::Float32=DEFAULT_BRUSH,
    duration::Float32=DEFAULT_LINE_DURATION)
    start_pos3 = vec3("start_pos", start_pos)
    end_pos3 = vec3("end_pos", end_pos)
    brush_value = validated_brush(brush)
    draw_duration = validated_duration(duration)

    line_shape = OdinJuliaBridge.create_new_line(
        state_ptr,
        start_pos3,
        start_pos3,
        color,
        brush_value)

    payload = LinePayload(
        Int(line_shape.hostId),
        Int(line_shape.joint1Id),
        Int(line_shape.joint2Id),
        start_pos3,
        end_pos3,
        color,
        brush_value)

    job = ReplDrawJob(:line, draw_duration, Float32(0f0), nothing, payload)
    start_job!(state_ptr, job)
    track_managed_host!(ensure_session!(), Int(line_shape.hostId))
    return line_shape
end

"""
Draw a circle, arc, or sector with compass animation and return a circle handle.

Keywords:
- `start_theta=0f0`
- `end_theta=Inf32` (default full-circle sentinel)
- `filled=false`
- `color=:steelblue`
- `brush=5f0`
- `duration=DEFAULT_CIRCLE_DURATION` (draw animation duration only)

Circle rules:
- full circle when `end_theta - start_theta >= 2pi` or `end_theta` is infinite,
- full circles still start at `start_theta` and sweep one full turn.
"""
function circle!(state_ptr::Ptr{Cvoid}, center::Vector{Float32}, radius::Float32;
    start_theta::Float32=0f0, end_theta::Float32=Inf32, filled::Bool=false,
    color=DEFAULT_COLOR, brush::Float32=DEFAULT_BRUSH,
    duration::Float32=DEFAULT_CIRCLE_DURATION)
    center3 = vec3("center", center)
    brush_value = validated_brush(brush)
    draw_duration = validated_duration(duration)
    start_theta_valid = validated_start_theta(start_theta)
    end_theta_valid = validated_end_theta(end_theta)
    full_sweep = is_full_sweep_request(start_theta_valid, end_theta_valid)

    if !isfinite(radius) || radius <= 0f0
        throw(ArgumentError("radius must be finite and > 0f0"))
    end

    final_end_theta = effective_end_theta(start_theta_valid, end_theta_valid)
    start_pos = point_on_circle(center3, radius, start_theta_valid)
    end_pos = point_on_circle(center3, radius, final_end_theta)
    angle_theta = final_end_theta - start_theta_valid

    shape = if filled
        OdinJuliaBridge.create_new_filledcircle(
            state_ptr,
            center3,
            radius,
            start_theta_valid,
            final_end_theta,
            color,
            brush_value)
    else
        OdinJuliaBridge.create_new_circle(
            state_ptr,
            center3,
            radius,
            start_theta_valid,
            final_end_theta,
            color,
            brush_value)
    end

    payload = CirclePayload(
        filled,
        full_sweep,
        Int(shape.hostId),
        Int(shape.startId),
        Int(shape.endId),
        center3,
        start_pos,
        end_pos,
        radius,
        angle_theta,
        color,
        brush_value)

    job = ReplDrawJob(:circle, draw_duration, Float32(0.0), nothing, payload)
    start_job!(state_ptr, job)
    track_managed_host!(ensure_session!(), Int(shape.hostId))
    return shape
end

end
