if !isdefined(Main, :OdinJuliaBridge)
    include("../odin-julia-bridge.jl")
end
if !isdefined(Main, :EuclidLatex)
    include("../latex.jl")
end

using .EuclidLatex
using .OdinJuliaBridge
using LaTeXStrings
using Test

struct PlainPresentationFixture
    value::Int
end

struct OversizedPresentationFixture end

"""Render a deterministic bounded plain-text fixture."""
Base.show(io::IO, ::MIME"text/plain", value::PlainPresentationFixture) =
    print(io, "fixture:", value.value)

"""Render one byte beyond the canonical presentation bound."""
Base.show(io::IO, ::MIME"text/plain", _value::OversizedPresentationFixture) =
    print(io, "x" ^ (PRESENTATION_MAX_SOURCE_BYTES + 1))

@testset "canonical MIME selection" begin
    @test presented_text("A").mime == TextPlain
    @test presented_text("A").bytes == "A"

    latex = presented_text(L"\alpha")
    @test latex.mime == TextLatex
    @test latex.bytes == sprint(show, MIME"text/latex"(), L"\alpha")

    document = tex"A point is $A$."
    presented_document = presented_text(document)
    @test presented_document.mime == TextLatex
    @test presented_document.bytes == raw"A point is $A$."

    multiline = tex"""
    \textbf{Definition 1.}

    A point is that which has no part.
    """
    @test multiline.source ==
        "\\textbf{Definition 1.}\n\nA point is that which has no part.\n"

    plain = presented_text(PlainPresentationFixture(7))
    @test plain == PresentedText(TextPlain, "fixture:7")
end

@testset "canonical byte limits" begin
    exact = "x" ^ PRESENTATION_MAX_SOURCE_BYTES
    @test presented_text(exact).bytes == exact
    @test_throws ArgumentError presented_text(exact * "x")
    @test_throws ArgumentError presented_text(OversizedPresentationFixture())
end