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
        empty!(session.output_entries)
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

"""Return the Julia REPL-style source label for the current queued input."""
function repl_input_filename(session::ScratchpadSession)
    input_number = max(session.metrics.queue_dequeued, 1)
    return "REPL[$(input_number)]"
end

"""Evaluate one queued input line, including local commands, help mode, and safe eval."""
function evaluate_queued_input!(
    session::ScratchpadSession,
    state_ptr::Ptr{Cvoid},
    text::String,
    input_mode::Int32=InputModeJulia)

    stripped = strip(text)
    dispatched = stripped == "?" ? ":help" : stripped
    append_input_echo!(session, text, input_mode)

    if input_mode == InputModeHelp
        append_native_help_query!(session, stripped)
        return
    end

    if handle_help_query!(session, dispatched)
        return
    end

    if handle_local_command!(state_ptr, dispatched)
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

    repl_parsed = Base.parse_input_line(text; filename=repl_input_filename(session))
    scoped = apply_softscope(runtime, repl_parsed)
    try
        result = Core.eval(runtime, scoped)
        if result !== nothing
            append_eval_result_output!(session, result)
        end
    catch
        session.metrics.eval_errors += 1
        append_native_error_block!(session,
            format_current_exception_text(runtime; color=true))
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
        catch
            hook.failures += 1
            hook.consecutive_failures += 1
            session.metrics.hook_errors += 1
            append_native_error_block!(
                session,
                "Frame $(frame_hook_label(hook.id, hook.label)) failed:\n" *
                format_current_exception_text(session.runtime; color=true))
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

"""Prime Scratchpad parsing, completion, evaluation, formatting, and dynview emission."""
function prime_repl!(state_ptr::Ptr{Cvoid})
    warm_session = create_session(state_ptr, -1)
    SessionRef[] = warm_session
    try
        queue_input(state_ptr, "sum(1:3)") || return false
        complete_backslash(state_ptr, "\\alpha") == "α" || return false
        isempty(complete_input(state_ptr, "EuclidRep", 9)) && return false
        loop(state_ptr, 0f0)
        isempty(get_view_text(state_ptr)) && return false
        status = OdinJuliaBridge.dynview_reset_stream(state_ptr)
        return status == OdinJuliaBridge.BRIDGE_STATUS_OK
    finally
        SessionRef[] = create_session(state_ptr, NextSessionIdRef[])
    end
end

"""Initialize scratchpad session lifecycle and seed the Julia runtime banner."""
function initialize(state_ptr::Ptr{Cvoid})
    InitializeCountRef[] += 1
    session = ensure_session!(state_ptr)
    append_startup_banner!(session)
end

"""Clean scratchpad lifecycle state when animation unloads."""
"""Clean any extra animation data at the end of performance"""
function clean(state_ptr::Ptr{Cvoid})
    CleanCountRef[] += 1
    SessionRef[] = nothing

    if isdefined(Main, :EuclidRepl) &&
        isdefined(Main.EuclidRepl, :reset_scratchpad_session!)
        Main.EuclidRepl.reset_scratchpad_session!()
    end
end

"""Per-frame scratchpad driver: dequeue/evaluate input and run frame hooks."""
function loop(state_ptr::Ptr{Cvoid}, dt)
    session = ensure_session!(state_ptr)
    try
        if !isempty(session.queue)
            entry = popfirst!(session.queue)
            session.metrics.queue_dequeued += 1
            eval_started_at = time_ns()
            evaluate_queued_input!(session, state_ptr, entry.text, entry.mode)
            maybe_warn_slow_eval!(session, time_ns() - eval_started_at)
        end

        run_frame_hooks!(session, state_ptr, dt)
    catch
        append_native_error_block!(
            session, format_current_exception_text(session.runtime; color=true))
    end
end

