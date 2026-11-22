using Test

if !isdefined(Main, :EuclidAnimations)
    include("../odin-julia-bridge.jl")
    include("../geometry.jl")
    include("../animations.jl")
end

module NativeCompoundTestEnvironment
module OdinJuliaBridge
const BRIDGE_STATUS_OK = Int32(0)
const AnimationKey = Main.OdinJuliaBridge.AnimationKey
using Main.OdinJuliaBridge: native_modifier_request, bridge_color
for name in names(Main.OdinJuliaBridge; all=true)
    startswith(string(name), "NATIVE_MODIFIER_") || continue
    @eval const $name = getfield(Main.OdinJuliaBridge, $(QuoteNode(name)))
end

"""Own captured requests and injected capture status for a single adapter test."""
mutable struct Fixture
    requests::Vector{Main.OdinJuliaBridge.BridgeNativeModifierRequest}
    status::Int32
    arcs::Vector{NTuple{3,Float32}}
end

"""Keep direct full-sweep completion observations separate from sampled requests."""
Fixture(requests, status) = Fixture(requests, status, NTuple{3,Float32}[])

"""Record production-shaped payloads without calling the host executable."""
function apply_native_modifier_request(state::Ptr{Cvoid}, request)
    fixture = unsafe_pointer_to_objref(state)::Fixture
    push!(fixture.requests, request)
    return fixture.status
end

"""Record intentional full-sweep completion while sampled tool motion stays native."""
function set_arc_geometry(state::Ptr{Cvoid}, _entity, radius, start, sweep)
    fixture = unsafe_pointer_to_objref(state)::Fixture
    push!(fixture.arcs, (Float32(radius), Float32(start), Float32(sweep)))
    return fixture.status
end
end

module EuclidAnimations
using ..OdinJuliaBridge
using LinearAlgebra
include("../animations/common.jl")
include("../animations/transforms.jl")
include("../animations/pen.jl")
include("../animations/compass.jl")
include("../animations/strokes.jl")
include("../animations/circles.jl")
include("../animations/completion.jl")
include("../animations/repl.jl")
end
end

"""Exercise every basic overload and native completion without legacy bridge symbols."""
function native_basic_adapter_cases(helpers, state, first, last)
    return [
        (0x04, () -> helpers.place_pen_at_angles(state, first, π / 3, 0)),
        (0x04, () -> helpers.place_pen_at_angles(state, first..., π / 3, 0)),
        (0x02, () -> helpers.animate_pen_descend(state, 0.5, 1, 1.4, first[1:2]...)),
        (0x03, () -> helpers.animate_pen_rise(state, 0.5, 1, 1.4, first[1:2]...)),
        (0x03, () -> helpers.animate_pen_rise(state, 0.5, 1, 0.2, 1.4, first[1:2]...)),
        (0x05, () -> helpers.animate_compass_descend(
            state, 0.5, 1, 1.4, first[1:2]..., last[1:2]...)),
        (0x06, () -> helpers.animate_compass_rise(
            state, 0.5, 1, 1.4, first[1:2]..., last[1:2]...)),
        (0x07, () -> helpers.animate_draw_point(state, 0.5, 1, first, 0.01, :black, 10)),
        (0x08, () -> helpers.animate_draw_line(state, 0.5, 1, first, last;
            penbrush=0.01, pencolor=:black,
            line_host_id=10, line_joint1_id=11, line_joint2_id=12)),
        (0x09, () -> helpers.animate_draw_circle(state, 0.5, 1, first, last, π, 0.2;
            marker_host_id=10)),
        (0x0a, () -> helpers.animate_draw_filledcircle(state, 0.5, 1, first, last, π, 0.2;
            marker_host_id=10)),
        (0x0b, () -> helpers.complete_point(state, first, 0.01, :black, 10)),
        (0x0c, () -> helpers.complete_line(state, first, last;
            penbrush=0.01, pencolor=:black, line_host_id=10,
            line_joint1_id=11, line_joint2_id=12)),
        (0x0d, () -> helpers.complete_circle(
            state, first, last, π, 0.2; marker_host_id=10))]
end

@testset "native basic overloads, completion and rejection closure" begin
    bridge = NativeCompoundTestEnvironment.OdinJuliaBridge
    helpers = NativeCompoundTestEnvironment.EuclidAnimations
    fixture = bridge.Fixture(OdinJuliaBridge.BridgeNativeModifierRequest[], Int32(0))
    first, last = Float32[0.2, 0.3, 0], Float32[0.4, 0.3, 0]
    GC.@preserve fixture begin
        state = pointer_from_objref(fixture)
        for (kind, invoke) in native_basic_adapter_cases(helpers, state, first, last)
            fixture.status = Int32(0)
            before = length(fixture.requests)
            result = invoke()
            @test length(fixture.requests) > before
            @test fixture.requests[end].kind == kind
            @test kind < 11 ? isnothing(result) : result == 0
            fixture.status = Int32(2)
            if kind < 11
                @test_throws ErrorException invoke()
            else
                @test invoke() == Int32(2)
            end
        end
        fixture.status = Int32(0)
        helpers.animate_repl_draw_point(state, 0.1, 1, first, 0.01, :black, 10)
        @test fixture.requests[end].kind == 2
        helpers.animate_repl_draw_line(state, 0.5, 1, first, last;
            line_host_id=10, line_joint1_id=11, line_joint2_id=12)
        @test fixture.requests[end].kind == 8
        helpers.animate_repl_draw_circle(state, 0.5, 1, first, last, π, 0.2;
            marker_host_id=10)
        @test fixture.requests[end].kind == 9
        helpers.animate_repl_draw_filledcircle(state, 0.5, 1, first, last, π, 0.2;
            marker_host_id=10)
        @test fixture.requests[end].kind == 10
    end
end

@testset "Terminal coordinators preserve phases and checked direct completion" begin
    bridge = NativeCompoundTestEnvironment.OdinJuliaBridge
    helpers = NativeCompoundTestEnvironment.EuclidAnimations
    fixture = bridge.Fixture(OdinJuliaBridge.BridgeNativeModifierRequest[], Int32(0))
    first, last = Float32[0.2, 0.3, 0], Float32[0.4, 0.3, 0]
    GC.@preserve fixture begin
        state = pointer_from_objref(fixture)
        for elapsed in (0f0, 0.2f0, 0.5f0, 0.8f0, 1f0), draw in (
            helpers.animate_repl_draw_circle, helpers.animate_repl_draw_filledcircle)
            empty!(fixture.requests)
            empty!(fixture.arcs)
            draw(state, elapsed, 1, first, last, -π, 0.2; marker_host_id=10)
            @test !isempty(fixture.requests)
            if elapsed < 0.2f0
                @test only(fixture.requests).kind == 5
            elseif elapsed < 0.8f0
                @test only(fixture.requests).kind ==
                    (draw === helpers.animate_repl_draw_circle ? 9 : 10)
            else
                @test only(fixture.requests).kind == 6
                @test only(fixture.arcs) == (0.2f0, 0f0, Float32(-π))
            end
        end
        fixture.status = Int32(2)
        @test_throws ErrorException helpers.animate_repl_draw_circle(
            state, 1, 1, first, last, π, 0.2; marker_host_id=10)
    end
end

@testset "point transform overloads retain native status returns" begin
    bridge = NativeCompoundTestEnvironment.OdinJuliaBridge
    helpers = NativeCompoundTestEnvironment.EuclidAnimations
    fixture = bridge.Fixture(OdinJuliaBridge.BridgeNativeModifierRequest[], Int32(0))
    first, last = Float32[0.2, 0.3, 0], Float32[1, 0, 0]
    GC.@preserve fixture begin
        state = pointer_from_objref(fixture)
        for status in (Int32(0), Int32(2))
            fixture.status = status
            @test helpers.transform_translate_point(
                state, 10, first, last, 0.5, 1) == status
            @test helpers.transform_translate_point(
                state, 10, first, last, 2, 0.5, 1) == status
            @test fixture.requests[end].kind == 14
            for rotate in (
                helpers.transform_rotate_point_x, helpers.transform_rotate_point_y,
                helpers.transform_rotate_point_z)
                @test rotate(state, 10, first, -4π, 0.5, 1) == status
                @test fixture.requests[end].kind == 15
                @test fixture.requests[end].angle == Float32(-4π)
            end
            @test helpers.transform_reflect2d_point(state, 10, first, zeros(Float32, 3),
                last, 0.5, 1) == status
            @test fixture.requests[end].kind == 16
            @test helpers.transform_reflect2d_point_negative(
                state, 10, first, zeros(Float32, 3), last, 0.5, 1) == status
            @test fixture.requests[end].kind == 17
            for reflect in (helpers.transform_reflect2d_point_x_axis,
                helpers.transform_reflect2d_point_y_axis,
                helpers.transform_reflect2d_point_diag_pos,
                helpers.transform_reflect2d_point_diag_neg)
                @test reflect(state, 10, first, 0.5, 1) == status
                @test fixture.requests[end].kind == 16
            end
        end
    end
end

@testset "native compound production adapters" begin
    bridge = NativeCompoundTestEnvironment.OdinJuliaBridge
    helpers = NativeCompoundTestEnvironment.EuclidAnimations
    fixture = bridge.Fixture(OdinJuliaBridge.BridgeNativeModifierRequest[], Int32(0))
    first = Float32[0.2, 0.3, 0]
    middle = Float32[0.4, 0.3, 0]
    last = Float32[0.4, 0.5, 0]
    GC.@preserve fixture begin
        state = pointer_from_objref(fixture)
        helpers.animate_pen_tilt(state, 0.5, 1, first, 0, π / 2, 0)
        @test lastindex(fixture.requests) == 1
        @test fixture.requests[end].kind == OdinJuliaBridge.NATIVE_MODIFIER_PEN_TILT
        helpers.animate_pen_cone(state, 0.5, first, π / 3, 6)
        @test fixture.requests[end].kind == OdinJuliaBridge.NATIVE_MODIFIER_PEN_CONE
        helpers.animate_pen_cone(state, 0.5, first..., π / 3, 6)
        @test fixture.requests[end].kind == OdinJuliaBridge.NATIVE_MODIFIER_PEN_CONE
        position = helpers.animate_pen_drag(
            state, 0.5, 1, first, last, π / 3, 0, :steelblue)
        @test position ≈ (first + last) / 2
        @test fixture.requests[end].kind == OdinJuliaBridge.NATIVE_MODIFIER_PEN_DRAG
        helpers.animate_pen_arcmove(state, 0.5, 1, first, last, 0.2, 2, :none)
        @test fixture.requests[end].kind == OdinJuliaBridge.NATIVE_MODIFIER_PEN_TRANSFER
        @test !fixture.requests[end].flag
        helpers.animate_compass_arcmove(state, 0.5, 1, first, last, last, first)
        @test fixture.requests[end].kind ==
            OdinJuliaBridge.NATIVE_MODIFIER_COMPASS_TRANSFER
        @test fixture.requests[end].displacement == Tuple(first)
        helpers.animate_highlight_point(state, 0.5, 1, first, :steelblue)
        @test fixture.requests[end].kind ==
            OdinJuliaBridge.NATIVE_MODIFIER_PEN_HIGHLIGHT_POINT
        helpers.animate_pen_tilt_and_drag(state, 0.5, 1, first, last, :steelblue)
        @test fixture.requests[end].kind == OdinJuliaBridge.NATIVE_MODIFIER_PEN_STROKE
        helpers.animate_extend_line(state, 0.5, 1, first, middle, last, 0.01, :steelblue;
            line_host_id=10, line_joint1_id=11, line_joint2_id=12)
        @test fixture.requests[end].kind == OdinJuliaBridge.NATIVE_MODIFIER_EXTEND_LINE
        @test fixture.requests[end].third == Tuple(first)
        before = length(fixture.requests)
        helpers.animate_draw_two_line_segments(state, 0.5, 1, first, middle, last,
            0.01, :steelblue; line1_host_id=10, line1_joint1_id=11, line1_joint2_id=12,
            line2_host_id=20, line2_joint1_id=21, line2_joint2_id=22)
        @test length(fixture.requests) == before + 2
        @test !fixture.requests[end - 1].flag && fixture.requests[end].flag
        @test fixture.requests[end].entity == 20
        helpers.animate_compass_arc_highlight(
            state, 0.5, 1, first, last, -π, 0.2, :steelblue)
        @test fixture.requests[end].kind ==
            OdinJuliaBridge.NATIVE_MODIFIER_COMPASS_HIGHLIGHT
        @test !fixture.requests[end].flag
        helpers.animate_compass_fill_arc_highlight(
            state, 0.5, 1, first, last, -π, 0.2, :steelblue)
        @test fixture.requests[end].flag
        helpers.animate_draw_filledcircle(state, 0.5, 1, first, last, π, 0.2;
            color=:steelblue, marker_host_id=10, formation=false)
        @test fixture.requests[end].kind ==
            OdinJuliaBridge.NATIVE_MODIFIER_DRAW_FILLED_CIRCLE
        @test !fixture.requests[end].flag
        status = helpers.animate_reflect2d_filled_angle_marker(state, 10;
            start_center=first, start_point=middle, end_point=last,
            line_point_a=first, line_point_b=middle,
            current_time=0.5, total_duration=1)
        @test status == OdinJuliaBridge.BRIDGE_STATUS_OK
        @test fixture.requests[end].kind ==
            OdinJuliaBridge.NATIVE_MODIFIER_REFLECT_ANGLE_MARKER
        fixture.status = Int32(2)
        @test_throws ErrorException helpers.animate_pen_cone(state, 0.5, first, π / 3, 6)
    end
end
