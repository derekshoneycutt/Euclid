#!/usr/bin/env julia

module EuclidTestRunner

include("build_config.jl")
using .EuclidBuildConfiguration: native_linker_flags, native_runtime_environment
using Serialization

pushfirst!(LOAD_PATH, joinpath(@__DIR__, "analysis"))
using JSON3

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const JULIA_EXE = Base.julia_cmd().exec[1]
const JULIA_TEST_RUNNER = joinpath(
    REPOSITORY_ROOT, "src", "julia", "test", "runtests.jl")
const JULIA_TEST_REPORTER = joinpath(REPOSITORY_ROOT, "tools", "julia_test_reporter.jl")
const JULIA_TEST_PROJECT = joinpath(REPOSITORY_ROOT, "src", "julia")
const ODIN_SOURCE_ROOT = joinpath(REPOSITORY_ROOT, "src")
const ANSI_RESET = "\e[0m"
const ANSI_BOLD = "\e[1m"
const ANSI_BOLD_GREEN = "\e[1;32m"
const ANSI_BOLD_RED = "\e[1;31m"
const ANSI_YELLOW = "\e[33m"

struct SuiteDefinition
    name::String
    language::String
end

struct TestResult
    name::String
    language::String
    package::String
    file::String
    line::Int
    status::String
    elapsed_ns::Union{Nothing, UInt64}
    message::Union{Nothing, String}
end

struct TestLocation
    file::String
    line::Int
end

mutable struct RunnerOptions
    selected_suite::Union{Nothing,String}
    format::String
    color::Symbol
    selected_test::Union{Nothing,String}
    selected_package::Union{Nothing,String}
end

const RUNNER_OPTION_FIELDS = Dict(
    "--format" => :format,
    "--color" => :color,
    "--test" => :selected_test,
    "--package" => :selected_package)

struct SuiteResult
    name::String
    language::String
    tests::Union{Nothing, Int}
    elapsed_ns::UInt64
    status::String
    output::String
    records::Vector{TestResult}
end

"""Return all application test suite definitions."""
function suite_definitions()
    return [
        SuiteDefinition("julia", "Julia"),
        SuiteDefinition("odin", "Odin"),
    ]
end

"""Assemble the Odin test command with native linkage and reporting controls."""
function odin_test_command(linker_flags::String; source_path::String=ODIN_SOURCE_ROOT,
    report_path::String="", selected_test=nothing)
    odin_command = [
        "odin",
        "test",
        source_path,
        "-all-packages",
        "-define:ODIN_TEST_THREADS=1",
    ]
    !isempty(report_path) && push!(odin_command,
        "-define:ODIN_TEST_JSON_REPORT=$report_path")
    selected_test !== nothing && push!(odin_command,
        "-define:ODIN_TEST_NAMES=$selected_test")
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

"""Resolve a selected package beneath src without permitting traversal."""
function odin_source_path(selected_package)
    selected_package === nothing && return ODIN_SOURCE_ROOT
    isabspath(selected_package) && return nothing
    components = splitpath(normpath(selected_package))
    any(component -> component == "..", components) && return nothing
    path = normpath(joinpath(ODIN_SOURCE_ROOT, components...))
    return isdir(path) ? path : nothing
end

"""Discover Odin test procedure locations beneath one source path."""
function discover_odin_locations(source_path::String)
    locations = Dict{String,TestLocation}()
    for (directory, _, filenames) in walkdir(source_path)
        for filename in filter(name -> endswith(name, ".odin"), filenames)
            path = joinpath(directory, filename)
            content = read(path, String)
            package_match = match(
                r"(?m)^package\s+([A-Za-z_][A-Za-z0-9_]*)", content)
            package_match === nothing && continue
            package = package_match[1]
            pattern = Regex(
                raw"(?m)^\s*@\(test\)\s*\n\s*" *
                raw"([A-Za-z_][A-Za-z0-9_]*)\s*::\s*proc\b")
            for test_match in eachmatch(pattern, content)
                offset = test_match.offsets[1]
                prefix = SubString(content, 1, prevind(content, offset))
                line = count(==('\n'), prefix) + 1
                name = test_match[1]
                locations["$package.$name"] = TestLocation(
                    relpath(path, REPOSITORY_ROOT), line)
            end
        end
    end
    return locations
end

"""Apply one recognized named command-line option to mutable parser state."""
function apply_named_option!(options::RunnerOptions, argument::String)
    parts = split(argument, "="; limit=2)
    length(parts) == 2 || return false
    field = get(RUNNER_OPTION_FIELDS, parts[1], nothing)
    field === nothing && return false
    value = field == :color ? Symbol(parts[2]) : parts[2]
    setproperty!(options, field, value)
    return true
end

"""Return exact test names declared directly in one Odin package directory."""
function odin_package_test_names(source_path::String, locations)
    relative_directory = relpath(source_path, REPOSITORY_ROOT)
    return sort([name for (name, location) in locations
        if dirname(location.file) == relative_directory])
end

"""Resolve the exact Odin selection for a package and optional test name."""
function odin_selection(source_path::String, selected_package, selected_test,
    locations)
    selected_test !== nothing && return selected_test
    selected_package === nothing && return nothing
    names = odin_package_test_names(source_path, locations)
    return isempty(names) ? "" : join(names, ',')
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
    println(io, "  --test=NAME                Run one named Odin test")
    println(io, "  --package=PATH             Run one Odin package beneath src/")
    println(io, "  -h, --help                 Show this help")
    println(io)
    println(io, "Suites:")
    for suite in suite_definitions()
        println(io, "  $(suite.name)  $(suite.language) tests")
    end
end

"""Parse test-runner suite and output options."""
function parse_options(arguments::Vector{String})
    options = RunnerOptions(nothing, "text", :auto, nothing, nothing)

    for argument in arguments
        if argument in ("-h", "--help")
            return :help
        elseif apply_named_option!(options, argument)
            continue
        elseif startswith(argument, "-")
            return "unknown option: $argument"
        elseif options.selected_suite !== nothing
            return "only one suite may be selected"
        else
            options.selected_suite = argument
        end
    end

    options.format in ("text", "json") ||
        return "unsupported format: $(options.format)"
    options.color in (:auto, :always, :never) ||
        return "unsupported color mode: $(options.color)"
    options.selected_test == "" && return "test name must not be empty"
    options.selected_package == "" && return "package path must not be empty"
    return options
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

"""Convert serialized Julia reporter values into public test records."""
function julia_test_records(values)
    return [TestResult(
        value.name, "Julia", value.package, value.file, value.line,
        value.status, value.elapsed_ns, value.message) for value in values]
end

"""Run the Julia application test suite with structured leaf reporting."""
function run_julia_suite(suite::SuiteDefinition)
    return mktempdir() do directory
        report_path = joinpath(directory, "julia-tests.bin")
        command = Cmd(Cmd([
            JULIA_EXE,
            "--project=" * JULIA_TEST_PROJECT,
            JULIA_TEST_REPORTER,
        ]); dir=REPOSITORY_ROOT)
        result = capture_command(addenv(
            command, "EUCLID_JULIA_TEST_REPORT" => report_path))
        values = isfile(report_path) ? deserialize(report_path) : NamedTuple[]
        records = julia_test_records(values)
        status = result.exit_code == 0 && !isempty(records) ? "PASS" : "FAIL"
        return SuiteResult(suite.name, suite.language, length(records),
            result.elapsed_ns, status, result.output, records)
    end
end

"""Convert one Odin JSON report into source-located public test records."""
function odin_test_records(report, locations, output::String)
    records = TestResult[]
    for (package_value, tests) in pairs(report.packages)
        package = String(package_value)
        for test in tests
            name = "$package.$(test.name)"
            location = get(locations, name, TestLocation("", 0))
            status = test.success ? "passed" : "failed"
            message = test.success ? nothing : output
            push!(records, TestResult(name, "Odin", package, location.file,
                location.line, status, nothing, message))
        end
    end
    return records
end

"""Run the Odin suite with optional package and exact-name selection."""
function run_odin_suite(suite::SuiteDefinition; selected_package=nothing,
    selected_test=nothing)
    source_path = odin_source_path(selected_package)
    source_path === nothing && return SuiteResult(suite.name, suite.language,
        0, 0, "FAIL", "Invalid Odin package path: $selected_package\n", TestResult[])
    locations = discover_odin_locations(ODIN_SOURCE_ROOT)
    selection = odin_selection(
        source_path, selected_package, selected_test, locations)
    selection == "" && return SuiteResult(suite.name, suite.language, 0, 0,
        "FAIL", "No Odin tests declared in package: $selected_package\n", TestResult[])
    return mktempdir() do directory
        report_path = joinpath(directory, "odin-tests.json")
        arguments = odin_test_command(native_linker_flags(); source_path,
            report_path, selected_test=selection)
        command = Cmd(Cmd(arguments); dir=REPOSITORY_ROOT)
        runtime_environment = native_runtime_environment()
        runtime_environment !== nothing &&
            (command = addenv(command, runtime_environment))
        result = capture_command(command)
        report = isfile(report_path) ? JSON3.read(read(report_path, String)) : nothing
        records = report === nothing ? TestResult[] :
            odin_test_records(report, locations, result.output)
        status = odin_suite_status(result.exit_code,
            report === nothing ? nothing : length(records))
        return SuiteResult(suite.name, suite.language, length(records),
            result.elapsed_ns, status, result.output, records)
    end
end

"""Run the requested language suite with optional Odin selection."""
function run_suite(suite::SuiteDefinition; selected_package=nothing,
    selected_test=nothing)
    suite.language == "Julia" && return run_julia_suite(suite)
    return run_odin_suite(suite; selected_package, selected_test)
end

"""Return whether selection options are valid for one explicit Odin suite."""
function selection_valid(options)
    selection_requested = options.selected_test !== nothing ||
        options.selected_package !== nothing
    return !selection_requested || options.selected_suite == "odin"
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
    return exit_code == 0 && test_count !== nothing && test_count > 0 ?
        "PASS" : "FAIL"
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

"""Return one machine-readable suite summary."""
function suite_record(result::SuiteResult)
    return (
        name=result.name,
        language=result.language,
        tests=result.tests,
        elapsed_ns=result.elapsed_ns,
        status=lowercase(result.status))
end

"""Write per-test records and suite summaries as JSON."""
function write_json_report(io::IO, results::Vector{SuiteResult})
    passed = all(result -> result.status == "PASS", results)
    records = reduce(vcat, (result.records for result in results); init=TestResult[])
    JSON3.pretty(io, (
        schema_version="2.0.0",
        passed,
        tests=records,
        suites=suite_record.(results)))
    println(io)
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
    if !selection_valid(options)
        println(stderr, "test_runner.jl: --test and --package require the odin suite")
        return 2
    end

    results = [run_suite(suite;
        selected_package=options.selected_package,
        selected_test=options.selected_test) for suite in suites]
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
