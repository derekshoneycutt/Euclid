"""
EuclidRepl

REPL-first typed geometry constructors, tool choreography, and queued motion.

Key behavior:
- one active draw job at a time,
- bounded FIFO actions run to natural completion without replacement,
- drawn geometry persists until Terminal session reset/restart.

`status().drained` reports successful command capture, not native publication.
Use ordinary animation pause/resume; the former finish-now `stop!` is removed.

Use `?point!`, `?line!`, `?circle!`, `?label!`, `?triangle!`, `?cycloid!`,
`?trochoid!`, `?parabola!`, `?hyperbola!`, and `?rotate_z!` in the Terminal
for API details. See TerminalArchitecture.md for the supported shape and motion
boundary.
"""
module EuclidRepl

using ..OdinJuliaBridge
using ..EuclidAnimations
using Colors: Colorant

export DEFAULT_POINT_DURATION, DEFAULT_LINE_DURATION, DEFAULT_CIRCLE_DURATION,
    DEFAULT_LABEL_DURATION, DEFAULT_REGION_DURATION, DEFAULT_POLYGON_DURATION,
    DEFAULT_CURVE_DURATION,
    DEFAULT_TRANSFORM_DURATION, DEFAULT_HIGHLIGHT_DURATION,
    DEFAULT_COLOR, DEFAULT_HIGHLIGHT_COLOR, DEFAULT_BRUSH,
    euclidcolors, hide!, point!, line!, circle!, label!, triangle!, square!,
    pentagon!, lens!, lune!, polygon_vertex_ids, line_endpoint_ids,
    circle_region_center_ids, cycloid!, ordinary_cycloid!,
    curtate_cycloid!, prolate_cycloid!, trochoid!, ellipse!, cardioid!,
    limacon!, convex_limacon!, dimpled_limacon!, epitrochoid!, hypotrochoid!,
    hypocycloid!, deltoid!, astroid!, five_hypocycloid!,
    eleven_half_hypocycloid!, nephroid!, three_dimple_epitrochoid!,
    five_point_hypotrochoid!, parabola!, hyperbola!, rotate_z!,
    highlight_pen!, highlight_compass!,
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
const DEFAULT_LABEL_DURATION = DEFAULT_HIGHLIGHT_DURATION
const DEFAULT_REGION_DURATION = DEFAULT_HIGHLIGHT_DURATION
const DEFAULT_POLYGON_DURATION = DEFAULT_LINE_DURATION
const DEFAULT_CURVE_DURATION = DEFAULT_CIRCLE_DURATION
const DEFAULT_COLOR = :steelblue
const DEFAULT_HIGHLIGHT_COLOR = :lightgreen
const DEFAULT_BRUSH = 5f0
const HIGHLIGHT_TOOL_TOP_Z = 1.4f0
const HIGHLIGHT_DESCEND_SHARE = 0.2f0
const HIGHLIGHT_PASS_SHARE = 0.3f0
const CURVE_TOOL_TOP_Z = 1.4f0

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

struct LabelPayload <: ReplDrawPayload
    host_id::UInt64
    reveal_duration::Float32
end

struct RegionPayload <: ReplDrawPayload
    host_id::UInt64
    center_ids::NTuple{2,UInt64}
    reveal_duration::Float32
end

mutable struct PolygonPayload <: ReplDrawPayload
    host_id::UInt64
    vertex_ids::Vector{UInt64}
    vertices::Vector{Vector{Float32}}
    color
    reveal_started::Bool
end

struct CycloidPayload <: ReplDrawPayload
    host_id::UInt64
    endpoint_ids::NTuple{2,UInt64}
    first::Vector{Float32}
    second::Vector{Float32}
    rolling_radius::Float32
    tracer_distance::Float32
    tracer_phase::Float32
    parameter_start::Float32
    parameter_finish::Float32
    draw_parameter::Float32
    color
    brush::Float32
end

struct TrochoidPayload <: ReplDrawPayload
    host_id::UInt64
    center::Vector{Float32}
    mode::Int32
    fixed_radius::Float32
    rolling_radius::Float32
    tracer_distance::Float32
    tracer_phase::Float32
    rotation::Float32
    parameter_start::Float32
    parameter_finish::Float32
    draw_parameter::Float32
    color
    brush::Float32
end

struct ParabolaPayload <: ReplDrawPayload
    host_id::UInt64
    vertex::Vector{Float32}
    focal_distance::Float32
    rotation::Float32
    parameter_start::Float32
    parameter_finish::Float32
    draw_parameter::Float32
    link_length::Float32
    color
    brush::Float32
end

struct HyperbolaPayload <: ReplDrawPayload
    host_id::UInt64
    center::Vector{Float32}
    semimajor::Float32
    semiminor::Float32
    rotation::Float32
    parameter_start::Float32
    parameter_finish::Float32
    draw_parameter::Float32
    rail_half_length::Float32
    branches::Symbol
    color
    brush::Float32
end

mutable struct AnalyticRotationPayload <: ReplDrawPayload
    kind::Symbol
    host_id::UInt64
    pivot::Vector{Float32}
    theta::Float32
    center::Vector{Float32}
    geometry::Union{
        Nothing,
        OdinJuliaBridge.BridgeArcGeometry,
        OdinJuliaBridge.BridgeTrochoidGeometry,
        OdinJuliaBridge.BridgeParabolaGeometry,
        OdinJuliaBridge.BridgeHyperbolaGeometry}
end

"""Commit an analytic rotation at its exact requested endpoint."""
finalize_payload!(
    state_ptr::Ptr{Cvoid}, payload::AnalyticRotationPayload) =
    render_payload!(state_ptr, 1f0, 1f0, payload)

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

"""Install shared bindings for one generation's fresh Terminal module."""
function install_repl_bindings!(
    context_module::Module, runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid})
    repl_module = EuclidRepl
    Core.eval(context_module, quote
        const EuclidRepl = $repl_module
        const OdinJuliaBridge = EuclidRepl.OdinJuliaBridge
        const EuclidAnimations = EuclidRepl.EuclidAnimations
        const EUCLID_REPL_RUNTIME = $runtime
        const EUCLID_STATE_PTR = $state_ptr
        const state_ptr = $state_ptr
    end)
    return nothing
end

"""Install point, line, circle, visibility, and palette helpers."""
function install_primitive_helpers!(context_module::Module)
    Core.eval(context_module, quote
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
        """circle!(center,radius; start_theta=0,sweep_theta=2pi,filled=false)."""
        circle!(args...; kwargs...) = EuclidRepl.circle!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
    end)
    return nothing
end

"""Install labels, filled polygons, circle regions, and defining-ID accessors."""
function install_region_helpers!(context_module::Module)
    Core.eval(context_module, quote
        """Reveal a text label."""
        label!(args...; kwargs...) = EuclidRepl.label!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """triangle!(first,second,third; color,duration); ordered coplanar XY vertices."""
        triangle!(args...; kwargs...) = EuclidRepl.triangle!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """square!(first,second,third,fourth; color,duration); ordered XY vertices."""
        square!(args...; kwargs...) = EuclidRepl.square!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """pentagon!(first,second,third,fourth,fifth; color,duration); ordered XY vertices."""
        pentagon!(args...; kwargs...) = EuclidRepl.pentagon!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and reveal the intersection of two circles."""
        lens!(args...; kwargs...) = EuclidRepl.lens!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and reveal the directional difference of two circles."""
        lune!(args...; kwargs...) = EuclidRepl.lune!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Return ordered polygon defining-point IDs."""
        polygon_vertex_ids(shape) = EuclidRepl.polygon_vertex_ids(shape)
        """Return ordered line endpoint IDs."""
        line_endpoint_ids(shape) = EuclidRepl.line_endpoint_ids(shape)
        """Return ordered lens/lune defining-center IDs."""
        circle_region_center_ids(shape) =
            EuclidRepl.circle_region_center_ids(shape)
    end)
    return nothing
end

"""Install the literal-rail Cycloid constructors."""
function install_cycloid_helpers!(context_module::Module)
    Core.eval(context_module, quote
        """Construct and animate a literal-rail Cycloid."""
        cycloid!(args...; kwargs...) = EuclidRepl.cycloid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct an ordinary Cycloid."""
        ordinary_cycloid!(args...; kwargs...) = EuclidRepl.ordinary_cycloid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct a curtate Cycloid."""
        curtate_cycloid!(args...; kwargs...) = EuclidRepl.curtate_cycloid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct a prolate Cycloid."""
        prolate_cycloid!(args...; kwargs...) = EuclidRepl.prolate_cycloid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
    end)
    return nothing
end

"""Install general rolling-circle and roulette constructors."""
function install_trochoid_helpers!(context_module::Module)
    Core.eval(context_module, quote
        """Construct an external or internal trochoid."""
        trochoid!(args...; kwargs...) = EuclidRepl.trochoid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate an ellipse."""
        ellipse!(args...; kwargs...) = EuclidRepl.ellipse!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate a cardioid."""
        cardioid!(args...; kwargs...) = EuclidRepl.cardioid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate a limacon."""
        limacon!(args...; kwargs...) = EuclidRepl.limacon!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate a convex limacon."""
        convex_limacon!(args...; kwargs...) = EuclidRepl.convex_limacon!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate a dimpled limacon."""
        dimpled_limacon!(args...; kwargs...) = EuclidRepl.dimpled_limacon!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate an epitrochoid."""
        epitrochoid!(args...; kwargs...) = EuclidRepl.epitrochoid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate a hypotrochoid."""
        hypotrochoid!(args...; kwargs...) = EuclidRepl.hypotrochoid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
    end)
    return nothing
end

"""Install the named closed-roulette constructors."""
function install_named_roulette_helpers!(context_module::Module)
    Core.eval(context_module, quote
        """Construct and animate a hypocycloid."""
        hypocycloid!(args...; kwargs...) = EuclidRepl.hypocycloid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate a deltoid."""
        deltoid!(args...; kwargs...) = EuclidRepl.deltoid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate an astroid."""
        astroid!(args...; kwargs...) = EuclidRepl.astroid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate a five-cusped hypocycloid."""
        five_hypocycloid!(args...; kwargs...) = EuclidRepl.five_hypocycloid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate an eleven-halves hypocycloid."""
        eleven_half_hypocycloid!(args...; kwargs...) =
            EuclidRepl.eleven_half_hypocycloid!(
                EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate a nephroid."""
        nephroid!(args...; kwargs...) = EuclidRepl.nephroid!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate a three-dimple epitrochoid."""
        three_dimple_epitrochoid!(args...; kwargs...) =
            EuclidRepl.three_dimple_epitrochoid!(
                EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate the five-point hypotrochoid."""
        five_point_hypotrochoid!(args...; kwargs...) =
            EuclidRepl.five_point_hypotrochoid!(
                EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
    end)
    return nothing
end

"""Install conics, highlights, and queue controls."""
function install_conic_and_control_helpers!(context_module::Module)
    Core.eval(context_module, quote
        """Construct and animate a finite parabola."""
        parabola!(args...; kwargs...) = EuclidRepl.parabola!(
            EUCLID_REPL_RUNTIME, EUCLID_STATE_PTR, args...; kwargs...)
        """Construct and animate a one-host hyperbola."""
        hyperbola!(args...; kwargs...) = EuclidRepl.hyperbola!(
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

"""Install the complete shape and queue API for a Terminal generation."""
function install_drawing_helpers!(
    context_module::Module, runtime::EuclidReplRuntime,
    state_ptr::Ptr{Cvoid})::Nothing
    install_repl_bindings!(context_module, runtime, state_ptr)
    install_primitive_helpers!(context_module)
    install_region_helpers!(context_module)
    install_cycloid_helpers!(context_module)
    install_trochoid_helpers!(context_module)
    install_named_roulette_helpers!(context_module)
    install_conic_and_control_helpers!(context_module)
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
        """Rotate a typed shape in its supported board-plane representation."""
        rotate_z!(args...; kwargs...) = EuclidRepl.rotate_z!(
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

"""Validate a positive finite analytic parameter and return Float32."""
function validated_positive_parameter(name::AbstractString, value::Real)::Float32
    result = Float32(value)
    isfinite(result) && result > 0f0 ||
        throw(ArgumentError("$(name) must be finite and > 0f0"))
    return result
end

"""Validate a finite nonnegative analytic parameter and return Float32."""
function validated_nonnegative_parameter(name::AbstractString, value::Real)::Float32
    result = Float32(value)
    isfinite(result) && result >= 0f0 ||
        throw(ArgumentError("$(name) must be finite and >= 0f0"))
    return result
end

"""Validate a directed finite curve domain and one frontier within it."""
function validated_curve_domain(parameter_start::Real, parameter_finish::Real,
    draw_parameter::Real)
    first = validated_angle_theta(parameter_start)
    finish = validated_angle_theta(parameter_finish)
    frontier = validated_angle_theta(draw_parameter)
    first != finish || throw(ArgumentError("curve parameter endpoints must differ"))
    inside = first < finish ? first <= frontier <= finish :
        first >= frontier >= finish
    inside || throw(ArgumentError("draw_parameter must lie in the directed curve interval"))
    return Float32[first, finish, frontier]
end

"""Convert one public trochoid mode symbol to its bridge enum value."""
function validated_trochoid_mode(mode::Symbol)::Int32
    mode === :external && return OdinJuliaBridge.TROCHOID_EXTERNAL
    mode === :internal && return OdinJuliaBridge.TROCHOID_INTERNAL
    throw(ArgumentError("trochoid mode must be :external or :internal"))
end

"""Fail the active Terminal action when a native operation rejects a command."""
function checked_terminal_status(status::Int32, operation::AbstractString)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        error("Terminal $(operation) failed with status $status")
    return nothing
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

"""Rotate a point about the world-Z line through a pivot without changing z."""
function rotated_xy_position(
    position::AbstractVector{<:Real}, pivot::AbstractVector{<:Real}, theta::Real)
    sine, cosine = sincos(Float32(theta))
    dx = Float32(position[1] - pivot[1])
    dy = Float32(position[2] - pivot[2])
    return Float32[
        pivot[1] + dx * cosine - dy * sine,
        pivot[2] + dx * sine + dy * cosine,
        position[3]]
end

"""Rotate an arc's in-plane parameterization after its center moves."""
function rotate_analytic_geometry!(
    state_ptr::Ptr{Cvoid}, payload::AnalyticRotationPayload, theta::Float32,
    geometry::OdinJuliaBridge.BridgeArcGeometry)
    payload.kind == :arc || error("Terminal analytic rotation has an invalid arc kind")
    checked_terminal_status(OdinJuliaBridge.set_arc_geometry(state_ptr,
        payload.host_id, geometry.radius, geometry.start_theta + theta,
        geometry.sweep_theta), "arc rotation")
end

"""Rotate a trochoid's in-plane parameterization without changing its frontier."""
function rotate_analytic_geometry!(
    state_ptr::Ptr{Cvoid}, payload::AnalyticRotationPayload, theta::Float32,
    geometry::OdinJuliaBridge.BridgeTrochoidGeometry)
    payload.kind == :trochoid ||
        error("Terminal analytic rotation has an invalid trochoid kind")
    checked_terminal_status(OdinJuliaBridge.set_trochoid_geometry(
        state_ptr, payload.host_id; mode=geometry.mode,
        fixed_radius=geometry.fixed_radius, rolling_radius=geometry.rolling_radius,
        tracer_distance=geometry.tracer_distance, tracer_phase=geometry.tracer_phase,
        rotation=geometry.rotation + theta, parameter_start=geometry.parameter_start,
        parameter_finish=geometry.parameter_finish,
        draw_parameter=geometry.draw_parameter), "trochoid rotation")
end

"""Rotate a parabola's in-plane parameterization without changing its frontier."""
function rotate_analytic_geometry!(
    state_ptr::Ptr{Cvoid}, payload::AnalyticRotationPayload, theta::Float32,
    geometry::OdinJuliaBridge.BridgeParabolaGeometry)
    payload.kind == :parabola ||
        error("Terminal analytic rotation has an invalid parabola kind")
    checked_terminal_status(OdinJuliaBridge.set_parabola_geometry(
        state_ptr, payload.host_id; focal_distance=geometry.focal_distance,
        rotation=geometry.rotation + theta, parameter_start=geometry.parameter_start,
        parameter_finish=geometry.parameter_finish,
        draw_parameter=geometry.draw_parameter), "parabola rotation")
end

"""Rotate a hyperbola's in-plane parameterization without changing its frontier."""
function rotate_analytic_geometry!(
    state_ptr::Ptr{Cvoid}, payload::AnalyticRotationPayload, theta::Float32,
    geometry::OdinJuliaBridge.BridgeHyperbolaGeometry)
    payload.kind == :hyperbola ||
        error("Terminal analytic rotation has an invalid hyperbola kind")
    checked_terminal_status(OdinJuliaBridge.set_hyperbola_geometry(
        state_ptr, payload.host_id; semimajor=geometry.semimajor,
        semiminor=geometry.semiminor, rotation=geometry.rotation + theta,
        parameter_start=geometry.parameter_start,
        parameter_finish=geometry.parameter_finish,
        draw_parameter=geometry.draw_parameter), "hyperbola rotation")
end

"""Render a queued analytic planar rotation while preserving native geometry."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real,
    payload::AnalyticRotationPayload)
    geometry = payload.geometry
    geometry === nothing && error("Terminal analytic rotation was not initialized")
    theta = payload.theta * clamp(Float32(elapsed / duration), 0f0, 1f0)
    position = rotated_xy_position(payload.center, payload.pivot, theta)
    checked_terminal_status(OdinJuliaBridge.set_point_position_status(
        state_ptr, payload.host_id, position[1], position[2], position[3]),
        "analytic center motion")
    rotate_analytic_geometry!(state_ptr, payload, theta, geometry)
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

"""Validate an ordered polygon in the native XY fill plane."""
function validated_polygon_vertices(vertices)
    3 <= length(vertices) <= 5 ||
        throw(ArgumentError("polygons require between 3 and 5 vertices"))
    points = [vec3("vertex[$index]", vertex) for (index, vertex) in pairs(vertices)]
    all(point -> point[3] == points[1][3], points) ||
        throw(ArgumentError("polygon vertices must share one z coordinate"))
    length(unique(Tuple.(points))) == length(points) ||
        throw(ArgumentError("polygon vertices must be distinct"))
    twice_area = sum(
        Float64(points[index][1]) * Float64(points[mod1(index + 1, length(points))][2]) -
        Float64(points[mod1(index + 1, length(points))][1]) * Float64(points[index][2])
        for index in eachindex(points))
    isfinite(twice_area) && !iszero(twice_area) ||
        throw(ArgumentError("polygon vertices must enclose nonzero area"))
    for first_edge in eachindex(points)
        first_next = mod1(first_edge + 1, length(points))
        for second_edge in (first_edge + 1):length(points)
            second_next = mod1(second_edge + 1, length(points))
            (first_edge == second_edge || first_next == second_edge ||
                second_next == first_edge) && continue
            EuclidAnimations.segments_intersect_xy(points[first_edge],
                points[first_next], points[second_edge], points[second_next]) &&
                throw(ArgumentError("polygon edges must not intersect"))
        end
    end
    return points
end

"""Return a circle-region constructor's validated planar geometry."""
function validated_circle_region(first_center, first_radius, second_center, second_radius)
    first = vec3("first_center", first_center)
    second = vec3("second_center", second_center)
    first[3] == second[3] ||
        throw(ArgumentError("circle centers must share one z coordinate"))
    r1 = validated_radius(first_radius)
    r2 = validated_radius(second_radius)
    distance = hypot(Float64(second[1] - first[1]), Float64(second[2] - first[2]))
    abs(Float64(r1) - Float64(r2)) < distance < Float64(r1) + Float64(r2) ||
        throw(ArgumentError("circle radii must have a strict two-intersection overlap"))
    return (center=first, radius=r1), (center=second, radius=r2)
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

"""Finalize a label after its native reveal interval."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::LabelPayload)
    checked_terminal_status(OdinJuliaBridge.show_point(state_ptr, payload.host_id),
        "label completion")
end

"""Finalize a filled region after its native reveal interval."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::RegionPayload)
    checked_terminal_status(OdinJuliaBridge.show_point(state_ptr, payload.host_id),
        "region completion")
end

"""Finalize a polygon after edge tracing and its filled-region reveal."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::PolygonPayload)
    checked_terminal_status(OdinJuliaBridge.show_point(state_ptr, payload.host_id),
        "polygon completion")
end

"""Commit a Cycloid's exact frontier even when a tick skipped its last draw frame."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::CycloidPayload)
    checked_terminal_status(OdinJuliaBridge.set_cycloid_frontier(
        state_ptr, payload.host_id, payload.draw_parameter), "Cycloid completion")
    checked_terminal_status(OdinJuliaBridge.show_point(state_ptr, payload.host_id),
        "curve completion")
end

"""Commit a trochoid's exact frontier before any queued motion snapshots it."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::TrochoidPayload)
    checked_terminal_status(OdinJuliaBridge.set_trochoid_frontier(
        state_ptr, payload.host_id, payload.draw_parameter), "trochoid completion")
    checked_terminal_status(OdinJuliaBridge.show_point(state_ptr, payload.host_id),
        "curve completion")
end

"""Commit the requested parabola frontier independently of draw-phase sampling."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::ParabolaPayload)
    checked_terminal_status(OdinJuliaBridge.set_parabola_frontier(
        state_ptr, payload.host_id, payload.draw_parameter), "parabola completion")
    checked_terminal_status(OdinJuliaBridge.show_point(state_ptr, payload.host_id),
        "curve completion")
end

"""Commit the shared hyperbola frontier without changing branch selection."""
function finalize_payload!(state_ptr::Ptr{Cvoid}, payload::HyperbolaPayload)
    checked_terminal_status(OdinJuliaBridge.set_hyperbola_frontier(
        state_ptr, payload.host_id, payload.draw_parameter), "hyperbola completion")
    checked_terminal_status(OdinJuliaBridge.show_point(state_ptr, payload.host_id),
        "curve completion")
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

"""Wait for the label reveal started when this action was activated."""
render_payload!(_state::Ptr{Cvoid}, _elapsed::Real, _duration::Real,
    _payload::LabelPayload) = nothing

"""Wait for the region reveal started when this action was activated."""
render_payload!(_state::Ptr{Cvoid}, _elapsed::Real, _duration::Real,
    _payload::RegionPayload) = nothing

"""Start the polygon fill reveal once elapsed time reaches its phase."""
function start_polygon_reveal_if_due!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real,
    payload::PolygonPayload, reveal_region)
    reveal_start = duration * 0.7f0
    if elapsed >= reveal_start && !payload.reveal_started
        reveal_duration = duration * 0.15f0
        result = reveal_region(
            state_ptr, payload.host_id, reveal_duration)
        checked_terminal_status(result, "polygon reveal")
        payload.reveal_started = true
    end
    return nothing
end

"""Trace polygon edges, reveal its fill, and raise the pen."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::PolygonPayload)
    descend = duration * 0.15f0
    draw = duration * 0.55f0
    reveal = duration * 0.15f0
    rise_start = descend + draw + reveal
    start_polygon_reveal_if_due!(
        state_ptr, elapsed, duration, payload, OdinJuliaBridge.reveal_region!)
    if elapsed < descend
        first = payload.vertices[1]
        EuclidAnimations.animate_pen_descend(state_ptr, elapsed, descend,
            HIGHLIGHT_TOOL_TOP_Z, first[1], first[2])
    elseif elapsed < descend + draw
        render_polygon_edges!(state_ptr, elapsed - descend, draw, payload)
    elseif elapsed >= rise_start
        last = payload.vertices[1]
        EuclidAnimations.animate_pen_rise(state_ptr, elapsed - rise_start,
            duration - rise_start, HIGHLIGHT_TOOL_TOP_Z, last[1], last[2])
    end
end

"""Render the active edge of a polygon's ordered pen path."""
function render_polygon_edges!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::PolygonPayload)
    edge_count = length(payload.vertices)
    edge_duration = duration / edge_count
    edge = min(floor(Int, elapsed / edge_duration) + 1, edge_count)
    edge_elapsed = elapsed - (edge - 1) * edge_duration
    start = payload.vertices[edge]
    finish = payload.vertices[mod1(edge + 1, edge_count)]
    azimuth = atan(finish[2] - start[2], finish[1] - start[1])
    EuclidAnimations.animate_pen_drag(state_ptr, edge_elapsed, edge_duration,
        start, finish, π / 3f0, azimuth, payload.color)
end

"""Animate one literal-rail Cycloid through descent, frontier, and tool retirement."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::CycloidPayload)
    descend = duration * 0.2f0
    draw = duration * 0.6f0
    rise_start = descend + draw
    if elapsed < descend
        EuclidAnimations.animate_cycloid_descend(state_ptr, elapsed, descend,
            CURVE_TOOL_TOP_Z, payload.first, payload.second, payload.rolling_radius;
            tracer_distance=payload.tracer_distance,
            parameter_start=payload.parameter_start,
            parameter_finish=payload.parameter_finish,
            tracer_phase=payload.tracer_phase)
    elseif elapsed < rise_start
        EuclidAnimations.animate_draw_cycloid(state_ptr, elapsed - descend, draw,
            payload.first, payload.second, payload.rolling_radius;
            tracer_distance=payload.tracer_distance,
            parameter_start=payload.parameter_start,
            parameter_finish=payload.parameter_finish,
            draw_parameter=payload.draw_parameter,
            curve_id=payload.host_id, color=payload.color, brush=payload.brush,
            tracer_phase=payload.tracer_phase)
    else
        EuclidAnimations.animate_cycloid_rise(state_ptr, elapsed - rise_start,
            duration - rise_start, CURVE_TOOL_TOP_Z, payload.first, payload.second,
            payload.rolling_radius; tracer_distance=payload.tracer_distance,
            parameter_start=payload.parameter_start,
            parameter_finish=payload.parameter_finish,
            draw_parameter=payload.draw_parameter,
            tracer_phase=payload.tracer_phase)
    end
end

"""Animate one analytic Trochoid with its guide and compass."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::TrochoidPayload)
    descend = duration * 0.2f0
    draw = duration * 0.6f0
    rise_start = descend + draw
    if elapsed < descend
        EuclidAnimations.animate_trochoid_descend(state_ptr, elapsed, descend,
            CURVE_TOOL_TOP_Z, payload.center, payload.parameter_start;
            mode=payload.mode, fixed_radius=payload.fixed_radius,
            rolling_radius=payload.rolling_radius,
            tracer_distance=payload.tracer_distance, rotation=payload.rotation,
            tracer_phase=payload.tracer_phase)
    elseif elapsed < rise_start
        EuclidAnimations.animate_draw_trochoid(state_ptr, elapsed - descend, draw,
            payload.center, payload.parameter_start, payload.parameter_finish;
            mode=payload.mode, fixed_radius=payload.fixed_radius,
            rolling_radius=payload.rolling_radius,
            tracer_distance=payload.tracer_distance, curve_id=payload.host_id,
            color=payload.color, brush=payload.brush, rotation=payload.rotation,
            tracer_phase=payload.tracer_phase,
            draw_parameter=payload.draw_parameter)
    else
        EuclidAnimations.animate_trochoid_rise(state_ptr, elapsed - rise_start,
            duration - rise_start, CURVE_TOOL_TOP_Z, payload.center,
            payload.draw_parameter;
            mode=payload.mode, fixed_radius=payload.fixed_radius,
            rolling_radius=payload.rolling_radius,
            tracer_distance=payload.tracer_distance, rotation=payload.rotation,
            tracer_phase=payload.tracer_phase)
    end
end

"""Animate a finite parabola with its integrated articulated instrument."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::ParabolaPayload)
    descend = duration * 0.2f0
    draw = duration * 0.6f0
    rise_start = descend + draw
    if elapsed < descend
        EuclidAnimations.animate_parabola_descend(state_ptr, elapsed, descend,
            CURVE_TOOL_TOP_Z, payload.vertex, payload.parameter_start;
            color=payload.color)
    elseif elapsed < rise_start
        EuclidAnimations.animate_draw_parabola(state_ptr, elapsed - descend, draw,
            payload.vertex, payload.focal_distance, payload.parameter_start,
            payload.draw_parameter; curve_id=payload.host_id, color=payload.color,
            rotation=payload.rotation)
    else
        EuclidAnimations.animate_parabola_rise(state_ptr, elapsed - rise_start,
            duration - rise_start, CURVE_TOOL_TOP_Z, payload.vertex,
            payload.draw_parameter; color=payload.color)
    end
end

"""Animate one selected branch set on the shared hyperbola frontier."""
function render_payload!(
    state_ptr::Ptr{Cvoid}, elapsed::Real, duration::Real, payload::HyperbolaPayload)
    descend = duration * 0.2f0
    draw = duration * 0.6f0
    rise_start = descend + draw
    if elapsed < descend
        EuclidAnimations.animate_hyperbola_descend(state_ptr, elapsed, descend,
            CURVE_TOOL_TOP_Z, payload.center, payload.parameter_start;
            color=payload.color)
    elseif elapsed < rise_start
        EuclidAnimations.animate_draw_hyperbola(state_ptr, elapsed - descend, draw,
            payload.center, payload.semimajor, payload.semiminor,
            payload.parameter_start, payload.draw_parameter; curve_id=payload.host_id,
            color=payload.color, rotation=payload.rotation, branches=payload.branches)
    else
        EuclidAnimations.animate_hyperbola_rise(state_ptr, elapsed - rise_start,
            duration - rise_start, CURVE_TOOL_TOP_Z, payload.center,
            payload.draw_parameter; color=payload.color)
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
    if job.kind == :point || job.kind == :line || job.kind == :polygon ||
        job.kind == :highlight_pen
        OdinJuliaBridge.hide_pen(state_ptr)
    elseif job.kind == :circle || job.kind == :highlight_compass
        OdinJuliaBridge.hide_compass(state_ptr)
    elseif job.kind == :cycloid
        checked_terminal_status(OdinJuliaBridge.hide_cycloid_tool(state_ptr),
            "Cycloid tool retirement")
        OdinJuliaBridge.hide_compass(state_ptr)
    elseif job.kind == :trochoid
        checked_terminal_status(OdinJuliaBridge.hide_trochoid_tool(state_ptr),
            "trochoid tool retirement")
        OdinJuliaBridge.hide_compass(state_ptr)
    elseif job.kind == :parabola
        checked_terminal_status(OdinJuliaBridge.hide_parabola_tool(state_ptr),
            "parabola tool retirement")
    elseif job.kind == :hyperbola
        checked_terminal_status(OdinJuliaBridge.hide_hyperbola_tool(state_ptr),
            "hyperbola tool retirement")
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
construction_target(payload::LabelPayload, id::UInt64) = payload.host_id == id
construction_target(payload::RegionPayload, id::UInt64) =
    id == payload.host_id || id in payload.center_ids
construction_target(payload::PolygonPayload, id::UInt64) =
    id == payload.host_id || id in payload.vertex_ids
construction_target(payload::CycloidPayload, id::UInt64) =
    id == payload.host_id || id in payload.endpoint_ids
construction_target(payload::Union{TrochoidPayload,ParabolaPayload,HyperbolaPayload},
    id::UInt64) = payload.host_id == id
construction_target(payload::AnalyticRotationPayload, id::UInt64) =
    payload.host_id == id
construction_target(_::ReplDrawPayload, _::UInt64) = false

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

"""Start a typed native label reveal when its queued action reaches the head."""
function activate_payload!(state_ptr::Ptr{Cvoid}, payload::LabelPayload)
    validated_target(state_ptr, payload.host_id)
    result = OdinJuliaBridge.reveal_label!(state_ptr, payload.host_id,
        payload.reveal_duration)
    checked_terminal_status(result, "label reveal")
end

"""Start a typed native region reveal when its queued action reaches the head."""
function activate_payload!(state_ptr::Ptr{Cvoid}, payload::RegionPayload)
    validated_target(state_ptr, payload.host_id)
    for center_id in payload.center_ids
        validated_target(state_ptr, center_id)
    end
    result = OdinJuliaBridge.reveal_region!(state_ptr, payload.host_id,
        payload.reveal_duration)
    checked_terminal_status(result, "region reveal")
end

"""Validate a polygon host and each ordered defining point at activation."""
function activate_payload!(state_ptr::Ptr{Cvoid}, payload::PolygonPayload)
    validated_target(state_ptr, payload.host_id)
    for point_id in payload.vertex_ids
        validated_target(state_ptr, point_id)
    end
end

"""Configure and validate a literal Cycloid's queued guide before descent."""
function activate_payload!(state_ptr::Ptr{Cvoid}, payload::CycloidPayload)
    validated_target(state_ptr, payload.host_id)
    for endpoint_id in payload.endpoint_ids
        validated_target(state_ptr, endpoint_id)
    end
    status = OdinJuliaBridge.set_cycloid_tool_geometry(state_ptr;
        rolling_radius=payload.rolling_radius,
        parameter_start=payload.parameter_start,
        parameter_finish=payload.parameter_finish,
        parameter=payload.parameter_start,
        orientation_phase=payload.tracer_phase)
    checked_terminal_status(status, "Cycloid tool setup")
end

"""Configure and validate a trochoid's queued guide before descent."""
function activate_payload!(state_ptr::Ptr{Cvoid}, payload::TrochoidPayload)
    validated_target(state_ptr, payload.host_id)
    status = OdinJuliaBridge.set_trochoid_tool_geometry(state_ptr;
        mode=payload.mode, fixed_radius=payload.fixed_radius,
        rolling_radius=payload.rolling_radius,
        parameter=payload.parameter_start, rotation=payload.rotation,
        orientation_phase=payload.tracer_phase)
    checked_terminal_status(status, "trochoid tool setup")
end

"""Configure and validate a parabola's integrated guide before descent."""
function activate_payload!(state_ptr::Ptr{Cvoid}, payload::ParabolaPayload)
    validated_target(state_ptr, payload.host_id)
    status = OdinJuliaBridge.set_parabola_tool_geometry(state_ptr;
        focal_distance=payload.focal_distance, link_length=payload.link_length,
        rotation=payload.rotation, parameter_start=payload.parameter_start,
        parameter_finish=payload.parameter_finish,
        parameter=payload.parameter_start)
    checked_terminal_status(status, "parabola tool setup")
end

"""Configure and validate a hyperbola's paired guide before descent."""
function activate_payload!(state_ptr::Ptr{Cvoid}, payload::HyperbolaPayload)
    validated_target(state_ptr, payload.host_id)
    status = OdinJuliaBridge.set_hyperbola_tool_geometry(state_ptr;
        semimajor=payload.semimajor, semiminor=payload.semiminor,
        rotation=payload.rotation, parameter_start=payload.parameter_start,
        parameter_finish=payload.parameter_finish,
        parameter=payload.parameter_start,
        rail_half_length=payload.rail_half_length)
    checked_terminal_status(status, "hyperbola tool setup")
end

"""Snapshot current center and analytic parameters when the rotation activates."""
function activate_payload!(
    state_ptr::Ptr{Cvoid}, payload::AnalyticRotationPayload)
    view = validated_target(state_ptr, payload.host_id)
    view.has_position != 0 ||
        error("Terminal analytic rotation target has no position")
    payload.center = Float32[view.pos...]
    if payload.kind == :arc
        query = OdinJuliaBridge.get_arc_geometry(state_ptr, payload.host_id)
        checked_terminal_status(query.status, "arc geometry query")
        payload.geometry = query.arc
    elseif payload.kind == :trochoid
        query = OdinJuliaBridge.get_trochoid_geometry(state_ptr, payload.host_id)
        checked_terminal_status(query.status, "trochoid geometry query")
        payload.geometry = query.geometry
    else
        parabola = OdinJuliaBridge.get_parabola_geometry(state_ptr, payload.host_id)
        if parabola.status == OdinJuliaBridge.BRIDGE_STATUS_OK
            payload.kind = :parabola
            payload.geometry = parabola.geometry
        else
            hyperbola = OdinJuliaBridge.get_hyperbola_geometry(state_ptr, payload.host_id)
            checked_terminal_status(hyperbola.status, "conic geometry query")
            payload.kind = :hyperbola
            payload.geometry = hyperbola.geometry
        end
    end
end

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

"""Hide any newly supported typed shape result by its single host identity."""
function hide!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    shape::Union{
        OdinJuliaBridge.BridgeShapeCircleRegion,
        OdinJuliaBridge.BridgeShapeTrochoidResult,
        OdinJuliaBridge.BridgeShapeCycloidResult,
        OdinJuliaBridge.BridgeShapeConicResult,
        OdinJuliaBridge.BridgeShapeTriangle,
        OdinJuliaBridge.BridgeShapeSquare,
        OdinJuliaBridge.BridgeShapePentagon})
    shape.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        throw(ArgumentError("hide! requires a successful typed shape result"))
    _hide_bridge_point(runtime, state_ptr, shape.host_id)
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

"""Require a successful native constructor result before admitting its action."""
function checked_constructor_result(result, family::AbstractString)
    result.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        error("Terminal $(family) reservation failed with status $(result.status)")
    return result
end

"""Copy a label's plain text after enforcing the native UTF-8 source limit."""
function validated_label_source(text::AbstractString)::String
    source = String(text)
    ncodeunits(source) <= 256 ||
        throw(ArgumentError("label text must not exceed 256 UTF-8 bytes"))
    occursin('\0', source) && throw(ArgumentError("label text must not contain NUL"))
    return source
end

"""
Reveal a bounded plain-text label and return its typed entity result.

The UTF-8 source may contain at most 256 bytes. The queued reveal begins only
when this action reaches the FIFO head.
"""
function label!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, text::AbstractString,
    position::AbstractVector{<:Real}; color=:plum1, brush::Real=DEFAULT_BRUSH,
    duration::Real=DEFAULT_LABEL_DURATION)
    source = validated_label_source(text)
    position3 = vec3("position", position)
    brush_value = validated_brush(brush)
    reveal_duration = validated_duration(duration)
    shape_color = OdinJuliaBridge._shape_color(color)
    session = ensure_session!(runtime)
    require_action_capacity(session)
    label = checked_constructor_result(OdinJuliaBridge.create_new_label(
        state_ptr, source, position3, shape_color, brush_value), "label")
    start_job!(runtime, state_ptr, ReplDrawJob(:label, reveal_duration, 0f0,
        LabelPayload(label.index, reveal_duration)))
    track_managed_host!(session, label.index)
    return label
end

"""Return a successful polygon result's vertex identities in construction order."""
function polygon_vertex_ids(shape::OdinJuliaBridge.BridgeShapeTriangle)
    shape.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        throw(ArgumentError("polygon result is not successful"))
    return UInt64[shape.joint1_id, shape.joint2_id, shape.joint3_id]
end

"""Return a successful quadrilateral's vertex identities in construction order."""
function polygon_vertex_ids(shape::OdinJuliaBridge.BridgeShapeSquare)
    shape.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        throw(ArgumentError("polygon result is not successful"))
    return UInt64[shape.joint1_id, shape.joint2_id, shape.joint3_id, shape.joint4_id]
end

"""Return a successful pentagon's vertex identities in construction order."""
function polygon_vertex_ids(shape::OdinJuliaBridge.BridgeShapePentagon)
    shape.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        throw(ArgumentError("polygon result is not successful"))
    return UInt64[shape.joint1_id, shape.joint2_id, shape.joint3_id, shape.joint4_id,
        shape.joint5_id]
end

"""Return a successful line result's ordered endpoint identities."""
function line_endpoint_ids(shape::OdinJuliaBridge.BridgeShapeLine)
    shape.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        throw(ArgumentError("line result is not successful"))
    return (shape.joint1_id, shape.joint2_id)
end

"""Return a successful lens/lune result's ordered defining-center identities."""
function circle_region_center_ids(shape::OdinJuliaBridge.BridgeShapeCircleRegion)
    shape.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        throw(ArgumentError("circle-region result is not successful"))
    return (shape.first_center_id, shape.second_center_id)
end

"""Queue a polygon's ordered pen path and filled-region reveal."""
function queue_polygon!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, vertices, color,
    duration::Real, kind::Symbol, constructor)
    points = validated_polygon_vertices(vertices)
    draw_duration = validated_duration(duration)
    shape_color = OdinJuliaBridge._shape_color(color)
    session = ensure_session!(runtime)
    require_action_capacity(session)
    shape = checked_constructor_result(constructor(points, shape_color), String(kind))
    ids = polygon_vertex_ids(shape)
    payload = PolygonPayload(shape.host_id, ids, points, shape_color, false)
    start_job!(runtime, state_ptr, ReplDrawJob(:polygon, draw_duration, 0f0, payload))
    track_managed_host!(session, shape.host_id)
    return shape
end

"""Construct and animate an ordered, filled triangle."""
function triangle!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    first::AbstractVector{<:Real}, second::AbstractVector{<:Real},
    third::AbstractVector{<:Real}; color=DEFAULT_COLOR,
    duration::Real=DEFAULT_POLYGON_DURATION)
    vertices = (first, second, third)
    queue_polygon!(runtime, state_ptr, vertices, color, duration, :triangle,
        (points, shape_color) -> OdinJuliaBridge.create_new_triangle(
            state_ptr, points..., shape_color))
end

"""Construct and animate an ordered, filled square."""
function square!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    first::AbstractVector{<:Real}, second::AbstractVector{<:Real},
    third::AbstractVector{<:Real}, fourth::AbstractVector{<:Real};
    color=DEFAULT_COLOR, duration::Real=DEFAULT_POLYGON_DURATION)
    vertices = (first, second, third, fourth)
    queue_polygon!(runtime, state_ptr, vertices, color, duration, :square,
        (points, shape_color) -> OdinJuliaBridge.create_new_square(
            state_ptr, points..., shape_color))
end

"""Construct and animate an ordered, filled pentagon."""
function pentagon!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    first::AbstractVector{<:Real}, second::AbstractVector{<:Real},
    third::AbstractVector{<:Real}, fourth::AbstractVector{<:Real},
    fifth::AbstractVector{<:Real}; color=DEFAULT_COLOR,
    duration::Real=DEFAULT_POLYGON_DURATION)
    vertices = (first, second, third, fourth, fifth)
    queue_polygon!(runtime, state_ptr, vertices, color, duration, :pentagon,
        (points, shape_color) -> OdinJuliaBridge.create_new_pentagon(
            state_ptr, points..., shape_color))
end

"""Queue a native filled-region reveal and track its one host."""
function queue_circle_region!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, first_center,
    first_radius::Real, second_center, second_radius::Real,
    kind::Symbol, constructor; color=DEFAULT_COLOR, duration::Real=DEFAULT_REGION_DURATION)
    first, second = validated_circle_region(
        first_center, first_radius, second_center, second_radius)
    reveal_duration = validated_duration(duration)
    shape_color = OdinJuliaBridge._shape_color(color)
    session = ensure_session!(runtime)
    require_action_capacity(session)
    region = checked_constructor_result(constructor(
        state_ptr, first.center, first.radius, second.center, second.radius;
        color=shape_color), String(kind))
    start_job!(runtime, state_ptr, ReplDrawJob(:region, reveal_duration, 0f0,
        RegionPayload(region.host_id,
            (region.first_center_id, region.second_center_id), reveal_duration)))
    track_managed_host!(session, region.host_id)
    return region
end

"""Construct the filled intersection of two overlapping circles."""
function lens!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    first_center::AbstractVector{<:Real}, first_radius::Real,
    second_center::AbstractVector{<:Real}, second_radius::Real;
    color=DEFAULT_COLOR, duration::Real=DEFAULT_REGION_DURATION)
    queue_circle_region!(runtime, state_ptr, first_center, first_radius,
        second_center, second_radius, :lens,
        OdinJuliaBridge.create_new_lens; color, duration)
end

"""Construct the directional difference of the first circle minus the second."""
function lune!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    first_center::AbstractVector{<:Real}, first_radius::Real,
    second_center::AbstractVector{<:Real}, second_radius::Real;
    color=DEFAULT_COLOR, duration::Real=DEFAULT_REGION_DURATION)
    queue_circle_region!(runtime, state_ptr, first_center, first_radius,
        second_center, second_radius, :lune,
        OdinJuliaBridge.create_new_lune; color, duration)
end

"""
Construct a finite literal-rail Cycloid and animate its guide and compass.

The rolling distance may not exceed the rail length. `draw_parameter` selects
the initial visible frontier within the directed parameter domain.
"""
function cycloid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    first::AbstractVector{<:Real}, second::AbstractVector{<:Real};
    rolling_radius::Real, tracer_distance::Real=rolling_radius,
    tracer_phase::Real=0f0, parameter_start::Real=0f0,
    parameter_finish::Real=4f0 * Float32(pi),
    draw_parameter::Real=parameter_finish, color=DEFAULT_COLOR,
    brush::Real=DEFAULT_BRUSH, duration::Real=DEFAULT_CURVE_DURATION)
    first3 = vec3("first", first)
    second3 = vec3("second", second)
    first3[3] == second3[3] ||
        throw(ArgumentError("Cycloid rail endpoints must share one z coordinate"))
    rail_length = hypot(Float64(second3[1] - first3[1]),
        Float64(second3[2] - first3[2]))
    rail_length > 0 || throw(ArgumentError("Cycloid rail must have nonzero XY length"))
    radius = validated_positive_parameter("rolling_radius", rolling_radius)
    distance = validated_nonnegative_parameter("tracer_distance", tracer_distance)
    phase = validated_angle_theta(tracer_phase)
    start, finish, frontier = validated_curve_domain(
        parameter_start, parameter_finish, draw_parameter)
    Float64(radius) * abs(Float64(finish - start)) <= rail_length ||
        throw(ArgumentError("Cycloid rolling travel must fit within its rail"))
    brush_value = validated_brush(brush)
    draw_duration = validated_duration(duration)
    shape_color = OdinJuliaBridge._shape_color(color)
    session = ensure_session!(runtime)
    require_action_capacity(session)
    result = checked_constructor_result(OdinJuliaBridge.create_new_cycloid(
        state_ptr, first3, second3; rolling_radius=radius,
        tracer_distance=distance, tracer_phase=phase,
        parameter_start=start, parameter_finish=finish,
        draw_parameter=frontier, color=shape_color, brush_size=brush_value),
        "Cycloid")
    payload = CycloidPayload(result.host_id, (result.first_id, result.second_id),
        first3, second3, radius, distance, phase, start, finish, frontier,
        shape_color, brush_value)
    start_job!(runtime, state_ptr, ReplDrawJob(:cycloid, draw_duration, 0f0, payload))
    track_managed_host!(session, result.host_id)
    return result
end

"""Construct an ordinary Cycloid whose tracer lies on the rolling circle."""
function ordinary_cycloid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, first, second,
    radius::Real; kwargs...)
    rolling = validated_positive_parameter("radius", radius)
    cycloid!(runtime, state_ptr, first, second;
        rolling_radius=rolling, tracer_distance=rolling, kwargs...)
end

"""Construct a curtate Cycloid with its tracer strictly inside the rolling circle."""
function curtate_cycloid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, first, second,
    radius::Real, tracer_distance::Real; kwargs...)
    rolling = validated_positive_parameter("radius", radius)
    distance = validated_nonnegative_parameter("tracer_distance", tracer_distance)
    distance < rolling ||
        throw(ArgumentError("curtate Cycloid requires tracer_distance < radius"))
    cycloid!(runtime, state_ptr, first, second;
        rolling_radius=rolling, tracer_distance=distance, kwargs...)
end

"""Construct a prolate Cycloid with its tracer outside the rolling circle."""
function prolate_cycloid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, first, second,
    radius::Real, tracer_distance::Real; kwargs...)
    rolling = validated_positive_parameter("radius", radius)
    distance = validated_positive_parameter("tracer_distance", tracer_distance)
    distance > rolling ||
        throw(ArgumentError("prolate Cycloid requires tracer_distance > radius"))
    cycloid!(runtime, state_ptr, first, second;
        rolling_radius=rolling, tracer_distance=distance, kwargs...)
end

"""
Construct and animate an analytic external or internal trochoid.

Use `mode=:external` or `:internal`; the returned typed result contains the
single curve host. All finite frontier and geometry parameters are validated
before reserving native identities.
"""
function trochoid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    center::AbstractVector{<:Real}; mode::Symbol=:external,
    fixed_radius::Real, rolling_radius::Real, tracer_distance::Real,
    tracer_phase::Real=0f0, rotation::Real=0f0,
    parameter_start::Real=0f0, parameter_finish::Real=2f0 * Float32(pi),
    draw_parameter::Real=parameter_finish, color=DEFAULT_COLOR,
    brush::Real=DEFAULT_BRUSH, duration::Real=DEFAULT_CURVE_DURATION)
    center3 = vec3("center", center)
    mode_value = validated_trochoid_mode(mode)
    fixed = validated_positive_parameter("fixed_radius", fixed_radius)
    rolling = validated_positive_parameter("rolling_radius", rolling_radius)
    if mode_value == OdinJuliaBridge.TROCHOID_INTERNAL && fixed <= rolling
        throw(ArgumentError("internal trochoid requires fixed_radius > rolling_radius"))
    end
    distance = validated_nonnegative_parameter("tracer_distance", tracer_distance)
    phase = validated_angle_theta(tracer_phase)
    rotation_value = validated_angle_theta(rotation)
    start, finish, frontier = validated_curve_domain(
        parameter_start, parameter_finish, draw_parameter)
    brush_value = validated_brush(brush)
    draw_duration = validated_duration(duration)
    shape_color = OdinJuliaBridge._shape_color(color)
    session = ensure_session!(runtime)
    require_action_capacity(session)
    result = checked_constructor_result(OdinJuliaBridge.create_new_trochoid(
        state_ptr, center3; mode=mode_value, fixed_radius=fixed,
        rolling_radius=rolling, tracer_distance=distance,
        tracer_phase=phase, rotation=rotation_value,
        parameter_start=start, parameter_finish=finish,
        draw_parameter=frontier, color=shape_color, brush_size=brush_value),
        "trochoid")
    payload = TrochoidPayload(result.host_id, center3, mode_value, fixed,
        rolling, distance, phase, rotation_value, start, finish, frontier,
        shape_color, brush_value)
    start_job!(runtime, state_ptr, ReplDrawJob(:trochoid, draw_duration, 0f0, payload))
    track_managed_host!(session, result.host_id)
    return result
end

"""Construct an ellipse using the internal rolling-circle representation."""
function ellipse!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, center,
    a::Real, b::Real; draw_parameter::Real=2f0 * Float32(pi), kwargs...)
    semimajor = validated_positive_parameter("a", a)
    semiminor = validated_positive_parameter("b", b)
    semimajor >= semiminor ||
        throw(ArgumentError("ellipse semiaxes require a >= b"))
    trochoid!(runtime, state_ptr, center; mode=:internal,
        fixed_radius=semimajor + semiminor,
        rolling_radius=(semimajor + semiminor) / 2f0,
        tracer_distance=(semimajor - semiminor) / 2f0,
        draw_parameter, kwargs...)
end

"""Construct an equal-radius external trochoid cardioid."""
function cardioid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, center,
    radius::Real; draw_parameter::Real=2f0 * Float32(pi), kwargs...)
    value = validated_positive_parameter("radius", radius)
    trochoid!(runtime, state_ptr, center; mode=:external,
        fixed_radius=value, rolling_radius=value, tracer_distance=value,
        draw_parameter, kwargs...)
end

"""Construct an equal-radius external trochoid limacon."""
function limacon!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, center,
    radius::Real, tracer_distance::Real;
    draw_parameter::Real=2f0 * Float32(pi), kwargs...)
    value = validated_positive_parameter("radius", radius)
    distance = validated_nonnegative_parameter("tracer_distance", tracer_distance)
    trochoid!(runtime, state_ptr, center; mode=:external,
        fixed_radius=value, rolling_radius=value, tracer_distance=distance,
        draw_parameter, kwargs...)
end

"""Construct a limacon with the fixed convex tracer ratio of 0.4."""
function convex_limacon!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, center,
    radius::Real; kwargs...)
    value = validated_positive_parameter("radius", radius)
    limacon!(runtime, state_ptr, center, value, 0.4f0 * value; kwargs...)
end

"""Construct a limacon with the fixed dimpled tracer ratio of 0.75."""
function dimpled_limacon!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, center,
    radius::Real; kwargs...)
    value = validated_positive_parameter("radius", radius)
    limacon!(runtime, state_ptr, center, value, 0.75f0 * value; kwargs...)
end

"""Construct a rational-ratio roulette with its minimal closure interval."""
function rational_trochoid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, center,
    mode::Symbol, fixed_radius::Real, k::Rational, tracer_distance::Real;
    parameter_start::Real=0f0,
    parameter_finish::Union{Nothing,Real}=nothing,
    draw_parameter::Union{Nothing,Real}=nothing, tracer_phase::Real=0f0,
    rotation::Real=0f0, color=DEFAULT_COLOR, brush::Real=DEFAULT_BRUSH,
    duration::Real=DEFAULT_CURVE_DURATION)
    k > 0 || throw(ArgumentError("trochoid ratio k must be positive"))
    mode === :internal && k <= 1 &&
        throw(ArgumentError("internal trochoid ratio k must be greater than one"))
    radius = validated_positive_parameter("fixed_radius", fixed_radius)
    start = validated_angle_theta(parameter_start)
    period = 2f0 * Float32(pi) * Float32(denominator(k))
    isfinite(period) || throw(ArgumentError("trochoid closure period must be finite"))
    finish = parameter_finish === nothing ? start + period :
        validated_angle_theta(parameter_finish)
    frontier = draw_parameter === nothing ? finish :
        validated_angle_theta(draw_parameter)
    trochoid!(runtime, state_ptr, center; mode, fixed_radius=radius,
        rolling_radius=radius / Float32(k), tracer_distance, tracer_phase,
        rotation, parameter_start=start, parameter_finish=finish,
        draw_parameter=frontier, color, brush, duration)
end

"""Construct a closed external trochoid with exact rational radius ratio."""
function epitrochoid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, center,
    fixed_radius::Real, k::Rational, tracer_distance::Real; kwargs...)
    rational_trochoid!(runtime, state_ptr, center, :external,
        fixed_radius, k, tracer_distance; kwargs...)
end

"""Construct a closed internal trochoid with exact rational radius ratio."""
function hypotrochoid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, center,
    fixed_radius::Real, k::Rational, tracer_distance::Real; kwargs...)
    rational_trochoid!(runtime, state_ptr, center, :internal,
        fixed_radius, k, tracer_distance; kwargs...)
end

"""Construct a closed hypocycloid whose tracer lies on the rolling circle."""
function hypocycloid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, center,
    fixed_radius::Real, k::Rational; kwargs...)
    k > 1 || throw(ArgumentError("hypocycloid ratio k must be greater than one"))
    radius = validated_positive_parameter("fixed_radius", fixed_radius)
    tracer = radius / Float32(k)
    rational_trochoid!(runtime, state_ptr, center, :internal,
        radius, k, tracer; kwargs...)
end

"""Construct the three-cusped deltoid hypocycloid."""
function deltoid!(runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    center, fixed_radius::Real; kwargs...)
    hypocycloid!(runtime, state_ptr, center, fixed_radius, 3 // 1; kwargs...)
end

"""Construct the four-cusped astroid hypocycloid."""
function astroid!(runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    center, fixed_radius::Real; kwargs...)
    hypocycloid!(runtime, state_ptr, center, fixed_radius, 4 // 1; kwargs...)
end

"""Construct the five-cusped hypocycloid."""
function five_hypocycloid!(runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    center, fixed_radius::Real; kwargs...)
    hypocycloid!(runtime, state_ptr, center, fixed_radius, 5 // 1; kwargs...)
end

"""Construct the eleven-halves-ratio hypocycloid."""
function eleven_half_hypocycloid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    center, fixed_radius::Real; kwargs...)
    hypocycloid!(runtime, state_ptr, center, fixed_radius, 11 // 2; kwargs...)
end

"""Construct the two-cusped external nephroid."""
function nephroid!(runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    center, fixed_radius::Real; kwargs...)
    radius = validated_positive_parameter("fixed_radius", fixed_radius)
    rational_trochoid!(runtime, state_ptr, center, :external,
        radius, 2 // 1, radius / 2f0; kwargs...)
end

"""Construct the external three-dimple epicycloid family."""
function three_dimple_epitrochoid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, center,
    fixed_radius::Real, tracer_distance::Real; kwargs...)
    rational_trochoid!(runtime, state_ptr, center, :external,
        fixed_radius, 3 // 1, tracer_distance; kwargs...)
end

"""Construct the five-point hypotrochoid with the authored tracer distance."""
function five_point_hypotrochoid!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, center,
    fixed_radius::Real; kwargs...)
    rational_trochoid!(runtime, state_ptr, center, :internal,
        fixed_radius, 5 // 3, fixed_radius; kwargs...)
end

"""Construct a finite open parabola and animate its integrated instrument."""
function parabola!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    vertex::AbstractVector{<:Real}; focal_distance::Real,
    rotation::Real=0f0, parameter_start::Real=-1f0,
    parameter_finish::Real=1f0, draw_parameter::Real=parameter_finish,
    color=DEFAULT_COLOR, brush::Real=DEFAULT_BRUSH,
    duration::Real=DEFAULT_CURVE_DURATION)
    vertex3 = vec3("vertex", vertex)
    focal = validated_positive_parameter("focal_distance", focal_distance)
    rotation_value = validated_angle_theta(rotation)
    start, finish, frontier = validated_curve_domain(
        parameter_start, parameter_finish, draw_parameter)
    extent = max(abs(Float64(start)), abs(Float64(finish)))
    link_length = Float32(1.02 * Float64(focal) * sqrt(1 + extent^2))
    isfinite(link_length) && link_length > 0f0 ||
        throw(ArgumentError("parabola link length is not finite"))
    brush_value = validated_brush(brush)
    draw_duration = validated_duration(duration)
    shape_color = OdinJuliaBridge._shape_color(color)
    session = ensure_session!(runtime)
    require_action_capacity(session)
    result = checked_constructor_result(OdinJuliaBridge.create_new_parabola(
        state_ptr, vertex3; focal_distance=focal, rotation=rotation_value,
        parameter_start=start, parameter_finish=finish,
        draw_parameter=frontier, color=shape_color, brush_size=brush_value),
        "parabola")
    payload = ParabolaPayload(result.host_id, vertex3, focal, rotation_value,
        start, finish, frontier, link_length, shape_color, brush_value)
    start_job!(runtime, state_ptr, ReplDrawJob(:parabola, draw_duration, 0f0, payload))
    track_managed_host!(session, result.host_id)
    return result
end

"""Construct a one-host hyperbola with immutable branch selection."""
function hyperbola!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    center::AbstractVector{<:Real}; semimajor::Real, semiminor::Real,
    branches::Symbol=:both, rotation::Real=0f0,
    parameter_start::Real=-1f0, parameter_finish::Real=1f0,
    draw_parameter::Real=parameter_finish,
    rail_half_length::Union{Nothing,Real}=nothing, color=DEFAULT_COLOR,
    brush::Real=DEFAULT_BRUSH, duration::Real=DEFAULT_CURVE_DURATION)
    center3 = vec3("center", center)
    major = validated_positive_parameter("semimajor", semimajor)
    minor = validated_positive_parameter("semiminor", semiminor)
    rotation_value = validated_angle_theta(rotation)
    start, finish, frontier = validated_curve_domain(
        parameter_start, parameter_finish, draw_parameter)
    extent = max(abs(Float64(start)), abs(Float64(finish)))
    extent <= 4 || throw(ArgumentError("hyperbola parameter magnitude must not exceed 4"))
    required_rail = hypot(Float64(major) * cosh(extent),
        Float64(minor) * sinh(extent))
    isfinite(required_rail) ||
        throw(ArgumentError("hyperbola carriage extent is not finite"))
    rail = rail_half_length === nothing ? Float32(1.01 * required_rail) :
        validated_positive_parameter("rail_half_length", rail_half_length)
    Float64(rail) >= required_rail ||
        throw(ArgumentError("rail_half_length must contain both hyperbola carriages"))
    OdinJuliaBridge.hyperbola_branches(branches)
    brush_value = validated_brush(brush)
    draw_duration = validated_duration(duration)
    shape_color = OdinJuliaBridge._shape_color(color)
    session = ensure_session!(runtime)
    require_action_capacity(session)
    result = checked_constructor_result(OdinJuliaBridge.create_new_hyperbola(
        state_ptr, center3; semimajor=major, semiminor=minor,
        rotation=rotation_value, parameter_start=start,
        parameter_finish=finish, draw_parameter=frontier,
        color=shape_color, brush_size=brush_value, branches),
        "hyperbola")
    payload = HyperbolaPayload(result.host_id, center3, major, minor,
        rotation_value, start, finish, frontier, rail, branches,
        shape_color, brush_value)
    start_job!(runtime, state_ptr, ReplDrawJob(:hyperbola, draw_duration, 0f0, payload))
    track_managed_host!(session, result.host_id)
    return result
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

"""Queue a coordinated defining-point rotation about a supplied world-Z line."""
function rotate_defining_points_z!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, point_ids,
    theta::Real, pivot::AbstractVector{<:Real}; duration::Real=DEFAULT_TRANSFORM_DURATION)
    ids = validated_point_ids(point_ids)
    pivot3 = vec3("pivot", pivot)
    starts = [Float32[0f0, 0f0, 0f0] for _ in ids]
    axis_end = Float32[pivot3[1], pivot3[2], pivot3[3] + 1f0]
    return rotate_points!(runtime, state_ptr, ids, starts, pivot3, axis_end,
        theta; duration)
end

"""Queue a supported planar rotation for a shape's defining points."""
function rotate_z!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    shape::OdinJuliaBridge.BridgeShapeLine, theta::Real;
    pivot::AbstractVector{<:Real}, duration::Real=DEFAULT_TRANSFORM_DURATION)
    rotate_defining_points_z!(runtime, state_ptr, line_endpoint_ids(shape),
        theta, pivot; duration)
end

"""Queue a supported planar rotation for a polygon's ordered defining points."""
function rotate_z!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    shape::Union{OdinJuliaBridge.BridgeShapeTriangle,
        OdinJuliaBridge.BridgeShapeSquare,OdinJuliaBridge.BridgeShapePentagon},
    theta::Real; pivot::AbstractVector{<:Real},
    duration::Real=DEFAULT_TRANSFORM_DURATION)
    rotate_defining_points_z!(runtime, state_ptr, polygon_vertex_ids(shape),
        theta, pivot; duration)
end

"""Queue a planar rotation of both defining centers of a lens or lune."""
function rotate_z!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    shape::OdinJuliaBridge.BridgeShapeCircleRegion, theta::Real;
    pivot::AbstractVector{<:Real}, duration::Real=DEFAULT_TRANSFORM_DURATION)
    rotate_defining_points_z!(runtime, state_ptr,
        circle_region_center_ids(shape), theta, pivot; duration)
end

"""Queue a planar rotation of both defining rail endpoints of a Cycloid."""
function rotate_z!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    shape::OdinJuliaBridge.BridgeShapeCycloidResult, theta::Real;
    pivot::AbstractVector{<:Real}, duration::Real=DEFAULT_TRANSFORM_DURATION)
    shape.status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        throw(ArgumentError("Cycloid result is not successful"))
    rotate_defining_points_z!(runtime, state_ptr,
        (shape.first_id, shape.second_id), theta, pivot; duration)
end

"""Admit an activation-sampled planar rotation of one analytic shape host."""
function queue_analytic_rotation!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid}, status::Int32,
    host_id::UInt64, kind::Symbol, theta::Real, pivot, duration::Real)
    status == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        throw(ArgumentError("analytic shape result is not successful"))
    session = ensure_session!(runtime)
    host_id in session.managed_host_ids ||
        throw(ArgumentError("rotate_z! requires a Terminal-managed shape"))
    theta32 = validated_angle_theta(theta)
    pivot3 = vec3("pivot", pivot)
    draw_duration = validated_duration(duration)
    require_action_capacity(session)
    payload = AnalyticRotationPayload(
        kind, host_id, pivot3, theta32, Float32[0f0, 0f0, 0f0], nothing)
    start_job!(runtime, state_ptr,
        ReplDrawJob(:analytic_rotation, draw_duration, 0f0, payload))
    return host_id
end

"""Rotate an arc or sector in its board plane, preserving radius and sweep."""
function rotate_z!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    shape::OdinJuliaBridge.BridgeShapeCircle, theta::Real;
    pivot::AbstractVector{<:Real}, duration::Real=DEFAULT_TRANSFORM_DURATION)
    queue_analytic_rotation!(runtime, state_ptr, shape.status, shape.host_id,
        :arc, theta, pivot, duration)
end

"""Rotate a trochoid family in its board plane without changing its parameterization."""
function rotate_z!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    shape::OdinJuliaBridge.BridgeShapeTrochoidResult, theta::Real;
    pivot::AbstractVector{<:Real}, duration::Real=DEFAULT_TRANSFORM_DURATION)
    queue_analytic_rotation!(runtime, state_ptr, shape.status, shape.host_id,
        :trochoid, theta, pivot, duration)
end

"""Rotate a parabola or hyperbola in its board plane without changing its frontier."""
function rotate_z!(
    runtime::EuclidReplRuntime, state_ptr::Ptr{Cvoid},
    shape::OdinJuliaBridge.BridgeShapeConicResult, theta::Real;
    pivot::AbstractVector{<:Real}, duration::Real=DEFAULT_TRANSFORM_DURATION)
    queue_analytic_rotation!(runtime, state_ptr, shape.status, shape.host_id,
        :conic, theta, pivot, duration)
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
