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
    terminal::EuclidHost.HostRuntime
    terminal_animation_callback::Function
    desired_terminal_generation::UInt64
    announced_terminal_generation::UInt64
    pending_terminal_evaluation::Union{Nothing,EuclidTerminalEvaluationRequest}
end

"""Create the Julia runtime host whose lifetime is owned by the native worker."""
function create_euclid_runtime_host(state_ptr::Ptr{Cvoid})::EuclidRuntimeHost
    state_ptr == C_NULL && throw(ArgumentError("state_ptr must not be null"))
    terminal = EuclidHost.create_host_runtime(
        state_ptr, 0.0f0, 0.0f0; session_generation=UInt64(1))
    terminal_animation_callback = (callback_state_ptr, operation, dt) ->
        terminal_animation_entry(state_ptr, callback_state_ptr, operation, dt)
    return EuclidRuntimeHost(
        state_ptr, create_euclid_runtime_generation(), terminal,
        terminal_animation_callback,
        UInt64(1), UInt64(0), nothing)
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
    session = host.terminal.session
    if session.generation == generation &&
        session.phase === EuclidHost.HostSessionActive
        if host.announced_terminal_generation != generation
            EuclidActorRuntime.emit!(
                host.terminal.actors,
                EuclidHost.JuliaSessionStarted(generation))
            host.announced_terminal_generation = generation
        end
        return true
    end
    session.phase === EuclidHost.HostSessionActive &&
        EuclidHost.close_session_for_host(host.terminal, session.generation)
    return true
end

"""Retire one matching Terminal generation without exposing replacement state."""
function close_euclid_terminal_session!(
    host::EuclidRuntimeHost, generation::UInt64)::Bool
    host.desired_terminal_generation == generation &&
        (host.desired_terminal_generation = UInt64(0))
    session = host.terminal.session
    session.generation == generation || return false
    session.phase === EuclidHost.HostSessionActive || return true
    return EuclidHost.close_session_for_host(host.terminal, generation)
end

"""Pump bounded Terminal actor work and install a requested quiescent successor."""
function pump_euclid_terminal!(host::EuclidRuntimeHost)::Bool
    status = EuclidHost.pump_for_host(
        host.terminal, Int32(8), UInt64(500_000))
    session = host.terminal.session
    desired = host.desired_terminal_generation
    if desired > session.generation &&
        session.phase === EuclidHost.HostSessionQuiescent
        EuclidHost.start_session_for_host(host.terminal, desired)
        host.announced_terminal_generation = desired
    end
    pending = host.pending_terminal_evaluation
    session = host.terminal.session
    if pending !== nothing && session.generation == pending.generation &&
        session.phase === EuclidHost.HostSessionActive
        host.pending_terminal_evaluation = nothing
        EuclidHost.ingest_evaluation_for_host(
            host.terminal, pending.request_id, pending.source,
            pending.mode, pending.generation)
    end
    return status.immediately_runnable || status.outgoing_available
end

"""Close and cooperatively drain the Terminal actor generation before Julia exits."""
function shutdown_euclid_terminal!(host::EuclidRuntimeHost)::Bool
    host.desired_terminal_generation = UInt64(0)
    EuclidHost.request_shutdown_for_host(host.terminal)
    for _ in 1:4096
        status = EuclidHost.pump_for_host(
            host.terminal, Int32(8), UInt64(500_000))
        EuclidActorRuntime.take_outgoing!(host.terminal.actors)
        if !status.immediately_runnable &&
            EuclidActorRuntime.pending_request_count(
                host.terminal.actors) == 0 &&
            host.terminal.evaluator_state.runtime.active_stream === nothing
            EuclidReplEvaluation.close_interactive_terminal!(
                host.terminal.evaluator_state.runtime.terminal)
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

    host.active_generation = generation
    return true
end