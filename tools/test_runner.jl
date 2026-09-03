#!/usr/bin/env julia

module EuclidTestRunner

include("build_config.jl")
using .EuclidBuildConfiguration: native_linker_flags, native_runtime_environment

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const JULIA_EXE = Base.julia_cmd().exec[1]
const JULIA_TEST_RUNNER = joinpath(
    REPOSITORY_ROOT, "src", "julia", "test", "runtests.jl")
const JULIA_TEST_PROJECT = joinpath(REPOSITORY_ROOT, "src", "julia")
const ANSI_RESET = "\e[0m"
const ANSI_BOLD = "\e[1m"
const ANSI_BOLD_GREEN = "\e[1;32m"
const ANSI_BOLD_RED = "\e[1;31m"
const ANSI_YELLOW = "\e[33m"

struct SuiteDefinition
    name::String
    language::String
end

struct SuiteResult
    name::String
    language::String
    tests::Union{Nothing, Int}
    elapsed_ns::UInt64
    status::String
    output::String
end

"""Return all application test suite definitions."""
function suite_definitions()
    return [
        SuiteDefinition("julia", "Julia"),
        SuiteDefinition("odin", "Odin"),
    ]
end

"""Assemble the odin test command with complete native linkage."""
function odin_test_command(linker_flags::String)
    odin_command = [
        "odin",
        "test",
        joinpath(REPOSITORY_ROOT, "src"),
        "-all-packages",
        "-define:ODIN_TEST_THREADS=1",
    ]
    if Sys.iswindows()
        linker_flags = strip(string(linker_flags, " /STACK:8388608"))
    end
    if !Sys.iswindows() && !Sys.isapple()
        linker_flags = strip(string(
            linker_flags,
            " -lX11 -lXrandr -lXi -lXcursor -lXinerama"))
    end
    if !isempty(linker_flags)
        push!(odin_command, "-extra-linker-flags:$linker_flags")
    end
    return odin_command
end

"""Write test-runner command-line usage information."""
function usage(io::IO=stdout)
    println(io, "Usage: julia tools/test_runner.jl [SUITE] [OPTIONS]")
    println(io)
    println(io, "Run Euclid application test suites.")
    println(io)
    println(io, "Options:")
    println(io, "  --format=text|json         Select human or machine output")
    println(io, "  --color=auto|always|never  Control text report colors")
    println(io, "  -h, --help                 Show this help")
    println(io)
    println(io, "Suites:")
    for suite in suite_definitions()
        println(io, "  $(suite.name)  $(suite.language) tests")
    end
end

"""Parse test-runner suite and output options."""
function parse_options(arguments::Vector{String})
    selected_suite = nothing
    format = "text"
    color = :auto

    for argument in arguments
        if argument in ("-h", "--help")
            return :help
        elseif startswith(argument, "--format=")
            format = split(argument, "="; limit=2)[2]
        elseif startswith(argument, "--color=")
            color = Symbol(split(argument, "="; limit=2)[2])
        elseif startswith(argument, "-")
            return "unknown option: $argument"
        elseif selected_suite !== nothing
            return "only one suite may be selected"
        else
            selected_suite = argument
        end
    end

    format in ("text", "json") || return "unsupported format: $format"
    color in (:auto, :always, :never) || return "unsupported color mode: $color"
    return (; selected_suite, format, color)
end

"""Select one requested suite or all available suites."""
function select_suites(selected_suite)
    suites = suite_definitions()
    selected_suite === nothing && return suites
    selected = filter(suite -> suite.name == selected_suite, suites)
    isempty(selected) && return nothing
    return selected
end

"""Execute a command, retaining combined output and elapsed time."""
function capture_command(command::Cmd)
    output = IOBuffer()
    started = time_ns()
    process = run(pipeline(ignorestatus(command), stdout=output, stderr=output))
    return (
        exit_code=process.exitcode,
        elapsed_ns=UInt64(time_ns() - started),
        output=String(take!(output)))
end

"""Run the Julia application test suite."""
function run_julia_suite(suite::SuiteDefinition)
    command = Cmd(Cmd([
        JULIA_EXE,
        "--project=" * JULIA_TEST_PROJECT,
        JULIA_TEST_RUNNER,
    ]); dir=REPOSITORY_ROOT)
    result = capture_command(command)
    status = result.exit_code == 0 ? "PASS" : "FAIL"
    return SuiteResult(
        suite.name, suite.language, reported_julia_count(result.output),
        result.elapsed_ns, status, result.output)
end

"""Run the Odin application test suite."""
function run_odin_suite(suite::SuiteDefinition)
    command = Cmd(Cmd(odin_test_command(native_linker_flags()));
        dir=REPOSITORY_ROOT)
    runtime_environment = native_runtime_environment()
    if runtime_environment !== nothing
        command = addenv(command, runtime_environment)
    end
    result = capture_command(command)
    test_count = reported_odin_count(result.output)
    status = odin_suite_status(result.exit_code, test_count)
    return SuiteResult(
        suite.name, suite.language, test_count,
        result.elapsed_ns, status, result.output)
end

"""Execute one suite through its language-specific runner."""
function run_suite(suite::SuiteDefinition)
    suite.language == "Julia" && return run_julia_suite(suite)
    return run_odin_suite(suite)
end

"""Return the Julia test count from runner output, when present."""
function reported_julia_count(output)
    count_match = match(
        r"EuclidApp Julia Tests\s*\|\s*(\d+)\s+(\d+)", output)
    count_match === nothing && return nothing
    return parse(Int, count_match[2])
end

"""Return the Odin test count from runner output, when present."""
function reported_odin_count(output)
    count_match = match(r"Finished (\d+) tests? in", output)
    return count_match === nothing ? nothing : parse(Int, count_match[1])
end

"""Return Odin suite status, requiring its terminal completion summary."""
function odin_suite_status(exit_code, test_count)
    return exit_code == 0 && test_count !== nothing ? "PASS" : "FAIL"
end

"""Return whether ANSI styling is enabled for test output."""
function color_enabled(io::IO, color::Symbol)
    color == :always && return true
    color == :never && return false
    return !haskey(ENV, "NO_COLOR") && get(io, :color, false)
end

"""Wrap test output text in an ANSI style when enabled."""
function styled(text::AbstractString, style::AbstractString, enabled::Bool)
    return enabled ? style * text * ANSI_RESET : text
end

"""Return the ANSI style for a test result status."""
function status_style(status::String)
    status == "PASS" && return ANSI_BOLD_GREEN
    status == "FAIL" && return ANSI_BOLD_RED
    return ANSI_YELLOW
end

"""Format a nanosecond duration for human-readable output."""
function format_duration(elapsed_ns::UInt64)
    elapsed_ms = elapsed_ns / 1_000_000
    elapsed_ms < 1 && return "<1 ms"
    elapsed_ms < 1_000 && return "$(round(Int, elapsed_ms)) ms"
    return "$(round(elapsed_ms / 1_000; digits=2)) s"
end

"""Convert test results into formatted table rows."""
function table_rows(results::Vector{SuiteResult})
    return [[
        result.name,
        result.language,
        something(result.tests, "?"),
        format_duration(result.elapsed_ns),
        result.status,
    ] for result in results]
end

"""Format one fixed-width test result table line."""
function table_line(values, widths)
    cells = (rpad(string(value), width) for (value, width) in zip(values, widths))
    return "| " * join(cells, " | ") * " |"
end

"""Write a formatted table of test suite results."""
function write_table(io::IO, results::Vector{SuiteResult}, use_color::Bool)
    headers = ["Suite", "Language", "Tests", "Time", "Status"]
    rows = table_rows(results)
    widths = [maximum(textwidth(string(row[column])) for row in vcat([headers], rows))
        for column in eachindex(headers)]
    separator = "+" * join((repeat("-", width + 2) for width in widths), "+") * "+"

    println(io, separator)
    println(io, table_line(headers, widths))
    println(io, separator)
    for (result, row) in zip(results, rows)
        prefix = table_line(row[1:end - 1], widths[1:end - 1])
        status = rpad(row[end], widths[end])
        styled_status = styled(status, status_style(result.status), use_color)
        println(io, prefix, " ", styled_status, " |")
    end
    println(io, separator)
end

"""Write human-readable test results and failure details."""
function write_text_report(io::IO, results::Vector{SuiteResult}, color::Symbol)
    use_color = color_enabled(io, color)
    println(io, styled("APPLICATION TESTS", ANSI_BOLD, use_color))
    println(io)
    write_table(io, results, use_color)

    failed = filter(result -> result.status != "PASS", results)
    for result in failed
        println(io)
        println(io, styled("FAILURE: $(result.name)", ANSI_BOLD_RED, use_color))
        print(io, result.output)
        endswith(result.output, '\n') || println(io)
    end

    known_tests = sum(something(result.tests, 0) for result in results)
    passed_suites = count(result -> result.status == "PASS", results)
    println(io)
    println(io, "Suites: $passed_suites/$(length(results)) passed")
    println(io, "Tests:  $known_tests reported")
    overall = isempty(failed) ? "PASS" : "FAIL"
    println(io, styled(overall, status_style(overall), use_color))
end

"""Escape a string for emission in JSON output."""
function json_escape(value::AbstractString)
    escaped = replace(
        value,
        '\\' => "\\\\",
        '"' => "\\\"",
        '\n' => "\\n",
        '\r' => "\\r",
        '\t' => "\\t")
    return "\"$escaped\""
end

"""Write the complete test result report as JSON."""
function write_json_report(io::IO, results::Vector{SuiteResult})
    passed = all(result -> result.status == "PASS", results)
    println(io, "{")
    println(io, "  \"schema_version\": \"1.0.0\",")
    println(io, "  \"passed\": ", passed, ",")
    println(io, "  \"suites\": [")
    for (index, result) in enumerate(results)
        tests = result.tests === nothing ? "null" : string(result.tests)
        comma = index == length(results) ? "" : ","
        println(io, "    {")
        println(io, "      \"name\": ", json_escape(result.name), ",")
        println(io, "      \"language\": ", json_escape(result.language), ",")
        println(io, "      \"tests\": ", tests, ",")
        println(io, "      \"elapsed_ns\": ", result.elapsed_ns, ",")
        println(io, "      \"status\": ", json_escape(lowercase(result.status)))
        println(io, "    }", comma)
    end
    println(io, "  ]")
    println(io, "}")
end

"""Run selected test suites and write the requested report format."""
function main(arguments::Vector{String})
    options = parse_options(arguments)
    if options === :help
        usage()
        return 0
    elseif options isa String
        println(stderr, "test_runner.jl: $options")
        return 2
    end

    suites = select_suites(options.selected_suite)
    if suites === nothing
        println(stderr, "test_runner.jl: unknown suite: $(options.selected_suite)")
        return 2
    end

    results = [run_suite(suite) for suite in suites]
    if options.format == "json"
        write_json_report(stdout, results)
    else
        write_text_report(stdout, results, options.color)
    end
    return all(result -> result.status == "PASS", results) ? 0 : 1
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(EuclidTestRunner.main(ARGS))
end
