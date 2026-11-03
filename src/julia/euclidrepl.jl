"""
EuclidRepl

REPL-first geometry helpers for interactive point, line, and circle drawing
with tool animation.

Key behavior:
- one active draw job at a time,
- bounded FIFO actions run to natural completion without replacement,
- drawn geometry persists until Terminal session reset/restart.

`status().drained` reports successful command capture, not native publication.
Use ordinary animation pause/resume; the former finish-now `stop!` is removed.

Use `?point!`, `?line!`, and `?circle!` in the Terminal for API details.
"""
module EuclidRepl

using ..OdinJuliaBridge
using ..EuclidAnimations
using Colors: Colorant

export DEFAULT_POINT_DURATION, DEFAULT_LINE_DURATION, DEFAULT_CIRCLE_DURATION,
    DEFAULT_TRANSFORM_DURATION, DEFAULT_HIGHLIGHT_DURATION,
    DEFAULT_COLOR, DEFAULT_HIGHLIGHT_COLOR, DEFAULT_BRUSH,
    euclidcolors, hide!, point!, line!, circle!, highlight_pen!, highlight_compass!,
    translate_points!, rotate_points!, rotate_points_x!, rotate_points_y!,
    rotate_points_z!, reflect2d_points!, reflect2d_points_x_axis!,
    reflect2d_points_y_axis!, reflect2d_points_diag_pos!, reflect2d_points_diag_neg!,
    ACTION_QUEUE_CAPACITY, TRANSFORM_POINT_CAPACITY, clear!, status

const ACTION_QUEUE_CAPACITY = 32
const TRANSFORM_POINT_CAPACITY = 16
"""Native scene-command ceiling from bridge/model/model.odin; a clear emits only hides."""
const CLEAR_COMMAND_CAPACITY = 256

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
    :firebrick)

"""Return the curated Euclid color palette as Julia Colors objects."""
function euclidcolors()
    [parse(Colorant, String(name)) for name in EUCLID_COLORS]
end

abstract type ReplDrawPayload end

struct PointPayload <: ReplDrawPayload
    point_id::UInt64
    pos::Vector{Float32}
    color
    brush::Float32
end

struct LinePayload <: ReplDrawPayload
    host_id::UInt64
    start_id::UInt64
    end_id::UInt64
    start_pos::Vector{Float32}
    end_pos::Vector{Float32}
    color
    brush::Float32
end

struct CirclePayload <: ReplDrawPayload
    filled::Bool
    host_id::UInt64
    center::Vector{Float32}
    start_pos::Vector{Float32}
    radius::Float32
    sweep_theta::Float32
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
    point_ids::Vector{UInt64}
    start_positions::Vector{Vector{Float32}}
    spec::TransformSpec
end

"""Copied visibility intent with bounded per-tick progress for large ordered clears."""
mutable struct VisibilityPayload <: ReplDrawPayload
    host_ids::Vector{UInt64}
    clear::Bool
    next_host::Int
end

"""Start an ordered visibility action at its first copied host."""
function visibility_payload(host_ids, clear)
    return VisibilityPayload(host_ids, clear, 1)
end

"""One admitted action, with activation deferred until its first captured tick."""
mutable struct ReplDrawJob
    kind::Symbol
    duration::Float32
    elapsed::Float32
    payload::ReplDrawPayload
    activated::Bool
end

"""Construct an unactivated action without allocating per-tick state."""
ReplDrawJob(kind, duration, elapsed, payload) =
    ReplDrawJob(kind, duration, elapsed, payload, false)

"""Generation-owned fixed FIFO slots and persistent managed geometry identities."""
mutable struct ReplDrawSession
    active_job::Union{Nothing, ReplDrawJob}
    managed_host_ids::Vector{UInt64}
    pending::Vector{Union{Nothing,ReplDrawJob}}
    pending_head::Int
    pending_count::Int
    completed_count::Int
    failed::Bool
    awaiting_snapshot::Bool
end

"""Generation-local EuclidRepl state owned by one Terminal session."""
mutable struct EuclidReplRuntime
    session::ReplDrawSession
end

"""Create empty EuclidRepl state for one Terminal session generation."""
function create_runtime()
    slots = Vector{Union{Nothing,ReplDrawJob}}(undef, ACTION_QUEUE_CAPACITY)
    fill!(slots, nothing)
    return EuclidReplRuntime(ReplDrawSession(
        nothing, UInt64[], slots, 1, 0, 0, false, false))
end

"""Install user-facing drawing helpers bound to one Terminal generation."""
function install_drawing_helpers!(
    context_module::Module, runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid})::Nothing

    repl_module = EuclidRepl
    Core.eval(context_module, quote
        const EuclidRepl = $repl_module
        const EUCLID_REPL_RUNTIME = $runtime
        const EUCLID_STATE_PTR = $state_ptr
        const state_ptr = $state_ptr
        """Hide one REPL-managed geometry target."""
        hide!(args...; kwargs...) = EuclidRepl.hide!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Return the curated Euclid drawing colors."""
        euclidcolors(args...; kwargs...) = EuclidRepl.euclidcolors(args...; kwargs...)
        """Draw one animated point."""
        point!(args...; kwargs...) = EuclidRepl.point!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Draw one animated line."""
        line!(args...; kwargs...) = EuclidRepl.line!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Draw one animated circle."""
        circle!(args...; kwargs...) = EuclidRepl.circle!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Animate a pen highlight."""
        highlight_pen!(args...; kwargs...) = EuclidRepl.highlight_pen!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Animate a compass highlight."""
        highlight_compass!(args...; kwargs...) = EuclidRepl.highlight_compass!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Queue a clear of geometry admitted before this command."""
        clear!() = EuclidRepl.clear!(EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR)
        """Return Euclid drawing status for this Terminal generation."""
        status() = EuclidRepl.status(EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR)
    end)
    return nothing
end

"""Install user-facing rotation helpers bound to one Terminal generation."""
function install_rotation_helpers!(context_module::Module)::Nothing
    Core.eval(context_module, quote
        """Translate managed points."""
        translate_points!(args...; kwargs...) = EuclidRepl.translate_points!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Rotate managed points about an axis."""
        rotate_points!(args...; kwargs...) = EuclidRepl.rotate_points!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Rotate managed points about the x axis."""
        rotate_points_x!(args...; kwargs...) = EuclidRepl.rotate_points_x!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Rotate managed points about the y axis."""
        rotate_points_y!(args...; kwargs...) = EuclidRepl.rotate_points_y!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Rotate managed points about the z axis."""
        rotate_points_z!(args...; kwargs...) = EuclidRepl.rotate_points_z!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
    end)
    return nothing
end

"""Install user-facing reflection helpers bound to one Terminal generation."""
function install_reflection_helpers!(context_module::Module)::Nothing
    Core.eval(context_module, quote
        """Reflect points across an arbitrary 2D line."""
        reflect2d_points!(args...; kwargs...) = EuclidRepl.reflect2d_points!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Reflect points across the x axis."""
        reflect2d_points_x_axis!(args...; kwargs...) =
            EuclidRepl.reflect2d_points_x_axis!(
                EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Reflect points across the y axis."""
        reflect2d_points_y_axis!(args...; kwargs...) =
            EuclidRepl.reflect2d_points_y_axis!(
                EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Reflect points across the positive diagonal."""
        reflect2d_points_diag_pos!(args...; kwargs...) =
            EuclidRepl.reflect2d_points_diag_pos!(
                EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Reflect points across the negative diagonal."""
        reflect2d_points_diag_neg!(args...; kwargs...) =
            EuclidRepl.reflect2d_points_diag_neg!(
                EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
    end)
    return nothing
end

"""Install user-facing transform helpers bound to one Terminal generation."""
function install_transform_helpers!(context_module::Module)::Nothing
    install_rotation_helpers!(context_module)
    install_reflection_helpers!(context_module)
    return nothing
end

"""Install user-facing geometry helpers bound to one Terminal generation."""
function install_session_helpers!(
    context_module::Module, runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid})::Nothing

    install_drawing_helpers!(context_module, runtime, state_ptr)
    install_transform_helpers!(context_module)
    return nothing
end

struct ReplStatus
    active::Bool
    kind::Union{Nothing,Symbol}
    elapsed::Union{Nothing,Float32}
    duration::Union{Nothing,Float32}
    subscription_id::Union{Nothing,Int}
    managed_shape_count::Int
    pending_count::Int
    completed_count::Int
    failed::Bool
    drained::Bool
end

"""Return the Terminal-generation-owned EuclidRepl session."""
ensure_session!(runtime::EuclidReplRuntime) = runtime.session

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

"""Return validated non-empty point ids as packed `UInt64` entities."""
function validated_point_ids(point_ids)
    ids = UInt64[UInt64(id) for id in point_ids]
    if isempty(ids)
        throw(ArgumentError("point_ids must contain at least one id"))
    end
    length(ids) <= TRANSFORM_POINT_CAPACITY ||
        throw(ArgumentError("point batch exceeds TRANSFORM_POINT_CAPACITY"))
    allunique(ids) || throw(ArgumentError("point_ids must be distinct"))
    return ids
end

"""Return validated start positions, one 3D position per point id."""
function validated_start_positions(start_positions)
    positions = Vector{Vector{Float32}}()

    # Accept flat xyz-packed input (e.g. [x1, y1, z1, x2, y2, z2]) for convenience.
    if start_positions isa AbstractVector{<:Real}
        length(start_positions) <= 3 * TRANSFORM_POINT_CAPACITY ||
            throw(ArgumentError("start_positions exceeds TRANSFORM_POINT_CAPACITY"))
        if length(start_positions) % 3 != 0
            throw(ArgumentError(
                "flat start_positions must contain a multiple of 3 values (x, y, z per point)"))
        end

        point_count = Int(length(start_positions) ÷ 3)
        for idx in 1:point_count
            base = (idx - 1) * 3
            push!(positions, vec3("start_positions[$(idx)]", @view start_positions[(base + 1):(base + 3)]))
        end
        return positions
    end

    for (idx, pos) in enumerate(start_positions)
        idx <= TRANSFORM_POINT_CAPACITY ||
            throw(ArgumentError("start_positions exceeds TRANSFORM_POINT_CAPACITY"))
        push!(positions, vec3("start_positions[$(idx)]", pos))
    end
    return positions
end

"""Validate matching lengths for point ids and start positions."""
function validate_transform_batch_lengths(
    point_ids::Vector{UInt64}, start_positions::Vector{Vector{Float32}})

    if length(point_ids) != length(start_positions)
        throw(ArgumentError("point_ids and start_positions must have equal length"))
    end
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
    start_theta = theta_from_center(payload.center, payload.start_pos)
    OdinJuliaBridge.set_arc_geometry(state_ptr, payload.host_id,
        payload.radius, start_theta, payload.sweep_theta)
    OdinJuliaBridge.show_point(state_ptr, payload.host_id)
end

"""Apply final visible state for a transform payload at completed progress."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::TransformPayload)
    for (index, point_id) in pairs(payload.point_ids)
        start_position = payload.start_positions[index]
        render_transform_spec!(state_ptr, 1f0, 1f0, point_id,
            start_position, payload.spec)
    end
end

"""Render one frame of the active payload animation at elapsed draw time."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::PointPayload)
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
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::LinePayload)
    EuclidAnimations.animate_repl_draw_line(
        state_ptr,
        Float32(elapsed),
        Float32(duration),
        payload.start_pos,
        payload.end_pos;
        penbrush=payload.brush,
        pencolor=payload.color,
        line_host_id=payload.host_id,
        line_joint1_id=payload.start_id,
        line_joint2_id=payload.end_id)
end

"""Render one frame of the active payload animation at elapsed draw time."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::CirclePayload)
    if payload.filled
        EuclidAnimations.animate_repl_draw_filledcircle(
            state_ptr,
            Float32(elapsed),
            Float32(duration),
            payload.center,
            payload.start_pos,
            payload.sweep_theta,
            payload.radius;
            brush=payload.brush,
            color=payload.color,
            marker_host_id=payload.host_id)
    else
        EuclidAnimations.animate_repl_draw_circle(
            state_ptr,
            Float32(elapsed),
            Float32(duration),
            payload.center,
            payload.start_pos,
            payload.sweep_theta,
            payload.radius;
            brush=payload.brush,
            color=payload.color,
            marker_host_id=payload.host_id)
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
        EuclidAnimations.animate_pen_descend(state_ptr, elapsed, descend_duration,
            HIGHLIGHT_TOOL_TOP_Z, payload.start_pos[1], payload.start_pos[2])
        return
    end

    if elapsed < second_pass_start
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, elapsed - first_pass_start,
            pass_duration, payload.start_pos, payload.end_pos, payload.color)
        return
    end

    if elapsed < rise_start
        EuclidAnimations.animate_pen_tilt_and_drag(state_ptr, elapsed - second_pass_start,
            pass_duration, payload.end_pos, payload.start_pos, payload.color)
        return
    end

    EuclidAnimations.animate_pen_rise(state_ptr, elapsed - rise_start,
        rise_duration, HIGHLIGHT_TOOL_TOP_Z, payload.start_pos[1], payload.start_pos[2])
end

"""Render one frame of compass highlight with descend-pass-pass-rise sequencing."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real,
    duration::Real, payload::CompassHighlightPayload)

    descend_duration = duration * HIGHLIGHT_DESCEND_SHARE
    pass_duration = duration * HIGHLIGHT_PASS_SHARE
    first_pass_start = descend_duration
    second_pass_start = first_pass_start + pass_duration
    rise_start = second_pass_start + pass_duration
    rise_duration = max(duration - rise_start, 1f-5)

    if elapsed < first_pass_start
        EuclidAnimations.animate_compass_descend(state_ptr, elapsed, descend_duration,
            HIGHLIGHT_TOOL_TOP_Z, payload.center[1], payload.center[2],
            payload.start_pos[1], payload.start_pos[2])
        return
    end

    if elapsed < second_pass_start
        render_compass_highlight_pass!(state_ptr, elapsed - first_pass_start,
            pass_duration, payload, payload.start_pos, payload.angle_theta)
        return
    end

    if elapsed < rise_start
        render_compass_highlight_pass!(state_ptr, elapsed - second_pass_start,
            pass_duration, payload, payload.end_pos, -payload.angle_theta)
        return
    end

    EuclidAnimations.animate_compass_rise(state_ptr, elapsed - rise_start,
        rise_duration, HIGHLIGHT_TOOL_TOP_Z, payload.center[1], payload.center[2],
        payload.start_pos[1], payload.start_pos[2])
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
        EuclidAnimations.animate_compass_fill_arc_highlight(state_ptr, elapsed, duration,
            payload.center, start_pos, angle_theta, payload.radius, payload.color)
        return
    end

    EuclidAnimations.animate_compass_arc_highlight(state_ptr, elapsed, duration,
        payload.center, start_pos, angle_theta, payload.radius, payload.color)
end

"""Render one frame of batch point translation."""
function render_transform_spec!(
    state_ptr::Ptr{Cvoid},
    elapsed::Real,
    duration::Real,
    point_id::UInt64,
    start_position::AbstractVector{<:Real},
    spec::TranslateSpec)

    result = EuclidAnimations.transform_translate_point(
        state_ptr,
        point_id,
        start_position,
        spec.displacement,
        elapsed,
        duration)
    result == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        error("Terminal translation failed with status $result")
end

"""Render one frame of batch point rotation."""
function render_transform_spec!(
    state_ptr::Ptr{Cvoid},
    elapsed::Real,
    duration::Real,
    point_id::UInt64,
    start_position::AbstractVector{<:Real},
    spec::RotateSpec)

    result = EuclidAnimations.transform_rotate_point(
        state_ptr,
        point_id,
        start_position,
        spec.axis_a,
        spec.axis_b,
        spec.theta,
        elapsed,
        duration)
    result == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        error("Terminal rotation failed with status $result")
end

"""Render one frame of batch point 2D reflection."""
function render_transform_spec!(
    state_ptr::Ptr{Cvoid},
    elapsed::Real,
    duration::Real,
    point_id::UInt64,
    start_position::AbstractVector{<:Real},
    spec::Reflect2DSpec)

    result = EuclidAnimations.transform_reflect2d_point(
        state_ptr,
        point_id,
        start_position,
        spec.line_a,
        spec.line_b,
        elapsed,
        duration)
    result == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        error("Terminal reflection failed with status $result")
end

"""Render one frame of the active payload animation at elapsed draw time."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::TransformPayload)
    for (index, point_id) in pairs(payload.point_ids)
        start_position = payload.start_positions[index]
        render_transform_spec!(
            state_ptr,
            elapsed,
            duration,
            point_id,
            start_position,
            payload.spec)
    end
end

"""Finalize active job visibility and hide the tool used for that job."""
function finalize_job!(state_ptr::Ptr{Cvoid}, job::ReplDrawJob)
    if state_ptr == Ptr{Cvoid}(0)
        return
    end

    finalize_payload!(state_ptr, job.payload)
    retire_job_tool!(state_ptr, job)
end

"""Retire the active apparatus without completing interrupted geometry."""
function retire_job_tool!(state_ptr::Ptr{Cvoid}, job::ReplDrawJob)
    state_ptr == C_NULL && return nothing
    if job.kind == :point || job.kind == :line || job.kind == :highlight_pen
        OdinJuliaBridge.hide_pen(state_ptr)
    elseif job.kind == :circle || job.kind == :highlight_compass
        OdinJuliaBridge.hide_compass(state_ptr)
    end
end

"""Highlights leave no persistent shape to finalize."""
finalize_payload!(
    _::Ptr{Cvoid}, _::Union{PenHighlightPayload,CompassHighlightPayload}) =
    nothing

"""Visibility has already been emitted by its bounded execution frames."""
finalize_payload!(_::Ptr{Cvoid}, _::VisibilityPayload) = nothing

"""Emit ordered hiding, retaining identities admitted after an ordered clear."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, _::Real, _::Real, payload::VisibilityPayload)
    last_host = min(length(payload.host_ids),
        payload.next_host + CLEAR_COMMAND_CAPACITY - 1)
    for index in payload.next_host:last_host
        id = payload.host_ids[index]
        OdinJuliaBridge.hide_point(state_ptr, id) == OdinJuliaBridge.BRIDGE_STATUS_OK ||
            error("Terminal visibility execution failed for entity $id")
    end
    payload.next_host = last_host + 1
    return nothing
end

"""Validate a target against the bridge's current immutable projection."""
function validated_target(state_ptr::Ptr{Cvoid}, id::UInt64)
    view = OdinJuliaBridge.get_point(state_ptr, id)
    view.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        throw(ArgumentError("invalid or stale Terminal entity $id"))
    return view
end

"""Recognize transform identities reserved by a queued construction."""
construction_target(payload::PointPayload, id::UInt64) = payload.point_id == id
construction_target(payload::LinePayload, id::UInt64) =
    id == payload.host_id || id == payload.start_id || id == payload.end_id
construction_target(payload::CirclePayload, id::UInt64) = payload.host_id == id
construction_target(::ReplDrawPayload, ::UInt64) = false

"""Recognize admitted native reservations that may not exist in this tick's older snapshot."""
function queued_construction_target(session::ReplDrawSession, id::UInt64)::Bool
    job = session.active_job
    if job !== nothing && construction_target(job.payload, id)
        return true
    end
    for offset in 0:(session.pending_count - 1)
        index = mod1(session.pending_head + offset, ACTION_QUEUE_CAPACITY)
        job = session.pending[index]
        if job !== nothing && construction_target(job.payload, id)
            return true
        end
    end
    return false
end

"""Validate snapshot targets or successful queued reservations; activation revalidates both."""
function validate_transform_targets(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, ids::Vector{UInt64})
    for id in ids
        queued_construction_target(runtime.session, id) && continue
        validated_target(state_ptr, id).has_position != 0 ||
            throw(ArgumentError("Terminal motion target $id has no position"))
    end
end

"""Revalidate native targets and sample motion starts once, at activation."""
function activate_payload!(state_ptr::Ptr{Cvoid}, payload::TransformPayload)
    for (index, id) in pairs(payload.point_ids)
        view = validated_target(state_ptr, id)
        view.has_position != 0 || error("Terminal motion target $id lost its position")
        for component in 1:3
            payload.start_positions[index][component] = view.pos[component]
        end
    end
end

"""Revalidate a construction host immediately before its first frame."""
activate_payload!(state_ptr::Ptr{Cvoid}, payload::PointPayload) =
    validated_target(state_ptr, payload.point_id)
activate_payload!(state_ptr::Ptr{Cvoid}, payload::Union{LinePayload,CirclePayload}) =
    validated_target(state_ptr, payload.host_id)

"""Revalidate every visibility target before emitting any commands."""
function activate_payload!(state_ptr::Ptr{Cvoid}, payload::VisibilityPayload)
    for id in payload.host_ids
        validated_target(state_ptr, id)
    end
end

"""Payloads without native identities need no activation query."""
activate_payload!(::Ptr{Cvoid}, _::ReplDrawPayload) = nothing

"""Clear the generation-local job without changing managed geometry."""
function clear_active_job!(
    runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    session::ReplDrawSession)

    job = session.active_job
    if job === nothing
        return
    end

    session.active_job = nothing
end

"""Track a host point id as managed EuclidRepl geometry."""
function track_managed_host!(session::ReplDrawSession, host_id::UInt64)
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

"""Advance one draw job inside the native animation tick's scene-command capture."""
function run_active_job_frame!(
    runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    dt::Real)

    session = ensure_session!(runtime)
    session.failed && return nothing
    if session.awaiting_snapshot
        session.awaiting_snapshot = false
        return nothing
    end
    job = session.active_job
    if job === nothing
        session.pending_count == 0 && return nothing
        job = session.pending[session.pending_head]
        session.pending[session.pending_head] = nothing
        session.pending_head = mod1(session.pending_head + 1, ACTION_QUEUE_CAPACITY)
        session.pending_count -= 1
        session.active_job = job
    end

    succeeded = false
    try
        execute_job_frame!(state_ptr, session, job, dt)
        succeeded = true
    finally
        if !succeeded
            session.failed = true
        end
    end
end

"""Advance one action; completion means capture succeeded, not native publication."""
function execute_job_frame!(
    state_ptr::Ptr{Cvoid}, session::ReplDrawSession, job::ReplDrawJob, dt::Real)
    if !job.activated
        activate_payload!(state_ptr, job.payload)
        job.activated = true
    end
    job.elapsed = min(job.duration, job.elapsed + max(0f0, Float32(dt)))
    render_payload!(state_ptr, job.elapsed, job.duration, job.payload)
    visibility_complete = !(job.payload isa VisibilityPayload) ||
        job.payload.next_host > length(job.payload.host_ids)
    if job.elapsed >= job.duration && visibility_complete
        finalize_job!(state_ptr, job)
        if job.payload isa VisibilityPayload && job.payload.clear
            filter!(id -> !(id in job.payload.host_ids), session.managed_host_ids)
        end
        session.completed_count += 1
        session.active_job = nothing
    end
end

"""Reject overflow or a failed generation before reserving native identities."""
function require_action_capacity(session::ReplDrawSession)
    session.failed && error("Terminal action execution failed; reset the Terminal")
    outstanding = session.pending_count + Int(session.active_job !== nothing)
    outstanding < ACTION_QUEUE_CAPACITY ||
        throw(ArgumentError("Terminal action queue is full (capacity $ACTION_QUEUE_CAPACITY)"))
end

"""Append without changing earlier work; the next action starts on a later tick."""
function start_job!(
    runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    job::ReplDrawJob)

    session = ensure_session!(runtime)

    require_action_capacity(session)
    if session.active_job === nothing && session.pending_count == 0
        session.active_job = job
        session.awaiting_snapshot = true
    else
        index = mod1(session.pending_head + session.pending_count, ACTION_QUEUE_CAPACITY)
        session.pending[index] = job
        session.pending_count += 1
    end
end

"""Stop animation and clear managed state before a Terminal session closes."""
function reset_session!(runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid})
    session = ensure_session!(runtime)
    session.active_job === nothing || retire_job_tool!(state_ptr, session.active_job)
    clear_active_job!(runtime, state_ptr, session)
    fill!(session.pending, nothing)
    session.pending_head = 1
    session.pending_count = 0
    session.completed_count = 0
    session.failed = false
    session.awaiting_snapshot = false
    clear_managed_geometry!(state_ptr, session)
    return nothing
end

"""
Queue a clear of geometry admitted before this command, without interrupting actions.

Returns `true` when admitted. Large clears use the native 256-command tick capacity.
"""
function clear!(
    host_runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid})

    session = ensure_session!(host_runtime)
    require_action_capacity(session)
    payload = visibility_payload(copy(session.managed_host_ids), true)
    start_job!(host_runtime, state_ptr, ReplDrawJob(:clear, eps(Float32), 0f0, payload))
    return true
end

"""Queue hiding a valid managed host without interrupting accepted work."""
function _hide_bridge_point(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, id::UInt64)
    session = ensure_session!(runtime)
    require_action_capacity(session)
    id in session.managed_host_ids ||
        throw(ArgumentError("hide! requires a Terminal-managed geometry host"))
    queued_construction_target(session, id) || validated_target(state_ptr, id)
    payload = visibility_payload(UInt64[id], false)
    start_job!(runtime, state_ptr, ReplDrawJob(:hide, eps(Float32), 0f0, payload))
    return nothing
end

"""Hide a REPL-managed geometry target by integer index or bridge entity/view handle."""
function hide!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    index::Integer)

    _ = host_runtime
    _hide_bridge_point(host_runtime, state_ptr, UInt64(index))
    return nothing
end

"""Hide a standalone entity returned by `point!` using its packed index."""
function hide!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    point::OdinJuliaBridge.BridgeShapeEntityResult)

    _ = host_runtime
    _hide_bridge_point(host_runtime, state_ptr, point.index)
    return nothing
end

function hide!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    view::OdinJuliaBridge.BridgePointView)

    _ = host_runtime
    _hide_bridge_point(host_runtime, state_ptr, view.index)
    return nothing
end
function hide!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    shape::OdinJuliaBridge.BridgeShapeLine)

    _ = host_runtime
    _hide_bridge_point(host_runtime, state_ptr, shape.host_id)
    return nothing
end
function hide!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    shape::OdinJuliaBridge.BridgeShapeCircle)

    _ = host_runtime
    _hide_bridge_point(host_runtime, state_ptr, shape.host_id)
    return nothing
end
function hide!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    shape::OdinJuliaBridge.BridgeShapeFilledCircle)

    _ = host_runtime
    _hide_bridge_point(host_runtime, state_ptr, shape.host_id)
    return nothing
end

"""Inspect FIFO capture progress; `drained` excludes failed or pending work, not native rejection."""
function status(
    host_runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid})

    _ = state_ptr
    session = ensure_session!(host_runtime)
    job = session.active_job

    if job === nothing
        return ReplStatus(
            false,
            nothing,
            nothing,
            nothing,
            nothing,
            length(session.managed_host_ids),
            session.pending_count, session.completed_count, session.failed,
            session.pending_count == 0 && !session.failed)
    end

    return ReplStatus(
        true,
        job.kind,
        job.elapsed,
        job.duration,
        nothing,
        length(session.managed_host_ids),
        session.pending_count, session.completed_count, session.failed, false)
end

"""
Draw a point with pen animation and return a `BridgeShapeEntityResult` handle.

Append to the bounded FIFO without interrupting earlier actions. The reserved
host remains hidden until activation; duration includes descent, drawing, and ascent.
Pass the returned handle to `hide!` to hide the completed point.

Keywords:
- `color=:steelblue`
- `brush=5f0`
- `duration=DEFAULT_POINT_DURATION` (full tool sequence)
"""
function point!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    pos::AbstractVector{<:Real};
    color=DEFAULT_COLOR, brush::Real=DEFAULT_BRUSH,
    duration::Real=DEFAULT_POINT_DURATION)
    pos3 = vec3("pos", pos)
    brush_value = validated_brush(brush)
    draw_duration = validated_duration(duration)

    color = OdinJuliaBridge._shape_color(color)
    require_action_capacity(ensure_session!(host_runtime))
    point = OdinJuliaBridge.create_new_point(state_ptr, pos3, color, brush_value)
    point.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        error("Terminal point reservation failed with status $(point.status)")
    payload = PointPayload(point.index, pos3, color, brush_value)
    job = ReplDrawJob(:point, draw_duration, Float32(0f0), payload)

    start_job!(host_runtime, state_ptr, job)
    track_managed_host!(ensure_session!(host_runtime), point.index)
    return point
end

"""
Draw a line with pen animation and return a `BridgeShapeLine` handle.

Append to the bounded FIFO; the reserved host is hidden until its action runs.
Keywords:
- `color=:steelblue`
- `brush=5f0`
- `duration=DEFAULT_LINE_DURATION` (full tool sequence)
"""
function line!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    start_pos::AbstractVector{<:Real}, end_pos::AbstractVector{<:Real};
    color=DEFAULT_COLOR, brush::Real=DEFAULT_BRUSH,
    duration::Real=DEFAULT_LINE_DURATION)
    start_pos3 = vec3("start_pos", start_pos)
    end_pos3 = vec3("end_pos", end_pos)
    brush_value = validated_brush(brush)
    draw_duration = validated_duration(duration)

    color = OdinJuliaBridge._shape_color(color)
    require_action_capacity(ensure_session!(host_runtime))
    line_shape = OdinJuliaBridge.create_new_line(
        state_ptr,
        start_pos3,
        start_pos3,
        color, brush_value)
    line_shape.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        error("Terminal line reservation failed with status $(line_shape.status)")

    payload = LinePayload(
        line_shape.host_id,
        line_shape.joint1_id,
        line_shape.joint2_id,
        start_pos3,
        end_pos3,
        color,
        brush_value)

    job = ReplDrawJob(:line, draw_duration, Float32(0f0), payload)
    start_job!(host_runtime, state_ptr, job)
    track_managed_host!(ensure_session!(host_runtime), line_shape.host_id)
    return line_shape
end

"""
Draw a circle, arc, or sector with compass animation and return a circle handle.

Append to the bounded FIFO; the reserved host is hidden until its action runs.
Keywords:
- `start_theta=0f0`
- `sweep_theta=2pi`
- `filled=false`
- `color=:steelblue`
- `brush=5f0`
- `duration=DEFAULT_CIRCLE_DURATION` (full tool sequence)

Positive sweeps increase theta and negative sweeps decrease theta. Full turns are
represented explicitly by positive or negative `2pi` sweeps.
"""
function circle!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid}, center::AbstractVector{<:Real}, radius::Real;
    start_theta::Real=0f0, sweep_theta::Real=TWO_PI_F32, filled::Bool=false,
    color=DEFAULT_COLOR, brush::Real=DEFAULT_BRUSH,
    duration::Real=DEFAULT_CIRCLE_DURATION)
    center3 = vec3("center", center)
    brush_value = validated_brush(brush)
    draw_duration = validated_duration(duration)
    start_theta_valid = validated_start_theta(start_theta)
    sweep_theta_valid = validated_start_theta(sweep_theta)
    radius_valid = validated_radius(radius)

    start_pos = point_on_circle(center3, radius_valid, start_theta_valid)

    color = OdinJuliaBridge._shape_color(color)
    require_action_capacity(ensure_session!(host_runtime))
    shape = if filled
        OdinJuliaBridge.create_new_filledcircle(state_ptr, center3, radius_valid,
            start_theta_valid, sweep_theta_valid, color, brush_value)
    else
        OdinJuliaBridge.create_new_circle(state_ptr, center3, radius_valid,
            start_theta_valid, sweep_theta_valid, color, brush_value)
    end

    shape.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        error("Terminal circle reservation failed with status $(shape.status)")
    payload = CirclePayload(filled, shape.host_id, center3, start_pos,
        radius_valid, sweep_theta_valid,
        color, brush_value)

    job = ReplDrawJob(:circle, draw_duration, Float32(0.0), payload)
    start_job!(host_runtime, state_ptr, job)
    track_managed_host!(ensure_session!(host_runtime), shape.host_id)
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
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    start_pos::AbstractVector{<:Real},
    end_pos::AbstractVector{<:Real};
    color=DEFAULT_HIGHLIGHT_COLOR,
    duration::Real=DEFAULT_HIGHLIGHT_DURATION)

    start_pos3 = vec3("start_pos", start_pos)
    end_pos3 = vec3("end_pos", end_pos)
    draw_duration = validated_duration(duration)

    payload = PenHighlightPayload(
        start_pos3, end_pos3, OdinJuliaBridge._shape_color(color))
    job = ReplDrawJob(:highlight_pen, draw_duration, Float32(0f0), payload)
    start_job!(host_runtime, state_ptr, job)
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
    host_runtime::EuclidReplRuntime,
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
        OdinJuliaBridge._shape_color(color),
        filled)
    job = ReplDrawJob(:highlight_compass, draw_duration, Float32(0f0), payload)
    start_job!(host_runtime, state_ptr, job)
    return nothing
end

"""
Queue translation of at most 16 distinct points from their activation-time positions.

`start_positions` is copied and validated for compatibility, but actual starts
are sampled after preceding actions finish. Returned IDs do not alias queued inputs.

Keywords:
- `duration=DEFAULT_TRANSFORM_DURATION`
"""
function translate_points!(
    host_runtime::EuclidReplRuntime,
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
    validate_transform_targets(host_runtime, state_ptr, ids)

    payload = TransformPayload(ids, starts, TranslateSpec(displacement3))
    job = ReplDrawJob(:transform, draw_duration, Float32(0f0), payload)
    start_job!(host_runtime, state_ptr, job)
    return copy(ids)
end

"""
Animate rotation of multiple points around a shared 3D axis line.

Queue at most 16 distinct targets. `start_positions` remains validated for
compatibility; actual starts are sampled at activation, not submission.
Keywords:
- `duration=DEFAULT_TRANSFORM_DURATION`
"""
function rotate_points!(
    host_runtime::EuclidReplRuntime,
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
    axis_a = vec3("axis_point_a", axis_point_a)
    axis_b = vec3("axis_point_b", axis_point_b)
    draw_duration = validated_duration(duration)
    theta32 = validated_angle_theta(theta)
    sum(abs2, axis_b - axis_a) > EuclidAnimations.TransformEps^2 ||
        throw(ArgumentError("rotation axis must have distinct endpoints"))
    validate_transform_targets(host_runtime, state_ptr, ids)

    payload = TransformPayload(
        ids,
        starts,
        RotateSpec(axis_a, axis_b, theta32))
    job = ReplDrawJob(:transform, draw_duration, Float32(0f0), payload)
    start_job!(host_runtime, state_ptr, job)
    return copy(ids)
end

"""Rotate points around world X axis through origin."""
function rotate_points_x!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions,
    theta::Real;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return rotate_points!(
        host_runtime,
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 0f0, 0f0],
        theta;
        duration=duration)
end

"""Rotate points around world Y axis through origin."""
function rotate_points_y!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions,
    theta::Real;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return rotate_points!(
        host_runtime,
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[0f0, 1f0, 0f0],
        theta;
        duration=duration)
end

"""Rotate points around world Z axis through origin."""
function rotate_points_z!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions,
    theta::Real;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return rotate_points!(
        host_runtime,
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[0f0, 0f0, 1f0],
        theta;
        duration=duration)
end

"""
Animate 2D reflection of multiple points across one XY line (`z=0`).

Queue at most 16 distinct targets, sampling their starts at activation.
`start_positions` remains accepted and validated for signature compatibility.
Keywords:
- `duration=DEFAULT_TRANSFORM_DURATION`
"""
function reflect2d_points!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions,
    line_point_a::AbstractVector{<:Real},
    line_point_b::AbstractVector{<:Real};
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    ids = validated_point_ids(point_ids)
    starts = validated_start_positions(start_positions)
    validate_transform_batch_lengths(ids, starts)
    line_a = vec3("line_point_a", line_point_a)
    line_b = vec3("line_point_b", line_point_b)
    draw_duration = validated_duration(duration)
    abs(line_a[3]) <= EuclidAnimations.TransformEps &&
        abs(line_b[3]) <= EuclidAnimations.TransformEps ||
        throw(ArgumentError("reflection line must lie in the XY plane"))
    sum(abs2, line_b[1:2] - line_a[1:2]) > EuclidAnimations.TransformEps^2 ||
        throw(ArgumentError("reflection line must have distinct XY endpoints"))
    validate_transform_targets(host_runtime, state_ptr, ids)

    payload = TransformPayload(ids, starts, Reflect2DSpec(line_a, line_b))
    job = ReplDrawJob(:transform, draw_duration, Float32(0f0), payload)
    start_job!(host_runtime, state_ptr, job)
    return copy(ids)
end

"""Reflect points across world X axis (`y=0`) on XY plane."""
function reflect2d_points_x_axis!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return reflect2d_points!(
        host_runtime,
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 0f0, 0f0];
        duration=duration)
end

"""Reflect points across world Y axis (`x=0`) on XY plane."""
function reflect2d_points_y_axis!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return reflect2d_points!(
        host_runtime,
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[0f0, 1f0, 0f0];
        duration=duration)
end

"""Reflect points across diagonal `y=x` on XY plane."""
function reflect2d_points_diag_pos!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return reflect2d_points!(
        host_runtime,
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 1f0, 0f0];
        duration=duration)
end

"""Reflect points across diagonal `y=-x` on XY plane."""
function reflect2d_points_diag_neg!(
    host_runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid},
    point_ids,
    start_positions;
    duration::Real=DEFAULT_TRANSFORM_DURATION)

    return reflect2d_points!(
        host_runtime,
        state_ptr,
        point_ids,
        start_positions,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, -1f0, 0f0];
        duration=duration)
end

end
