module ConicAnimationTestEnvironment
module OdinJuliaBridge

const AnimationKey = Main.OdinJuliaBridge.AnimationKey
const BRIDGE_STATUS_OK = Int32(0)
"""Own recorded calls and mock native storage for one lifecycle test invocation."""
mutable struct Fixture
    calls::Vector{Tuple{Symbol,Tuple,NamedTuple}}
    stored_state::Any
    next_id::UInt64
end

"""Borrow the explicitly passed fixture while the invoking test keeps it rooted."""
function fixture_from_state(state::Ptr{Cvoid})
    return unsafe_pointer_to_objref(state)::Fixture
end

for name in (:ANIMATION_OPERATION_ENTER, :ANIMATION_OPERATION_TICK,
    :ANIMATION_OPERATION_EXIT, :ANIMATION_OPERATION_SHOW_COMPLETED,
    :ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED)
    @eval const $name = getfield(Main.OdinJuliaBridge, $(QuoteNode(name)))
end

"""Record native requests without entering libjulia's host executable boundary."""
function record(name::Symbol, args::Tuple, kwargs::NamedTuple)
    push!(fixture_from_state(args[1]).calls, (name, args, kwargs))
    return BRIDGE_STATUS_OK
end

"""Record the parabola instrument's translated pose."""
set_parabola_tool_position(args...; kwargs...) =
    record(:set_parabola_tool_position, args, (; kwargs...))
"""Record the parabola instrument's tracing parameter."""
set_parabola_tool_parameter(args...; kwargs...) =
    record(:set_parabola_tool_parameter, args, (; kwargs...))
"""Record the parabola instrument's configuration."""
set_parabola_tool_geometry(args...; kwargs...) =
    record(:set_parabola_tool_geometry, args, (; kwargs...))
"""Record the parabola pen's contact state."""
set_parabola_tool_active(args...; kwargs...) =
    record(:set_parabola_tool_active, args, (; kwargs...))
"""Record parabola instrument visibility."""
show_parabola_tool(args...; kwargs...) =
    record(:show_parabola_tool, args, (; kwargs...))
"""Record parabola instrument cleanup."""
hide_parabola_tool(args...; kwargs...) =
    record(:hide_parabola_tool, args, (; kwargs...))
"""Record the parabola ink's reveal frontier."""
set_parabola_frontier(args...; kwargs...) =
    record(:set_parabola_frontier, args, (; kwargs...))
"""Record the hyperbola instrument's translated pose."""
set_hyperbola_tool_position(args...; kwargs...) =
    record(:set_hyperbola_tool_position, args, (; kwargs...))
"""Record the paired pens' tracing parameter."""
set_hyperbola_tool_parameter(args...; kwargs...) =
    record(:set_hyperbola_tool_parameter, args, (; kwargs...))
"""Record the hyperbola instrument's configuration."""
set_hyperbola_tool_geometry(args...; kwargs...) =
    record(:set_hyperbola_tool_geometry, args, (; kwargs...))
"""Record the paired pens' contact state."""
set_hyperbola_tool_active(args...; kwargs...) =
    record(:set_hyperbola_tool_active, args, (; kwargs...))
"""Record hyperbola instrument visibility."""
show_hyperbola_tool(args...; kwargs...) =
    record(:show_hyperbola_tool, args, (; kwargs...))
"""Record hyperbola instrument cleanup."""
hide_hyperbola_tool(args...; kwargs...) =
    record(:hide_hyperbola_tool, args, (; kwargs...))
"""Record an individual hyperbola branch's reveal frontier."""
set_hyperbola_frontier(args...; kwargs...) =
    record(:set_hyperbola_frontier, args, (; kwargs...))
"""Record curve visibility without entering native code."""
show_point(args...; kwargs...) = record(:show_point, args, (; kwargs...))
"""Record curve hiding without entering native code."""
hide_point(args...; kwargs...) = record(:hide_point, args, (; kwargs...))
"""Record authored trail positions for pen/frontier agreement assertions."""
emit_trailing_particle(args...; kwargs...) =
    record(:emit_trailing_particle, args, (; kwargs...))
"""Record completion of the draw-and-lift cycle."""
notify_animation_cycle_boundary(args...; kwargs...) =
    record(:notify_animation_cycle_boundary, args, (; kwargs...))
"""Record presentation publication without invoking the content producer."""
publish_view_content(args...; kwargs...) =
    record(:publish_view_content, args, (; kwargs...))
"""Record acquisition of the animation content specification."""
animation_content_specification(args...; kwargs...) =
    record(:animation_content_specification, args, (; kwargs...))

"""Return a distinct native identity for each newly constructed curve."""
function create_new_parabola(args...; kwargs...)
    record(:create_new_parabola, args, (; kwargs...))
    fixture = fixture_from_state(args[1])
    fixture.next_id += 1
    return (status=BRIDGE_STATUS_OK, host_id=fixture.next_id)
end

"""Return a separate identity for each signed hyperbola branch."""
function create_new_hyperbola(args...; kwargs...)
    record(:create_new_hyperbola, args, (; kwargs...))
    fixture = fixture_from_state(args[1])
    fixture.next_id += 1
    return (status=BRIDGE_STATUS_OK, host_id=fixture.next_id)
end

"""Copy the immutable animation state as the native typed store would."""
function set_animation_value!(state, _key, value)
    fixture_from_state(state).stored_state = value
    return BRIDGE_STATUS_OK
end

"""Return the latest immutable state to the animation policy."""
function get_animation_value(state, _key)
    return fixture_from_state(state).stored_state, BRIDGE_STATUS_OK
end

end

end

const ConicAnimationTestBridge = ConicAnimationTestEnvironment.OdinJuliaBridge

"""Load a production conic program against a recording native boundary."""
function conic_test_program(name::String)
    owner = Module(gensym(:ConicAnimationTest), false, false)
    for (symbol, value) in (
        :AnimationCatalog => AnimationCatalog,
        :OdinJuliaBridge => ConicAnimationTestBridge,
        :EuclidGeometry => EuclidGeometry,
        :EuclidLatex => EuclidLatex,
        :EuclidSearchContent => EuclidSearchContent)
        Core.eval(owner, :(const $symbol = $value))
    end
    implementation = Base.include(owner,
        joinpath(ProductionContentRoot, "curves", "$name.jl"))
    return implementation.entry, parentmodule(implementation.entry)
end

"""Pass test-owned mock state through the native argument, rooted for the call."""
function invoke_conic_test_entry(entry, fixture, operation, dt::Float32)
    GC.@preserve fixture begin
        state = pointer_from_objref(fixture)
        return Base.invokelatest(entry, state, operation, dt)
    end
end

@testset "conic animation lifecycle and synchronized drawing" begin
    bridge = ConicAnimationTestBridge
    for (name, branches) in (("parabola", 1), ("hyperbola", 2))
        fixture = bridge.Fixture(Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(0))
        entry, program = conic_test_program(name)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_ENTER, 0f0)
        @test fixture.next_id == branches
        if branches == 2
            creations = filter(call -> call[1] == :create_new_hyperbola, fixture.calls)
            @test getproperty.(getindex.(creations, 3), :branch) == [1, -1]
        end
        independent = bridge.Fixture(
            Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(100))
        saved_state, saved_calls = fixture.stored_state, length(fixture.calls)
        @test invoke_conic_test_entry(
            entry, independent, bridge.ANIMATION_OPERATION_ENTER, 0f0)
        @test independent.next_id == 100 + branches
        @test fixture.next_id == branches
        @test fixture.stored_state === saved_state
        @test length(fixture.calls) == saved_calls
        for _ in 1:3
            invoke_conic_test_entry(
                entry, fixture, bridge.ANIMATION_OPERATION_TICK, 0.5f0)
        end
        for _ in 1:10
            empty!(fixture.calls)
            invoke_conic_test_entry(
                entry, fixture, bridge.ANIMATION_OPERATION_TICK, 0.5f0)
            frontier_calls = filter(call -> call[1] == Symbol("set_$(name)_frontier"),
                fixture.calls)
            tool_call = only(filter(
                call -> call[1] == Symbol("set_$(name)_tool_parameter"), fixture.calls))
            @test length(frontier_calls) == branches
            @test all(call[2][3] == tool_call[2][2] for call in frontier_calls)
            trails = filter(call -> call[1] == :emit_trailing_particle, fixture.calls)
            @test length(trails) == branches
            parameter = tool_call[2][2]
            for (index, trail) in enumerate(trails)
                expected = branches == 1 ?
                    parabola_point(program.Vertex, program.FocalDistance, parameter) :
                    hyperbola_point(program.Center, program.Semimajor,
                        program.Semiminor, parameter; branch=index == 1 ? 1 : -1)
                @test trail[2][2:4] == Tuple(expected)
            end
        end
        @test fixture.stored_state.phase == program.PhaseRise
        for _ in 1:3
            invoke_conic_test_entry(
                entry, fixture, bridge.ANIMATION_OPERATION_TICK, 0.5f0)
        end
        @test fixture.stored_state.phase == program.PhaseHold
        @test any(call -> call[1] == Symbol("hide_$(name)_tool"), fixture.calls)
        @test any(call -> call[1] == :notify_animation_cycle_boundary, fixture.calls)
        for _ in 1:5
            invoke_conic_test_entry(
                entry, fixture, bridge.ANIMATION_OPERATION_TICK, 0.5f0)
        end
        @test fixture.stored_state.phase == program.PhaseDescend
        @test fixture.next_id == branches
        empty!(fixture.calls)
        @test invoke_conic_test_entry(entry, fixture,
            bridge.ANIMATION_OPERATION_SHOW_COMPLETED, 0f0)
        @test count(call -> call[1] == :show_point, fixture.calls) == branches
        @test !any(call -> call[1] == :emit_trailing_particle, fixture.calls)
        @test any(call -> call[1] == Symbol("hide_$(name)_tool"), fixture.calls)
        frontiers = filter(call -> call[1] == Symbol("set_$(name)_frontier"),
            fixture.calls)
        @test all(call[2][3] == program.FinishParameter for call in frontiers)
        @test length(frontiers) == branches
        @test invoke_conic_test_entry(entry, fixture,
            bridge.ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED, 0f0)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_EXIT, 0f0)
        @test !invoke_conic_test_entry(entry, fixture, Int32(-1), 0f0)
        @test_throws ErrorException Base.invokelatest(program.checked, Int32(2))
    end
end
