#!/usr/bin/env julia

using Dates
using JET
using CodeComplexity

const JET_METHOD_ERROR_WHITELIST_PATTERNS = [
    r"`iterate\(::Nothing\)`",
    r"`iterate\(::Nothing, ::Int64\)`",
    r"`ncodeunits\(::Nothing\)`",
    r"`parse_hex\(::Nothing\)`",
    r"`parse_f32\(::Nothing\)`",
    r"`-\(::Vector\{Float32\}, ::Nothing\)`",
    r"`\+\(::Nothing, ::Vector\{Float32\}\)`",
]

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

"""
Run a command and return its exit code and optional captured output.

When capture_output is false, stdout and stderr in the return value are empty strings.
"""
function run_command(command::Cmd; cwd::Union{Nothing,AbstractString}=nothing, capture_output::Bool=false)
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

        return CommandResult(exit_code, String(take!(stdout_buffer)), String(take!(stderr_buffer)))
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

    stdout_text = read(stdout_pipe, String)
    stderr_text = read(stderr_pipe, String)
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

"""Parse every Julia source file in src/julia and fail on syntax errors."""
function validate_all_julia_files(src_dir::String, script_dir::String)
    julia_root = joinpath(src_dir, "julia")
    julia_files = sort([path for path in collect_paths(julia_root) if endswith(path, ".jl")])

    if isempty(julia_files)
        println("Warning: no Julia files found for syntax validation.")
        return
    end

    for file_path in julia_files
        try
            Meta.parseall(read(file_path, String))
        catch err
            rel = relpath(file_path, script_dir)
            details = sprint(showerror, err)
            error("Julia syntax validation failed for $rel: $details")
        end
    end

    println("Julia syntax validation passed for $(length(julia_files)) files.")
    return Dict{String,Any}(
        "files" => length(julia_files),
    )
end

"""Run JET static analysis over Julia source files in src/julia."""
function jet_report_location(report, script_dir::String)::String
    project_root = normpath(script_dir)

    for frame in report.vst
        frame_file = String(frame.file)
        normalized = normpath(frame_file)

        if startswith(normalized, project_root)
            return relpath(normalized, script_dir) * ":" * string(frame.line)
        end

        if startswith(frame_file, "src/")
            return frame_file * ":" * string(frame.line)
        end
    end

    return "unknown"
end

"""Return a single-line, truncated message for a JET report."""
function jet_report_message(report; max_len::Int=180)::String
    message = sprint(show, report)
    message = replace(message, '\n' => ' ')
    message = replace(message, r"\s+" => " ")
    message = strip(message)

    if length(message) <= max_len
        return message
    end

    return message[1:max_len-3] * "..."
end

"""Return true when a JET report is considered known-noise and safe to ignore."""
function is_whitelisted_jet_report(report_type::String, message::String)
    if report_type == "UndefVarErrorReport" && occursin("Base.active_repl", message)
        return true
    end

    if report_type == "MethodErrorReport"
        for pattern in JET_METHOD_ERROR_WHITELIST_PATTERNS
            if occursin(pattern, message)
                return true
            end
        end
    end

    return false
end

"""Run JET static analysis and fail on actionable reports."""
function run_jet_analysis(src_dir::String, script_dir::String)
    julia_root = joinpath(src_dir, "julia")
    julia_files = String[joinpath(julia_root, "script.jl")]
    if !isfile(julia_files[1])
        error("JET target file not found: $(julia_files[1])")
    end

    failed = false
    report_count = 0
    actionable_count = 0
    whitelisted_count_total = 0
    max_reports_per_file = 8

    for path in julia_files
        println("JET analyzing " * relpath(path, julia_root))
        result = JET.report_file(path)
        reports = JET.get_reports(result)

        actionable = Tuple{String,String,String}[]
        whitelisted_count = 0
        for report in reports
            report_type = string(nameof(typeof(report)))
            location = jet_report_location(report, script_dir)
            message = jet_report_message(report)
            if is_whitelisted_jet_report(report_type, message)
                whitelisted_count += 1
            else
                push!(actionable, (report_type, location, message))
            end
        end

        report_count += length(reports)
        actionable_count += length(actionable)
        whitelisted_count_total += whitelisted_count

        if !isempty(reports)
            display_path = relpath(path, script_dir)
            println("JET findings in $display_path: $(length(reports))")

            if whitelisted_count > 0
                println("  - whitelisted: $whitelisted_count")
            end

            if isempty(actionable)
                println("  - actionable: 0")
                continue
            end

            failed = true
            println("  - actionable: $(length(actionable))")

            show_count = min(length(actionable), max_reports_per_file)
            for i in 1:show_count
                report_type, location, message = actionable[i]
                println("  - [$report_type] $location | $message")
            end

            if length(actionable) > max_reports_per_file
                remaining = length(actionable) - max_reports_per_file
                println("  - ... and $remaining more report(s)")
            end
        end
    end

    return Dict{String,Any}(
        "reports" => report_count,
        "actionable" => actionable_count,
        "whitelisted" => whitelisted_count_total,
        "failed" => failed)
end

"""Return true when a path is configured as warning-only for complexity checks."""
function is_warning_only_complexity_path(path::String, warning_roots::Vector{String})
    candidate = normpath(path)
    for warning_root in warning_roots
        if startswith(candidate, warning_root)
            return true
        end
    end
    return false
end

"""Run CodeComplexity analysis over Julia source files and fail on blocking violations."""
function run_code_complexity_analysis(src_dir::String)
    julia_root = joinpath(src_dir, "julia")

    max_complexity = 10
    warning_roots = [
        normpath(joinpath(julia_root, "elements")),
        normpath(joinpath(julia_root, "hilbert")),
        normpath(joinpath(julia_root, "proclus")),
    ]

    metric = CodeComplexity.CyclomaticComplexity()
    violations = CodeComplexity.measure_directory(metric, julia_root;
        recursive=true,
        max_value=max_complexity)

    if isempty(violations)
        println("CodeComplexity passed (cyclomatic <= $max_complexity for all functions).")
        return Dict{String,Any}(
            "max_complexity" => max_complexity,
            "violation_files" => 0,
            "warning_count" => 0,
            "warning_loop_count" => 0,
            "blocking_found" => false)
    end

    println("CodeComplexity violations found: $(length(violations))")
    blocking_found = false
    warning_count = 0
    warning_loop_count = 0

    for file_measure in violations
        warning_only = is_warning_only_complexity_path(file_measure.path, warning_roots)
        if warning_only
            warning_count += length(file_measure.functions)
            non_loop_functions = [fn for fn in file_measure.functions if fn.name != "loop"]
            warning_loop_count += length(file_measure.functions) - length(non_loop_functions)

            if isempty(non_loop_functions)
                continue
            end

            println("  [warning-only] " * file_measure.path)
            for fn in non_loop_functions
                println(
                    "    - " * fn.name *
                    " (cyclomatic=" * string(fn.value) *
                    ", line=" * string(fn.line) * ")")
            end
        else
            blocking_found = true
            println("  [blocking] " * file_measure.path)
            for fn in file_measure.functions
                println(
                    "    - " * fn.name *
                    " (cyclomatic=" * string(fn.value) *
                    ", line=" * string(fn.line) * ")")
            end
        end
    end

    if warning_count > 0
        println("CodeComplexity warning-only violations: $warning_count")
    end

    if warning_loop_count > 0
        println("CodeComplexity warning-only: $warning_loop_count loop functions flagged")
    end

    if !blocking_found
        println("CodeComplexity violations are warning-only for configured directories.")
    end

    return Dict{String,Any}(
        "max_complexity" => max_complexity,
        "violation_files" => length(violations),
        "warning_count" => warning_count,
        "warning_loop_count" => warning_loop_count,
        "blocking_found" => blocking_found)
end

"""Parse scc --by-file -pw aggregate rows for Julia, Odin, and Total."""
function parse_scc_primary_rows(output::String)
    rows = Dict{String,Tuple{Int,Int}}()

    for raw_line in split(output, '\n')
        line = strip(raw_line)
        if isempty(line)
            continue
        end

        fields = split(line)
        if length(fields) < 7
            continue
        end

        language = fields[1]
        if !(language in ("Odin", "Julia", "Total"))
            continue
        end

        try
            code = parse(Int, fields[6])
            complexity = parse(Int, fields[7])
            rows[language] = (code, complexity)
        catch
            continue
        end
    end

    return rows
end

"""Print derived `Complexity/Code` metrics from scc output."""
function print_scc_complexity_per_file_summary(output::String)
    rows = parse_scc_primary_rows(output)
    labels = ["Odin", "Julia", "Total"]
    printed_any = false

    for label in labels
        if !haskey(rows, label)
            continue
        end

        code, complexity = rows[label]
        complexity_per_code = code == 0 ? 0.0 : complexity / code
        rounded = round(complexity_per_code; digits=4)
        println("scc derived ($label): Complexity/Code = $rounded")
        printed_any = true
    end

    if !printed_any
        println("Warning: Could not parse scc summary rows for Odin/Julia/Total.")
    end

    return Dict{String,Any}(
        "parsed_rows" => length(rows))
end

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
        return VetSectionResult(
            key,
            "Fail",
            fail_summary,
            "internal-error",
            nothing,
            stdout_text,
            stderr_text,
            metrics,
            true,
            false,
            false,
            false)
    end

    return VetSectionResult(
        key,
        "Pass",
        ok_summary,
        "ok",
        nothing,
        stdout_text,
        stderr_text,
        metrics,
        false,
        false,
        false,
        false)
end

"""Print concise section summaries, with details only for warnings or failures."""
function emit_console_summary(run_result::VetRunResult)
    println("Vet summary:")
    for section in run_result.sections
        println("  [" * section.status * "] " * section.key * " - " * section.summary)
    end

    for section in run_result.sections
        if section.status in ("Fail", "Warn")
            println("")
            println("Details for " * section.key * ":")

            details = strip(section.stderr)
            if isempty(details)
                details = strip(section.stdout)
            end

            if isempty(details)
                println("  (no captured details)")
            else
                println(truncate_console_details(details))
            end
        end
    end
end

"""Run the Julia syntax validation section and return structured section output."""
function run_julia_syntax_section(src_dir::String, script_dir::String)
    value, stdout_text, stderr_text, caught_error = run_captured() do
        validate_all_julia_files(src_dir, script_dir)
    end

    metrics = value isa Dict{String,Any} ? value : Dict{String,Any}()
    return build_internal_section_result(
        "julia-syntax",
        "Julia syntax validation passed.",
        "Julia syntax validation failed.",
        metrics,
        stdout_text,
        stderr_text,
        caught_error)
end

"""Run the Julia CodeComplexity section and return structured section output."""
function run_codecomplexity_section(src_dir::String)
    value, stdout_text, stderr_text, caught_error = run_captured() do
        run_code_complexity_analysis(src_dir)
    end

    metrics = value isa Dict{String,Any} ? value : Dict{String,Any}()

    if caught_error !== nothing
        return build_internal_section_result(
            "julia-codecomplexity",
            "CodeComplexity passed.",
            "CodeComplexity analysis failed to execute.",
            metrics,
            stdout_text,
            stderr_text,
            caught_error)
    end

    blocking_found = get(metrics, "blocking_found", false)
    warning_count = get(metrics, "warning_count", 0)

    if blocking_found
        return VetSectionResult(
            "julia-codecomplexity",
            "Fail",
            "CodeComplexity reported blocking violations.",
            "ok",
            nothing,
            stdout_text,
            stderr_text,
            metrics,
            true,
            false,
            false,
            false)
    end

    if warning_count > 0
        return VetSectionResult(
            "julia-codecomplexity",
            "Warn",
            "CodeComplexity produced warning-only violations.",
            "ok",
            nothing,
            stdout_text,
            stderr_text,
            metrics,
            false,
            true,
            false,
            false)
    end

    return VetSectionResult(
        "julia-codecomplexity",
        "Pass",
        "CodeComplexity passed.",
        "ok",
        nothing,
        stdout_text,
        stderr_text,
        metrics,
        false,
        false,
        false,
        false)
end

"""Run the Julia JET section and return structured section output."""
function run_jet_section(src_dir::String, script_dir::String)
    value, stdout_text, stderr_text, caught_error = run_captured() do
        run_jet_analysis(src_dir, script_dir)
    end

    metrics = value isa Dict{String,Any} ? value : Dict{String,Any}()
    if caught_error !== nothing
        return build_internal_section_result(
            "julia-jet",
            "JET analysis passed.",
            "JET analysis failed to execute.",
            metrics,
            stdout_text,
            stderr_text,
            caught_error)
    end

    failed = get(metrics, "failed", false)
    if failed
        return VetSectionResult(
            "julia-jet",
            "Fail",
            "JET analysis reported actionable issues.",
            "ok",
            nothing,
            stdout_text,
            stderr_text,
            metrics,
            true,
            false,
            false,
            false)
    end

    return VetSectionResult(
        "julia-jet",
        "Pass",
        "JET analysis passed.",
        "ok",
        nothing,
        stdout_text,
        stderr_text,
        metrics,
        false,
        false,
        false,
        false)
end

"""Run Odin lizard once with capture and return structured section output."""
function run_odin_lizard_section(src_dir::String, script_dir::String)
    if Sys.which("lizard") === nothing
        return VetSectionResult(
            "odin-lizard",
            "Missing",
            "lizard not installed; skipping Odin lizard analysis.",
            "missing",
            nothing,
            "",
            "",
            Dict{String,Any}(),
            false,
            false,
            true,
            true)
    end

    odin_files = sort([path for path in collect_paths(src_dir) if endswith(path, ".odin")])
    if isempty(odin_files)
        return VetSectionResult(
            "odin-lizard",
            "Skipped",
            "No Odin files discovered; skipping lizard analysis.",
            "skipped",
            nothing,
            "",
            "",
            Dict{String,Any}("files" => 0),
            false,
            false,
            true,
            false)
    end

    result = run_command(
        Cmd(vcat(["lizard", "-l", "cpp"], odin_files));
        cwd=script_dir,
        capture_output=true)

    metrics = Dict{String,Any}(
        "files" => length(odin_files),
        "exit_code" => result.exit_code)

    if result.exit_code != 0
        return VetSectionResult(
            "odin-lizard",
            "Fail",
            "Lizard odin analysis reported warnings.",
            "exit-nonzero",
            result.exit_code,
            result.stdout,
            result.stderr,
            metrics,
            true,
            false,
            false,
            false)
    end

    return VetSectionResult(
        "odin-lizard",
        "Pass",
        "Lizard odin analysis passed.",
        "ok",
        result.exit_code,
        result.stdout,
        result.stderr,
        metrics,
        false,
        false,
        false,
        false)
end

"""Run scc once with capture and return structured section output."""
function run_repo_scc_section(script_dir::String)
    if Sys.which("scc") === nothing
        return VetSectionResult(
            "repo-scc",
            "Missing",
            "scc not found on PATH; skipping scc analysis.",
            "missing",
            nothing,
            "",
            "",
            Dict{String,Any}(),
            false,
            false,
            true,
            true)
    end

    result = run_command(Cmd(["scc", "--by-file", "-pw"]); cwd=script_dir, capture_output=true)
    if result.exit_code != 0
        return VetSectionResult(
            "repo-scc",
            "Warn",
            "scc analysis failed.",
            "exit-nonzero",
            result.exit_code,
            result.stdout,
            result.stderr,
            Dict{String,Any}("exit_code" => result.exit_code),
            false,
            true,
            false,
            false)
    end

    summary_metrics = print_scc_complexity_per_file_summary(result.stdout)
    metrics = Dict{String,Any}(
        "exit_code" => result.exit_code,
        "parsed_rows" => get(summary_metrics, "parsed_rows", 0))

    return VetSectionResult(
        "repo-scc",
        "Pass",
        "scc analysis completed.",
        "ok",
        result.exit_code,
        result.stdout,
        result.stderr,
        metrics,
        false,
        false,
        false,
        false)
end

"""Run complete vet analysis for Julia checks and Odin lizard."""
function run_vet_analysis(script_dir::String, src_dir::String)
    sections = VetSectionResult[]

    println("Running Julia syntax validation...")
    push!(sections, run_julia_syntax_section(src_dir, script_dir))

    println("Running CodeComplexity analysis...")
    push!(sections, run_codecomplexity_section(src_dir))

    println("Running JET static analysis...")
    push!(sections, run_jet_section(src_dir, script_dir))

    println("Running lizard analysis (odin)...")
    push!(sections, run_odin_lizard_section(src_dir, script_dir))

    println("Running scc statistics (scc --by-file -pw)...")
    push!(sections, run_repo_scc_section(script_dir))

    has_blocking_failures = any(section -> section.blocking, sections)
    run_result = VetRunResult(string(Dates.now(Dates.UTC)), sections, has_blocking_failures)

    emit_console_summary(run_result)

    if has_blocking_failures
        error("Vet analysis reported blocking issues.")
    end

    return run_result
end

"""Standalone entrypoint that runs vet using this script's repository paths."""
function main()
    script_dir = abspath(@__DIR__)
    src_dir = joinpath(script_dir, "src")

    run_vet_analysis(script_dir, src_dir)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end

