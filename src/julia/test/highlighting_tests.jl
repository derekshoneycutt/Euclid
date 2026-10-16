module HighlightingTests

using Test
import StyledStrings
import JuliaSyntaxHighlighting

include("../eval/highlighting.jl")
const H = SyntaxHighlighting
const Face = StyledStrings.Face
const AnnotatedString = StyledStrings.AnnotatedString

"""Run a fixture with deterministic Julia defaults, isolated from user face customizations."""
function with_default_faces(f, overrides::Pair...)
    faces = Pair{Symbol,Face}[
        :default => Face(
            weight=:normal, slant=:normal, foreground=:default, background=:default,
            underline=false, strikethrough=false, inverse=false),
        (name => Face(foreground=name) for name in H.ANSI_COLORS)...,
        :grey => Face(foreground=:bright_black),
        :gray => Face(foreground=:bright_black),
        JuliaSyntaxHighlighting.HIGHLIGHT_FACES...,
        overrides...]
    return StyledStrings.withfaces(f, faces)
end

"""Assert complete, bounded source coverage and UTF-8-safe, merged intervals."""
function test_run_contract(source, runs)
    @test length(runs) <= H.MAX_STYLE_RUNS
    if isempty(source)
        @test isempty(runs)
        return
    end
    @test first(runs).start_byte == 0
    @test last(runs).end_byte == ncodeunits(source)
    for (index, run) in enumerate(runs)
        @test run.start_byte < run.end_byte
        @test isvalid(source, Int(run.start_byte) + 1)
        @test run.end_byte == ncodeunits(source) || isvalid(source, Int(run.end_byte) + 1)
        if index > 1
            @test runs[index - 1].end_byte == run.start_byte
            @test runs[index - 1].style != run.style
        end
    end
end

"""Return the accepted style for one zero-based byte position in a fixture."""
style_at(runs, byte) =
    only(run.style for run in runs if run.start_byte <= byte < run.end_byte)

@testset "Julia syntax defaults and exact source coverage" begin
    with_default_faces() do
        for source in (
            "", "x = 1", " \n\t", "function f(x)\n    # comment\n    \"text\"\nend",
            "function f(", "\"unterminated", ")", "α = \"🙂 e\u0301\" # 日本語\n",
            "f((a[1], Dict{String,Int}()))", "raw\"a\\b\"", "#= nested #= comment =# =#")
            test_run_contract(source, H.highlight_source(source))
        end
        @test style_at(H.highlight_source("if true\nend"), 0).foreground ==
            H.HighlightColor(H.AnsiColor, UInt32(1))
        @test only(H.highlight_source("# comment")).style.foreground ==
            H.HighlightColor(H.AnsiColor, UInt32(8))
        @test only(H.highlight_source("\"🙂\"")).style.foreground ==
            H.HighlightColor(H.AnsiColor, UInt32(2))
        @test style_at(H.highlight_source(")"), 0).background ==
            H.HighlightColor(H.AnsiColor, UInt32(1))
        @test only(H.highlight_source("plain_identifier")).style.foreground ==
            H.DEFAULT_COLOR
    end
end

@testset "overlaps, gaps, inheritance, and adjacent style merging" begin
    with_default_faces(
        :test_parent => Face(foreground=0x123456, weight=:bold, slant=:italic),
        :test_secondary => Face(foreground=:blue, background=0x654321),
        :test_child => Face(inherit=[:test_parent, :test_secondary], inverse=true)) do
        source = AnnotatedString("αbc🙂z")
        Base.annotate!(source, 1:3, :face, :test_child)
        Base.annotate!(source, 3:4, :face, Face(foreground=:red, underline=true))
        Base.annotate!(source, 5:8, :face, :unknown_euclid_fixture)
        runs = H.normalize_runs(source)
        test_run_contract(source, runs)
        first_style = style_at(runs, 0)
        @test first_style.foreground == H.HighlightColor(H.RgbColor, UInt32(0x123456))
        @test first_style.background == H.HighlightColor(H.RgbColor, UInt32(0x654321))
        @test first_style.weight == H.BoldWeight
        @test first_style.italic && first_style.inverse
        @test style_at(runs, 2).foreground == H.HighlightColor(H.AnsiColor, UInt32(1))
        @test style_at(runs, 2).underline == H.StraightUnderline
        @test style_at(runs, 4).foreground == H.DEFAULT_COLOR
        @test style_at(runs, 8).foreground == H.DEFAULT_COLOR
        @test last(runs).start_byte == 4
    end
    with_default_faces() do
        source = AnnotatedString("abc")
        Base.annotate!(source, 1:1, :face, Face(weight=:bold))
        Base.annotate!(source, 2:2, :face, Face(weight=:semibold))
        Base.annotate!(source, 3:3, :not_a_face, :ignored)
        @test length(H.normalize_runs(source)) == 2
    end
end

@testset "native attributes and bounded style vocabulary" begin
    with_default_faces() do
        for (weight, expected) in (
            :thin => H.DimWeight, :extralight => H.DimWeight, :light => H.DimWeight,
            :semilight => H.DimWeight, :normal => H.NormalWeight, :medium => H.BoldWeight,
            :semibold => H.BoldWeight, :bold => H.BoldWeight, :extrabold => H.BoldWeight,
            :black => H.BoldWeight, :unknown => H.NormalWeight)
            source = AnnotatedString("x", [(1:1, :face, Face(; weight))])
            @test only(H.normalize_runs(source)).style.weight == expected
        end
        for slant in (:normal, :italic, :oblique, :unknown)
            source = AnnotatedString("x", [(1:1, :face, Face(; slant))])
            @test only(H.normalize_runs(source)).style.italic ==
                (slant in (:italic, :oblique))
        end
        for (name, expected) in zip(H.UNDERLINE_STYLES, instances(H.UnderlineKind)[2:end])
            source = AnnotatedString("x", [(1:1, :face, Face(
                underline=(StyledStrings.SimpleColor(0xabcdef), name),
                strikethrough=true, inverse=true, font="ignored", height=200))])
            style = only(H.normalize_runs(source)).style
            @test style.underline == expected
            @test style.underline_color == H.HighlightColor(H.RgbColor, UInt32(0xabcdef))
            @test style.strikethrough && style.inverse
        end
        for (value, expected) in (
            true => H.StraightUnderline, false => H.NoUnderline,
            StyledStrings.SimpleColor(:red) => H.StraightUnderline,
            (nothing, :unsupported) => H.NoUnderline)
            source = AnnotatedString("x", [(1:1, :face, Face(underline=value))])
            @test only(H.normalize_runs(source)).style.underline == expected
        end
        for (index, name) in enumerate(H.ANSI_COLORS)
            @test H.resolve_color(StyledStrings.SimpleColor(name)) ==
                H.HighlightColor(H.AnsiColor, UInt32(index - 1))
        end
        @test H.resolve_color(StyledStrings.SimpleColor(:not_a_color)) == H.DEFAULT_COLOR
    end
end

@testset "current configuration, aliases, defaults, and rainbow delimiters" begin
    with_default_faces(
        :red => Face(foreground=0x112233),
        :julia_string => Face(foreground=0x445566),
        :julia_rainbow_paren_1 => Face(foreground=:red),
        :julia_rainbow_paren_2 => Face(foreground=:green),
        :julia_rainbow_bracket_1 => Face(foreground=:blue),
        :julia_rainbow_curly_1 => Face(foreground=:magenta)) do
        @test only(H.highlight_source("\"text\"")).style.foreground ==
            H.HighlightColor(H.RgbColor, UInt32(0x445566))
        runs = H.highlight_source("(([]))")
        @test style_at(runs, 0).foreground ==
            H.HighlightColor(H.RgbColor, UInt32(0x112233))
        @test style_at(runs, 1).foreground == H.HighlightColor(H.AnsiColor, UInt32(2))
        @test style_at(runs, 2).foreground == H.HighlightColor(H.AnsiColor, UInt32(4))
        @test style_at(H.highlight_source("{}"), 0).foreground ==
            H.HighlightColor(H.AnsiColor, UInt32(5))
    end
    for color in (0x010203, 0xaabbcc)
        with_default_faces(:julia_string => Face(foreground=color)) do
            @test only(H.highlight_source("\"same source\"")).style.foreground ==
                H.HighlightColor(H.RgbColor, UInt32(color))
        end
    end
    with_default_faces(:default => Face(foreground=0x123456, weight=:bold)) do
        @test only(H.highlight_source("plain")).style.foreground ==
            H.HighlightColor(H.RgbColor, UInt32(0x123456))
        @test only(H.highlight_source("plain")).style.weight == H.BoldWeight
    end
end

@testset "explicit source, annotation, run, and configuration failures" begin
    with_default_faces() do
        @test_throws ArgumentError H.highlight_source("x" ^ (H.MAX_SOURCE_BYTES + 1))
        test_run_contract("x" ^ H.MAX_SOURCE_BYTES,
            H.highlight_source("x" ^ H.MAX_SOURCE_BYTES))
        @test_throws ArgumentError H.highlight_source(String(UInt8[0xff]))
        @test_throws ArgumentError H.normalize_runs(
            AnnotatedString("α", [(1:1, :face, :bold)]))
        @test_throws ArgumentError H.normalize_runs(
            AnnotatedString("abc", [(0:1, :face, :bold)]))
        @test_throws ArgumentError H.normalize_runs(
            AnnotatedString("abc", [(1:4, :face, :bold)]))
        annotations = [(1:1, :face, :bold) for _ in 1:(H.MAX_ANNOTATIONS + 1)]
        @test_throws ArgumentError H.normalize_runs(AnnotatedString("x", annotations))
        source = "x" ^ (H.MAX_STYLE_RUNS + 1)
        annotations =
            [(i:i, :face, isodd(i) ? :bold : :italic) for i in eachindex(source)]
        accepted = H.normalize_runs(
            AnnotatedString(source[1:end-1], annotations[1:end-1]))
        @test length(accepted) == H.MAX_STYLE_RUNS
        @test_throws ArgumentError H.normalize_runs(
            AnnotatedString(source, annotations))
        @test_throws ArgumentError H.normalize_runs(
            AnnotatedString("x", [(1:1, :face, 42)]))
    end
    with_default_faces(
        :test_cycle => Face(inherit=:test_cycle),
        :test_color_a => Face(foreground=:test_color_b),
        :test_color_b => Face(foreground=:test_color_a)) do
        @test_throws ArgumentError H.normalize_runs(
            AnnotatedString("x", [(1:1, :face, :test_cycle)]))
        @test_throws ArgumentError H.resolve_color(
            StyledStrings.SimpleColor(:test_color_a))
    end
    chain = [Symbol("test_depth_", i) for i in 1:(H.MAX_FACE_DEPTH + 1)]
    faces = [chain[i] => Face(inherit=chain[i + 1]) for i in 1:(length(chain) - 1)]
    with_default_faces(faces...) do
        @test_throws ArgumentError H.normalize_runs(
            AnnotatedString("x", [(1:1, :face, first(chain))]))
    end
    with_default_faces(:test_wide => Face(inherit=fill(:bold, H.MAX_FACE_VISITS))) do
        @test_throws ArgumentError H.normalize_runs(
            AnnotatedString("x", [(1:1, :face, :test_wide)]))
    end
end

@testset "standard faces.toml loading in a fresh Julia process" begin
    mktempdir() do directory
        mkpath(joinpath(directory, "config"))
        write(joinpath(directory, "config", "faces.toml"), """
            [julia.string]
            inherit = "bold"
            foreground = "#abcdef"
            """)
        adapter = joinpath(@__DIR__, "..", "eval", "highlighting.jl")
        code = """
            pushfirst!(DEPOT_PATH, $(repr(directory)))
            include($(repr(adapter)))
            H = SyntaxHighlighting
            runs = H.highlight_source("\\"text\\"")
            @assert length(runs) == 3
            @assert all(run.style.foreground == H.HighlightColor(
                H.RgbColor, UInt32(0xabcdef)) for run in runs)
            @assert runs[2].start_byte == 1 && runs[2].end_byte == 5
            @assert runs[2].style.weight == H.BoldWeight
            """
        project = dirname(@__DIR__)
        command = `$(Base.julia_cmd()) --startup-file=no --project=$project -e $code`
        @test success(pipeline(command; stdout, stderr))
    end
end

end
