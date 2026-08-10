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
function classify_input(
    state_ptr::Ptr{Cvoid}, text::String, input_mode::Int32=InputModeJulia)

    session = ensure_session!(state_ptr)

    if input_mode == InputModeHelp
        return ParseComplete
    end

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

"""Resolve a single unambiguous backslash completion, or return `""` when none applies."""
function complete_backslash(state_ptr::Ptr{Cvoid}, token::String)
    session = ensure_session!(state_ptr)

    if isempty(token) || first(token) != '\\'
        return ""
    end

    completions, completion_range, success = REPL.REPLCompletions.completions(
        token,
        lastindex(token),
        session.runtime)
    if !success || length(completions) != 1
        return ""
    end

    if first(completion_range) != firstindex(token) ||
        last(completion_range) != lastindex(token)
        return ""
    end

    completion = first(completions)
    if !(completion isa REPL.REPLCompletions.BslashCompletion)
        return ""
    end

    return String(getproperty(completion, :completion))
end

"""Return the text that should replace the completed range for one REPL completion item."""
function completion_text(item)
    if hasproperty(item, :completion)
        return String(getproperty(item, :completion))
    end
    if hasproperty(item, :mod)
        return String(getproperty(item, :mod))
    end
    return nothing
end

"""Return the longest shared prefix across completion replacement texts."""
function longest_completion_prefix(values::Vector{String})
    if isempty(values)
        return ""
    end

    prefix = first(values)
    for value in values
        limit = min(ncodeunits(prefix), ncodeunits(value))
        keep = 0
        for i in 1:limit
            if prefix[i] != value[i]
                break
            end
            keep = i
        end
        prefix = prefix[1:keep]
        if isempty(prefix)
            return ""
        end
    end
    return prefix
end

"""Encode a completion replacement as `start\nend\ntext` using Odin byte offsets."""
function encode_completion_result(start_byte::Int, end_byte::Int, replacement::AbstractString)
    return string(start_byte) * "\n" * string(end_byte) * "\n" * String(replacement)
end

"""Collect replacement strings for completion items and drop unsupported entry types."""
function completion_replacement_values(completions)
    values = String[]
    for item in completions
        replacement = completion_text(item)
        if replacement === nothing
            continue
        end
        push!(values, replacement)
    end
    return values
end

"""Return the current completion span text for the provided REPL completion range."""
function completion_range_text(text::String, completion_range)
    return text[first(completion_range):last(completion_range)]
end

"""Resolve replacement text from completion candidates, or return `nothing` when no change applies."""
function completion_replacement_text(text::String, completion_range, values::Vector{String})
    if isempty(values)
        return nothing
    end

    if length(values) == 1
        replacement = first(values)
        return replacement == completion_range_text(text, completion_range) ? nothing : replacement
    end

    current_text = completion_range_text(text, completion_range)
    common_prefix = longest_completion_prefix(values)
    if ncodeunits(common_prefix) <= ncodeunits(current_text)
        return nothing
    end
    return common_prefix
end

"""Resolve a generic scratchpad completion request from full input text and caret byte offset."""
function complete_input(
    state_ptr::Ptr{Cvoid},
    text::String,
    caret_byte::Int,
    input_mode::Int32=InputModeJulia)

    session = ensure_session!(state_ptr)
    if isempty(text) || caret_byte <= 0
        return ""
    end

    clamped_caret = clamp(caret_byte, 1, ncodeunits(text))
    _ = input_mode
    completions, completion_range, success = REPL.REPLCompletions.completions(
        text,
        clamped_caret,
        session.runtime)
    if !success || isempty(completions)
        return ""
    end

    replacement_values = completion_replacement_values(completions)
    replacement_text = completion_replacement_text(text, completion_range, replacement_values)
    if replacement_text === nothing
        return ""
    end

    start_byte = first(completion_range) - 1
    end_byte = last(completion_range)
    return encode_completion_result(start_byte, end_byte, replacement_text)
end

