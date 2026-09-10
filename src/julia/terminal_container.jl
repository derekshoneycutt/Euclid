module TerminalContainer

import ..EuclidActorRuntime: ActorId

export Change, ChangeCause, Color, Config, ConfigurationRejection
export ConfigurationResult, Dimensions, MoveMode, Rectangle, ResizeAxes
export Subscription, TerminalContainerError, configure!, subscribe, unsubscribe!

const CONTAINER_CONTEXT_KEY = :euclid_terminal_container_client
const CONTAINER_REQUEST_CAPACITY = 64

Base.@enum MoveMode::UInt8 begin
    MoveDisabled = 0
    MoveHandle = 1
end

Base.@enum ResizeAxes::UInt8 begin
    ResizeNone = 0
    ResizeHorizontal = 1
    ResizeVertical = 2
    ResizeBoth = 3
end

Base.@enum ChangeCause::Int32 begin
    Moved = 1
    Resized = 2
    Configuration = 3
    WindowConstraint = 4
end

Base.@enum ConfigurationRejection::Int32 begin
    ConfigurationAccepted = 0
    InvalidGeneration = 1
    InvalidRectangle = 2
    InvalidChrome = 3
    InvalidDimensionLimits = 4
    InvalidAllowedBounds = 5
    InitialBoundsTooSmall = 6
    UnsupportedMoveMode = 7
    UnsupportedResizeAxes = 8
    ConfigurationBusy = 9
end

"""Portable RGBA color used by terminal-container configuration."""
struct Color
    red::UInt8
    green::UInt8
    blue::UInt8
    alpha::UInt8
end

"""Pixel-space terminal-container bounds."""
struct Rectangle
    x::Float32
    y::Float32
    width::Float32
    height::Float32
end

"""Positive terminal viewport size measured in character cells."""
struct Dimensions
    columns::UInt16
    rows::UInt16
end

"""Complete generation-versioned terminal-container configuration."""
struct Config
    generation::UInt64
    background::Color
    foreground::Color
    border_color::Color
    border_width::Float32
    resize_hit_width::Float32
    handle_height::Float32
    move_mode::MoveMode
    resize_axes::ResizeAxes
    initial_bounds::Rectangle
    allowed_bounds::Rectangle
    minimum_dimensions::Dimensions
    maximum_dimensions::Dimensions
end

"""Native outcome for one terminal-container configuration generation."""
struct ConfigurationResult
    generation::UInt64
    accepted::Bool
    reason::ConfigurationRejection
    effective_bounds::Rectangle
    constrained::Bool
end

"""One committed terminal-container bounds fact delivered to subscribers."""
struct Change
    session_generation::UInt64
    bounds_generation::UInt64
    interaction_id::UInt64
    cause::ChangeCause
    resize_edges::UInt8
    previous::Rectangle
    current::Rectangle
    dimensions::Dimensions
    constrained::Bool
end

"""Public error raised when container service work cannot be admitted."""
struct TerminalContainerError <: Exception
    message::String
end

"""Generation-safe handle for one session-owned actor subscription."""
mutable struct Subscription
    id::UInt64
    generation::UInt64
    active::Bool
    client::Any
end

"""Request to attach one actor to the session container service."""
struct SubscribeRequest
    actor::ActorId
    subscription::Subscription
    admission::Channel{Any}
end

"""Request idempotent removal of one actor subscription."""
struct UnsubscribeRequest
    subscription::Subscription
end

"""Request publication of one complete native container configuration."""
struct ConfigureRequest
    config::Config
    admission::Channel{Any}
end

"""Bounded request broker shared by evaluations and one container service."""
mutable struct Client
    requests::Channel{Any}
    generation::UInt64
    next_subscription_id::UInt64
    accepting::Bool
end

"""Create an accepting client for one nonzero Julia session generation."""
function Client(generation::UInt64)
    generation > 0 || throw(ArgumentError(
        "terminal container client generation must be nonzero"))
    return Client(Channel{Any}(CONTAINER_REQUEST_CAPACITY), generation,
        UInt64(1), true)
end

"""Render one public container error without exposing service internals."""
function Base.showerror(io::IO, error::TerminalContainerError)
    print(io, error.message)
end

"""Run an operation with container authority scoped to the current evaluation."""
function with_client(operation, client::Client)
    return task_local_storage(operation, CONTAINER_CONTEXT_KEY, client)
end

"""Return the active evaluation's container broker or reject unsupported use."""
function current_client()::Client
    client = get(task_local_storage(), CONTAINER_CONTEXT_KEY, nothing)
    client isa Client || throw(TerminalContainerError(
        "terminal container operations require an active Euclid evaluation"))
    client.accepting || throw(TerminalContainerError(
        "terminal container service is stopping"))
    return client
end

"""Return whether one rectangle has finite coordinates and positive extent."""
function rectangle_valid(rectangle::Rectangle)::Bool
    return isfinite(rectangle.x) && isfinite(rectangle.y) &&
        isfinite(rectangle.width) && isfinite(rectangle.height) &&
        rectangle.width > 0 && rectangle.height > 0
end

"""Reject non-finite or negative terminal container chrome dimensions."""
function validate_chrome(config::Config)::Nothing
    all(isfinite, (config.border_width, config.resize_hit_width,
        config.handle_height)) || throw(ArgumentError(
        "terminal container chrome values must be finite"))
    config.border_width >= 0 && config.resize_hit_width >= 0 &&
        config.handle_height >= 0 || throw(ArgumentError(
        "terminal container chrome values must be nonnegative"))
    return nothing
end

"""Reject terminal container cell bounds that are empty or inverted."""
function validate_dimensions(config::Config)::Nothing
    config.minimum_dimensions.columns > 0 &&
        config.minimum_dimensions.rows > 0 || throw(ArgumentError(
        "terminal container minimum dimensions must be positive"))
    config.maximum_dimensions.columns >= config.minimum_dimensions.columns &&
        config.maximum_dimensions.rows >= config.minimum_dimensions.rows ||
        throw(ArgumentError(
            "terminal container maximum dimensions must include the minimum"))
    return nothing
end

"""Reject malformed values before publishing a complete configuration."""
function validate_config(config::Config)::Nothing
    config.generation > 0 || throw(ArgumentError(
        "terminal container configuration generation must be nonzero"))
    rectangle_valid(config.initial_bounds) || throw(ArgumentError(
        "terminal container initial bounds must be finite and positive"))
    rectangle_valid(config.allowed_bounds) || throw(ArgumentError(
        "terminal container allowed bounds must be finite and positive"))
    validate_chrome(config)
    validate_dimensions(config)
    return nothing
end

"""Subscribe one live actor without transferring ownership of its lifetime."""
function subscribe(actor::ActorId)::Subscription
    client = current_client()
    subscription = Subscription(client.next_subscription_id,
        client.generation, true, client)
    client.next_subscription_id += 1
    admission = Channel{Any}(1)
    put!(client.requests, SubscribeRequest(actor, subscription, admission))
    result = take!(admission)
    result === nothing || throw(result)
    return subscription
end

"""Deactivate one subscription immediately and request idempotent cleanup."""
function unsubscribe!(subscription::Subscription)::Bool
    subscription.active || return false
    subscription.active = false
    client = subscription.client
    client isa Client && client.accepting &&
        put!(client.requests, UnsubscribeRequest(subscription))
    return true
end

"""Validate and publish one complete versioned container configuration."""
function configure!(config::Config)::UInt64
    validate_config(config)
    client = current_client()
    admission = Channel{Any}(1)
    put!(client.requests, ConfigureRequest(config, admission))
    result = take!(admission)
    result === nothing || throw(result)
    return config.generation
end

end