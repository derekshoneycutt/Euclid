#!/usr/bin/env julia

module EuclidScenarioRunner

using Dates
using JSON3
using UUIDs

include(joinpath(@__DIR__, "evidence.jl"))
using .EuclidEvidence

const SCENARIO_SCHEMA_VERSION = "1.0.0"
const REPOSITORY_ROOT = abspath(joinpath(@__DIR__, ".."))
const SCENARIO_ROOT = joinpath(REPOSITORY_ROOT, "tools", "scenarios")
const ARTIFACT_ROOT = joinpath(REPOSITORY_ROOT, ".build", "scenarios")

"""Selection and presentation requested for one scenario invocation."""
struct ScenarioOptions
    names::Vector{String}
    format::Symbol
end

"""Captured process outcome for one application invocation."""
struct ProcessResult
    exit_code::Int
    stdout::String
    stderr::String
end

"""Return all behavior names represented by source-controlled scenarios."""
function scenario_names(root::AbstractString=SCENARIO_ROOT)
    isdir(root) || error("Scenario directory is missing: $root")
    names = [splitext(name)[1] for name in readdir(root) if endswith(name, ".jsonl")]
    isempty(names) && error("No scenarios found in $root")
    return sort!(names)
end

"""Parse one named scenario or the complete corpus plus output format."""
function parse_scenario_options(arguments::Vector{String}; root=SCENARIO_ROOT)
    format = :text
    selectors = String[]
    for argument in arguments
        if startswith(argument, "--format=")
            value = split(argument, "="; limit=2)[2]
            value in ("text", "json") || error("Unsupported scenario format: $value")
            format = Symbol(value)
        else
            push!(selectors, argument)
        end
    end
    length(selectors) == 1 || error("scenario requires one NAME or --all")
    available = scenario_names(root)
    names = only(selectors) == "--all" ? available : [only(selectors)]
    all(name -> name in available, names) || error(
        "Unknown scenario: $(only(selectors))")
    return ScenarioOptions(names, format)
end

"""Create a collision-resistant repository-relative artifact path for one run."""
function fresh_artifact_path(name::String; root=ARTIFACT_ROOT)
    timestamp = Dates.format(now(UTC), "yyyymmdd-HHMMSS")
    identity = first(string(uuid4()), 8)
    path = joinpath(root, "$name-$timestamp-$identity")
    ispath(path) && error("Scenario artifact path already exists: $path")
    return path
end

"""Run one command while retaining output needed for concise failure reporting."""
function capture_process(command::Cmd; cwd::AbstractString=REPOSITORY_ROOT)
    output = IOBuffer()
    errors = IOBuffer()
    exit_code = 0
    try
        cd(cwd) do
            run(pipeline(command; stdout=output, stderr=errors))
        end
    catch error_object
        exit_code = error_object isa Base.ProcessFailedException ?
            error_object.procs[1].exitcode : 1
    end
    return ProcessResult(exit_code, String(take!(output)), String(take!(errors)))
end

"""Validate a produced bundle and preserve child output when production failed."""
function inspect_scenario_bundle(path::String, process::ProcessResult)
    try
        return EuclidEvidence.inspect_bundle(path)
    catch error_object
        output = isempty(strip(process.stderr)) ? process.stdout : process.stderr
        detail = isempty(strip(output)) ? "" : "\n" * strip(output)
        error("Scenario did not produce a valid bundle: " *
            sprint(showerror, error_object) * detail)
    end
end

"""Run one scenario and return its validated manifest-derived result record."""
function run_scenario(binary::String, name::String)
    source = joinpath("tools", "scenarios", "$name.jsonl")
    artifact_path = fresh_artifact_path(name)
    artifact_argument = replace(relpath(artifact_path, REPOSITORY_ROOT), '\\' => '/')
    command = Cmd([binary, "--scenario=$source",
        "--scenario-artifacts=$artifact_argument"])
    process = capture_process(command)
    bundle = inspect_scenario_bundle(artifact_path, process)
    manifest = bundle.manifest
    return (name=name, file=replace(source, '\\' => '/'),
        artifacts=artifact_argument, result=String(manifest.result),
        reason=String(manifest.reason), failed_step=Int(manifest.failed_step),
        trace_complete=Bool(manifest.trace_complete), exit_code=process.exit_code)
end

"""Return whether a scenario record represents an unqualified successful run."""
scenario_passed(record) = record.result == "passed" && record.trace_complete &&
    record.exit_code == 0

"""Write scenario records as stable machine-readable JSON."""
function write_json_report(io::IO, records)
    report = (schema_version=SCENARIO_SCHEMA_VERSION,
        passed=all(scenario_passed, records), scenarios=records)
    println(io, JSON3.write(report))
end

"""Write concise human-readable scenario outcomes and artifact locations."""
function write_text_report(io::IO, records)
    for record in records
        status = uppercase(record.result)
        println(io, "$status  $(record.name)  $(record.artifacts)")
        if !scenario_passed(record)
            println(io, "       reason=$(record.reason) failed_step=$(record.failed_step)")
        end
    end
end

"""Run the selected scenario set and return a process-style status."""
function run_selected(binary::String, options::ScenarioOptions; io::IO=stdout)
    records = [run_scenario(binary, name) for name in options.names]
    options.format == :json ? write_json_report(io, records) :
        write_text_report(io, records)
    return all(scenario_passed, records) ? 0 : 1
end

"""Run the standalone scenario boundary used by the repository driver."""
function main(arguments::Vector{String}=collect(ARGS))
    binary_index = findfirst(startswith("--binary="), arguments)
    binary_index === nothing && error("scenario runner requires --binary=PATH")
    binary = String(split(arguments[binary_index], "="; limit=2)[2])
    isfile(binary) || error("Scenario binary is missing: $binary")
    options = parse_scenario_options(deleteat!(copy(arguments), binary_index))
    return run_selected(binary, options)
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(EuclidScenarioRunner.main())
end