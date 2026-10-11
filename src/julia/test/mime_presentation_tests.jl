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

mutable struct PresentationObservation
    state::Ptr{Cvoid}
    presentation::Union{Nothing,PresentedText}
    value::Any
end

const ExpectedPresentationState = Ptr{Cvoid}(UInt(0x1234))

"""Render a deterministic bounded plain-text fixture."""
Base.show(io::IO, ::MIME"text/plain", value::PlainPresentationFixture) =
    print(io, "fixture:", value.value)

"""Render one byte beyond the canonical presentation bound."""
Base.show(io::IO, ::MIME"text/plain", _value::OversizedPresentationFixture) =
    print(io, "x" ^ (PRESENTATION_MAX_SOURCE_BYTES + 1))

"""Return a deterministic failed publication status for error-path coverage."""
failed_presentation(_state_ptr, _presentation) = BRIDGE_STATUS_ILLEGAL_STATE

"""Record one serialized presentation in local test observation state."""
function record_presentation!(observation, state_ptr, presentation)
    observation.state = state_ptr
    observation.presentation = presentation
    return BRIDGE_STATUS_OK
end

"""Record one producer value in local test observation state."""
function record_presentation_value!(observation, state_ptr, value)
    observation.state = state_ptr
    observation.value = value
    return BRIDGE_STATUS_OK
end

"""Produce one deterministic TeX document for callback delegation coverage."""
presentation_fixture(state_ptr) = state_ptr == ExpectedPresentationState ? tex"y" : ""

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

@testset "canonical publication helpers" begin
    observation = PresentationObservation(Ptr{Cvoid}(0), nothing, nothing)
    record_presentation = Base.Fix1(record_presentation!, observation)
    record_presentation_value = Base.Fix1(
        record_presentation_value!, observation)

    @test OdinJuliaBridge._present_with(
        ExpectedPresentationState, tex"x^2", record_presentation) ==
        BRIDGE_STATUS_OK
    @test observation.state == ExpectedPresentationState
    @test observation.presentation == PresentedText(TextLatex, "x^2")

    @test_throws ErrorException OdinJuliaBridge._present_with(
        ExpectedPresentationState, "plain", failed_presentation)

    @test OdinJuliaBridge._publish_view_content_with(
        ExpectedPresentationState, presentation_fixture,
        record_presentation_value) == BRIDGE_STATUS_OK
    @test observation.state == ExpectedPresentationState
    @test observation.value == tex"y"
end