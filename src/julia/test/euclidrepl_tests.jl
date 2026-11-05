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
if !isdefined(Main, :EuclidActorRuntime)
    include("../runtime.jl")
end
if !isdefined(Main, :Ticks)
    include("../ticks.jl")
end
if !isdefined(Main, :EuclidRepl)
    include("../euclidrepl.jl")
end

using .EuclidRepl
using Colors
using Test

@testset "Terminal tick cadence" begin
    requested_ns = Ticks.interval_nanoseconds(1 / 60)
    @test requested_ns == UInt64(16_666_666)
    @test Ticks.interval_nanoseconds(1e-12) == UInt64(1)
end

const TEST_STATE_PTR = Ptr{Cvoid}(0)
const TEST_REPL_RUNTIME = EuclidRepl.create_runtime()
const REPL_TEST_POSITIONS = Dict{UInt64,NTuple{3,Float32}}()
const REPL_TEST_KINDS = Dict{UInt64,Int32}()
const REPL_TEST_ORIENTATIONS = Dict{UInt64,NTuple{4,Float32}}()
const REPL_TEST_HIDDEN = UInt64[]
const REPL_TEST_SHOWN = UInt64[]
const REPL_TEST_REVEALED = UInt64[]
const REPL_TEST_FRONTIERS = Dict{UInt64,Float32}()

"""Return a copied native orientation for null-state motion fixtures."""
function OdinJuliaBridge.get_shape_orientation(state::Ptr{Cvoid}, id::UInt64)
    state == C_NULL || return OdinJuliaBridge.get_shape_orientation(state, Int(id))
    found = haskey(REPL_TEST_ORIENTATIONS, id)
    status = found ? OdinJuliaBridge.BRIDGE_STATUS_OK :
        OdinJuliaBridge.BRIDGE_STATUS_NOT_FOUND
    return OdinJuliaBridge.BridgeShapeOrientationResult(
        status, get(REPL_TEST_ORIENTATIONS, id, (0f0, 0f0, 0f0, 1f0)))
end

"""Record native orientation writes for null-state motion fixtures."""
function OdinJuliaBridge.set_shape_orientation(
    state::Ptr{Cvoid}, id::UInt64, orientation::NTuple{4,Float32})
    state == C_NULL ||
        return OdinJuliaBridge.set_shape_orientation(state, Int(id), orientation)
    haskey(REPL_TEST_ORIENTATIONS, id) || return OdinJuliaBridge.BRIDGE_STATUS_NOT_FOUND
    REPL_TEST_ORIENTATIONS[id] = orientation
    return OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Record exact Cycloid completion frontiers in the null-state fixture."""
function OdinJuliaBridge.set_cycloid_frontier(
    state::Ptr{Cvoid}, id::UInt64, frontier::Float32)
    state == C_NULL ||
        return OdinJuliaBridge.set_cycloid_frontier(state, Int(id), frontier)
    REPL_TEST_FRONTIERS[id] = frontier
    return OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Record exact trochoid completion frontiers in the null-state fixture."""
function OdinJuliaBridge.set_trochoid_frontier(
    state::Ptr{Cvoid}, id::UInt64, frontier::Float32)
    state == C_NULL ||
        return OdinJuliaBridge.set_trochoid_frontier(state, Int(id), frontier)
    REPL_TEST_FRONTIERS[id] = frontier
    return OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Record exact parabola completion frontiers in the null-state fixture."""
function OdinJuliaBridge.set_parabola_frontier(
    state::Ptr{Cvoid}, id::UInt64, frontier::Float32)
    state == C_NULL ||
        return OdinJuliaBridge.set_parabola_frontier(state, Int(id), frontier)
    REPL_TEST_FRONTIERS[id] = frontier
    return OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Record exact hyperbola completion frontiers in the null-state fixture."""
function OdinJuliaBridge.set_hyperbola_frontier(
    state::Ptr{Cvoid}, id::UInt64, frontier::Float32)
    state == C_NULL ||
        return OdinJuliaBridge.set_hyperbola_frontier(state, Int(id), frontier)
    REPL_TEST_FRONTIERS[id] = frontier
    return OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Accept completion visibility only for the null-state frontier fixture."""
function OdinJuliaBridge.show_point(state::Ptr{Cvoid}, id::UInt64)
    state == C_NULL || return OdinJuliaBridge.show_point(state, Int(id))
    push!(REPL_TEST_SHOWN, id)
    return OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Supply immutable native projections only for the null-state unit fixture."""
function OdinJuliaBridge.get_point(state::Ptr{Cvoid}, id::UInt64)
    state == C_NULL || return OdinJuliaBridge.get_point(state, Int(id))
    positioned = haskey(REPL_TEST_POSITIONS, id)
    found = positioned || haskey(REPL_TEST_KINDS, id)
    status = found ? OdinJuliaBridge.BRIDGE_STATUS_OK :
        OdinJuliaBridge.BRIDGE_STATUS_INVALID_INDEX
    return OdinJuliaBridge.BridgePointView(
        status, id, get(REPL_TEST_KINDS, id, OdinJuliaBridge.SHAPE_KIND_POINT),
        0, UInt8(positioned), 1, 0,
        get(REPL_TEST_POSITIONS, id, (0f0, 0f0, 0f0)),
        OdinJuliaBridge.BridgeColor(0, 0, 0, 0),
        OdinJuliaBridge.BridgeColor(0, 0, 0, 0), 0, 5f0, 0)
end

"""Record motion in the null-state fixture without replacing native non-null calls."""
function OdinJuliaBridge.set_point_position_status(
    state::Ptr{Cvoid}, id::UInt64, position)
    state == C_NULL ||
        return OdinJuliaBridge.set_point_position_status(state, Int(id), position)
    haskey(REPL_TEST_POSITIONS, id) || return OdinJuliaBridge.BRIDGE_STATUS_INVALID_INDEX
    REPL_TEST_POSITIONS[id] = Tuple(Float32.(position))
    return OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Record ordered visibility in the null-state fixture."""
function OdinJuliaBridge.hide_point(state::Ptr{Cvoid}, id::UInt64)
    state == C_NULL || return OdinJuliaBridge.hide_point(state, Int(id))
    haskey(REPL_TEST_POSITIONS, id) || return OdinJuliaBridge.BRIDGE_STATUS_INVALID_INDEX
    push!(REPL_TEST_HIDDEN, id)
    return OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Record one reveal request made by a polygon phase test."""
function record_test_region_reveal!(
    _state::Ptr{Cvoid}, id::UInt64, _duration::Real)
    push!(REPL_TEST_REVEALED, id)
    return OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Record action frames and activation order without invoking native tools."""
mutable struct ReplQueueTestPayload <: EuclidRepl.ReplDrawPayload
    identity::Int
    frames::Vector{Tuple{Int,Float32}}
    fail::Bool
end

"""Append each rendered frame or raise a deterministic execution failure."""
function EuclidRepl.render_payload!(
    ::Ptr{Cvoid}, elapsed::Real, _::Real, payload::ReplQueueTestPayload)
    payload.fail && error("fixture execution failed")
    push!(payload.frames, (payload.identity, Float32(elapsed)))
end

"""Create a one-second action sharing a test-owned frame observation vector."""
queue_fixture_job(identity, frames; fail=false) = EuclidRepl.ReplDrawJob(
    :test, 1f0, 0f0, ReplQueueTestPayload(identity, frames, fail))

"""Provide a successful visibility callback for Julia-only REPL tests."""
function test_shape_set_visible(
    _state::Ptr{Cvoid},
    _entity::UInt64,
    _visible::UInt8)::Int32
    return OdinJuliaBridge.BRIDGE_STATUS_OK
end

if Sys.iswindows()
    OdinJuliaBridge.HOST_SYMBOL_CACHE[:shape_set_visible] =
        @cfunction(test_shape_set_visible, Int32, (Ptr{Cvoid}, UInt64, UInt8))
end

@testset "EuclidRepl validation" begin
    @test EuclidRepl.validated_label_source("A"^256) == "A"^256
    @test EuclidRepl.validated_label_source("é"^128) == "é"^128
    @test_throws ArgumentError EuclidRepl.validated_label_source("é"^129)
    @test_throws ArgumentError EuclidRepl.validated_label_source("a\0b")
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

    @test_throws ArgumentError EuclidRepl.validated_angle_theta(Inf32)
    @test_throws ArgumentError EuclidRepl.validated_angle_theta(NaN32)

    @test_throws ArgumentError EuclidRepl.validated_radius(0f0)
    @test_throws ArgumentError EuclidRepl.validated_radius(-1f0)
    @test_throws ArgumentError EuclidRepl.validated_radius(Inf32)

    triangle_vertices = EuclidRepl.validated_polygon_vertices([
        [0, 0, 0], [2, 0, 0], [0, 2, 0]])
    @test triangle_vertices == [
        Float32[0, 0, 0], Float32[2, 0, 0], Float32[0, 2, 0]]
    @test_throws ArgumentError EuclidRepl.validated_polygon_vertices([
        [0, 0, 0], [2, 2, 0], [0, 3, 0], [3, 0, 0]])
    @test_throws ArgumentError EuclidRepl.validated_polygon_vertices([
        [0, 0, 0], [2, 0, 0], [0, 2, 1]])
    @test_throws ArgumentError EuclidRepl.validated_polygon_vertices([
        [0, 0, 0], [1, 0, 0], [2, 0, 0]])
    @test EuclidRepl.polygon_vertex_ids(
        OdinJuliaBridge.BridgeShapeTriangle(0, 10, 11, 12, 13)) ==
        UInt64[11, 12, 13]
    @test EuclidRepl.polygon_vertex_ids(
        OdinJuliaBridge.BridgeShapeSquare(0, 10, 11, 12, 13, 14)) ==
        UInt64[11, 12, 13, 14]
    @test EuclidRepl.polygon_vertex_ids(
        OdinJuliaBridge.BridgeShapePentagon(0, 10, 11, 12, 13, 14, 15)) ==
        UInt64[11, 12, 13, 14, 15]
    @test_throws ArgumentError EuclidRepl.polygon_vertex_ids(
        OdinJuliaBridge.BridgeShapeTriangle(
            OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT, 10, 11, 12, 13))

    region = EuclidRepl.validated_circle_region(
        [0, 0, 0], 1, [1, 0, 0], 1)
    @test region == (
        (center=Float32[0, 0, 0], radius=1f0),
        (center=Float32[1, 0, 0], radius=1f0))
    @test_throws ArgumentError EuclidRepl.validated_circle_region(
        [0, 0, 0], 1, [2, 0, 0], 1)
    @test_throws ArgumentError EuclidRepl.validated_circle_region(
        [0, 0, 0], 1, [0.5, 0, 0], 0.25)
    @test_throws ArgumentError EuclidRepl.validated_circle_region(
        [0, 0, 0], 1, [1, 0, 1], 1)

    @test_throws ArgumentError EuclidRepl.vec3("bad", Float32[1f0, 2f0])
    @test_throws ArgumentError EuclidRepl.vec3("bad", Float32[1f0, Inf32, 3f0])
    @test_throws ArgumentError EuclidRepl.validated_positive_parameter("radius", 0)
    @test_throws ArgumentError EuclidRepl.validated_positive_parameter("radius", Inf)

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

end

@testset "EuclidRepl shape family domains reject before admission" begin
    runtime = EuclidRepl.create_runtime()
    first = Float32[0, 0, 0]
    second = Float32[0.5, 0, 0]
    @test_throws ArgumentError EuclidRepl.cycloid!(
        runtime, TEST_STATE_PTR, first, second;
        rolling_radius=0.1, parameter_finish=4pi)
    @test_throws ArgumentError EuclidRepl.cycloid!(
        runtime, TEST_STATE_PTR, first, Float32[0.5, 0, 1],
        rolling_radius=0.01)
    @test_throws ArgumentError EuclidRepl.curtate_cycloid!(
        runtime, TEST_STATE_PTR, first, [1, 0, 0], 0.1, 0.1)
    @test_throws ArgumentError EuclidRepl.prolate_cycloid!(
        runtime, TEST_STATE_PTR, first, [1, 0, 0], 0.1, 0.1)
    @test_throws ArgumentError EuclidRepl.trochoid!(
        runtime, TEST_STATE_PTR, first; mode=:unknown, fixed_radius=0.1,
        rolling_radius=0.05, tracer_distance=0.02)
    @test_throws ArgumentError EuclidRepl.trochoid!(
        runtime, TEST_STATE_PTR, first; mode=:internal, fixed_radius=0.05,
        rolling_radius=0.1, tracer_distance=0.02)
    @test_throws ArgumentError EuclidRepl.trochoid!(
        runtime, TEST_STATE_PTR, first; fixed_radius=0.1,
        rolling_radius=0.05, tracer_distance=0.02,
        parameter_start=-1, parameter_finish=1, draw_parameter=2)
    @test_throws ArgumentError EuclidRepl.ellipse!(
        runtime, TEST_STATE_PTR, first, 0.05, 0.1)
    @test_throws ArgumentError EuclidRepl.hypocycloid!(
        runtime, TEST_STATE_PTR, first, 0.1, 1 // 1)
    @test_throws ArgumentError EuclidRepl.rational_trochoid!(
        runtime, TEST_STATE_PTR, first, :internal, 0.1, 1 // 1, 0.02)
    @test_throws ArgumentError EuclidRepl.parabola!(
        runtime, TEST_STATE_PTR, first; focal_distance=0)
    @test_throws ArgumentError EuclidRepl.parabola!(
        runtime, TEST_STATE_PTR, first; focal_distance=0.1,
        parameter_start=1, parameter_finish=-1, draw_parameter=2)
    @test_throws ArgumentError EuclidRepl.hyperbola!(
        runtime, TEST_STATE_PTR, first; semimajor=0.1, semiminor=0.05,
        parameter_start=-5, parameter_finish=5)
    @test_throws ArgumentError EuclidRepl.hyperbola!(
        runtime, TEST_STATE_PTR, first; semimajor=0.1, semiminor=0.05,
        rail_half_length=0.1)
    @test_throws ArgumentError EuclidRepl.hyperbola!(
        runtime, TEST_STATE_PTR, first; semimajor=0.1, semiminor=0.05,
        branches=:invalid)
    @test EuclidRepl.status(runtime, TEST_STATE_PTR).pending_count == 0
    @test EuclidRepl.status(runtime, TEST_STATE_PTR).managed_shape_count == 0
end

@testset "EuclidRepl visibility helpers" begin
    EuclidRepl.reset_session!(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    empty!(REPL_TEST_HIDDEN)
    empty!(REPL_TEST_SHOWN)
    session = EuclidRepl.ensure_session!(TEST_REPL_RUNTIME)
    for id in UInt64[5, 7, 11, 21, 31, 41]
        REPL_TEST_POSITIONS[id] = (0f0, 0f0, 0f0)
        EuclidRepl.track_managed_host!(session, id)
    end
    point = OdinJuliaBridge.BridgeShapeEntityResult(
        OdinJuliaBridge.BRIDGE_STATUS_OK, UInt64(7))
    point_view = OdinJuliaBridge.BridgePointView(
        Int32(0),
        UInt64(7),
        Int32(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        (0f0, 0f0, 0f0),
        OdinJuliaBridge.BridgeColor(0, 0, 0, 0),
        OdinJuliaBridge.BridgeColor(0, 0, 0, 0),
        UInt8(0),
        0f0,
        UInt16(0))
    line_shape = OdinJuliaBridge.BridgeShapeLine(0, 11, 12, 13)
    circle_shape = OdinJuliaBridge.BridgeShapeCircle(0, 21)
    filled_circle_shape = OdinJuliaBridge.BridgeShapeFilledCircle(0, 31)
    triangle_shape = OdinJuliaBridge.BridgeShapeTriangle(
        OdinJuliaBridge.BRIDGE_STATUS_OK, 41, 42, 43, 44)

    @test isnothing(EuclidRepl.hide!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 5))
    @test isnothing(EuclidRepl.hide!(TEST_REPL_RUNTIME, TEST_STATE_PTR, point))
    @test isnothing(EuclidRepl.hide!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, point_view))
    @test isnothing(EuclidRepl.hide!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, line_shape))
    @test isnothing(EuclidRepl.hide!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, circle_shape))
    @test isnothing(EuclidRepl.hide!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, filled_circle_shape))
    @test isnothing(EuclidRepl.hide!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, triangle_shape))
    @test isempty(REPL_TEST_HIDDEN)
    @test EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR).pending_count == 6
    EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 1f0)
    @test isempty(REPL_TEST_HIDDEN)
    for _ in 1:7
        EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 1f0)
    end
    @test REPL_TEST_HIDDEN == UInt64[5, 7, 7, 11, 21, 31, 41]
    @test_throws ArgumentError EuclidRepl.hide!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 99)
    invalid_triangle = OdinJuliaBridge.BridgeShapeTriangle(
        OdinJuliaBridge.BRIDGE_STATUS_NOT_FOUND, 41, 42, 43, 44)
    @test_throws ArgumentError EuclidRepl.hide!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, invalid_triangle)

    @test isnothing(EuclidRepl.show!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 5))
    @test isnothing(EuclidRepl.show!(TEST_REPL_RUNTIME, TEST_STATE_PTR, point))
    @test isnothing(EuclidRepl.show!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, point_view))
    @test isnothing(EuclidRepl.show!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, line_shape))
    @test isnothing(EuclidRepl.show!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, circle_shape))
    @test isnothing(EuclidRepl.show!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, filled_circle_shape))
    @test isnothing(EuclidRepl.show!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, triangle_shape))
    @test isempty(REPL_TEST_SHOWN)
    @test EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR).pending_count == 6
    EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 1f0)
    @test isempty(REPL_TEST_SHOWN)
    for _ in 1:7
        EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 1f0)
    end
    @test REPL_TEST_SHOWN == UInt64[5, 7, 7, 11, 21, 31, 41]
    @test_throws ArgumentError EuclidRepl.show!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 99)
    @test_throws ArgumentError EuclidRepl.show!(
        TEST_REPL_RUNTIME, TEST_STATE_PTR, invalid_triangle)
end

@testset "EuclidRepl installs Terminal show helper" begin
    runtime = EuclidRepl.create_runtime()
    context_module = Module(:EuclidReplVisibilityHelperTest)
    REPL_TEST_POSITIONS[51] = (0f0, 0f0, 0f0)
    EuclidRepl.track_managed_host!(runtime.session, UInt64(51))
    EuclidRepl.install_drawing_helpers!(
        context_module, runtime, TEST_STATE_PTR)

    @test isdefined(context_module, :show!)
    @test isnothing(getfield(context_module, :show!)(51))
    @test runtime.session.active_job.payload.visible
end

@testset "EuclidRepl typed shape identities and admissions" begin
    runtime = EuclidRepl.create_runtime()
    vertices = [[0, 0, 0], [2, 0, 0], [0, 2, 0]]
    shape = EuclidRepl.queue_polygon!(
        runtime, TEST_STATE_PTR, vertices, :steelblue, 1f0, :triangle,
        (points, _) -> OdinJuliaBridge.BridgeShapeTriangle(
            OdinJuliaBridge.BRIDGE_STATUS_OK, 600, 601, 602, 603))
    payload = runtime.session.active_job.payload
    @test EuclidRepl.polygon_vertex_ids(shape) == UInt64[601, 602, 603]
    @test payload.vertices == [
        Float32[0, 0, 0], Float32[2, 0, 0], Float32[0, 2, 0]]
    @test runtime.session.managed_host_ids == UInt64[600]
    vertices[2][1] = 50
    @test payload.vertices[2] == Float32[2, 0, 0]
    @test_throws ArgumentError EuclidRepl.queue_polygon!(
        runtime, TEST_STATE_PTR, [[0, 0, 0], [2, 2, 0], [0, 3, 0], [3, 0, 0]],
        :steelblue, 1f0, :square, (_, _) -> error("invalid polygon was constructed"))

    region_runtime = EuclidRepl.create_runtime()
    region = EuclidRepl.queue_circle_region!(
        region_runtime, TEST_STATE_PTR, [0, 0, 0], 1, [1, 0, 0], 1,
        :lens,
        (state, first, first_radius, second, second_radius; color) ->
            OdinJuliaBridge.BridgeShapeCircleRegion(
                OdinJuliaBridge.BRIDGE_STATUS_OK, 700, 701, 702);
        color=:steelblue, duration=1f0)
    @test EuclidRepl.circle_region_center_ids(region) == (UInt64(701), UInt64(702))
    @test region_runtime.session.active_job.payload.center_ids ==
        (UInt64(701), UInt64(702))
end

@testset "EuclidRepl coordinated polygon rotation" begin
    runtime = EuclidRepl.create_runtime()
    ids = UInt64[801, 802, 803]
    initial = ((0f0, 0f0, 0f0), (1f0, 0f0, 0f0), (0f0, 2f0, 0f0))
    for (id, position) in zip(ids, initial)
        REPL_TEST_POSITIONS[id] = position
    end
    shape = OdinJuliaBridge.BridgeShapeTriangle(
        OdinJuliaBridge.BRIDGE_STATUS_OK, 800, ids...)
    REPL_TEST_KINDS[800] = OdinJuliaBridge.SHAPE_KIND_POLYGON
    EuclidRepl.track_managed_host!(runtime.session, UInt64(800))
    EuclidRepl.rotate_z!(runtime, TEST_STATE_PTR, shape, Float32(pi / 2);
        pivot=Float32[0.5, -0.5, 2], duration=1f0)
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 0.25f0)
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 0.25f0)
    moved = Tuple(REPL_TEST_POSITIONS[id] for id in ids)
    initial_distances = (1f0, 2f0, sqrt(5f0))
    measured = (
        sqrt(sum(abs2(moved[1][index] - moved[2][index]) for index in 1:3)),
        sqrt(sum(abs2(moved[1][index] - moved[3][index]) for index in 1:3)),
        sqrt(sum(abs2(moved[2][index] - moved[3][index]) for index in 1:3)))
    @test collect(measured) ≈ collect(initial_distances) atol=1f-5
    active = EuclidRepl.status(runtime, TEST_STATE_PTR)
    expected = EuclidRepl.rotated_xy_position(collect(initial[2]),
        Float32[0.5, -0.5, 2], Float32(pi / 2) * active.elapsed)
    @test collect(moved[2]) ≈ expected atol=1f-5
    @test active.active
    for _ in 1:3
        EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 0.25f0)
    end
    @test EuclidRepl.status(runtime, TEST_STATE_PTR).drained
end

@testset "EuclidRepl polygon reveal survives skipped phase frames" begin
    empty!(REPL_TEST_REVEALED)
    payload = EuclidRepl.PolygonPayload(
        950, UInt64[951, 952, 953],
        [Float32[0, 0, 0], Float32[1, 0, 0], Float32[0, 1, 0]],
        :steelblue, false)
    EuclidRepl.start_polygon_reveal_if_due!(
        TEST_STATE_PTR, 0.95f0, 1f0, payload, record_test_region_reveal!)
    @test payload.reveal_started
    @test REPL_TEST_REVEALED == UInt64[950]
    EuclidRepl.start_polygon_reveal_if_due!(
        TEST_STATE_PTR, 0.99f0, 1f0, payload, record_test_region_reveal!)
    @test REPL_TEST_REVEALED == UInt64[950]
end

@testset "EuclidRepl curve completion commits exact frontiers" begin
    empty!(REPL_TEST_FRONTIERS)
    origin = Float32[0, 0, 0]
    payloads = (
        EuclidRepl.CycloidPayload(960, (UInt64(961), UInt64(962)),
            origin, Float32[1, 0, 0], 0.1f0, 0.1f0, 0f0, 1f0, -1f0, 0f0, :steelblue, 5f0),
        EuclidRepl.TrochoidPayload(970, origin, Int32(0),
            0.1f0, 0.05f0, 0.02f0, 0f0, 0f0, 0f0, 6f0, 1.5f0, :steelblue, 5f0),
        EuclidRepl.ParabolaPayload(980, origin,
            0.1f0, 0f0, -1f0, 1f0, 0.5f0, 1f0, :steelblue, 5f0),
        EuclidRepl.HyperbolaPayload(990, origin,
            0.1f0, 0.05f0, 0f0, -1f0, 1f0, -0.5f0, 1f0, :both, :steelblue, 5f0))
    for payload in payloads
        EuclidRepl.finalize_payload!(TEST_STATE_PTR, payload)
        @test REPL_TEST_FRONTIERS[payload.host_id] == payload.draw_parameter
    end
end

@testset "EuclidRepl activation-sampled analytic rotation admission" begin
    rotated = EuclidRepl.rotated_xy_position(
        Float32[1, 0, 7], Float32[0, 0, 0], Float32(pi / 2))
    @test rotated isa Vector{Float32}
    @test rotated ≈ Float32[0, 1, 7] atol=1f-5

    runtime = EuclidRepl.create_runtime()
    host_id = UInt64(900)
    REPL_TEST_POSITIONS[host_id] = (0.7f0, 0.7f0, 0f0)
    REPL_TEST_KINDS[host_id] = OdinJuliaBridge.SHAPE_KIND_ARC
    REPL_TEST_ORIENTATIONS[host_id] = (0f0, 0f0, 0f0, 1f0)
    EuclidRepl.track_managed_host!(runtime.session, host_id)
    shape = OdinJuliaBridge.BridgeShapeCircle(
        OdinJuliaBridge.BRIDGE_STATUS_OK, host_id)
    pivot = Float32[0.3, 0.4, 0]
    @test EuclidRepl.rotate_z!(runtime, TEST_STATE_PTR, shape, pi / 2;
        pivot, duration=1f0) === shape
    payload = runtime.session.active_job.payload
    @test payload.host_id == host_id && payload.oriented
    pivot[1] = 9f0
    @test payload.spec.axis_a == Float32[0.3, 0.4, 0]
    @test_throws ArgumentError EuclidRepl.rotate_z!(
        runtime, TEST_STATE_PTR,
        OdinJuliaBridge.BridgeShapeCircle(
            OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT, host_id),
        1; pivot=[0, 0, 0])
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
    EuclidRepl.reset_session!(TEST_REPL_RUNTIME, TEST_STATE_PTR)

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
    @test compass_status.kind == :highlight_pen
    @test compass_status.pending_count == 1

    EuclidRepl.reset_session!(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR).active == false
end

@testset "EuclidRepl session lifecycle" begin
    EuclidRepl.reset_session!(TEST_REPL_RUNTIME, TEST_STATE_PTR)

    state0 = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test state0.active == false
    @test state0.managed_shape_count == 0

    session = EuclidRepl.ensure_session!(TEST_REPL_RUNTIME)
    @test !isdefined(EuclidRepl, :stop!)
    @test EuclidRepl.clear!(TEST_REPL_RUNTIME, TEST_STATE_PTR) == true
    EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 1f0)
    EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 1f0)

    # Simulate managed geometry bookkeeping in test-only state.
    push!(session.managed_host_ids, 1)
    push!(session.managed_host_ids, 2)
    @test EuclidRepl.status(
        TEST_REPL_RUNTIME, TEST_STATE_PTR).managed_shape_count == 2

    @test EuclidRepl.clear!(TEST_REPL_RUNTIME, TEST_STATE_PTR) == true
    @test EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR).managed_shape_count == 2
    REPL_TEST_POSITIONS[1] = (0f0, 0f0, 0f0)
    REPL_TEST_POSITIONS[2] = (0f0, 0f0, 0f0)
    EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 1f0)
    EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 1f0)
    @test EuclidRepl.status(
        TEST_REPL_RUNTIME, TEST_STATE_PTR).managed_shape_count == 2

    EuclidRepl.reset_session!(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    state_after_reset = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test state_after_reset.active == false
    @test state_after_reset.managed_shape_count == 0
end

@testset "EuclidRepl FIFO and bounded storage reuse" begin
    EuclidRepl.reset_session!(TEST_REPL_RUNTIME, TEST_STATE_PTR)

    session = EuclidRepl.ensure_session!(TEST_REPL_RUNTIME)
    frames = Tuple{Int,Float32}[]
    job_a = queue_fixture_job(1, frames)
    job_b = queue_fixture_job(2, frames)

    EuclidRepl.start_job!(TEST_REPL_RUNTIME, TEST_STATE_PTR, job_a)
    s1 = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test s1.active == true
    @test s1.kind == :test

    EuclidRepl.start_job!(TEST_REPL_RUNTIME, TEST_STATE_PTR, job_b)
    s2 = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test s2.active == true
    @test s2.kind == :test
    @test session.active_job === job_a
    @test s2.pending_count == 1
    @test s2.subscription_id === nothing
    @test job_b.elapsed == 0f0

    EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 0.25f0)
    @test isempty(frames)
    @test job_a.elapsed == 0f0 && !job_a.activated
    EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 0.25f0)
    @test frames == [(1, 0.25f0)]
    EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 2f0)
    @test frames == [(1, 0.25f0), (1, 1f0)]
    @test job_b.elapsed == 0f0
    @test !EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR).drained
    EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 1f0)
    @test frames[end] == (2, 1f0)
    s3 = EuclidRepl.status(TEST_REPL_RUNTIME, TEST_STATE_PTR)
    @test s3.active == false
    @test s3.drained
    @test s3.completed_count == 2
    slots = session.pending
    for cycle in 1:3
        for id in 1:EuclidRepl.ACTION_QUEUE_CAPACITY
            EuclidRepl.start_job!(
                TEST_REPL_RUNTIME, TEST_STATE_PTR, queue_fixture_job(id, frames))
        end
        @test session.pending_count == EuclidRepl.ACTION_QUEUE_CAPACITY - 1
        @test_throws ArgumentError EuclidRepl.start_job!(
            TEST_REPL_RUNTIME, TEST_STATE_PTR, queue_fixture_job(99, frames))
        @test_throws ArgumentError EuclidRepl.point!(
            TEST_REPL_RUNTIME, TEST_STATE_PTR, [0, 0, 0])
        @test_throws ArgumentError EuclidRepl.line!(
            TEST_REPL_RUNTIME, TEST_STATE_PTR, [0, 0, 0], [1, 1, 0])
        @test_throws ArgumentError EuclidRepl.circle!(
            TEST_REPL_RUNTIME, TEST_STATE_PTR, [0, 0, 0], 1)
        @test session.pending_count == EuclidRepl.ACTION_QUEUE_CAPACITY - 1
        EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 1f0)
        for _ in 1:EuclidRepl.ACTION_QUEUE_CAPACITY
            EuclidRepl.run_active_job_frame!(TEST_REPL_RUNTIME, TEST_STATE_PTR, 1f0)
        end

        @testset "EuclidRepl stale activation and copied highlight inputs" begin
            runtime = EuclidRepl.create_runtime()
            REPL_TEST_POSITIONS[42] = (0f0, 0f0, 0f0)
            EuclidRepl.translate_points!(
                runtime, TEST_STATE_PTR, [42], [0.1, 0, 0])
            delete!(REPL_TEST_POSITIONS, UInt64(42))
            EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
            @test !EuclidRepl.status(runtime, TEST_STATE_PTR).failed
            @test_throws ArgumentError EuclidRepl.run_active_job_frame!(
                runtime, TEST_STATE_PTR, 1f0)
            @test EuclidRepl.status(runtime, TEST_STATE_PTR).failed
            @test EuclidRepl.status(runtime, TEST_STATE_PTR).completed_count == 0
            EuclidRepl.reset_session!(runtime, TEST_STATE_PTR)
            start = [0.1f0, 0.2f0, 0f0]
            finish = [0.5f0, 0.2f0, 0f0]
            EuclidRepl.highlight_pen!(runtime, TEST_STATE_PTR, start, finish)
            start[1] = 99f0
            finish[1] = 99f0
            @test runtime.session.active_job.payload.start_pos == [0.1f0, 0.2f0, 0f0]
            @test runtime.session.active_job.payload.end_pos == [0.5f0, 0.2f0, 0f0]
            EuclidRepl.reset_session!(runtime, TEST_STATE_PTR)
        end
        @test first.(frames[(end - EuclidRepl.ACTION_QUEUE_CAPACITY + 1):end]) ==
            collect(1:EuclidRepl.ACTION_QUEUE_CAPACITY)
        @test session.pending === slots
        @test all(isnothing, slots)
    end
end

@testset "EuclidRepl activation-time motion and immutable submission" begin
    runtime = EuclidRepl.create_runtime()
    REPL_TEST_POSITIONS[7] = (0.1f0, 0.2f0, 0f0)
    ids = UInt64[7]
    displacement = [0.2f0, 0f0, 0f0]
    returned = EuclidRepl.translate_points!(
        runtime, TEST_STATE_PTR, ids, displacement; duration=1f0)
    EuclidRepl.translate_points!(
        runtime, TEST_STATE_PTR, ids, displacement; duration=1f0)
    ids[1] = 99
    returned[1] = 99
    displacement[1] = 99f0
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 0.25f0)
    @test REPL_TEST_POSITIONS[7] == (0.1f0, 0.2f0, 0f0)
    for (step, expected) in enumerate([0.15f0, 0.2f0, 0.25f0, 0.3f0])
        EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 0.25f0)
        @test isapprox(REPL_TEST_POSITIONS[7][1], expected; atol=1f-6)
    end
    @test !EuclidRepl.status(runtime, TEST_STATE_PTR).drained
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test isapprox(REPL_TEST_POSITIONS[7][1], 0.5f0; atol=1f-6)
    @test EuclidRepl.status(runtime, TEST_STATE_PTR).drained
    @test_throws ArgumentError EuclidRepl.translate_points!(
        runtime, TEST_STATE_PTR, [99], [1, 0, 0])
    @test_throws ArgumentError EuclidRepl.validated_point_ids(fill(7, 17))
    @test_throws ArgumentError EuclidRepl.validated_point_ids([7, 7])
    @test_throws ArgumentError EuclidRepl.rotate_points!(
        runtime, TEST_STATE_PTR, [7], [0, 0, 0], [0, 0, 1], Inf)
    @test EuclidRepl.status(runtime, TEST_STATE_PTR).completed_count == 2
end

@testset "EuclidRepl failure blocks successors and reset releases payloads" begin
    runtime = EuclidRepl.create_runtime()
    frames = Tuple{Int,Float32}[]
    EuclidRepl.start_job!(
        runtime, TEST_STATE_PTR, queue_fixture_job(1, frames; fail=true))
    EuclidRepl.start_job!(
        runtime, TEST_STATE_PTR, queue_fixture_job(2, frames))
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test_throws ErrorException EuclidRepl.run_active_job_frame!(
        runtime, TEST_STATE_PTR, 1f0)
    failed = EuclidRepl.status(runtime, TEST_STATE_PTR)
    @test failed.failed && !failed.drained
    @test failed.completed_count == 0 && failed.pending_count == 1
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test isempty(frames)
    @test_throws ErrorException EuclidRepl.clear!(runtime, TEST_STATE_PTR)
    EuclidRepl.reset_session!(runtime, TEST_STATE_PTR)
    @test all(isnothing, runtime.session.pending)
    @test EuclidRepl.status(runtime, TEST_STATE_PTR).drained
end

@testset "EuclidRepl ordered clear preserves later admissions" begin
    runtime = EuclidRepl.create_runtime()
    session = runtime.session
    empty!(REPL_TEST_HIDDEN)
    empty!(REPL_TEST_SHOWN)
    REPL_TEST_POSITIONS[8] = (0f0, 0f0, 0f0)
    REPL_TEST_POSITIONS[9] = (0f0, 0f0, 0f0)
    EuclidRepl.track_managed_host!(session, UInt64(8))
    EuclidRepl.clear!(runtime, TEST_STATE_PTR)
    EuclidRepl.track_managed_host!(session, UInt64(9))
    EuclidRepl.hide!(runtime, TEST_STATE_PTR, 9)
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test isempty(REPL_TEST_HIDDEN)
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test REPL_TEST_HIDDEN == UInt64[8]
    @test session.managed_host_ids == UInt64[8, 9]
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test REPL_TEST_HIDDEN == UInt64[8, 9]
    EuclidRepl.show!(runtime, TEST_STATE_PTR, 8)
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test REPL_TEST_SHOWN == UInt64[8]
end

@testset "EuclidRepl large clear uses bounded captured batches" begin
    runtime = EuclidRepl.create_runtime()
    empty!(REPL_TEST_HIDDEN)
    for id in UInt64.(100:356)
        REPL_TEST_POSITIONS[id] = (0f0, 0f0, 0f0)
        EuclidRepl.track_managed_host!(runtime.session, id)
    end
    EuclidRepl.clear!(runtime, TEST_STATE_PTR)
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test length(REPL_TEST_HIDDEN) == EuclidRepl.CLEAR_COMMAND_CAPACITY
    @test EuclidRepl.status(runtime, TEST_STATE_PTR).completed_count == 0
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test REPL_TEST_HIDDEN == UInt64.(100:356)
    @test EuclidRepl.status(runtime, TEST_STATE_PTR).drained
    @test runtime.session.managed_host_ids == UInt64.(100:356)
end

@testset "EuclidRepl same-evaluation construction dependencies use reservations" begin
    runtime = EuclidRepl.create_runtime()
    id = UInt64(500)
    delete!(REPL_TEST_POSITIONS, id)
    payload = EuclidRepl.PointPayload(id, [0.3f0, 0.4f0, 0f0], :steelblue, 5f0)
    job = EuclidRepl.ReplDrawJob(:point, 1f0, 0f0, payload)
    EuclidRepl.start_job!(runtime, TEST_STATE_PTR, job)
    EuclidRepl.track_managed_host!(runtime.session, id)
    EuclidRepl.translate_points!(
        runtime, TEST_STATE_PTR, [id], [0.1, 0, 0])
    EuclidRepl.hide!(runtime, TEST_STATE_PTR, id)
    @test runtime.session.pending_count == 2
    EuclidRepl.run_active_job_frame!(runtime, TEST_STATE_PTR, 1f0)
    @test !job.activated && job.elapsed == 0f0
    @test !runtime.session.failed
    @test_throws ArgumentError EuclidRepl.run_active_job_frame!(
        runtime, TEST_STATE_PTR, 1f0)
    @test runtime.session.failed
    EuclidRepl.reset_session!(runtime, TEST_STATE_PTR)
end
