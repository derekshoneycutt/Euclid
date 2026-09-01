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
    catch e
        append_output_line!(session,
            "remove_frame_hook: invalid hook id ($(sprint(showerror, e)))")
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
    catch e
        e isa Exception || rethrow()
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
function history_previous(
    state_ptr::Ptr{Cvoid}, input_mode::Int32=InputModeJulia)

    session = ensure_session!(state_ptr)
    if isempty(session.history)
        return ""
    end

    if session.history_cursor == length(session.history) + 1
        session.history_origin_mode = input_mode
    end
    if session.history_cursor > 1
        session.history_cursor -= 1
    end
    entry = session.history[session.history_cursor]
    return string(entry.mode) * "\n" * entry.text
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
        return string(session.history_origin_mode) * "\n"
    end

    entry = session.history[session.history_cursor]
    return string(entry.mode) * "\n" * entry.text
end

"""
Save scratchpad input history to a newline-delimited file.

Returns `true` on success, otherwise `false` and appends an error line to output.
"""
function save_history_to_file(state_ptr::Ptr{Cvoid}, path)
    session = ensure_session!(state_ptr)

    file_path = try
        String(path)
    catch e
        append_output_line!(session,
            "save_history: invalid path ($(sprint(showerror, e)))")
        return false
    end

    if isempty(file_path)
        append_output_line!(session, "save_history: path is empty")
        return false
    end

    try
        open(file_path, "w") do io
            for entry in session.history
                write(io, entry.text)
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

"""Intercept an interactive exit/quit by resetting only the scratchpad session."""
function intercept_exit_or_quit(state_ptr::Ptr{Cvoid})
    session = reset_session!(state_ptr)
    append_output_line!(session, "exit()/quit() intercepted; scratchpad session reset")
    return nothing
end

"""
Queue one complete scratchpad input entry for one-per-frame execution.

Returns `true` if queued, `false` when parse state is not complete.
"""
function queue_input(
    state_ptr::Ptr{Cvoid}, text::String, input_mode::Int32=InputModeJulia,
    request_id::UInt64=UInt64(0))

    session = ensure_session!(state_ptr)

    stripped = strip(text)
    if input_mode == InputModeJulia && (isempty(stripped) || first(stripped) != '?')
        status, _ = classify_parse(text)
        if status != ParseComplete
            return false
        end
    end

    append_history_line!(session, text, input_mode)
    session.history_cursor = length(session.history) + 1
    queue_line!(session, text, input_mode, request_id)
    return true
end

