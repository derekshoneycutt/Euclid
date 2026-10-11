"""Construct an explicit owned specification for non-native actor tests."""
function test_animation_content_value(
    animation_id::UUID=UUID(UInt128(0)), runtime_generation::UInt64=UInt64(1);
    edition_id="original-en-us", revision=UInt64(1), content_generation=UInt64(17))
    return OdinJuliaBridge.AnimationContentSpecification(
        "en-US", edition_id, "Test edition", "en-US", revision, animation_id,
        content_generation, runtime_generation)
end

"""Bind fixture copies instead of dereferencing synthetic native state pointers."""
function invoke_test_animation_content_entry(entry, state_ptr, command)::Bool
    value = test_animation_content_value(
        command.animation_id, command.runtime_generation)
    binding = OdinJuliaBridge.AnimationContentContext => (state_ptr, value)
    return Base.ScopedValues.with(binding) do
        Base.invokelatest(entry, state_ptr, command.operation, command.dt)
    end
end

@testset "animation content specification layout and constants" begin
    bridge = OdinJuliaBridge
    abi = bridge.AnimationContentSpecificationABI
    @test isbitstype(abi)
    @test sizeof(abi) == 440
    @test fieldoffset(abi, 9) == 400
    @test fieldoffset(abi, 10) == 408
    @test fieldoffset(abi, 11) == 424
    @test fieldoffset(abi, 12) == 432
    invocation = bridge.AnimationContentInvocationABI
    @test isbitstype(invocation)
    @test sizeof(invocation) == 40
    @test fieldoffset(invocation, 2) == 16
    @test fieldoffset(invocation, 3) == 24
    @test fieldoffset(invocation, 4) == 32
    @test bridge.ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED == Int32(4)
    @test bridge.BRIDGE_FEATURE_ANIMATION_CONTENT_SPECIFICATION == Int32(1 << 10)
    statuses = (
        bridge.ANIMATION_CONTENT_OK,
        bridge.ANIMATION_CONTENT_MISSING_INVOCATION_CONTEXT,
        bridge.ANIMATION_CONTENT_IDENTITY_MISMATCH,
        bridge.ANIMATION_CONTENT_MISSING_DEFAULT,
        bridge.ANIMATION_CONTENT_STALE_GENERATION,
        bridge.ANIMATION_CONTENT_INVALID_OUTPUT)
    @test statuses == UInt32.((0, 1, 2, 3, 4, 5))
    id = UUID("683b096d-5f64-50d2-9853-df907ca19075")
    bytes = ntuple(
        index -> UInt8((id.value >> (8 * (16 - index))) & 0xff), 16)
    @test bridge.animation_content_uuid(bytes) == id
    @test_throws bridge.AnimationContentQueryError bridge.animation_content_specification(
        C_NULL)
    for (bytes, length) in (((0xff,), 1), ((0x00,), 1), ((0x61,), 2))
        @test_throws bridge.AnimationContentQueryError bridge.animation_content_string(
            bytes, UInt16(length))
    end
end

@testset "invocation scope is immutable, nested, and cleared on failure" begin
    bridge = OdinJuliaBridge
    ptr = Ptr{Cvoid}(1)
    query = bridge.animation_content_specification
    old = test_animation_content_value()
    replacement = test_animation_content_value(UUID(UInt128(1)), UInt64(2);
        edition_id="elements-heath-adapted", revision=UInt64(2))
    Base.ScopedValues.with(bridge.AnimationContentContext => (ptr, old)) do
        @test bridge.animation_content_specification(ptr) === old
        @test bridge.animation_content_specification(ptr) === old
        @test_throws bridge.AnimationContentQueryError query(Ptr{Cvoid}(2))
        @test_throws ErrorException Base.ScopedValues.with(
            bridge.AnimationContentContext => (ptr, replacement)) do
            @test bridge.animation_content_specification(ptr) === replacement
            error("fixture callback failed")
        end
        @test bridge.animation_content_specification(ptr) === old
    end
    @test_throws bridge.AnimationContentQueryError bridge.animation_content_specification(
        ptr)
end

@testset "actor validates notices without changing sequence or active state" begin
    runtime = EuclidActorRuntime.ActorRuntime(
        clock=EuclidActorRuntime.ManualClock(UInt64(300)))
    supervisor = EuclidActorRuntime.spawn!(
        runtime, EuclidPolicy.AnimationSupervisor())
    id = UUID(UInt128(1))
    calls = Ref(0)
    entry = (_ptr, operation, _dt) -> begin
        calls[] += 1
        operation ==
            OdinJuliaBridge.ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED
    end
    program = EuclidPolicy.CompatibilityAnimationProgram(
        supervisor, id, entry, C_NULL, UInt64(2), UInt64(7), UInt64(19), true)
    actor = EuclidActorRuntime.spawn!(runtime, program; supervisor)
    key = EuclidPolicy.AnimationRequestKey(UInt64(44))
    command = EuclidPolicy.AnimationProgramCommand(
        key, UInt64(44), UInt64(2), UInt64(7), id,
        OdinJuliaBridge.ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED,
        UInt64(0), nothing, 37.0f0)
    @test EuclidPolicy.validate_program_command(program, command) === nothing
    EuclidActorRuntime.register_request!(runtime, key, actor)
    EuclidActorRuntime.send!(runtime, actor, command)
    drain_animation_actors!(runtime)
    @test calls[] == 1
    @test program.active
    @test program.last_sequence == 19
    @test EuclidActorRuntime.pending_request_count(runtime) == 0
    unknown = EuclidPolicy.AnimationProgramCommand(
        key, UInt64(44), UInt64(2), UInt64(7), id,
        Int32(99), UInt64(0), nothing, 0.0f0)
    @test_throws ArgumentError EuclidPolicy.validate_program_command(
        program, unknown)
    @test calls[] == 1
    program.active = false
    @test_throws ArgumentError EuclidPolicy.validate_program_command(
        program, command)
end
