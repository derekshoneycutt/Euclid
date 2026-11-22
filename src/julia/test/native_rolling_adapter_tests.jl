using Test

module NativeRollingTestBridge
const OdinJuliaBridge = @__MODULE__
export OdinJuliaBridge
const Legacy = Main.ConicAnimationTestBridge
for name in names(Legacy; all=true)
    Base.isidentifier(string(name)) || continue
    name in (:eval, :include, :OdinJuliaBridge) && continue
    @eval const $name = getfield(Legacy, $(QuoteNode(name)))
end
using Main.OdinJuliaBridge: native_modifier_request, bridge_color, hyperbola_branches
for name in names(Main.OdinJuliaBridge; all=true)
    startswith(string(name), "NATIVE_MODIFIER_") || continue
    @eval const $name = getfield(Main.OdinJuliaBridge, $(QuoteNode(name)))
end

"""Record the actual native request while ordinary lifecycle calls use legacy mocks."""
function apply_native_modifier_request(state::Ptr{Cvoid}, request)
    return record(:native_modifier, (state, request), (;))
end
end

module NativeRollingTestHelpers
const OdinJuliaBridge = Main.NativeRollingTestBridge
const EuclidGeometry = Main.EuclidGeometry
include("../animations/common.jl")
include("../animations/cycloids.jl")
include("../animations/trochoids.jl")
end

"""Return the only native sample captured by one authored explicit-time callback."""
function recorded_rolling_request(fixture)
    requests = filter(call -> call[1] == :native_modifier, fixture.calls)
    @test length(requests) == 1
    @test !any(call -> call[1] in (:set_cycloid_tool_line,
        :set_cycloid_tool_parameter, :set_trochoid_tool_position,
        :set_trochoid_tool_parameter, :lock_compass_joint1,
        :lock_compass_joint2, :emit_trailing_particle), fixture.calls)
    return only(requests)[2][2]
end

@testset "all authored rolling leaves execute native adapters unchanged" begin
    bridge = NativeRollingTestBridge
    for name in CurveTestNames
        family = curve_test_family(name)
        family in ("cycloid", "trochoid") || continue
        fixture = bridge.Fixture(
            Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(0), :none)
        entry, program = conic_test_program(name; bridge)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_ENTER, 0f0)
        placement = recorded_rolling_request(fixture)
        base = family == "cycloid" ? bridge.NATIVE_MODIFIER_CYCLOID_PLACE :
            bridge.NATIVE_MODIFIER_TROCHOID_PLACE
        @test placement.kind == base
        @test placement.third[3] == program.StartParameter
        @test placement.scalar == program.TopZ
        for (phase, duration) in ((program.PhaseDescend, program.DescendDuration),
            (program.PhaseDraw, program.DrawDuration),
            (program.PhaseRise, program.RiseDuration))
            for progress in (0f0, 0.25f0, 0.5f0, 1f0)
                fixture.stored_state = Base.invokelatest(typeof(fixture.stored_state),
                    UInt64(1), phase, duration * progress)
                empty!(fixture.calls)
                @test invoke_conic_test_entry(
                    entry, fixture, bridge.ANIMATION_OPERATION_TICK, 0f0)
                request = recorded_rolling_request(fixture)
                @test request.kind == base + phase + 1
                @test request.elapsed == duration * progress
                @test request.duration == duration
                if phase == program.PhaseDraw
                    @test request.entity == 1
                    @test request.third[3] == program.FinishParameter
                end
                if family == "cycloid"
                    @test request.radius == program.Radius
                    @test request.start == Tuple(program.First)
                    @test request.second == Tuple(program.Second)
                    @test request.displacement[1] == program.TracerDistance
                else
                    @test request.radius == program.RollingRadius
                    @test request.integer == program.Mode
                    @test request.displacement[1:2] ==
                        (program.FixedRadius, program.TracerDistance)
                end
            end
        end
        empty!(fixture.calls)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_SHOW_COMPLETED, 0f0)
        @test !any(call -> call[1] == :native_modifier, fixture.calls)
        @test any(call -> call[1] == Symbol("hide_$(family)_tool"), fixture.calls)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_EXIT, 0f0)
        fixture.rejected_call = :native_modifier
        fixture.stored_state = Base.invokelatest(typeof(fixture.stored_state),
            UInt64(1), program.PhaseDraw, 0f0)
        @test_throws ErrorException invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_TICK, 0.1f0)
    end
end

@testset "rolling public returns and partial directed payloads" begin
    bridge, helpers = NativeRollingTestBridge, NativeRollingTestHelpers
    fixture = bridge.Fixture(
        Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(0), :none)
    first, second = (0.1f0, 0.2f0, 0f0), (0.9f0, 0.8f0, 0f0)
    GC.@preserve fixture begin
        state = pointer_from_objref(fixture)
        tracer = helpers.place_cycloid_tools(
            state, first, second, 0.05, 0.08, 0.5, 0.3;
            parameter_start=2, parameter_finish=-2, tracer_phase=0.4)
        @test all(isapprox.(tracer, EuclidGeometry.cycloid_point(
            (first[1], first[2], 0.3), (second[1], second[2], 0.3),
            0.05, 0.08, 0.5; parameter_start=2, parameter_finish=-2, tracer_phase=0.4)))
        @test recorded_rolling_request(fixture).third == (2f0, -2f0, 0.5f0)
        empty!(fixture.calls)
        helpers.animate_draw_cycloid(state, 1, 1, first, second, 0.05;
            tracer_distance=0.08, parameter_start=2, parameter_finish=-2,
            draw_parameter=-1, curve_id=20, color=:steelblue, brush=5, tracer_phase=0.4)
        request = recorded_rolling_request(fixture)
        @test request.third == (2f0, -2f0, -1f0)
        @test request.displacement[2] == 0.4f0
        empty!(fixture.calls)
        tracer = helpers.place_trochoid_tools(
            state, first, bridge.TROCHOID_INTERNAL, 0.2, 0.05, 0.08, 0.5, 0.3;
            rotation=0.4, tracer_phase=0.6)
        @test all(isapprox.(tracer, EuclidGeometry.trochoid_point(
            (first[1], first[2], 0.3), EuclidGeometry.TrochoidInternal,
            0.2, 0.05, 0.08, 0.5; rotation=0.4, tracer_phase=0.6)))
        empty!(fixture.calls)
        helpers.animate_draw_trochoid(state, 1, 1, first, 2, -2;
            mode=bridge.TROCHOID_EXTERNAL, fixed_radius=0.2, rolling_radius=0.05,
            tracer_distance=0.08, draw_parameter=-1, curve_id=21,
            color=:steelblue, brush=5, rotation=0.4, tracer_phase=0.6)
        request = recorded_rolling_request(fixture)
        @test request.third == (2f0, -2f0, -1f0)
        @test request.angle == 0.4f0
        @test request.displacement[3] == 0.6f0
    end
end
