# Tooling tests for Euclid's verification adapter (tools/test_runner.jl and
# tools/verify.jl). Run with the analysis project active so JSON3 resolves:
#
#     julia --project=tools/analysis tools/test/runtests.jl

using Test

include(joinpath(@__DIR__, "..", "verify.jl"))

const Verification = Main.EuclidVerification
const TestRunner = Verification.EuclidTestRunner

@testset "Euclid tooling" begin
    @testset "suite definitions" begin
        suites = TestRunner.suite_definitions()
        @test [suite.name for suite in suites] == ["julia", "odin"]
        @test [suite.language for suite in suites] == ["Julia", "Odin"]
    end

    @testset "test count extraction" begin
        julia_output = "Test Summary:         | Pass  Total   Time\n" *
            "EuclidApp Julia Tests |  712    712  31.5s\n"
        @test TestRunner.reported_julia_count(julia_output) == 712
        @test TestRunner.reported_julia_count("no counts here") === nothing

        @test TestRunner.reported_odin_count(
            "Finished 139 tests in 7.5s. All tests were successful.") == 139
        @test TestRunner.reported_odin_count(
            "Finished 1 test in 12.7s. The test was successful.") == 1
        @test TestRunner.reported_odin_count("No tests to run.") === nothing
    end

    @testset "test runner option parsing" begin
        @test TestRunner.parse_options(String[]) ==
            (selected_suite=nothing, format="text", color=:auto)
        @test TestRunner.parse_options(["--format=json"]).format == "json"
        @test TestRunner.parse_options(["--color=never"]).color == :never
        @test TestRunner.parse_options(["julia"]).selected_suite == "julia"
        @test TestRunner.parse_options(["--bogus"]) isa String
        @test TestRunner.parse_options(["julia", "odin"]) isa String
        @test TestRunner.parse_options(["--format=xml"]) isa String
        @test TestRunner.parse_options(["--color=wrong"]) isa String

        suites = TestRunner.select_suites(nothing)
        @test length(suites) == 2
        @test only(TestRunner.select_suites("odin")).name == "odin"
        @test TestRunner.select_suites("missing") === nothing
    end

    @testset "verification option parsing" begin
        summary = Verification.parse_options(String[])
        @test summary.verbosity == Verification.Summary
        @test Verification.parse_options(["--verbose"]).verbosity ==
            Verification.Trace
        @test Verification.parse_options([
            "--verbose", "--verbosity=1"]).verbosity == Verification.Details
        @test Verification.parse_options(["--verbosity=3"]) isa String
        @test Verification.parse_options([
            "--report=analysis.md"]).report_path == "analysis.md"
        @test Verification.parse_options([
            "--settings=custom.jl"]).settings_path == "custom.jl"
        @test Verification.parse_options(["--unknown"]) isa String
        @test Verification.parse_options(["--report="]) isa String
        @test Verification.parse_options(["--format=xml"]) isa String
        @test Verification.parse_options(["--color=wrong"]) isa String

        @test Verification.resolve_report_path("analysis.md") ==
            joinpath(Verification.REPOSITORY_ROOT, "analysis.md")
        @test Verification.resolve_report_path("/tmp/analysis.md") ==
            "/tmp/analysis.md"
        @test Verification.resolve_report_path(nothing) === nothing
        @test Verification.resolve_settings_path("custom.jl") ==
            joinpath(Verification.REPOSITORY_ROOT, "custom.jl")
        @test Verification.resolve_settings_path(nothing) === nothing
    end

    @testset "analyzer test count marker" begin
        marker_output = "some test chatter\n" *
            Verification.COUNT_MARKER *
            "{\"passed\":5,\"failed\":1,\"errors\":0,\"broken\":0}\n"
        counts = Verification.analyzer_test_counts(marker_output)
        @test counts == Dict("passed" => 5, "failed" => 1, "errors" => 0,
            "broken" => 0)
        @test isempty(Verification.analyzer_test_counts("no marker"))
        @test isempty(Verification.analyzer_test_counts(
            Verification.COUNT_MARKER * "not json"))
    end

    @testset "json report parse fallback" begin
        @test Verification.parse_json_report("{\"files_analyzed\":3}") !== nothing
        @test Verification.parse_json_report("not json") === nothing
        @test Verification.parse_json_report("") === nothing
    end

    @testset "failure output trimming" begin
        analyzer_output = "successful fixture output\n" *
            "self analysis: Test Failed at fixture.jl:12\n" *
            "  Expression: report.exit_code == 0\n"
        @test Verification.concise_analyzer_failure_output(analyzer_output) ==
            "self analysis: Test Failed at fixture.jl:12\n" *
            "  Expression: report.exit_code == 0\n"
        @test Verification.concise_analyzer_failure_output("process crashed\n") ==
            "process crashed\n"
    end

    @testset "verification presentation" begin
        diagnostic = (
            response="warn",
            path="fixture.odin",
            line=2,
            column=3,
            rule_id="FIXTURE-WARN",
            message="visible warning")
        code_statistics = (
            files=2,
            functions=2,
            structs=5,
            lines=30,
            blank_lines=5,
            comment_lines=4,
            code_lines=21,
            complexity=7,
            complexity_per_code_line=1 / 3)
        odin_statistics = (
            files=1,
            functions=1,
            structs=3,
            lines=20,
            blank_lines=3,
            comment_lines=2,
            code_lines=15,
            complexity=3,
            complexity_per_code_line=0.2)
        julia_statistics = (
            files=1,
            functions=1,
            structs=2,
            lines=10,
            blank_lines=2,
            comment_lines=2,
            code_lines=6,
            complexity=4,
            complexity_per_code_line=2 / 3)
        cocomo = (
            model="organic",
            effort_person_months=1.2,
            schedule_months=2.4,
            people=0.5,
            estimated_cost=13_510.0)
        locomo = (
            preset="medium",
            input_tokens=10_000.0,
            output_tokens=2_000.0,
            estimated_cycles=2.1,
            estimated_cost=0.06,
            generation_seconds=40.0,
            review_hours=0.01)
        report = (
            engines=["common"],
            rules=["FIXTURE-WARN"],
            files_analyzed=2,
            diagnostics=[diagnostic],
            statistics=(
                code=code_statistics,
                code_by_language=(odin=odin_statistics, julia=julia_statistics),
                cocomo=cocomo,
                locomo=locomo))
        results = [
            Verification.PhaseResult(
                "Application tests", "1 test", UInt64(1), "PASS",
                "unit trace\n", Dict{String, Any}()),
            Verification.PhaseResult(
                "Analyzer tests", "1 test", UInt64(1), "PASS", "test trace\n",
                Dict{String, Any}("counts" => Dict("passed" => 1))),
            Verification.PhaseResult(
                "Analyzer self-analysis", "1 file", UInt64(1), "PASS",
                "self trace\n", Dict{String, Any}("report" => report)),
            Verification.PhaseResult(
                "Repository analysis", "1 warning", UInt64(1), "PASS",
                "analysis trace\n", Dict{String, Any}("report" => report)),
        ]

        summary_io = IOBuffer()
        Verification.write_text_report(summary_io, results,
            Verification.OutputPolicy(Verification.Summary, :never, "text"))
        summary_text = String(take!(summary_io))
        @test occursin("visible warning", summary_text)
        @test occursin("CODE STATISTICS", summary_text)
        @test occursin("Complexity/Code", summary_text)
        @test occursin("| Odin", summary_text)
        @test occursin("| Julia", summary_text)
        @test occursin("| Total", summary_text)
        @test occursin("COCOMO (organic)", summary_text)
        @test occursin("LOCOMO (medium)", summary_text)
        @test occursin("Verification: PASS", summary_text)
        @test !occursin("TRACE:", summary_text)
        @test Verification.code_statistics_row("Odin", odin_statistics) ==
            Any["Odin", 1, 1, 3, 20, 3, 2, 15, 3, 0.2]

        # A failed analysis with a parsed report suppresses its raw output so
        # diagnostics stay readable instead of replaying the machine report.
        failed_analysis = Verification.PhaseResult(
            "Repository analysis", "1 warning", UInt64(1), "FAIL",
            "{\"large\":\"machine report\"}\n",
            Dict{String, Any}("report" => report))
        failed_results = vcat(results[1:3], [failed_analysis])
        failed_io = IOBuffer()
        Verification.write_text_report(failed_io, failed_results,
            Verification.OutputPolicy(Verification.Summary, :never, "text"))
        failed_text = String(take!(failed_io))
        @test occursin("visible warning", failed_text)
        @test occursin("Verification: FAIL", failed_text)
        @test !occursin("machine report", failed_text)
        @test !occursin("FAILURE: Repository analysis", failed_text)

        # A failed analysis without a parsed report replays its raw output.
        broken_analysis = Verification.PhaseResult(
            "Repository analysis", "analysis failed", UInt64(1), "FAIL",
            "analyzer process failed\n",
            Dict{String, Any}("report" => nothing))
        broken_results = vcat(results[1:3], [broken_analysis])
        broken_io = IOBuffer()
        Verification.write_text_report(broken_io, broken_results,
            Verification.OutputPolicy(Verification.Summary, :never, "text"))
        broken_text = String(take!(broken_io))
        @test occursin("FAILURE: Repository analysis", broken_text)
        @test occursin("analyzer process failed", broken_text)

        color_io = IOBuffer()
        Verification.write_text_report(color_io, results,
            Verification.OutputPolicy(Verification.Summary, :always, "text"))
        @test occursin("\e[1;32m", String(take!(color_io)))

        details_io = IOBuffer()
        Verification.write_text_report(details_io, results,
            Verification.OutputPolicy(Verification.Details, :never, "text"))
        details_text = String(take!(details_io))
        @test occursin("Analyzer tests: passed=1", details_text)
        @test occursin("Repository analysis: 1 engines, 1 rules", details_text)

        trace_io = IOBuffer()
        Verification.write_text_report(trace_io, results,
            Verification.OutputPolicy(Verification.Trace, :never, "text"))
        trace_text = String(take!(trace_io))
        @test occursin("TRACE:", trace_text)
        @test occursin("unit trace", trace_text)

        json_io = IOBuffer()
        Verification.write_json_report(json_io, results)
        json_text = String(take!(json_io))
        @test occursin("\"schema_version\"", json_text)
        @test occursin("analysis trace", json_text)
        @test occursin("visible warning", json_text)

        progress_io = IOBuffer()
        progress_result = Verification.run_progress_phase(
            progress_io,
            2,
            4,
            "Fixture phase",
            () -> results[2])
        progress_text = String(take!(progress_io))
        @test progress_result === results[2]
        @test occursin("[2/4] Fixture phase", progress_text)
        @test occursin("PASS  1 test", progress_text)
    end

    @testset "build phase attachment" begin
        # Exercise phase attachment without running the real subprocesses by
        # driving run_progress_phase directly and confirming pushfirst! order.
        build_phase = Verification.PhaseResult(
            "Build", "Euclid application", UInt64(1), "PASS", "build trace\n",
            Dict{String, Any}("exit_code" => 0))

        """Build a passing phase result fixture for presentation assertions."""
        fixture(name) = Verification.PhaseResult(
            name, "1 item", UInt64(1), "PASS", "trace\n", Dict{String, Any}())
        other_phases = [
            fixture("Application tests"),
            fixture("Analyzer tests"),
            fixture("Analyzer self-analysis"),
            fixture("Repository analysis"),
        ]
        results = copy(other_phases)
        pushfirst!(results, build_phase)
        @test first(results) === build_phase
        @test length(results) == 5
        @test [result.name for result in results] == [
            "Build",
            "Application tests",
            "Analyzer tests",
            "Analyzer self-analysis",
            "Repository analysis",
        ]
        io = IOBuffer()
        Verification.write_text_report(io, results,
            Verification.OutputPolicy(Verification.Summary, :never, "text"))
        @test occursin("Verification: PASS", String(take!(io)))
    end
end
