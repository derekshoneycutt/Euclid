if !isdefined(Main, :OdinJuliaBridge)
    include("../odin-julia-bridge.jl")
end

using .OdinJuliaBridge
using Test

@testset "exercise-header text validation" begin
    sentence = "On a given finite straight line to construct an equilateral triangle."
    @test validate_exercise_header_text(sentence) == sentence

    exact = "x" ^ EXERCISE_HEADER_MAX_TEXT_BYTES
    @test ncodeunits(validate_exercise_header_text(exact)) ==
        EXERCISE_HEADER_MAX_TEXT_BYTES
    @test_throws ArgumentError validate_exercise_header_text(exact * "x")
    @test_throws ArgumentError validate_exercise_header_text("")
    @test_throws ArgumentError validate_exercise_header_text(" \t\n")
    @test_throws ArgumentError validate_exercise_header_text("a\0b")
    @test_throws ArgumentError validate_exercise_header_text(String(UInt8[0xc3, 0x28]))
end
