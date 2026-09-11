if !isdefined(Main, :EuclidHost)
    include("runtime.jl")
    include("terminal.jl")
    include("ticks.jl")
    include("terminal_container.jl")
    include("eval.jl")
    include("interpolation.jl")
    include("policy.jl")
    include("host.jl")
end

"""One independently owned generation of reloadable Euclid content."""
struct EuclidRuntimeGeneration
    content::Module
    animation_catalog::Module
    null_animation::Module
    harness_scenarios::Module
end

"""Julia runtime state owned and rooted by the native Julia worker."""
struct EuclidTerminalEvaluationRequest
    request_id::UInt64
    source::String
    mode::Int32
    generation::UInt64
end

"""Julia runtime state owned and rooted by the native Julia worker."""
mutable struct EuclidRuntimeHost
    state_ptr::Ptr{Cvoid}
    active_generation::Union{Nothing,EuclidRuntimeGeneration}
    candidate_generation::Union{Nothing,EuclidRuntimeGeneration}
    reactor::EuclidHost.HostRuntime
    terminal_animation_callback::Function
    desired_terminal_generation::UInt64
    announced_terminal_generation::UInt64
    pending_terminal_evaluation::Union{Nothing,EuclidTerminalEvaluationRequest}
end

const OptionalActorRuntime = Union{Nothing,EuclidActorRuntime.ActorRuntime}
const ANIMATION_TICK_PUMP_LIMIT = 512
const ANIMATION_TICK_PUMP_TURNS = Int32(8)
const ANIMATION_TICK_PUMP_BUDGET_NS = UInt64(500_000)
const ANIMATION_LIFECYCLE_FAILED = Int32(0)
const ANIMATION_LIFECYCLE_NATIVE_RESET = Int32(1)
const ANIMATION_LIFECYCLE_COMPLETED = Int32(2)

"""Primitive-only tick payload transferred directly from native storage."""
struct NativeAnimationTickPayload
    request_id::UInt64
    runtime_generation::UInt64
    animation_generation::UInt64
    sequence::UInt64
    slot_index::Int32
    reservation_generation::UInt64
    dt::Float32
end

"""Primitive-only lifecycle request transferred directly from native storage."""
struct NativeAnimationLifecyclePayload
    request_id::UInt64
    runtime_generation::UInt64
    animation_generation::UInt64
    operation::Int32
end

"""Create the Julia runtime host whose lifetime is owned by the native worker."""
function create_euclid_runtime_host(
    state_ptr::Ptr{Cvoid};
    actor_runtime::OptionalActorRuntime=nothing)::EuclidRuntimeHost
    state_ptr == C_NULL && throw(ArgumentError("state_ptr must not be null"))
    generation = create_euclid_runtime_generation()
    terminal_animation_callback = (callback_state_ptr, operation, dt) ->
        terminal_animation_entry(state_ptr, callback_state_ptr, operation, dt)
    reactor = EuclidHost.create_host_runtime(
        state_ptr, 0.0f0, 0.0f0;
        session_generation=UInt64(1),
        animation_runtime_generation=UInt64(0),
        animation_implementation_loader=(id ->
            load_generation_animation_implementation(
                generation, terminal_animation_callback, id)),
        actor_runtime)
    return EuclidRuntimeHost(
        state_ptr, generation, nothing, reactor,
        terminal_animation_callback,
        UInt64(1), UInt64(0), nothing)
end

"""Root one uncommitted content generation until native publication resolves."""
function stage_euclid_runtime_generation(
    host::EuclidRuntimeHost,
    generation::EuclidRuntimeGeneration)::Bool
    host.candidate_generation === nothing || return false
    host.candidate_generation = generation
    return true
end

"""Retire the rooted candidate after native rollback."""
function discard_euclid_runtime_generation(host::EuclidRuntimeHost)::Bool
    host.candidate_generation = nothing
    return true
end

"""Validate one bridge-stable lifecycle operation for the Terminal animation."""
function terminal_animation_entry(
    expected_state_ptr::Ptr{Cvoid}, state_ptr::Ptr{Cvoid},
    operation::Int32, dt::Float32)::Bool

    state_ptr == expected_state_ptr || return false
    dt >= 0 || return false
    return operation == OdinJuliaBridge.ANIMATION_OPERATION_ENTER ||
        operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK ||
        operation == OdinJuliaBridge.ANIMATION_OPERATION_EXIT
end

"""Request one generation-scoped Terminal session through orderly replacement."""
function start_euclid_terminal_session!(
    host::EuclidRuntimeHost, generation::UInt64)::Bool
    generation > 0 || return false
    host.desired_terminal_generation = generation
    session = host.reactor.session
    if session.generation == generation &&
        session.phase === EuclidHost.HostSessionActive
        if host.announced_terminal_generation != generation
            EuclidActorRuntime.emit!(
                host.reactor.actors,
                EuclidHost.JuliaSessionStarted(generation))
            host.announced_terminal_generation = generation
        end
        return true
    end
    session.phase === EuclidHost.HostSessionActive &&
        EuclidHost.close_session_for_host(host.reactor, session.generation)
    return true
end

"""Retire one matching Terminal generation without exposing replacement state."""
function close_euclid_terminal_session!(
    host::EuclidRuntimeHost, generation::UInt64)::Bool
    host.desired_terminal_generation == generation &&
        (host.desired_terminal_generation = UInt64(0))
    session = host.reactor.session
    session.generation == generation || return false
    session.phase === EuclidHost.HostSessionActive || return true
    return EuclidHost.close_session_for_host(host.reactor, generation)
end

"""Pump bounded application actor work and install a requested Terminal successor."""
function pump_euclid_reactor!(host::EuclidRuntimeHost)::Bool
    status = EuclidHost.pump_for_host(
        host.reactor, Int32(8), UInt64(500_000))
    session = host.reactor.session
    desired = host.desired_terminal_generation
    if desired > session.generation &&
        session.phase === EuclidHost.HostSessionQuiescent
        EuclidHost.start_session_for_host(host.reactor, desired)
        host.announced_terminal_generation = desired
    end
    pending = host.pending_terminal_evaluation
    session = host.reactor.session
    if pending !== nothing && session.generation == pending.generation &&
        session.phase === EuclidHost.HostSessionActive
        host.pending_terminal_evaluation = nothing
        EuclidHost.ingest_evaluation_for_host(
            host.reactor, pending.request_id, pending.source,
            pending.mode, pending.generation)
    end
    return status.immediately_runnable || status.outgoing_available
end

"""Take only the actor result matching one native animation request."""
function take_correlated_animation_result!(
    reactor::EuclidHost.HostRuntime, result_type, request_id::UInt64)
    index = findfirst(result -> result isa result_type &&
        result.request_id == request_id, reactor.actors.outgoing)
    index === nothing && return nothing
    return popat!(reactor.actors.outgoing, index)
end

"""Pump bounded turns until one exact animation result is available."""
function await_animation_result!(
    host::EuclidRuntimeHost, result_type, request_id::UInt64)
    for _ in 1:ANIMATION_TICK_PUMP_LIMIT
        EuclidHost.pump_for_host(
            host.reactor, ANIMATION_TICK_PUMP_TURNS,
            ANIMATION_TICK_PUMP_BUDGET_NS)
        result = take_correlated_animation_result!(
            host.reactor, result_type, request_id)
        result === nothing || return result
    end
    return nothing
end

"""Wait for native reset work or terminal lifecycle completion."""
function await_animation_lifecycle_signal!(
    host::EuclidRuntimeHost, request_id::UInt64)::Int32
    for _ in 1:ANIMATION_TICK_PUMP_LIMIT
        EuclidHost.pump_for_host(
            host.reactor, ANIMATION_TICK_PUMP_TURNS,
            ANIMATION_TICK_PUMP_BUDGET_NS)
        reset = take_correlated_animation_result!(
            host.reactor, EuclidPolicy.ResetNativeAnimationState, request_id)
        reset === nothing || return ANIMATION_LIFECYCLE_NATIVE_RESET
        completed = take_correlated_animation_result!(
            host.reactor, EuclidPolicy.AnimationLifecycleCompleted, request_id)
        completed === nothing || return completed.succeeded ?
            ANIMATION_LIFECYCLE_COMPLETED : ANIMATION_LIFECYCLE_FAILED
    end
    return ANIMATION_LIFECYCLE_FAILED
end

"""Wait for the persistent animation supervisor to accept host commands."""
function await_animation_supervisor!(host::EuclidRuntimeHost)::Bool
    for _ in 1:ANIMATION_TICK_PUMP_LIMIT
        host.reactor.animation_ready && return true
        EuclidHost.pump_for_host(
            host.reactor, ANIMATION_TICK_PUMP_TURNS,
            ANIMATION_TICK_PUMP_BUDGET_NS)
    end
    return false
end

"""Resolve null, Terminal, or path-backed implementations for one generation."""
function load_generation_animation_implementation(
    generation::EuclidRuntimeGeneration, terminal_animation_callback::Function,
    animation_id::UUID)
    constructor = getfield(generation.animation_catalog, :AnimationImplementation)
    if animation_id == UUID(UInt128(0))
        return constructor(
            animation_id, getfield(generation.null_animation, :animation_entry))
    end
    descriptors = getfield(generation.animation_catalog, :AnimationDescriptors)
    descriptor = only(filter(candidate -> candidate.id == animation_id, descriptors))
    terminal_kind = getfield(generation.animation_catalog, :TerminalNode)
    descriptor.kind === terminal_kind &&
        return constructor(animation_id, terminal_animation_callback)
    return load_generation_animation(generation, animation_id)
end

"""Resolve the implementation used when adopting an animation for one tick."""
function load_tick_implementation(
    host::EuclidRuntimeHost, generation::EuclidRuntimeGeneration,
    animation_id::UUID)
    return load_generation_animation_implementation(
        generation, host.terminal_animation_callback, animation_id)
end

"""Return the actor mirroring the native program active for one tick."""
function adopt_animation_for_tick!(
    host::EuclidRuntimeHost, payload::NativeAnimationTickPayload,
    animation_id::UUID, implementation)
    state = host.reactor.animation_supervisor_state
    actor = state.active_program_actor
    current = actor !== nothing &&
        state.active_runtime_generation == payload.runtime_generation &&
        state.active_animation_generation == payload.animation_generation &&
        state.active_animation_id == animation_id &&
        EuclidActorRuntime.is_live(host.reactor.actors, actor)
    current && return actor
    await_animation_supervisor!(host) || return nothing
    command = EuclidPolicy.AdoptActiveAnimation(
        payload.request_id, payload.runtime_generation,
        payload.animation_generation, animation_id, host.state_ptr, implementation)
    outcome = EuclidHost.send_animation_supervisor_for_host(host.reactor, command)
    outcome === EuclidActorRuntime.SendAccepted ||
        error("animation supervisor mailbox invariant violated")
    adopted = await_animation_result!(
        host, EuclidPolicy.ActiveAnimationAdopted, payload.request_id)
    return adopted === nothing || !adopted.succeeded ?
        nothing : adopted.program_actor
end

"""Execute one tick with an implementation resolved by the owning generation."""
function animation_host_tick_with_implementation!(
    host::EuclidRuntimeHost, payload::NativeAnimationTickPayload,
    animation_id::UUID, implementation)::Bool
    actor = adopt_animation_for_tick!(host, payload, animation_id, implementation)
    actor === nothing && return false
    command = EuclidPolicy.TickAnimation(
        payload.request_id, payload.runtime_generation,
        payload.animation_generation, animation_id, actor, payload.sequence,
        EuclidPolicy.AnimationTickSlotHandle(
            payload.slot_index, payload.reservation_generation), payload.dt)
    outcome = EuclidHost.send_animation_supervisor_for_host(host.reactor, command)
    outcome === EuclidActorRuntime.SendAccepted ||
        error("animation supervisor mailbox invariant violated")
    completed = await_animation_result!(
        host, EuclidPolicy.AnimationTickCompleted, payload.request_id)
    completed !== nothing &&
        completed.reason === EuclidPolicy.AnimationMailboxFull &&
        error("animation program mailbox invariant violated")
    return completed !== nothing && completed.succeeded &&
        completed.runtime_generation == payload.runtime_generation &&
        completed.animation_generation == payload.animation_generation &&
        completed.animation_id == animation_id && completed.program_actor == actor &&
        completed.sequence == payload.sequence &&
        completed.slot.index == payload.slot_index &&
        completed.slot.reservation_generation == payload.reservation_generation
end

"""Execute one native-owned animation tick through the shared actor scheduler."""
function animation_host_tick(
    host::EuclidRuntimeHost, payload::NativeAnimationTickPayload,
    stable_id::AbstractString)::Bool
    animation_id = UUID(String(stable_id))
    generation = active_euclid_runtime_generation(host)
    implementation = load_tick_implementation(host, generation, animation_id)
    return animation_host_tick_with_implementation!(
        host, payload, animation_id, implementation)
end

"""Begin one correlated animation lifecycle transaction."""
function animation_host_lifecycle(
    host::EuclidRuntimeHost, payload::NativeAnimationLifecyclePayload,
    stable_id::AbstractString)::Int32
    await_animation_supervisor!(host) || return ANIMATION_LIFECYCLE_FAILED
    animation_id = UUID(String(stable_id))
    state = host.reactor.animation_supervisor_state
    actor = state.active_program_actor
    command = if payload.operation == Int32(EuclidPolicy.AnimationActivate)
        EuclidPolicy.ActivateAnimation(
            payload.request_id, payload.runtime_generation,
            payload.animation_generation, animation_id, host.state_ptr)
    elseif payload.operation == Int32(EuclidPolicy.AnimationReset) &&
        actor !== nothing
        EuclidPolicy.ResetAnimation(
            payload.request_id, payload.runtime_generation,
            state.active_animation_generation,
            payload.animation_generation, actor)
    elseif payload.operation == Int32(EuclidPolicy.AnimationReload)
        candidate = host.candidate_generation
        candidate === nothing && return ANIMATION_LIFECYCLE_FAILED
        EuclidPolicy.ReloadAnimation(
            payload.request_id, payload.runtime_generation,
            payload.runtime_generation + UInt64(1),
            state.active_animation_generation, payload.animation_generation,
            animation_id,
            id -> load_generation_animation_implementation(
                candidate, host.terminal_animation_callback, id))
    else
        return ANIMATION_LIFECYCLE_FAILED
    end
    outcome = EuclidHost.send_animation_supervisor_for_host(host.reactor, command)
    outcome === EuclidActorRuntime.SendAccepted ||
        return ANIMATION_LIFECYCLE_FAILED
    return await_animation_lifecycle_signal!(host, payload.request_id)
end

"""Acknowledge native reset work and await exact lifecycle completion."""
function animation_host_acknowledge_reset(
    host::EuclidRuntimeHost, request_id::UInt64, accepted::Bool)::Bool
    outcome = EuclidHost.send_animation_supervisor_for_host(
        host.reactor,
        EuclidPolicy.NativeAnimationStateReset(request_id, accepted))
    outcome === EuclidActorRuntime.SendAccepted || return false
    return await_animation_lifecycle_signal!(host, request_id) ==
        ANIMATION_LIFECYCLE_COMPLETED
end

"""Close and cooperatively drain application actors before Julia exits."""
function shutdown_euclid_reactor!(host::EuclidRuntimeHost)::Bool
    host.desired_terminal_generation = UInt64(0)
    EuclidHost.request_shutdown_for_host(host.reactor)
    for _ in 1:4096
        status = EuclidHost.pump_for_host(
            host.reactor, Int32(8), UInt64(500_000))
        EuclidActorRuntime.take_outgoing!(host.reactor.actors)
        if status.shutdown_ready &&
            host.reactor.evaluator_state.runtime.active_stream === nothing
            EuclidReplEvaluation.close_interactive_terminal!(
                host.reactor.evaluator_state.runtime.terminal)
            return true
        end
    end
    return false
end

"""Return whether a native-owned host reference has the expected runtime type."""
function is_euclid_runtime_host(host)::Bool
    return host isa EuclidRuntimeHost
end

"""Create one fresh module that owns all reloadable content for a generation."""
function create_euclid_runtime_generation(
    source_root::AbstractString=@__DIR__)::EuclidRuntimeGeneration

    root = abspath(String(source_root))
    content = Module(gensym(:EuclidRuntimeContent), false, false)
    Core.eval(content, :(const OdinJuliaBridge = $OdinJuliaBridge))
    Core.eval(content, :(const EuclidAnimations = $EuclidAnimations))
    Core.eval(content, :(const EuclidGeometry = $EuclidGeometry))
    Core.eval(content, :(const EuclidLatex = $EuclidLatex))
    Base.include(content, joinpath(root, "animation_catalog.jl"))
    Base.include(content, joinpath(root, "nullanimation.jl"))
    Base.include(content, joinpath(root, "harness_scenarios.jl"))
    return EuclidRuntimeGeneration(
        content,
        Base.invokelatest(getfield, content, :AnimationCatalog),
        Base.invokelatest(getfield, content, :NullAnimation),
        Base.invokelatest(getfield, content, :EuclidHarnessScenarios))
end

"""Load one animation into the content module owned by a generation."""
function load_generation_animation(
    generation::EuclidRuntimeGeneration, id)::Any

    loader = getfield(generation.animation_catalog, :ensure_animation_loaded)
    return Base.invokelatest(loader, generation.content, id)
end

"""Return the committed generation owned by a valid runtime host."""
function active_euclid_runtime_generation(
    host::EuclidRuntimeHost)::EuclidRuntimeGeneration

    generation = host.active_generation
    generation === nothing && error("Euclid runtime host has no active generation")
    return generation
end

"""Commit one validated generation as the host's sole active content owner."""
function commit_euclid_runtime_generation(
    host::EuclidRuntimeHost,
    generation::EuclidRuntimeGeneration)::Bool

    host.candidate_generation === generation || return false
    host.active_generation = generation
    host.candidate_generation = nothing
    return true
end