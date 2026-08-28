#!/usr/bin/env julia

import Pkg

const VERIFICATION_ANALYSIS_PROJECT = get(
    ENV,
    "ODIN_JULIA_ANALYSIS_PROJECT",
    joinpath(@__DIR__, "analysis"))

# Activate the analyzer project so JSON3 is available when this script runs
# standalone; reactivation is a no-op when the driver already activated it.
if !isdefined(Base, :JSON3) && Base.active_project() !=
        joinpath(VERIFICATION_ANALYSIS_PROJECT, "Project.toml")
    Pkg.activate(VERIFICATION_ANALYSIS_PROJECT; io=devnull)
end

module EuclidVerification

using JSON3

include(joinpath(@__DIR__, "test_runner.jl"))
using .EuclidTestRunner

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const ANALYSIS_PROJECT = get(
    ENV,
    "ODIN_JULIA_ANALYSIS_PROJECT",
    joinpath(@__DIR__, "analysis"))
const ANALYZER_SCRIPT = joinpath(@__DIR__, "analyze.jl")
const ANALYZER_SETTINGS = joinpath(@__DIR__, "analysis_settings.jl")
const ANALYZER_SELF_SETTINGS = joinpath(ANALYSIS_PROJECT, "settings.jl")
const ANALYZER_CLI = joinpath(ANALYSIS_PROJECT, "analyze.jl")
const JULIA_EXE = Base.julia_cmd().exec[1]
const ANSI_RESET = "\e[0m"
const ANSI_BOLD = "\e[1m"
const ANSI_GREEN = "\e[1;32m"
const ANSI_RED = "\e[1;31m"
const ANSI_YELLOW = "\e[1;33m"
const COUNT_MARKER = "__EUCLID_ANALYZER_TEST_COUNTS__"

@enum Verbosity Summary=0 Details=1 Trace=2

struct OutputPolicy
    verbosity::Verbosity
    color::Symbol
    format::String
    report_path::Union{Nothing, String}
    settings_path::Union{Nothing, String}
end

mutable struct OptionParseState
    verbosity::Verbosity
    color::Symbol
    format::String
    report_path::Union{Nothing, String}
    settings_path::Union{Nothing, String}
end

"""Construct the default mutable state used while parsing verification options."""
OptionParseState() = OptionParseState(Summary, :auto, "text", nothing, nothing)

"""Construct an output policy without report or settings overrides."""
OutputPolicy(verbosity::Verbosity, color::Symbol, format::String) =
    OutputPolicy(verbosity, color, format, nothing, nothing)

struct PhaseResult
    name::String
    detail::String
    elapsed_ns::UInt64
    status::String
    output::String
    metadata::Dict{String, Any}
end

"""Print verification runner usage."""
function usage(io::IO=stdout)
    println(io, "Usage: julia tools/verify.jl [OPTIONS]")
    println(io)
    println(io, "Options:")
    println(io, "  --verbosity=0|1|2       Summary, details, or complete trace output")
    println(io, "  --verbose               Alias for --verbosity=2")
    println(io, "  --color=auto|always|never")
    println(io, "  --format=text|json      Select human or complete machine output")
    println(io, "  --settings=PATH         Load Euclid analyzer settings from PATH")
    println(io, "  --report=PATH           Write the comprehensive analysis report")
end

"""Parse a numeric verbosity value or return its validation error."""
function parse_verbosity(value::AbstractString)
    value in ("0", "1", "2") || return "invalid verbosity: $value"
    return Verbosity(parse(Int, value))
end

"""Apply one non-empty settings or report path option."""
function parse_path_option!(state::OptionParseState, argument::String)
    value = split(argument, "="; limit=2)[2]
    if startswith(argument, "--settings=")
        isempty(value) && return "settings path must not be empty"
        state.settings_path = value
    else
        isempty(value) && return "report path must not be empty"
        state.report_path = value
    end
    return nothing
end

"""Apply one verification option, returning a sentinel or error when parsing stops."""
function parse_option!(state::OptionParseState, argument::String)
    argument in ("-h", "--help") && return :help
    if argument == "--verbose"
        state.verbosity = Trace
    elseif startswith(argument, "--verbosity=")
        value = split(argument, "="; limit=2)[2]
        verbosity = parse_verbosity(value)
        verbosity isa String && return verbosity
        state.verbosity = verbosity
    elseif startswith(argument, "--color=")
        state.color = Symbol(split(argument, "="; limit=2)[2])
    elseif startswith(argument, "--format=")
        state.format = split(argument, "="; limit=2)[2]
    elseif startswith(argument, "--settings=") ||
            startswith(argument, "--report=")
        return parse_path_option!(state, argument)
    else
        return "unknown option: $argument"
    end
    return nothing
end

"""Parse verification presentation options."""
function parse_options(arguments::Vector{String})
    state = OptionParseState()
    for argument in arguments
        result = parse_option!(state, argument)
        result === nothing || return result
    end
    return validated_output_policy(
        state.verbosity, state.color, state.format,
        state.report_path, state.settings_path)
end

"""Validate parsed presentation modes and construct the output policy."""
function validated_output_policy(verbosity, color, format, report_path, settings_path)
    color in (:auto, :always, :never) || return "unsupported color mode: $color"
    format in ("text", "json") || return "unsupported format: $format"
    return OutputPolicy(verbosity, color, format, report_path, settings_path)
end

"""Resolve a requested report path from the repository root."""
function resolve_report_path(report_path)
    report_path === nothing && return nothing
    return isabspath(report_path) ? normpath(report_path) :
        normpath(joinpath(REPOSITORY_ROOT, report_path))
end

"""Resolve a requested settings path from the repository root."""
function resolve_settings_path(settings_path)
    settings_path === nothing && return nothing
    return isabspath(settings_path) ? normpath(settings_path) :
        normpath(joinpath(REPOSITORY_ROOT, settings_path))
end

"""Run a command while retaining its combined output and elapsed time."""
function capture_command(command::Cmd)
    output = IOBuffer()
    started = time_ns()
    process = run(pipeline(ignorestatus(command), stdout=output, stderr=output))
    return (
        exit_code=process.exitcode,
        elapsed_ns=UInt64(time_ns() - started),
        output=String(take!(output)))
end

"""Run a command while retaining machine output and optionally streaming diagnostics."""
function capture_command_streams(command::Cmd; stream_errors::Bool=false)
    output = IOBuffer()
    errors = stream_errors ? stderr : IOBuffer()
    started = time_ns()
    process = run(pipeline(ignorestatus(command), stdout=output, stderr=errors))
    return (
        exit_code=process.exitcode,
        elapsed_ns=UInt64(time_ns() - started),
        output=String(take!(output)),
        errors=stream_errors ? "" : String(take!(errors)))
end

"""Discard successful analyzer-test chatter preceding the first test failure."""
function concise_analyzer_failure_output(output::String)
    failure = findfirst(r"(?m)^.*: Test Failed at ", output)
    failure === nothing && return output
    return output[first(failure):end]
end

"""Run all application test suites and aggregate their structured results."""
function run_application_tests_phase()
    started = time_ns()
    results = [EuclidTestRunner.run_suite(suite)
        for suite in EuclidTestRunner.suite_definitions()]
    elapsed_ns = UInt64(time_ns() - started)
    passed = all(result -> result.status == "PASS", results)
    tests = sum(something(result.tests, 0) for result in results)
    detail = all(result -> result.tests !== nothing, results) ?
        "$tests tests across Julia and Odin" : "test counts unavailable"
    output = join((result.output for result in results), "")
    suites = [Dict(
        "name" => result.name,
        "language" => result.language,
        "tests" => result.tests,
        "elapsed_ns" => result.elapsed_ns,
        "status" => lowercase(result.status),
        "output" => result.output) for result in results]
    metadata = Dict{String, Any}("tests" => tests, "suites" => suites)
    return PhaseResult(
        "Application tests", detail, elapsed_ns,
        passed ? "PASS" : "FAIL", output, metadata)
end

"""Run analyzer regression tests and extract structured Julia test counts."""
function run_analyzer_test_phase(trace::Bool=false)
    test_file = joinpath(ANALYSIS_PROJECT, "test", "runtests.jl")
    expression = "using Test, JSON3; result=include($(repr(test_file))); " *
        "counts=Test.get_test_counts(result); println(\"$COUNT_MARKER\", " *
        "JSON3.write(Dict(" *
        "\"passed\"=>counts.passes + counts.cumulative_passes, " *
        "\"failed\"=>counts.fails + counts.cumulative_fails, " *
        "\"errors\"=>counts.errors + counts.cumulative_errors, " *
        "\"broken\"=>counts.broken + counts.cumulative_broken)))"
    command = Cmd(
        `$(Base.julia_cmd()) --project=$ANALYSIS_PROJECT -e $expression`;
        dir=REPOSITORY_ROOT)
    result = capture_command(command)
    counts = analyzer_test_counts(result.output)
    tests = sum(get(counts, key, 0) for key in ("passed", "failed", "errors", "broken"))
    detail = isempty(counts) ? "test counts unavailable" : "$tests tests"
    metadata = Dict{String, Any}(
        "exit_code" => result.exit_code, "counts" => counts)
    output = !trace && result.exit_code != 0 ?
        concise_analyzer_failure_output(result.output) : result.output
    return PhaseResult(
        "Analyzer tests", detail, result.elapsed_ns,
        result.exit_code == 0 ? "PASS" : "FAIL", output, metadata)
end

"""Parse an analyzer JSON report; report-parse failure returns nothing, not a crash."""
function parse_json_report(output::String)
    return try
        JSON3.read(output)
    catch parse_error
        parse_error isa Exception || rethrow()
        nothing
    end
end

"""Extract the analyzer test count marker from process output."""
function analyzer_test_counts(output::String)
    marker = findlast(COUNT_MARKER, output)
    marker === nothing && return Dict{String, Any}()
    parsed = parse_json_report(output[last(marker) + 1:end])
    parsed === nothing && return Dict{String, Any}()
    return Dict{String, Any}(String(key) => value for (key, value) in pairs(parsed))
end

"""Analyze the analyzer's own source with its self-analysis settings."""
function run_self_analysis_phase(stream_progress::Bool=false)
    arguments = [
        Base.julia_cmd().exec...,
        ANALYZER_CLI,
        "check",
        ANALYSIS_PROJECT,
        "--settings=$ANALYZER_SELF_SETTINGS",
        "--format=json",
    ]
    stream_progress && push!(arguments, "--progress=always")
    command = Cmd(Cmd(arguments); dir=REPOSITORY_ROOT)
    result = capture_command_streams(command; stream_errors=stream_progress)
    report = parse_json_report(result.output)
    diagnostics = report === nothing ? Any[] : collect(report.diagnostics)
    warnings = count(item -> lowercase(String(item.response)) == "warn", diagnostics)
    failures = count(item -> lowercase(String(item.response)) == "fail", diagnostics)
    files = report === nothing ? 0 : Int(report.files_analyzed)
    detail = report === nothing ? "analysis failed" :
        "$files files, $warnings warnings, $failures failures"
    metadata = Dict{String, Any}(
        "exit_code" => result.exit_code,
        "warnings" => warnings,
        "failures" => failures,
        "report" => report)
    phase_output = isempty(result.errors) ? result.output :
        result.errors * result.output
    return PhaseResult(
        "Analyzer self-analysis", detail, result.elapsed_ns,
        result.exit_code == 0 ? "PASS" : "FAIL", phase_output, metadata)
end

"""Analyze the Euclid repository and retain the complete machine report."""
function run_euclid_analysis_phase(
    report_path=nothing,
    settings_path=nothing,
    stream_progress::Bool=false)
    arguments = [
        Base.julia_cmd().exec...,
        ANALYZER_SCRIPT,
        "check",
        REPOSITORY_ROOT,
        "--format=json",
    ]
    stream_progress && push!(arguments, "--progress=always")
    push!(arguments, "--settings=$(settings_path === nothing ?
        ANALYZER_SETTINGS : settings_path)")
    report_path === nothing || push!(arguments, "--report=$report_path")
    command = Cmd(Cmd(arguments); dir=REPOSITORY_ROOT)
    result = capture_command_streams(command; stream_errors=stream_progress)
    report = parse_json_report(result.output)
    diagnostics = report === nothing ? Any[] : collect(report.diagnostics)
    warnings = count(item -> lowercase(String(item.response)) == "warn", diagnostics)
    failures = count(item -> lowercase(String(item.response)) == "fail", diagnostics)
    files = report === nothing ? 0 : Int(report.files_analyzed)
    detail = report === nothing ? "analysis failed" :
        "$files files, $warnings warnings, $failures failures"
    metadata = Dict{String, Any}(
        "exit_code" => result.exit_code,
        "warnings" => warnings,
        "failures" => failures,
        "report" => report)
    phase_output = isempty(result.errors) ? result.output :
        result.errors * result.output
    return PhaseResult(
        "Repository analysis", detail, result.elapsed_ns,
        result.exit_code == 0 ? "PASS" : "FAIL", phase_output, metadata)
end

"""Return whether ANSI styling should be used for this stream."""
function color_enabled(io::IO, color::Symbol)
    color == :always && return true
    color == :never && return false
    return !haskey(ENV, "NO_COLOR") && get(io, :color, false)
end

"""Apply an ANSI style when color output is enabled."""
function styled(text::AbstractString, style::AbstractString, enabled::Bool)
    return enabled ? style * text * ANSI_RESET : text
end

"""Select the ANSI style for a phase status."""
function status_style(status::String)
    status == "PASS" && return ANSI_GREEN
    status == "FAIL" && return ANSI_RED
    return ANSI_YELLOW
end

"""Format a nanosecond duration for human output."""
function format_duration(elapsed_ns::UInt64)
    elapsed_ms = elapsed_ns / 1_000_000
    elapsed_ms < 1 && return "<1 ms"
    elapsed_ms < 1_000 && return "$(round(Int, elapsed_ms)) ms"
    return "$(round(elapsed_ms / 1_000; digits=2)) s"
end

"""Render one aligned table row."""
function table_line(values, widths)
    cells = (rpad(string(value), width) for (value, width) in zip(values, widths))
    return "| " * join(cells, " | ") * " |"
end

"""Render the unified phase summary table."""
function write_table(io::IO, results::Vector{PhaseResult}, use_color::Bool)
    headers = ["Phase", "Result", "Time", "Status"]
    rows = [[
        result.name,
        result.detail,
        format_duration(result.elapsed_ns),
        result.status,
    ] for result in results]
    widths = [maximum(textwidth(string(row[column])) for row in vcat([headers], rows))
        for column in eachindex(headers)]
    separators = (repeat("-", width + 2) for width in widths)
    separator = "+" * join(separators, "+") * "+"
    println(io, separator)
    println(io, table_line(headers, widths))
    println(io, separator)
    for (result, row) in zip(results, rows)
        prefix = table_line(row[1:end - 1], widths[1:end - 1])
        padded_status = rpad(row[end], widths[end])
        status = styled(padded_status, status_style(result.status), use_color)
        println(io, prefix, " ", status, " |")
    end
    println(io, separator)
end

"""Write compact repository statistics and estimate summaries."""
function write_statistics(io::IO, analysis::PhaseResult, use_color::Bool)
    report = get(analysis.metadata, "report", nothing)
    report === nothing && return
    statistics = report.statistics
    headers = [
        "Language", "Files", "Functions", "Structs", "Lines", "Blank", "Comment",
        "Code", "Complexity", "Complexity/Code"]
    rows = [
        code_statistics_row("Odin", statistics.code_by_language.odin),
        code_statistics_row("Julia", statistics.code_by_language.julia),
        code_statistics_row("Total", statistics.code),
    ]
    widths = [maximum(textwidth(string(row[index])) for row in vcat([headers], rows))
        for index in eachindex(headers)]
    separator = "+" * join((repeat("-", width + 2) for width in widths), "+") * "+"
    println(io)
    println(io, styled("CODE STATISTICS", ANSI_BOLD, use_color))
    println(io)
    println(io, separator)
    println(io, table_line(headers, widths))
    println(io, separator)
    for row in rows
        println(io, table_line(row, widths))
    end
    println(io, separator)
    write_estimate_summaries(io, statistics)
end

"""Write compact COCOMO and LOCOMO estimate summaries."""
function write_estimate_summaries(io, statistics)
    cocomo = statistics.cocomo
    locomo = statistics.locomo
    println(io, "COCOMO ($(cocomo.model)): \$", round(Int, cocomo.estimated_cost),
        ", ", round(cocomo.effort_person_months; digits=2), " person-months, ",
        round(cocomo.schedule_months; digits=2), " months, ",
        round(cocomo.people; digits=2), " people")
    println(io, "LOCOMO ($(locomo.preset)): \$",
        round(locomo.estimated_cost; digits=2), ", ",
        round(Int, locomo.input_tokens), " input / ",
        round(Int, locomo.output_tokens), " output tokens, ",
        round(locomo.estimated_cycles; digits=2), " cycles, ",
        round(locomo.generation_seconds / 3600; digits=2), " generation hours, ",
        round(locomo.review_hours; digits=2), " review hours")
end

"""Return one compact code-statistics table row."""
function code_statistics_row(language, code)
    return Any[
        language,
        Int(code.files),
        Int(code.functions),
        Int(code.structs),
        Int(code.lines),
        Int(code.blank_lines),
        Int(code.comment_lines),
        Int(code.code_lines),
        Int(code.complexity),
        round(code.complexity_per_code_line; digits=3),
    ]
end

"""Return the single phase with the requested name, or nothing when absent."""
function find_phase(results::Vector{PhaseResult}, name::String)
    matches = filter(result -> result.name == name, results)
    return isempty(matches) ? nothing : only(matches)
end

"""Write curated phase details for level-one output."""
function write_details(io::IO, results::Vector{PhaseResult})
    analyzer = find_phase(results, "Analyzer tests")
    if analyzer !== nothing
        counts = analyzer.metadata["counts"]
        println(io, "Analyzer tests: ", isempty(counts) ? "counts unavailable" :
            join(("$key=$(get(counts, key, 0))"
                for key in ("passed", "failed", "errors", "broken")), ", "))
    end
    analysis = find_phase(results, "Repository analysis")
    analysis === nothing && return
    report = get(analysis.metadata, "report", nothing)
    report === nothing && return
    engine_count = length(report.engines)
    rule_count = length(report.rules)
    println(io, "Repository analysis: $engine_count engines, $rule_count rules")
end

"""Write diagnostics that must remain visible at every verbosity."""
function write_diagnostics(io::IO, analysis::PhaseResult, use_color::Bool)
    report = get(analysis.metadata, "report", nothing)
    report === nothing && return
    visible = filter(item -> lowercase(String(item.response)) in ("warn", "fail"),
        report.diagnostics)
    isempty(visible) && return
    println(io)
    println(io, styled("ANALYSIS DIAGNOSTICS", ANSI_BOLD, use_color))
    for item in visible
        severity = uppercase(String(item.response))
        style = severity == "FAIL" ? ANSI_RED : ANSI_YELLOW
        location = "$(item.path):$(item.line):$(item.column)"
        println(io, styled(severity, style, use_color), " ", location,
            " [$(item.rule_id)] ", item.message)
    end
end

"""Replay complete captured phase output for trace verbosity."""
function write_trace(io::IO, results::Vector{PhaseResult}, use_color::Bool)
    for result in results
        println(io)
        println(io, styled("TRACE: $(uppercase(result.name))", ANSI_BOLD, use_color))
        isempty(result.output) && (println(io, "(no output)"); continue)
        print(io, result.output)
        endswith(result.output, '\n') || println(io)
    end
end

"""Return whether a failed phase has unrepresented output worth replaying."""
function should_replay_failure_output(result::PhaseResult)
    endswith(result.name, "analysis") || return true
    return get(result.metadata, "report", nothing) === nothing
end

"""Write the human-readable unified verification report."""
function write_text_report(io::IO, results::Vector{PhaseResult}, policy::OutputPolicy)
    use_color = color_enabled(io, policy.color)
    println(io, styled("VERIFICATION", ANSI_BOLD, use_color))
    println(io)
    write_table(io, results, use_color)
    analysis = find_phase(results, "Repository analysis")
    analysis !== nothing && write_statistics(io, analysis, use_color)
    policy.verbosity >= Details && (println(io); write_details(io, results))
    analysis !== nothing && write_diagnostics(io, analysis, use_color)
    failed = filter(result -> result.status == "FAIL", results)
    if policy.verbosity < Trace
        for result in filter(should_replay_failure_output, failed)
            println(io)
            println(io, styled("FAILURE: $(result.name)", ANSI_RED, use_color))
            print(io, result.output)
            endswith(result.output, '\n') || println(io)
        end
    else
        write_trace(io, results, use_color)
    end
    println(io)
    overall = isempty(failed) ? "PASS" : "FAIL"
    println(io, styled("Verification: $overall", status_style(overall), use_color))
end

"""Convert a phase result to its complete machine representation."""
function phase_json(result::PhaseResult)
    return Dict(
        "name" => result.name,
        "detail" => result.detail,
        "elapsed_ns" => result.elapsed_ns,
        "status" => lowercase(result.status),
        "output" => result.output,
        "metadata" => result.metadata)
end

"""Write the complete verbosity-independent verification report as JSON."""
function write_json_report(io::IO, results::Vector{PhaseResult})
    report = Dict(
        "schema_version" => "1.0.0",
        "passed" => all(result -> result.status == "PASS", results),
        "phases" => phase_json.(results))
    JSON3.pretty(io, report)
    println(io)
end

"""Run one phase while writing immediate start and completion progress."""
function run_progress_phase(progress_io, index, total, name, operation)
    progress_io === nothing || begin
        println(progress_io, "  [$index/$total] $name")
        flush(progress_io)
    end
    result = operation()
    progress_io === nothing || begin
        println(progress_io, "        $(result.status)  $(result.detail) " *
            "($(format_duration(result.elapsed_ns)))")
        flush(progress_io)
    end
    return result
end

"""Return the labeled phase operations for one gate selection."""
function selected_phase_specs(
    selection::Symbol, policy::OutputPolicy, report_path, settings_path,
    progress_io)
    selection in (:tests, :analysis, :full) ||
        error("unsupported phase selection: $selection")
    specs = Tuple{String, Function}[]
    if selection in (:tests, :full)
        push!(specs, ("Run application tests", run_application_tests_phase))
        push!(specs, ("Run analyzer regression tests",
            () -> run_analyzer_test_phase(policy.verbosity == Trace)))
    end
    if selection == :full
        push!(specs, ("Run analyzer self-analysis",
            () -> run_self_analysis_phase(progress_io !== nothing)))
    end
    if selection in (:analysis, :full)
        push!(specs, ("Analyze the Euclid repository",
            () -> run_euclid_analysis_phase(
                report_path,
                settings_path,
                progress_io !== nothing)))
    end
    return specs
end

"""Run verification phases; an optional build phase result is attached first."""
function run_phases(
    policy::OutputPolicy; progress_io=stderr,
    build_phase::Union{PhaseResult, Nothing}=nothing,
    selection::Symbol=:full)
    progress_io === nothing || begin
        println(progress_io, "VERIFICATION PROGRESS")
        flush(progress_io)
    end
    report_path = resolve_report_path(policy.report_path)
    settings_path = resolve_settings_path(policy.settings_path)
    specs = selected_phase_specs(
        selection, policy, report_path, settings_path, progress_io)
    results = [run_progress_phase(
        progress_io,
        index,
        length(specs),
        name,
        operation) for (index, (name, operation)) in enumerate(specs)]
    build_phase === nothing || pushfirst!(results, build_phase)
    return results
end

"""Run the selected phases, write the report, and return the gate exit code."""
function execute_gate(
    policy::OutputPolicy; build_phase::Union{PhaseResult, Nothing}=nothing,
    selection::Symbol=:full)
    results = run_phases(policy; build_phase=build_phase, selection=selection)
    policy.format == "json" ? write_json_report(stdout, results) :
        write_text_report(stdout, results, policy)
    return all(result -> result.status == "PASS", results) ? 0 : 1
end

"""Convert a completed strict build into the build phase result."""
function make_build_phase(
    detail::String, elapsed_ns::UInt64, exit_code::Int, output::String)
    status = exit_code == 0 ? "PASS" : "FAIL"
    metadata = Dict{String, Any}("exit_code" => exit_code)
    return PhaseResult("Build", detail, elapsed_ns, status, output, metadata)
end

"""Run the verification gate for an outer driver, attaching the strict build result."""
function driver_gate(
    arguments::Vector{String},
    selection::Symbol,
    build::Union{Nothing, NamedTuple})
    policy = parse_options(arguments)
    if policy === :help
        usage()
        return 0
    elseif policy isa String
        println(stderr, "verify.jl: $policy")
        return 2
    end
    build_phase = build === nothing ? nothing : make_build_phase(
        build.detail, build.elapsed_ns, build.exit_code, build.output)
    return execute_gate(policy; build_phase=build_phase, selection=selection)
end

"""Run the repository verification command."""
function main(arguments::Vector{String})
    policy = parse_options(arguments)
    if policy === :help
        usage()
        return 0
    elseif policy isa String
        println(stderr, "verify.jl: $policy")
        return 2
    end
    return execute_gate(policy)
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(EuclidVerification.main(ARGS))
end
