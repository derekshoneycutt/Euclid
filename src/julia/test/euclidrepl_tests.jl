if !isdefined(Main, :OdinJuliaBridge)
    include("../odin-julia-bridge.jl")
end
if !isdefined(Main, :EuclidGeometry)
    include("../geometry.jl")
end
if !isdefined(Main, :EuclidAnimations) ||
   !isdefined(Main.EuclidAnimations, :displacement_from_vector_and_length)
    include("../animations.jl")
end
if !isdefined(Main, :EuclidLatex)
    include("../latex.jl")
end
if !isdefined(Main, :Scratchpad)
    include("../scratchpad.jl")
end
if !isdefined(Main, :EuclidRepl)
    include("../euclidrepl.jl")
end

using .EuclidRepl
using Colors
using Test

const TEST_STATE_PTR = Ptr{Cvoid}(0)
const TEST_REPL_RUNTIME = Scratchpad.create_runtime_state()

@testset "EuclidRepl validation" begin
    @test_throws ArgumentError EuclidRepl.validated_duration(0f0)
    @test_throws ArgumentError EuclidRepl.validated_duration(-1f0)
    @test_throws ArgumentError EuclidRepl.validated_duration(Inf32)

    @test EuclidRepl.vec3("pos", Int[1, 2, 3]) == Float32[1f0, 2f0, 3f0]
    @test EuclidAnimations.displacement_from_vector_and_length(
        Int[1, 0, 0], 1) == Float32[1f0, 0f0, 0f0]

    @test_throws ArgumentError EuclidRepl.validated_brush(0f0)
    @test_throws ArgumentError EuclidRepl.validated_brush(-2f0)
    @test_throws ArgumentError EuclidRepl.validated_brush(Inf32)

    @test_throws ArgumentError EuclidRepl.validated_start_theta(Inf32)
    @test_throws ArgumentError EuclidRepl.validated_start_theta(NaN32)

    @test_throws ArgumentError EuclidRepl.validated_end_theta(NaN32)

    @test_throws ArgumentError EuclidRepl.validated_angle_theta(Inf32)
    @test_throws ArgumentError EuclidRepl.validated_angle_theta(NaN32)

    @test_throws ArgumentError EuclidRepl.validated_radius(0f0)
    @test_throws ArgumentError EuclidRepl.validated_radius(-1f0)
    @test_throws ArgumentError EuclidRepl.validated_radius(Inf32)

    @test_throws ArgumentError EuclidRepl.vec3("bad", Float32[1f0, 2f0])
    @test_throws ArgumentError EuclidRepl.vec3("bad", Float32[1f0, Inf32, 3f0])

    nested_positions = EuclidRepl.validated_start_positions([
        Float64[1.0, 2.0, 3.0],
        Float64[4.0, 5.0, 6.0],
    ])
    @test nested_positions == [
        Float32[1f0, 2f0, 3f0],
        Float32[4f0, 5f0, 6f0],
    ]

    flat_positions = EuclidRepl.validated_start_positions(
        Float64[1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
    @test flat_positions == [
        Float32[1f0, 2f0, 3f0],
        Float32[4f0, 5f0, 6f0],
    ]
    @test_throws ArgumentError EuclidRepl.validated_start_positions(
        Float64[1.0, 2.0, 3.0, 4.0])

    @test EuclidRepl.effective_end_theta(0f0, Inf32) ≈ EuclidRepl.TWO_PI_F32
    @test EuclidRepl.effective_end_theta(0f0, 10f0) ≈ EuclidRepl.TWO_PI_F32
    @test EuclidRepl.effective_end_theta(0f0, 1f0) ≈ 1f0
end

@testset "EuclidRepl hide helpers" begin
    point_view = OdinJuliaBridge.BridgePointView(
        0x0,
        7,
        0,
        0x0,
        0f0,
        0f0,
        0x0,
        (0f0, 0f0, 0f0),
        0x0,
        OdinJuliaBridge.BridgeColor(0, 0, 0, 0),
        0x0,
        OdinJuliaBridge.BridgeColor(0, 0, 0, 0),
        0x0,
        UInt32(0),
        Int32(0),
        0,
        0,
        0,
        0)
    line_shape = OdinJuliaBridge.BridgeShapeLine(11, 12, 13)
    circle_shape = OdinJuliaBridge.BridgeShapeCircle(21, 22, 23)
    filled_circle_shape = OdinJuliaBridge.BridgeShapeFilledCircle(31, 32, 33)

    @test isnothing(EuclidRepl.hide!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 5))
    @test isnothing(EuclidRepl.hide!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, point_view))
    @test isnothing(EuclidRepl.hide!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, line_shape))
    @test isnothing(EuclidRepl.hide!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, circle_shape))
    @test isnothing(EuclidRepl.hide!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, filled_circle_shape))
end

@testset "EuclidRepl color palette helpers" begin
    colors = EuclidRepl.euclidcolors()

    @test colors isa Vector{<:Colorant}
    @test length(colors) == 7
    @test colors[1] == parse(Colorant, "steelblue")
    @test colors[2] == parse(Colorant, "palevioletred1")
    @test colors[3] == parse(Colorant, "khaki3")
    @test colors[4] == parse(Colorant, "grey60")
    @test colors[5] == parse(Colorant, "plum1")
    @test colors[6] == parse(Colorant, "lightgreen")
    @test colors[7] == parse(Colorant, "firebrick")
end

@testset "EuclidRepl highlight APIs" begin
    EuclidRepl.reset_scratchpad_session!(TEST_REPL_RUNTIME)

    @test_throws ArgumentError EuclidRepl.highlight_pen!(
        TEST_REPL_RUNTIME,
        TEST_STATE_PTR,
        Float32[0f0, 0f0],
        Float32[1f0, 0f0, 0f0])

    @test_throws ArgumentError EuclidRepl.highlight_compass!(
        TEST_REPL_RUNTIME,
        TEST_STATE_PTR,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 0f0, 0f0],
        Inf32,
        1f0)

    @test_throws ArgumentError EuclidRepl.highlight_compass!(
        TEST_REPL_RUNTIME,
        TEST_STATE_PTR,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 0f0, 0f0],
        0.5f0,
        0f0)

    @test isnothing(EuclidRepl.highlight_pen!(
        TEST_REPL_RUNTIME,
        TEST_STATE_PTR,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 0f0, 0f0]))

    pen_status = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test pen_status.active == true
    @test pen_status.kind == :highlight_pen

    @test isnothing(EuclidRepl.highlight_compass!(
        TEST_REPL_RUNTIME,
        TEST_STATE_PTR,
        Float32[0f0, 0f0, 0f0],
        Float32[1f0, 0f0, 0f0],
        π / 2,
        1f0,
        filled=true))

    compass_status = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test compass_status.active == true
    @test compass_status.kind == :highlight_compass

    @test EuclidRepl.stop!(TEST_REPL_RUNTIME, TEST_STATE_PTR) == true
    @test EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR).active == false
end

@testset "EuclidRepl session lifecycle" begin
    EuclidRepl.reset_scratchpad_session!(TEST_REPL_RUNTIME)

    state0 = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test state0.active == false
    @test state0.managed_shape_count == 0

    session = EuclidRepl.ensure_session!(TEST_REPL_RUNTIME)
    @test EuclidRepl.stop!(TEST_REPL_RUNTIME, TEST_STATE_PTR) == false
    @test EuclidRepl.clear!(TEST_REPL_RUNTIME, TEST_STATE_PTR) == true

    # Simulate managed geometry bookkeeping in test-only state.
    push!(session.managed_host_ids, 1)
    push!(session.managed_host_ids, 2)
    @test EuclidRepl.status(
        TEST_REPL_RUNTIME, TEST_STATE_PTR).managed_shape_count == 2

    @test EuclidRepl.clear!(TEST_REPL_RUNTIME, TEST_STATE_PTR) == true
    @test EuclidRepl.status(
        TEST_REPL_RUNTIME, TEST_STATE_PTR).managed_shape_count == 0

    EuclidRepl.reset_scratchpad_session!(TEST_REPL_RUNTIME)
    state_after_reset = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test state_after_reset.active == false
    @test state_after_reset.managed_shape_count == 0
end

@testset "EuclidRepl preemption and status" begin
    EuclidRepl.reset_scratchpad_session!(TEST_REPL_RUNTIME)

    session = EuclidRepl.ensure_session!(TEST_REPL_RUNTIME)
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

    EuclidRepl.start_job!(TEST_REPL_RUNTIME, TEST_STATE_PTR, job_a)
    s1 = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test s1.active == true
    @test s1.kind == :point

    EuclidRepl.start_job!(TEST_REPL_RUNTIME, TEST_STATE_PTR, job_b)
    s2 = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test s2.active == true
    @test s2.kind == :line

    @test EuclidRepl.stop!(TEST_REPL_RUNTIME, TEST_STATE_PTR) == true
    s3 = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test s3.active == false
end
