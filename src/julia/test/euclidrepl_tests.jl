if !isdefined(Main, :OdinJuliaBridge)
    include("../odin-julia-bridge.jl")
end
if !isdefined(Main, :EuclidGeometry)
    include("../geometry.jl")
end
if !isdefined(Main, :EuclidAnimations)
    include("../animations.jl")
end
if !isdefined(Main, :Scratchpad)
    include("../scratchpad.jl")
end
if !isdefined(Main, :EuclidRepl)
    include("../euclidrepl.jl")
end

using .EuclidRepl
using Test

const TEST_STATE_PTR = Ptr{Cvoid}(0)

@testset "EuclidRepl validation" begin
    @test_throws ArgumentError EuclidRepl.validated_duration(0f0)
    @test_throws ArgumentError EuclidRepl.validated_duration(-1f0)
    @test_throws ArgumentError EuclidRepl.validated_duration(Inf32)

    @test_throws ArgumentError EuclidRepl.validated_brush(0f0)
    @test_throws ArgumentError EuclidRepl.validated_brush(-2f0)
    @test_throws ArgumentError EuclidRepl.validated_brush(Inf32)

    @test_throws ArgumentError EuclidRepl.validated_start_theta(Inf32)
    @test_throws ArgumentError EuclidRepl.validated_start_theta(NaN32)

    @test_throws ArgumentError EuclidRepl.validated_end_theta(NaN32)

    @test_throws ArgumentError EuclidRepl.vec3("bad", Float32[1f0, 2f0])
    @test_throws ArgumentError EuclidRepl.vec3("bad", Float32[1f0, Inf32, 3f0])

    @test EuclidRepl.effective_end_theta(0f0, Inf32) ≈ EuclidRepl.TWO_PI_F32
    @test EuclidRepl.effective_end_theta(0f0, 10f0) ≈ EuclidRepl.TWO_PI_F32
    @test EuclidRepl.effective_end_theta(0f0, 1f0) ≈ 1f0
end

@testset "EuclidRepl session lifecycle" begin
    EuclidRepl.reset_scratchpad_session!()

    state0 = EuclidRepl.status(TEST_STATE_PTR)
    @test state0.active == false
    @test state0.managed_shape_count == 0

    session = EuclidRepl.ensure_session!()
    @test EuclidRepl.stop!(TEST_STATE_PTR) == false
    @test EuclidRepl.clear!(TEST_STATE_PTR) == true

    # Simulate managed geometry bookkeeping in test-only state.
    push!(session.managed_host_ids, 1)
    push!(session.managed_host_ids, 2)
    @test EuclidRepl.status(TEST_STATE_PTR).managed_shape_count == 2

    @test EuclidRepl.clear!(TEST_STATE_PTR) == true
    @test EuclidRepl.status(TEST_STATE_PTR).managed_shape_count == 0

    EuclidRepl.reset_scratchpad_session!()
    state_after_reset = EuclidRepl.status(TEST_STATE_PTR)
    @test state_after_reset.active == false
    @test state_after_reset.managed_shape_count == 0
end

@testset "EuclidRepl preemption and status" begin
    EuclidRepl.reset_scratchpad_session!()

    session = EuclidRepl.ensure_session!()
    payload_a = EuclidRepl.PointPayload(1, Float32[0f0, 0f0, 0f0], :steelblue, 5f0)
    job_a = EuclidRepl.ReplDrawJob(:point, 0.5f0, 0.25f0, nothing, payload_a)

    payload_b = EuclidRepl.LinePayload(
        2,
        3,
        4,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 0f0, 0f0],
        :steelblue,
        5f0)
    job_b = EuclidRepl.ReplDrawJob(:line, 0.8f0, 0f0, nothing, payload_b)

    EuclidRepl.start_job!(TEST_STATE_PTR, job_a)
    s1 = EuclidRepl.status(TEST_STATE_PTR)
    @test s1.active == true
    @test s1.kind == :point

    EuclidRepl.start_job!(TEST_STATE_PTR, job_b)
    s2 = EuclidRepl.status(TEST_STATE_PTR)
    @test s2.active == true
    @test s2.kind == :line

    @test EuclidRepl.stop!(TEST_STATE_PTR) == true
    s3 = EuclidRepl.status(TEST_STATE_PTR)
    @test s3.active == false
end
