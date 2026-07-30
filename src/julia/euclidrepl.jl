"""
EuclidRepl

REPL-first geometry helpers for interactive point, line, and circle drawing
with tool animation.

Key behavior:
- one active draw job at a time,
- new draws preempt active draw and finalize interrupted shape visibility,
- drawn geometry persists until scratchpad session reset/restart.

Use `?point!`, `?line!`, and `?circle!` for API details.
"""
module EuclidRepl

using ..OdinJuliaBridge
using ..EuclidAnimations
using ..Scratchpad
using Colors: Colorant

export DEFAULT_POINT_DURATION, DEFAULT_LINE_DURATION, DEFAULT_CIRCLE_DURATION,
    DEFAULT_TRANSFORM_DURATION, DEFAULT_HIGHLIGHT_DURATION,
    DEFAULT_COLOR, DEFAULT_HIGHLIGHT_COLOR, DEFAULT_BRUSH,
    euclidcolors, hide!, point!, line!, circle!, highlight_pen!, highlight_compass!,
    translate_points!, rotate_points!, rotate_points_x!, rotate_points_y!, rotate_points_z!,
    reflect2d_points!, reflect2d_points_x_axis!, reflect2d_points_y_axis!,
    reflect2d_points_diag_pos!, reflect2d_points_diag_neg!,
    stop!, clear!, status

const DEFAULT_POINT_DURATION = 5.5f0
const DEFAULT_LINE_DURATION = 7.5f0
const DEFAULT_CIRCLE_DURATION = 8.0f0
const DEFAULT_TRANSFORM_DURATION = 2.5f0
const DEFAULT_HIGHLIGHT_DURATION = 3.2f0
const DEFAULT_COLOR = :steelblue
const DEFAULT_HIGHLIGHT_COLOR = :lightgreen
const DEFAULT_BRUSH = 5f0
const HIGHLIGHT_TOOL_TOP_Z = 1.4f0
const HIGHLIGHT_DESCEND_SHARE = 0.2f0
const HIGHLIGHT_PASS_SHARE = 0.3f0

const TWO_PI_F32 = Float32(2π)
const EUCLID_COLORS = (
    :steelblue,
    :palevioletred1,
    :khaki3,
    :grey60,
    :plum1,
    :lightgreen,
    :firebrick,
)

"""Return the curated Euclid color palette as Julia Colors objects."""
function euclidcolors()
    [parse(Colorant, String(name)) for name in EUCLID_COLORS]
end

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

struct PenHighlightPayload <: ReplDrawPayload
    start_pos::Vector{Float32}
    end_pos::Vector{Float32}
    color
end

struct CompassHighlightPayload <: ReplDrawPayload
    center::Vector{Float32}
    start_pos::Vector{Float32}
    end_pos::Vector{Float32}
    angle_theta::Float32
    radius::Float32
    color
    filled::Bool
end

abstract type TransformSpec end

struct TranslateSpec <: TransformSpec
    displacement::Vector{Float32}
end

struct RotateSpec <: TransformSpec
    axis_a::Vector{Float32}
    axis_b::Vector{Float32}
    theta::Float32
end

struct Reflect2DSpec <: TransformSpec
    line_a::Vector{Float32}
    line_b::Vector{Float32}
end

struct TransformPayload <: ReplDrawPayload
    point_ids::Vector{Int}
    start_positions::Vector{Vector{Float32}}
    spec::TransformSpec
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
function validated_duration(value::Real)::Float32
    duration = Float32(value)
    if !isfinite(duration) || duration <= 0f0
        throw(ArgumentError("duration must be finite and > 0f0"))
    end

    return duration
end

"""Return `value` as `Float32` and fail when brush is non-positive or non-finite."""
function validated_brush(value::Real)::Float32
    brush = Float32(value)
    if !isfinite(brush) || brush <= 0f0
        throw(ArgumentError("brush must be finite and > 0f0"))
    end

    return brush
end

"""Validate that start theta is finite and return it as `Float32`."""
function validated_start_theta(value::Real)::Float32
    theta = Float32(value)
    if !isfinite(theta)
        throw(ArgumentError("start_theta must be finite"))
    end

    return theta
end

"""Validate end theta and return it as `Float32`, allowing `Inf` sentinel."""
function validated_end_theta(value::Real)::Float32
    theta = Float32(value)
    if isnan(theta)
        throw(ArgumentError("end_theta must not be NaN"))
    end

    return theta
end

"""Validate highlight angle theta as a finite Float32 value."""
function validated_angle_theta(value::Real)::Float32
    theta = Float32(value)
    if !isfinite(theta)
        throw(ArgumentError("angle_theta must be finite"))
    end

    return theta
end

"""Validate highlight radius as finite and positive Float32."""
function validated_radius(value::Real)::Float32
    radius = Float32(value)
    if !isfinite(radius) || radius <= 0f0
        throw(ArgumentError("radius must be finite and > 0f0"))
    end

    return radius
end

"""Return a copied 3D Float32 vector, failing when length is below 3."""
function vec3(name::AbstractString, value::AbstractVector{<:Real})
    if length(value) < 3
        throw(ArgumentError("$(name) must have at least 3 Float32 components"))
    end

    first_value = Float32(value[1])
    second_value = Float32(value[2])
    third_value = Float32(value[3])
    if !isfinite(first_value) || !isfinite(second_value) || !isfinite(third_value)
        throw(ArgumentError("$(name) components must be finite"))
    end

    return Float32[first_value, second_value, third_value]
end

"""Return validated non-empty point ids as `Vector{Int}`."""
function validated_point_ids(point_ids)
    ids = Int[Integer(id) for id in point_ids]
    if isempty(ids)
        throw(ArgumentError("point_ids must contain at least one id"))
    end
    return ids
end

"""Return validated start positions, one 3D position per point id."""
function validated_start_positions(start_positions)
    positions = Vector{Vector{Float32}}()
    for (idx, pos) in enumerate(start_positions)
        push!(positions, vec3("start_positions[$(idx)]", pos))
    end
    return positions
end

"""Validate matching lengths for point ids and start positions."""
function validate_transform_batch_lengths(
    point_ids::Vector{Int}, start_positions::Vector{Vector{Float32}})

    if length(point_ids) != length(start_positions)
        throw(ArgumentError("point_ids and start_positions must have equal length"))
    end
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
function point_on_circle(center::AbstractVector{<:Real}, radius::Real, theta::Real)
    center_vec = vec3("center", center)
    radius32 = Float32(radius)
    theta32 = Float32(theta)
    return Float32[
        center_vec[1] + radius32 * Float32(cos(theta32)),
        center_vec[2] + radius32 * Float32(sin(theta32)),
        center_vec[3],
    ]
end

"""Return XY polar angle from center to point as Float32."""
function theta_from_center(center::AbstractVector{<:Real}, point::AbstractVector{<:Real})
    center_vec = vec3("center", center)
    point_vec = vec3("point", point)
    return Float32(atan(point_vec[2] - center_vec[2], point_vec[1] - center_vec[1]))
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

"""Apply final visible state for a transform payload at completed progress."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::TransformPayload)
    for (index, point_id) in pairs(payload.point_ids)
        start_position = payload.start_positions[index]
        render_transform_spec!(state_ptr, 1f0, 1f0, point_id, start_position, payload.spec)
    end
end

"""Render one frame of the active payload animation at elapsed draw time."""
function render_payload!(state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::PointPayload)
    EuclidAnimations.animate_repl_draw_point(
        state_ptr,
        Float32(elapsed),
        Float32(duration),
        payload.pos,
        payload.brush,
        payload.color,
        payload.point_id)
end

"""Render one frame of the active payload animation at elapsed draw time."""
function render_payload!(state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::LinePayload)
    EuclidAnimations.animate_repl_draw_line(
        state_ptr,
        Float32(elapsed),
        Float32(duration),
        payload.start_pos,
        payload.end_pos,
        payload.brush,
        payload.color,
        payload.host_id,
        payload.start_id,
        payload.end_id)
end

"""Render one frame of the active payload animation at elapsed draw time."""
function render_payload!(state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::CirclePayload)
    if payload.filled
        EuclidAnimations.animate_repl_draw_filledcircle(
            state_ptr,
            Float32(elapsed),
            Float32(duration),
            payload.center,
            payload.start_pos,
            payload.angle_theta,
            payload.radius,
            payload.brush,
            payload.color,
            payload.host_id,
            payload.start_id,
            payload.end_id,
            payload.full_sweep)
    else
        EuclidAnimations.animate_repl_draw_circle(
            state_ptr,
            Float32(elapsed),
            Float32(duration),
            payload.center,
            payload.start_pos,
            payload.angle_theta,
            payload.radius,
            payload.brush,
            payload.color,
            payload.host_id,
            payload.start_id,
            payload.end_id,
            payload.full_sweep)
    end
end

"""Render one frame of pen highlight with descend-pass-pass-rise sequencing."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::PenHighlightPayload)

    descend_duration = duration * HIGHLIGHT_DESCEND_SHARE
    pass_duration = duration * HIGHLIGHT_PASS_SHARE
    first_pass_start = descend_duration
    second_pass_start = first_pass_start + pass_duration
    rise_start = second_pass_start + pass_duration
    rise_duration = max(duration - rise_start, 1f-5)

    if elapsed < first_pass_start
        EuclidAnimations.animate_pen_descend(
            state_ptr,
            elapsed,
            descend_duration,
            HIGHLIGHT_TOOL_TOP_Z,
            payload.start_pos[1],
            payload.start_pos[2],
        )
        return
    end

    if elapsed < second_pass_start
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr,
            elapsed - first_pass_start,
            pass_duration,
            payload.start_pos,
            payload.end_pos,
            payload.color,
        )
        return
    end

    if elapsed < rise_start
        EuclidAnimations.animate_pen_tilt_and_drag(
            state_ptr,
            elapsed - second_pass_start,
            pass_duration,
            payload.end_pos,
            payload.start_pos,
            payload.color,
        )
        return
    end

    EuclidAnimations.animate_pen_rise(
        state_ptr,
        elapsed - rise_start,
        rise_duration,
        HIGHLIGHT_TOOL_TOP_Z,
        payload.start_pos[1],
        payload.start_pos[2],
    )
end

"""Render one frame of compass highlight with descend-pass-pass-rise sequencing."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::CompassHighlightPayload)

    descend_duration = duration * HIGHLIGHT_DESCEND_SHARE
    pass_duration = duration * HIGHLIGHT_PASS_SHARE
    first_pass_start = descend_duration
    second_pass_start = first_pass_start + pass_duration
    rise_start = second_pass_start + pass_duration
    rise_duration = max(duration - rise_start, 1f-5)

    if elapsed < first_pass_start
        EuclidAnimations.animate_compass_descend(
            state_ptr,
            elapsed,
            descend_duration,
            HIGHLIGHT_TOOL_TOP_Z,
            payload.center[1],
            payload.center[2],
            payload.start_pos[1],
            payload.start_pos[2],
        )
        return
    end

    if elapsed < second_pass_start
        render_compass_highlight_pass!(
            state_ptr,
            elapsed - first_pass_start,
            pass_duration,
            payload,
            payload.start_pos,
            payload.angle_theta,
        )
        return
    end

    if elapsed < rise_start
        render_compass_highlight_pass!(
            state_ptr,
            elapsed - second_pass_start,
            pass_duration,
            payload,
            payload.end_pos,
            -payload.angle_theta,
        )
        return
    end

    EuclidAnimations.animate_compass_rise(
        state_ptr,
        elapsed - rise_start,
        rise_duration,
        HIGHLIGHT_TOOL_TOP_Z,
        payload.center[1],
        payload.center[2],
        payload.start_pos[1],
        payload.start_pos[2],
    )
end

"""Render one compass highlight pass using filled or unfilled trail styling."""
function render_compass_highlight_pass!(
    state_ptr::Ptr{Cvoid},
    elapsed::Real,
    duration::Real,
    payload::CompassHighlightPayload,
    start_pos::AbstractVector{<:Real},
    angle_theta::Real)

    if payload.filled
        EuclidAnimations.animate_compass_fill_arc_highlight(
            state_ptr,
            elapsed,
            duration,
            payload.center,
            start_pos,
            angle_theta,
            payload.radius,
            payload.color,
        )
        return
    end

    EuclidAnimations.animate_compass_arc_highlight(
        state_ptr,
        elapsed,
        duration,
        payload.center,
        start_pos,
        angle_theta,
        payload.radius,
        payload.color,
    )
end

"""Render one frame of batch point translation."""
function render_transform_spec!(
    state_ptr::Ptr{Cvoid},
    elapsed::Real,
    duration::Real,
    point_id::Int,
    start_position::AbstractVector{<:Real},
    spec::TranslateSpec)

    EuclidAnimations.transform_translate_point(
        state_ptr,
        point_id,
        start_position,
        spec.displacement,
        elapsed,
        duration,
    )
end

"""Render one frame of batch point rotation."""
function render_transform_spec!(
    state_ptr::Ptr{Cvoid},
    elapsed::Real,
    duration::Real,
    point_id::Int,
    start_position::AbstractVector{<:Real},
    spec::RotateSpec)

    EuclidAnimations.transform_rotate_point(
        state_ptr,
        point_id,
        start_position,
        spec.axis_a,
        spec.axis_b,
        spec.theta,
        elapsed,
        duration,
    )
end

"""Render one frame of batch point 2D reflection."""
function render_transform_spec!(
    state_ptr::Ptr{Cvoid},
    elapsed::Real,
    duration::Real,
    point_id::Int,
    start_position::AbstractVector{<:Real},
    spec::Reflect2DSpec)

    EuclidAnimations.transform_reflect2d_point(
        state_ptr,
        point_id,
        start_position,
        spec.line_a,
        spec.line_b,
        elapsed,
        duration,
    )
end

"""Render one frame of the active payload animation at elapsed draw time."""
function render_payload!(state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::TransformPayload)
    for (index, point_id) in pairs(payload.point_ids)
        start_position = payload.start_positions[index]
        render_transform_spec!(
            state_ptr,
            elapsed,
            duration,
            point_id,
            start_position,
            payload.spec,
        )
    end
end

"""Finalize active job visibility and hide the tool used for that job."""
function finalize_job!(state_ptr::Ptr{Cvoid}, job::ReplDrawJob)
    if state_ptr == Ptr{Cvoid}(0)
        return
    end

    finalize_payload!(state_ptr, job.payload)
    if job.kind == :point || job.kind == :line || job.kind == :highlight_pen
        OdinJuliaBridge.hide_pen(state_ptr)
    elseif job.kind == :circle || job.kind == :highlight_compass
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
function run_active_job_frame!(state_ptr::Ptr{Cvoid}, dt::Real)
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

function _hide_bridge_point(state_ptr::Ptr{Cvoid}, id::Integer)
    try
        OdinJuliaBridge.hide_point(state_ptr, Int(id))
    catch err
        message = sprint(showerror, err)
        if occursin("could not load symbol", message) || occursin("undefined symbol", message)
            return nothing
        end
        rethrow(err)
    end
    return nothing
end

"""Hide a REPL-managed geometry target by integer index or bridge shape/view handle."""
function hide!(state_ptr::Ptr{Cvoid}, index::Integer)
    _hide_bridge_point(state_ptr, Int(index))
    return nothing
end

"""Hide a point-view handle by taking its index."""
function hide!(state_ptr::Ptr{Cvoid}, view::OdinJuliaBridge.BridgePointView)
    _hide_bridge_point(state_ptr, Int(view.index))
    return nothing
end

"""Hide a line-shape handle by its host id."""
function hide!(state_ptr::Ptr{Cvoid}, shape::OdinJuliaBridge.BridgeShapeLine)
    _hide_bridge_point(state_ptr, Int(shape.hostId))
    return nothing
end

"""Hide a circle-shape handle by its host id."""
function hide!(state_ptr::Ptr{Cvoid}, shape::OdinJuliaBridge.BridgeShapeCircle)
    _hide_bridge_point(state_ptr, Int(shape.hostId))
    return nothing
end

"""Hide a filled-circle-shape handle by its host id."""
function hide!(state_ptr::Ptr{Cvoid}, shape::OdinJuliaBridge.BridgeShapeFilledCircle)
    _hide_bridge_point(state_ptr, Int(shape.hostId))
    return nothing
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
function point!(state_ptr::Ptr{Cvoid}, pos::AbstractVector{<:Real};
    color=DEFAULT_COLOR, brush::Real=DEFAULT_BRUSH,
    duration::Real=DEFAULT_POINT_DURATION)
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
function line!(state_ptr::Ptr{Cvoid}, start_pos::AbstractVector{<:Real}, end_pos::AbstractVector{<:Real};
    color=DEFAULT_COLOR, brush::Real=DEFAULT_BRUSH,
    duration::Real=DEFAULT_LINE_DURATION)
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
function circle!(state_ptr::Ptr{Cvoid}, center::AbstractVector{<:Real}, radius::Real;
    start_theta::Real=0f0, end_theta::Real=Inf32, filled::Bool=false,
    color=DEFAULT_COLOR, brush::Real=DEFAULT_BRUSH,
    duration::Real=DEFAULT_CIRCLE_DURATION)
    center3 = vec3("center", center)
    brush_value = validated_brush(brush)
    draw_duration = validated_duration(duration)
    start_theta_valid = validated_start_theta(start_theta)
    end_theta_valid = validated_end_theta(end_theta)
    full_sweep = is_full_sweep_request(start_theta_valid, end_theta_valid)
    radius_valid = validated_radius(radius)

    final_end_theta = effective_end_theta(start_theta_valid, end_theta_valid)
    start_pos = point_on_circle(center3, radius_valid, start_theta_valid)
    end_pos = point_on_circle(center3, radius_valid, final_end_theta)
    angle_theta = final_end_theta - start_theta_valid

    shape = if filled
        OdinJuliaBridge.create_new_filledcircle(
            state_ptr,
            center3,
            radius_valid,
            start_theta_valid,
            final_end_theta,
            color,
            brush_value)
    else
        OdinJuliaBridge.create_new_circle(
            state_ptr,
            center3,
            radius_valid,
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
        radius_valid,
        angle_theta,
        color,
        brush_value)

    job = ReplDrawJob(:circle, draw_duration, Float32(0.0), nothing, payload)
    start_job!(state_ptr, job)
    track_managed_host!(ensure_session!(), Int(shape.hostId))
    return shape
end

"""
Highlight one segment with pen motion and a return pass.

Sequence:
- descend at start,
- drag start->end,
- drag end->start,
- rise at start.

Keywords:
- `color=:lightgreen`
- `duration=DEFAULT_HIGHLIGHT_DURATION`
"""
function highlight_pen!(
    state_ptr::Ptr{Cvoid},
    start_pos::AbstractVector{<:Real},
    end_pos::AbstractVector{<:Real};
    color=DEFAULT_HIGHLIGHT_COLOR,
    duration::Real=DEFAULT_HIGHLIGHT_DURATION)

    start_pos3 = vec3("start_pos", start_pos)
    end_pos3 = vec3("end_pos", end_pos)
    draw_duration = validated_duration(duration)

    payload = PenHighlightPayload(start_pos3, end_pos3, color)
    job = ReplDrawJob(:highlight_pen, draw_duration, Float32(0f0), nothing, payload)
    start_job!(state_ptr, job)
    return nothing
end

"""
Highlight one compass arc with a return sweep.

Sequence:
- descend at pivot/start,
- sweep start->end,
- sweep end->start,
- rise at start.

Keywords:
- `color=:lightgreen`
- `filled=false`
- `duration=DEFAULT_HIGHLIGHT_DURATION`
"""
function highlight_compass!(
    state_ptr::Ptr{Cvoid},
    center::AbstractVector{<:Real},
    start_pos::AbstractVector{<:Real},
    angle_theta::Real,
    radius::Real;
    color=DEFAULT_HIGHLIGHT_COLOR,
    filled::Bool=false,
    duration::Real=DEFAULT_HIGHLIGHT_DURATION)

    center3 = vec3("center", center)
    start_pos3 = vec3("start_pos", start_pos)
    angle_theta32 = validated_angle_theta(angle_theta)
    radius32 = validated_radius(radius)
    draw_duration = validated_duration(duration)

    start_theta = theta_from_center(center3, start_pos3)
    start_on_arc = point_on_circle(center3, radius32, start_theta)
    end_on_arc = point_on_circle(center3, radius32, start_theta + angle_theta32)

    payload = CompassHighlightPayload(
        center3,
        start_on_arc,
        end_on_arc,
        angle_theta32,
        radius32,
        color,
        filled,
    )
    job = ReplDrawJob(:highlight_compass, draw_duration, Float32(0f0), nothing, payload)
    start_job!(state_ptr, job)
    return nothing
end

"""
Animate translation of multiple points using per-point start positions.

Keywords:
- `duration=DEFAULT_TRANSFORM_DURATION`
"""
function translate_points!(
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions,
    displacement::AbstractVector{<:Real};
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    ids = validated_point_ids(point_ids)
    starts = validated_start_positions(start_positions)
    validate_transform_batch_lengths(ids, starts)
    displacement3 = vec3("displacement", displacement)
    draw_duration = validated_duration(duration)

    payload = TransformPayload(ids, starts, TranslateSpec(displacement3))
    job = ReplDrawJob(:transform, draw_duration, Float32(0f0), nothing, payload)
    start_job!(state_ptr, job)
    return ids
end

"""
Animate rotation of multiple points around a shared 3D axis line.

Keywords:
- `duration=DEFAULT_TRANSFORM_DURATION`
"""
function rotate_points!(
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions,
    axis_point_a::AbstractVector{<:Real},
    axis_point_b::AbstractVector{<:Real},
    theta::Real;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    ids = validated_point_ids(point_ids)
    starts = validated_start_positions(start_positions)
    validate_transform_batch_lengths(ids, starts)
    axisA = vec3("axis_point_a", axis_point_a)
    axisB = vec3("axis_point_b", axis_point_b)
    draw_duration = validated_duration(duration)

    payload = TransformPayload(
        ids,
        starts,
        RotateSpec(axisA, axisB, Float32(theta)),
    )
    job = ReplDrawJob(:transform, draw_duration, Float32(0f0), nothing, payload)
    start_job!(state_ptr, job)
    return ids
end

"""Rotate points around world X axis through origin."""
function rotate_points_x!(
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions,
    theta::Real;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return rotate_points!(
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 0f0, 0f0],
        theta;
        duration=duration,
    )
end

"""Rotate points around world Y axis through origin."""
function rotate_points_y!(
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions,
    theta::Real;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return rotate_points!(
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[0f0, 1f0, 0f0],
        theta;
        duration=duration,
    )
end

"""Rotate points around world Z axis through origin."""
function rotate_points_z!(
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions,
    theta::Real;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return rotate_points!(
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[0f0, 0f0, 1f0],
        theta;
        duration=duration,
    )
end

"""
Animate 2D reflection of multiple points across one XY line (`z=0`).

Keywords:
- `duration=DEFAULT_TRANSFORM_DURATION`
"""
function reflect2d_points!(
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions,
    line_point_a::AbstractVector{<:Real},
    line_point_b::AbstractVector{<:Real};
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    ids = validated_point_ids(point_ids)
    starts = validated_start_positions(start_positions)
    validate_transform_batch_lengths(ids, starts)
    lineA = vec3("line_point_a", line_point_a)
    lineB = vec3("line_point_b", line_point_b)
    draw_duration = validated_duration(duration)

    payload = TransformPayload(ids, starts, Reflect2DSpec(lineA, lineB))
    job = ReplDrawJob(:transform, draw_duration, Float32(0f0), nothing, payload)
    start_job!(state_ptr, job)
    return ids
end

"""Reflect points across world X axis (`y=0`) on XY plane."""
function reflect2d_points_x_axis!(
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return reflect2d_points!(
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 0f0, 0f0];
        duration=duration,
    )
end

"""Reflect points across world Y axis (`x=0`) on XY plane."""
function reflect2d_points_y_axis!(
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return reflect2d_points!(
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[0f0, 1f0, 0f0];
        duration=duration,
    )
end

"""Reflect points across diagonal `y=x` on XY plane."""
function reflect2d_points_diag_pos!(
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return reflect2d_points!(
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 1f0, 0f0];
        duration=duration,
    )
end

"""Reflect points across diagonal `y=-x` on XY plane."""
function reflect2d_points_diag_neg!(
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return reflect2d_points!(
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, -1f0, 0f0];
        duration=duration,
    )
end

end
