using Test

include(joinpath(@__DIR__, "..", "scenario_runner.jl"))
const ScenarioRunner = EuclidScenarioRunner

@testset "scenario selection and reporting" begin
    mktempdir() do root
        mkpath(joinpath(root, "terminal", "history"))
        mkpath(joinpath(root, "settings"))
        write(joinpath(root, "terminal", "second.jsonl"), "{}\n")
        write(joinpath(root, "settings", "first.jsonl"), "{}\n")
        write(joinpath(root, "settings", "restore.jsonl"), "{}\n")
        write(joinpath(root, "terminal", "history", "restore.jsonl"), "{}\n")
        catalog = entries -> open(joinpath(root, "catalog.toml"), "w") do io
            ScenarioRunner.TOML.print(io, Dict("scenarios" => entries))
        end
        entries = Dict("second" => "terminal/second.jsonl",
            "first" => "settings/first.jsonl")
        catalog(entries)
        @test ScenarioRunner.scenario_names(root) == ["first", "second"]
        @test ScenarioRunner.scenario_sources(root) == entries
        selected = ScenarioRunner.parse_scenario_options(
            ["second", "--format=json"]; root)
        @test selected.names == ["second"]
        @test selected.format == :json
        @test !selected.listing
        @test ScenarioRunner.parse_scenario_options(["--all"]; root).names ==
            ["first", "second"]
        listed = ScenarioRunner.parse_scenario_options(["--list"]; root)
        @test listed.listing
        @test listed.names == ["first", "second"]
        for arguments in (["missing"], ["restore"], ["terminal/history/restore"],
            ["--list", "--all"], ["--list", "--format=xml"])
            @test_throws ErrorException ScenarioRunner.parse_scenario_options(
                arguments; root)
        end
        listing = IOBuffer()
        ScenarioRunner.write_scenario_listing(listing, :json; root)
        records = ScenarioRunner.JSON.parse(String(take!(listing))).scenarios
        @test [record.name for record in records] == ["first", "second"]
        @test [record.category for record in records] == ["settings", "terminal"]
        @test all(record -> record.kind == "scenario", records)
        @test [record.file for record in records] ==
            ["settings/first.jsonl", "terminal/second.jsonl"]
        ScenarioRunner.write_scenario_listing(listing, :text; root)
        @test occursin("first  settings  scenario  settings/first.jsonl",
            String(take!(listing)))
        for source in ("../outside.jsonl", "/outside.jsonl",
            "settings\\first.jsonl", "./settings/first.jsonl",
            "settings//first.jsonl", "settings/first.txt",
            "settings/missing.jsonl", 1)
            catalog(Dict("invalid" => source))
            @test_throws ErrorException ScenarioRunner.scenario_sources(root)
        end
        catalog(Dict("first" => entries["first"], "duplicate" => entries["first"]))
        @test_throws ErrorException ScenarioRunner.scenario_sources(root)
        catalog(Dict{String,String}())
        @test_throws ErrorException ScenarioRunner.scenario_sources(root)
        write(joinpath(root, "catalog.toml"), "scenarios = 1\n")
        @test_throws ErrorException ScenarioRunner.scenario_sources(root)
    end

    sources = ScenarioRunner.scenario_sources()
    @test length(sources) == 123
    @test all(source -> occursin('/', source), values(sources))
    @test isempty(filter(endswith(".jsonl"), readdir(ScenarioRunner.SCENARIO_ROOT)))
    workflows = first.(ScenarioRunner.scenario_workflows())
    @test length(workflows) == 12
    @test all(name -> haskey(sources, name), workflows)
    @test ScenarioRunner.scenario_source("keyboard-focus-acceptance") ==
        joinpath("tools", "scenarios", "ui", "keyboard-focus-acceptance.jsonl")
    listing = IOBuffer()
    ScenarioRunner.write_scenario_listing(listing, :json)
    records = ScenarioRunner.JSON.parse(String(take!(listing))).scenarios
    @test count(record -> record.kind == "workflow", records) == 12
    @test only(filter(record -> record.name == "settings-persistence-acceptance",
        records)).kind == "workflow"
    @test all(record -> isfile(joinpath(ScenarioRunner.SCENARIO_ROOT,
        split(record.file, '/')...)), records)

    first_path = ScenarioRunner.fresh_artifact_path("example")
    second_path = ScenarioRunner.fresh_artifact_path("example")
    @test first_path != second_path
    @test !ispath(first_path)
    inconclusive = (result="inconclusive", trace_complete=false, exit_code=1)
    @test !ScenarioRunner.scenario_passed(inconclusive)
    output = IOBuffer()
    ScenarioRunner.write_json_report(output, [inconclusive])
    report = ScenarioRunner.JSON.parse(String(take!(output)))
    @test !report.passed
    @test report.scenarios[1].result == "inconclusive"
end
