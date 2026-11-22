using Test

module NativeConicTestHelpers
const OdinJuliaBridge = Main.NativeRollingTestBridge
const EuclidGeometry = Main.EuclidGeometry
include("../animations/common.jl")
include("../animations/conics.jl")
end

"""Require a native request rather than the former Julia apparatus setter sequence."""
function recorded_conic_request(fixture)
    requests = filter(call -> call[1] == :native_modifier, fixture.calls)
    @test length(requests) == 1
    @test !any(call -> call[1] in (:set_parabola_tool_position,
        :set_parabola_tool_parameter, :set_hyperbola_tool_position,
        :set_hyperbola_tool_parameter, :emit_trailing_particle), fixture.calls)
    return only(requests)[2][2]
end

"""Install an authored phase sample while retaining the initialized native identity."""
function set_native_conic_fixture_phase!(fixture, phase, elapsed)
    state = fixture.stored_state
    arguments = hasproperty(state, :branches) ?
        (state.curve_id, state.branches, phase, elapsed) :
        (state.curve_id, phase, elapsed)
    fixture.stored_state = Base.invokelatest(typeof(state), arguments...)
    empty!(fixture.calls)
end

@testset "real authored conics execute native apparatus adapters" begin
    bridge = NativeRollingTestBridge
    for (name, branches) in (("parabola", :both), ("hyperbola", :both),
        ("hyperbola", :positive), ("hyperbola", :negative))
        fixture = bridge.Fixture(
            Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(0), :none)
        entry, program = conic_test_program(name; bridge)
        if name == "hyperbola"
            initialize_hyperbola_fixture(entry, fixture, branches)
        else
            @test invoke_conic_test_entry(
                entry, fixture, bridge.ANIMATION_OPERATION_ENTER, 0f0)
        end
        base = name == "parabola" ? bridge.NATIVE_MODIFIER_PARABOLA_PLACE :
            bridge.NATIVE_MODIFIER_HYPERBOLA_PLACE
        placement = recorded_conic_request(fixture)
        @test placement.kind == base
        @test placement.third[1] == program.StartParameter
        @test placement.scalar == program.TopZ
        for (phase, duration) in ((program.PhaseDescend, program.DescendDuration),
            (program.PhaseDraw, program.DrawDuration),
            (program.PhaseRise, program.RiseDuration))
            for progress in (0f0, 0.25f0, 0.5f0, 1f0)
                set_native_conic_fixture_phase!(fixture, phase, duration * progress)
                @test invoke_conic_test_entry(
                    entry, fixture, bridge.ANIMATION_OPERATION_TICK, 0f0)
                request = recorded_conic_request(fixture)
                @test request.kind == base + phase + 1
                @test request.elapsed == duration * progress
                @test request.duration == duration
                @test request.start == Tuple(
                    name == "parabola" ? program.Vertex : program.Center)
                if phase == program.PhaseDraw
                    @test request.entity == fixture.stored_state.curve_id
                    @test request.third == (
                        program.StartParameter, 0f0, program.FinishParameter)
                    @test request.integer == bridge.hyperbola_branches(branches)
                    @test request.radius ==
                        (name == "parabola" ? program.FocalDistance : program.Semimajor)
                end
            end
        end
        empty!(fixture.calls)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_SHOW_COMPLETED, 0f0)
        @test !any(call -> call[1] == :native_modifier, fixture.calls)
        @test any(call -> call[1] == Symbol("hide_$(name)_tool"), fixture.calls)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_EXIT, 0f0)
        fixture.rejected_call = :native_modifier
        set_native_conic_fixture_phase!(fixture, program.PhaseDraw, 0f0)
        @test_throws ErrorException invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_TICK, 0.1f0)
    end
end

@testset "conic adapters retain partial reversed domains and rotated selections" begin
    bridge, helpers = NativeRollingTestBridge, NativeConicTestHelpers
    fixture = bridge.Fixture(
        Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(0), :none)
    center = (0.4f0, 0.5f0, 0.1f0)
    GC.@preserve fixture begin
        state = pointer_from_objref(fixture)
        helpers.animate_draw_parabola(state, 0.5, 1, center, 0.075, 1, -0.5;
            curve_id=7, color=:steelblue, rotation=0.6)
        request = recorded_conic_request(fixture)
        @test request.third == (1f0, 0f0, -0.5f0)
        @test request.angle == 0.6f0 && request.entity == 7
        for branches in (:both, :positive, :negative)
            empty!(fixture.calls)
            helpers.animate_draw_hyperbola(state, 0.5, 1, center, 0.12, 0.1, 1, -0.5;
                curve_id=8, color=:steelblue, rotation=0.6, branches)
            request = recorded_conic_request(fixture)
            @test request.third == (1f0, 0f0, -0.5f0)
            @test request.angle == 0.6f0 && request.displacement[1] == 0.1f0
            @test request.integer == bridge.hyperbola_branches(branches)
        end
        @test_throws ArgumentError helpers.animate_draw_hyperbola(
            state, 0.5, 1, center, 0.12, 0.1, 1, -0.5;
            curve_id=8, color=:steelblue, branches=:invalid)
    end
end
