if !isdefined(Main, :OdinJuliaBridge)
    include("../odin-julia-bridge.jl")
end
if !isdefined(Main, :EuclidGeometry)
    include("../geometry.jl")
end
if !isdefined(Main, :EuclidAnimations)
    include("../animations.jl")
end
if !isdefined(Main, :EuclidRepl)
    if !isdefined(Main, :Terminal)
        include("../terminal.jl")
    end
    include("../euclidrepl.jl")
end

using Test
using .EuclidAnimations
using .EuclidRepl
using .OdinJuliaBridge

const NATIVE_MODIFIER_EXPORT_INVENTORY = Dict(
    :animate_pen_descend => :basic,
    :animate_pen_rise => :basic,
    :animate_compass_descend => :basic,
    :animate_compass_rise => :basic,
    :animate_pen_tilt => :sampled,
    :animate_pen_cone => :sampled,
    :animate_pen_drag => :basic,
    :animate_pen_arcmove => :sampled,
    :animate_compass_arcmove => :sampled,
    :animate_highlight_point => :sampled,
    :animate_extend_line => :sampled,
    :animate_pen_tilt_and_drag => :sampled,
    :animate_draw_point => :basic,
    :animate_draw_line => :basic,
    :animate_draw_filledcircle => :basic,
    :animate_draw_two_line_segments => :sampled,
    :animate_draw_circle => :basic,
    :animate_compass_fill_arc_highlight => :sampled,
    :animate_compass_arc_highlight => :sampled,
    :animate_repl_draw_point => :basic,
    :animate_repl_draw_line => :basic,
    :animate_repl_draw_circle => :basic,
    :animate_repl_draw_filledcircle => :basic,
    :transform_translate_point => :basic,
    :transform_rotate_point => :basic,
    :transform_rotate_point_x => :basic,
    :transform_rotate_point_y => :basic,
    :transform_rotate_point_z => :basic,
    :transform_reflect2d_point => :basic,
    :transform_reflect2d_point_negative => :basic,
    :transform_reflect2d_point_x_axis => :basic,
    :transform_reflect2d_point_y_axis => :basic,
    :transform_reflect2d_point_diag_pos => :basic,
    :transform_reflect2d_point_diag_neg => :basic,
    :reflected_angle_marker_pose_xy => :pure,
    :animate_reflect2d_filled_angle_marker => :sampled,
    :reveal_label => :native_reveal,
    :reveal_region => :native_reveal,
    :animate_cycloid_descend => :sampled,
    :animate_draw_cycloid => :sampled,
    :animate_cycloid_rise => :sampled,
    :animate_trochoid_descend => :sampled,
    :animate_draw_trochoid => :sampled,
    :animate_trochoid_rise => :sampled,
    :animate_parabola_descend => :sampled,
    :animate_draw_parabola => :sampled,
    :animate_parabola_rise => :sampled,
    :animate_hyperbola_descend => :sampled,
    :animate_draw_hyperbola => :sampled,
    :animate_hyperbola_rise => :sampled,)

const NATIVE_MODIFIER_SUPPORT_INVENTORY = (:normalized_progress, :curve_parameter,
    :displacement_from_vector_and_length, :rotate_point_about_axis_line,
    :reflect_point_xy_across_line, :reflection_arc_point_above_surface,
    :reflection_arc_point_below_surface,)

const NATIVE_MODIFIER_NONEXPORT_INVENTORY = Set([
    :TransformEps, :checked_curve_status, :segments_intersect_xy,
    :complete_point, :complete_line, :complete_circle,
    :place_cycloid_tools, :place_trochoid_tools,
    :place_hyperbola_tool, :place_parabola_tool,])

"""Collect EuclidAnimations helper calls from authored Julia sources."""
function inventory_helper_calls(root::AbstractString)
    calls = Set{Symbol}()
    if isdir(root)
        for (directory, _, files) in walkdir(root)
            for file in files
                endswith(file, ".jl") || continue
                source = read(joinpath(directory, file), String)
                for match in eachmatch(r"EuclidAnimations\.([A-Za-z_][A-Za-z0-9_]*)", source)
                    push!(calls, Symbol(match.captures[1]))
                end
            end
        end
    else
        source = read(root, String)
        for match in eachmatch(r"EuclidAnimations\.([A-Za-z_][A-Za-z0-9_]*)", source)
            push!(calls, Symbol(match.captures[1]))
        end
    end
    return calls
end

"""Return Float32 progress without a native clock or stored motion state."""
function test_progress(time::Real, duration::Real)
    return EuclidAnimations.normalized_progress(time, duration)
end

@testset "exported helper inventory" begin
    exported = Set(
        name for name in names(EuclidAnimations; all=false)
        if name != :EuclidAnimations)
    @test exported == Set(keys(NATIVE_MODIFIER_EXPORT_INVENTORY))
    @test length(NATIVE_MODIFIER_EXPORT_INVENTORY) == length(exported)
    @test all(disposition ->
        disposition in (:basic, :sampled, :pure, :native_reveal),
        values(NATIVE_MODIFIER_EXPORT_INVENTORY))
    for name in exported
        expected = name in (:animate_pen_cone, :animate_pen_rise,
            :transform_translate_point) ? 2 : 1
        @test length(methods(getfield(EuclidAnimations, name))) == expected
    end
    @test length(methods(EuclidAnimations.place_pen_at_angles)) == 2
    for name in NATIVE_MODIFIER_SUPPORT_INVENTORY
        @test isdefined(EuclidAnimations, name)
    end
end

@testset "authored call-site inventory" begin
    content_calls = inventory_helper_calls(
        normpath(joinpath(@__DIR__, "..", "..", "content")))
    repl_calls = inventory_helper_calls(
        normpath(joinpath(@__DIR__, "..", "euclidrepl.jl")))
    all_calls = union(content_calls, repl_calls)
    known_calls = union(
        Set(keys(NATIVE_MODIFIER_EXPORT_INVENTORY)),
        NATIVE_MODIFIER_SUPPORT_INVENTORY,
        NATIVE_MODIFIER_NONEXPORT_INVENTORY)
    unknown = setdiff(all_calls, known_calls)
    @test isempty(unknown)
    @test !isempty(content_calls)
    @test :animate_draw_line in content_calls
    @test :animate_draw_circle in content_calls
    @test :animate_repl_draw_line in repl_calls
end

@testset "phase boundary and jump parity" begin
    @test test_progress(-1, 1) == 0f0
    @test test_progress(0, 1) == 0f0
    @test test_progress(1 / 4, 1) == 0.25f0
    @test test_progress(1 / 2, 1) == 0.5f0
    @test test_progress(1, 1) == 1f0
    @test test_progress(100, 1) == 1f0
    @test test_progress(0, 0) == 1f0
    @test test_progress(-1, 0) == 1f0
    @test EuclidAnimations.curve_parameter(-1, 2, 3f0, 7f0) == 3f0
    @test EuclidAnimations.curve_parameter(1, 2, 3f0, 7f0) == 5f0
    @test EuclidAnimations.curve_parameter(2, 2, 3f0, 7f0) == 7f0
    @test EuclidAnimations.curve_parameter(100, 2, 3f0, 7f0) == 7f0
end

@testset "numeric transform tolerances" begin
    displacement = EuclidAnimations.displacement_from_vector_and_length(
        Float32[3, 4, 0], 10)
    @test displacement ≈ Float32[6, 8, 0] atol=1f-6

    rotated = EuclidAnimations.rotate_point_about_axis_line(
        Float32[1, 0, 0], Float32[0, 0, 0],
        Float32[0, 0, 1], π / 2)
    @test rotated ≈ Float32[0, 1, 0] atol=1f-6

    reflected = EuclidAnimations.reflect_point_xy_across_line(
        Float32[1, 2, 3], Float32[0, 0, 0],
        Float32[1, 1, 0])
    @test reflected ≈ Float32[2, 1, 3] atol=1f-6
end

@testset "native modifier payload contract" begin
    request = native_modifier_request(
        NATIVE_MODIFIER_TRANSLATE_POINT;
        entity=17,
        elapsed=0.25,
        duration=1,
        start_position=(1f0, 2f0, 3f0),
        displacement=(4f0, 4f0, 4f0))
    @test request.kind == NATIVE_MODIFIER_TRANSLATE_POINT
    @test request.entity == UInt64(17)
    @test request.elapsed == Cfloat(0.25)
    @test request.duration == Cfloat(1)
    @test request.start == (Cfloat(1), Cfloat(2), Cfloat(3))
    @test request.displacement ==
        (Cfloat(4), Cfloat(4), Cfloat(4))
    @test sizeof(BridgeNativeModifierRequest) == 144
    @test fieldnames(BridgeNativeModifierRequest) == (
        :kind, :entity, :second_entity, :third_entity, :elapsed, :duration,
        :start, :second, :third, :displacement, :axis_a, :axis_b,
        :angle, :radius, :brush, :color_packed, :scalar, :integer, :flag)
    @test ntuple(i -> fieldoffset(BridgeNativeModifierRequest, i), 19) == (
        0, 8, 16, 24, 32, 36, 40, 52, 64, 76, 88, 100, 112, 116, 120, 124, 128, 132, 136)
    @test isdefined(OdinJuliaBridge, :apply_native_modifier_request)
    kinds = sort([getfield(OdinJuliaBridge, name) for name in
        names(OdinJuliaBridge; all=true) if startswith(String(name), "NATIVE_MODIFIER_")])
    @test kinds == Int32.(0:46)
end

@testset "Terminal and stochastic effect inventory" begin
    repl_source = read(normpath(joinpath(
        @__DIR__, "..", "euclidrepl.jl")), String)
    @test occursin("animate_repl_draw_point", repl_source)
    @test occursin("animate_repl_draw_line", repl_source)
    @test occursin("animate_repl_draw_circle", repl_source)
    @test occursin("animate_repl_draw_filledcircle", repl_source)

    @test NATIVE_MODIFIER_EXPORT_INVENTORY[:animate_draw_filledcircle] == :basic
end
