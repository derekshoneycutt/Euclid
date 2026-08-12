#!/usr/bin/env julia

using Dates

struct CommandResult
    exit_code::Int
    stdout::String
    stderr::String
end

struct VetSectionResult
    key::String
    status::String
    summary::String
    command_status::String
    command_exit_code::Union{Nothing,Int}
    stdout::String
    stderr::String
    metrics::Dict{String,Any}
    blocking::Bool
    warning::Bool
    skipped::Bool
    missing::Bool
end

struct VetRunResult
    started_at::String
    sections::Vector{VetSectionResult}
    has_blocking_failures::Bool
end

mutable struct OdinProcRow
    file::String
    line::Int
    name::String
    nloc::Int
    ccn::Int
    params::Int
    returns::Int
    forgiven::Bool
    forgiven_params::Bool
    forgiven_returns::Bool
    severity::String
    status::String
end

struct OdinAllocRow
    file::String
    line::Int
    scope::String
    kind::String
    alloc_class::String
    status::String
    expr::String
end

struct ParserFileError
    file::String
    details::String
end

struct LineLengthIssue
    severity::String
    file::String
    line::Int
    code_length::Int
    line_length::Int
    has_explicit_exception::Bool
end

mutable struct LineScanState
    in_string::Bool
    string_delim::String
    in_block_comment::Bool
end

"""Per-file line inventory: physical lines split into code/comment/blank."""
struct FileLineTally
    path::String
    language::String
    lines::Int
    code::Int
    comment::Int
    blank::Int
    bytes::Int
end

"""Aggregate per-file tallies into a per-bucket total."""
mutable struct MetricsBucket
    files::Int
    lines::Int
    code::Int
    comment::Int
    blank::Int
    bytes::Int
    complexity::Int
end
MetricsBucket() = MetricsBucket(0, 0, 0, 0, 0, 0, 0)

"""LOCOMO-style LLM regeneration-cost model config (mirrors scc defaults)."""
struct LocomoConfig
    tokens_per_line::Float64
    input_per_line::Float64
    complexity_weight::Float64
    iterations::Float64
    iteration_weight::Float64
    input_price::Float64
    output_price::Float64
    tokens_per_second::Float64
    review_minutes::Float64
end

"""Default LOCOMO config matching scc's medium preset."""
locomo_default_config() = LocomoConfig(10.0, 20.0, 5.0, 1.5, 2.0, 3.0, 15.0, 50.0, 0.01)

"""Average annual wage (USD) and corporate overhead multiplier used for the
COCOMO dollar-cost estimate. Matches scc's defaults so the figure is comparable."""
const COCOMO_AVG_WAGE_USD = 56286
const COCOMO_OVERHEAD_MULTIPLIER = 2.4

const LINE_LENGTH_WARN_THRESHOLD = 90
const LINE_LENGTH_DISCOURAGED_THRESHOLD = 100
const LINE_LENGTH_HARD_LIMIT = 120

const LINE_LENGTH_EXCEPTION_PATTERNS = [
    r"line-length-exception"i,
    r"line_length_exception"i,
    r"vet:\s*allow-long-line"i,
    r"line-length:\s*allow"i,
]

const ODIN_ANALYZER_PACKAGE = joinpath("tools", "vet")
const ODIN_COMPLEXITY_BLOCK_THRESHOLD = 15
const ODIN_COMPLEXITY_WARN_THRESHOLD = 10
const ODIN_PARAM_BLOCK_THRESHOLD = 8
const ODIN_RETURN_BLOCK_THRESHOLD = 2
const ODIN_NLOC_REVIEW_THRESHOLD = 20
const ODIN_PARAM_REVIEW_THRESHOLD = 5

"""Return true when a section should surface detailed payload in markdown."""
function section_has_payload(section::VetSectionResult)
    return !isempty(strip(section.stdout)) || !isempty(strip(section.stderr))
end

"""Return overall report status based on section outcomes."""
function compute_overall_status(run_result::VetRunResult)
    if any(section -> section.status == "Fail", run_result.sections)
        return "Fail"
    end

    if any(section -> section.status == "Warn", run_result.sections)
        return "Warn"
    end

    if any(section -> section.status == "Pass", run_result.sections)
        return "Pass"
    end

    if any(section -> section.status == "Missing", run_result.sections)
        return "Missing"
    end

    return "Skipped"
end

"""Convert values to markdown-safe inline text."""
function markdown_inline(value)
    text = string(value)
    text = replace(text, '\n' => ' ')
    return replace(text, "|" => "\\|")
end

"""Append section metrics as markdown list items."""
function write_section_metrics(io::IO, metrics::Dict{String,Any})
    if isempty(metrics)
        write(io, "\n### Metrics\n\n- none\n")
        return
    end

    write(io, "\n### Metrics\n\n")
    for key in sort(collect(keys(metrics)))
        value = metrics[key]
        write(io, "- ", markdown_inline(key), ": ", markdown_inline(value), "\n")
    end
end

"""Append captured stdout and stderr blocks to a section in markdown."""
function write_section_payload(io::IO, section::VetSectionResult)
    stdout_text = strip(section.stdout)
    stderr_text = strip(section.stderr)

    if !isempty(stdout_text)
        write(io, "\n### Captured Stdout\n\n```text\n")
        write(io, stdout_text)
        write(io, "\n```\n")
    end

    if !isempty(stderr_text)
        write(io, "\n### Captured Stderr\n\n```text\n")
        write(io, stderr_text)
        write(io, "\n```\n")
    end
end

"""Write a markdown report to disk for all captured vet sections."""
function write_vet_report(
    run_result::VetRunResult, report_path::String, script_dir::String)
    mkpath(dirname(report_path))

    overall_status = compute_overall_status(run_result)
    command = join([PROGRAM_FILE; ARGS], " ")

    open(report_path, "w") do io
        write(io, "# Vet Report\n\n")
        write(io, "## Summary\n\n")
        write(io, "- Timestamp: ", run_result.started_at, "\n")
        write(io, "- Command: `", markdown_inline(command), "`\n")
        write(io, "- Report Path: `", relpath(report_path, script_dir), "`\n")
        write(io, "- Overall Status: ", overall_status, "\n")

        write(io, "\n## Section Status\n\n")
        write(io, "| Section | Status | Summary |\n")
        write(io, "| --- | --- | --- |\n")
        for section in run_result.sections
            write(
                io,
                "| ", markdown_inline(section.key),
                " | ", markdown_inline(section.status),
                " | ", markdown_inline(section.summary),
                " |\n")
        end

        for section in run_result.sections
            write(io, "\n## ", markdown_inline(section.key), "\n\n")
            write(io, "- Status: ", markdown_inline(section.status), "\n")
            write(io, "- Summary: ", markdown_inline(section.summary), "\n")
            write(io, "- Command Status: ", markdown_inline(section.command_status), "\n")

            if section.command_exit_code !== nothing
                write(io, "- Command Exit Code: ", string(section.command_exit_code), "\n")
            end

            write(io, "- Blocking: ", section.blocking ? "yes" : "no", "\n")
            write(io, "- Warning: ", section.warning ? "yes" : "no", "\n")
            write(io, "- Skipped: ", section.skipped ? "yes" : "no", "\n")
            write(io, "- Missing: ", section.missing ? "yes" : "no", "\n")

            write_section_metrics(io, section.metrics)
            if section_has_payload(section)
                write_section_payload(io, section)
            end
        end
    end
end

"""
Run a command and return its exit code and optional captured output.

When capture_output is false, stdout and stderr in the return value are empty strings.
"""
function run_command(
    command::Cmd; cwd::Union{Nothing,AbstractString}=nothing, capture_output::Bool=false)
    if capture_output
        stdout_buffer = IOBuffer()
        stderr_buffer = IOBuffer()
        exit_code = 0

        try
            if cwd === nothing
                run(pipeline(command; stdout=stdout_buffer, stderr=stderr_buffer))
            else
                cd(cwd) do
                    run(pipeline(command; stdout=stdout_buffer, stderr=stderr_buffer))
                end
            end
        catch
            exit_code = 1
        end

        return CommandResult(
            exit_code, String(take!(stdout_buffer)), String(take!(stderr_buffer)))
    end

    exit_code = 0
    try
        if cwd === nothing
            run(command)
        else
            cd(cwd) do
                run(command)
            end
        end
    catch
        exit_code = 1
    end

    return CommandResult(exit_code, "", "")
end

"""Capture stdout/stderr while running a function and return output plus result or error."""
function run_captured(f::Function)
    stdout_pipe = Pipe()
    stderr_pipe = Pipe()
    value = nothing
    caught_error = nothing

    stdout_task = @async read(stdout_pipe, String)
    stderr_task = @async read(stderr_pipe, String)

    redirect_stdio(stdout=stdout_pipe, stderr=stderr_pipe) do
        try
            value = f()
        catch err
            caught_error = err
            showerror(stderr, err)
            println(stderr)
        end
    end

    close(stdout_pipe.in)
    close(stderr_pipe.in)

    stdout_text = fetch(stdout_task)
    stderr_text = fetch(stderr_task)
    return value, stdout_text, stderr_text, caught_error
end

"""Collect all file paths recursively beneath a root directory."""
function collect_paths(root::String)
    paths = String[]
    for (dirpath, _, filenames) in walkdir(root)
        for filename in filenames
            push!(paths, joinpath(dirpath, filename))
        end
    end
    return paths
end

#   Julia static-analysis passes (syntax, parser metadata, return-shape,
#   CodeComplexity, JET) live in a dedicated module included into this scope.
include(joinpath(@__DIR__, "julia_static_analysis.jl"))

"""Limit detail payload for focused console output on failures and warnings."""
function truncate_console_details(text::AbstractString; max_lines::Int=24)
    lines = split(String(text), '\n')
    if length(lines) <= max_lines
        return text
    end

    kept = lines[1:max_lines]
    remaining = length(lines) - max_lines
    push!(kept, "... ($remaining more line(s) in captured output)")
    return join(kept, '\n')
end

"""Return true when path should be excluded from line-length checks."""
function should_skip_line_length_path(path::String)::Bool
    normalized = replace(normpath(path), '\\' => '/')

    if occursin("/tests/", normalized) || occursin("/test/", normalized)
        return true
    end

    if endswith(normalized, "_tests.odin") || endswith(normalized, "_test.jl") ||
        endswith(normalized, "_tests.jl")
        return true
    end

    if startswith(normalized, "src/julia/elements/") ||
        startswith(normalized, "src/julia/algebra/") ||
        startswith(normalized, "src/julia/hilbert/") ||
        startswith(normalized, "src/julia/proclus/") ||
        startswith(normalized, "src/julialib/")
        return true
    end

    return false
end

"""Return true when line contains an explicit long-line exception marker."""
function has_line_length_exception_marker(line::AbstractString)::Bool
    for pattern in LINE_LENGTH_EXCEPTION_PATTERNS
        if occursin(pattern, line)
            return true
        end
    end

    return false
end

"""Return true when substring starts at index and matches token."""
function starts_with_token(line::AbstractString, index::Int, token::String)::Bool
    if isempty(line) || index > lastindex(line)
        return false
    end

    return startswith(SubString(line, index), token)
end

"""Advance index by a number of characters, clamped to line end + 1."""
function advance_index_by_chars(line::AbstractString, index::Int, chars::Int)::Int
    advanced = index
    for _ in 1:chars
        if advanced > lastindex(line)
            return advanced
        end
        advanced = nextind(line, advanced)
    end

    return advanced
end

"""Advance one line and return its code-only length plus updated scanner state."""
function scan_line_code_length(
    line::AbstractString,
    state::LineScanState,
    line_comment_token::String,
    block_comment_start::String,
    block_comment_end::String,
    string_delims::Vector{String})
    code_length = 0
    index = 1
    line_end = lastindex(line)

    while index <= line_end
        if state.in_block_comment
            if starts_with_token(line, index, block_comment_end)
                state.in_block_comment = false
                index = advance_index_by_chars(line, index, length(block_comment_end))
            else
                index = nextind(line, index)
            end
            continue
        end

        if state.in_string
            if state.string_delim == "\""
                if starts_with_token(line, index, "\\")
                    index = advance_index_by_chars(line, index, 2)
                    continue
                end

                if starts_with_token(line, index, "\"")
                    state.in_string = false
                    state.string_delim = ""
                    index = nextind(line, index)
                    continue
                end
            elseif starts_with_token(line, index, state.string_delim)
                delim_len = length(state.string_delim)
                state.in_string = false
                state.string_delim = ""
                index = advance_index_by_chars(line, index, delim_len)
                continue
            end

            index = nextind(line, index)
            continue
        end

        if starts_with_token(line, index, line_comment_token)
            break
        end

        if starts_with_token(line, index, block_comment_start)
            state.in_block_comment = true
            index = advance_index_by_chars(line, index, length(block_comment_start))
            continue
        end

        matched_delim = ""
        for delim in string_delims
            if starts_with_token(line, index, delim)
                matched_delim = delim
                break
            end
        end

        if !isempty(matched_delim)
            state.in_string = true
            state.string_delim = matched_delim
            index = advance_index_by_chars(line, index, length(matched_delim))
            continue
        end

        code_length += 1
        index = nextind(line, index)
    end

    return code_length
end

"""Build line-length issues for a source file using language-specific token rules."""
function collect_file_line_length_issues(
    path::String, rel_path::String, extension::String)
    lines = split(read(path, String), '\n')
    issues = LineLengthIssue[]

    if extension == ".odin"
        state = LineScanState(false, "", false)
        for (line_number, line) in enumerate(lines)
            code_length = scan_line_code_length(
                line,
                state,
                "//",
                "/*",
                "*/",
                ["\"", "`"])

            line_length = length(line)
            if code_length <= LINE_LENGTH_WARN_THRESHOLD
                continue
            end

            has_exception = has_line_length_exception_marker(line)
            if code_length > LINE_LENGTH_HARD_LIMIT && !has_exception
                push!(issues, LineLengthIssue("BLOCK", rel_path, line_number,
                    code_length, line_length, false))
            elseif code_length >= LINE_LENGTH_DISCOURAGED_THRESHOLD
                push!(issues, LineLengthIssue("HARD_WARN", rel_path, line_number,
                    code_length, line_length, has_exception))
            else
                push!(issues, LineLengthIssue("WARN", rel_path, line_number,
                    code_length, line_length, has_exception))
            end
        end
    else
        state = LineScanState(false, "", false)
        for (line_number, line) in enumerate(lines)
            code_length = scan_line_code_length(
                line,
                state,
                "#",
                "#=",
                "=#",
                ["\"\"\"", "\"", "`"])

            line_length = length(line)
            if code_length <= LINE_LENGTH_WARN_THRESHOLD
                continue
            end

            has_exception = has_line_length_exception_marker(line)
            if code_length > LINE_LENGTH_HARD_LIMIT && !has_exception
                push!(issues, LineLengthIssue("BLOCK", rel_path, line_number,
                    code_length, line_length, false))
            elseif code_length >= LINE_LENGTH_DISCOURAGED_THRESHOLD
                push!(issues, LineLengthIssue("HARD_WARN", rel_path, line_number,
                    code_length, line_length, has_exception))
            else
                push!(issues, LineLengthIssue("WARN", rel_path, line_number,
                    code_length, line_length, has_exception))
            end
        end
    end

    return issues
end

"""Render line-length issues table for vet output."""
function render_line_length_issues(issues::Vector{LineLengthIssue})
    lines = String[]
    push!(lines, "Line-length table (.odin/.jl code-only chars):")
    push!(lines, "SEV       CODE  LINE  FILE:LINE  EXCEPTION")

    for issue in issues
        marker = issue.has_explicit_exception ? "yes" : "no"
        file_line = issue.file * ":" * string(issue.line)
        push!(
            lines,
            rpad(issue.severity, 9) * " " *
            lpad(string(issue.code_length), 5) * " " *
            lpad(string(issue.line_length), 5) * "  " *
            file_line * "  " * marker)
    end

    return join(lines, '\n')
end

"""Run line-length policy checks for Odin and Julia source files."""
function run_line_length_policy_section(script_dir::String)
    candidate_files = sort([
        path for path in collect_paths(script_dir)
        if endswith(path, ".odin") || endswith(path, ".jl")
    ])

    scanned_files = 0
    skipped_files = 0
    issues = LineLengthIssue[]

    for absolute_path in candidate_files
        rel_path = relpath(absolute_path, script_dir)
        if should_skip_line_length_path(rel_path)
            skipped_files += 1
            continue
        end

        extension = endswith(rel_path, ".odin") ? ".odin" : ".jl"
        append!(issues,
            collect_file_line_length_issues(absolute_path, rel_path, extension))
        scanned_files += 1
    end

    sort!(issues, by=issue -> (
        issue.severity == "BLOCK" ? 0 : (issue.severity == "HARD_WARN" ? 1 : 2),
        -issue.code_length,
        issue.file,
        issue.line))

    warn_count = count(issue -> issue.severity == "WARN", issues)
    hard_warn_count = count(issue -> issue.severity == "HARD_WARN", issues)
    block_count = count(issue -> issue.severity == "BLOCK", issues)
    exception_count = count(issue -> issue.has_explicit_exception, issues)

    if !isempty(issues)
        println(render_line_length_issues(issues))
    else
        println("Line-length table (.odin/.jl code-only chars): no issues")
    end

    return Dict{String,Any}(
        "warn_threshold" => LINE_LENGTH_WARN_THRESHOLD,
        "discouraged_threshold" => LINE_LENGTH_DISCOURAGED_THRESHOLD,
        "hard_limit" => LINE_LENGTH_HARD_LIMIT,
        "scanned_files" => scanned_files,
        "skipped_files" => skipped_files,
        "warn_count" => warn_count,
        "hard_warn_count" => hard_warn_count,
        "block_count" => block_count,
        "exception_count" => exception_count)
end

# --- repo-metrics: first-party replacement for the external scc tool ---

"""Classify one file's lines into code/comment/blank using the comment/string-
aware scanner shared with the line-length policy. A line is `code` when it has
at least one non-comment, non-string character; `comment` when it carries only
comment/string content; `blank` when it is empty after stripping whitespace."""
function tally_file_lines(path::String, rel_path::String, language::String)::FileLineTally
    content = read(path, String)
    lines = split(content, '\n')

    line_comment, block_start, block_end, string_delims =
        if language == "Odin"
            ("//", "/*", "*/", ["\"", "`"])
        else
            ("#", "#=", "=#", ["\"\"\"", "\"", "`"])
        end

    state = LineScanState(false, "", false)
    code = 0
    comment = 0
    blank = 0
    for line in lines
        code_length = scan_line_code_length(line, state, line_comment,
            block_start, block_end, string_delims)
        if code_length > 0
            code += 1
        elseif isempty(strip(line)) && !state.in_block_comment && !state.in_string
            blank += 1
        else
            comment += 1
        end
    end

    return FileLineTally(rel_path, language, length(lines), code, comment, blank,
        ncodeunits(content))
end

function add_file!(bucket::MetricsBucket, tally::FileLineTally)
    bucket.files += 1
    bucket.lines += tally.lines
    bucket.code += tally.code
    bucket.comment += tally.comment
    bucket.blank += tally.blank
    bucket.bytes += tally.bytes
    return bucket
end

"""Basic COCOMO (organic) effort/schedule/staff estimate from code lines.
Constants are the standard organic model; KLOC is code lines / 1000."""
function cocomo_organic(code_lines::Int)
    kloc = code_lines / 1000.0
    effort = 2.4 * kloc^1.05
    schedule = 2.5 * effort^0.38
    people = effort / schedule
    cost = effort * (COCOMO_AVG_WAGE_USD / 12.0) * COCOMO_OVERHEAD_MULTIPLIER
    return (effort=effort, schedule=schedule, people=people, cost=cost)
end

"""Estimate LLM regeneration cost for one file from its code lines and
parse-accurate complexity. Returns a named tuple of tokens/cost/cycles/time."""
function locomo_estimate(code_lines::Int, complexity::Int, config::LocomoConfig)
    code_lines <= 0 && return (output_tokens=0.0, input_tokens=0.0, cost=0.0,
        cycles=0.0, generation_seconds=0.0, review_minutes=0.0)

    density = complexity / code_lines
    input_factor = 1.0 + sqrt(density) * config.complexity_weight
    cycles = config.iterations + sqrt(density) * config.iteration_weight

    output_tokens = code_lines * config.tokens_per_line * cycles
    input_tokens = code_lines * config.input_per_line * input_factor * cycles
    cost = (input_tokens * config.input_price +
        output_tokens * config.output_price) / 1_000_000.0
    generation_seconds = config.tokens_per_second > 0 ?
        output_tokens / config.tokens_per_second : 0.0
    review_minutes = code_lines * config.review_minutes

    return (output_tokens=output_tokens, input_tokens=input_tokens, cost=cost,
        cycles=cycles, generation_seconds=generation_seconds,
        review_minutes=review_minutes)
end

"""Create a VetSectionResult from a captured Julia analysis section."""
function build_internal_section_result(
    key::String,
    ok_summary::String,
    fail_summary::String,
    metrics::Dict{String,Any},
    stdout_text::String,
    stderr_text::String,
    caught_error)
    if caught_error !== nothing
        return VetSectionResult(key, "Fail", fail_summary, "internal-error", nothing,
            stdout_text, stderr_text, metrics, true, false, false, false)
    end

    return VetSectionResult(key, "Pass", ok_summary, "ok", nothing, stdout_text,
        stderr_text, metrics, false, false, false, false)
end

"""Print concise section summaries, with details only for warnings or failures."""
function emit_console_summary(run_result::VetRunResult, report_path::String)
    println("Vet summary:")
    for section in run_result.sections
        println("  [" * section.status * "] " * section.key * " - " * section.summary)
    end

    println("Detailed vet report: " * report_path)

    for section in run_result.sections
        if section.status in ("Fail", "Warn")
            if section.key == "julia-codecomplexity" && section.status == "Warn"
                println("")
                println("Details for " * section.key * ":")
                println("  Warning-only complexity details are report-only. See " * report_path)
                continue
            end

            println("")
            println("Details for " * section.key * ":")

            stderr_details = strip(section.stderr)
            stdout_details = strip(section.stdout)
            details = stderr_details
            if !isempty(stderr_details) && !isempty(stdout_details)
                details = "stderr:\n" * stderr_details * "\n\nstdout:\n" * stdout_details
            elseif isempty(details)
                details = stdout_details
            end

            if isempty(details)
                println("  (no captured details)")
            elseif section.status == "Fail"
                println(details)
            else
                println(truncate_console_details(details; max_lines=120))
            end
        end
    end
end

"""Return true when external object has command-result-like fields."""
function is_command_result_like(value)
    return hasproperty(value, :exit_code) && hasproperty(value, :stdout) &&
        hasproperty(value, :stderr)
end

"""Build an odin-build-vet section from captured build output in make.jl."""
function run_odin_build_vet_section(odin_build_result)
    if odin_build_result === nothing
        return VetSectionResult("odin-build-vet", "Skipped",
            "Odin vet build output was not captured.", "skipped", nothing,
            "", "", Dict{String,Any}(), false, false, true, false)
    end

    if !is_command_result_like(odin_build_result)
        return VetSectionResult("odin-build-vet", "Warn",
            "Odin vet build capture had an unexpected shape.", "unexpected-result",
            nothing, "", "",
            Dict{String,Any}("result_type" => string(typeof(odin_build_result))),
            false, true, false, false)
    end

    exit_code = getproperty(odin_build_result, :exit_code)
    stdout_text = String(getproperty(odin_build_result, :stdout))
    stderr_text = String(getproperty(odin_build_result, :stderr))

    metrics = Dict{String,Any}(
        "exit_code" => exit_code,
        "stdout_bytes" => ncodeunits(stdout_text),
        "stderr_bytes" => ncodeunits(stderr_text))

    if exit_code != 0
        return VetSectionResult("odin-build-vet", "Fail", "Odin vet build failed.",
            "exit-nonzero", exit_code, stdout_text, stderr_text, metrics,
            true, false, false, false)
    end

    return VetSectionResult("odin-build-vet", "Pass", "Odin vet build passed.", "ok",
        exit_code, stdout_text, stderr_text, metrics, false, false, false, false)
end

"""Export Odin compiler dependency metadata and return structured section output."""
function run_odin_dependencies_section(src_dir::String, script_dir::String)
    if Sys.which("odin") === nothing
        return VetSectionResult("odin-dependencies", "Missing",
            "odin not found on PATH; skipping dependency export.",
            "missing", nothing, "", "",
            Dict{String,Any}(), false, false, true, true)
    end

    export_dir = mktempdir()
    export_file = joinpath(export_dir, "odin-dependencies.json")
    asm_out_file = joinpath(export_dir, "odin-dependencies-probe.s")

    try
        result = run_command(
            Cmd([
                "odin",
                "build",
                "main.odin",
                "-file",
                "-build-mode:asm",
                "-out:$asm_out_file",
                "-export-dependencies:json",
                "-export-dependencies-file:$export_file",
            ]);
            cwd=src_dir,
            capture_output=true)

        metrics = Dict{String,Any}(
            "exit_code" => result.exit_code,
            "export_path" => relpath(export_file, script_dir),
            "exported" => isfile(export_file))

        dependency_json = ""
        if isfile(export_file)
            dependency_json = read(export_file, String)
            metrics["dependency_json_bytes"] = ncodeunits(dependency_json)
        end

        stdout_text = join(filter(!isempty, [
            result.stdout,
            dependency_json,
        ]), "\n")

        if result.exit_code != 0
            return VetSectionResult("odin-dependencies", "Warn",
                "Odin dependency export failed.",
                "exit-nonzero", result.exit_code, stdout_text, result.stderr,
                metrics, false, true, false, false)
        end

        return VetSectionResult("odin-dependencies", "Pass",
            "Odin dependency export completed.",
            "ok", result.exit_code, stdout_text, result.stderr,
            metrics, false, false, false, false)
    finally
        if ispath(export_dir)
            rm(export_dir; force=true, recursive=true)
        end
    end
end

"""Run the Julia syntax validation section and return structured section output."""
function run_julia_syntax_section(src_dir::String, script_dir::String)
    value, stdout_text, stderr_text, caught_error = run_captured() do
        validate_all_julia_files(src_dir, script_dir)
    end

    metrics = value isa Dict{String,Any} ? value : Dict{String,Any}()
    return build_internal_section_result("julia-syntax",
        "Julia syntax validation passed.",
        "Julia syntax validation failed.",
        metrics, stdout_text, stderr_text, caught_error)
end

"""Run the line-length policy section and return structured section output."""
function run_line_length_section(script_dir::String)
    value, stdout_text, stderr_text, caught_error = run_captured() do
        run_line_length_policy_section(script_dir)
    end

    metrics = value isa Dict{String,Any} ? value : Dict{String,Any}()
    if caught_error !== nothing
        return build_internal_section_result("source-line-length",
            "Source line-length policy passed.",
            "Source line-length policy failed to execute.",
            metrics, stdout_text, stderr_text, caught_error)
    end

    block_count = get(metrics, "block_count", 0)
    hard_warn_count = get(metrics, "hard_warn_count", 0)
    warn_count = get(metrics, "warn_count", 0)

    if block_count > 0
        return VetSectionResult("source-line-length", "Fail",
            "Line-length policy found blocking violations above 120 without explicit exceptions.",
            "ok", nothing, stdout_text, stderr_text, metrics,
            true, false, false, false)
    end

    if hard_warn_count > 0 || warn_count > 0
        return VetSectionResult("source-line-length", "Warn",
            "Line-length policy found non-blocking warnings.",
            "ok", nothing, stdout_text, stderr_text, metrics,
            false, true, false, false)
    end

    return VetSectionResult("source-line-length", "Pass",
        "Line-length policy passed.",
        "ok", nothing, stdout_text, stderr_text, metrics,
        false, false, false, false)
end

"""Run the parser-backed Julia metadata section and return structured output."""
function run_julia_parser_metadata_section(src_dir::String, script_dir::String)
    value, stdout_text, stderr_text, caught_error = run_captured() do
        extract_julia_function_metadata(src_dir, script_dir)
    end

    metrics = value isa Dict{String,Any} ? value : Dict{String,Any}()
    if caught_error !== nothing
        return build_internal_section_result("julia-parser-metadata",
            "Julia parser metadata extraction passed.",
            "Julia parser metadata extraction failed.",
            metrics, stdout_text, stderr_text, caught_error)
    end

    parse_failure_count = get(metrics, "parse_failure_count", 0)
    if parse_failure_count > 0
        return VetSectionResult("julia-parser-metadata", "Warn",
            "Julia parser metadata extraction completed with partial parse failures.",
            "ok", nothing, stdout_text, stderr_text, metrics,
            false, true, false, false)
    end

    return VetSectionResult("julia-parser-metadata", "Pass",
        "Julia parser metadata extraction passed.",
        "ok", nothing, stdout_text, stderr_text, metrics,
        false, false, false, false)
end

"""Run the explicit Julia tuple-return section and return structured output."""
function run_julia_return_shape_section(src_dir::String, script_dir::String)
    value, stdout_text, stderr_text, caught_error = run_captured() do
        run_julia_return_shape_analysis(src_dir, script_dir)
    end

    metrics = value isa Dict{String,Any} ? value : Dict{String,Any}()
    if caught_error !== nothing
        return build_internal_section_result("julia-return-shape",
            "Julia return-shape analysis passed.",
            "Julia return-shape analysis failed to execute.",
            metrics, stdout_text, stderr_text, caught_error)
    end

    parse_failure_count = get(metrics, "parse_failure_count", 0)
    issue_count = get(metrics, "issue_count", 0)
    if parse_failure_count > 0
        return VetSectionResult("julia-return-shape", "Fail",
            "Julia return-shape analysis completed with parse failures.",
            "ok", nothing, stdout_text, stderr_text, metrics,
            true, false, false, false)
    end

    if issue_count > 0
        return VetSectionResult("julia-return-shape", "Fail",
            "Julia return-shape analysis found explicit tuple returns above arity 2.",
            "ok", nothing, stdout_text, stderr_text, metrics,
            true, false, false, false)
    end

    return VetSectionResult("julia-return-shape", "Pass",
        "Julia return-shape analysis passed.",
        "ok", nothing, stdout_text, stderr_text, metrics,
        false, false, false, false)
end

"""Run the Julia CodeComplexity section and return structured section output."""
function run_codecomplexity_section(src_dir::String, script_dir::String)
    value, stdout_text, stderr_text, caught_error = run_captured() do
        run_code_complexity_analysis(src_dir, script_dir)
    end

    metrics = value isa Dict{String,Any} ? value : Dict{String,Any}()

    if caught_error !== nothing
        return build_internal_section_result("julia-codecomplexity",
            "CodeComplexity passed.",
            "CodeComplexity analysis failed to execute.",
            metrics, stdout_text, stderr_text, caught_error)
    end

    blocking_found = get(metrics, "blocking_found", false)
    warning_count = get(metrics, "warning_count", 0)

    if blocking_found
        return VetSectionResult("julia-codecomplexity", "Fail",
            "CodeComplexity reported blocking violations.",
            "ok", nothing, stdout_text, stderr_text, metrics,
            true, false, false, false)
    end

    if warning_count > 0
        return VetSectionResult("julia-codecomplexity","Warn",
            "CodeComplexity produced warning-only violations.",
            "ok", nothing, stdout_text, stderr_text, metrics,
            false, true, false, false)
    end

    return VetSectionResult("julia-codecomplexity", "Pass",
        "CodeComplexity passed.",
        "ok", nothing, stdout_text, stderr_text, metrics,
        false, false, false, false)
end

"""Run the Julia JET section and return structured section output."""
function run_jet_section(src_dir::String, script_dir::String)
    value, stdout_text, stderr_text, caught_error = run_captured() do
        run_jet_analysis(src_dir, script_dir)
    end

    metrics = value isa Dict{String,Any} ? value : Dict{String,Any}()
    if caught_error !== nothing
        return build_internal_section_result("julia-jet",
            "JET analysis passed.",
            "JET analysis failed to execute.",
            metrics, stdout_text, stderr_text, caught_error)
    end

    failed = get(metrics, "failed", false)
    if failed
        return VetSectionResult("julia-jet", "Fail",
            "JET analysis reported actionable issues.",
            "ok", nothing, stdout_text, stderr_text, metrics,
            true, false, false, false)
    end

    return VetSectionResult("julia-jet", "Pass",
        "JET analysis passed.",
        "ok", nothing, stdout_text, stderr_text, metrics,
        false, false, false, false)
end

"""Return the path of the compiled Odin static analyzer binary."""
function odin_analyzer_path(script_dir::String)
    name = Sys.iswindows() ? "euclid_vet_analyzer.exe" : "euclid_vet_analyzer"
    return joinpath(script_dir, "bin", name)
end

"""Build the Odin static analyzer with the project vet flags."""
function build_odin_analyzer(script_dir::String)
    return run_command(
        Cmd([
            "odin", "build", ODIN_ANALYZER_PACKAGE,
            "-vet", "-strict-style", "-disallow-do", "-warnings-as-errors",
            "-out:" * odin_analyzer_path(script_dir),
        ]);
        cwd=script_dir, capture_output=true)
end

"""Parse analyzer TSV output into procedure rows, allocation rows, and failures."""
function parse_odin_analyzer_output(text::String)
    proc_rows = OdinProcRow[]
    alloc_rows = OdinAllocRow[]
    parse_failures = String[]

    for line in split(text, '\n')
        fields = split(line, '\t')
        tag = fields[1]
        if tag == "PROC" && length(fields) >= 11
            push!(proc_rows, OdinProcRow(
                String(fields[2]), Base.parse(Int, fields[3]), String(fields[4]),
                Base.parse(Int, fields[5]), Base.parse(Int, fields[6]),
                Base.parse(Int, fields[7]), Base.parse(Int, fields[8]),
                fields[9] == "true", fields[10] == "true", fields[11] == "true",
                "INFO", "PASS"))
        elseif tag == "PROC" && length(fields) >= 9
            push!(proc_rows, OdinProcRow(
                String(fields[2]), Base.parse(Int, fields[3]), String(fields[4]),
                Base.parse(Int, fields[5]), Base.parse(Int, fields[6]),
                Base.parse(Int, fields[7]), Base.parse(Int, fields[8]),
                fields[9] == "true", false, false, "INFO", "PASS"))
        elseif tag == "PROC" && length(fields) >= 8
            push!(proc_rows, OdinProcRow(
                String(fields[2]), Base.parse(Int, fields[3]), String(fields[4]),
                Base.parse(Int, fields[5]), Base.parse(Int, fields[6]),
                Base.parse(Int, fields[7]), 0,
                fields[8] == "true", false, false, "INFO", "PASS"))
        elseif tag == "ALLOC" && length(fields) >= 8
            push!(alloc_rows, OdinAllocRow(
                String(fields[2]), Base.parse(Int, fields[3]), String(fields[4]),
                String(fields[5]), String(fields[6]), String(fields[7]),
                String(join(fields[8:end], '\t'))))
        elseif tag == "PARSE_ERROR" && length(fields) >= 2
            push!(parse_failures, String(join(fields[2:end], '\t')))
        end
    end

    return proc_rows, alloc_rows, parse_failures
end

"""Classify Odin procedure rows against complexity policy (in-code markers only)."""
function classify_odin_proc_rows!(rows::Vector{OdinProcRow})
    blocking_count = 0
    warning_count = 0
    forgiven_count = 0
    param_blocking_count = 0
    return_blocking_count = 0

    for row in rows
        complexity_warning = row.ccn > ODIN_COMPLEXITY_WARN_THRESHOLD
        complexity_blocking = row.ccn >= ODIN_COMPLEXITY_BLOCK_THRESHOLD
        param_blocking = row.params > ODIN_PARAM_BLOCK_THRESHOLD && !row.forgiven_params
        return_blocking = row.returns > ODIN_RETURN_BLOCK_THRESHOLD &&
            !row.forgiven_returns
        has_forgiven_policy =
            (complexity_warning && row.forgiven) ||
            (row.params > ODIN_PARAM_BLOCK_THRESHOLD && row.forgiven_params) ||
            (row.returns > ODIN_RETURN_BLOCK_THRESHOLD && row.forgiven_returns)

        if complexity_warning && row.forgiven && !param_blocking && !return_blocking
            row.severity = "INFO"
            row.status = "FORGIVEN"
            forgiven_count += 1
        elseif complexity_blocking || param_blocking || return_blocking
            row.severity = "BLOCK"
            row.status = "FAIL"
            blocking_count += 1
            if param_blocking
                param_blocking_count += 1
            end
            if return_blocking
                return_blocking_count += 1
            end
        elseif complexity_warning
            row.severity = "WARN"
            row.status = "WARN"
            warning_count += 1
        elseif has_forgiven_policy
            row.severity = "INFO"
            row.status = "FORGIVEN"
            forgiven_count += 1
        end
    end

    sort!(rows, by=r -> (
        severity_rank(r.severity),
        -r.ccn,
        -r.nloc,
        r.name,
        r.file,
        r.line))

    return Dict{String,Any}(
        "blocking_count" => blocking_count,
        "warning_count" => warning_count,
        "forgiven_count" => forgiven_count,
        "param_blocking_count" => param_blocking_count,
        "return_blocking_count" => return_blocking_count)
end

"""Render the Odin static analysis table for report/console capture."""
function render_odin_static_table(rows::Vector{OdinProcRow})
    lines = String[]
    push!(lines, "Odin static analysis table:")
    push!(lines, "SEV  STATUS  NLOC  CCN  PARAM  RETURN  PROCEDURE  FILE:LINE")

    for row in rows
        file_line = "src/" * row.file * ":" * string(row.line)
        push!(lines,
            rpad(row.severity, 5) * " " *
            rpad(row.status, 13) * " " *
            lpad(string(row.nloc), 5) * " " *
            lpad(string(row.ccn), 4) * " " *
            lpad(string(row.params), 6) * "  " *
            lpad(string(row.returns), 6) * "  " *
            row.name * "  " *
            file_line)
    end

    return join(lines, '\n')
end

"""Aggregate Odin allocation statistics shared by the report and console."""
function odin_allocation_stats(alloc_rows::Vector{OdinAllocRow})
    kind_counts = Dict{String,Int}()
    class_counts = Dict{String,Int}()
    scope_set = Set{String}()
    file_set = Set{String}()
    block_count = 0
    warn_count = 0
    forgiven_count = 0

    for row in alloc_rows
        kind_counts[row.kind] = get(kind_counts, row.kind, 0) + 1
        class_counts[row.alloc_class] = get(class_counts, row.alloc_class, 0) + 1
        push!(scope_set, row.scope)
        push!(file_set, row.file)
        if row.status == "block"
            block_count += 1
        elseif row.status == "warn"
            warn_count += 1
        elseif row.status == "forgiven"
            forgiven_count += 1
        end
    end

    return kind_counts, class_counts, scope_set, file_set,
        block_count, warn_count, forgiven_count
end

"""Render the Odin allocation statistics block and site table for the report."""
function render_odin_allocations(alloc_rows::Vector{OdinAllocRow})
    kind_counts, class_counts, scope_set, file_set,
        block_count, warn_count, forgiven_count = odin_allocation_stats(alloc_rows)

    lines = String[]
    push!(lines, "Odin allocation statistics:")
    push!(lines, "  total allocation sites: $(length(alloc_rows))")
    push!(lines, "  procedures with allocations: $(length(scope_set))")
    push!(lines, "  files with allocations: $(length(file_set))")
    push!(lines, "  implicit-allocator blocks: $block_count")
    push!(lines, "  default-heap warnings: $warn_count")
    push!(lines, "  forgiven sites: $forgiven_count")
    push!(lines, "  sites by allocator class:")
    classes = sort(collect(keys(class_counts));
        by=c -> (-class_counts[c], c))
    for class in classes
        push!(lines, "    $class: $(class_counts[class])")
    end
    push!(lines, "  sites by kind:")
    kinds = sort(collect(keys(kind_counts)); by=k -> (-kind_counts[k], k))
    for kind in kinds
        push!(lines, "    $kind: $(kind_counts[kind])")
    end

    push!(lines, "")
    push!(lines, "Odin allocation sites:")
    push!(lines, "STATUS  CLASS  LINE  KIND  PROCEDURE  FILE  EXPRESSION")
    for row in alloc_rows
        push!(lines,
            rpad(row.status, 7) * " " *
            rpad(row.alloc_class, 8) * " " *
            lpad(string(row.line), 5) * "  " *
            row.kind * "  " * row.scope * "  " * "src/" * row.file * "  " *
            row.expr)
    end

    return join(lines, '\n')
end

"""Print the Odin allocation statistics that appear in every vet run."""
function print_odin_allocation_stats(alloc_rows::Vector{OdinAllocRow})
    kind_counts, class_counts, scope_set, file_set,
        block_count, warn_count, forgiven_count = odin_allocation_stats(alloc_rows)
    println("Odin allocation sites: $(length(alloc_rows)) across " *
        "$(length(scope_set)) procedures in $(length(file_set)) files.")
    classes = sort(collect(keys(class_counts));
        by=c -> (-class_counts[c], c))
    for class in classes
        println("  - allocator $class: $(class_counts[class])")
    end
    if block_count > 0
        println("  - BLOCK: $block_count site(s) allocate without an explicit allocator")
    end
    if warn_count > 0
        println("  - WARN: $warn_count site(s) allocate on the default heap allocator")
    end
    if forgiven_count > 0
        println("  - forgiven: $forgiven_count site(s) carry #vet forgiveness markers")
    end
end

"""Build one pair of failing Odin sections when the analyzer cannot run."""
function odin_analyzer_failure_sections(
    analysis_key::String, allocations_key::String, status::String,
    summary::String, command_status::String, exit_code,
    stdout_text::String, stderr_text::String, metrics::Dict{String,Any})
    blocking = status == "Fail"
    return VetSectionResult[
        VetSectionResult(analysis_key, status, summary, command_status,
            exit_code, stdout_text, stderr_text, metrics,
            blocking, false, status == "Skipped", status == "Missing"),
        VetSectionResult(allocations_key, status, summary, command_status,
            exit_code, "", stderr_text, copy(metrics),
            blocking, false, status == "Skipped", status == "Missing"),
    ]
end

"""Build and run the parser-based Odin static analysis and allocation sections."""
function run_odin_static_analysis_sections(src_dir::String, script_dir::String)
    analysis_key = "odin-static-analysis"
    allocations_key = "odin-allocations"

    if Sys.which("odin") === nothing
        return odin_analyzer_failure_sections(analysis_key, allocations_key,
            "Missing", "odin not found on PATH; skipping Odin static analysis.",
            "missing", nothing, "", "", Dict{String,Any}())
    end

    build_result = build_odin_analyzer(script_dir)
    if build_result.exit_code != 0
        return odin_analyzer_failure_sections(analysis_key, allocations_key,
            "Fail", "Odin static analyzer failed to build.", "exit-nonzero",
            build_result.exit_code, build_result.stdout, build_result.stderr,
            Dict{String,Any}("exit_code" => build_result.exit_code))
    end

    run_result = run_command(
        Cmd([odin_analyzer_path(script_dir), src_dir]);
        cwd=script_dir, capture_output=true)
    proc_rows, alloc_rows, parse_failures =
        parse_odin_analyzer_output(run_result.stdout)

    if run_result.exit_code != 0 && isempty(proc_rows) &&
        isempty(alloc_rows) && isempty(parse_failures)
        return odin_analyzer_failure_sections(analysis_key, allocations_key,
            "Fail", "Odin static analyzer run failed.", "exit-nonzero",
            run_result.exit_code, run_result.stdout, run_result.stderr,
            Dict{String,Any}("exit_code" => run_result.exit_code))
    end

    class_metrics = classify_odin_proc_rows!(proc_rows)
    odin_files = sort([
        path for path in collect_paths(src_dir) if endswith(path, ".odin")])
    analysis_metrics = merge(Dict{String,Any}(
        "files" => length(odin_files),
        "functions" => length(proc_rows),
        "parse_failure_count" => length(parse_failures),
        "over_nloc_review_count" =>
            count(r -> r.nloc > ODIN_NLOC_REVIEW_THRESHOLD, proc_rows),
        "over_param_block_count" =>
            count(r -> r.params > ODIN_PARAM_BLOCK_THRESHOLD, proc_rows),
        "over_return_block_count" =>
            count(r -> r.returns > ODIN_RETURN_BLOCK_THRESHOLD, proc_rows),
        "max_ccn" => isempty(proc_rows) ? 0 : maximum(r -> r.ccn, proc_rows),
        "exit_code" => run_result.exit_code), class_metrics)

    analysis_stdout = render_odin_static_table(proc_rows)
    if !isempty(parse_failures)
        analysis_stdout *= "\n\nParse failures:\n" * join(parse_failures, '\n')
    end

    blocking_count = class_metrics["blocking_count"]
    warning_count = class_metrics["warning_count"]
    analysis_section = if !isempty(parse_failures)
        VetSectionResult(analysis_key, "Fail",
            "Odin analyzer failed to parse $(length(parse_failures)) file(s).",
            "exit-nonzero", run_result.exit_code, analysis_stdout,
            run_result.stderr, analysis_metrics, true, false, false, false)
    elseif blocking_count > 0
        VetSectionResult(analysis_key, "Fail",
            "Odin static analysis reported $blocking_count blocking " *
            "policy violation(s) (complexity/params/returns).",
            "ok", run_result.exit_code, analysis_stdout, run_result.stderr,
            analysis_metrics, true, false, false, false)
    elseif warning_count > 0
        VetSectionResult(analysis_key, "Warn",
            "Odin static analysis reported $warning_count new complexity " *
            "warning(s); add an inline `#vet forgives(cyclomatic_complexity)` " *
            "exception or reduce the complexity.",
            "ok", run_result.exit_code, analysis_stdout, run_result.stderr,
            analysis_metrics, false, true, false, false)
    else
        VetSectionResult(analysis_key, "Pass",
            "Odin static analysis passed " *
            "($(class_metrics["forgiven_count"]) forgiven).",
            "ok", run_result.exit_code, analysis_stdout, run_result.stderr,
            analysis_metrics, false, false, false, false)
    end

    kind_counts, class_counts, scope_set, file_set,
        alloc_block_count, alloc_warn_count, alloc_forgiven_count =
        odin_allocation_stats(alloc_rows)
    alloc_metrics = Dict{String,Any}(
        "total_allocation_sites" => length(alloc_rows),
        "procedures_with_allocations" => length(scope_set),
        "files_with_allocations" => length(file_set),
        "implicit_allocator_blocks" => alloc_block_count,
        "heap_allocator_warnings" => alloc_warn_count,
        "forgiven_sites" => alloc_forgiven_count)
    for (kind, count) in kind_counts
        alloc_metrics["kind_" * replace(kind, '.' => '_')] = count
    end
    for (class, count) in class_counts
        alloc_metrics["class_" * class] = count
    end

    print_odin_allocation_stats(alloc_rows)
    alloc_summary = "Recorded $(length(alloc_rows)) Odin allocation site(s) across " *
        "$(length(scope_set)) procedures in $(length(file_set)) files."
    allocations_section = if alloc_block_count > 0
        VetSectionResult(allocations_key, "Fail",
            alloc_summary * " $alloc_block_count site(s) allocate without an " *
            "explicit allocator (add one, or a documented " *
            "`#vet forgives(implicit_allocator)` exception).",
            "ok", run_result.exit_code, render_odin_allocations(alloc_rows), "",
            alloc_metrics, true, false, false, false)
    elseif alloc_warn_count > 0
        VetSectionResult(allocations_key, "Warn",
            alloc_summary * " $alloc_warn_count site(s) allocate on the default " *
            "heap allocator (prefer context.temp_allocator or an owned arena, or " *
            "add a documented `#vet forgives(heap_allocator)` exception).",
            "ok", run_result.exit_code, render_odin_allocations(alloc_rows), "",
            alloc_metrics, false, true, false, false)
    else
        VetSectionResult(allocations_key, "Pass", alloc_summary,
            "ok", run_result.exit_code, render_odin_allocations(alloc_rows), "",
            alloc_metrics, false, false, false, false)
    end

    return VetSectionResult[analysis_section, allocations_section]
end

"""Return per-file total cyclomatic complexity for Odin sources by re-running
the already-built static analyzer and summing each file's procedure CCN."""
function collect_odin_file_complexity(src_dir::String, script_dir::String)
    complexity = Dict{String,Int}()
    analyzer = odin_analyzer_path(script_dir)
    if !isfile(analyzer)
        return complexity
    end

    result = run_command(Cmd([analyzer, src_dir]); cwd=script_dir, capture_output=true)
    for line in split(result.stdout, '\n')
        fields = split(line, '\t')
        if length(fields) >= 6 && fields[1] == "PROC"
            # The analyzer reports paths relative to src_dir; re-anchor them to
            # the script_dir-relative form used by the line tally.
            rel = joinpath(relpath(src_dir, script_dir), String(fields[2]))
            ccn = tryparse(Int, fields[6])
            if ccn !== nothing
                complexity[rel] = get(complexity, rel, 0) + ccn
            end
        end
    end
    return complexity
end

"""Return per-file total cyclomatic complexity for Julia sources from
CodeComplexity's parse-accurate per-function measures."""
function collect_julia_file_complexity(src_dir::String, script_dir::String)
    complexity = Dict{String,Int}()
    julia_root = joinpath(src_dir, "julia")
    metric = CodeComplexity.CyclomaticComplexity()
    for file_measure in CodeComplexity.measure_directory(metric, julia_root;
        recursive=true)
        rel = relpath(normpath(file_measure.path), script_dir)
        total = 0
        for fn in file_measure.functions
            total += Int(round(fn.value))
        end
        complexity[rel] = total
    end
    return complexity
end

"""Build the repo-metrics section: line inventory, parse-accurate complexity
rollups, COCOMO, and a LOCOMO LLM regeneration-cost estimate, all computed from
the project's own token streams rather than the external scc tool."""
function run_repo_metrics_section(src_dir::String, script_dir::String)
    candidate_files = sort([
        path for path in collect_paths(script_dir)
        if endswith(path, ".odin") || endswith(path, ".jl")])

    odin_complexity = collect_odin_file_complexity(src_dir, script_dir)
    julia_complexity = collect_julia_file_complexity(src_dir, script_dir)

    by_language = Dict{String,MetricsBucket}()
    by_dir = Dict{String,MetricsBucket}()
    total = MetricsBucket()
    total_complexity = 0
    locomo = (output_tokens=0.0, input_tokens=0.0, cost=0.0, cycles=0.0,
        generation_seconds=0.0, review_minutes=0.0)
    config = locomo_default_config()

    for absolute_path in candidate_files
        rel_path = relpath(absolute_path, script_dir)
        normalized = replace(rel_path, '\\' => '/')
        language = endswith(rel_path, ".odin") ? "Odin" : "Julia"
        tally = tally_file_lines(absolute_path, rel_path, language)

        file_complexity = language == "Odin" ?
            get(odin_complexity, rel_path, 0) :
            get(julia_complexity, rel_path, 0)
        total_complexity += file_complexity

        # Bucket by top-level directory; files at the repo root group under
        # "(root)" so they are not mistaken for directory names.
        top_dir = contains(normalized, '/') ? split(normalized, '/')[1] : "(root)"
        for bucket in (get!(by_language, language, MetricsBucket()),
            get!(by_dir, top_dir, MetricsBucket()), total)
            add_file!(bucket, tally)
            bucket.complexity += file_complexity
        end

        estimate = locomo_estimate(tally.code, file_complexity, config)
        locomo = merge(locomo, (
            output_tokens=locomo.output_tokens + estimate.output_tokens,
            input_tokens=locomo.input_tokens + estimate.input_tokens,
            cost=locomo.cost + estimate.cost,
            generation_seconds=locomo.generation_seconds +
                estimate.generation_seconds,
            review_minutes=locomo.review_minutes + estimate.review_minutes))
    end

    cocomo = cocomo_organic(total.code)
    avg_cycles = total.code > 0 ?
        (locomo.output_tokens / (total.code * config.tokens_per_line)) : 0.0

    metrics = Dict{String,Any}(
        "files" => total.files,
        "lines" => total.lines,
        "code" => total.code,
        "comment" => total.comment,
        "blank" => total.blank,
        "bytes" => total.bytes,
        "total_complexity" => total_complexity,
        "complexity_per_code_total" =>
            total.code == 0 ? 0.0 : round(total_complexity / total.code; digits=4),
        "complexity_per_code_odin" =>
            by_language["Odin"].code == 0 ? 0.0 :
                round(by_language["Odin"].complexity / by_language["Odin"].code;
                    digits=4),
        "complexity_per_code_julia" =>
            by_language["Julia"].code == 0 ? 0.0 :
                round(by_language["Julia"].complexity / by_language["Julia"].code;
                    digits=4),
        "cocomo_cost_usd" => round(cocomo.cost; digits=0),
        "cocomo_effort_months" => round(cocomo.effort; digits=2),
        "cocomo_schedule_months" => round(cocomo.schedule; digits=2),
        "cocomo_people" => round(cocomo.people; digits=2),
        "locomo_output_tokens" => round(locomo.output_tokens; digits=0),
        "locomo_input_tokens" => round(locomo.input_tokens; digits=0),
        "locomo_cost_usd" => round(locomo.cost; digits=2),
        "locomo_cycles" => round(avg_cycles; digits=2),
        "locomo_generation_hours" => round(locomo.generation_seconds / 3600; digits=2),
        "locomo_review_hours" => round(locomo.review_minutes / 60; digits=2))

    report_text = render_repo_metrics_report(by_language, by_dir, total,
        total_complexity, cocomo, locomo, avg_cycles)
    print(report_text)

    summary = "Computed $(total.files) files / $(total.code) code lines " *
        "across $(length(by_language)) languages (first-party metrics)."
    return VetSectionResult("repo-metrics", "Pass", summary, "ok", nothing,
        report_text, "", metrics, false, false, false, false)
end

"""Format a count with thousands separators for readable report tables."""
function format_count(value::Int)::String
    digits = string(abs(value))
    groups = String[]
    while length(digits) > 3
        pushfirst!(groups, digits[end - 2:end])
        digits = digits[1:end - 3]
    end
    pushfirst!(groups, digits)
    return (value < 0 ? "-" : "") * join(groups, ",")
end

"""Render one repo-metrics inventory table row."""
function render_metrics_row(label::String, bucket::MetricsBucket)::String
    return rpad(label, 12) * " " *
        lpad(format_count(bucket.files), 6) * " " *
        lpad(format_count(bucket.lines), 8) * " " *
        lpad(format_count(bucket.code), 8) * " " *
        lpad(format_count(bucket.comment), 9) * " " *
        lpad(format_count(bucket.blank), 7) * " " *
        lpad(format_count(bucket.complexity), 10)
end

"""Render the full repo-metrics report: per-language and per-directory inventory
tables plus COCOMO and LOCOMO estimate blocks."""
function render_repo_metrics_report(
    by_language::Dict{String,MetricsBucket},
    by_dir::Dict{String,MetricsBucket},
    total::MetricsBucket,
    total_complexity::Int,
    cocomo,
    locomo,
    avg_cycles::Float64)::String

    out = IOBuffer()
    header = rpad("Language", 12) * " " * lpad("Files", 6) * " " *
        lpad("Lines", 8) * " " * lpad("Code", 8) * " " * lpad("Comments", 9) *
        " " * lpad("Blanks", 7) * " " * lpad("Complexity", 10)
    divider = repeat("-", length(header))

    println(out, "Repository metrics (first-party; no external scc):")
    println(out, "")
    println(out, header)
    println(out, divider)
    for language in sort(collect(keys(by_language)))
        println(out, render_metrics_row(language, by_language[language]))
    end
    println(out, divider)
    println(out, render_metrics_row("Total", total))

    println(out, "")
    println(out, "By top-level directory:")
    println(out, header)
    println(out, divider)
    for dir in sort(collect(keys(by_dir)))
        println(out, render_metrics_row(dir, by_dir[dir]))
    end

    println(out, "")
    println(out, "Estimated Cost to Develop (organic COCOMO):  \$" *
        format_count(Int(round(cocomo.cost))))
    println(out, "Estimated Schedule Effort (organic):         " *
        string(round(cocomo.schedule; digits=2)) * " months")
    println(out, "Estimated People Required (organic):         " *
        string(round(cocomo.people; digits=2)))

    println(out, "")
    println(out, "LOCOMO LLM regeneration estimate (medium preset):")
    println(out, "  Tokens Required (in/out):  " *
        format_count(Int(round(locomo.input_tokens))) * " / " *
        format_count(Int(round(locomo.output_tokens))))
    println(out, "  Cost to Generate:          \$" *
        string(round(locomo.cost; digits=2)))
    println(out, "  Estimated Cycles:          " * string(round(avg_cycles; digits=2)))
    println(out, "  Generation Time (serial):  " *
        string(round(locomo.generation_seconds / 3600; digits=2)) * " hours")
    println(out, "  Human Review Time:         " *
        string(round(locomo.review_minutes / 60; digits=2)) * " hours")
    println(out, "  (Rough ballpark for regenerating code with an LLM; excludes " *
        "context reuse, tests, and debugging.)")

    println(out, "")
    println(out, "Processed " * format_count(total.bytes) * " bytes, " *
        string(round(total.bytes / 1_000_000; digits=3)) * " megabytes (SI)")

    return String(take!(out))
end

"""Run complete vet analysis for Julia checks and Odin lizard."""
function run_vet_analysis(script_dir::String, src_dir::String, odin_build_result=nothing)
    sections = VetSectionResult[]
    report_path = joinpath(script_dir, "bin", "vet-report.md")

    println("Recording Odin vet build output...")
    push!(sections, run_odin_build_vet_section(odin_build_result))

    println("Exporting Odin compiler dependencies...")
    push!(sections, run_odin_dependencies_section(src_dir, script_dir))

    println("Running Julia syntax validation...")
    push!(sections, run_julia_syntax_section(src_dir, script_dir))

    println("Running source line-length policy...")
    push!(sections, run_line_length_section(script_dir))

    println("Running Julia parser metadata extraction...")
    push!(sections, run_julia_parser_metadata_section(src_dir, script_dir))

    println("Running Julia return-shape analysis...")
    push!(sections, run_julia_return_shape_section(src_dir, script_dir))

    println("Running CodeComplexity analysis...")
    push!(sections, run_codecomplexity_section(src_dir, script_dir))

    println("Running JET static analysis...")
    push!(sections, run_jet_section(src_dir, script_dir))

    println("Running Odin static analysis (parser-based)...")
    append!(sections, run_odin_static_analysis_sections(src_dir, script_dir))

    println("Running repo-metrics (first-party statistics)...")
    push!(sections, run_repo_metrics_section(src_dir, script_dir))

    has_blocking_failures = any(section -> section.blocking, sections)
    run_result =
        VetRunResult(string(Dates.now(Dates.UTC)), sections, has_blocking_failures)

    try
        write_vet_report(run_result, report_path, script_dir)
    catch err
        details = sprint(showerror, err)
        error("Failed to write vet report at $(relpath(report_path, script_dir)): $details")
    end

    emit_console_summary(run_result, relpath(report_path, script_dir))

    if has_blocking_failures
        error("Vet analysis reported blocking issues.")
    end

    return run_result
end

"""Standalone entrypoint that runs vet using this script's repository paths."""
function main()
    # The script lives in tools/; the repository root is its parent directory.
    script_dir = abspath(joinpath(@__DIR__, ".."))
    src_dir = joinpath(script_dir, "src")

    run_vet_analysis(script_dir, src_dir, nothing)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end

