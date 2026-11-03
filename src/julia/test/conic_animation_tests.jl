module ConicAnimationTestEnvironment
module OdinJuliaBridge

const AnimationKey = Main.OdinJuliaBridge.AnimationKey
const BRIDGE_STATUS_OK = Int32(0)
const TROCHOID_EXTERNAL = Main.OdinJuliaBridge.TROCHOID_EXTERNAL
const TROCHOID_INTERNAL = Main.OdinJuliaBridge.TROCHOID_INTERNAL
const HYPERBOLA_POSITIVE = Main.OdinJuliaBridge.HYPERBOLA_POSITIVE
const HYPERBOLA_NEGATIVE = Main.OdinJuliaBridge.HYPERBOLA_NEGATIVE
const HYPERBOLA_BOTH = Main.OdinJuliaBridge.HYPERBOLA_BOTH
using Main.OdinJuliaBridge: hyperbola_branches

"""Decode the real bridge selection for authored content running in this fixture."""
hyperbola_branch_mode(selection::Int32) =
    Main.OdinJuliaBridge.hyperbola_branch_mode(selection)
"""Own recorded calls and mock native storage for one lifecycle test invocation."""
mutable struct Fixture
    calls::Vector{Tuple{Symbol,Tuple,NamedTuple}}
    stored_state::Any
    next_id::UInt64
    rejected_call::Symbol
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
    return name == fixture_from_state(args[1]).rejected_call ? Int32(2) : BRIDGE_STATUS_OK
end

"""Record authored curve color."""
set_point_color(args...; kwargs...) =
    record(:set_point_color, args, (; kwargs...))
"""Record authored curve brush size."""
set_point_brush(args...; kwargs...) =
    record(:set_point_brush, args, (; kwargs...))
"""Record a curve host's position."""
set_point_position(args...; kwargs...) =
    record(:set_point_position, args, (; kwargs...))
"""Record the circle's radius and drawn sweep."""
set_arc_geometry(args...; kwargs...) =
    record(:set_arc_geometry, args, (; kwargs...))
"""Record the cycloid's drawn parameter."""
set_cycloid_frontier(args...; kwargs...) =
    record(:set_cycloid_frontier, args, (; kwargs...))
"""Record the trochoid's drawn parameter."""
set_trochoid_frontier(args...; kwargs...) =
    record(:set_trochoid_frontier, args, (; kwargs...))
"""Record both literal cycloid rail endpoints."""
set_cycloid_tool_line(args...; kwargs...) =
    record(:set_cycloid_tool_line, args, (; kwargs...))
"""Record the cycloid guide's rolling parameter."""
set_cycloid_tool_parameter(args...; kwargs...) =
    record(:set_cycloid_tool_parameter, args, (; kwargs...))
"""Record the cycloid guide's configuration."""
set_cycloid_tool_geometry(args...; kwargs...) =
    record(:set_cycloid_tool_geometry, args, (; kwargs...))
"""Record cycloid guide visibility."""
show_cycloid_tool(args...; kwargs...) =
    record(:show_cycloid_tool, args, (; kwargs...))
"""Record cycloid guide cleanup."""
hide_cycloid_tool(args...; kwargs...) =
    record(:hide_cycloid_tool, args, (; kwargs...))
"""Record the trochoid guide's center and elevation."""
set_trochoid_tool_position(args...; kwargs...) =
    record(:set_trochoid_tool_position, args, (; kwargs...))
"""Record the trochoid guide's rolling parameter."""
set_trochoid_tool_parameter(args...; kwargs...) =
    record(:set_trochoid_tool_parameter, args, (; kwargs...))
"""Record the trochoid guide's configuration."""
set_trochoid_tool_geometry(args...; kwargs...) =
    record(:set_trochoid_tool_geometry, args, (; kwargs...))
"""Record trochoid guide visibility."""
show_trochoid_tool(args...; kwargs...) =
    record(:show_trochoid_tool, args, (; kwargs...))
"""Record trochoid guide cleanup."""
hide_trochoid_tool(args...; kwargs...) =
    record(:hide_trochoid_tool, args, (; kwargs...))
"""Record compass contact and its authored color."""
set_compass_active(args...; kwargs...) =
    record(:set_compass_active, args, (; kwargs...))
"""Record the compass pivot's requested pose."""
lock_compass_joint1(args...; kwargs...) =
    record(:lock_compass_joint1, args, (; kwargs...))
"""Record the compass tracer's requested pose."""
lock_compass_joint2(args...; kwargs...) =
    record(:lock_compass_joint2, args, (; kwargs...))
"""Record compass visibility."""
show_compass(args...; kwargs...) =
    record(:show_compass, args, (; kwargs...))
"""Record compass cleanup."""
hide_compass(args...; kwargs...) =
    record(:hide_compass, args, (; kwargs...))

"""Return a fixture-owned identity only after successful recorded construction."""
function create_curve(name::Symbol, args::Tuple, kwargs::NamedTuple)
    status = record(name, args, kwargs)
    fixture = fixture_from_state(args[1])
    status == BRIDGE_STATUS_OK && (fixture.next_id += 1)
    return (status=status, host_id=fixture.next_id)
end

"""Reserve a fixture-owned circle identity after successful construction."""
create_new_circle(args...; kwargs...) =
    create_curve(:create_new_circle, args, (; kwargs...))
"""Reserve a fixture-owned cycloid identity after successful construction."""
create_new_cycloid(args...; kwargs...) =
    create_curve(:create_new_cycloid, args, (; kwargs...))
"""Reserve a fixture-owned ellipse identity after successful construction."""
create_new_ellipse(args...; kwargs...) =
    create_curve(:create_new_ellipse, args, (; kwargs...))
"""Reserve a fixture-owned cardioid identity after successful construction."""
create_new_cardioid(args...; kwargs...) =
    create_curve(:create_new_cardioid, args, (; kwargs...))
"""Reserve a fixture-owned limacon identity after successful construction."""
create_new_limacon(args...; kwargs...) =
    create_curve(:create_new_limacon, args, (; kwargs...))
"""Reserve a fixture-owned hypocycloid identity after successful construction."""
create_new_hypocycloid(args...; kwargs...) =
    create_curve(:create_new_hypocycloid, args, (; kwargs...))
"""Reserve a fixture-owned deltoid identity after successful construction."""
create_new_deltoid(args...; kwargs...) =
    create_curve(:create_new_deltoid, args, (; kwargs...))
"""Reserve a fixture-owned astroid identity after successful construction."""
create_new_astroid(args...; kwargs...) =
    create_curve(:create_new_astroid, args, (; kwargs...))
"""Reserve a fixture-owned nephroid identity after successful construction."""
create_new_nephroid(args...; kwargs...) =
    create_curve(:create_new_nephroid, args, (; kwargs...))
"""Reserve a fixture-owned epitrochoid identity after successful construction."""
create_new_epitrochoid(args...; kwargs...) =
    create_curve(:create_new_epitrochoid, args, (; kwargs...))
"""Reserve a fixture-owned hypotrochoid identity after successful construction."""
create_new_hypotrochoid(args...; kwargs...) =
    create_curve(:create_new_hypotrochoid, args, (; kwargs...))

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
"""Record the complete hyperbola's common reveal frontier."""
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

"""Return one identity for each complete hyperbola."""
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

"""Load real animation helpers and snapshot a fresh program's test-visible bindings."""
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
    Base.include(owner, joinpath(@__DIR__, "..", "animations.jl"))
    implementation = Base.include(owner,
        joinpath(ProductionContentRoot, "curves", "$name.jl"))
    program = parentmodule(implementation.entry)
    fields = (:Vertex, :Center, :First, :Second, :Radius, :Mode,
        :FixedRadius, :RollingRadius, :TracerDistance, :FocalDistance,
        :Semimajor, :Semiminor, :StartParameter, :FinishParameter,
        :DescendDuration, :DrawDuration, :RiseDuration, :HoldDuration, :TopZ,
        :PhaseDescend, :PhaseDraw, :PhaseRise, :PhaseHold, :checked)
    parameters = (; (field => Base.invokelatest(getfield, program, field)
        for field in fields if Base.invokelatest(isdefined, program, field))...)
    return implementation.entry, parameters
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
        fixture = bridge.Fixture(
            Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(0), :none)
        entry, program = conic_test_program(name)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_ENTER, 0f0)
        @test fixture.next_id == 1
        if branches == 2
            creations = filter(call -> call[1] == :create_new_hyperbola, fixture.calls)
            @test length(creations) == 1
            @test !hasproperty(only(creations)[3], :branch)
            @test fixture.stored_state.curve_id == 1
        end

        independent = bridge.Fixture(
            Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(100), :none)
        saved_state, saved_calls = fixture.stored_state, length(fixture.calls)
        @test invoke_conic_test_entry(
            entry, independent, bridge.ANIMATION_OPERATION_ENTER, 0f0)
        @test independent.next_id == 101
        @test fixture.next_id == 1
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
            @test length(frontier_calls) == 1
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
        @test fixture.next_id == 1
        empty!(fixture.calls)
        @test invoke_conic_test_entry(entry, fixture,
            bridge.ANIMATION_OPERATION_SHOW_COMPLETED, 0f0)
        @test count(call -> call[1] == :show_point, fixture.calls) == 1
        @test !any(call -> call[1] == :emit_trailing_particle, fixture.calls)
        @test any(call -> call[1] == Symbol("hide_$(name)_tool"), fixture.calls)
        frontiers = filter(call -> call[1] == Symbol("set_$(name)_frontier"),
            fixture.calls)
        @test all(call[2][3] == program.FinishParameter for call in frontiers)
        @test length(frontiers) == 1
        @test invoke_conic_test_entry(entry, fixture,
            bridge.ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED, 0f0)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_EXIT, 0f0)
        @test !invoke_conic_test_entry(entry, fixture, Int32(-1), 0f0)
        @test_throws ErrorException Base.invokelatest(program.checked, Int32(2))
    end
end

const CurveTestNames = (
    "circle", "ellipse", "parabola", "hyperbola", "cycloid", "curtate_cycloid",
    "prolate_cycloid", "cardioid", "limacon", "dimpled_limacon", "convex_limacon",
    "deltoid", "astroid", "five_hypocycloid", "eleven_half_hypocycloid",
    "nephroid", "three_dimple_epitrochoid", "five_point_hypotrochoid")

"""Read scalar and vector compass lock arguments through one fixture projection."""
function recorded_curve_position(call)
    value = call[2][2]
    return value isa AbstractVector || value isa Tuple ? Tuple(value) : call[2][2:4]
end

"""Classify an existing leaf by its actual drawing apparatus."""
function curve_test_family(name::String)
    name in ("circle", "parabola", "hyperbola") && return name
    return name in ("cycloid", "curtate_cycloid", "prolate_cycloid") ?
        "cycloid" : "trochoid"
end

"""Evaluate the expected analytic tip independently of the real motion helpers."""
function expected_curve_tip(program, family::String, parameter::Float32, index::Int)
    if family == "circle"
        return Float32[program.Center[1] + program.Radius * cos(parameter),
            program.Center[2] + program.Radius * sin(parameter), 0f0]
    elseif family == "cycloid"
        return Tuple(cycloid_point(program.First, program.Second, program.Radius,
            program.TracerDistance, parameter;
            parameter_start=program.StartParameter,
            parameter_finish=program.FinishParameter))
    elseif family == "trochoid"
        mode = program.Mode == OdinJuliaBridge.TROCHOID_EXTERNAL ?
            TrochoidExternal : TrochoidInternal
        return Tuple(trochoid_point(program.Center, mode, program.FixedRadius,
            program.RollingRadius, program.TracerDistance, parameter))
    elseif family == "parabola"
        return Tuple(parabola_point(program.Vertex, program.FocalDistance, parameter))
    end
    return Tuple(hyperbola_point(program.Center, program.Semimajor,
        program.Semiminor, parameter; branch=index == 1 ? 1 : -1))
end

"""Check each real drawing step against geometry, frontier, apparatus and trails."""
function assert_curve_draw_step(fixture, program, family::String, progress::Float32)
    parameter = program.StartParameter +
        (program.FinishParameter - program.StartParameter) * progress
    trails = filter(call -> call[1] == :emit_trailing_particle, fixture.calls)
    @test length(trails) == (family == "hyperbola" ? 2 : 1)
    if family == "circle"
        arc = only(filter(call -> call[1] == :set_arc_geometry, fixture.calls))
        @test arc[2][5] ≈ (program.FinishParameter - program.StartParameter) * progress
    else
        tool = only(filter(call ->
            call[1] == Symbol("set_$(family)_tool_parameter"), fixture.calls))
        frontiers = filter(call ->
            call[1] == Symbol("set_$(family)_frontier"), fixture.calls)
        @test length(frontiers) == 1
        @test tool[2][2] ≈ parameter
        @test all(call -> call[2][3] == tool[2][2], frontiers)
    end
    for (index, trail) in enumerate(trails)
        expected = expected_curve_tip(program, family, parameter, index)
        @test all(isapprox.(recorded_curve_position(trail), expected; atol=1f-6))
        if family in ("circle", "cycloid", "trochoid")
            lock = only(filter(call -> call[1] == :lock_compass_joint2, fixture.calls))
            @test all(isapprox.(recorded_curve_position(lock), expected; atol=1f-6))
        end
    end
end

@testset "one hyperbola frontier drives two rotated tip trails" begin
    entry, _ = conic_test_program("hyperbola")
    owner = parentmodule(parentmodule(entry))
    helpers = Base.invokelatest(getfield, owner, :EuclidAnimations)
    draw = Base.invokelatest(getfield, helpers, :animate_draw_hyperbola)
    bridge = ConicAnimationTestBridge
    fixture = bridge.Fixture(
        Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(0), :none)
    center = (0.4f0, 0.6f0, 0.2f0)
    GC.@preserve fixture begin
        state = pointer_from_objref(fixture)
        Base.invokelatest(draw, state, 0.5f0, 1f0, center, 0.12f0, 0.1f0,
            1.25f0, -0.75f0; curve_id=UInt64(7), color=:steelblue, rotation=0.4f0)
    end
    frontier = only(filter(call ->
        call[1] == :set_hyperbola_frontier, fixture.calls))
    @test frontier[2][2:3] == (UInt64(7), 0.25f0)
    trails = filter(call -> call[1] == :emit_trailing_particle, fixture.calls)
    @test length(trails) == 2
    for (index, trail) in enumerate(trails)
        expected = hyperbola_point(center, 0.12f0, 0.1f0, 0.25f0;
            branch=index == 1 ? 1 : -1, rotation=0.4f0)
        @test all(isapprox.(recorded_curve_position(trail), Tuple(expected)))
    end
end

"""Record one real lifecycle tick with no calls retained from earlier phases."""
function curve_test_tick(entry, fixture, dt::Float32)
    empty!(fixture.calls)
    return invoke_conic_test_entry(entry, fixture,
        ConicAnimationTestBridge.ANIMATION_OPERATION_TICK, dt)
end

"""Initialize a real authored hyperbola with test-owned native state and selection."""
function initialize_hyperbola_fixture(entry, fixture, branches::Symbol)
    initialize = Base.invokelatest(getfield, parentmodule(entry), :initialize)
    GC.@preserve fixture begin
        Base.invokelatest(initialize, pointer_from_objref(fixture); branches)
    end
    return nothing
end

"""Check selected ink contacts without confusing inactive motion with drawing."""
function assert_hyperbola_contacts(fixture, branches::Symbol, active::Bool)
    contacts = filter(call -> call[1] == :set_hyperbola_tool_active, fixture.calls)
    @test !isempty(contacts)
    @test last(contacts)[2][2] == Int(active)
    if active
        @test last(contacts)[3].branches == branches
    end
end

@testset "immutable hyperbola selection preserves the real authored lifecycle" begin
    bridge = ConicAnimationTestBridge
    for (branches, signs) in ((:both, (1, -1)), (:positive, (1,)), (:negative, (-1,)))
        entry, program = conic_test_program("hyperbola")
        fixture = bridge.Fixture(
            Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(0), :none)
        initialize_hyperbola_fixture(entry, fixture, branches)
        creation = only(filter(call ->
            call[1] == :create_new_hyperbola, fixture.calls))
        @test creation[3].branches == branches
        @test fixture.next_id == 1
        @test fixture.stored_state.branches ==
            OdinJuliaBridge.hyperbola_branches(branches)
        assert_hyperbola_contacts(fixture, branches, false)
        curve_test_tick(entry, fixture, program.DescendDuration / 2)
        assert_hyperbola_contacts(fixture, branches, false)
        @test !any(call -> call[1] == :emit_trailing_particle, fixture.calls)
        curve_test_tick(entry, fixture, program.DescendDuration / 2)
        assert_hyperbola_contacts(fixture, branches, true)
        curve_test_tick(entry, fixture, program.DrawDuration / 2)
        frontier = only(filter(call ->
            call[1] == :set_hyperbola_frontier, fixture.calls))
        @test frontier[2][2] == fixture.stored_state.curve_id
        tool = only(filter(call ->
            call[1] == :set_hyperbola_tool_parameter, fixture.calls))
        @test tool[2][2] == frontier[2][3]
        assert_hyperbola_contacts(fixture, branches, true)
        trails = filter(call -> call[1] == :emit_trailing_particle, fixture.calls)
        @test length(trails) == length(signs)
        for (trail, sign) in zip(trails, signs)
            expected = hyperbola_point(program.Center, program.Semimajor,
                program.Semiminor, frontier[2][3]; branch=sign)
            @test all(isapprox.(recorded_curve_position(trail), Tuple(expected)))
        end
        curve_test_tick(entry, fixture, program.DrawDuration / 2)
        assert_hyperbola_contacts(fixture, branches, false)
        curve_test_tick(entry, fixture, program.RiseDuration)
        assert_hyperbola_contacts(fixture, branches, false)
        @test !any(call -> call[1] == :emit_trailing_particle, fixture.calls)
        curve_test_tick(entry, fixture, program.HoldDuration)
        @test fixture.stored_state.branches ==
            OdinJuliaBridge.hyperbola_branches(branches)
        @test fixture.next_id == 1
        empty!(fixture.calls)
        @test invoke_conic_test_entry(entry, fixture,
            bridge.ANIMATION_OPERATION_SHOW_COMPLETED, 0f0)
        assert_hyperbola_contacts(fixture, branches, false)
        @test !any(call -> call[1] == :emit_trailing_particle, fixture.calls)
        @test fixture.next_id == 1
        @test invoke_conic_test_entry(entry, fixture,
            bridge.ANIMATION_OPERATION_EXIT, 0f0)
    end
end

@testset "selected hyperbola trails use rotated intrinsic axes" begin
    entry, _ = conic_test_program("hyperbola")
    owner = parentmodule(parentmodule(entry))
    helpers = Base.invokelatest(getfield, owner, :EuclidAnimations)
    draw = Base.invokelatest(getfield, helpers, :animate_draw_hyperbola)
    bridge = ConicAnimationTestBridge
    center = (0.4f0, 0.6f0, 0.2f0)
    for (branches, sign) in ((:positive, 1), (:negative, -1))
        fixture = bridge.Fixture(
            Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(0), :none)
        GC.@preserve fixture begin
            Base.invokelatest(draw, pointer_from_objref(fixture), 0.5f0, 1f0,
                center, 0.12f0, 0.1f0, 1.25f0, -0.75f0;
                curve_id=UInt64(7), color=:steelblue, rotation=0.8f0, branches)
        end
        trail = only(filter(call -> call[1] == :emit_trailing_particle, fixture.calls))
        expected = hyperbola_point(center, 0.12f0, 0.1f0, 0.25f0;
            branch=sign, rotation=0.8f0)
        @test all(isapprox.(recorded_curve_position(trail), Tuple(expected)))
        @test length(
            filter(call -> call[1] == :set_hyperbola_frontier, fixture.calls)) == 1
    end
end

@testset "shared curve helpers preserve directed parameters and rotated tracers" begin
    @test EuclidAnimations.curve_parameter(-1f0, 1f0, 1.25f0, -0.75f0) == 1.25f0
    @test EuclidAnimations.curve_parameter(2f0, 1f0, 1.25f0, -0.75f0) == -0.75f0
    @test EuclidAnimations.curve_parameter(0.5f0, 1f0, 1.25f0, -0.75f0) == 0.25f0
    entry, _ = conic_test_program("ellipse")
    owner = parentmodule(parentmodule(entry))
    helpers = Base.invokelatest(getfield, owner, :EuclidAnimations)
    draw = Base.invokelatest(getfield, helpers, :animate_draw_trochoid)
    place = Base.invokelatest(getfield, helpers, :place_trochoid_tools)
    bridge = ConicAnimationTestBridge
    fixture = bridge.Fixture(
        Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(0), :none)
    center = (0.5f0, 0.5f0, 0f0)
    GC.@preserve fixture begin
        state = pointer_from_objref(fixture)
        Base.invokelatest(draw, state, 2f0, 1f0, center, 1.25f0, -0.75f0;
            mode=bridge.TROCHOID_INTERNAL, fixed_radius=0.3f0,
            rolling_radius=0.1f0, tracer_distance=0.06f0,
            curve_id=UInt64(1), color=:steelblue, brush=5f0,
            rotation=0.4f0, tracer_phase=0.2f0)
        @test_throws ArgumentError Base.invokelatest(
            place, state, center, Int32(2), 0.3f0, 0.1f0, 0.06f0, 0f0, 0f0)
    end
    frontier = only(filter(call -> call[1] == :set_trochoid_frontier, fixture.calls))
    @test frontier[2][3] == -0.75f0
    trail = only(filter(call -> call[1] == :emit_trailing_particle, fixture.calls))
    expected = Tuple(trochoid_point(center, TrochoidInternal,
        0.3f0, 0.1f0, 0.06f0, -0.75f0; rotation=0.4f0, tracer_phase=0.2f0))
    @test recorded_curve_position(trail) == expected
end

@testset "all curve leaves own and execute their complete flow" begin
    bridge = ConicAnimationTestBridge
    for name in CurveTestNames
        family = curve_test_family(name)
        entry, program = conic_test_program(name)
        source = read(joinpath(ProductionContentRoot, "curves", "$name.jl"), String)
        for lifecycle in ("initialize", "reset_cycle_state", "loop",
            "show_completed", "clean", "animation_entry")
            @test occursin("function $lifecycle(", source)
        end
        @test !occursin("_shared.jl", source)
        @test !occursin("function instrument_pose", source)
        fixture = bridge.Fixture(
            Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(0), :none)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_ENTER, 0f0)
        identities = fixture.next_id
        independent = bridge.Fixture(
            Tuple{Symbol,Tuple,NamedTuple}[], nothing, UInt64(100), :none)
        saved_state = fixture.stored_state
        @test invoke_conic_test_entry(
            entry, independent, bridge.ANIMATION_OPERATION_ENTER, 0f0)
        @test fixture.stored_state === saved_state
        @test independent.next_id == 100 + identities
        @test curve_test_tick(entry, fixture, program.DescendDuration / 2f0)
        @test fixture.stored_state.phase == program.PhaseDescend
        @test !any(call -> call[1] == :emit_trailing_particle, fixture.calls)
        @test curve_test_tick(entry, fixture, program.DescendDuration + 1f0)
        @test fixture.stored_state.phase == program.PhaseDraw
        positions = filter(call -> call[1] == :lock_compass_joint2 ||
            call[1] == Symbol("set_$(family)_tool_position"), fixture.calls)
        @test all(call -> last(recorded_curve_position(call)) == 0f0, positions)
        @test curve_test_tick(entry, fixture, program.DrawDuration / 2f0)
        assert_curve_draw_step(fixture, program, family, 0.5f0)
        @test curve_test_tick(entry, fixture, program.DrawDuration + 1f0)
        assert_curve_draw_step(fixture, program, family, 1f0)
        @test fixture.stored_state.phase == program.PhaseRise
        @test curve_test_tick(entry, fixture, program.RiseDuration + 1f0)
        @test fixture.stored_state.phase == program.PhaseHold
        @test !any(call -> call[1] == :emit_trailing_particle, fixture.calls)
        @test count(call -> call[1] == :notify_animation_cycle_boundary,
            fixture.calls) == 1
        @test any(call -> call[1] == (family in ("circle", "cycloid", "trochoid") ?
            :hide_compass : Symbol("hide_$(family)_tool")), fixture.calls)
        @test curve_test_tick(entry, fixture, program.HoldDuration + 1f0)
        @test fixture.stored_state.phase == program.PhaseDescend
        @test fixture.next_id == identities
        empty!(fixture.calls)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_SHOW_COMPLETED, 0f0)
        @test count(call -> call[1] == :show_point, fixture.calls) == identities
        @test !any(call -> call[1] == :emit_trailing_particle, fixture.calls)
        @test curve_test_tick(entry, fixture, program.DescendDuration)
        @test curve_test_tick(entry, fixture, program.DrawDuration / 2f0)
        empty!(fixture.calls)
        @test invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_EXIT, 0f0)
        contacts = filter(call -> endswith(string(call[1]), "_active"), fixture.calls)
        @test !isempty(contacts)
        @test all(call -> call[2][2] == 0, contacts)
        fixture.rejected_call = family == "circle" ? :set_arc_geometry :
            Symbol("set_$(family)_frontier")
        @test_throws ErrorException invoke_conic_test_entry(
            entry, fixture, bridge.ANIMATION_OPERATION_ENTER, 0f0)
    end
end
