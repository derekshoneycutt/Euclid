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

include("../scratchpad.jl")

using .Scratchpad
using Test

function new_metrics()
    return Scratchpad.ScratchpadMetrics(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
end

function new_session(; id::Int=1)
    return Scratchpad.ScratchpadSession(
        id,
        Module(Symbol(:ScratchpadTestRuntime, id)),
        String[],
        String[],
        String[],
        Scratchpad.ScratchpadFrameHook[],
        new_metrics(),
        1,
        1)
end

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
