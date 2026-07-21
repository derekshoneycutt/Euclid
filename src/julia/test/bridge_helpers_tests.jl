if !isdefined(Main, :OdinJuliaBridge)
    include("../odin-julia-bridge.jl")
end

using .OdinJuliaBridge
using Colors
using Test

@testset "bridge_color conversions" begin
    white = OdinJuliaBridge.bridge_color(colorant"white")
    @test white.r == 0xff
    @test white.g == 0xff
    @test white.b == 0xff
    @test white.a == 0xff

    steel_from_symbol = OdinJuliaBridge.bridge_color(:steelblue)
    steel_from_string = OdinJuliaBridge.bridge_color("steelblue")
    @test steel_from_symbol == steel_from_string

    half_alpha = OdinJuliaBridge.bridge_color(RGBA(1.0, 0.0, 0.0, 0.5))
    @test half_alpha.r == 0xff
    @test half_alpha.g == 0x00
    @test half_alpha.b == 0x00
    @test half_alpha.a == 0x80

    @test_throws Exception OdinJuliaBridge.bridge_color(:not_a_real_color_name)
    @test_throws Exception OdinJuliaBridge.bridge_color("not_a_real_color_name")
end

@testset "bridge constants" begin
    @test OdinJuliaBridge.LABEL_DECORATION_NONE == Int32(0)
    @test OdinJuliaBridge.LABEL_DECORATION_PRIME == Int32(1)
    @test OdinJuliaBridge.LABEL_DECORATION_DOUBLEPRIME == Int32(2)
    @test OdinJuliaBridge.LABEL_DECORATION_HAT == Int32(3)
    @test OdinJuliaBridge.LABEL_DECORATION_BAR == Int32(4)

    @test OdinJuliaBridge.BRIDGE_STATUS_OK == Int32(0)
    @test OdinJuliaBridge.BRIDGE_STATUS_NON_CONVERGED == Int32(7)

    @test OdinJuliaBridge.CONSTRAINT_SPEC_TRAITS == Int32(1 << 0)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_ONPOINT == Int32(1 << 1)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_RESTRICTION == Int32(1 << 2)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_BOUNCE == Int32(1 << 3)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_ALLOWANCE == Int32(1 << 4)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_DEPENDON == Int32(1 << 5)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_CHILDOFFSET == Int32(1 << 6)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_DOAPPLY == Int32(1 << 7)
end

@testset "vector wrapper prevalidation" begin
    state_ptr = Ptr{Cvoid}(0)

    @test_throws BoundsError OdinJuliaBridge.set_point_position(state_ptr, 1, Float32[1f0, 2f0])
    @test_throws BoundsError OdinJuliaBridge.set_point_position_status(state_ptr, 1, Float32[1f0, 2f0])
end
