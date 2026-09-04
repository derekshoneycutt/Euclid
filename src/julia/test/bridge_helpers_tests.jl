if !isdefined(Main, :OdinJuliaBridge)
    include("../odin-julia-bridge.jl")
end

using .OdinJuliaBridge
using Colors
using Test

struct BridgeStatePair
    phase::UInt8
    elapsed::Float32
end

struct BridgeStatePairWide
    phase::UInt16
    elapsed::Float32
end

struct BridgeStateLarge
    payload::NTuple{256,UInt8}
end

@testset "bridge_color conversions" begin
    white = OdinJuliaBridge.bridge_color(colorant"white")
    @test white.r == 0xff
    @test white.g == 0xff
    @test white.b == 0xff
    @test white.a == 0xff

    steel_from_symbol = OdinJuliaBridge.bridge_color(:steelblue)
    steel_from_string = OdinJuliaBridge.bridge_color("steelblue")
    @test steel_from_symbol == steel_from_string

    @test OdinJuliaBridge.bridge_color(:julia_blue) ==
        OdinJuliaBridge.BridgeColor(0x40, 0x63, 0xd8, 0xff)
    @test OdinJuliaBridge.bridge_color("julia_green") ==
        OdinJuliaBridge.BridgeColor(0x38, 0x98, 0x26, 0xff)
    @test OdinJuliaBridge.bridge_color(:julia_purple) ==
        OdinJuliaBridge.BridgeColor(0x95, 0x58, 0xb2, 0xff)
    @test OdinJuliaBridge.bridge_color("julia_red") ==
        OdinJuliaBridge.BridgeColor(0xcb, 0x3c, 0x33, 0xff)

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
    @test OdinJuliaBridge.LABEL_DECORATION_TRIPLEPRIME == Int32(3)
    @test OdinJuliaBridge.LABEL_DECORATION_HAT == Int32(4)
    @test OdinJuliaBridge.LABEL_DECORATION_BAR == Int32(5)

    @test OdinJuliaBridge.BRIDGE_STATUS_OK == Int32(0)
    @test OdinJuliaBridge.BRIDGE_STATUS_NON_CONVERGED == Int32(7)
    @test OdinJuliaBridge.BRIDGE_STATUS_NOT_FOUND == Int32(8)
    @test OdinJuliaBridge.BRIDGE_STATUS_SCHEMA_MISMATCH == Int32(9)
    @test OdinJuliaBridge.BRIDGE_VERSION == Int32(5)
    @test OdinJuliaBridge.BRIDGE_FEATURE_TYPED_ANIMATION_STATE == Int32(1 << 4)
    @test OdinJuliaBridge.BRIDGE_FEATURE_ANIMATION_METADATA_CATALOG == Int32(1 << 5)

    @test OdinJuliaBridge.CONSTRAINT_SPEC_TRAITS == Int32(1 << 0)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_ONPOINT == Int32(1 << 1)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_RESTRICTION == Int32(1 << 2)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_BOUNCE == Int32(1 << 3)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_ALLOWANCE == Int32(1 << 4)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_DEPENDON == Int32(1 << 5)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_CHILDOFFSET == Int32(1 << 6)
    @test OdinJuliaBridge.CONSTRAINT_SPEC_DOAPPLY == Int32(1 << 7)
end

@testset "typed animation state schema" begin
    key = OdinJuliaBridge.AnimationKey{BridgeStatePair}(0x01)
    @test key.value == UInt64(1)
    schema = OdinJuliaBridge.animation_schema_id(BridgeStatePair)
    @test schema == (0x96072c48f0d10eb0, 0x6783d4a92efbb0a7)
    @test schema == OdinJuliaBridge.animation_schema_id(BridgeStatePair)
    @test schema != OdinJuliaBridge.animation_schema_id(BridgeStatePairWide)
    @test schema != OdinJuliaBridge.animation_schema_id(Tuple{UInt8,Float32})
    @test OdinJuliaBridge.animation_schema_id(BridgeStateLarge) ==
        (0xc4a2f7abe873db7a, 0x8621b098c2e28741)
    @test OdinJuliaBridge.animation_schema_id(
        NamedTuple{(:phase, :elapsed),Tuple{UInt8,Float32}}) != schema
    @test_throws ArgumentError OdinJuliaBridge.animation_schema_id(Vector{UInt8})
end

@testset "typed animation state preserves copied storage" begin
    expected = BridgeStatePair(0x03, 2.5f0)
    observed = OdinJuliaBridge._with_animation_value_source(expected) do pointer
        GC.gc(true)
        unsafe_load(Ptr{BridgeStatePair}(pointer))
    end
    @test observed == expected

    copied, status = OdinJuliaBridge._with_animation_value_destination(
        BridgeStatePair) do pointer
        GC.gc(true)
        unsafe_store!(Ptr{BridgeStatePair}(pointer), expected)
        OdinJuliaBridge.BRIDGE_STATUS_OK
    end
    @test status == OdinJuliaBridge.BRIDGE_STATUS_OK
    @test copied == expected

    missing, missing_status = OdinJuliaBridge._with_animation_value_destination(
        BridgeStatePair) do _
        GC.gc(true)
        OdinJuliaBridge.BRIDGE_STATUS_NOT_FOUND
    end
    @test missing === nothing
    @test missing_status == OdinJuliaBridge.BRIDGE_STATUS_NOT_FOUND

    invalid_key = OdinJuliaBridge.AnimationKey{Vector{UInt8}}(0x01)
    @test OdinJuliaBridge.set_animation_value!(
        Ptr{Cvoid}(0), invalid_key, UInt8[]) ==
        OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    @test OdinJuliaBridge.get_animation_value(Ptr{Cvoid}(0), invalid_key) ==
        (nothing, OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT)
    empty_key = OdinJuliaBridge.AnimationKey{Nothing}(0x01)
    @test OdinJuliaBridge.set_animation_value!(Ptr{Cvoid}(0), empty_key, nothing) ==
        OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT
    @test OdinJuliaBridge.get_animation_value(Ptr{Cvoid}(0), empty_key) ==
        (nothing, OdinJuliaBridge.BRIDGE_STATUS_INVALID_ARGUMENT)
end

@testset "vector wrapper prevalidation" begin
    state_ptr = Ptr{Cvoid}(0)

    @test_throws BoundsError OdinJuliaBridge.set_point_position(
        state_ptr, 1, Float32[1f0, 2f0])
    @test_throws BoundsError OdinJuliaBridge.set_point_position_status(
        state_ptr, 1, Float32[1f0, 2f0])
end
