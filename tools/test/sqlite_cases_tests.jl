using Test
using OdinJuliaAnalysis

include(joinpath(@__DIR__, "..", "sqlite_cases.jl"))

const SQLiteCasesTestRoot = normpath(joinpath(@__DIR__, "..", ".."))
const SQLiteCasesEngine = OdinJuliaAnalysis.SQLEngine
const SQLiteCasesRuleIds = Set((
    "SQL-KEYWORD-CASING",
    "SQL-SEMICOLON",
    "SQL-NUMBERED-BINDS",
    "SQL-EXPLICIT-AS",
    "SQL-PROJECTION-WILDCARD",
    "SQL-COMMA-JOIN"))

"""Enumerate the two owned first-party SQL roots using repository-relative paths."""
function sqlite_case_source_paths()
    paths = String[]
    for root in ("src", "tools/content_builder")
        for (directory, _, files) in walkdir(joinpath(SQLiteCasesTestRoot, root))
            for file in files
                endswith(file, ".sql") || continue
                path = joinpath(directory, file)
                push!(paths, replace(relpath(path, SQLiteCasesTestRoot), '\\' => '/'))
            end
        end
    end
    return sort!(paths)
end

"""Create immutable analyzer snapshots for all declared application SQL."""
function sqlite_case_sources(paths)
    return Dict(path => SQLiteCasesEngine.analyze(
        read(joinpath(SQLiteCasesTestRoot, path), String))
        for path in paths)
end

"""Summarize one failed case without exposing full runner output."""
function sqlite_case_failure_summary(case)
    if case.failure === nothing
        return "$(case.id): $(something(case.message, case.status))"
    end
    return "$(case.id): $(case.failure.phase): $(case.failure.message)"
end

"""Compare the checked-in manifest to native coverage without asserting query results."""
function test_sqlite_case_execution(paths, cases, sources)
    runner = isempty(ARGS) ?
        get(ENV, "EUCLID_SQLITE_RUNNER",
            joinpath(SQLiteCasesTestRoot, ".build", "sqlite-validator",
                Sys.iswindows() ? "sqlite-validator.exe" : "sqlite-validator")) :
        abspath(ARGS[1])
    @test isfile(runner)
    settings = SQLiteValidationSettings(;
        runner=SQLiteRunnerSettings([runner]; working_directory=SQLiteCasesTestRoot),
        cases,
        require_coverage=true)
    evidence = OdinJuliaAnalysis.analyze_sqlite_validation(
        SQLiteCasesTestRoot, sources, settings)
    if evidence.status != "complete"
        failures = [sqlite_case_failure_summary(case)
            for case in evidence.cases if case.status != "passed"]
        @error "SQLite case execution did not complete" status=evidence.status failures
    end
    @test evidence.status == "complete"
    @test length(evidence.cases) == length(cases)
    @test all(case -> case.status == "passed", evidence.cases)
    @test length(evidence.coverage) == length(paths)
    @test all(item -> item.validated && item.executed, evidence.coverage)
    return evidence
end

@testset "SQLite first-party manifest and adoption" begin
    paths = sqlite_case_source_paths()
    sources = sqlite_case_sources(paths)
    cases = euclid_sqlite_validation_cases()
    file_steps = [step for case in cases for step in case.steps
        if step isa SQLiteFileStep]
    manifest_paths = [replace(normpath(step.path), '\\' => '/') for step in file_steps]

    search_paths = Set(step.path for step in euclid_history_search_steps())
    @test length(paths) == 61
    @test length(search_paths) == 4
    @test all(path -> count(==(path), manifest_paths) ==
        (path in search_paths ? 2 : 1), paths)
    @test Set(manifest_paths) == Set(paths)
    @test all(case -> all(requirement -> requirement in
        ("fts5", "spellfix1", "history_matches"),
        case.requirements), cases)

    @testset "All six source conventions are clean" begin
        for path in paths
            evidence = sources[path]
            @test isempty(evidence.issues)
            @test isempty(evidence.structure.gaps)
            @test Set(keys(evidence.structure.rules)) == SQLiteCasesRuleIds
            @test all(status == :evaluated for status in values(evidence.structure.rules))
            @test isempty(SQLiteCasesEngine.structural_findings(evidence))
        end
    end

    @testset "Typed cases execute every authored source" begin
        result = test_sqlite_case_execution(paths, cases, sources)
        @info "SQLite adoption coverage" files=length(result.coverage)
        @info "SQLite validation cases" cases=length(result.cases)
    end
end
