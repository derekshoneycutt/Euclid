#!/usr/bin/env julia

using Dates
using JET
using CodeComplexity
using JuliaSyntax

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

struct JuliaFunctionMetadata
    name::String
    file::String
    start_line::Int
    end_line::Int
    nloc::Int
    param_count::Int
    signature_preview::String
end

struct JuliaComplexityRow
    severity::String
    status::String
    nloc::Int
    ccn::Int
    param_count::Int
    function_name::String
    file::String
    line::Int
end

struct ParserFileError
    file::String
    details::String
end

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
function write_vet_report(run_result::VetRunResult, report_path::String, script_dir::String)
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
            JuliaSyntax.parseall(Expr, read(file_path, String))
        catch err
            rel = relpath(file_path, script_dir)
            details = sprint(showerror, err)
            error("Julia syntax validation failed for $rel: $details")
        end
    end

    println("Julia syntax validation passed for $(length(julia_files)) files.")
    return Dict{String,Any}(
        "files" => length(julia_files))
end

"""Return first callable expression in a signature, unwrapping where clauses."""
function unwrap_signature_callable(signature)
    if signature isa Expr && signature.head == :where && !isempty(signature.args)
        return unwrap_signature_callable(signature.args[1])
    end
    return signature
end

"""Return a readable function name from a callable expression."""
function callable_name(callable)
    if callable isa Symbol
        return string(callable)
    end

    if callable isa Expr
        if callable.head == :curly && !isempty(callable.args)
            return callable_name(callable.args[1])
        end

        if callable.head == :. && length(callable.args) == 2
            return callable_name(callable.args[2])
        end

        return string(callable)
    end

    return string(callable)
end

"""Return function name and parameter count for a parsed signature expression."""
function extract_signature_details(signature)
    callable = unwrap_signature_callable(signature)

    if callable isa Symbol
        return string(callable), 0
    end

    if callable isa Expr && callable.head == :call && !isempty(callable.args)
        name = callable_name(callable.args[1])
        param_count = 0
        for arg in callable.args[2:end]
            if arg isa Expr && arg.head == :parameters
                param_count += length(arg.args)
            else
                param_count += 1
            end
        end
        return name, param_count
    end

    return string(callable), 0
end

"""Count non-empty source lines in a function text block."""
function count_nonempty_lines(text::String)
    lines = split(text, '\n')
    return count(line -> !isempty(strip(line)), lines)
end

"""Truncate signature preview text for report readability."""
function short_signature_preview(signature; max_len::Int=160)
    preview = replace(string(signature), '\n' => ' ')
    preview = replace(preview, r"\s+" => " ")
    preview = strip(preview)
    if length(preview) <= max_len
        return preview
    end
    return preview[1:max_len-3] * "..."
end

"""Return the first expression from a parsed toplevel function text block."""
function first_parsed_expr(parsed)
    if parsed isa Expr && parsed.head == :toplevel
        for arg in parsed.args
            if arg isa Expr
                return arg
            end
        end
    end

    return parsed
end

"""Return true when expression is a short-form function assignment."""
function is_short_function_assignment(expr::Expr)
    if expr.head != :(=) || length(expr.args) != 2
        return false
    end

    lhs = expr.args[1]
    lhs = unwrap_signature_callable(lhs)
    return lhs isa Expr && lhs.head == :call
end

"""Extract function metadata from a JuliaSyntax function node."""
function metadata_from_function_node(node, rel_file::String)
    function_text = String(JuliaSyntax.sourcetext(node))
    parsed = JuliaSyntax.parseall(Expr, function_text)
    function_expr = first_parsed_expr(parsed)

    signature = function_expr
    if function_expr isa Expr && function_expr.head == :function && !isempty(function_expr.args)
        signature = function_expr.args[1]
    elseif function_expr isa Expr && is_short_function_assignment(function_expr)
        signature = function_expr.args[1]
    end

    name, param_count = extract_signature_details(signature)
    start_line = Int(first(JuliaSyntax.source_location(node)))
    line_span_count = max(1, length(split(function_text, '\n')))
    end_line = start_line + line_span_count - 1
    nloc = max(1, count_nonempty_lines(function_text))

    return JuliaFunctionMetadata(
        name,
        rel_file,
        start_line,
        end_line,
        nloc,
        param_count,
        short_signature_preview(signature))
end

"""Collect all JuliaSyntax function nodes from a syntax tree."""
function collect_juliasyntax_function_nodes!(node, out)
    if JuliaSyntax.kind(node) == JuliaSyntax.K"function"
        push!(out, node)
    end

    children = JuliaSyntax.children(node)
    if children === nothing
        return
    end

    for child in children
        collect_juliasyntax_function_nodes!(child, out)
    end
end

"""Compute representative parser quality metrics for selected Julia files."""
function representative_parser_quality(metadata::Vector{JuliaFunctionMetadata})
    representative_files = Set([
        "src/julia/script.jl",
        "src/julia/scratchpad.jl",
        "src/julia/elements/book1/def_021b_obtusetriangle.jl",
    ])

    files_found = Set{String}()
    covered = 0
    valid_spans = 0
    for item in metadata
        if !(item.file in representative_files)
            continue
        end
        covered += 1
        push!(files_found, item.file)
        if item.end_line >= item.start_line
            valid_spans += 1
        end
    end

    return Dict{String,Any}(
        "representative_files_target" => length(representative_files),
        "representative_files_found" => length(files_found),
        "representative_functions" => covered,
        "representative_valid_spans" => valid_spans,
        "parser_choice" => "JuliaSyntax SyntaxNode traversal",
        "parser_rationale" => "Uses JuliaSyntax function nodes for line spans and signatures.")
end

"""Collect parser-backed metadata and representative quality data for Julia files."""
function collect_julia_metadata_bundle(src_dir::String, script_dir::String)
    julia_root = joinpath(src_dir, "julia")
    julia_files = sort([path for path in collect_paths(julia_root) if endswith(path, ".jl")])
    metadata = JuliaFunctionMetadata[]
    parse_errors = ParserFileError[]

    for file_path in julia_files
        rel_file = relpath(file_path, script_dir)
        source = read(file_path, String)

        try
            syntax_tree = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, source)
            function_nodes = Any[]
            collect_juliasyntax_function_nodes!(syntax_tree, function_nodes)

            for node in function_nodes
                push!(metadata, metadata_from_function_node(node, rel_file))
            end
        catch err
            push!(parse_errors, ParserFileError(rel_file, sprint(showerror, err)))
            println("Warning: parser metadata skipped " * rel_file)
        end
    end

    sort!(metadata, by=item -> (item.file, item.start_line, item.name))
    quality = representative_parser_quality(metadata)
    return metadata, quality, length(julia_files), parse_errors
end

"""Extract parser-backed metadata for Julia functions under src/julia."""
function extract_julia_function_metadata(src_dir::String, script_dir::String)
    metadata, quality, file_count, parse_errors = collect_julia_metadata_bundle(src_dir, script_dir)

    sample_limit = min(5, length(metadata))
    println("Julia parser metadata collected for $(length(metadata)) functions.")
    for index in 1:sample_limit
        item = metadata[index]
        println(
            "  - " * item.name *
            " | params=" * string(item.param_count) *
            " | lines=" * string(item.start_line) * "-" * string(item.end_line) *
            " | " * item.file *
            " | " * item.signature_preview)
    end

    if !isempty(parse_errors)
        show_count = min(5, length(parse_errors))
        println("Parser metadata parse failures: $(length(parse_errors))")
        for index in 1:show_count
            issue = parse_errors[index]
            println("  - " * issue.file * " | " * issue.details)
        end
        if length(parse_errors) > show_count
            println("  - ... and $(length(parse_errors) - show_count) more parse failure(s)")
        end
    end

    return Dict{String,Any}(
        "files" => file_count,
        "functions" => length(metadata),
        "parse_failure_count" => length(parse_errors),
        "quality_representative_files_target" => quality["representative_files_target"],
        "quality_representative_files_found" => quality["representative_files_found"],
        "quality_representative_functions" => quality["representative_functions"],
        "quality_representative_valid_spans" => quality["representative_valid_spans"],
        "parser_choice" => quality["parser_choice"],
        "parser_rationale" => quality["parser_rationale"])
end

"""Map severity to a sortable rank where higher urgency sorts first."""
function severity_rank(severity::String)
    if severity == "BLOCK"
        return 0
    end

    if severity == "WARN"
        return 1
    end

    return 2
end

"""Render lizard-style Julia complexity table lines for report/console capture."""
function render_julia_complexity_table(rows::Vector{JuliaComplexityRow})
    lines = String[]
    push!(lines, "Julia complexity table:")
    push!(lines, "SEV  STATUS  NLOC  CCN  PARAM  FUNCTION  FILE:LINE")

    for row in rows
        file_line = row.file * ":" * string(row.line)
        push!(
            lines,
            rpad(row.severity, 5) * " " *
            rpad(row.status, 6) * " " *
            lpad(string(row.nloc), 5) * " " *
            lpad(string(row.ccn), 4) * " " *
            lpad(string(row.param_count), 6) * "  " *
            row.function_name * "  " *
            file_line)
    end

    return join(lines, '\n')
end

"""Join parser metadata and complexity values to full-coverage table rows."""
function build_julia_complexity_rows(
    metadata::Vector{JuliaFunctionMetadata},
    all_measures,
    max_complexity::Int,
    warning_roots::Vector{String},
    script_dir::String)
    per_name_index = Dict{Tuple{String,String},Vector{Tuple{Int,Int}}}()
    complexity_function_count = 0

    for file_measure in all_measures
        rel_file = relpath(normpath(file_measure.path), script_dir)
        for fn in file_measure.functions
            key = (rel_file, fn.name)
            if !haskey(per_name_index, key)
                per_name_index[key] = Tuple{Int,Int}[]
            end
            push!(per_name_index[key], (fn.line, Int(round(fn.value))))
            complexity_function_count += 1
        end
    end

    rows = JuliaComplexityRow[]
    blocking_count = 0
    warning_only_count = 0
    passed_count = 0
    unmatched_count = 0

    for item in metadata
        key = (item.file, item.name)
        ccn = 0
        matched = false

        if haskey(per_name_index, key) && !isempty(per_name_index[key])
            candidates = per_name_index[key]
            first_candidate_idx = firstindex(candidates)
            best_idx = first_candidate_idx
            best_distance = abs(candidates[first_candidate_idx][1] - item.start_line)
            for i in Iterators.drop(eachindex(candidates), 1)
                distance = abs(candidates[i][1] - item.start_line)
                if distance < best_distance
                    best_distance = distance
                    best_idx = i
                end
            end

            ccn = candidates[best_idx][2]
            deleteat!(candidates, best_idx)
            per_name_index[key] = candidates
            matched = true
        end

        if !matched
            unmatched_count += 1
        end

        absolute_path = normpath(joinpath(script_dir, item.file))
        warning_only_path = is_warning_only_complexity_path(absolute_path, warning_roots)
        is_violation = ccn > max_complexity

        severity = "INFO"
        status = "PASS"
        if is_violation && warning_only_path
            severity = "WARN"
            status = "WARN"
            warning_only_count += 1
        elseif is_violation
            severity = "BLOCK"
            status = "FAIL"
            blocking_count += 1
        else
            passed_count += 1
        end

        push!(
            rows,
            JuliaComplexityRow(
                severity,
                status,
                item.nloc,
                ccn,
                item.param_count,
                item.name,
                item.file,
                item.start_line))
    end

    sort!(rows, by=row -> (
        severity_rank(row.severity),
        -row.ccn,
        -row.nloc,
        row.function_name,
        row.file,
        row.line))

    metrics = Dict{String,Any}(
        "total_functions" => length(rows),
        "blocking_count" => blocking_count,
        "warning_only_count" => warning_only_count,
        "pass_count" => passed_count,
        "unmatched_complexity_rows" => unmatched_count,
        "complexity_function_count" => complexity_function_count)

    return rows, metrics
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
    julia_root::String = joinpath(src_dir, "julia")
    julia_files = String[joinpath(julia_root, "script.jl")]
    if !isfile(julia_files[1])
        error("JET target file not found: $(julia_files[1])")
    end

    failed = false
    report_count = 0
    actionable_count = 0
    whitelisted_count_total = 0
    max_reports_per_file = 8

    for path::String in julia_files
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
            for index in 1:show_count
                report_entry = actionable[index]
                report_type, location, message = report_entry
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
function run_code_complexity_analysis(src_dir::String, script_dir::String)
    julia_root = joinpath(src_dir, "julia")

    max_complexity = 10
    warning_roots = [
        normpath(joinpath(julia_root, "elements")),
        normpath(joinpath(julia_root, "hilbert")),
        normpath(joinpath(julia_root, "proclus")),
    ]

    metadata, _, _, parse_errors = collect_julia_metadata_bundle(src_dir, script_dir)
    metric = CodeComplexity.CyclomaticComplexity()
    all_measures = CodeComplexity.measure_directory(metric, julia_root; recursive=true)

    rows, row_metrics = build_julia_complexity_rows(
        metadata,
        all_measures,
        max_complexity,
        warning_roots,
        script_dir)

    println(render_julia_complexity_table(rows))

    blocking_count = get(row_metrics, "blocking_count", 0)
    warning_count = get(row_metrics, "warning_only_count", 0)
    blocking_found = blocking_count > 0
    warning_loop_count = count(row -> row.status == "WARN" && row.function_name == "loop", rows)

    println("CodeComplexity full coverage rows: $(length(rows))")
    println("CodeComplexity blocking violations: $blocking_count")
    println("CodeComplexity warning-only violations: $warning_count")

    if warning_loop_count > 0
        println("CodeComplexity warning-only: $warning_loop_count loop functions flagged")
    end

    if !blocking_found
        println("CodeComplexity violations are warning-only for configured directories.")
    end

    return Dict{String,Any}(
        "max_complexity" => max_complexity,
        "violation_files" => count(row -> row.status in ("FAIL", "WARN"), rows),
        "warning_count" => warning_count,
        "warning_loop_count" => warning_loop_count,
        "blocking_found" => blocking_found,
        "total_functions" => get(row_metrics, "total_functions", length(rows)),
        "pass_count" => get(row_metrics, "pass_count", 0),
        "parse_failure_count" => length(parse_errors),
        "blocking_count" => blocking_count,
        "unmatched_complexity_rows" => get(row_metrics, "unmatched_complexity_rows", 0),
        "complexity_function_count" => get(row_metrics, "complexity_function_count", 0))
end

"""Parse aggregate scc CSV rows for Julia, Odin, and computed Total."""
function parse_scc_primary_rows(output::String)
    rows = Dict{String,Tuple{Int,Int}}()
    total_code = 0
    total_complexity = 0
    row_pattern = r"^([^,]+),([0-9]+),([0-9]+),([0-9]+),([0-9]+),([0-9]+),"

    for (index, raw_line) in enumerate(split(output, "\n"))
        if index == 1
            continue
        end

        line = strip(raw_line)
        if isempty(line)
            continue
        end

        match_result = match(row_pattern, line)
        if match_result === nothing
            continue
        end

        captures = match_result.captures
        language = strip(captures[1])
        code_value = tryparse(Int, captures[3])
        complexity_value = tryparse(Int, captures[6])

        if code_value === nothing || complexity_value === nothing
            continue
        end

        code = code_value
        complexity = complexity_value
        total_code += code
        total_complexity += complexity

        if language in ("Odin", "Julia")
            rows[language] = (code, complexity)
        end
    end

    if total_code > 0 || total_complexity > 0
        rows["Total"] = (total_code, total_complexity)
    end

    return rows
end

"""Print derived `Complexity/Code` metrics from scc output."""
function print_scc_complexity_per_file_summary(output::String)
    rows = parse_scc_primary_rows(output)
    labels = ["Odin", "Julia", "Total"]
    printed_any = false
    derived = Dict{String,Float64}()

    for label in labels
        if !haskey(rows, label)
            continue
        end

        code, complexity = rows[label]
        complexity_per_code = code == 0 ? 0.0 : complexity / code
        rounded = round(complexity_per_code; digits=4)
        println("scc derived ($label): Complexity/Code = $rounded")
        derived[label] = rounded
        printed_any = true
    end

    if !printed_any
        println("Warning: Could not parse scc summary rows for Odin/Julia/Total.")
    end

    return Dict{String,Any}(
        "parsed_rows" => length(rows),
        "complexity_per_code_odin" => get(derived, "Odin", 0.0),
        "complexity_per_code_julia" => get(derived, "Julia", 0.0),
        "complexity_per_code_total" => get(derived, "Total", 0.0))
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

"""Return true when external object has command-result-like fields."""
function is_command_result_like(value)
    return hasproperty(value, :exit_code) && hasproperty(value, :stdout) && hasproperty(value, :stderr)
end

"""Build an odin-build-vet section from captured build output in make.jl."""
function run_odin_build_vet_section(odin_build_result)
    if odin_build_result === nothing
        return VetSectionResult(
            "odin-build-vet",
            "Skipped",
            "Odin vet build output was not captured.",
            "skipped",
            nothing,
            "",
            "",
            Dict{String,Any}(),
            false,
            false,
            true,
            false)
    end

    if !is_command_result_like(odin_build_result)
        return VetSectionResult(
            "odin-build-vet",
            "Warn",
            "Odin vet build capture had an unexpected shape.",
            "unexpected-result",
            nothing,
            "",
            "",
            Dict{String,Any}("result_type" => string(typeof(odin_build_result))),
            false,
            true,
            false,
            false)
    end

    exit_code = getproperty(odin_build_result, :exit_code)
    stdout_text = String(getproperty(odin_build_result, :stdout))
    stderr_text = String(getproperty(odin_build_result, :stderr))

    metrics = Dict{String,Any}(
        "exit_code" => exit_code,
        "stdout_bytes" => ncodeunits(stdout_text),
        "stderr_bytes" => ncodeunits(stderr_text))

    if exit_code != 0
        return VetSectionResult(
            "odin-build-vet",
            "Fail",
            "Odin vet build failed.",
            "exit-nonzero",
            exit_code,
            stdout_text,
            stderr_text,
            metrics,
            true,
            false,
            false,
            false)
    end

    return VetSectionResult(
        "odin-build-vet",
        "Pass",
        "Odin vet build passed.",
        "ok",
        exit_code,
        stdout_text,
        stderr_text,
        metrics,
        false,
        false,
        false,
        false)
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

"""Run the parser-backed Julia metadata section and return structured output."""
function run_julia_parser_metadata_section(src_dir::String, script_dir::String)
    value, stdout_text, stderr_text, caught_error = run_captured() do
        extract_julia_function_metadata(src_dir, script_dir)
    end

    metrics = value isa Dict{String,Any} ? value : Dict{String,Any}()
    if caught_error !== nothing
        return build_internal_section_result(
            "julia-parser-metadata",
            "Julia parser metadata extraction passed.",
            "Julia parser metadata extraction failed.",
            metrics,
            stdout_text,
            stderr_text,
            caught_error)
    end

    parse_failure_count = get(metrics, "parse_failure_count", 0)
    if parse_failure_count > 0
        return VetSectionResult(
            "julia-parser-metadata",
            "Warn",
            "Julia parser metadata extraction completed with partial parse failures.",
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
        "julia-parser-metadata",
        "Pass",
        "Julia parser metadata extraction passed.",
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

"""Run the Julia CodeComplexity section and return structured section output."""
function run_codecomplexity_section(src_dir::String, script_dir::String)
    value, stdout_text, stderr_text, caught_error = run_captured() do
        run_code_complexity_analysis(src_dir, script_dir)
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

    summary_capture = run_command(Cmd(["scc", "-f", "csv"]); cwd=script_dir, capture_output=true)
    summary_metrics = Dict{String,Any}()
    if summary_capture.exit_code == 0
        summary_metrics = print_scc_complexity_per_file_summary(summary_capture.stdout)
    else
        println("Warning: failed to collect scc CSV summary for derived metrics.")
    end

    metrics = Dict{String,Any}(
        "exit_code" => result.exit_code,
        "parsed_rows" => get(summary_metrics, "parsed_rows", 0),
        "complexity_per_code_odin" => get(summary_metrics, "complexity_per_code_odin", 0.0),
        "complexity_per_code_julia" => get(summary_metrics, "complexity_per_code_julia", 0.0),
        "complexity_per_code_total" => get(summary_metrics, "complexity_per_code_total", 0.0))

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
function run_vet_analysis(script_dir::String, src_dir::String, odin_build_result=nothing)
    sections = VetSectionResult[]
    report_path = joinpath(script_dir, "bin", "vet-report.md")

    println("Recording Odin vet build output...")
    push!(sections, run_odin_build_vet_section(odin_build_result))

    println("Running Julia syntax validation...")
    push!(sections, run_julia_syntax_section(src_dir, script_dir))

    println("Running Julia parser metadata extraction...")
    push!(sections, run_julia_parser_metadata_section(src_dir, script_dir))

    println("Running CodeComplexity analysis...")
    push!(sections, run_codecomplexity_section(src_dir, script_dir))

    println("Running JET static analysis...")
    push!(sections, run_jet_section(src_dir, script_dir))

    println("Running lizard analysis (odin)...")
    push!(sections, run_odin_lizard_section(src_dir, script_dir))

    println("Running scc statistics (scc --by-file -pw)...")
    push!(sections, run_repo_scc_section(script_dir))

    has_blocking_failures = any(section -> section.blocking, sections)
    run_result = VetRunResult(string(Dates.now(Dates.UTC)), sections, has_blocking_failures)

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
    script_dir = abspath(@__DIR__)
    src_dir = joinpath(script_dir, "src")

    run_vet_analysis(script_dir, src_dir, nothing)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end

