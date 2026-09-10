using UUIDs

if !isdefined(Main, :EuclidRuntimeHost)
    include("../runtime_host.jl")
end

const RuntimeHostPointId = UUID("03bf688d-40d0-56a2-a6be-ca2656c9b10d")

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

"""Drain one host evaluation through its terminal actor services."""
function drain_runtime_host_evaluation(host::EuclidRuntimeHost, request_id::UInt64)
    output = IOBuffer()
    terminal = host.terminal
    for _ in 1:4096
        pump_euclid_terminal!(host)
        command = EuclidHost.take_evaluation_for_host(terminal)
        command.kind == Int32(0) && continue
        command.kind == Int32(1) && print(output, command.text)
        if command.kind == Int32(2) && command.request_id == request_id
            return String(take!(output))
        end
    end
    error("runtime host evaluation did not complete within the bounded pump limit")
end

@testset "runtime host terminal evaluation" begin
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    @test start_euclid_terminal_session!(host, UInt64(1))
    host.pending_terminal_evaluation = EuclidTerminalEvaluationRequest(
        UInt64(1), "1 + 1", Int32(0), UInt64(1))
    @test drain_runtime_host_evaluation(host, UInt64(1)) == "2\n"
    @test host.terminal.evaluator_state.runtime.active_stream === nothing
    @test close_euclid_terminal_session!(host, UInt64(1))
    while host.terminal.session.phase !== EuclidHost.HostSessionQuiescent
        pump_euclid_terminal!(host)
        EuclidActorRuntime.take_outgoing!(host.terminal.actors)
    end
    terminal = host.terminal.session.evaluator_state.runtime.terminal
    @test !isopen(terminal.input)
    @test !isopen(terminal.writer)
    @test shutdown_euclid_terminal!(host)
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
    @test host.terminal.session.generation == UInt64(1)
    @test callback_ref.value === host.terminal_animation_callback
    @test getfield(host.active_generation.content,
        :ElementsOneDefinitionPoint) === first_module

    @test commit_euclid_runtime_generation(host, second_generation)
    @test host.active_generation === second_generation

    other_host = create_euclid_runtime_host(Ptr{Cvoid}(2))
    @test other_host.terminal.session.euclid_repl_runtime !==
        host.terminal.session.euclid_repl_runtime
    @test_throws ArgumentError create_euclid_runtime_host(C_NULL)
    @test shutdown_euclid_terminal!(other_host)
    @test shutdown_euclid_terminal!(host)
end