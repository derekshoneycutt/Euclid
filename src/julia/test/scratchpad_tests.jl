if !isdefined(Main, :OdinJuliaBridge)
    include("../odin-julia-bridge.jl")
end
if !isdefined(Main, :EuclidGeometry)
    include("../geometry.jl")
end
if !isdefined(Main, :EuclidAnimations)
    @eval module EuclidAnimations
    end
end
if !isdefined(Main, :EuclidLatex)
    include("../latex.jl")
end

include("../scratchpad.jl")
if !isdefined(Main, :EuclidRepl)
    include("../euclidrepl.jl")
end

using .Scratchpad
using Test

const TEST_SESSION_ID_REF = Ref(1)

function new_metrics()
    return Scratchpad.ScratchpadMetrics(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
end

function new_session(; id::Int=TEST_SESSION_ID_REF[])
    TEST_SESSION_ID_REF[] = id + 1
    return Scratchpad.create_session(TEST_STATE_PTR, id)
end

struct ScratchpadLatexResultMock
end

Base.show(io::IO, ::MIME"text/plain", ::ScratchpadLatexResultMock) = print(io, "ScratchpadLatexResultMock()")
Base.show(io::IO, ::MIME"text/latex", ::ScratchpadLatexResultMock) = print(io, "\\frac{1}{2}")

struct ScratchpadPlainResultMock
end

Base.show(io::IO, ::MIME"text/plain", ::ScratchpadPlainResultMock) = print(io, "ScratchpadPlainResultMock()")

function with_test_session(f::Function)
    old_session = Scratchpad.session_ref[]
    try
        session = new_session()
        Scratchpad.session_ref[] = session
        return f(session)
    finally
        Scratchpad.session_ref[] = old_session
    end
end

const TEST_STATE_PTR = Ptr{Cvoid}(0)

@testset "classify_parse" begin
    status_complete, parsed_complete = Scratchpad.classify_parse("1 + 2")
    @test status_complete == Scratchpad.ParseComplete
    @test parsed_complete isa Expr

    status_incomplete, _ = Scratchpad.classify_parse("begin\n  x = 1")
    @test status_incomplete == Scratchpad.ParseIncomplete

    status_error, _ = Scratchpad.classify_parse("x = )")
    @test status_error == Scratchpad.ParseError
end

@testset "create_session" begin
    session = Scratchpad.create_session(TEST_STATE_PTR, 10_001)
    @test session.id == 10_001
    @test isempty(session.queue)
    @test isempty(session.output)
    @test isempty(session.history)
    @test Core.eval(session.runtime, :state_ptr) == TEST_STATE_PTR
end

@testset "startup banner" begin
    session = new_session()
    Scratchpad.append_startup_banner!(session)

    release_date = Scratchpad.julia_release_date()
    @test release_date !== nothing
    @test occursin(r"^\d{4}-\d{2}-\d{2}$", release_date)
    @test session.output == [
        "               _",
        "   _       _ _(_)_     |  Documentation: https://docs.julialang.org",
        "  (_)     | (_) (_)    |",
        "   _ _   _| |_  __ _   |  Type \":help\" for help.",
        "  | | | | | | |/ _` |  |",
        "  | | |_| | | | (_| |  |  Version $(VERSION) ($(release_date))",
        " _/ |\\__'_|_|_|\\__'_|  |  Official https://julialang.org release",
        "|__/                   |",
    ]

    Scratchpad.append_help_lines!(session)
    @test "Julia REPL Scratchpad" in session.output
    @test "  :help        show this help" in session.output
end

@testset "terminal prompt echo" begin
    session = Scratchpad.create_session(TEST_STATE_PTR, 10_002)

    Scratchpad.append_input_echo!(session, "begin\n    x = 1\nend")

    @test session.output == [
        "julia> begin",
        "           x = 1",
        "       end",
    ]
    @test all(entry -> entry.block_kind == OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_INPUT,
        session.output_entries)
    @test all(entry -> entry.style_id == Scratchpad.DynviewStyleInput,
        session.output_entries)
end

@testset "parse_error_message" begin
    @test Scratchpad.parse_error_message(Expr(:error, "oops")) == "Parse error: oops"
    @test Scratchpad.parse_error_message(:not_an_expr) == "Parse error"
end

@testset "blocked_input_reason" begin
    @test Scratchpad.blocked_input_reason("using Pkg") == "package management is disabled in scratchpad"
    @test Scratchpad.blocked_input_reason("import   pkg") == "package management is disabled in scratchpad"
    @test Scratchpad.blocked_input_reason("run(`ls`)") == "blocked token: run("
    @test Scratchpad.blocked_input_reason("cp(\"a\", \"b\")") == "blocked token: cp("
    @test Scratchpad.blocked_input_reason("x = 42") === nothing
end

@testset "classify_input" begin
    with_test_session() do session
        @test Scratchpad.classify_input(TEST_STATE_PTR, "x = 2") == Scratchpad.ParseComplete
        @test isempty(session.output)

        @test Scratchpad.classify_input(TEST_STATE_PTR, "x = )") == Scratchpad.ParseError
        @test length(session.output) == 1
        @test startswith(session.output[1], "Parse error")

        @test Scratchpad.classify_input(TEST_STATE_PTR, "?OdinJuliaBridge.bridge_color") == Scratchpad.ParseComplete
        @test length(session.output) == 1
    end
end

@testset "complete_backslash" begin
    with_test_session() do _
        @test Scratchpad.complete_backslash(TEST_STATE_PTR, "\\alpha") == "α"
        @test Scratchpad.complete_backslash(TEST_STATE_PTR, "\\al") == ""
        @test Scratchpad.complete_backslash(TEST_STATE_PTR, "alpha") == ""
    end
end

@testset "complete_input" begin
    with_test_session() do session
        @test Scratchpad.complete_input(TEST_STATE_PTR, "\\alpha", 6) == "0\n6\nα"
        @test Scratchpad.completion_replacement_text("test_val", 1:8, ["test_value"]) == "test_value"
        @test Scratchpad.completion_replacement_text("alph", 1:4, ["alpha_one", "alpha_two"]) == "alpha_"
        @test Scratchpad.completion_replacement_text("alpha_", 1:6, ["alpha_one", "alpha_two"]) === nothing
    end
end

@testset "native exception stack formatting" begin
    runtime = Module(:ScratchpadExceptionFormattingTest)
    formatted = try
        1 + "a"
        ""
    catch
        Scratchpad.format_current_exception_text(runtime)
    end

    @test startswith(formatted, "ERROR: MethodError")
    @test occursin("MethodError", formatted)
    @test occursin("Closest candidates are:", formatted)
    @test occursin("Stacktrace:", formatted)
    @test occursin("+", formatted)
    @test !occursin("\e[", formatted)
    _, style_id = Scratchpad.dynview_ids_for_line(formatted)
    @test style_id == Scratchpad.DynviewStyleError

    oversized = repeat("α", Scratchpad.MaxExceptionOutputBytes)
    truncated = Scratchpad.truncate_exception_output(oversized)
    @test ncodeunits(truncated) <= Scratchpad.MaxExceptionOutputBytes
    @test endswith(truncated, Scratchpad.ExceptionOutputTruncated)
    @test isvalid(truncated)
end

@testset "new runtime method candidates" begin
    runtime = Module(:ScratchpadRuntimeMethodCandidateTest)
    Core.eval(runtime, :(f(x, y) = x + y))

    formatted = try
        Core.eval(runtime, :(f(2)))
        ""
    catch
        Scratchpad.format_current_exception_text(runtime)
    end

    @test startswith(formatted, "ERROR: MethodError: no method matching f(::Int64)")
    @test occursin("The function `f` exists", formatted)
    @test occursin("Closest candidates are:", formatted)
    @test occursin("f(::Any, !Matched::Any)", formatted)
end

@testset "evaluate newly defined function mismatch" begin
    with_test_session() do session
        session.metrics.queue_dequeued = 1
        Scratchpad.evaluate_queued_input!(session, TEST_STATE_PTR, "f(x, y) = x + y")
        session.metrics.queue_dequeued = 2
        Scratchpad.evaluate_queued_input!(session, TEST_STATE_PTR, "f(2)")

        output = join(session.output, "\n")
        @test session.metrics.eval_errors == 1
        @test occursin("ERROR: MethodError: no method matching f(::Int64)", output)
        @test occursin("The function `f` exists", output)
        @test occursin("Closest candidates are:", output)
        @test occursin("f(::Any, !Matched::Any)", output)
        @test occursin("@ Main.$(nameof(session.runtime)) REPL[1]:1", output)
        @test occursin("@ REPL[2]:1", output)
        @test !occursin("eval(m::Module", output)
        @test !occursin("evaluate_queued_input!", output)
        @test any(==("Closest candidates are:"), session.output)
        @test any(==("Stacktrace:"), session.output)
        error_start = findfirst(entry -> startswith(entry.line, "ERROR:"), session.output_entries)
        @test error_start !== nothing
        @test all(entry -> entry.style_id == Scratchpad.DynviewStyleError,
            session.output_entries[error_start:lastindex(session.output_entries)])
        @test all(entry -> !occursin('\n', entry.line), session.output_entries)
    end
end

@testset "latex result formatting helpers" begin
    @test Scratchpad.normalize_latex_result_source("\$\\alpha\$") == "\\alpha"
    @test Scratchpad.normalize_latex_result_source("\$\$\\frac{1}{2}\$\$") == "\\frac{1}{2}"
    @test Scratchpad.normalize_latex_result_source("  \\beta  ") == "\\beta"

    latex_source = Scratchpad.format_result_latex_source(ScratchpadLatexResultMock(), Main)
    @test latex_source == "\\frac{1}{2}"

    plain_source = Scratchpad.format_result_latex_source(ScratchpadPlainResultMock(), Main)
    @test plain_source === nothing
end

@testset "append eval result output" begin
    session = new_session()

    Scratchpad.append_eval_result_output!(session, ScratchpadLatexResultMock())
    @test length(session.output) == 1
    @test session.output[1] == "=> ScratchpadLatexResultMock()"
    @test length(session.output_entries) == 1
    @test session.output_entries[1].latex_source == "\\frac{1}{2}"

    Scratchpad.append_eval_result_output!(session, ScratchpadPlainResultMock())
    @test length(session.output) == 2
    @test session.output[2] == "=> ScratchpadPlainResultMock()"
    @test length(session.output_entries) == 2
    @test session.output_entries[2].latex_source == ""
end

@testset "history navigation" begin
    with_test_session() do session
        @test Scratchpad.history_previous(TEST_STATE_PTR) == ""
        @test Scratchpad.history_next(TEST_STATE_PTR) == ""

        append!(session.history, ["alpha", "beta", "gamma"])
        session.history_cursor = length(session.history) + 1

        @test Scratchpad.history_previous(TEST_STATE_PTR) == "gamma"
        @test Scratchpad.history_previous(TEST_STATE_PTR) == "beta"
        @test Scratchpad.history_previous(TEST_STATE_PTR) == "alpha"
        @test Scratchpad.history_previous(TEST_STATE_PTR) == "alpha"

        @test Scratchpad.history_next(TEST_STATE_PTR) == "beta"
        @test Scratchpad.history_next(TEST_STATE_PTR) == "gamma"
        @test Scratchpad.history_next(TEST_STATE_PTR) == ""
        @test Scratchpad.history_next(TEST_STATE_PTR) == ""

        @test Scratchpad.history_reset_cursor(TEST_STATE_PTR)
        @test session.history_cursor == length(session.history) + 1
    end
end

@testset "queue cap behavior" begin
    session = new_session(id = 2)

    total = Scratchpad.MaxQueueLines + 2
    for i in 1:total
        Scratchpad.queue_line!(session, "line-$(i)")
    end

    @test length(session.queue) == Scratchpad.MaxQueueLines
    @test first(session.queue) == "line-3"
    @test last(session.queue) == "line-$(total)"
    @test session.metrics.queue_dropped == 2
    @test session.metrics.queue_enqueued == total
    @test session.metrics.queue_high_water == Scratchpad.MaxQueueLines
end

@testset "module help doc fallback" begin
    runtime = Module(:ScratchpadHelpRuntime)
    Core.eval(runtime, :(const EuclidRepl = Main.EuclidRepl))

    binding = Base.Docs.Binding(runtime, :EuclidRepl)
    doc_entry = Scratchpad.resolve_module_doc_entry(binding, Main.EuclidRepl)

    @test doc_entry !== nothing
    rendered = Scratchpad.render_help_docs(doc_entry)
    @test rendered !== nothing
    @test occursin("REPL-first geometry helpers", rendered)
end

@testset "highlight helper aliases and bindings" begin
    @test haskey(Scratchpad.HELPER_DOC_ALIASES, "highlight_pen!")
    @test haskey(Scratchpad.HELPER_DOC_ALIASES, "highlight_compass!")
    @test haskey(Scratchpad.HELPER_DOC_ALIASES, "hide!")
    @test haskey(Scratchpad.HELPER_DOC_ALIASES, "euclidcolors")

    runtime = Scratchpad.create_runtime_module(5_001)
    @test isdefined(runtime, Symbol("highlight_pen!"))
    @test isdefined(runtime, Symbol("highlight_compass!"))
    @test isdefined(runtime, Symbol("hide!"))
    @test isdefined(runtime, Symbol("euclidcolors"))
    @test isdefined(runtime, :LaTeXStrings)
    @test isdefined(runtime, :Latexify)

    latex_value = Core.eval(runtime, :(L"\\alpha"))
    @test latex_value isa Main.LaTeXStrings.LaTeXString

    latexify_value = Core.eval(runtime, :(latexify([1 2; 3 4])))
    @test latexify_value !== nothing
end
