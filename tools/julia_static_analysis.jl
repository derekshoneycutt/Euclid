# Julia static-analysis passes for the Euclid vet pipeline.
#
# This module is included by tools/make-vet.jl into its top-level scope (it is
# not a `module` block) so the section runners can call the public entry points
# directly. It owns every Julia-only analysis: syntax validation, parser-backed
# function metadata, explicit tuple return-shape checks, CodeComplexity
# cyclomatic-complexity analysis, and JET static analysis.
#
# Shared with the driver (defined there, used here): collect_paths and
# ParserFileError. The public entry points each return a Dict{String,Any} of
# metrics; the driver's section runners wrap those into VetSectionResult.

using Pkg
using JET
using CodeComplexity
using JuliaSyntax

#   Method-error message substrings that JET reports but are accepted as known
#   non-issues for this codebase.
const JET_METHOD_ERROR_WHITELIST_PATTERNS = [
    r"`iterate\(::Nothing\)`",
    r"`iterate\(::Nothing, ::Int64\)`",
    r"`ncodeunits\(::Nothing\)`",
    r"`parse_hex\(::Nothing\)`",
    r"`parse_f32\(::Nothing\)`",
    r"`-\(::Vector\{Float32\}, ::Nothing\)`",
    r"`\+\(::Nothing, ::Vector\{Float32\}\)`",
]

#   Parser-backed metadata for one Julia function definition.
struct JuliaFunctionMetadata
    name::String
    file::String
    start_line::Int
    end_line::Int
    nloc::Int
    param_count::Int
    signature_preview::String
end

#   One explicit tuple-return violation in a Julia function.
struct JuliaReturnShapeIssue
    file::String
    function_name::String
    line::Int
    return_count::Int
    signature_preview::String
end

#   One cyclomatic-complexity measurement row for the Julia report.
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

mutable struct JuliaReturnScanState
    file::String
    function_name::String
    function_start_line::Int
    signature_preview::String
    current_line::Int
    issues::Vector{JuliaReturnShapeIssue}
end

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
    function_expr, signature = function_expr_and_signature(function_text)

    name, param_count = extract_signature_details(signature)
    start_line = Int(first(JuliaSyntax.source_location(node)))
    line_span_count = max(1, length(split(function_text, '\n')))
    end_line = start_line + line_span_count - 1
    nloc = max(1, count_nonempty_lines(function_text))

    return JuliaFunctionMetadata(name, rel_file, start_line, end_line, nloc, param_count,
        short_signature_preview(signature))
end

"""Return parsed function expression and signature for one function text block."""
function function_expr_and_signature(function_text::String)
    parsed = JuliaSyntax.parseall(Expr, function_text)
    function_expr = first_parsed_expr(parsed)

    signature = function_expr
    if function_expr isa Expr && function_expr.head == :function &&
        !isempty(function_expr.args)
        signature = function_expr.args[1]
    elseif function_expr isa Expr && is_short_function_assignment(function_expr)
        signature = function_expr.args[1]
    end

    return function_expr, signature
end

"""Return true when an expression is an explicit positional tuple with arity > 0."""
function is_positional_tuple_expr(expr)
    return expr isa Expr && expr.head == :tuple
end

"""Append explicit tuple-return issues for one function expression."""
function collect_explicit_tuple_return_issues!(expr, state::JuliaReturnScanState;
    is_root::Bool=false)
    if expr isa LineNumberNode
        state.current_line = Int(expr.line)
        return
    end

    if !(expr isa Expr)
        return
    end

    if !is_root && (expr.head == :function || is_short_function_assignment(expr))
        return
    end

    if expr.head == :return && !isempty(expr.args)
        value = expr.args[1]
        if is_positional_tuple_expr(value) && length(value.args) > 2
            issue_line = state.current_line > 0 ?
                state.function_start_line + state.current_line - 1 :
                state.function_start_line
            push!(state.issues, JuliaReturnShapeIssue(
                state.file,
                state.function_name,
                issue_line,
                length(value.args),
                state.signature_preview))
        end
    end

    for arg in expr.args
        if arg isa LineNumberNode
            state.current_line = Int(arg.line)
            continue
        end

        if arg isa Expr
            collect_explicit_tuple_return_issues!(arg, state)
        end
    end
end

"""Return explicit positional tuple-return issues for one Julia function node."""
function return_shape_issues_from_function_node(node, rel_file::String)
    function_text = String(JuliaSyntax.sourcetext(node))
    function_expr, signature = function_expr_and_signature(function_text)
    metadata = metadata_from_function_node(node, rel_file)
    issues = JuliaReturnShapeIssue[]
    state = JuliaReturnScanState(
        rel_file,
        metadata.name,
        metadata.start_line,
        short_signature_preview(signature),
        1,
        issues)

    if function_expr isa Expr && is_short_function_assignment(function_expr)
        rhs = function_expr.args[2]
        if is_positional_tuple_expr(rhs) && length(rhs.args) > 2
            push!(issues, JuliaReturnShapeIssue(
                rel_file,
                metadata.name,
                metadata.start_line,
                length(rhs.args),
                metadata.signature_preview))
        end
        return issues
    end

    collect_explicit_tuple_return_issues!(function_expr, state; is_root=true)
    return issues
end

"""Collect explicit tuple-return issues for Julia functions under src/julia."""
function collect_julia_return_shape_issues(src_dir::String, script_dir::String)
    julia_root = joinpath(src_dir, "julia")
    julia_files = sort([path for path in collect_paths(julia_root) if endswith(path, ".jl")])
    issues = JuliaReturnShapeIssue[]
    parse_errors = ParserFileError[]
    function_count = 0

    for file_path in julia_files
        rel_file = relpath(file_path, script_dir)
        source = read(file_path, String)

        try
            syntax_tree = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, source)
            function_nodes = Any[]
            collect_juliasyntax_function_nodes!(syntax_tree, function_nodes)
            function_count += length(function_nodes)

            for node in function_nodes
                append!(issues, return_shape_issues_from_function_node(node, rel_file))
            end
        catch err
            push!(parse_errors, ParserFileError(rel_file, sprint(showerror, err)))
            println("Warning: return-shape scan skipped " * rel_file)
        end
    end

    sort!(issues, by=issue ->
        (issue.file, issue.line, issue.function_name, issue.return_count))
    return issues, length(julia_files), function_count, parse_errors
end

"""Render explicit Julia tuple-return issues for vet output."""
function render_julia_return_shape_issues(issues::Vector{JuliaReturnShapeIssue})
    lines = String[]
    push!(lines, "Julia explicit tuple-return table:")
    push!(lines, "ARITY  FUNCTION  FILE:LINE  SIGNATURE")

    for issue in issues
        file_line = issue.file * ":" * string(issue.line)
        push!(lines,
            lpad(string(issue.return_count), 5) * "  " *
            issue.function_name * "  " *
            file_line * "  " *
            issue.signature_preview)
    end

    return join(lines, '\n')
end

"""Run explicit Julia tuple-return analysis and block on arity above 2."""
function run_julia_return_shape_analysis(src_dir::String, script_dir::String)
    issues, file_count, function_count, parse_errors =
        collect_julia_return_shape_issues(src_dir, script_dir)

    if !isempty(issues)
        println(render_julia_return_shape_issues(issues))
    else
        println("Julia explicit tuple-return table: no issues")
    end

    if !isempty(parse_errors)
        println("Return-shape parse failures: $(length(parse_errors))")
        show_count = min(5, length(parse_errors))
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
        "functions" => function_count,
        "issue_count" => length(issues),
        "parse_failure_count" => length(parse_errors))
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
    metadata, quality, file_count,
    parse_errors = collect_julia_metadata_bundle(src_dir, script_dir)

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

"""Return true when complexity warning for a function is explicitly acceptable."""
function is_acceptable_complexity_warning(row::JuliaComplexityRow)
    normalized_file = replace(row.file, '\\' => '/')

    if row.function_name == "loop"
        return true
    end

    if startswith(row.function_name, "get_view_text") &&
        occursin(r"^src/julia/[^/]+/", normalized_file)
        return true
    end

    return false
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
        warning_only_loop = item.name == "loop"
        normalized_file = replace(item.file, '\\' => '/')
        warning_only_get_view_text = startswith(item.name, "get_view_text") &&
            occursin(r"^src/julia/[^/]+/", normalized_file)
        warning_only = warning_only_path || warning_only_loop ||
            warning_only_get_view_text
        is_violation = ccn > max_complexity

        severity = "INFO"
        status = "PASS"
        if is_violation && warning_only
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

"""Return one report location using either direct file/line fields or the
virtual stack trace frames carried by older JET report types."""
function jet_report_location(report, script_dir::String)::String
    project_root = normpath(script_dir)

    if hasproperty(report, :file) && hasproperty(report, :line)
        frame_file = String(getproperty(report, :file))
        frame_line = getproperty(report, :line)
        normalized = normpath(frame_file)

        if startswith(normalized, project_root)
            return relpath(normalized, script_dir) * ":" * string(frame_line)
        end

        if startswith(frame_file, "src/")
            return frame_file * ":" * string(frame_line)
        end
    end

    if hasproperty(report, :vst)
        for frame in getproperty(report, :vst)
            frame_file = String(frame.file)
            normalized = normpath(frame_file)

            if startswith(normalized, project_root)
                return relpath(normalized, script_dir) * ":" * string(frame.line)
            end

            if startswith(frame_file, "src/")
                return frame_file * ":" * string(frame.line)
            end
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

    previous_project = Base.active_project()
    Pkg.activate(julia_root; io=devnull)

    failed = false
    report_count = 0
    actionable_count = 0
    whitelisted_count_total = 0
    max_reports_per_file = 8

    try
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
    finally
        if isnothing(previous_project)
            Pkg.activate(; temp=true, io=devnull)
        else
            Pkg.activate(dirname(previous_project); io=devnull)
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

    rows, row_metrics = build_julia_complexity_rows(metadata, all_measures,
        max_complexity, warning_roots, script_dir)

    println(render_julia_complexity_table(rows))

    blocking_count = get(row_metrics, "blocking_count", 0)
    warning_count = get(row_metrics, "warning_only_count", 0)
    blocking_found = blocking_count > 0
    warning_loop_count = count(row -> row.status == "WARN" && row.function_name == "loop", rows)
    acceptable_warning_count = count(
        row -> row.status == "WARN" && is_acceptable_complexity_warning(row),
        rows)
    unacceptable_warning_count = warning_count - acceptable_warning_count

    println("CodeComplexity full coverage rows: $(length(rows))")
    println("CodeComplexity blocking violations: $blocking_count")
    println("CodeComplexity warning-only violations: $warning_count")
    println("CodeComplexity acceptable warning-only violations: $acceptable_warning_count")
    println("CodeComplexity non-acceptable warning-only violations: $unacceptable_warning_count")

    if warning_loop_count > 0
        println("CodeComplexity warning-only: $warning_loop_count loop functions flagged")
    end

    if !blocking_found
        println("CodeComplexity violations are warning-only for configured paths/patterns.")
    end

    return Dict{String,Any}(
        "max_complexity" => max_complexity,
        "violation_files" => count(row -> row.status in ("FAIL", "WARN"), rows),
        "warning_count" => warning_count,
        "warning_loop_count" => warning_loop_count,
        "acceptable_warning_count" => acceptable_warning_count,
        "unacceptable_warning_count" => unacceptable_warning_count,
        "blocking_found" => blocking_found,
        "total_functions" => get(row_metrics, "total_functions", length(rows)),
        "pass_count" => get(row_metrics, "pass_count", 0),
        "parse_failure_count" => length(parse_errors),
        "blocking_count" => blocking_count,
        "unmatched_complexity_rows" => get(row_metrics, "unmatched_complexity_rows", 0),
        "complexity_function_count" => get(row_metrics, "complexity_function_count", 0))
end

