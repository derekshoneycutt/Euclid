using UUIDs

if !isdefined(Main, :EuclidRuntimeHost)
    include("../runtime_host.jl")
end

const RuntimeHostPointId = UUID("03bf688d-40d0-56a2-a6be-ca2656c9b10d")

"""Return the stable UUID registered for the generation's Terminal node."""
function runtime_host_terminal_id(host::EuclidRuntimeHost)::UUID
    generation = active_euclid_runtime_generation(host)
    descriptors = getfield(generation.animation_catalog, :AnimationDescriptors)
    terminal_kind = getfield(generation.animation_catalog, :TerminalNode)
    return only(descriptor.id for descriptor in descriptors
        if descriptor.kind === terminal_kind)
end

@testset "runtime host tick cadence" begin
    requested_ns = Ticks.interval_nanoseconds(1 / 60)
    @test Main.EuclidPolicy.tick_interval_steps(requested_ns) == UInt64(1)
    @test Float64(1) / Float64(Main.EuclidPolicy.TICK_FIXED_RATE_HZ) == 1 / 60
end

@testset "runtime host startup banner" begin
    banner = EuclidReplEvaluation.startup_banner_for_host()
    @test occursin(string(VERSION), banner)
    @test occursin('\e', banner)
end

@testset "native animation tick payload has stable isbits layout" begin
    @test isbitstype(NativeAnimationTickPayload)
    @test sizeof(NativeAnimationTickPayload) == 56
    @test isbitstype(NativeAnimationLifecyclePayload)
    @test sizeof(NativeAnimationLifecyclePayload) == 32
end

@testset "runtime host retires candidate generation roots" begin
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    active = active_euclid_runtime_generation(host)
    discarded = create_euclid_runtime_generation()
    @test stage_euclid_runtime_generation(host, discarded)
    @test host.candidate_generation === discarded
    @test discard_euclid_runtime_generation(host)
    @test host.active_generation === active
    @test host.candidate_generation === nothing

    committed = create_euclid_runtime_generation()
    @test stage_euclid_runtime_generation(host, committed)
    @test commit_euclid_runtime_generation(host, committed)
    @test host.active_generation === committed
    @test host.candidate_generation === nothing
    @test shutdown_euclid_reactor!(host)
end

@testset "runtime host activates Terminal through lifecycle supervisor" begin
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    terminal_id = runtime_host_terminal_id(host)
    payload = NativeAnimationLifecyclePayload(
        UInt64(70), UInt64(0), UInt64(1),
        Int32(EuclidPolicy.AnimationActivate))
    @test animation_host_lifecycle(host, payload, string(terminal_id)) ==
        ANIMATION_LIFECYCLE_NATIVE_RESET
    @test animation_host_acknowledge_reset(host, payload.request_id, true)
    supervisor = host.reactor.animation_supervisor_state
    @test supervisor.active_animation_id == terminal_id
    @test supervisor.active_animation_generation == UInt64(1)
    @test shutdown_euclid_reactor!(host)
end

@testset "runtime host routes ticks while preserving Terminal output" begin
    calls = Tuple{Ptr{Cvoid},Int32,Float32}[]
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    implementation = AnimationCatalog.AnimationImplementation(
        RuntimeHostPointId, (state_ptr, operation, dt) -> begin
            push!(calls, (state_ptr, operation, dt))
            true
        end)
    EuclidActorRuntime.emit!(host.reactor.actors,
        EuclidPolicy.SetTerminalVisibility(
            UInt64(9), true, EuclidPolicy.TerminalRectangle(
                0.0f0, 0.0f0, 1.0f0, 1.0f0)))
    payload = NativeAnimationTickPayload(
        UInt64(80), UInt64(0), UInt64(2), UInt64(1),
        Int32(0), UInt64(1), 0.25f0)
    @test animation_host_tick_with_implementation!(
        host, payload, RuntimeHostPointId, implementation)
    @test calls == [(Ptr{Cvoid}(1),
        OdinJuliaBridge.ANIMATION_OPERATION_TICK, 0.25f0)]
    @test any(command -> command isa EuclidPolicy.SetTerminalVisibility,
        host.reactor.actors.outgoing)
    @test host.reactor.animation_supervisor_state.active_animation_id ==
        RuntimeHostPointId
    @test shutdown_euclid_reactor!(host)
    @test length(calls) == 1
end

@testset "runtime host bounds unresolved animation correlation" begin
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    @test await_animation_result!(
        host, EuclidPolicy.AnimationTickCompleted, UInt64(999)) === nothing
    @test shutdown_euclid_reactor!(host)
end

@testset "runtime host does not restart a failed animation generation" begin
    calls = Ref(0)
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    implementation = AnimationCatalog.AnimationImplementation(
        RuntimeHostPointId, (_state_ptr, operation, _dt) -> begin
            operation == OdinJuliaBridge.ANIMATION_OPERATION_TICK &&
                (calls[] += 1)
            error("tick failed")
        end)
    first = NativeAnimationTickPayload(
        UInt64(90), UInt64(0), UInt64(3), UInt64(1),
        Int32(0), UInt64(1), 0.1f0)
    second = NativeAnimationTickPayload(
        UInt64(91), UInt64(0), UInt64(3), UInt64(2),
        Int32(0), UInt64(2), 0.1f0)
    @test !animation_host_tick_with_implementation!(
        host, first, RuntimeHostPointId, implementation)
    @test !animation_host_tick_with_implementation!(
        host, second, RuntimeHostPointId, implementation)
    @test calls[] == 1
    @test shutdown_euclid_reactor!(host)
end

@testset "application reactor fairly starts persistent roots" begin
    clock = EuclidActorRuntime.ManualClock(UInt64(0))
    actors = EuclidActorRuntime.ActorRuntime(clock=clock)
    host = create_euclid_runtime_host(
        Ptr{Cvoid}(1); actor_runtime=actors)
    reactor = host.reactor

    @test reactor.actors === actors
    @test reactor.animation_supervisor_state.active_runtime_generation ==
        UInt64(0)
    @test EuclidActorRuntime.mailbox_depth(
        actors, reactor.animation_supervisor) == 1
    @test EuclidHost.send_animation_supervisor_for_host(
        reactor, EuclidPolicy.StartAnimationSupervisor()) ===
        EuclidActorRuntime.SendMailboxFull

    terminal_turn = EuclidHost.pump_for_host(
        reactor, Int32(1), UInt64(1_000_000_000))
    @test !terminal_turn.animation_ready
    @test terminal_turn.immediately_runnable
    @test terminal_turn.outgoing_available

    animation_turn = EuclidHost.pump_for_host(
        reactor, Int32(1), UInt64(1_000_000_000))
    @test animation_turn.animation_ready
    @test !animation_turn.animation_failed
    @test animation_turn.animation_queue_depth == Int32(0)
    @test animation_turn.animation_queue_high_water == Int32(1)
    @test animation_turn.animation_failure_count == UInt64(0)
    @test reactor.animation_outcomes_routed == UInt64(1)
    @test shutdown_euclid_reactor!(host)
    @test !EuclidActorRuntime.is_live(
        actors, reactor.animation_supervisor)
    @test !EuclidActorRuntime.is_live(
        actors, reactor.hotkey_controller)
    @test !EuclidActorRuntime.is_live(
        actors, reactor.terminal_controller)
    @test reactor.shutdown_phase === EuclidHost.HostShutdownComplete
    @test reactor.animation_outcomes_routed == UInt64(2)
end

@testset "application reactor reports animation supervisor failure" begin
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    reactor = host.reactor
    EuclidHost.pump_for_host(reactor, Int32(8), UInt64(1_000_000_000))
    @test EuclidActorRuntime.send!(
        reactor.actors, reactor.animation_supervisor, :unsupported) ===
        EuclidActorRuntime.SendAccepted

    status = EuclidHost.pump_for_host(
        reactor, Int32(1), UInt64(1_000_000_000))
    @test !status.animation_ready
    @test status.animation_failed
    @test status.animation_failure_count == UInt64(1)
    @test !status.healthy
    @test shutdown_euclid_reactor!(host)
end

@testset "application reactor reports animation program failure" begin
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    reactor = host.reactor
    state = reactor.animation_supervisor_state
    state.load_implementation = _id -> AnimationCatalog.AnimationImplementation(
        RuntimeHostPointId,
        (_state_ptr, operation, _dt) ->
            operation != OdinJuliaBridge.ANIMATION_OPERATION_TICK)
    empty!(state.implementation_cache)
    EuclidHost.pump_for_host(reactor, Int32(8), UInt64(1_000_000_000))
    EuclidActorRuntime.take_outgoing!(reactor.actors)
    @test EuclidHost.send_animation_supervisor_for_host(
        reactor, EuclidPolicy.ActivateAnimation(
            UInt64(1), UInt64(0), UInt64(1), RuntimeHostPointId,
            Ptr{Cvoid}(1))) === EuclidActorRuntime.SendAccepted
    EuclidHost.pump_for_host(reactor, Int32(8), UInt64(1_000_000_000))
    @test only(EuclidActorRuntime.take_outgoing!(reactor.actors)) isa
        EuclidPolicy.ResetNativeAnimationState
    @test EuclidHost.send_animation_supervisor_for_host(
        reactor, EuclidPolicy.NativeAnimationStateReset(
            UInt64(1), true)) === EuclidActorRuntime.SendAccepted
    EuclidHost.pump_for_host(reactor, Int32(8), UInt64(1_000_000_000))
    EuclidActorRuntime.take_outgoing!(reactor.actors)
    actor = something(state.active_program_actor)
    @test EuclidHost.send_animation_supervisor_for_host(
        reactor, EuclidPolicy.TickAnimation(
            UInt64(2), UInt64(0), UInt64(1), RuntimeHostPointId, actor,
            UInt64(1), EuclidPolicy.AnimationTickSlotHandle(
                Int32(0), UInt64(1)), 0.1f0)) ===
        EuclidActorRuntime.SendAccepted

    status = EuclidHost.pump_for_host(
        reactor, Int32(8), UInt64(1_000_000_000))
    @test status.animation_failed
    @test status.animation_failure_count == UInt64(1)
    @test !status.healthy
    @test shutdown_euclid_reactor!(host)
end

"""Drain one host evaluation through its terminal actor services."""
function drain_runtime_host_evaluation(host::EuclidRuntimeHost, request_id::UInt64)
    output = IOBuffer()
    reactor = host.reactor
    for _ in 1:4096
        pump_euclid_reactor!(host)
        command = EuclidHost.take_evaluation_for_host(reactor)
        command.kind == Int32(0) && continue
        command.kind == Int32(1) && print(output, command.text)
        if command.kind == Int32(2) && command.request_id == request_id
            return String(take!(output))
        end
    end
    error("runtime host evaluation did not complete within the bounded pump limit")
end

"""Drain one correlated completion command through the Terminal actor services."""
function drain_runtime_host_completion(
    host::EuclidRuntimeHost, request_id::UInt64)
    for _ in 1:4096
        pump_euclid_reactor!(host)
        command = EuclidHost.take_completion_for_host(host.reactor)
        command.kind == Int32(0) && continue
        command.request_id == request_id && return command
    end
    error("runtime host completion did not complete within the bounded pump limit")
end

"""Pump until the requested Terminal generation reports session readiness."""
function await_runtime_host_session(host::EuclidRuntimeHost, generation::UInt64)
    for _ in 1:4096
        pump_euclid_reactor!(host)
        command = EuclidHost.take_session_lifecycle_for_host(host.reactor)
        command.kind == Int32(1) && command.generation == generation && return true
    end
    return false
end

@testset "runtime host terminal completion" begin
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    @test start_euclid_terminal_session!(host, UInt64(4))
    @test await_runtime_host_session(host, UInt64(4))

    source = "α = printl"
    cursor_byte = Int32(ncodeunits(source))
    EuclidHost.ingest_completion_preview_for_host(
        host.reactor, UInt64(41), source, cursor_byte, UInt64(4))
    preview = drain_runtime_host_completion(host, UInt64(41))
    @test preview.kind == Int32(1)
    @test preview.found
    @test preview.replacement_start == Int32(ncodeunits("α = "))
    @test preview.replacement_end == cursor_byte
    @test preview.insertion == "println"
    @test !preview.show_candidates

    EuclidHost.ingest_completion_candidates_for_host(
        host.reactor, UInt64(42), "Base.", Int32(5), UInt64(4))
    candidates = drain_runtime_host_completion(host, UInt64(42))
    @test candidates.kind == Int32(1)
    @test !candidates.found
    @test candidates.show_candidates
    @test !isempty(candidates.insertion)

    @test close_euclid_terminal_session!(host, UInt64(4))
    while host.reactor.session.phase !== EuclidHost.HostSessionQuiescent
        pump_euclid_reactor!(host)
        EuclidActorRuntime.take_outgoing!(host.reactor.actors)
    end
    @test shutdown_euclid_reactor!(host)
end

@testset "runtime host terminal evaluation" begin
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    @test start_euclid_terminal_session!(host, UInt64(1))
    host.pending_terminal_evaluation = EuclidTerminalEvaluationRequest(
        UInt64(1), "1 + 1", Int32(0), UInt64(1))
    @test drain_runtime_host_evaluation(host, UInt64(1)) == "2\n"
    @test host.reactor.evaluator_state.runtime.active_stream === nothing
    @test close_euclid_terminal_session!(host, UInt64(1))
    while host.reactor.session.phase !== EuclidHost.HostSessionQuiescent
        pump_euclid_reactor!(host)
        EuclidActorRuntime.take_outgoing!(host.reactor.actors)
    end
    terminal = host.reactor.session.evaluator_state.runtime.terminal
    @test !isopen(terminal.input)
    @test !isopen(terminal.writer)
    @test shutdown_euclid_reactor!(host)
end

@testset "runtime generation isolation" begin
    first_generation = create_euclid_runtime_generation()
    second_generation = create_euclid_runtime_generation()

    first_implementation = load_generation_animation(
        first_generation, RuntimeHostPointId)
    second_implementation = load_generation_animation(
        second_generation, RuntimeHostPointId)
    first_module = getfield(first_generation.content, :ElementsOneDefinitionPoint)
    second_module = getfield(second_generation.content, :ElementsOneDefinitionPoint)

    @test first_implementation.id == RuntimeHostPointId
    @test second_implementation.id == RuntimeHostPointId
    @test first_module !== second_module
    @test parentmodule(first_module) === first_generation.content
    @test parentmodule(second_module) === second_generation.content

    state_ptr = Ptr{Cvoid}(1)
    host = create_euclid_runtime_host(state_ptr)
    host.active_generation = first_generation
    callback_ref = WeakRef(host.terminal_animation_callback)
    GC.gc(true)
    @test host.state_ptr == state_ptr
    @test host.active_generation === first_generation
    @test host.reactor.session.generation == UInt64(1)
    @test callback_ref.value === host.terminal_animation_callback
    @test getfield(host.active_generation.content,
        :ElementsOneDefinitionPoint) === first_module

    @test stage_euclid_runtime_generation(host, second_generation)
    @test commit_euclid_runtime_generation(host, second_generation)
    @test host.active_generation === second_generation

    other_host = create_euclid_runtime_host(Ptr{Cvoid}(2))
    @test other_host.reactor.session.euclid_repl_runtime !==
        host.reactor.session.euclid_repl_runtime
    @test_throws ArgumentError create_euclid_runtime_host(C_NULL)
    @test shutdown_euclid_reactor!(other_host)
    @test shutdown_euclid_reactor!(host)
end