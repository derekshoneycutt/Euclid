#!/usr/bin/env julia

module EuclidScenarioRunner

using Dates
using JSON
using UUIDs
using SHA

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
function run_scenario_launch(binary::String, name::String, source::String,
    artifact_path::String, arguments::Vector{String};
    environment::Vector{Pair{String,String}}=Pair{String,String}[])
    artifact_argument = replace(relpath(artifact_path, REPOSITORY_ROOT), '\\' => '/')
    command = addenv(Cmd([binary, arguments..., "--scenario=$source",
        "--scenario-artifacts=$artifact_argument"]), environment...)
    process = capture_process(command)
    mkpath(artifact_path)
    write(joinpath(artifact_path, "process.stdout.log"), process.stdout)
    write(joinpath(artifact_path, "process.stderr.log"), process.stderr)
    bundle = inspect_scenario_bundle(artifact_path, process)
    manifest = bundle.manifest
    return (name=name, file=replace(source, '\\' => '/'),
        artifacts=artifact_argument, result=String(manifest.result),
        reason=String(manifest.reason), failed_step=Int(manifest.failed_step),
        trace_complete=Bool(manifest.trace_complete), exit_code=process.exit_code)
end

"""Run ordinary scenarios without ever opening the developer's preferences."""
function run_scenario(binary::String, name::String)
    return run_scenario_launch(binary, name,
        joinpath("tools", "scenarios", "$name.jsonl"),
        fresh_artifact_path(name), ["--no-user-db"])
end

"""Read canonical committed scalar rows through a separate read-only SQLite process."""
function settings_database_rows(path::String)
    sqlite = Sys.which("sqlite3")
    sqlite === nothing && error("Settings acceptance requires the sqlite3 CLI")
    query = "SELECT namespace,key,value_type,integer_value,text_value " *
        "FROM user_setting ORDER BY namespace,key"
    process = capture_process(Cmd([sqlite, "-readonly", "-json", path, query]))
    process.exit_code == 0 || error("Settings inspection failed: $(process.stderr)")
    return JSON.parse(process.stdout)
end

"""Reject incomplete manifests, bad frees, unjoined saves and owner execution."""
function validate_settings_launch(record)
    scenario_passed(record) || error("Settings launch failed: $(record.name)")
    bundle = EuclidEvidence.inspect_bundle(joinpath(REPOSITORY_ROOT, record.artifacts))
    settings = bundle.state.settings
    !settings.active || error("Settings save remained active after shutdown")
    settings.owner_execution_count == 0 ||
        error("Settings save executed on display owner")
    bundle.allocations.bad_frees == 0 || error("Settings launch reported bad frees")
    path = joinpath(REPOSITORY_ROOT, record.artifacts)
    validate_settings_process(read(joinpath(path, "process.stdout.log"), String))
    validate_settings_trace(path, settings)
    return bundle
end

"""Require the post-teardown debug allocator report, not an earlier live-state sample."""
function validate_settings_process(output::String)
    pattern = Regex("== allocation evidence: live=(\\d+) current_bytes=(\\d+) " *
        "peak_bytes=\\d+ total=\\d+ bad_frees=(\\d+) ==")
    summary = match(pattern, output)
    summary === nothing && error("Settings launch lacks final debug allocation evidence")
    all(value -> parse(Int, value) == 0, summary.captures) ||
        error("Settings launch retained allocations or reported bad frees")
    return nothing
end

"""Require every joined outcome to match an earlier submitted task identity and batch."""
function validate_settings_trace(path::String, settings)
    trace_path = joinpath(path, "evidence.bin")
    submitted = EuclidEvidence.query_trace(trace_path;
        kind="settings_save_submitted", limit=1_000)
    committed = EuclidEvidence.query_trace(trace_path;
        kind="settings_save_committed", limit=1_000)
    failed = EuclidEvidence.query_trace(trace_path;
        kind="settings_save_failed", limit=1_000)
    length(committed) == settings.commit_count ||
        error("Commit trace disagrees with state")
    length(failed) == settings.failure_count ||
        error("Failure trace disagrees with state")
    length(submitted) == length(committed) + length(failed) ||
        error("Settings trace contains unjoined tasks")
    for event in vcat(committed, failed)
        validate_settings_outcome(event, submitted)
    end
end

"""Check owner, task generation, ordering, immutable batch size and commit executor."""
function validate_settings_outcome(event, submitted)
    event.correlation_kind == "task" && event.producer == "display" ||
        error("Settings outcome has the wrong owner or identity domain")
    matching = filter(candidate -> candidate.correlation == event.correlation &&
        candidate.generation == event.generation &&
        candidate.correlation_kind == event.correlation_kind, submitted)
    length(matching) == 1 || error("Settings outcome lacks a unique submission")
    only(matching).sequence < event.sequence || error("Outcome preceded submission")
    only(matching).payload.first == event.payload.first ||
        error("Settings batch changed during execution")
    event.kind != "settings_save_committed" || event.payload.second == 0 ||
        error("Commit trace reports owner execution")
    return nothing
end

"""Check the full persisted startup and control intent through independent row reads."""
function validate_settings_committed_rows(database::String)
    rows = settings_database_rows(database)
    for (namespace, key, value) in [
        ("window", "width", 900), ("window", "height", 650),
        ("window", "mode", "fixed"), ("window", "layout", "landscape"),
        ("drawing", "dust_limit", 1400), ("drawing", "sound_enabled", 1),
        ("interface", "display_fps", 1), ("rendering", "limit_fps", 0),
        ("rendering", "simd", 0), ("rendering", "gpu_dust_instancing", 0)]
        require_setting_row(rows, namespace, key, value)
    end
    return rows
end

"""Require an exact committed preference value, not merely an in-memory observation."""
function require_setting_row(rows, namespace::String, key::String, expected)
    matching = filter(row -> row["namespace"] == namespace && row["key"] == key, rows)
    length(matching) == 1 || error("Missing or duplicate setting: $namespace.$key")
    row = only(matching)
    column = expected isa String ? "text_value" : "integer_value"
    row[column] == expected || error("Unexpected committed setting: $namespace.$key")
    return nothing
end

"""Prove restore, temporary overrides, disabled storage, final flush and failed writes."""
function run_settings_acceptance(binary::String)
    root = fresh_artifact_path("settings-persistence")
    mkpath(root)
    database = joinpath(root, "user.sqlite3")
    records = NamedTuple[]
    fake_home = joinpath(root, "data-home")
    isolated_environment = ["XDG_DATA_HOME" => fake_home,
        "LOCALAPPDATA" => fake_home, "APPDATA" => fake_home]
    launch = (name, source, arguments; environment=Pair{String,String}[]) -> begin
        record = run_scenario_launch(binary, "settings-$name", source,
            joinpath(root, name), arguments;
            environment=vcat(isolated_environment, environment))
        push!(records, record)
        return validate_settings_launch(record)
    end
    source = name -> joinpath("tools", "scenarios", "settings", "$name.jsonl")
    first = launch("first", joinpath("tools", "scenarios",
        "settings-persistence-acceptance.jsonl"), ["--user-db=$database", "--persist",
        "--window-size=900x650", "--window-mode=fixed", "--layout=landscape",
        "--no-simd", "--no-gpu-dust-instancing"])
    first.state.settings.commit_count == 1 ||
        error("Settings edits did not form one batch")
    ispath(fake_home) && error("Custom database launch touched the default data directory")
    rows = validate_settings_committed_rows(database)
    restored = launch("restore", source("restore"), ["--user-db=$database"])
    restored.state.settings.window_width == 900 || error("Restored window width differs")
    restored.state.settings.window_height == 650 ||
        error("Restored window height differs")
    baseline = sha256(read(database))
    launch("override", source("override"),
        ["--user-db=$database", "--window-size=800x600"])
    sha256(read(database)) == baseline || error("Temporary CLI override changed database")
    settings_database_rows(database) == rows || error("CLI override changed saved rows")
    run_settings_storage_edges(launch, source, root, database, baseline)
    validate_settings_persist_rejection(binary, database, root, isolated_environment)
    return records
end

"""Require explicit startup persistence failure to exit nonzero without changing rows."""
function validate_settings_persist_rejection(binary, database, root, environment)
    baseline = sha256(read(database))
    process = capture_process(addenv(Cmd([binary, "--user-db=$database",
        "--persist", "--window-size=800x600"]), environment...))
    write(joinpath(root, "persist-rejected.stdout.log"), process.stdout)
    write(joinpath(root, "persist-rejected.stderr.log"), process.stderr)
    process.exit_code != 0 || error("Rejected explicit persistence exited successfully")
    occursin("Unable to persist explicit settings", process.stderr) ||
        error("Explicit persistence failed for an unexpected reason")
    sha256(read(database)) == baseline || error("Rejected persistence changed saved rows")
    validate_settings_process(process.stdout)
end

"""Exercise isolated no-store, shutdown-flush and genuine SQLite transaction failure."""
function run_settings_storage_edges(launch, source, root, database, baseline)
    fake_home = joinpath(root, "data-home")
    fake_default = joinpath(fake_home, "Euclid", "user.sqlite3")
    mkpath(dirname(fake_default))
    cp(database, fake_default)
    disabled = launch("no-database", source("no-database"), ["--no-user-db"];
        environment=["XDG_DATA_HOME" => fake_home, "LOCALAPPDATA" => fake_home,
            "APPDATA" => fake_home])
    disabled.state.settings.commit_count == 0 || error("Disabled storage submitted saves")
    sha256(read(fake_default)) == baseline ||
        error("Disabled storage changed default rows")
    sha256(read(database)) == baseline ||
        error("Disabled storage changed custom database")
    readdir(dirname(fake_default)) == ["user.sqlite3"] ||
        error("Disabled storage created database side files")
    flushed = launch("shutdown", source("shutdown"), ["--user-db=$database"])
    flushed.state.settings.pending_count == 0 || error("Shutdown left unsaved edits")
    require_setting_row(settings_database_rows(database), "drawing", "dust_limit", 1500)
    sqlite = Sys.which("sqlite3")
    fault = capture_process(Cmd([sqlite, database,
        "CREATE TRIGGER settings_acceptance_failure BEFORE INSERT ON user_setting " *
        "BEGIN SELECT RAISE(ABORT,'settings acceptance fault'); END"]))
    fault.exit_code == 0 ||
        error("Cannot create isolated failure fixture: $(fault.stderr)")
    degraded = launch("degraded", source("degraded"), ["--user-db=$database"])
    degraded.state.settings.failure_count == 3 ||
        error("Retries were not capped at three")
    degraded.state.settings.pending_count == 1 || error("Failed edit was not retained")
    require_setting_row(settings_database_rows(database), "drawing", "dust_limit", 1500)
end

"""Return whether a scenario record represents an unqualified successful run."""
scenario_passed(record) = record.result == "passed" && record.trace_complete &&
    record.exit_code == 0

"""Write scenario records as stable machine-readable JSON."""
function write_json_report(io::IO, records)
    report = (schema_version=SCENARIO_SCHEMA_VERSION,
        passed=all(scenario_passed, records), scenarios=records)
    println(io, JSON.json(report))
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
    records = NamedTuple[]
    for name in options.names
        if name == "settings-persistence-acceptance"
            append!(records, run_settings_acceptance(binary))
        else
            push!(records, run_scenario(binary, name))
        end
    end
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