using Test
using OdinJuliaAnalysis
using JSON

include(joinpath(@__DIR__, "..", "analysis_bootstrap.jl"))

module SQLiteReportFixture
include(joinpath(@__DIR__, "..", "analysis", "tools", "Verification.jl"))
end

@testset "Euclid SQLite analysis prerequisite selection" begin
    bootstrap = EuclidAnalysisBootstrap
    @test bootstrap.needs_sqlite_runner(["check"])
    @test bootstrap.needs_sqlite_runner(["check", bootstrap.ROOT])
    @test bootstrap.needs_sqlite_runner([
        "check", "--settings=$(bootstrap.SETTINGS)"])
    @test !bootstrap.needs_sqlite_runner(["stats", "query.sql"])
    @test !bootstrap.needs_sqlite_runner(["check", "--help"])
    @test !bootstrap.needs_sqlite_runner(["check", "--settings=custom.jl"])
    @test !bootstrap.needs_sqlite_runner(String[])
    @test bootstrap.prepare_analysis_runner(["stats", "query.sql"]) === nothing
    expected = bootstrap.EuclidSQLiteValidation.published_runner_path()
    @test bootstrap.prepare_analysis_runner(["check"]) == expected
    @test isfile(expected)
    @test bootstrap.prepare_analysis_runner(["check"]) == expected
end

@testset "Euclid SQLite fail-closed production policy" begin
    settings_path = joinpath(@__DIR__, "..", "analysis_settings.jl")
    configuration = OdinJuliaAnalysis.load_settings(settings_path)
    for rule in ("SQL-KEYWORD-CASING", "SQL-SEMICOLON", "SQL-NUMBERED-BINDS",
        "SQL-EXPLICIT-AS", "SQL-PROJECTION-WILDCARD", "SQL-COMMA-JOIN")
        @test configuration.rules[rule].enabled
        @test configuration.rules[rule].response == Fail
    end
    @test configuration.sqlite_validation.require_coverage
    @test configuration.sqlite_validation.runner !== nothing
    @test !isempty(configuration.sqlite_validation.cases)
end

@testset "SQLite runtime failures remain visible in every report" begin
    engine = OdinJuliaAnalysis
    failure = SQLiteValidationFailure("step", 19, 275, 4, "fixture constraint failure")
    step = SQLiteStepEvidence("insert", "query.sql", repeat("0", 64),
        "execute", "failed", true, false, false, 3, 1, failure)
    case = SQLiteCaseEvidence("fixture", "failed",
        SQLiteProviderEvidence("fixture-provider", "1.0", String[]),
        true, true, true, true, [step], nothing, nothing, "fixture stderr")
    coverage = SQLiteSourceCoverage(
        "query.sql", repeat("0", 64), true, true, false, false, false, ["execute"])
    evidence = SQLiteValidationEvidence("failed", true, [case], [coverage], nothing)
    output = IOBuffer()
    engine.write_sqlite_validation(output, evidence)
    text = String(take!(output))
    for value in ("fixture-provider", "query.sql", "19/275", "byte 4",
        "fixture constraint failure", "fixture stderr", "validated=false")
        @test occursin(value, text)
    end
    output = IOBuffer()
    engine.write_markdown_sqlite_validation(output, evidence)
    markdown = String(take!(output))
    for value in ("fixture-provider", "query.sql", "19/275", "byte 4",
        "fixture constraint failure", "fixture stderr", "Transaction complete: true")
        @test occursin(value, markdown)
    end
    report = JSON.parse(JSON.json((sqlite_validation=evidence,)))
    output = IOBuffer()
    SQLiteReportFixture.Verification.write_analysis_diagnostics(
        output, (sqlite_validation=report.sqlite_validation, diagnostics=Any[]), false)
    summary = String(take!(output))
    for value in ("fixture-provider", "query.sql", "19/275", "byte 4",
        "fixture constraint failure", "fixture stderr", "Uncovered: query.sql")
        @test occursin(value, summary)
    end
    for status in ("complete", "disabled", "not-configured")
        output = IOBuffer()
        quiet = (sqlite_validation=(status=status,), diagnostics=Any[])
        SQLiteReportFixture.Verification.write_analysis_diagnostics(output, quiet, false)
        @test isempty(String(take!(output)))
    end
    output = IOBuffer()
    incomplete = (sqlite_validation=(status="incomplete", message=nothing,
        cases=report.sqlite_validation.cases, coverage=report.sqlite_validation.coverage),
        diagnostics=Any[])
    SQLiteReportFixture.Verification.write_analysis_diagnostics(output, incomplete, false)
    @test occursin("SQLite runtime validation: incomplete", String(take!(output)))
end
