using UUIDs

if !isdefined(Main, :EuclidRuntimeHost)
    include("../runtime_host.jl")
end

const RuntimeHostPointId = UUID("03bf688d-40d0-56a2-a6be-ca2656c9b10d")

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
    scratchpad = host.scratchpad
    session = Scratchpad.create_session(scratchpad, state_ptr, 41)
    scratchpad.current_session = session
    callback_ref = WeakRef(host.scratchpad.animation_callback)
    GC.gc(true)
    @test host.state_ptr == state_ptr
    @test host.active_generation === first_generation
    @test host.scratchpad === scratchpad
    @test host.scratchpad.current_session === session
    @test callback_ref.value === host.scratchpad.animation_callback
    @test getfield(host.active_generation.content,
        :ElementsOneDefinitionPoint) === first_module

    @test commit_euclid_runtime_generation(host, second_generation)
    @test host.active_generation === second_generation
    @test host.scratchpad === scratchpad
    @test host.scratchpad.current_session === session

    other_host = create_euclid_runtime_host(Ptr{Cvoid}(2))
    @test other_host.scratchpad !== host.scratchpad
    @test other_host.scratchpad.current_session === nothing
    @test_throws ArgumentError create_euclid_runtime_host(C_NULL)
end