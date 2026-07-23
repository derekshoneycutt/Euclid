module Scratchpad

using ..OdinJuliaBridge
using REPL

export init_euclid_scripts_scratchpad, get_view_text, initialize, clean, loop,
    classify_input, queue_input, register_frame_hook, remove_frame_hook,
    clear_frame_hooks, list_frame_hooks, save_history_to_file,
    history_previous, history_next, history_reset_cursor

mutable struct ScratchpadMetrics
    output_trimmed::Int
    history_trimmed::Int
    queue_dropped::Int
    queue_enqueued::Int
    queue_dequeued::Int
    queue_high_water::Int
    local_commands::Int
    blocked_commands::Int
    eval_errors::Int
    hook_errors::Int
    slow_eval_warnings::Int
    slow_hook_warnings::Int
    last_eval_ns::Int
    last_hook_ns::Int
end

mutable struct ScratchpadFrameHook
    id::Int
    fn::Any
    label::String
    enabled::Bool
    failures::Int
    consecutive_failures::Int
end

mutable struct ScratchpadSession
    id::Int
    runtime::Module
    queue::Vector{String}
    output::Vector{String}
    history::Vector{String}
    hooks::Vector{ScratchpadFrameHook}
    metrics::ScratchpadMetrics
    history_cursor::Int
    next_hook_id::Int
end

const ScratchpadName = "Scratchpad"
const ParseError = Int32(0)
const ParseIncomplete = Int32(1)
const ParseComplete = Int32(2)
const MaxOutputLines = 400
const MaxHistoryLines = 400
const MaxQueueLines = 64
const SlowEvalWarnNs = Int(150_000_000)
const SlowHookWarnNs = Int(80_000_000)
const MaxConsecutiveHookFailures = 3
const DynviewStyleInput = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_PROMPT
const DynviewStyleOutput = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT
const DynviewStyleError = OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_ERROR

const session_ref = Ref{Union{Nothing, ScratchpadSession}}(nothing)
const next_session_id_ref = Ref(1)
const initialize_count_ref = Ref(0)
const clean_count_ref = Ref(0)
const reset_count_ref = Ref(0)

# REPL-callable API is centered around: classify_input, queue_input,
# register_frame_hook/remove_frame_hook/clear_frame_hooks/list_frame_hooks,
# history_previous/history_next/history_reset_cursor, and save_history_to_file.

"""Register scratchpad animation callbacks with the host animation tree."""
function init_euclid_scripts_scratchpad(state_ptr::Ptr{Cvoid})
    OdinJuliaBridge.add_root_animation_interface(
        state_ptr, get_view_text, initialize, loop, clean, ScratchpadName)
end

"""Create an isolated runtime module used as the scratchpad eval scope."""
function create_runtime_module(session_id::Int)
    mod_name = Symbol("EuclidScratchpadSession_", session_id)
    runtime = Module(mod_name)

    Core.eval(runtime, :(const OdinJuliaBridge = Main.OdinJuliaBridge))
    Core.eval(runtime, :(const EuclidGeometry = Main.EuclidGeometry))
    Core.eval(runtime, :(const EuclidAnimations = Main.EuclidAnimations))
    Core.eval(runtime, :(const EuclidRepl = Main.EuclidRepl))
    Core.eval(runtime, :(const Scratchpad = Main.Scratchpad))

    # Expose helpers directly in session scope so users can register/remove hooks from input.
    Core.eval(runtime, quote
        register_frame_hook(fn; label="") = Scratchpad.register_frame_hook(state_ptr, fn; label=label)
        remove_frame_hook(hook_id) = Scratchpad.remove_frame_hook(state_ptr, hook_id)
        clear_frame_hooks() = Scratchpad.clear_frame_hooks(state_ptr)
        list_frame_hooks() = Scratchpad.list_frame_hooks(state_ptr)
        save_history(path) = Scratchpad.save_history_to_file(state_ptr, path)

        # Convenience wrappers for common EuclidRepl draw APIs.
        point!(args...; kwargs...) = EuclidRepl.point!(state_ptr, args...; kwargs...)
        line!(args...; kwargs...) = EuclidRepl.line!(state_ptr, args...; kwargs...)
        circle!(args...; kwargs...) = EuclidRepl.circle!(state_ptr, args...; kwargs...)

        # Intercept interactive exit/quit and reset only scratchpad session state.
        exit(args...) = Scratchpad.intercept_exit_or_quit(state_ptr)
        quit(args...) = Scratchpad.intercept_exit_or_quit(state_ptr)
    end)

    return runtime
end

"""Append one output line while enforcing the configured output retention cap."""
function append_output_line!(session::ScratchpadSession, line::AbstractString)
    push!(session.output, String(line))
    extra = length(session.output) - MaxOutputLines
    if extra > 0
        session.metrics.output_trimmed += extra
        deleteat!(session.output, 1:extra)
    end
end

"""Append one history line while enforcing the configured history retention cap."""
function append_history_line!(session::ScratchpadSession, line::String)
    push!(session.history, line)
    extra = length(session.history) - MaxHistoryLines
    if extra > 0
        session.metrics.history_trimmed += extra
        deleteat!(session.history, 1:extra)
    end
end

"""Push text into the execution queue and track queue metrics/cap behavior."""
function queue_line!(session::ScratchpadSession, text::String)
    if length(session.queue) >= MaxQueueLines
        session.metrics.queue_dropped += 1
        _ = popfirst!(session.queue)
    end

    push!(session.queue, text)
    session.metrics.queue_enqueued += 1
    session.metrics.queue_high_water = max(session.metrics.queue_high_water, length(session.queue))
end

"""Return a safety-policy block reason for input text, or `nothing` when allowed."""
function blocked_input_reason(text::AbstractString)
    lowered = lowercase(strip(String(text)))
    if occursin(r"^(using|import)\s+pkg\b", lowered)
        return "package management is disabled in scratchpad"
    end

    blocked_tokens = (
        "@ccall",
        "ccall(",
        "run(",
        "pipeline(",
        "Base.run",
        "download(",
        "rm(",
        "mv(",
        "cp(",
    )
    for token in blocked_tokens
        if occursin(token, lowered)
            return "blocked token: $(token)"
        end
    end

    return nothing
end

"""Record eval timing and emit a warning when eval exceeds the slow threshold."""
function maybe_warn_slow_eval!(session::ScratchpadSession, elapsed_ns::Integer)
    session.metrics.last_eval_ns = elapsed_ns
    if elapsed_ns <= SlowEvalWarnNs
        return
    end

    session.metrics.slow_eval_warnings += 1
    elapsed_ms = round(elapsed_ns / 1_000_000; digits=2)
    append_output_line!(session, "Warning: eval took $(elapsed_ms) ms")
end

"""Record hook timing and emit a warning when a hook exceeds the slow threshold."""
function maybe_warn_slow_hook!(session::ScratchpadSession, hook::ScratchpadFrameHook, elapsed_ns::Integer)
    session.metrics.last_hook_ns = elapsed_ns
    if elapsed_ns <= SlowHookWarnNs
        return
    end

    session.metrics.slow_hook_warnings += 1
    elapsed_ms = round(elapsed_ns / 1_000_000; digits=2)
    append_output_line!(session, "Warning: $(frame_hook_label(hook.id, hook.label)) took $(elapsed_ms) ms")
end

"""Build a formatted summary of current scratchpad runtime metrics."""
function metrics_summary_lines(state_ptr::Ptr{Cvoid})
    session = ensure_session!(state_ptr)
    m = session.metrics
    return [
        "Scratchpad Metrics",
        "queue enqueued=$(m.queue_enqueued) dequeued=$(m.queue_dequeued) dropped=$(m.queue_dropped) high_water=$(m.queue_high_water)",
        "trimmed output=$(m.output_trimmed) history=$(m.history_trimmed)",
        "errors eval=$(m.eval_errors) hooks=$(m.hook_errors) blocked=$(m.blocked_commands)",
        "slow eval warnings=$(m.slow_eval_warnings) last_eval_ns=$(m.last_eval_ns)",
        "slow hook warnings=$(m.slow_hook_warnings) last_hook_ns=$(m.last_hook_ns)",
        "transitions initialize=$(initialize_count_ref[]) clean=$(clean_count_ref[]) reset=$(reset_count_ref[])",
    ]
end

"""Create and install a fresh scratchpad session, runtime module, and counters."""
function reset_session!(state_ptr::Ptr{Cvoid})
    if isdefined(Main, :EuclidRepl) && isdefined(Main.EuclidRepl, :reset_scratchpad_session!)
        Main.EuclidRepl.reset_scratchpad_session!()
    end

    session_id = next_session_id_ref[]
    next_session_id_ref[] = session_id + 1
    reset_count_ref[] += 1

    runtime = create_runtime_module(session_id)
    session = ScratchpadSession(
        session_id,
        runtime,
        String[],
        String[],
        String[],
        ScratchpadFrameHook[],
        ScratchpadMetrics(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        1,
        1)
    session_ref[] = session

    Core.eval(runtime, :(state_ptr = $state_ptr))
    return session
end

"""Return the current session or create one when missing, refreshing state_ptr binding."""
function ensure_session!(state_ptr::Ptr{Cvoid})
    session = session_ref[]
    if session === nothing
        return reset_session!(state_ptr)
    end

    Core.eval(session.runtime, :(state_ptr = $state_ptr))
    return session
end

"""Apply REPL softscope transformation to parsed expressions when available."""
function apply_softscope(runtime::Module, expr)
    try
        return REPL.softscope(runtime, expr)
    catch
        try
            return REPL.softscope(expr)
        catch
            return expr
        end
    end
end

"""Parse text and classify it as parse error, incomplete input, or complete expression."""
function classify_parse(text::String)
    parsed = Meta.parse(text; raise=false)
    if parsed isa Expr && parsed.head === :incomplete
        return ParseIncomplete, parsed
    end
    if parsed isa Expr && parsed.head === :error
        return ParseError, parsed
    end
    return ParseComplete, parsed
end

"""Convert a parse-error expression payload into a stable user-facing message."""
function parse_error_message(parsed)
    message = "Parse error"
    if parsed isa Expr && !isempty(parsed.args)
        message = "Parse error: " * string(parsed.args[1])
    end
    return message
end

"""Classify user input parse state and append parse errors to output when present."""
function classify_input(state_ptr::Ptr{Cvoid}, text::String)
    session = ensure_session!(state_ptr)

    stripped = strip(text)
    if !isempty(stripped) && first(stripped) == '?'
        # Help-mode queries are handled in evaluate_queued_input! and should not be parsed as Julia syntax.
        return ParseComplete
    end

    status, parsed = classify_parse(text)
    if status == ParseError
        append_output_line!(session, parse_error_message(parsed))
    end

    return status
end

"""Format a frame hook identifier/label pair for user-facing log messages."""
function frame_hook_label(id::Int, label::String)
    if isempty(label)
        return "hook id=$(id)"
    end

    return "hook id=$(id) label=$(repr(label))"
end

"""
Register a callback that runs every frame during scratchpad loop execution.

Returns a numeric hook id that can be used with `remove_frame_hook`.
"""
function register_frame_hook(state_ptr::Ptr{Cvoid}, fn; label="")
    session = ensure_session!(state_ptr)

    hook_id = session.next_hook_id
    session.next_hook_id += 1
    push!(session.hooks, ScratchpadFrameHook(hook_id, fn, String(label), true, 0, 0))
    append_output_line!(session, "Registered $(frame_hook_label(hook_id, String(label)))")

    return hook_id
end

"""Register a frame hook without appending user-facing output lines."""
function register_frame_hook_silent(state_ptr::Ptr{Cvoid}, fn; label="")
    session = ensure_session!(state_ptr)

    hook_id = session.next_hook_id
    session.next_hook_id += 1
    push!(session.hooks, ScratchpadFrameHook(hook_id, fn, String(label), true, 0, 0))

    return hook_id
end

"""
Remove a previously registered frame hook by id.

Returns `true` when the hook was removed, `false` otherwise.
"""
function remove_frame_hook(state_ptr::Ptr{Cvoid}, hook_id)
    session = ensure_session!(state_ptr)
    id = try
        Int(hook_id)
    catch
        append_output_line!(session, "remove_frame_hook: invalid hook id")
        return false
    end

    for i in eachindex(session.hooks)
        hook = session.hooks[i]
        if hook.id == id
            deleteat!(session.hooks, i)
            append_output_line!(session, "Removed $(frame_hook_label(hook.id, hook.label))")
            return true
        end
    end

    append_output_line!(session, "remove_frame_hook: hook id=$(id) not found")
    return false
end

"""Remove a frame hook by id without appending user-facing output lines."""
function remove_frame_hook_silent(state_ptr::Ptr{Cvoid}, hook_id)
    session = ensure_session!(state_ptr)
    id = try
        Int(hook_id)
    catch
        return false
    end

    for i in eachindex(session.hooks)
        hook = session.hooks[i]
        if hook.id == id
            deleteat!(session.hooks, i)
            return true
        end
    end

    return false
end

"""
Remove all registered frame hooks.

Returns the number of hooks removed.
"""
function clear_frame_hooks(state_ptr::Ptr{Cvoid})
    session = ensure_session!(state_ptr)
    removed = length(session.hooks)
    empty!(session.hooks)
    append_output_line!(session, "Cleared $(removed) frame hook(s)")
    return removed
end

"""
List currently registered frame hooks as a human-readable multiline string.
"""
function list_frame_hooks(state_ptr::Ptr{Cvoid})
    session = ensure_session!(state_ptr)
    if isempty(session.hooks)
        return "(no frame hooks registered)"
    end

    lines = String[]
    for hook in session.hooks
        push!(lines,
            "id=$(hook.id) label=$(repr(hook.label)) enabled=$(hook.enabled) failures=$(hook.failures)")
    end
    return join(lines, "\n")
end

"""
Reset scratchpad history navigation cursor to the latest (empty input) position.
"""
function history_reset_cursor(state_ptr::Ptr{Cvoid})
    session = ensure_session!(state_ptr)
    session.history_cursor = length(session.history) + 1
    return true
end

"""
Return the previous entry from scratchpad history.
"""
function history_previous(state_ptr::Ptr{Cvoid})
    session = ensure_session!(state_ptr)
    if isempty(session.history)
        return ""
    end

    if session.history_cursor > 1
        session.history_cursor -= 1
    end
    return session.history[session.history_cursor]
end

"""
Return the next entry from scratchpad history.

Returns `""` when navigation reaches the newest empty slot.
"""
function history_next(state_ptr::Ptr{Cvoid})
    session = ensure_session!(state_ptr)
    if isempty(session.history)
        return ""
    end

    max_cursor = length(session.history) + 1
    if session.history_cursor < max_cursor
        session.history_cursor += 1
    end
    if session.history_cursor == max_cursor
        return ""
    end

    return session.history[session.history_cursor]
end

"""
Save scratchpad input history to a newline-delimited file.

Returns `true` on success, otherwise `false` and appends an error line to output.
"""
function save_history_to_file(state_ptr::Ptr{Cvoid}, path)
    session = ensure_session!(state_ptr)

    file_path = try
        String(path)
    catch
        append_output_line!(session, "save_history: invalid path")
        return false
    end

    if isempty(file_path)
        append_output_line!(session, "save_history: path is empty")
        return false
    end

    try
        open(file_path, "w") do io
            for line in session.history
                write(io, line)
                write(io, "\n")
            end
        end
        append_output_line!(session, "History saved to $(file_path)")
        return true
    catch e
        append_output_line!(session, "save_history failed: " * sprint(showerror, e, catch_backtrace()))
        return false
    end
end

function intercept_exit_or_quit(state_ptr::Ptr{Cvoid})
    session = reset_session!(state_ptr)
    append_output_line!(session, "exit()/quit() intercepted; scratchpad session reset")
    return nothing
end

"""
Queue one complete scratchpad input entry for one-per-frame execution.

Returns `true` if queued, `false` when parse state is not complete.
"""
function queue_input(state_ptr::Ptr{Cvoid}, text::String)
    session = ensure_session!(state_ptr)

    stripped = strip(text)
    if isempty(stripped) || first(stripped) != '?'
        status, _ = classify_parse(text)
        if status != ParseComplete
            return false
        end
    end

    append_history_line!(session, text)
    session.history_cursor = length(session.history) + 1
    queue_line!(session, text)
    return true
end

"""Append built-in scratchpad usage/help lines to output."""
function append_help_lines!(session::ScratchpadSession)
    append_output_line!(session, "Julia REPL Scratchpad")
    append_output_line!(session, "Enter Julia code, just like the standard Julia REPL!")
    append_output_line!(session, "")
    append_output_line!(session, "Commands")
    append_output_line!(session, "  :help        show this help")
    append_output_line!(session, "  :clear       clear scrollback output")
    append_output_line!(session, "  :reset       reset scratchpad session")
    append_output_line!(session, "  :hooks       list frame hooks")
    append_output_line!(session, "  :stats       show runtime metrics")
    append_output_line!(session, "  ?name        show docs for module, function, or variable name")
    append_output_line!(session, "")
    append_output_line!(session, "Common Modules")
    append_output_line!(session, "  OdinJuliaBridge")
    append_output_line!(session, "  EuclidGeometry")
    append_output_line!(session, "  EuclidAnimations")
    append_output_line!(session, "  EuclidRepl")
    append_output_line!(session, "")
    append_output_line!(session, "Common Helper Methods")
    append_output_line!(session, "  register_frame_hook(fn; label=\"\")")
    append_output_line!(session, "  remove_frame_hook(id)")
    append_output_line!(session, "  clear_frame_hooks()")
    append_output_line!(session, "  list_frame_hooks()")
    append_output_line!(session, "  save_history(path)")
    append_output_line!(session, "  point!(pos; color=:steelblue, brush=5f0, duration=5.5f0)")
    append_output_line!(session, "  line!(start_pos, end_pos; color=:steelblue, brush=5f0, duration=7.5f0)")
    append_output_line!(session, "  circle!(center, radius; color=:steelblue, brush=5f0, duration=8.0f0)")
end

"""Render a result value using text/plain when possible for REPL-style display."""
function format_result_value(value)
    try
        return sprint(show, MIME("text/plain"), value)
    catch
        return sprint(show, value)
    end
end

"""Format an exception plus first stack frame location for concise output lines."""
function format_exception_text(e, bt)
    message = sprint(showerror, e)
    frames = stacktrace(bt)
    if isempty(frames)
        return message
    end

    frame = first(frames)
    return "$(message) @ $(frame.file):$(frame.line)"
end

"""Echo submitted input into output using prompt-style prefixes for multiline input."""
function append_input_echo!(session::ScratchpadSession, text::String)
    lines = split(text, '\n')
    if isempty(lines)
        append_output_line!(session, ">")
        return
    end

    append_output_line!(session, "> " * first(lines))
    for i in eachindex(lines)
        if i == firstindex(lines)
            continue
        end
        append_output_line!(session, "| " * lines[i])
    end
end

"""Append a possibly-multiline text block to output preserving blank lines."""
function append_output_block!(session::ScratchpadSession, text::AbstractString)
    if isempty(text)
        return
    end

    for line in split(String(text), '\n'; keepempty=true)
        append_output_line!(session, line)
    end
end

"""Return true when a line is part of prompt-style input echo output."""
is_input_echo_line(line::AbstractString) = startswith(line, "> ") || startswith(line, "| ")

"""Return true when a host bridge status code represents success."""
is_bridge_status_ok(code::Integer) = Int32(code) == OdinJuliaBridge.BRIDGE_STATUS_OK

"""Map one output line into block/style ids for dynview emission."""
function dynview_ids_for_line(line::AbstractString)
    if is_input_echo_line(line)
        return OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_INPUT, DynviewStyleInput
    end

    if startswith(line, "Error:") || startswith(line, "help error:") || startswith(line, "Blocked ")
        return OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT, DynviewStyleError
    end

    return OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT, DynviewStyleOutput
end

"""Switch dynview block when needed, preserving strict begin/end ordering."""
function dynview_switch_block!(state_ptr::Ptr{Cvoid}, open_block::Bool, current_kind::Int32, next_kind::Int32, block_id::Int32)
    if open_block && next_kind == current_kind
        return true, open_block, current_kind, block_id
    end

    if open_block && !is_bridge_status_ok(OdinJuliaBridge.dynview_end_block(state_ptr))
        return false, open_block, current_kind, block_id
    end
    if !is_bridge_status_ok(OdinJuliaBridge.dynview_begin_block(state_ptr, next_kind, block_id))
        return false, open_block, current_kind, block_id
    end

    return true, true, next_kind, block_id + Int32(1)
end

"""Emit one line and optional line-break into the active dynview block."""
function dynview_emit_line!(state_ptr::Ptr{Cvoid}, line::AbstractString, style_id::Int32, add_line_break::Bool)
    if !is_bridge_status_ok(OdinJuliaBridge.dynview_text_run(state_ptr, line, style_id))
        return false
    end
    if !is_bridge_status_ok(OdinJuliaBridge.dynview_copyable_text_run(state_ptr, "", line, style_id))
        return false
    end
    if add_line_break && !is_bridge_status_ok(OdinJuliaBridge.dynview_line_break(state_ptr))
        return false
    end
    return true
end

"""Emit current scratchpad output as a dynview command stream for host-side rendering."""
function emit_dynview_output_stream!(state_ptr::Ptr{Cvoid}, session::ScratchpadSession)
    if !is_bridge_status_ok(OdinJuliaBridge.dynview_reset_stream(state_ptr)) || isempty(session.output)
        return isempty(session.output)
    end

    block_id = Int32(1)
    current_kind = Int32(0)
    open_block = false
    last_line_index = lastindex(session.output)
    for i in eachindex(session.output)
        block_kind, style_id = dynview_ids_for_line(session.output[i])
        ok, open_block, current_kind, block_id = dynview_switch_block!(
            state_ptr,
            open_block,
            current_kind,
            block_kind,
            block_id)
        if !ok || !dynview_emit_line!(state_ptr, session.output[i], style_id, i != last_line_index)
            return false
        end
    end

    return !open_block || is_bridge_status_ok(OdinJuliaBridge.dynview_end_block(state_ptr))
end

"""Validate one dotted help-query segment as an identifier-like token."""
function is_valid_help_segment(segment::AbstractString)
    if isempty(segment)
        return false
    end
    first_char = first(segment)
    if !(isletter(first_char) || first_char == '_')
        return false
    end

    for c in segment
        if isletter(c) || isnumeric(c) || c == '_' || c == '!'
            continue
        end
        return false
    end
    return true
end

"""Parse `?` query text into module/binding symbol segments or return `nothing`."""
function parse_help_segments(query::AbstractString)
    cleaned = strip(String(query))
    if isempty(cleaned)
        return nothing
    end

    segments = split(cleaned, '.')
    if isempty(segments)
        return nothing
    end

    for segment in segments
        if !is_valid_help_segment(segment)
            return nothing
        end
    end

    return Symbol.(segments)
end

"""Resolve a dotted help query into a docs binding rooted from runtime or Main."""
function resolve_help_binding(runtime::Module, query::AbstractString)
    segments = parse_help_segments(query)
    if segments === nothing
        return nothing, "help error: invalid target syntax; use dotted identifiers like OdinJuliaBridge.bridge_color"
    end

    if length(segments) == 0
        return nothing, "help error: empty help target"
    end

    current_module = runtime
    segment_start = 1
    if segments[1] == :Main
        current_module = Main
        segment_start = 2
    end

    last_index = length(segments)
    if segment_start > last_index
        return nothing, "help error: missing symbol after module path"
    end

    for i in segment_start:(last_index - 1)
        segment = segments[i]
        if !isdefined(current_module, segment)
            return nothing, "help error: $(current_module).$(segment) is not defined"
        end

        next_value = getfield(current_module, segment)
        if !(next_value isa Module)
            return nothing, "help error: $(current_module).$(segment) is not a module"
        end

        current_module = next_value
    end

    symbol_name = segments[last_index]
    return Base.Docs.Binding(current_module, symbol_name), nothing
end

"""Render docs metadata objects into plain user-facing help text."""
function render_help_docs(doc_entry)
    if doc_entry isa Base.Docs.MultiDoc
        docs_dict = getfield(doc_entry, :docs)
        blocks = String[]
        for docstr in values(docs_dict)
            if !(docstr isa Base.Docs.DocStr)
                continue
            end

            rendered = render_doc_text_parts(getfield(docstr, :text))
            if !isempty(rendered)
                push!(blocks, rendered)
            end
        end

        if !isempty(blocks)
            return join(unique(blocks), "\n\n")
        end
    end

    if doc_entry isa Base.Docs.DocStr
        rendered = render_doc_text_parts(getfield(doc_entry, :text))
        if !isempty(rendered)
            return rendered
        end
    end

    fallback = strip(sprint(show, MIME("text/plain"), doc_entry))
    if isempty(fallback)
        return nothing
    end
    return fallback
end

"""Render `DocStr.text` fragments into one stripped string block."""
function render_doc_text_parts(parts)
    rendered = ""
    for part in parts
        if part isa AbstractString
            rendered *= part
        else
            rendered *= sprint(show, MIME("text/plain"), part)
        end
    end
    return strip(rendered)
end

"""Build argument parts from method declaration metadata when available."""
function render_signature_parts_from_decl(method)
    _, decl_parts, _, _ = Base.arg_decl_parts(method)
    parts = String[]
    arg_index = 0
    for i in eachindex(decl_parts)
        if i == firstindex(decl_parts)
            continue
        end

        arg_index += 1
        arg_name = strip(String(decl_parts[i][1]))
        arg_type = strip(String(decl_parts[i][2]))
        if isempty(arg_name)
            arg_name = "arg$(arg_index)"
        end

        if isempty(arg_type)
            push!(parts, arg_name)
        else
            push!(parts, arg_name * "::" * arg_type)
        end
    end
    return parts
end

"""Build fallback argument parts directly from method signature type tuple."""
function render_signature_parts_from_sig(method)
    sig = Base.unwrap_unionall(method.sig)
    params = sig.parameters

    parts = String[]
    if length(params) <= 1
        return parts
    end

    arg_index = 0
    for i in eachindex(params)
        if i == firstindex(params)
            continue
        end

        arg_index += 1
        push!(parts, "arg$(arg_index)::" * string(params[i]))
    end
    return parts
end

"""Render unique readable method signatures for a function docs binding."""
function render_help_signatures(binding::Base.Docs.Binding)
    if !isdefined(binding.mod, binding.var)
        return nothing
    end

    value = getfield(binding.mod, binding.var)
    if !(value isa Function)
        return nothing
    end

    method_list = methods(value)
    if length(method_list) == 0
        return "(no methods found)"
    end

    signatures = String[]
    for method in method_list
        arg_parts = String[]
        try
            arg_parts = render_signature_parts_from_decl(method)
        catch
            arg_parts = render_signature_parts_from_sig(method)
        end

        push!(signatures, string(binding.var) * "(" * join(arg_parts, ", ") * ")")
    end

    unique!(signatures)
    sort!(signatures)
    return join(signatures, "\n")
end

"""List unique sorted public/exported function names defined by a module."""
function list_module_function_names(module_value::Module)
    function_names = String[]
    for sym in names(module_value; all=false, imported=false)
        sym_text = String(sym)
        if startswith(sym_text, "#")
            continue
        end

        if !isdefined(module_value, sym)
            continue
        end

        value = getfield(module_value, sym)
        if value isa Function
            push!(function_names, sym_text)
        end
    end

    unique!(function_names)
    sort!(function_names)
    return function_names
end

"""Resolve module docs for a help binding, falling back to canonical module binding."""
function resolve_module_doc_entry(binding::Base.Docs.Binding, module_value::Module)
    doc_meta = Base.Docs.meta(binding.mod)
    if haskey(doc_meta, binding)
        return doc_meta[binding]
    end

    canonical_binding = Base.Docs.Binding(parentmodule(module_value), nameof(module_value))
    canonical_meta = Base.Docs.meta(canonical_binding.mod)
    if haskey(canonical_meta, canonical_binding)
        return canonical_meta[canonical_binding]
    end

    module_binding = Base.Docs.Binding(module_value, nameof(module_value))
    module_meta = Base.Docs.meta(module_value)
    if haskey(module_meta, module_binding)
        return module_meta[module_binding]
    end

    return nothing
end

"""Append module docs plus available function names and lookup hint."""
function append_module_help!(
    session::ScratchpadSession,
    query::AbstractString,
    module_value::Module,
    binding::Base.Docs.Binding)
    doc_entry = resolve_module_doc_entry(binding, module_value)
    if doc_entry !== nothing
        rendered = render_help_docs(doc_entry)
        if rendered !== nothing && !isempty(rendered)
            append_output_block!(session, rendered)
            append_output_line!(session, "")
        end
    end

    function_names = list_module_function_names(module_value)
    append_output_line!(session, "Functions in $(query)")
    if isempty(function_names)
        append_output_line!(session, "(no public functions found)")
        return
    end

    append_output_block!(session, join(function_names, "\n"))
    append_output_line!(session, "")
    append_output_line!(session, "Lookup one by name with ?$(query).function_name")
end

"""Append binding docs and method signatures to scratchpad output."""
function append_binding_help!(session::ScratchpadSession, query::AbstractString, binding::Base.Docs.Binding)
    append_binding_help!(session, query, binding, nothing)
end

"""Append binding docs and either helper-facing signature or inferred method signatures."""
function append_binding_help!(
    session::ScratchpadSession,
    query::AbstractString,
    binding::Base.Docs.Binding,
    signature_override::Union{Nothing, String})
    doc_meta = Base.Docs.meta(binding.mod)
    if !haskey(doc_meta, binding)
        append_output_line!(session, "help error: no docs found for $(query)")
        return
    end

    rendered = render_help_docs(doc_meta[binding])
    if rendered === nothing || isempty(rendered)
        append_output_line!(session, "help error: docs for $(query) are empty")
        return
    end

    append_output_block!(session, rendered)

    signatures = signature_override
    if signatures === nothing
        signatures = render_help_signatures(binding)
    end

    if signatures !== nothing && !isempty(signatures)
        append_output_line!(session, "")
        append_output_line!(session, "Method Signatures")
        append_output_block!(session, signatures)
    end
end

"""Return true when value should be shown as struct field/property help in `?` mode."""
function should_render_struct_help(value)
    if value isa Module || value isa Function
        return false
    end
    if value isa DataType
        return isstructtype(value)
    end
    return isstructtype(typeof(value))
end

"""Render a compact multiline description of struct fields/properties for help output."""
function render_struct_properties_help(query::AbstractString, value)
    if value isa DataType
        struct_type = value
        field_lines = String[]
        for i in eachindex(fieldnames(struct_type))
            fname = fieldnames(struct_type)[i]
            ftype = fieldtype(struct_type, i)
            push!(field_lines, string(fname) * "::" * string(ftype))
        end

        if isempty(field_lines)
            return "Struct Fields for $(query)\n(no fields found)"
        end

        return "Struct Fields for $(query)\n" * join(field_lines, "\n")
    end

    struct_type = typeof(value)
    prop_lines = String[]
    for prop in propertynames(value)
        push!(prop_lines, string(prop))
    end

    if isempty(prop_lines)
        for i in eachindex(fieldnames(struct_type))
            fname = fieldnames(struct_type)[i]
            ftype = fieldtype(struct_type, i)
            push!(prop_lines, string(fname) * "::" * string(ftype))
        end
    end

    if isempty(prop_lines)
        return "Struct Properties for $(query)::$(struct_type)\n(no properties found)"
    end

    unique!(prop_lines)
    sort!(prop_lines)
    return "Struct Properties for $(query)::$(struct_type)\n" * join(prop_lines, "\n")
end

"""Resolve runtime helper aliases to documented Scratchpad bindings and helper signatures."""
function resolve_helper_doc_alias(query::AbstractString)
    helper_name = strip(String(query))
    if helper_name == "register_frame_hook"
        return (
            binding = Base.Docs.Binding(Scratchpad, :register_frame_hook),
            signature = "register_frame_hook(fn; label=\"\")",
        )
    end
    if helper_name == "remove_frame_hook"
        return (
            binding = Base.Docs.Binding(Scratchpad, :remove_frame_hook),
            signature = "remove_frame_hook(hook_id)",
        )
    end
    if helper_name == "clear_frame_hooks"
        return (
            binding = Base.Docs.Binding(Scratchpad, :clear_frame_hooks),
            signature = "clear_frame_hooks()",
        )
    end
    if helper_name == "list_frame_hooks"
        return (
            binding = Base.Docs.Binding(Scratchpad, :list_frame_hooks),
            signature = "list_frame_hooks()",
        )
    end
    if helper_name == "save_history"
        return (
            binding = Base.Docs.Binding(Scratchpad, :save_history_to_file),
            signature = "save_history(path)",
        )
    end
    if helper_name == "point!"
        return (
            binding = Base.Docs.Binding(Main.EuclidRepl, Symbol("point!")),
            signature = "point!(pos; color=:steelblue, brush=5f0, duration=5.5f0)",
        )
    end
    if helper_name == "line!"
        return (
            binding = Base.Docs.Binding(Main.EuclidRepl, Symbol("line!")),
            signature = "line!(start_pos, end_pos; color=:steelblue, brush=5f0, duration=7.5f0)",
        )
    end
    if helper_name == "circle!"
        return (
            binding = Base.Docs.Binding(Main.EuclidRepl, Symbol("circle!")),
            signature = "circle!(center, radius; color=:steelblue, brush=5f0, duration=8.0f0)",
        )
    end
    return nothing
end

"""Handle `?` scratchpad queries for modules and documented bindings."""
function handle_help_query!(session::ScratchpadSession, text::AbstractString)
    if isempty(text) || first(text) != '?'
        return false
    end

    query = strip(String(text[2:end]))
    if isempty(query)
        append_output_line!(session, "help error: expected a target after ?, for example ?OdinJuliaBridge.bridge_color")
        return true
    end

    helper_alias = resolve_helper_doc_alias(query)
    if helper_alias !== nothing
        append_binding_help!(session, query, helper_alias.binding, helper_alias.signature)
        return true
    end

    binding, err = resolve_help_binding(session.runtime, query)
    if binding === nothing
        append_output_line!(session, err)
        return true
    end

    if !isdefined(binding.mod, binding.var)
        append_output_line!(session, "help error: $(query) is not defined")
        return true
    end

    resolved_value = getfield(binding.mod, binding.var)
    if resolved_value isa Module
        append_module_help!(session, query, resolved_value, binding)
        return true
    end

    if should_render_struct_help(resolved_value)
        append_output_block!(session, render_struct_properties_help(query, resolved_value))
        return true
    end

    append_binding_help!(session, query, binding)

    return true
end

"""Handle scratchpad local commands prefixed with ':' and return handled status."""
function handle_local_command!(state_ptr::Ptr{Cvoid}, text::AbstractString)
    session = ensure_session!(state_ptr)
    session.metrics.local_commands += 1

    if text == ":help"
        append_help_lines!(session)
        return true
    end
    if text == ":clear"
        empty!(session.output)
        return true
    end
    if text == ":hooks"
        append_output_line!(session, list_frame_hooks(state_ptr))
        return true
    end
    if text == ":stats"
        for line in metrics_summary_lines(state_ptr)
            append_output_line!(session, line)
        end
        return true
    end
    if text == ":reset"
        new_session = reset_session!(state_ptr)
        append_output_line!(new_session, "Session reset by :reset")
        return true
    end

    return false
end

"""Return true when input should be treated as an explicit exit request."""
is_exit_command(text::AbstractString) = text in ("exit", "quit", "exit()", "quit()")

"""Handle parse-status side effects and return true when evaluation should stop."""
function handle_parse_status!(session::ScratchpadSession, status, parsed)
    if status == ParseIncomplete
        append_output_line!(session, "Input incomplete during execution")
        return true
    end
    if status == ParseError
        append_output_line!(session, parse_error_message(parsed))
        return true
    end

    return false
end

"""Evaluate one queued input line, including local commands, help mode, and safe eval."""
function evaluate_queued_input!(session::ScratchpadSession, state_ptr::Ptr{Cvoid}, text::String)
    stripped = strip(text)
    append_input_echo!(session, text)

    if handle_help_query!(session, stripped)
        return
    end

    if handle_local_command!(state_ptr, stripped)
        return
    end

    if is_exit_command(stripped)
        intercept_exit_or_quit(state_ptr)
        return
    end

    reason = blocked_input_reason(stripped)
    if reason !== nothing
        session.metrics.blocked_commands += 1
        append_output_line!(session, "Blocked by scratchpad safety policy: " * reason)
        return
    end

    status, parsed = classify_parse(text)
    if handle_parse_status!(session, status, parsed)
        return
    end

    runtime = session.runtime
    Core.eval(runtime, :(state_ptr = $state_ptr))

    scoped = apply_softscope(runtime, parsed)
    try
        result = Core.eval(runtime, scoped)
        if result !== nothing
            append_output_line!(session, "=> " * format_result_value(result))
        end
    catch e
        session.metrics.eval_errors += 1
        append_output_line!(session, "Error: " * format_exception_text(e, catch_backtrace()))
    end
end

    """Run enabled frame hooks once, tracking failures and auto-disabling unstable hooks."""
function run_frame_hooks!(session::ScratchpadSession, state_ptr::Ptr{Cvoid}, dt)
    if isempty(session.hooks)
        return
    end

    dt32 = try
        Float32(dt)
    catch
        Float32(0)
    end

    for hook in session.hooks
        if !hook.enabled
            continue
        end

        hook_started_at = time_ns()
        try
            hook.fn(state_ptr, dt32)
            hook.consecutive_failures = 0
            maybe_warn_slow_hook!(session, hook, time_ns() - hook_started_at)
        catch e
            hook.failures += 1
            hook.consecutive_failures += 1
            session.metrics.hook_errors += 1
            append_output_line!(
                session,
                "Frame $(frame_hook_label(hook.id, hook.label)) failed: " *
                format_exception_text(e, catch_backtrace()))
            if hook.consecutive_failures >= MaxConsecutiveHookFailures
                hook.enabled = false
                append_output_line!(
                    session,
                    "Disabled $(frame_hook_label(hook.id, hook.label)) after $(hook.consecutive_failures) consecutive failures")
            end
        end
    end
end

"""Return current scratchpad output as newline-delimited text for the UI panel."""
function get_view_text(state_ptr::Ptr{Cvoid})
    session = ensure_session!(state_ptr)
    _ = emit_dynview_output_stream!(state_ptr, session)
    if isempty(session.output)
        return ""
    end

    return join(session.output, "\n")
end

"""Initialize scratchpad session lifecycle and seed startup help text."""
function initialize(state_ptr::Ptr{Cvoid})
    initialize_count_ref[] += 1
    session = reset_session!(state_ptr)
    append_help_lines!(session)
end

"""Clean scratchpad lifecycle state when animation unloads."""
function clean(state_ptr::Ptr{Cvoid})
    clean_count_ref[] += 1
    session_ref[] = nothing

    if isdefined(Main, :EuclidRepl) && isdefined(Main.EuclidRepl, :reset_scratchpad_session!)
        Main.EuclidRepl.reset_scratchpad_session!()
    end
end

"""Per-frame scratchpad driver: dequeue/evaluate input and run frame hooks."""
function loop(state_ptr::Ptr{Cvoid}, dt)
    session = ensure_session!(state_ptr)
    try
        if !isempty(session.queue)
            text = popfirst!(session.queue)
            session.metrics.queue_dequeued += 1
            eval_started_at = time_ns()
            evaluate_queued_input!(session, state_ptr, text)
            maybe_warn_slow_eval!(session, time_ns() - eval_started_at)
        end

        run_frame_hooks!(session, state_ptr, dt)
    catch e
        append_output_line!(session, "Error: " * format_exception_text(e, catch_backtrace()))
    end
end

end
